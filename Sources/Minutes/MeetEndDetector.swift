import Foundation

struct CallStreams: Equatable {
  let input: Bool
  let output: Bool
}

/// One reminder per uninterrupted quiet stretch, after observing call input.
struct MeetEndDetector {
  static let delaySeconds = 5

  enum Action: Equatable {
    case withdraw, stop, show(UUID)
  }

  func action(automaticallyStop: Bool, displayed: UUID?) -> Action? {
    if automaticallyStop, quietSince != nil, !keptRecording { return .stop }
    if let reminderID {
      return reminderID == displayed ? nil : .show(reminderID)
    }
    return displayed == nil ? nil : .withdraw
  }

  private var heardInput = false
  private var quietSince: TimeInterval?
  private var lastSample: TimeInterval?
  private var keptRecording = false
  private(set) var reminderID: UUID?

  mutating func observe(_ streams: CallStreams?, at now: TimeInterval) {
    guard let streams else {
      self = Self()
      return
    }
    if let lastSample, now - lastSample > 2 {
      // Sleep or a delayed poll cannot establish continuous inactivity.
      quietSince = nil
      reminderID = nil
    }
    lastSample = now
    if streams.input { heardInput = true }
    if streams.input || streams.output {
      quietSince = nil
      keptRecording = false
      reminderID = nil
    } else if heardInput && !keptRecording {
      let start = quietSince ?? now
      quietSince = start
      if reminderID == nil && now - start >= Double(Self.delaySeconds) { reminderID = UUID() }
    }
  }

  mutating func keepRecording() {
    keptRecording = true
    reminderID = nil
  }
}
