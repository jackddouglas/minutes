import AppKit
import MinutesCore
import SwiftUI

struct CalendarRecordingPrompt: View {
  @Bindable var model: AppModel
  let meeting: CalendarMeeting
  @Environment(\.dismiss) private var dismiss
  @ViewState private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text(meeting.title).font(.title2.bold()).textSelection(.enabled)
        Text(meeting.start, format: .dateTime.weekday().hour().minute()).foregroundStyle(.secondary)
      }
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          BrowserPicker(model: model)
          Divider()
          LabeledContent("Microphone", value: "System default")
        }.padding(8)
      }
      if model.isBusy { ProgressView(model.status).controlSize(.small) }
      if model.isRecording {
        Text("A recording is already in progress. Stop it before starting another.")
          .foregroundStyle(.secondary)
      }
      Text(
        "Records browser audio and your microphone. Use headphones to avoid echo."
      )
      .font(.callout).foregroundStyle(.secondary)
      if let message { Text(message).foregroundStyle(.red) }
      HStack {
        Button("Not Now", role: .cancel) {
          model.calendarMonitor.dismiss(meeting)
          dismiss()
        }.keyboardShortcut(.cancelAction)
        Button("Open Google Meet") { NSWorkspace.shared.open(meeting.url) }
        Spacer()
        Button("Start Recording") {
          model.calendarMonitor.refresh()
          guard model.calendarMonitor.upcoming.contains(where: { $0.id == meeting.id }),
            meeting.end > Date()
          else {
            message =
              "This event has ended or changed. Refresh Calendar to find the current meeting."
            return
          }
          model.title = meeting.title
          model.start()
          model.calendarMonitor.dismiss(meeting)
          dismiss()
        }.buttonStyle(.bordered).disabled(!model.canStart)
      }
    }.padding(24).frame(width: 500)
      .background(Color(nsColor: .windowBackgroundColor))
  }
}
