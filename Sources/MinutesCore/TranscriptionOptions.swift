import Foundation

public struct TranscriptionOptions: Codable, Equatable, Sendable {
  public enum Quality: String, Codable, CaseIterable, Sendable {
    case standard
    case thorough
  }
  public var quality: Quality
  /// System-track speakers only; the separate microphone is labelled You.
  public var expectedSystemSpeakers: Int?

  public init(quality: Quality = .thorough, expectedSystemSpeakers: Int? = nil) {
    self.quality = quality
    self.expectedSystemSpeakers = expectedSystemSpeakers
  }
}
