import AppKit
import SwiftUI

struct CodeEditorJumpTarget: Equatable {
    var id: UUID = UUID()
    var line: Int
    var column: Int?
}

struct NativeCodeEditorNSView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int

    var isEditable: Bool = true
    var wrapsLines: Bool = false
    var fontScale: Double = 1.0
    var jumpTarget: CodeEditorJumpTarget?
    var onSaveShortcut: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrapsLines
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        // Explicit TextKit 1 stack for deterministic glyph/line ruler geometry and fast code editing
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerWidth: CGFloat = wrapsLines ? 320 : CGFloat.greatestFiniteMagnitude
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = wrapsLines
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = AgentsCodeTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 320), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wrapsLines
        textView.autoresizingMask = wrapsLines ? [.width] : [.width, .height]

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        let fontSize = CGFloat(12.0 * max(0.8, min(1.5, fontScale)))
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = monoFont
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.typingAttributes = [
            .font: monoFont,
            .foregroundColor: NSColor.textColor,
        ]

        textView.string = text
        textView.delegate = context.coordinator
        textView.onSaveCommand = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSaveShortcut?()
        }

        scrollView.documentView = textView

        let ruler = CodeLineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasHorizontalRuler = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.attach(textView: textView, scrollView: scrollView, ruler: ruler)

        if let jumpTarget {
            context.coordinator.lastAppliedJumpID = jumpTarget.id
            DispatchQueue.main.async {
                context.coordinator.scrollTo(line: jumpTarget.line, column: jumpTarget.column, highlight: true)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? AgentsCodeTextView else { return }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        let fontSize = CGFloat(12.0 * max(0.8, min(1.5, fontScale)))
        let desiredFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != desiredFont {
            textView.font = desiredFont
            textView.typingAttributes = [
                .font: desiredFont,
                .foregroundColor: NSColor.textColor,
            ]
            context.coordinator.ruler?.updateRuleThicknessIfNeeded()
            context.coordinator.ruler?.needsDisplay = true
        }

        // Update wrapping configuration if toggled
        if let container = textView.textContainer, container.widthTracksTextView != wrapsLines {
            scrollView.hasHorizontalScroller = !wrapsLines
            textView.isHorizontallyResizable = !wrapsLines
            container.widthTracksTextView = wrapsLines
            container.containerSize = NSSize(
                width: wrapsLines ? max(120, scrollView.contentSize.width) : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.sizeToFit()
        }

        // Synchronize external string changes without clobbering active typing
        if !context.coordinator.isUpdatingFromTextView && textView.string != text {
            let previousRanges = textView.selectedRanges
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            textView.undoManager?.removeAllActions()
            let length = (text as NSString).length
            if let first = previousRanges.first?.rangeValue, first.location <= length {
                let clampedLen = min(first.length, max(0, length - first.location))
                textView.setSelectedRange(NSRange(location: first.location, length: clampedLen))
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            context.coordinator.isApplyingExternalText = false
            context.coordinator.ruler?.updateRuleThicknessIfNeeded()
            context.coordinator.ruler?.needsDisplay = true
            context.coordinator.recomputeCursorPosition(in: textView)
        }

        if let jumpTarget, jumpTarget.id != context.coordinator.lastAppliedJumpID {
            context.coordinator.lastAppliedJumpID = jumpTarget.id
            DispatchQueue.main.async {
                context.coordinator.scrollTo(line: jumpTarget.line, column: jumpTarget.column, highlight: true)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCodeEditorNSView
        weak var textView: AgentsCodeTextView?
        weak var ruler: CodeLineNumberRulerView?
        var isUpdatingFromTextView: Bool = false
        var isApplyingExternalText: Bool = false
        var lastAppliedJumpID: UUID?
        nonisolated(unsafe) private var boundsObserver: NSObjectProtocol?

        init(parent: NativeCodeEditorNSView) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func attach(textView: AgentsCodeTextView, scrollView: NSScrollView, ruler: CodeLineNumberRulerView) {
            self.textView = textView
            self.ruler = ruler
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak ruler] _ in
                MainActor.assumeIsolated {
                    ruler?.needsDisplay = true
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let tv = notification.object as? AgentsCodeTextView else { return }
            isUpdatingFromTextView = true
            parent.text = tv.string
            isUpdatingFromTextView = false
            ruler?.updateRuleThicknessIfNeeded()
            ruler?.needsDisplay = true
            tv.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? AgentsCodeTextView else { return }
            recomputeCursorPosition(in: tv)
            ruler?.needsDisplay = true
            tv.needsDisplay = true
        }

        func recomputeCursorPosition(in tv: AgentsCodeTextView) {
            let nsString = tv.string as NSString
            let selLocation = min(tv.selectedRange().location, nsString.length)
            var line = 1
            var lineStart = 0

            if selLocation > 0 {
                var idx = 0
                while idx < selLocation {
                    let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
                    let nextIdx = NSMaxRange(lineRange)
                    if nextIdx <= selLocation {
                        // Advance line count if line ended with a newline
                        let lastChar = nsString.character(at: nextIdx - 1)
                        if lastChar == 10 || lastChar == 13 {
                            line += 1
                            lineStart = nextIdx
                        }
                        if nextIdx == idx { break }
                        idx = nextIdx
                    } else {
                        break
                    }
                }
            }

            let col = max(1, selLocation - lineStart + 1)
            tv.activeCursorLine = line
            ruler?.activeLine = line

            if parent.cursorLine != line {
                parent.cursorLine = line
            }
            if parent.cursorColumn != col {
                parent.cursorColumn = col
            }
        }

        func scrollTo(line targetLine: Int, column targetCol: Int?, highlight: Bool) {
            guard let tv = textView else { return }
            let nsString = tv.string as NSString
            let clampedTargetLine = max(1, targetLine)

            var currentLine = 1
            var index = 0
            var targetLineRange = NSRange(location: 0, length: 0)

            while index <= nsString.length {
                if index == nsString.length {
                    targetLineRange = NSRange(location: index, length: 0)
                    break
                }
                let range = nsString.lineRange(for: NSRange(location: index, length: 0))
                if currentLine == clampedTargetLine {
                    targetLineRange = range
                    break
                }
                currentLine += 1
                let next = NSMaxRange(range)
                if next <= index { break }
                index = next
            }

            var contentLength = targetLineRange.length
            while contentLength > 0 {
                let ch = nsString.character(at: targetLineRange.location + contentLength - 1)
                if ch == 10 || ch == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }

            let colOffset = max(0, min(contentLength, (targetCol ?? 1) - 1))
            let caretRange = NSRange(location: targetLineRange.location + colOffset, length: 0)
            let indicatorRange = NSRange(location: targetLineRange.location, length: max(0, contentLength))

            tv.setSelectedRange(caretRange)
            tv.scrollRangeToVisible(indicatorRange)
            if highlight && indicatorRange.length > 0 {
                tv.showFindIndicator(for: indicatorRange)
            }
            recomputeCursorPosition(in: tv)
            ruler?.needsDisplay = true
        }
    }
}

// MARK: - Syntax-Friendly NSTextView Subclass

final class AgentsCodeTextView: NSTextView {
    var onSaveCommand: (() -> Void)?
    var activeCursorLine: Int = 1

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSaveCommand?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange())
    }

    override func insertNewline(_ sender: Any?) {
        let nsText = string as NSString
        let sel = selectedRange()
        let safeLoc = min(sel.location, nsText.length)
        let currentLineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let linePrefixLen = max(0, safeLoc - currentLineRange.location)
        let currentLinePrefix = nsText.substring(with: NSRange(location: currentLineRange.location, length: linePrefixLen))

        let leadingWhitespace = currentLinePrefix.prefix { $0 == " " || $0 == "\t" }
        insertText("\n" + leadingWhitespace, replacementRange: sel)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer
        else { return }

        let nsText = string as NSString
        let safeLoc = min(selectedRange().location, nsText.length)
        let lineCharRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)

        var lineRect: NSRect
        if glyphRange.length > 0 {
            lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        } else if layoutManager.extraLineFragmentTextContainer != nil {
            lineRect = layoutManager.extraLineFragmentRect
        } else if layoutManager.numberOfGlyphs > 0 {
            let prevGlyph = max(0, layoutManager.numberOfGlyphs - 1)
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: prevGlyph, effectiveRange: nil)
        } else {
            let lineHeight = font.map { layoutManager.defaultLineHeight(for: $0) } ?? 16
            lineRect = NSRect(x: 0, y: 0, width: bounds.width, height: lineHeight)
        }

        let origin = textContainerOrigin
        let highlightRect = NSRect(
            x: 0,
            y: lineRect.minY + origin.y,
            width: bounds.width,
            height: max(15, lineRect.height)
        )

        if highlightRect.intersects(rect) {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let fill = isDark
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.03)
            fill.setFill()
            highlightRect.fill()
        }
    }
}

