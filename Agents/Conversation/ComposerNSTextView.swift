import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Composer Trigger & Edit Models

nonisolated enum ComposerCompletionKeyCommand: Sendable {
    case moveUp
    case moveDown
    case accept
    case dismiss
}

nonisolated struct ComposerTriggerState: Equatable, Sendable {
    let trigger: String       // "@" or "/"
    let query: String
    let replacementRange: NSRange
}

nonisolated struct ComposerProgrammaticEdit: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case insertAtSelection(String)
        case replaceRange(NSRange, String, moveCaretTo: NSRange?)
        case replaceAll(String)
        case focus
    }

    let id: UUID
    let operation: Operation

    init(_ operation: Operation) {
        self.id = UUID()
        self.operation = operation
    }
}

// MARK: - NSViewRepresentable Wrapper

struct ComposerNSTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var selectedRange: NSRange
    @Binding var activeTrigger: ComposerTriggerState?
    @Binding var isFocused: Bool
    @Binding var isDragTargeted: Bool

    var placeholder: String
    var fontScale: Double
    var hasActiveCompletions: Bool
    var pendingEdit: ComposerProgrammaticEdit?

    var onEditConsumed: (UUID) -> Void
    var onSubmit: (_ alternateDelivery: Bool) -> Void
    var onCompletionKey: (ComposerCompletionKeyCommand) -> Void
    var onNavigateHistory: (_ direction: Int) -> Bool
    var onEscape: () -> Void
    var onPasteImageData: (Data, String) -> Void
    var onDropOrPasteURLs: ([URL]) -> Void

    static let minHeight: CGFloat = 38
    static let maxHeight: CGFloat = 320

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = ComposerAppKitTextView()
        textView.delegate = context.coordinator
        textView.coordinatorRef = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.placeholderString = placeholder
        textView.setAccessibilityLabel(placeholder)
        textView.font = Self.resolvedNSFont(scale: fontScale)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
            if let window = textView.window, window.firstResponder == window {
                window.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        let targetFont = Self.resolvedNSFont(scale: fontScale)
        if textView.font != targetFont {
            textView.font = targetFont
            context.coordinator.recalculateHeight()
        }

        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
            textView.setAccessibilityLabel(placeholder)
            textView.needsDisplay = true
        }

        // Apply pending programmatic edit (insertions, completion replacements, dictation updates)
        if let edit = pendingEdit, context.coordinator.lastProcessedEditID != edit.id {
            context.coordinator.lastProcessedEditID = edit.id
            context.coordinator.applyProgrammaticEdit(edit, on: textView)
            let consumedID = edit.id
            DispatchQueue.main.async {
                onEditConsumed(consumedID)
            }
            return
        }

        // Synchronize external text mutations (e.g. clear after send)
        if !context.coordinator.isUpdatingFromDelegate && textView.string != text {
            context.coordinator.isApplyingExternalSync = true
            textView.string = text
            let endLoc = (text as NSString).length
            textView.setSelectedRange(NSRange(location: endLoc, length: 0))
            context.coordinator.isApplyingExternalSync = false
            textView.needsDisplay = true
            context.coordinator.recalculateHeight()
            context.coordinator.evaluateTrigger(in: textView)
        }
    }

    private static func resolvedNSFont(scale: Double) -> NSFont {
        let clamped = max(0.8, min(1.5, scale))
        return NSFont.systemFont(ofSize: CGFloat(13.5 * clamped), weight: .regular)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerNSTextView
        weak var textView: ComposerAppKitTextView?
        var isUpdatingFromDelegate = false
        var isApplyingExternalSync = false
        var lastProcessedEditID: UUID? = nil

        init(parent: ComposerNSTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalSync, let textView else { return }
            isUpdatingFromDelegate = true
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            isUpdatingFromDelegate = false
            textView.needsDisplay = true
            recalculateHeight()
            evaluateTrigger(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalSync, let textView else { return }
            let sel = textView.selectedRange()
            if parent.selectedRange != sel {
                parent.selectedRange = sel
            }
            evaluateTrigger(in: textView)
        }

        func recalculateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let totalHeight = ceil(usedHeight + textView.textContainerInset.height * 2 + 2)
            let clamped = min(ComposerNSTextView.maxHeight, max(ComposerNSTextView.minHeight, totalHeight))
            if abs(parent.measuredHeight - clamped) > 0.5 {
                parent.measuredHeight = clamped
            }
        }

        func applyProgrammaticEdit(_ edit: ComposerProgrammaticEdit, on textView: ComposerAppKitTextView) {
            isApplyingExternalSync = true
            let nsString = textView.string as NSString

            switch edit.operation {
            case .insertAtSelection(let snippet):
                var targetRange = textView.selectedRange()
                if targetRange.location == NSNotFound || targetRange.location > nsString.length {
                    targetRange = NSRange(location: nsString.length, length: 0)
                }
                if textView.shouldChangeText(in: targetRange, replacementString: snippet) {
                    textView.replaceCharacters(in: targetRange, with: snippet)
                    textView.didChangeText()
                }
                let newCaret = NSRange(location: targetRange.location + (snippet as NSString).length, length: 0)
                textView.setSelectedRange(newCaret)
                textView.window?.makeFirstResponder(textView)

            case .replaceRange(let range, let replacement, let explicitCaret):
                let safeLoc = min(max(0, range.location), nsString.length)
                let safeLen = min(max(0, range.length), nsString.length - safeLoc)
                let safeRange = NSRange(location: safeLoc, length: safeLen)
                if textView.shouldChangeText(in: safeRange, replacementString: replacement) {
                    textView.replaceCharacters(in: safeRange, with: replacement)
                    textView.didChangeText()
                }
                let caret = explicitCaret ?? NSRange(location: safeRange.location + (replacement as NSString).length, length: 0)
                let postLength = (textView.string as NSString).length
                let clampedCaretLoc = min(max(0, caret.location), postLength)
                textView.setSelectedRange(NSRange(location: clampedCaretLoc, length: 0))
                textView.window?.makeFirstResponder(textView)

            case .replaceAll(let fullText):
                let fullRange = NSRange(location: 0, length: nsString.length)
                if textView.shouldChangeText(in: fullRange, replacementString: fullText) {
                    textView.replaceCharacters(in: fullRange, with: fullText)
                    textView.didChangeText()
                }
                let end = (fullText as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.window?.makeFirstResponder(textView)

            case .focus:
                textView.window?.makeFirstResponder(textView)
            }

            isApplyingExternalSync = false
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            textView.needsDisplay = true
            recalculateHeight()
            evaluateTrigger(in: textView)
        }

        func evaluateTrigger(in textView: ComposerAppKitTextView) {
            guard !textView.hasMarkedText() else {
                if parent.activeTrigger != nil { parent.activeTrigger = nil }
                return
            }

            let sel = textView.selectedRange()
            guard sel.length == 0, sel.location != NSNotFound else {
                if parent.activeTrigger != nil { parent.activeTrigger = nil }
                return
            }

            let nsText = textView.string as NSString
            guard sel.location <= nsText.length, sel.location > 0 else {
                if parent.activeTrigger != nil { parent.activeTrigger = nil }
                return
            }

            // Scan backward from caret until whitespace or start of string
            var scan = sel.location - 1
            while scan >= 0 {
                let ch = nsText.character(at: scan)
                if let scalar = Unicode.Scalar(ch), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    break
                }
                scan -= 1
            }

            let tokenStart = scan + 1
            let tokenLength = sel.location - tokenStart
            guard tokenLength >= 1 else {
                if parent.activeTrigger != nil { parent.activeTrigger = nil }
                return
            }

            let tokenRange = NSRange(location: tokenStart, length: tokenLength)
            let token = nsText.substring(with: tokenRange)

            if token.hasPrefix("@") {
                let query = String(token.dropFirst())
                // Ignore email-like patterns where character before @ was non-whitespace (guaranteed by scan)
                let nextState = ComposerTriggerState(trigger: "@", query: query, replacementRange: tokenRange)
                if parent.activeTrigger != nextState {
                    parent.activeTrigger = nextState
                }
                return
            }

            if token.hasPrefix("/") {
                // Slash commands trigger at start of composer or start of a new line
                let isLineStart: Bool = {
                    guard tokenStart > 0 else { return true }
                    let prev = nsText.character(at: tokenStart - 1)
                    return prev == 10 || prev == 13
                }()
                if isLineStart && !token.dropFirst().contains("/") {
                    let query = String(token.dropFirst())
                    let nextState = ComposerTriggerState(trigger: "/", query: query, replacementRange: tokenRange)
                    if parent.activeTrigger != nextState {
                        parent.activeTrigger = nextState
                    }
                    return
                }
            }

            if parent.activeTrigger != nil {
                parent.activeTrigger = nil
            }
        }
    }
}

