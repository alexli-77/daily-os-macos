import Foundation

/// Who is signed in to the console account store.
///
/// Three different identities exist in this product and confusing them is how
/// the sidebar ended up showing `leon` — a *team member id* — as if it were the
/// logged-in user:
///
/// 1. **The console account** (`admin`), in the service's SQLite `users` table.
///    Username, password, role. This is what a person means by "my account".
/// 2. **The team member** (`leon`), an id in the cycle sync. It says whose files
///    these are, not who is operating the app.
/// 3. **The Supabase session** (`大汪汪`), which is team sync's own login.
///
/// This type is (1), and only (1).
public struct ConsoleSession: Sendable, Equatable {
  public let username: String
  public let role: Role
  /// Empty unless the account carries one.
  public let email: String
  public let avatarSeed: String

  public init(username: String, role: Role, email: String = "", avatarSeed: String = "") {
    self.username = username
    self.role = role
    self.email = email
    self.avatarSeed = avatarSeed
  }
}

/// What the weather strip draws.
///
/// A snapshot rather than a forecast: this is decoration with one job — to make
/// the top of Today feel like a morning — and a full forecast would be a second
/// screen's worth of data for a strip two centimetres tall.
public struct WeatherSnapshot: Sendable, Equatable {
  /// WMO weather code, as Open-Meteo reports it. Kept raw so the mapping to a
  /// drawing lives in the view and not in the decoder.
  public let code: Int
  public let temperatureC: Double
  public let high: Double
  public let low: Double
  public let isDay: Bool
  public let place: String
  public let fetchedAt: Date

  public init(code: Int, temperatureC: Double, high: Double, low: Double, isDay: Bool, place: String, fetchedAt: Date) {
    self.code = code
    self.temperatureC = temperatureC
    self.high = high
    self.low = low
    self.isDay = isDay
    self.place = place
    self.fetchedAt = fetchedAt
  }

  /// Morning, afternoon, evening — the three times a day this refreshes.
  ///
  /// A fixed interval would drift into refreshing at 3am and never at 8am. The
  /// user asked for three captures a day and those three are the ones a day
  /// actually has.
  public enum Slot: Int, Sendable, CaseIterable {
    case morning, afternoon, evening

    public static func current(_ date: Date = .now, calendar: Calendar = .current) -> Slot {
      switch calendar.component(.hour, from: date) {
      case ..<12: .morning
      case ..<18: .afternoon
      default: .evening
      }
    }
  }

  /// Whether this snapshot belongs to the current slot of the current day.
  public func isFresh(at date: Date = .now, calendar: Calendar = .current) -> Bool {
    calendar.isDate(fetchedAt, inSameDayAs: date)
      && Slot.current(fetchedAt, calendar: calendar) == Slot.current(date, calendar: calendar)
  }
}

/// The optional knobs on "create the next cycle".
///
/// Every field is optional and `nil` means "decide for me". The service fills a
/// blank from the previous cycle — length from its length, start from the day
/// after it ended — because that is what someone who left the box empty meant,
/// and a hard-coded 14 days would quietly be wrong for anyone alternating
/// weekly and biweekly cycles, which this vault does.
public struct NewCycleRequest: Sendable, Equatable {
  public var days: Int?
  public var taskCount: Int?
  /// Free text the planner is told about — a trip, a deadline, a week off.
  public var note: String?

  public init(days: Int? = nil, taskCount: Int? = nil, note: String? = nil) {
    self.days = days
    self.taskCount = taskCount
    self.note = note
  }

  public var isDefault: Bool { days == nil && taskCount == nil && (note ?? "").isEmpty }
}
