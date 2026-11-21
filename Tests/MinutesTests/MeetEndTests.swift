import Testing

@testable import Minutes

private let speaking = CallStreams(input: true, output: true)
private let quiet = CallStreams(input: false, output: false)

@Test func meetEndRequiresInputAndFiveConsecutiveSeconds() {
  var detector = MeetEndDetector()
  for t in 0...40 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID == nil)
  detector.observe(speaking, at: 41)
  for t in 42...46 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID == nil)
  detector.observe(quiet, at: 47)
  #expect(detector.reminderID != nil)
  detector.keepRecording()
  #expect(detector.action(automaticallyStop: true, displayed: nil) == nil)
  for t in 48...87 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID == nil)
}

@Test(arguments: [CallStreams(input: true, output: false), CallStreams(input: false, output: true)])
func meetEndResumedStreamWithdrawsAndRearms(_ resumed: CallStreams) {
  var detector = MeetEndDetector()
  detector.observe(speaking, at: 0)
  for t in 1...5 { detector.observe(quiet, at: Double(t)) }
  detector.observe(resumed, at: 6)
  for t in 7...11 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID == nil)
  detector.observe(quiet, at: 12)
  let first = detector.reminderID
  #expect(first != nil)
  detector.observe(resumed, at: 13)
  #expect(detector.reminderID == nil)
  for t in 14...19 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID != nil && detector.reminderID != first)
}

@Test func meetEndRejectsMissingSamples() {
  var detector = MeetEndDetector()
  detector.observe(speaking, at: 0)
  detector.observe(quiet, at: 1)
  detector.observe(quiet, at: 40)
  #expect(detector.reminderID == nil)
  detector.observe(nil, at: 41)
  for t in 42...80 { detector.observe(quiet, at: Double(t)) }
  #expect(detector.reminderID == nil)
}

@Test func automaticStopUsesFirstInactiveSample() {
  var detector = MeetEndDetector()
  detector.observe(quiet, at: 0)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == nil)
  detector.observe(CallStreams(input: true, output: false), at: 1)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == nil)
  detector.observe(CallStreams(input: false, output: true), at: 2)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == nil)
  detector.observe(quiet, at: 3)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == .stop)
  #expect(detector.action(automaticallyStop: false, displayed: nil) == nil)
  detector.observe(nil, at: 4)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == nil)
}

@Test func automaticStopTakesEffectEvenAfterReminderWasDelivered() throws {
  var detector = MeetEndDetector()
  detector.observe(speaking, at: 0)
  for t in 1...6 { detector.observe(quiet, at: Double(t)) }
  let id = try #require(detector.reminderID)
  #expect(detector.action(automaticallyStop: false, displayed: nil) == .show(id))
  #expect(detector.action(automaticallyStop: false, displayed: id) == nil)
  #expect(detector.action(automaticallyStop: true, displayed: id) == .stop)
  #expect(detector.action(automaticallyStop: true, displayed: nil) == .stop)
  detector.observe(speaking, at: 7)
  #expect(detector.action(automaticallyStop: true, displayed: id) == .withdraw)
}