// MARK: - Monospaced Line-Number Gutter Ruler

final class CodeLineNumberRulerView: NSRulerView {
    private weak var codeTextView: AgentsCodeTextView?
    var activeLine: Int = 1

    init(textView: AgentsCodeTextView) {
        self.codeTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRuleThicknessIfNeeded() {
        guard let tv = codeTextView else { return }
        let approxLines = max(1, tv.string.utf8.filter { $0 == 10 }.count + 1)
        let digits = max(3, String(approxLines).count)
        let desired = CGFloat(digits * 8 + 18)
        if abs(ruleThickness - desired) > 1 {
            ruleThickness = desired
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = codeTextView,
              let layoutManager = tv.layoutManager,
              let textContainer = tv.textContainer
        else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let gutterBg = isDark
            ? NSColor(srgbRed: 0.11, green: 0.115, blue: 0.13, alpha: 1.0)
            : NSColor(srgbRed: 0.95, green: 0.955, blue: 0.965, alpha: 1.0)
        gutterBg.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        NSRect(x: bounds.maxX - 0.75, y: bounds.minY, width: 0.75, height: bounds.height).fill()

        let visibleRect = tv.visibleRect
        let origin = tv.textContainerOrigin
        let containerVisibleRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: containerVisibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsString = tv.string as NSString
        let baseSize = max(9.5, (tv.font?.pointSize ?? 12.0) - 1.5)
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .regular)
        let activeFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .semibold)

        // Count logical lines prior to visibleCharRange.location
        var lineNumber = 1
        if visibleCharRange.location > 0 {
            var scanIdx = 0
            while scanIdx < visibleCharRange.location && scanIdx < nsString.length {
                let r = nsString.lineRange(for: NSRange(location: scanIdx, length: 0))
                let end = NSMaxRange(r)
                if end <= visibleCharRange.location {
                    lineNumber += 1
                    if end <= scanIdx { break }
                    scanIdx = end
                } else {
                    break
                }
            }
        }

        var charIndex = visibleCharRange.location
        let maxChar = NSMaxRange(visibleCharRange)

        if nsString.length == 0 {
            drawLineLabel(
                number: 1,
                yPosition: origin.y - visibleRect.minY,
                lineHeight: layoutManager.defaultLineHeight(for: tv.font ?? regularFont),
                isActive: true,
                regularFont: regularFont,
                activeFont: activeFont
            )
            return
        }

        while charIndex < maxChar && charIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            if glyphIndex < layoutManager.numberOfGlyphs {
                let fragRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let yInRuler = fragRect.minY + origin.y - visibleRect.minY
                drawLineLabel(
                    number: lineNumber,
                    yPosition: yInRuler,
                    lineHeight: fragRect.height,
                    isActive: lineNumber == activeLine,
                    regularFont: regularFont,
                    activeFont: activeFont
                )
            }
            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= charIndex { break }
            charIndex = next
        }

