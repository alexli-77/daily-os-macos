import SwiftUI
import AppKit

/// A plain-text editor on a sheet of paper (LEO-351).
///
/// SwiftUI's `TextEditor` cannot set a line height, which this needs for a
/// comfortable, even rhythm — and which an earlier ruled version needed to try
/// (and failed) to line the text up with drawn rules. The rules are gone now; a
/// single left margin line stays, since a vertical line has no baseline to miss.
/// Paper, margin and ink colours and the font come from the caller.
struct PaperTextView: NSViewRepresentable {
  @Binding var text: String
  var font: NSFont
  /// The fixed line height for the body — generous, so the writing breathes.
  var lineHeight: CGFloat
  var paper: NSColor
  var margin: NSColor
  var ink: NSColor
  var leftInset: CGFloat
  var topInset: CGFloat
  var onChange: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = MarginTextView()
    textView.delegate = context.coordinator
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 0, height: topInset)
    textView.textContainer?.lineFragmentPadding = leftInset
    textView.string = text
    apply(to: textView)

    let scroll = NSScrollView()
    scroll.drawsBackground = true
    scroll.backgroundColor = paper
    scroll.hasVerticalScroller = true
    scroll.documentView = textView
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? MarginTextView else { return }
    scroll.backgroundColor = paper
    if textView.string != text { textView.string = text }
    apply(to: textView)
    textView.needsDisplay = true
  }

  private func apply(to textView: MarginTextView) {
    textView.marginColor = margin
    textView.marginX = leftInset
    textView.font = font
    textView.textColor = ink
    textView.insertionPointColor = ink

    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    textView.defaultParagraphStyle = style
    textView.typingAttributes = [.font: font, .foregroundColor: ink, .paragraphStyle: style]
    let whole = NSRange(location: 0, length: (textView.string as NSString).length)
    textView.textStorage?.addAttributes([.font: font, .foregroundColor: ink, .paragraphStyle: style], range: whole)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    let parent: PaperTextView
    init(_ parent: PaperTextView) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      parent.onChange()
    }
  }
}

/// Paints a single left margin line behind the text.
final class MarginTextView: NSTextView {
  var marginColor: NSColor = .clear
  var marginX: CGFloat = 0

  override func draw(_ dirtyRect: NSRect) {
    if marginX > 14 {
      marginColor.setStroke()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: marginX - 14, y: 0))
      line.line(to: NSPoint(x: marginX - 14, y: bounds.height))
      line.lineWidth = 1
      line.stroke()
    }
    super.draw(dirtyRect)
  }
}
