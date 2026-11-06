import Foundation

/// 提醒卡 / 便签墙 (LEO-355).
///
/// A small jotting with no deadline — a todo, an idea — that you want to be
/// reminded of now and then without being nagged. Instead of alerting on a date,
/// each note resurfaces on its own schedule: the service decides which notes
/// "float up" today and sends `surfacing` already resolved, the same division of
/// labour the countdown uses for its day counts. What this type owns is how a
/// note reads and which board it belongs to, both of which are presentation.
public struct Sticky: Identifiable, Sendable, Hashable {
  /// The paper colour. Purely visual — it never affects which notes surface,
  /// only how fast one is to find on the wall.
  public enum Color: String, Sendable, CaseIterable, Identifiable {
    case yellow
    case pink
    case blue
    case green
    case gray

    public var id: String { rawValue }

    public var label: String {
      switch self {
      case .yellow: "黄"
      case .pink: "粉"
      case .blue: "蓝"
      case .green: "绿"
      case .gray: "灰"
      }
    }
  }

  public let id: String
  public var text: String
  public var color: Color
  /// 0…4, the Leitner box: how far apart this note's wake-ups have grown.
  public var box: Int
  /// `YYYY-MM-DD` in the user's zone — the day this note next floats up.
  public var nextSurface: String
  /// Resolved by the service: true when `nextSurface` has arrived and the note
  /// is at the top of the wall today.
  public var surfacing: Bool

  public init(
    id: String,
    text: String,
    color: Color = .yellow,
    box: Int = 0,
    nextSurface: String,
    surfacing: Bool = false
  ) {
    self.id = id
    self.text = text
    self.color = color
    self.box = box
    self.nextSurface = nextSurface
    self.surfacing = surfacing
  }
}

/// What the user said when a surfaced note came up.
///
/// `done` archives it; `keep` ("还惦记") drops it to the shortest interval so it
/// comes back soon; `ok` ("知道了") promotes it a box so it sleeps longer.
public enum SurfaceResponse: String, Sendable {
  case done
  case keep
  case ok
}

/// What the editor sheet sends back. `id == nil` means create.
///
/// `Identifiable` with a `String?` id so the one sheet presents for both create
/// and edit — `nil` is as valid an identity as any saved note's.
public struct StickyDraft: Sendable, Equatable, Identifiable {
  public var id: String?
  public var text: String
  public var color: Sticky.Color

  public init(id: String? = nil, text: String = "", color: Sticky.Color = .yellow) {
    self.id = id
    self.text = text
    self.color = color
  }

  public init(editing item: Sticky) {
    self.init(id: item.id, text: item.text, color: item.color)
  }

  public var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension Sticky {
  /// Split the wall into what is awake today and what is still sleeping. Order
  /// inside each band is left as the service gave it — it already sorted by how
  /// overdue / how soon-to-wake each note is, and re-sorting here would be a
  /// second opinion about something that is not this side's to decide.
  public static func partition(_ items: [Sticky]) -> (surfacing: [Sticky], sleeping: [Sticky]) {
    (items.filter(\.surfacing), items.filter { !$0.surfacing })
  }
}