        // Trailing empty line after final newline
        if nsString.length > 0 {
            let lastChar = nsString.character(at: nsString.length - 1)
            if (lastChar == 10 || lastChar == 13), layoutManager.extraLineFragmentTextContainer != nil {
                let extraRect = layoutManager.extraLineFragmentRect
                let yInRuler = extraRect.minY + origin.y - visibleRect.minY
                if yInRuler >= -extraRect.height && yInRuler <= bounds.height {
                    drawLineLabel(
                        number: lineNumber,
                        yPosition: yInRuler,
                        lineHeight: extraRect.height,
                        isActive: lineNumber == activeLine,
                        regularFont: regularFont,
                        activeFont: activeFont
                    )
                }
            }
        }
    }

    private func drawLineLabel(
        number: Int,
        yPosition: CGFloat,
        lineHeight: CGFloat,
        isActive: Bool,
        regularFont: NSFont,
        activeFont: NSFont
    ) {
        let label = "\(number)" as NSString
        let font = isActive ? activeFont : regularFont
        let color = isActive ? NSColor.labelColor : NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = label.size(withAttributes: attrs)
        let drawPoint = NSPoint(
            x: max(4, ruleThickness - size.width - 7),
            y: yPosition + max(0, (lineHeight - size.height) * 0.5)
        )
        label.draw(at: drawPoint, withAttributes: attrs)
    }
}
