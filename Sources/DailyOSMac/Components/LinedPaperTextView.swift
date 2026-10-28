import SwiftUI
import AppKit

/// A plain-text editor drawn on lined notebook paper (LEO-351).
///
/// SwiftUI's `TextEditor` cannot set a line height, so ruled lines drawn behind
/// it would never meet the text. This wraps an `NSTextView` with a fixed line
/// height and paints the rules — and a left margin line — at that same rhythm, so
/// the writing sits on the lines. Paper, rule, margin and ink colours and the
/// font all come from the caller, so it follows the design system and the user's
/// font choice.
struct LinedPaperTextView: NSViewRepresentable {
  @Binding var text: String
  var font: NSFont
  var lineHeight: CGFloat
  var paper: NSColor
  var rule: NSColor
  var margin: NSColor
  var ink: NSColor
  var leftInset: CGFloat
  var topInset: CGFloat
  var onChange: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = RuledTextView()
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
    guard let textView = scroll.documentView as? RuledTextView else { return }
    scroll.backgroundColor = paper
    if textView.string != text { textView.string = text }
    apply(to: textView)
    textView.needsDisplay = true
  }

  /// Push the drawing colours, the line rhythm and the typography onto the view.
  private func apply(to textView: RuledTextView) {
    textView.ruleColor = rule
    textView.marginColor = margin
    textView.marginX = leftInset
    textView.lineStep = lineHeight
    textView.topInset = topInset
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
    let parent: LinedPaperTextView
    init(_ parent: LinedPaperTextView) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      parent.onChange()
    }
  }
}

/// The text view that paints the paper, the rules and the margin behind its text.
/// Text views are flipped, so y grows downward and the first rule sits one line
/// below the top inset.
final class RuledTextView: NSTextView {
  var ruleColor: NSColor = .separatorColor
  var marginColor: NSColor = .clear
  var marginX: CGFloat = 0
  var lineStep: CGFloat = 30
  var topInset: CGFloat = 10

  override func draw(_ dirtyRect: NSRect) {
    guard lineStep > 0 else { super.draw(dirtyRect); return }
    ruleColor.setStroke()
    // A few points under each line's baseline, so the writing sits on the rule
    // rather than floating above it.
    var y = topInset + lineStep - 6
    while y < bounds.height {
      let path = NSBezierPath()
      path.move(to: NSPoint(x: marginX, y: y))
      path.line(to: NSPoint(x: bounds.width, y: y))
      path.lineWidth = 1
      path.stroke()
      y += lineStep
    }
    if marginX > 12 {
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
