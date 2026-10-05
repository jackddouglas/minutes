import FluidAudio
import Foundation
import MinutesCore

actor TranscriptionService {
  let modelDirectory: URL = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Minutes/Models", isDirectory: true)

  private var speechModels: AsrModels?
  private var speakerModels: OfflineDiarizerModels?

  var isLoaded: Bool { speechModels != nil && speakerModels != nil }

  func unload() {
    speechModels = nil
    speakerModels = nil
  }

  func prepare(progress: @Sendable (String) async -> Void) async throws {
    do {
      if speechModels == nil {
        await progress("Loading transcription model…")
        speechModels = try await AsrModels.downloadAndLoad(to: modelDirectory, version: .v3)
      }
      if speakerModels == nil {
        await progress("Loading speaker model…")
        speakerModels = try await OfflineDiarizerModels.load(
          from: modelDirectory.appendingPathComponent("Diarization"))
      }
    } catch {
      unload()
      throw error
    }
  }

  func transcribe(
    _ tracks: AudioTracks, options: TranscriptionOptions = .init(),
    progress: @Sendable (String) async -> Void
  ) async throws
    -> [Utterance]
  {
    let diarizationConfig = try Self.diarizationConfig(options)
    try await prepare(progress: progress)
    guard let models = speechModels, let speakerModels else {
      throw MinutesError.message("Models could not load. Try again.")
    }
    let asr = AsrManager(config: .default)
    try await asr.loadModels(models)
    var utterances: [Utterance] = []
    if let remote = tracks.remote {
      await progress("Transcribing the meeting…")
      var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
      let result = try await asr.transcribe(remote, decoderState: &decoderState)
      let remoteWords = try words(result)
      if !remoteWords.isEmpty {
        await progress("Identifying voices in the meeting…")
        let diarizer = OfflineDiarizerManager(config: diarizationConfig)
        diarizer.initialize(models: speakerModels)
        let diarization = try await diarizer.process(remote)
        var labels: [String: String] = [:]
        let spans = diarization.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }.map {
          segment in
          if labels[segment.speakerId] == nil {
            labels[segment.speakerId] = "Speaker \(labels.count + 1)"
          }
          return SpeakerSpan(
            speaker: labels[segment.speakerId]!, start: Double(segment.startTimeSeconds),
            end: Double(segment.endTimeSeconds))
        }
        utterances += SpeakerAlignment.align(
          words: remoteWords, spans: spans, offset: tracks.remoteOffset)
      }
    }
    if let microphone = tracks.microphone {
      await progress("Transcribing your microphone…")
      var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
      let result = try await asr.transcribe(microphone, decoderState: &decoderState)
      utterances += SpeakerAlignment.align(
        words: try words(result), spans: [], offset: tracks.microphoneOffset, fixedSpeaker: "You")
    }
    return utterances.sorted { $0.start < $1.start }
  }

  static func diarizationConfig(_ options: TranscriptionOptions) throws -> OfflineDiarizerConfig {
    if let count = options.expectedSystemSpeakers, !(1...20).contains(count) {
      throw MinutesError.message("Expected system speakers must be between 1 and 20, or Automatic.")
    }
    var config = OfflineDiarizerConfig()
    if options.quality == .thorough {
      config.segmentation.stepRatio = 0.1
      config.embedding.minSegmentDurationSeconds = 0
    }
    config.clustering.numSpeakers = options.expectedSystemSpeakers
    // Recover speech that received no speaker votes instead of accepting the
    // diarizer's arbitrary first-cluster fallback. Preserve evidenced turns.
    config.zeroVoteReembed = .init(enabled: true, minDurationSeconds: 0.4)
    return config
  }

  private func words(_ result: ASRResult) throws -> [TimedWord] {
    guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
    guard let tokens = result.tokenTimings, !tokens.isEmpty else {
      throw MinutesError.message(
        "Transcription returned text without timestamps; speaker alignment could not be completed.")
    }
    return try WordTiming.words(tokens)
  }
}
