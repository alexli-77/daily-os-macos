import AppKit
import Foundation
import UserNotifications

/// 每晚 21:00：清理今天的 To-do。
///
/// A macOS notification, scheduled with the system rather than with a timer in
/// the app: a repeating calendar trigger is delivered by the system whether or
/// not Daily OS is running at nine, which a timer in a quit app never is. It
/// is fixed — every evening, the same time — because the habit is the point
/// (2026-10-26). The evening review runs at 21:30, after it.
///
/// Clicking it opens Daily OS on today. If the day is left uncleaned anyway,
/// the next morning's 清理 prompt catches it.
public enum CleanupReminder {
  public static let hour = 21
  public static let minute = 0
  static let identifier = "daily-os.cleanup.evening"

  /// Posted on the main queue when the notification is clicked.
  public static let openTodayNotification = Notification.Name("daily-os.cleanup.openToday")

  /// The center's delegate. Kept here because the center holds it weakly.
  @MainActor private static let delegate = Delegate()

  /// Ask for permission (once — macOS remembers the answer) and (re)schedule
  /// the evening reminder. Safe to call on every launch: the same identifier
  /// replaces the request instead of adding a second one.
  @MainActor
  public static func install() async {
    let center = UNUserNotificationCenter.current()
    center.delegate = delegate
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    guard granted else { return }
    let content = UNMutableNotificationContent()
    content.title = "该清理今天的 To-do 了"
    content.body = "每条标成 完成 / 部分 / 未做 / 推到明天。清完了，周报才算得准。"
    content.sound = .default
    var when = DateComponents()
    when.hour = hour
    when.minute = minute
    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
    )
    try? await center.add(request)
  }

  /// Whether the reminder is scheduled — for 设置 to say so, and for checks.
  public static func isScheduled() async -> Bool {
    let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
    return pending.contains { $0.identifier == identifier }
  }

  private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
    /// Shown even when Daily OS is in front: nine o'clock is the moment, not
    /// whenever the window next loses focus.
    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
      [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
      guard response.notification.request.identifier == CleanupReminder.identifier else { return }
      await MainActor.run {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: CleanupReminder.openTodayNotification, object: nil)
      }
    }
  }
}
