import AppKit
import SwiftUI
import DailyOSCore

// Generates App/Assets.xcassets/AppIcon.appiconset from `DailyOSMark`.
//
// The icon is rendered from the same view the app draws rather than exported
// from a design file, so the two cannot drift. That is the entire argument for
// a build step here: a logo that is a picture somewhere else eventually stops
// matching the one on screen, and nobody notices which of the two is stale.
//
//   swift run daily-os-icon
//
// Run it after changing the mark. The output is committed — a build that needs
// a code generator to produce an app icon is a build that fails on a machine
// where someone forgot.

/// One macOS icon slot. `size` is points, `scale` the multiplier.
struct Slot {
  let size: Int
  let scale: Int
  var pixels: Int { size * scale }
  var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let slots: [Slot] = [
  Slot(size: 16, scale: 1), Slot(size: 16, scale: 2),
  Slot(size: 32, scale: 1), Slot(size: 32, scale: 2),
  Slot(size: 128, scale: 1), Slot(size: 128, scale: 2),
  Slot(size: 256, scale: 1), Slot(size: 256, scale: 2),
  Slot(size: 512, scale: 1), Slot(size: 512, scale: 2),
]

/// The icon artwork.
///
/// A dark moss squircle with paper-coloured rings, not the light palette the
/// app uses. An icon lives in the Dock and in Finder next to other icons, on
/// whatever wallpaper the user picked — a near-white tile disappears against
/// half of them, and at 16pt a pale mark on pale ground is a grey smudge.
/// Inverting for the icon is the one place the palette is allowed to flip.
///
/// The mark is inset to about 62% of the tile. macOS does not mask or pad app
/// icons the way iOS does: the squircle and its margin are the artwork's job,
/// and an icon drawn edge to edge looks oversized beside every system app.
struct AppIconArt: View {
  /// How much of the mark survives at this size.
  ///
  /// Found by generating each slot and looking at it blown up, which is the
  /// only way this is ever found — every size looks fine in the asset catalog's
  /// thumbnail grid, because that grid shows them all at the same size.
  enum Detail {
    /// Seven rings. 128pt and up.
    case full
    /// Seven solid discs — at 32pt the hole in a ring is sub-pixel and the
    /// seven of them average into a smudge.
    case dots
    /// One ring. At 16pt the whole mark spans about seven physical pixels, so
    /// seven of anything inside it cannot separate no matter how it is drawn.
    /// A single bold ring is the same colours and the same silhouette family,
    /// and it is *crisp* — which at this size is the only property that reads.
    case single
  }

  var detail: Detail = .full

  private var paper: Color { Color(hex: 0xF6F7F4) }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 185, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(hex: 0x2A8B6E), Color(hex: 0x14533F)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        // A hairline of lift along the top edge, which is what stops a flat
        // gradient tile from looking like a placeholder.
        .overlay {
          RoundedRectangle(cornerRadius: 185, style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: 6
            )
        }
        // 824 in a 1024 canvas with a 185 radius is Apple's own macOS icon
        // grid. Drawing edge to edge, or rounding it more, makes the icon look
        // oversized and foreign beside every system app in the Dock.
        .frame(width: 824, height: 824)

      switch detail {
      case .full:
        DailyOSMark(motion: .still, style: .rings, tint: paper, centerTint: .white)
          .frame(width: 512, height: 512)
      case .dots:
        DailyOSMark(motion: .still, style: .solid, tint: paper, centerTint: .white)
          .frame(width: 470, height: 470)
      case .single:
        Circle()
          .strokeBorder(paper, lineWidth: 96)
          .frame(width: 440, height: 440)
      }
    }
    .frame(width: 1024, height: 1024)
  }
}

@MainActor
func render() throws {
  let root = URL(filePath: FileManager.default.currentDirectoryPath)
  let output = root.appending(path: "App/Assets.xcassets/AppIcon.appiconset")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

  // Rendered once at 1024 and downsampled, rather than re-rendered per size.
  // Re-rendering would re-solve the mark's geometry at every scale and let
  // rounding drift the ring positions between slots; one master keeps all ten
  // slots exactly the same picture.
  func master(_ detail: AppIconArt.Detail) throws -> NSImage {
    let renderer = ImageRenderer(content: AppIconArt(detail: detail))
    renderer.scale = 1
    guard let image = renderer.nsImage else {
      throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "渲染失败"])
    }
    return image
  }

  let masters: [AppIconArt.Detail: NSImage] = [
    .full: try master(.full),
    .dots: try master(.dots),
    .single: try master(.single),
  ]

  for slot in slots {
    let detail: AppIconArt.Detail = switch slot.pixels {
    case ...16: .single
    case ...64: .dots
    default: .full
    }
    let source = masters[detail]!
    guard let png = downsample(source, to: slot.pixels) else {
      throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "缩放到 \(slot.pixels) 失败"])
    }
    try png.write(to: output.appending(path: slot.filename))
  }

  let images = slots.map { slot in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.size)x\(slot.size)"
        }
    """
  }
  let contents = """
  {
    "images" : [
  \(images.joined(separator: ",\n"))
    ],
    "info" : {
      "author" : "daily-os-icon",
      "version" : 1
    }
  }

  """
  try contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
  print("✓ 写入 \(slots.count) 个尺寸 → App/Assets.xcassets/AppIcon.appiconset")
}

/// Draws the master into a bitmap of the target size with high interpolation.
/// `NSImage.size` alone would only retag it; the pixels have to be resampled or
/// the 16pt slot ships a 1024px image and every Finder list is a blurry mess.
func downsample(_ image: NSImage, to pixels: Int) -> Data? {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else { return nil }
  bitmap.size = NSSize(width: pixels, height: pixels)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.current?.imageInterpolation = .high
  image.draw(
    in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
    from: .zero,
    operation: .copy,
    fraction: 1
  )
  NSGraphicsContext.restoreGraphicsState()

  return bitmap.representation(using: .png, properties: [:])
}

try await MainActor.run { try render() }
