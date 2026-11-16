import SwiftUI

/// Keep the 20 Hz observation inside this leaf. Reading levels in ContentView
/// also invalidates its NavigationSplitView and native toolbar during resizing.
struct LiveRecordingView: View {
  let model: AppModel
  var faceplate = RecorderFaceplate()

  var body: some View {
    RecordingView(
      levels: model.recordingLevels, startedAt: model.recordingStarted,
      canOperate: !model.isBusy, onTransport: { model.stop() }
    )
    .faceplate(faceplate)
    .task {
      while !Task.isCancelled && model.isRecording {
        await model.refreshRecordingLevels()
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
      }
    }
  }
}

/// The recorder before capture. The opt-in microphone preview polls here for the
/// same reason live levels do: only this leaf redraws at meter rate.
struct ReadyRecorderView<SystemSource: View, Accessory: View>: View {
  @Bindable var model: AppModel
  var faceplate = RecorderFaceplate()
  @ViewBuilder let systemSource: SystemSource
  @ViewBuilder let accessory: Accessory

  private var previewing: Bool { model.previewsMicrophone && !model.isBusy && !model.isRecording }

  var body: some View {
    RecordingView(
      levels: RecordingLevels(microphone: model.previewLevel), isRecording: false,
      canOperate: model.canStart, onTransport: { model.start() },
      microphonePreview: $model.previewsMicrophone
    ) {
      systemSource
    } accessory: {
      accessory
    }
    .faceplate(faceplate)
    .task(id: previewing) {
      guard previewing else {
        model.stopMicrophonePreview()
        return
      }
      await model.startMicrophonePreview()
      while !Task.isCancelled {
        await model.refreshPreviewLevel()
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
      }
    }
    .onDisappear { model.stopMicrophonePreview() }
  }
}
