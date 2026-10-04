import MinutesCore
import SwiftUI

struct SpeakerReviewView: View {
  @Bindable var model: AppModel
  let meetingID: UUID
  @Environment(\.dismiss) private var dismiss
  @ViewState private var skipped: Set<UUID> = []
  @ViewState private var assignWholeSpeaker = false

  private var meeting: Meeting? { model.meetings.first { $0.id == meetingID } }
  private var unresolved: [Utterance] { meeting?.passagesNeedingSpeakerReview ?? [] }
  private var current: Utterance? { unresolved.first { !skipped.contains($0.id) } }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label("Review Speakers", systemImage: "person.crop.circle.badge.questionmark").font(
          .title2.bold())
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      if let meeting, let passage = current {
        HStack {
          Text(
            unresolved.count == 1
              ? "1 passage needs a name" : "\(unresolved.count) passages need names"
          )
          .foregroundStyle(.secondary)
          Spacer()
          Text("\(passage.speaker) · \(MarkdownExporter.timestamp(passage.start))")
            .monospacedDigit()
        }
        ScrollView {
          Text(passage.text).font(.title3).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        ReviewPlaybackControls(model: model, meeting: meeting, passage: passage)
          .padding(12).controlSurface()
        Divider()
        if passage.speaker == "Unassigned" {
          Text("Assign this passage only. Other unassigned passages may be different people.")
            .font(.callout).foregroundStyle(.secondary)
        } else {
          Toggle("Assign all \(passage.speaker) passages", isOn: $assignWholeSpeaker)
          Text("Individual passage corrections are kept when assigning a whole speaker.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text("Choose a person to save and play the next passage.").font(.callout)
        if model.savedSpeakers.isEmpty {
          Text("Add people in Settings → Saved Speakers, then return here to review.")
            .foregroundStyle(.secondary)
        } else {
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 10) {
              ForEach(model.savedSpeakers, id: \.self) { name in
                Button(name) {
                  if assignWholeSpeaker && passage.speaker != "Unassigned" {
                    model.renameSpeaker(passage.speaker, to: name, in: meeting)
                  } else {
                    model.assignPassage(passage.id, to: name, in: meeting)
                  }
                }
                .buttonStyle(.bordered).controlSize(.large)
                .frame(maxWidth: .infinity)
              }
            }
          }.frame(height: 100)
        }
        HStack {
          Text("\(unresolved.filter { skipped.contains($0.id) }.count) skipped")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Skip for Now") { skipped.insert(passage.id) }
        }
      } else {
        ContentUnavailableView {
          Label(
            unresolved.isEmpty ? "All speakers named" : "Remaining passages skipped",
            systemImage: "person.crop.circle.badge.checkmark")
        } description: {
          Text(
            unresolved.isEmpty
              ? "Your assignments have been saved to the transcript."
              : (unresolved.count == 1
                ? "1 passage still needs a name."
                : "\(unresolved.count) passages still need names."))
        } actions: {
          if !unresolved.isEmpty {
            Button("Review Skipped Passages") { skipped.removeAll() }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let error = model.error {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
    }
    .padding(24).frame(width: 640, height: 620)
    .task(id: current?.id) {
      model.playback.pause()
      assignWholeSpeaker = false
      if let meeting, let current { playPassage(meeting, current) }
    }
    .onDisappear { model.playback.pause() }
  }

  private func playPassage(_ meeting: Meeting, _ passage: Utterance) {
    model.play(
      meeting, from: max(0, passage.start - 0.5),
      until: max(passage.end + 0.5, passage.start + 2))
  }
}

// Keep playback clock updates out of the review queue and assignment controls.
private struct ReviewPlaybackControls: View {
  let model: AppModel
  let meeting: Meeting
  let passage: Utterance

  var body: some View {
    HStack {
      Button(
        model.playback.isPlaying ? "Pause" : "Play",
        systemImage:
          model.playback.isPlaying ? "pause.fill" : "play.fill"
      ) {
        if model.playback.isPlaying {
          model.playback.pause()
        } else {
          let end = max(passage.end + 0.5, passage.start + 2)
          let position = model.playback.position
          model.play(
            meeting,
            from: position >= max(0, passage.start - 0.5) && position < end
              ? position : max(0, passage.start - 0.5), until: end)
        }
      }.keyboardShortcut(.space, modifiers: [])
      Button("Replay", systemImage: "arrow.counterclockwise") {
        model.play(
          meeting, from: max(0, passage.start - 0.5),
          until: max(passage.end + 0.5, passage.start + 2))
      }
      Text(MarkdownExporter.timestamp(model.playback.position)).monospacedDigit()
        .foregroundStyle(.secondary)
      Spacer()
      Text("Plays automatically and stops after this passage.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