// MARK: - Custom AppKit NSTextView Subclass

@MainActor
final class ComposerAppKitTextView: NSTextView {
    weak var coordinatorRef: ComposerNSTextView.Coordinator?
    var placeholderString: String = ""

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            coordinatorRef?.parent.isFocused = true
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            coordinatorRef?.parent.isFocused = false
        }
        return resigned
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        coordinatorRef?.recalculateHeight()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholderString.isEmpty else { return }

        let targetFont = font ?? NSFont.systemFont(ofSize: 13.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: targetFont,
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let pad = textContainer?.lineFragmentPadding ?? 4
        let rect = NSRect(
            x: textContainerInset.width + pad,
            y: textContainerInset.height,
            width: max(0, bounds.width - (textContainerInset.width + pad) * 2),
            height: max(0, bounds.height - textContainerInset.height * 2)
        )
        (placeholderString as NSString).draw(in: rect, withAttributes: attrs)
    }

    // MARK: - Keyboard Handling (Return, ⇧Return, Escape, Autocomplete & History)

    override func keyDown(with event: NSEvent) {
        // Never intercept active IME composition (Japanese/Chinese/Korean/dead-keys)
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        guard let coord = coordinatorRef else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCompletions = coord.parent.hasActiveCompletions

        switch event.keyCode {
        case 36, 76: // Return / Keypad Enter
            if flags.contains(.shift) || flags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }
            if hasCompletions && !flags.contains(.command) {
                coord.parent.onCompletionKey(.accept)
                return
            }
            coord.parent.onSubmit(flags.contains(.command))
            return

        case 48: // Tab
            if hasCompletions && flags.subtracting([.numericPad]).isEmpty {
                coord.parent.onCompletionKey(.accept)
                return
            }

        case 53: // Escape
            if hasCompletions {
                coord.parent.onCompletionKey(.dismiss)
                return
            }
            coord.parent.onEscape()
            return

        case 126: // Up Arrow
            let cleanMods = flags.intersection([.shift, .command, .option, .control])
            if cleanMods.isEmpty {
                if hasCompletions {
                    coord.parent.onCompletionKey(.moveUp)
                    return
                }
                let sel = selectedRange()
                if sel.length == 0 && sel.location == 0 {
                    if coord.parent.onNavigateHistory(-1) {
                        return
                    }
                }
            }

        case 125: // Down Arrow
            let cleanMods = flags.intersection([.shift, .command, .option, .control])
            if cleanMods.isEmpty {
                if hasCompletions {
                    coord.parent.onCompletionKey(.moveDown)
                    return
                }
                let sel = selectedRange()
                if sel.length == 0 && sel.location == (string as NSString).length {
                    if coord.parent.onNavigateHistory(1) {
                        return
                    }
                }
            }

        default:
            break
        }

        super.keyDown(with: event)
    }

    // MARK: - Pasteboard Image & File Handling

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // 1. File URLs on pasteboard (e.g. Finder copy -> paste)
        if let fileURLs = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            coordinatorRef?.parent.onDropOrPasteURLs(fileURLs)
            return
        }

        // 2. Direct screenshot / image data when no plain text is on the pasteboard
        let hasPlainString = pb.string(forType: .string)?.isEmpty == false
        if !hasPlainString {
            if let pngData = pb.data(forType: .png), !pngData.isEmpty {
                let name = "pasted-image-\(Int(Date().timeIntervalSince1970)).png"
                coordinatorRef?.parent.onPasteImageData(pngData, name)
                return
            }
            if let tiffData = pb.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:])
            {
                let name = "pasted-image-\(Int(Date().timeIntervalSince1970)).png"
                coordinatorRef?.parent.onPasteImageData(pngData, name)
                return
            }
            if let nsImage = NSImage(pasteboard: pb),
               let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:])
            {
                let name = "pasted-image-\(Int(Date().timeIntervalSince1970)).png"
                coordinatorRef?.parent.onPasteImageData(pngData, name)
                return
            }
        }

        super.pasteAsPlainText(sender)
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pb.availableType(from: [.png, .tiff, .string]) != nil
        {
            coordinatorRef?.parent.isDragTargeted = true
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        coordinatorRef?.parent.isDragTargeted = false
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        coordinatorRef?.parent.isDragTargeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        coordinatorRef?.parent.isDragTargeted = false
        let pb = sender.draggingPasteboard

        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            coordinatorRef?.parent.onDropOrPasteURLs(urls)
            return true
        }

        if let pngData = pb.data(forType: .png), !pngData.isEmpty {
            let name = "dropped-image-\(Int(Date().timeIntervalSince1970)).png"
            coordinatorRef?.parent.onPasteImageData(pngData, name)
            return true
        }

        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:])
        {
            let name = "dropped-image-\(Int(Date().timeIntervalSince1970)).png"
            coordinatorRef?.parent.onPasteImageData(pngData, name)
            return true
        }

        return super.performDragOperation(sender)
    }
}
