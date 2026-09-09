import Foundation
import DailyOSCore

// Cross-platform parity checks, runnable with `swift run daily-os-checks`.
//
// Only one thing in this repository can be wrong in a way that a screenshot
// would not catch: the pixel avatar. It is a port of `pixelAvatarSvg()` from the
// daily-os service (`src/ui/avatar.ts`), and it is only worth porting if it
// produces byte-identical output — an account whose avatar changes between the
// Mac app and the browser is worse than no avatar at all.
//
// The expected values below were read off the real JavaScript implementation,
// not re-derived from the algorithm, so this compares two independent
// implementations rather than one implementation against itself.

var failures: [String] = []

@MainActor
func check(_ condition: Bool, _ message: @autoclosure () -> String) {
  if !condition { failures.append(message()) }
}

struct Fixture {
  let seed: String
  let hue: Int
  let cells: Set<PixelAvatarArt.Cell>

  init(_ seed: String, hue: Int, _ pairs: [(Int, Int)]) {
    self.seed = seed
    self.hue = hue
    self.cells = Set(pairs.map { PixelAvatarArt.Cell(x: $0.0, y: $0.1) })
  }
}

let fixtures: [Fixture] = [
  Fixture("kq7d2f1m", hue: 345, [
    (1, 0), (3, 0), (2, 0),
    (0, 2), (4, 2),
    (0, 3), (4, 3), (1, 3), (3, 3), (2, 3),
    (0, 4), (4, 4), (1, 4), (3, 4),
  ]),
  Fixture("z4h8bn02", hue: 236, [
    (0, 0), (4, 0),
    (1, 1), (3, 1), (2, 1),
    (2, 2),
    (0, 3), (4, 3), (1, 3), (3, 3), (2, 3),
    (0, 4), (4, 4),
  ]),
  Fixture("daily-os", hue: 166, [
    (0, 0), (4, 0),
    (1, 1), (3, 1), (2, 1),
    (0, 2), (4, 2), (1, 2), (3, 2),
    (0, 3), (4, 3), (2, 3),
    (0, 4), (4, 4), (1, 4), (3, 4),
  ]),
  Fixture("demo", hue: 287, [
    (1, 0), (3, 0), (2, 0),
    (0, 1), (4, 1), (1, 1), (3, 1),
    (0, 2), (4, 2), (2, 2),
    (1, 3), (3, 3),
    (2, 4),
  ]),
]

// 1. The generated grid matches the web implementation.
for fixture in fixtures {
  let art = PixelAvatarArt(seed: fixture.seed)
  check(
    Set(art.litCells) == fixture.cells,
    "avatar cells differ for seed '\(fixture.seed)'"
  )
  check(
    art.hue == fixture.hue,
    "avatar hue differs for seed '\(fixture.seed)': got \(art.hue), expected \(fixture.hue)"
  )
}

// 2. An empty seed falls back to the house avatar rather than to an empty grid.
check(
  PixelAvatarArt(seed: "").litCells == PixelAvatarArt(seed: "daily-os").litCells,
  "an empty seed should fall back to 'daily-os'"
)

// 3. No seed produces a blank or solid grid. The web implementation redraws up
//    to eight times to guarantee this; a port that dropped the retry loop would
//    still pass the fixtures above, so it is checked separately.
let half = (PixelAvatarArt.grid + 1) / 2
let totalHalfCells = PixelAvatarArt.grid * half
for index in 0..<400 {
  let seed = "seed-\(index)"
  let generated = PixelAvatarArt(seed: seed).litCells.filter { $0.x < half }.count
  check(generated >= 4, "'\(seed)' came out nearly blank (\(generated) cells)")
  check(generated <= totalHalfCells - 2, "'\(seed)' came out nearly solid (\(generated) cells)")
}

// 4. Formatting, which is shared by every screen and is easy to break silently.
check(Fmt.duration(.seconds(1.4)).hasPrefix("1.4"), "sub-10s durations should keep one decimal")
check(Fmt.duration(.seconds(128)) == "2m 08s", "minute durations should pad seconds")
check(Fmt.compactCount(940) == "940", "counts below 1k should be exact")
check(Fmt.compactCount(12_400) == "12.4k", "thousands should be compacted")
check(Fmt.money(0.0312) == "$0.0312", "sub-dollar cost needs four decimals to be readable")

if failures.isEmpty {
  print("ok — \(fixtures.count) avatar fixtures, 400 generated seeds, formatting")
} else {
  for failure in failures { print("FAIL: \(failure)") }
  print("\(failures.count) check(s) failed")
  exit(1)
}
