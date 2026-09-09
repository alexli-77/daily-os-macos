import SwiftUI

/// A deterministic 5×5 pixel identicon.
///
/// This is a straight port of `src/ui/avatar.ts` in the daily-os service, hash
/// function and PRNG included, so an account draws the *same* avatar on the Mac,
/// on the phone and in the browser. That only holds if the arithmetic matches
/// exactly — hence FNV-1a and mulberry32 reproduced verbatim rather than
/// replaced with something more Swift-ish. `daily-os-checks` pins the output.
public struct PixelAvatar: View {
  private let seed: String
  private let size: CGFloat

  public init(seed: String, size: CGFloat = 28) {
    self.seed = seed.isEmpty ? "daily-os" : seed
    self.size = size
  }

  public var body: some View {
    let art = PixelAvatarArt(seed: seed)
    Canvas(rendersAsynchronously: false) { context, canvasSize in
      let unit = min(canvasSize.width, canvasSize.height) / CGFloat(PixelAvatarArt.grid)
      context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(art.background))
      for cell in art.litCells {
        let rect = CGRect(
          x: CGFloat(cell.x) * unit,
          y: CGFloat(cell.y) * unit,
          width: unit,
          height: unit
        )
        context.fill(Path(rect), with: .color(art.foreground))
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
    .accessibilityLabel(Text("头像"))
  }
}

// MARK: - Generation

/// The generated artwork, separated from the view so it can be unit-tested.
public struct PixelAvatarArt: Sendable, Equatable {
  public static let grid = 5
  /// Only the left half plus the centre column is generated; the rest mirrors.
  static let half = (grid + 1) / 2

  public struct Cell: Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
      self.x = x
      self.y = y
    }
  }

  public let litCells: [Cell]
  public let foreground: Color
  public let background: Color
  /// Exposed for tests: the hue the seed hashed to.
  public let hue: Int

  public init(seed: String) {
    let key = seed.isEmpty ? "daily-os" : seed
    let hash = Self.fnv1a(key)
    // Two independent mixes, so hue is not correlated with block layout: seeds
    // one character apart should not look related.
    let hue = Int(Self.fnv1a("\(key)#hue") % 360)
    self.hue = hue
    self.foreground = Color(hslDegrees: hue, saturation: 0.58, lightness: 0.44)
    self.background = Color(hslDegrees: hue, saturation: 0.42, lightness: 0.93)

    // Redraw until the grid is neither near-empty nor near-solid. Both extremes
    // are indistinguishable from a rendering bug, and with 15 cells at even
    // odds they come up often enough to matter.
    var next = Mulberry32(seed: hash)
    var on = [Bool]()
    let total = Self.grid * Self.half
    for _ in 0..<8 {
      on = (0..<total).map { _ in next.next() < 0.5 }
      let lit = on.lazy.filter { $0 }.count
      if lit >= 4 && lit <= total - 2 { break }
    }

    var cells = [Cell]()
    for y in 0..<Self.grid {
      for x in 0..<Self.half where on[y * Self.half + x] {
        cells.append(Cell(x: x, y: y))
        let mirrored = Self.grid - 1 - x
        if mirrored != x { cells.append(Cell(x: mirrored, y: y)) }
      }
    }
    self.litCells = cells
  }

  /// FNV-1a over UTF-16 code units — matching `String.charCodeAt` on the web.
  static func fnv1a(_ value: String) -> UInt32 {
    var hash: UInt32 = 0x811c_9dc5
    for unit in value.utf16 {
      hash ^= UInt32(unit)
      hash = hash &* 0x0100_0193
    }
    return hash
  }
}

/// mulberry32, advanced once per cell.
struct Mulberry32 {
  private var state: UInt32

  init(seed: UInt32) { self.state = seed }

  mutating func next() -> Double {
    state = state &+ 0x6d2b_79f5
    var t = state
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double((t ^ (t >> 14))) / 4_294_967_296
  }
}

// MARK: - HSL

extension Color {
  /// CSS `hsl()`. SwiftUI ships HSB, which is a different colour space; the web
  /// avatars are specified in HSL and have to stay byte-identical.
  init(hslDegrees hue: Int, saturation: Double, lightness: Double) {
    let h = Double(hue % 360) / 360
    let c = (1 - abs(2 * lightness - 1)) * saturation
    let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
    let m = lightness - c / 2
    let (r, g, b): (Double, Double, Double)
    switch h * 6 {
    case ..<1: (r, g, b) = (c, x, 0)
    case ..<2: (r, g, b) = (x, c, 0)
    case ..<3: (r, g, b) = (0, c, x)
    case ..<4: (r, g, b) = (0, x, c)
    case ..<5: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }
    self.init(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: 1)
  }
}
