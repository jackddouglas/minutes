import MinutesCore
import SwiftUI

/// Analog meters in a native, appearance-aware recording surface. Before capture
/// begins it doubles as the new-meeting surface: the key starts recording and
/// each meter carries its source.
struct RecordingView<SystemSource: View, Accessory: View>: View {
  @Environment(\.colorScheme) private var colorScheme
  let levels: RecordingLevels
  var isRecording: Bool
  var startedAt: Date?
  var canOperate: Bool
  var onTransport: () -> Void
  var microphonePreview: Binding<Bool>?
  let systemSource: SystemSource
  let accessory: Accessory
  var faceplate = RecorderFaceplate()

  init(
    levels: RecordingLevels, isRecording: Bool = true, startedAt: Date? = nil,
    canOperate: Bool = true, onTransport: @escaping () -> Void = {},
    microphonePreview: Binding<Bool>? = nil,
    @ViewBuilder systemSource: () -> SystemSource,
    @ViewBuilder accessory: () -> Accessory = { EmptyView() }
  ) {
    self.levels = levels
    self.isRecording = isRecording
    self.startedAt = startedAt
    self.canOperate = canOperate
    self.onTransport = onTransport
    self.microphonePreview = microphonePreview
    self.systemSource = systemSource()
    self.accessory = accessory()
  }

  @Environment(\.recorderFitsContent) private var fitsContent

  func faceplate(_ faceplate: RecorderFaceplate) -> Self {
    var copy = self
    copy.faceplate = faceplate
    return copy
  }

  var body: some View {
    if fitsContent {
      // A floating panel sizes itself to the object and its shadow margin.
      VStack(spacing: 18) {
        instrument(compact: false, condensed: false).frame(width: 440)
        accessory
      }
      .padding(RecorderPanelPlacement.shadowInset)
    } else {
      fillingBody
    }
  }

  private var fillingBody: some View {
    GeometryReader { geometry in
      let condensed = geometry.size.height < 500
      let compact = geometry.size.width < 440 || condensed
      ScrollView {
        VStack(spacing: 18) {
          instrument(compact: compact, condensed: condensed)
            .frame(maxWidth: 500)
          accessory
        }
        .padding(compact ? 16 : 32)
        .frame(minHeight: geometry.size.height)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func instrument(compact: Bool, condensed: Bool) -> some View {
    VStack(spacing: 0) {
      if !condensed {
        HStack(spacing: 24) {
          MicrophoneGrille().frame(height: 42).accessibilityHidden(true)
          Circle().fill(RecorderFinish.orange.opacity(isRecording ? 1 : 0.22))
            .frame(width: 7, height: 7)
            .accessibilityLabel("Recording in progress")
            .accessibilityHidden(!isRecording)
        }
        .padding(.horizontal, 28).padding(.top, 24)
      }

      HStack(alignment: .top, spacing: compact ? 10 : 16) {
        RecordingMeter(
          title: "Microphone", level: levels.microphone, isRecording: isRecording,
          compact: compact, preview: isRecording ? nil : microphonePreview
        ) {
          Text("System default")
        }
        RecordingMeter(
          title: "System Audio", level: levels.system, isRecording: isRecording, compact: compact
        ) {
          systemSource
        }
        .help("Audio from the selected app")
      }
      .padding(.horizontal, compact ? 16 : 24)
      .padding(.vertical, 20)

      separator

      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          if let working = faceplate.working {
            Text(working.label).font(.system(size: 9, weight: .semibold)).tracking(1.4)
              .foregroundStyle(.secondary)
            Text(working.duration)
              .font(.system(size: compact ? 27 : 34, weight: .light, design: .monospaced))
              .tracking(-1.5)
              .accessibilityLabel("\(working.label.capitalized), \(working.duration) recorded")
          } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              Text(
                MarkdownExporter.timestamp(
                  isRecording ? context.date.timeIntervalSince(startedAt ?? context.date) : 0)
              )
              .font(.system(size: compact ? 27 : 34, weight: .light, design: .monospaced))
              .tracking(-1.5)
              .contentTransition(.identity)
              .opacity(isRecording ? 1 : 0.35)
            }
            .accessibilityLabel("Recording duration")
            .accessibilityHidden(!isRecording)
          }
        }
        Spacer(minLength: 0)
        if let speakers = faceplate.speakers {
          RecorderSpeakersCounter(count: speakers, isEnabled: faceplate.speakersEnabled)
        }
        VStack(spacing: 10) {
          Button(action: onTransport) {
            TransportKey(compact: compact, recording: isRecording)
              .contentShape(Circle())
          }
          .buttonStyle(TransportButtonStyle(compact: compact, recording: isRecording))
          .disabled(!canOperate)
          .keyboardShortcut(isRecording ? nil : .defaultAction)
          .accessibilityLabel(isRecording ? "Stop & Transcribe" : "Start Recording")
          .help(
            isRecording
              ? "Finish recording and transcribe this meeting"
              : "Record the selected app and your microphone")
        }
      }
      .padding(condensed ? 16 : (compact ? 20 : 24))
      if let tape = faceplate.tape {
        RecorderTapeView(tape: tape, onAction: faceplate.onTape)
          .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, -6)
      }
    }
    .foregroundStyle(.primary)
    .background {
      RoundedRectangle(cornerRadius: 20)
        .fill(
          LinearGradient(
            colors: colorScheme == .dark
              ? [
                Color(red: 0.24, green: 0.25, blue: 0.24),
                Color(red: 0.15, green: 0.16, blue: 0.15),
              ]
              : [RecorderFinish.ivory, RecorderFinish.lowerIvory],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 20)
            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.5), lineWidth: 0.5)
        }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
  }

  private var separator: some View {
    Divider().padding(.horizontal, 24)
  }
}

