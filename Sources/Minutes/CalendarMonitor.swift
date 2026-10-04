import AppKit
import EventKit
import MinutesCore
import Observation
import UserNotifications

struct MonitoredCalendar: Identifiable {
  let id: String
  let title: String
  let source: String
  let color: CGColor
}

@MainActor @Observable
final class CalendarMonitor: NSObject, UNUserNotificationCenterDelegate {
  private(set) var calendars: [MonitoredCalendar] = []
  private(set) var selectedCalendarIDs: Set<String>
  private(set) var enabled: Bool
  private(set) var requestingAccess = false
  private(set) var notificationsAllowed = false
  private(set) var status = "Connect Calendar to get recording reminders."
  private(set) var upcoming: [CalendarMeeting] = []
  var invitations: [CalendarMeeting] = []
  var onOpen: ((CalendarMeeting) -> Void)?
  private let store = EKEventStore()
  private let preferences: UserDefaults
  private var task: Task<Void, Never>?
  private var seen: [String: Double]
  private var center: UNUserNotificationCenter { .current() }

  init(preferences: UserDefaults = .standard) {
    self.preferences = preferences
    selectedCalendarIDs = Set(preferences.stringArray(forKey: "selectedCalendarIDs") ?? [])
    enabled = preferences.bool(forKey: "calendarDetectionEnabled")
    seen = preferences.dictionary(forKey: "calendarMeetingsNotified") as? [String: Double] ?? [:]
    super.init()
  }

  func startMonitoring() {
    center.delegate = self
    Task {
      let settings = await center.notificationSettings()
      notificationsAllowed = settings.authorizationStatus == .authorized
    }
    let review = UNNotificationAction(
      identifier: "review", title: "Review Recording…", options: .foreground)
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "meeting", actions: [review], intentIdentifiers: [])
    ])
    guard task == nil else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        self?.refresh()
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
      }
    }
  }

  func setEnabled(_ value: Bool) {
    guard !requestingAccess else { return }
    if !value {
      enabled = false
      preferences.set(false, forKey: "calendarDetectionEnabled")
      upcoming = []
      invitations = []
      center.removeAllDeliveredNotifications()
      status = "Calendar reminders are off."
      return
    }
    requestingAccess = true
    Task {
      defer { requestingAccess = false }
      do {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
          status =
            "Calendar access is off. Allow Minutes in System Settings → Privacy & Security → Calendars, then try again."
          return
        }
        enabled = true
        preferences.set(true, forKey: "calendarDetectionEnabled")
        let notifications = try await center.requestAuthorization(options: [.alert, .sound])
        notificationsAllowed = notifications
        preferences.set(notifications, forKey: "calendarNotificationsAllowed")
        startMonitoring()
        refresh()
      } catch {
        status = "Could not enable reminders. Try again in Settings. \(error.localizedDescription)"
      }
    }
  }

  func setCalendar(_ id: String, selected: Bool) {
    if selected { selectedCalendarIDs.insert(id) } else { selectedCalendarIDs.remove(id) }
    preferences.set(selectedCalendarIDs.sorted(), forKey: "selectedCalendarIDs")
    if enabled {
      center.removeAllDeliveredNotifications()
      refresh()
    }
  }

  func refresh(now: Date = Date()) {
    guard enabled else { return }
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      calendars = []
      upcoming = []
      invitations = []
      status =
        "Calendar access is unavailable. Allow Minutes in System Settings → Privacy & Security → Calendars."
      return
    }
    let available = store.calendars(for: .event)
    calendars = available.map {
      MonitoredCalendar(
        id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, color: $0.cgColor)
    }.sorted { ($0.source, $0.title, $0.id) < ($1.source, $1.title, $1.id) }
    let selected = available.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
    // Never query EventKit with an empty calendar filter: no selection means no monitoring.
    guard !selected.isEmpty else {
      upcoming = []
      invitations = []
      status = "Choose calendars to receive meeting reminders."
      return
    }
    let predicate = store.predicateForEvents(
      withStart: now.addingTimeInterval(-600),
      end: now.addingTimeInterval(86_400), calendars: selected)
    upcoming = store.events(matching: predicate).compactMap { event in
      guard !event.isAllDay, event.status != .canceled, event.endDate > now,
        !(event.attendees ?? []).contains(where: {
          $0.isCurrentUser && $0.participantStatus == .declined
        }),
        let url = CalendarMeeting.googleMeetURL(in: [
          event.url?.absoluteString ?? "", event.location ?? "", event.notes ?? "",
        ])
      else { return nil }
      return CalendarMeeting(
        eventID: event.eventIdentifier ?? event.calendarItemIdentifier,
        title: event.title ?? "Google Meet", start: event.startDate, end: event.endDate, url: url)
    }.sorted { $0.start < $1.start }
    // Reconcile cancellations/edits before the user accepts an invitation.
    let valid = Set(upcoming.map(\.id))
    invitations.removeAll { !valid.contains($0.id) || $0.end <= now }
    invitations = invitations.compactMap { invitation in upcoming.first { $0.id == invitation.id } }
    var ledger = CalendarReminderLedger(notified: seen)
    for meeting in ledger.claimDue(upcoming, at: now) {
      invitations.append(meeting)
      if !NSApp.isActive { notify(meeting) }
    }
    seen = ledger.notified
    preferences.set(seen, forKey: "calendarMeetingsNotified")
    status =
      upcoming.isEmpty
      ? "No Google Meet meetings in the next 24 hours."
      : "Watching \(upcoming.count) Google Meet meeting\(upcoming.count == 1 ? "" : "s") in the next 24 hours."
  }

  func dismiss(_ meeting: CalendarMeeting) {
    invitations.removeAll { $0.id == meeting.id }
    center.removeDeliveredNotifications(withIdentifiers: [meeting.id])
  }

  private func notify(_ meeting: CalendarMeeting) {
    let content = UNMutableNotificationContent()
    content.title = "Meeting starting"
    content.body = "\(meeting.title) — would you like to record?"
    content.categoryIdentifier = "meeting"
    content.sound = .default
    content.userInfo = ["meetingID": meeting.id]
    Task {
      do {
        try await center.add(
          UNNotificationRequest(identifier: meeting.id, content: content, trigger: nil))
      } catch {
        status = "Notifications are unavailable. Recording prompts still appear in Minutes."
      }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let id = response.notification.request.identifier
    await MainActor.run {
      self.refresh()
      if let meeting = self.upcoming.first(where: { $0.id == id && $0.isDue(at: Date()) }) {
        NSApp.activate(ignoringOtherApps: true)
        self.onOpen?(meeting)
      }
    }
  }
}
