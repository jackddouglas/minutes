import MinutesCore
import Testing

@testable import Minutes

@Test func transcriptNoticeNamesTheMeetingLengthAndVoices() {
  var meeting = Meeting(title: "Water Cooler Time", duration: 3966)
  meeting.utterances = ["You", "Speaker 1", "Speaker 1", "Speaker 2"].enumerated().map {
    Utterance(speaker: $1, start: Double($0), end: Double($0) + 1, text: "Hello")
  }
  let notice = TranscriptReadyNotice(meeting: meeting)
  #expect(notice.title == "Water Cooler Time is ready")
  #expect(notice.body == "1:06:06 · 3 speakers")
}

@Test func transcriptNoticeHandlesOneVoiceSilenceAndAnUnnamedMeeting() {
  var single = Meeting(title: "Standup", duration: 95)
  single.utterances = [Utterance(speaker: "You", start: 0, end: 1, text: "Hi")]
  #expect(TranscriptReadyNotice(meeting: single).body == "01:35 · 1 speaker")
  let silent = Meeting(title: "  ", duration: 12)
  #expect(TranscriptReadyNotice(meeting: silent).title == "\(Meeting.untitled) is ready")
  #expect(TranscriptReadyNotice(meeting: silent).body == "00:12 · No speech")
}