extension RecordingView where SystemSource == EmptyView, Accessory == EmptyView {
  init(
    levels: RecordingLevels, startedAt: Date? = nil, canOperate: Bool = true,
    onTransport: @escaping () -> Void = {}
  ) {
    self.init(
      levels: levels, startedAt: startedAt, canOperate: canOperate, onTransport: onTransport,
      systemSource: { EmptyView() })
  }
}

private struct RecorderFitsContentKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Lay the recorder out at its own size instead of filling its container.
  var recorderFitsContent: Bool {
    get { self[RecorderFitsContentKey.self] }
    set { self[RecorderFitsContentKey.self] = newValue }
  }
}

enum RecorderFinish {
  static let ivory = Color(red: 0.94, green: 0.935, blue: 0.905)
  static let lowerIvory = Color(red: 0.85, green: 0.85, blue: 0.815)
  static let ink = Color(red: 0.17, green: 0.18, blue: 0.17)
  static let secondaryInk = Color(red: 0.36, green: 0.37, blue: 0.34)
  static let orange = Color(red: 0.87, green: 0.24, blue: 0.08)
  static let alertInk = Color(red: 0.65, green: 0.18, blue: 0.06)
}

private struct RecordingMeter<Source: View>: View {
  let title: String
  let level: RecordingLevel
  let isRecording: Bool
  let compact: Bool
  var preview: Binding<Bool>? = nil
  @ViewBuilder let source: Source
  private static var statusDot: CGFloat { 4 }
  private static var statusGap: CGFloat { 4 }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let now = Date.now
    let receiving = level.isReceiving(at: now)
    let clipping = receiving && level.peak >= 0.99
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text(title).font(.system(size: compact ? 10 : 12, weight: .medium))
        if let preview {
          Spacer(minLength: 0)
          Toggle(isOn: preview) {
            Label("Preview Level", systemImage: "mic.and.signal.meter")
          }
          .toggleStyle(InstrumentSwitchStyle())
          .help(
            preview.wrappedValue
              ? "Stop previewing the microphone level"
              : "Preview the microphone level before recording")
        }
      }
      VUDial(amount: level.amount(at: now), compact: compact)
        .frame(height: compact ? 88 : 106)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level.amount(at: now))
      if isRecording {
        // Centred on the capitals; the reading below starts where the words do.
        HStack(alignment: .center, spacing: Self.statusGap) {
          Circle().fill(
            clipping
              ? RecorderFinish.orange
              : Color.primary.opacity(receiving && level.decibels > -50 ? 0.8 : 0.25)
          )
          .frame(width: Self.statusDot, height: Self.statusDot)
          .accessibilityHidden(true)
          Text(level.status(at: now))
            .font(.system(size: compact ? 9 : 10))
            .foregroundStyle(clipping ? Color.orange : Color.secondary)
        }
      } else {
        source
          .font(.system(size: compact ? 9 : 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text(receiving ? "\(Int(level.decibels)) dBFS" : "— dBFS")
        .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.top, -5)
        .padding(.leading, isRecording ? Self.statusDot + Self.statusGap : 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: isRecording ? .ignore : .contain)
    .accessibilityLabel(title)
    .accessibilityValue(
      isRecording || receiving
        ? "\(level.status(at: now)), \(receiving ? String(-Int(level.decibels)) + " decibels below full scale" : "no recent audio")"
        : ""
    )
  }
}

/// A small slide switch in the instrument's materials rather than a system control.
private struct InstrumentSwitchStyle: ToggleStyle {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 5) {
        configuration.label
          .labelStyle(.iconOnly)
          .symbolVariant(configuration.isOn ? .fill : .none)
          .font(.system(size: 13))
          .foregroundStyle(configuration.isOn ? .primary : .secondary)
        track(configuration)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }
    }
  }

  private func track(_ configuration: Configuration) -> some View {
    Capsule()
      .fill(Color.primary.opacity(configuration.isOn ? 0.72 : 0.14))
      .overlay(alignment: configuration.isOn ? .trailing : .leading) {
        Circle()
          .fill(colorScheme == .dark ? Color(white: 0.2) : RecorderFinish.ivory)
          .shadow(color: .black.opacity(0.3), radius: 0.6, y: 0.5)
          .padding(1.5)
      }
      .frame(width: 24, height: 13)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isOn)
  }
}

private struct VUDial: View {
  let amount: Double
  let compact: Bool

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let pivot = CGPoint(x: size.width / 2, y: size.height * 0.89)
      let radius = min((size.width / 2 - 11) / 0.82 - 9, size.height * 0.66)
      ZStack {
        RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.18))
        RoundedRectangle(cornerRadius: 4)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.83, green: 0.835, blue: 0.77),
                Color(red: 0.96, green: 0.955, blue: 0.88),
              ], startPoint: .top, endPoint: .bottom)
          )
          .padding(4)
          .shadow(color: .black.opacity(0.8), radius: 2, y: -1)
        Canvas { context, _ in
          func point(_ fraction: Double, _ distance: Double) -> CGPoint {
            let angle = (-55 + fraction * 110) * .pi / 180
            return CGPoint(x: pivot.x + sin(angle) * distance, y: pivot.y - cos(angle) * distance)
          }
          for tick in 0...30 {
            let fraction = Double(tick) / 30
            var path = Path()
            path.move(to: point(fraction, radius))
            path.addLine(to: point(fraction, radius - (tick.isMultiple(of: 5) ? 8 : 3.5)))
            context.stroke(
              path,
              with: .color(tick >= 27 ? RecorderFinish.orange : RecorderFinish.ink.opacity(0.85)),
              lineWidth: tick.isMultiple(of: 5) ? 1 : 0.6)
            if tick.isMultiple(of: compact ? 10 : 5) {
              context.draw(
                Text("\(-60 + tick * 2)").font(.system(size: compact ? 6 : 7, weight: .medium))
                  .foregroundColor(RecorderFinish.ink), at: point(fraction, radius + 9))
            }
          }
          var redZone = Path()
          for step in 90...100 {
            let position = point(Double(step) / 100, radius - 11)
            if step == 90 { redZone.move(to: position) } else { redZone.addLine(to: position) }
          }
          context.stroke(redZone, with: .color(RecorderFinish.orange), lineWidth: 1.5)
          context.draw(
            Text("LEVEL").font(.system(size: compact ? 6 : 7, weight: .medium)).tracking(1)
              .foregroundColor(RecorderFinish.secondaryInk),
            at: CGPoint(x: pivot.x, y: pivot.y - radius * 0.28))
          context.draw(
            Text("dBFS").font(.system(size: 5.5)).foregroundColor(RecorderFinish.secondaryInk),
            at: CGPoint(x: size.width - 20, y: size.height - 12))
        }
        Rectangle().fill(RecorderFinish.ink)
          .frame(width: 1, height: radius + 2)
          .offset(y: -(radius + 2) / 2)
          .rotationEffect(.degrees(-55 + amount * 110))
          .position(pivot)
          .shadow(color: .black.opacity(0.25), radius: 0.7, x: 1.5, y: 1)
        Circle().fill(RecorderFinish.ink).frame(width: 7, height: 7).position(pivot)
        // A restrained reflection and upper shadow locate the needle behind the cover.
        RoundedRectangle(cornerRadius: 4)
          .fill(
            LinearGradient(
              stops: [
                .init(color: .black.opacity(0.16), location: 0),
                .init(color: .clear, location: 0.16),
                .init(color: .white.opacity(0.08), location: 0.6),
                .init(color: .clear, location: 1),
              ], startPoint: .top, endPoint: .bottom)
          )
          .padding(4)
      }
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.4), lineWidth: 0.5)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.65), lineWidth: 0.5).offset(
          y: 0.5)
      }
    }
    .accessibilityHidden(true)
  }
}

private struct MicrophoneGrille: View {
  var body: some View {
    Canvas { context, size in
      let pitch: CGFloat = 7
      let columns = max(1, Int((size.width - 6) / pitch))
      let rows = max(1, Int((size.height - 6) / pitch))
      let startX = (size.width - CGFloat(columns - 1) * pitch) / 2
      let startY = (size.height - CGFloat(rows - 1) * pitch) / 2
      for row in 0..<rows {
        for column in 0..<columns {
          let hole = CGRect(
            x: startX + CGFloat(column) * pitch - 1.6, y: startY + CGFloat(row) * pitch - 1.6,
            width: 3.2, height: 3.2)
          // A lower bevel catches light; the upper lip shadows the cavity.
          context.fill(
            Path(ellipseIn: hole.offsetBy(dx: 0, dy: 0.65).insetBy(dx: -0.55, dy: -0.55)),
            with: .color(.white.opacity(0.55)))
          context.fill(
            Path(ellipseIn: hole.insetBy(dx: -0.35, dy: -0.35)),
            with: .linearGradient(
              Gradient(colors: [.black.opacity(0.55), .black.opacity(0.16)]),
              startPoint: CGPoint(x: hole.midX, y: hole.minY - 0.35),
              endPoint: CGPoint(x: hole.midX, y: hole.maxY + 0.35)))
          context.fill(
            Path(ellipseIn: hole),
            with: .linearGradient(
              Gradient(colors: [Color(white: 0.035), Color(white: 0.18)]),
              startPoint: CGPoint(x: hole.midX, y: hole.minY),
              endPoint: CGPoint(x: hole.midX, y: hole.maxY)))
          context.fill(
            Path(ellipseIn: hole.insetBy(dx: 0.6, dy: 0.6).offsetBy(dx: 0, dy: -0.35)),
            with: .color(.black.opacity(0.55)))
        }
      }
    }
  }
}

private struct TransportKey: View {
  let compact: Bool
  var recording = true
  var pressed = false
  var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      // The bezel stays anchored while the face compresses into its well.
      Circle().fill(Color(white: 0.22))
      Circle().fill(
        LinearGradient(
          colors: [Color(white: 0.55), Color(white: 0.92)], startPoint: .top, endPoint: .bottom)
      ).padding(1)
      Circle().fill(RecorderFinish.ink).padding(3)
      ZStack {
        Circle().fill(
          LinearGradient(
            colors: [Color(red: 0.965, green: 0.96, blue: 0.93), RecorderFinish.lowerIvory],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        Circle().strokeBorder(.white.opacity(0.65), lineWidth: 0.7).padding(1)
        // Record is a dot; once capture runs the same key becomes stop.
        RoundedRectangle(cornerRadius: recording ? 2 : (compact ? 8 : 9.5))
          .fill(RecorderFinish.orange)
          .frame(width: compact ? 16 : 19, height: compact ? 16 : 19)
      }
      .overlay {
        Circle()
          .strokeBorder(
            LinearGradient(
              colors: [.black.opacity(pressed ? 0.28 : (hovering ? 0.14 : 0)), .clear],
              startPoint: .top, endPoint: .bottom), lineWidth: pressed ? 2 : 1)
      }
      .padding(5)
      .shadow(
        color: .black.opacity(pressed ? 0.1 : 0.28), radius: pressed ? 0.3 : 1, y: pressed ? 0 : 1
      )
      .brightness(pressed ? -0.07 : (hovering ? -0.025 : 0))
      .scaleEffect(reduceMotion ? 1 : (pressed ? 0.96 : (hovering ? 0.985 : 1)))
      .offset(y: reduceMotion ? 0 : (pressed ? 0.5 : 0))
      .clipShape(Circle().inset(by: 3))
    }
    .frame(width: compact ? 58 : 70, height: compact ? 58 : 70)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
  }
}

private struct TransportButtonStyle: ButtonStyle {
  let compact: Bool
  let recording: Bool
  func makeBody(configuration: Configuration) -> some View {
    TransportButtonBody(compact: compact, recording: recording, pressed: configuration.isPressed)
  }
}

private struct TransportButtonBody: View {
  let compact: Bool
  let recording: Bool
  let pressed: Bool
  @State private var hovering = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    TransportKey(
      compact: compact, recording: recording, pressed: pressed && isEnabled,
      hovering: hovering && isEnabled
    )
    .contentShape(Circle())
    .opacity(isEnabled ? 1 : 0.5)
    .onHover { hovering = $0 }
  }
}
