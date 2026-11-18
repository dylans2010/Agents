import AppKit
import CoincideRemoteKit
import Foundation
import SwiftUI

// MARK: - SwiftUI Representable Wrapper

public struct NativeTerminalNSView: NSViewRepresentable {
    public let terminalID: String
    public let runtime: AgentsRuntimeClient?
    public let fontScale: Double
    public let isBusy: Bool
    public let isPrimaryFocus: Bool
    public let onFocusRequested: () -> Void
    public let onSendToComposer: (String) -> Void
    public let onSnapshotChanged: ((TerminalViewportSnapshot) -> Void)?

    public init(
        terminalID: String,
        runtime: AgentsRuntimeClient?,
        fontScale: Double,
        isBusy: Bool = false,
        isPrimaryFocus: Bool = true,
        onFocusRequested: @escaping () -> Void = {},
        onSendToComposer: @escaping (String) -> Void = { _ in },
        onSnapshotChanged: ((TerminalViewportSnapshot) -> Void)? = nil
    ) {
        self.terminalID = terminalID
        self.runtime = runtime
        self.fontScale = fontScale
        self.isBusy = isBusy
        self.isPrimaryFocus = isPrimaryFocus
        self.onFocusRequested = onFocusRequested
        self.onSendToComposer = onSendToComposer
        self.onSnapshotChanged = onSnapshotChanged
    }

    public func makeNSView(context: Context) -> TerminalCanvasNSView {
        let view = TerminalCanvasNSView(frame: .zero)
        view.configure(
            terminalID: terminalID,
            runtime: runtime,
            fontScale: fontScale,
            isBusy: isBusy,
            isPrimaryFocus: isPrimaryFocus,
            onFocusRequested: onFocusRequested,
            onSendToComposer: onSendToComposer,
            onSnapshotChanged: onSnapshotChanged
        )
        return view
    }

    public func updateNSView(_ nsView: TerminalCanvasNSView, context: Context) {
        nsView.configure(
            terminalID: terminalID,
            runtime: runtime,
            fontScale: fontScale,
            isBusy: isBusy,
            isPrimaryFocus: isPrimaryFocus,
            onFocusRequested: onFocusRequested,
            onSendToComposer: onSendToComposer,
            onSnapshotChanged: onSnapshotChanged
        )
    }
}

// MARK: - High-DPI AppKit PTY Terminal Canvas

public final class TerminalCanvasNSView: NSView {
    public struct GridPosition: Equatable, Comparable, Sendable {
        public var row: Int
        public var col: Int

        public static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.col < rhs.col
        }
    }

    private struct RenderSignature: Equatable {
        let terminalID: String
        let revision: UInt64
        let displayOffset: Int
        let cursorRow: Int
        let cursorCol: Int
        let cursorVisible: Bool
        let cursorShape: String
        let isDark: Bool
        let cols: Int
        let rows: Int
    }

    private static let defaultBackgroundColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.067, green: 0.075, blue: 0.094, alpha: 1.0)
            : NSColor(srgbRed: 0.980, green: 0.984, blue: 0.992, alpha: 1.0)
    }

    private static let defaultForegroundColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.902, green: 0.929, blue: 0.953, alpha: 1.0)
            : NSColor(srgbRed: 0.122, green: 0.137, blue: 0.157, alpha: 1.0)
    }

    private static let cursorTintColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.42, green: 0.69, blue: 1.0, alpha: 0.92)
            : NSColor(srgbRed: 0.12, green: 0.44, blue: 0.92, alpha: 0.90)
    }

    private static let jumpBadgeBackgroundColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 0.94)
            : NSColor(srgbRed: 0.90, green: 0.93, blue: 0.98, alpha: 0.95)
    }

    // Configuration
    private var terminalID: String = ""
    private var runtime: AgentsRuntimeClient?
    private var fontScale: Double = 1.0
    private var isBusy: Bool = false
    private var isPrimaryFocus: Bool = true
    private var onFocusRequested: (() -> Void)?
    private var onSendToComposer: ((String) -> Void)?
    private var onSnapshotChanged: ((TerminalViewportSnapshot) -> Void)?

    // Font & Monospaced Cell Metrics
    private var regularFont: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var boldFont: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .bold)
    private var italicFont: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var boldItalicFont: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .bold)
    private var cellWidth: CGFloat = 7.6
    private var cellHeight: CGFloat = 17.0
    private var baselineOffset: CGFloat = 13.0
    private let horizontalInset: CGFloat = 10.0
    private let verticalInset: CGFloat = 6.0

    // Viewport Snapshot & Polling State
    public private(set) var latestSnapshot: TerminalViewportSnapshot?
    private var lastRenderSignature: RenderSignature?
    private var lastResizedTerminalID: String = ""
    private var lastReportedCols: Int = 0
    private var lastReportedRows: Int = 0
    private var lastInteractionAt: ContinuousClock.Instant = .now
    private var scrollAccumulator: CGFloat = 0
    private var jumpToBottomRect: NSRect = .zero
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?

    // Selection State
    private var selectionAnchor: GridPosition?
    private var selectionHead: GridPosition?
    private var isDraggingSelection: Bool = false

    override public var isFlipped: Bool { true }
    override public var acceptsFirstResponder: Bool { true }
    override public var isOpaque: Bool { true }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        rebuildFonts(scale: 1.0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Configuration & Lifecycle

    public func configure(
        terminalID: String,
        runtime: AgentsRuntimeClient?,
        fontScale: Double,
        isBusy: Bool,
        isPrimaryFocus: Bool,
        onFocusRequested: @escaping () -> Void,
        onSendToComposer: @escaping (String) -> Void,
        onSnapshotChanged: ((TerminalViewportSnapshot) -> Void)?
    ) {
        let terminalChanged = self.terminalID != terminalID
        let scaleChanged = abs(self.fontScale - fontScale) > 0.001
        let runtimeChanged = (self.runtime == nil) != (runtime == nil)

        self.terminalID = terminalID
        self.runtime = runtime
        self.isBusy = isBusy
        self.isPrimaryFocus = isPrimaryFocus
        self.onFocusRequested = onFocusRequested
        self.onSendToComposer = onSendToComposer
        self.onSnapshotChanged = onSnapshotChanged

        if scaleChanged {
            self.fontScale = fontScale
            rebuildFonts(scale: fontScale)
            lastReportedCols = 0
            lastReportedRows = 0
            needsDisplay = true
        }

        if terminalChanged {
            latestSnapshot = nil
            lastRenderSignature = nil
            clearSelection()
            scrollAccumulator = 0
            lastReportedCols = 0
            lastReportedRows = 0
            lastInteractionAt = .now
            needsDisplay = true
        }

        recalculateGridAndResizeIfNeeded()

        if terminalChanged || runtimeChanged || pollTask == nil {
            restartPollLoop()
        }

        if isPrimaryFocus, window != nil, terminalChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if !(window.firstResponder is NSTextView) {
                    window.makeFirstResponder(self)
                }
            }
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            recalculateGridAndResizeIfNeeded()
            restartPollLoop()
            if isPrimaryFocus {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.window else { return }
                    window.makeFirstResponder(self)
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        lastRenderSignature = nil
        Task { await pollViewportOnce(forceRedraw: true) }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recalculateGridAndResizeIfNeeded()
    }

    override public func layout() {
        super.layout()
        recalculateGridAndResizeIfNeeded()
    }

    override public func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            lastInteractionAt = .now
            needsDisplay = true
        }
        return accepted
    }

    override public func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            needsDisplay = true
        }
        return resigned
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
        if !jumpToBottomRect.isEmpty {
            addCursorRect(jumpToBottomRect, cursor: .pointingHand)
        }
    }

    // MARK: - Font Metrics & Grid Sizing

    private func rebuildFonts(scale: Double) {
        let clampedScale = max(0.8, min(1.5, scale))
        let pointSize = CGFloat(12.5 * clampedScale)
        let reg = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let bld = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)
        let fm = NSFontManager.shared
        let ital = fm.convert(reg, toHaveTrait: .italicFontMask)
        let bldItal = fm.convert(bld, toHaveTrait: .italicFontMask)

        self.regularFont = reg
        self.boldFont = bld
        self.italicFont = ital
        self.boldItalicFont = bldItal

        let sampleWidth = ("M" as NSString).size(withAttributes: [.font: reg]).width
        self.cellWidth = max(6.0, sampleWidth)
        let rawLineHeight = reg.ascender - reg.descender + max(0, reg.leading)
        self.cellHeight = max(13.0, ceil(rawLineHeight + 2.0))
        self.baselineOffset = ceil(reg.ascender + 1.0)
    }

    private func computedGridDimensions() -> (cols: Int, rows: Int) {
        let usableWidth = max(0, bounds.width - horizontalInset * 2)
        let usableHeight = max(0, bounds.height - verticalInset * 2)
        let cols = max(20, Int(floor(usableWidth / max(1, cellWidth))))
        let rows = max(4, Int(floor(usableHeight / max(1, cellHeight))))
        return (cols, rows)
    }

    private func recalculateGridAndResizeIfNeeded() {
        guard bounds.width > 40, bounds.height > 30 else { return }
        guard !terminalID.isEmpty, let runtime else { return }
        let (cols, rows) = computedGridDimensions()
        guard terminalID != lastResizedTerminalID || cols != lastReportedCols || rows != lastReportedRows else {
            return
        }
        lastResizedTerminalID = terminalID
        lastReportedCols = cols
        lastReportedRows = rows
        let targetID = terminalID
        Task { [weak self] in
            try? await runtime.resizeTerminal(id: targetID, cols: cols, rows: rows)
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    // MARK: - Adaptive Viewport Polling

    private func effectiveIsDarkMode() -> Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func restartPollLoop() {
        pollTask?.cancel()
        guard window != nil, !terminalID.isEmpty, runtime != nil else {
            pollTask = nil
            return
        }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollViewportOnce(forceRedraw: true)
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - self.lastInteractionAt
                let isFocused = self.window?.firstResponder === self && (self.window?.isKeyWindow ?? false)
                let delayMs: Int
                if elapsed < .seconds(2) || self.isBusy {
                    delayMs = 24 // ~42 fps while active or running foreground process
                } else if isFocused {
                    delayMs = 50 // 20 fps while idle & focused
                } else {
                    delayMs = 150 // ~6.6 fps while unfocused & idle
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { break }
                await self.pollViewportOnce(forceRedraw: false)
            }
        }
    }

    public func pollViewportOnce(forceRedraw: Bool = false) async {
        guard let runtime, !terminalID.isEmpty else { return }
        let targetID = terminalID
        let isDark = effectiveIsDarkMode()
        guard let snapshot = try? await runtime.readTerminalViewport(id: targetID, dark: isDark) else {
            return
        }
        guard self.terminalID == targetID else { return }

        let sig = RenderSignature(
            terminalID: targetID,
            revision: snapshot.revision,
            displayOffset: snapshot.displayOffset,
            cursorRow: snapshot.cursorRow,
            cursorCol: snapshot.cursorCol,
            cursorVisible: snapshot.cursorVisible,
            cursorShape: snapshot.cursorShape,
            isDark: isDark,
            cols: snapshot.cols,
            rows: snapshot.rows
        )

        self.latestSnapshot = snapshot
        self.onSnapshotChanged?(snapshot)

        if forceRedraw || sig != lastRenderSignature {
            lastRenderSignature = sig
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    // MARK: - High-DPI Drawing

    override public func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveIsDarkMode()
        let defaultBG = Self.defaultBackgroundColor
        let defaultFG = Self.defaultForegroundColor

        defaultBG.setFill()
        dirtyRect.fill()

        guard let snapshot = latestSnapshot else {
            drawPlaceholderState(isDark: isDark)
            return
        }

        let normalizedSel = normalizedSelection()
        let lines = snapshot.lines

        // 1. Background Rects for Styled Runs
        for (rowIdx, line) in lines.enumerated() {
            let rowY = verticalInset + CGFloat(rowIdx) * cellHeight
            if rowY + cellHeight < dirtyRect.minY || rowY > dirtyRect.maxY { continue }

            var trackedCol = 0
            for (runIdx, run) in line.runs.enumerated() {
                let startCol = (runIdx > 0 && run.id == 0) ? trackedCol : run.id
                let colWidth = max(1, run.columnCount)
                defer { trackedCol = startCol + colWidth }

                let resolvedBG: NSColor? = {
                    if run.inverse {
                        return colorFromRGB(run.foregroundRGB) ?? defaultFG
                    }
                    if let bg = colorFromRGB(run.backgroundRGB), !colorsRoughlyEqual(bg, defaultBG) {
                        return bg
                    }
                    return nil
                }()

                if let resolvedBG {
                    let bgRect = NSRect(
                        x: horizontalInset + CGFloat(startCol) * cellWidth,
                        y: rowY,
                        width: CGFloat(colWidth) * cellWidth,
                        height: cellHeight
                    )
                    resolvedBG.setFill()
                    bgRect.fill()
                }
            }
        }

        // 2. Selection Highlight Rectangles
        if let (selStart, selEnd) = normalizedSel {
            let selectionColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(isDark ? 0.55 : 0.45)
            selectionColor.setFill()
            let maxCols = max(snapshot.cols, computedGridDimensions().cols)
            let firstRow = max(0, selStart.row)
            let lastRow = min(max(0, lines.count - 1), selEnd.row)
            if firstRow <= lastRow, !lines.isEmpty {
                for row in firstRow...lastRow {
                    let rowStartCol = (row == selStart.row) ? max(0, selStart.col) : 0
                    let rowEndCol = (row == selEnd.row) ? min(maxCols, selEnd.col) : maxCols
                    guard rowEndCol > rowStartCol else { continue }
                    let selRect = NSRect(
                        x: horizontalInset + CGFloat(rowStartCol) * cellWidth,
                        y: verticalInset + CGFloat(row) * cellHeight,
                        width: CGFloat(rowEndCol - rowStartCol) * cellWidth,
                        height: cellHeight
                    )
                    selRect.fill()
                }
            }
        }

        // 3. Text Runs
        for (rowIdx, line) in lines.enumerated() {
            let rowY = verticalInset + CGFloat(rowIdx) * cellHeight
            if rowY + cellHeight < dirtyRect.minY || rowY > dirtyRect.maxY { continue }

            var trackedCol = 0
            for (runIdx, run) in line.runs.enumerated() {
                let startCol = (runIdx > 0 && run.id == 0) ? trackedCol : run.id
                let colWidth = max(1, run.columnCount)
                defer { trackedCol = startCol + colWidth }

                guard !run.text.trimmingCharacters(in: .whitespaces).isEmpty || run.underline || run.strikethrough || run.linkURL != nil else {
                    continue
                }

                var fg: NSColor
                if run.inverse {
                    fg = colorFromRGB(run.backgroundRGB) ?? defaultBG
                } else {
                    fg = colorFromRGB(run.foregroundRGB) ?? defaultFG
                }
                if run.dim {
                    fg = fg.withAlphaComponent(0.58)
                }

                let font = selectFont(bold: run.bold, italic: run.italic)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: fg,
                ]
                if run.underline || run.linkURL != nil {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if run.strikethrough {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }

                let drawPoint = NSPoint(
                    x: horizontalInset + CGFloat(startCol) * cellWidth,
                    y: rowY + (cellHeight - baselineOffset) * 0.15
                )
                (run.text as NSString).draw(at: drawPoint, withAttributes: attrs)
            }
        }

        // 4. Cursor Rendering
        if snapshot.cursorVisible && snapshot.atBottom && snapshot.exitCode == nil {
            let cRow = snapshot.cursorRow
            let cCol = snapshot.cursorCol
            if cRow >= 0, cRow < max(snapshot.rows, lines.count + 1), cCol >= 0 {
                let cursorRect = NSRect(
                    x: horizontalInset + CGFloat(cCol) * cellWidth,
                    y: verticalInset + CGFloat(cRow) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                let cursorTint = Self.cursorTintColor
                let isFocused = (window?.firstResponder === self) && (window?.isKeyWindow ?? false)

                let shape = snapshot.cursorShape.lowercased()
                if !isFocused {
                    cursorTint.setStroke()
                    let strokeRect = cursorRect.insetBy(dx: 0.5, dy: 0.5)
                    let path = NSBezierPath(rect: strokeRect)
                    path.lineWidth = 1.0
                    path.stroke()
                } else if shape.contains("beam") || shape.contains("bar") {
                    let beamRect = NSRect(
                        x: cursorRect.minX,
                        y: cursorRect.minY + 1,
                        width: 2.0,
                        height: max(2, cursorRect.height - 2)
                    )
                    cursorTint.setFill()
                    beamRect.fill()
                } else if shape.contains("underline") {
                    let lineRect = NSRect(
                        x: cursorRect.minX,
                        y: cursorRect.maxY - 2.0,
                        width: cursorRect.width,
                        height: 2.0
                    )
                    cursorTint.setFill()
                    lineRect.fill()
                } else {
                    cursorTint.setFill()
                    cursorRect.fill()
                    // Draw character under block cursor in contrasting color
                    let charUnderCursor = characterAt(row: cRow, col: cCol, in: lines)
                    if charUnderCursor != " " {
                        let invColor = isDark ? defaultBG : NSColor.white
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: regularFont,
                            .foregroundColor: invColor,
                        ]
                        let pt = NSPoint(
                            x: cursorRect.minX,
                            y: cursorRect.minY + (cellHeight - baselineOffset) * 0.15
                        )
                        (String(charUnderCursor) as NSString).draw(at: pt, withAttributes: attrs)
                    }
                }
            }
        }

        // 5. Scrollback Position Pill & Right-Edge Scroll Thumb
        jumpToBottomRect = .zero
        if snapshot.historySize > 0 {
            drawScrollbarThumb(snapshot: snapshot, isDark: isDark)
        }
        if !snapshot.atBottom && snapshot.displayOffset > 0 {
            drawJumpToBottomBadge(offset: snapshot.displayOffset, isDark: isDark)
        }
    }

    private func drawPlaceholderState(isDark: Bool) {
        let msg = terminalID.isEmpty ? "Starting shell…" : "Connecting PTY…"
        let color = isDark ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: regularFont,
            .foregroundColor: color,
        ]
        (msg as NSString).draw(at: NSPoint(x: horizontalInset, y: verticalInset + 2), withAttributes: attrs)
    }

    private func drawScrollbarThumb(snapshot: TerminalViewportSnapshot, isDark: Bool) {
        let totalLines = CGFloat(max(1, snapshot.historySize + snapshot.rows))
        let visibleLines = CGFloat(max(1, snapshot.rows))
        guard totalLines > visibleLines else { return }

        let trackHeight = max(20, bounds.height - 8)
        let thumbHeight = max(20, (visibleLines / totalLines) * trackHeight)
        let maxOffset = CGFloat(max(1, snapshot.historySize))
        let fractionFromBottom = min(1, max(0, CGFloat(snapshot.displayOffset) / maxOffset))
        let thumbY = 4 + (1.0 - fractionFromBottom) * (trackHeight - thumbHeight)

        let thumbRect = NSRect(x: bounds.maxX - 7, y: thumbY, width: 4, height: thumbHeight)
        let thumbColor = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(snapshot.atBottom ? 0.14 : 0.34)
        thumbColor.setFill()
        NSBezierPath(roundedRect: thumbRect, xRadius: 2, yRadius: 2).fill()
    }

    private func drawJumpToBottomBadge(offset: Int, isDark: Bool) {
        let label = "↓ \(offset) lines above · Jump to Live"
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textColor = isDark ? NSColor.white : NSColor.black
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 10
        let padY: CGFloat = 4
        let pillWidth = textSize.width + padX * 2
        let pillHeight = textSize.height + padY * 2
        let pillRect = NSRect(
            x: bounds.maxX - pillWidth - 14,
            y: bounds.maxY - pillHeight - 10,
            width: pillWidth,
            height: pillHeight
        )
        jumpToBottomRect = pillRect

        let bg = Self.jumpBadgeBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        (label as NSString).draw(
            at: NSPoint(x: pillRect.minX + padX, y: pillRect.minY + padY),
            withAttributes: attrs
        )
    }

    private func selectFont(bold: Bool, italic: Bool) -> NSFont {
        switch (bold, italic) {
        case (true, true): boldItalicFont
        case (true, false): boldFont
        case (false, true): italicFont
        case (false, false): regularFont
        }
    }

    private func colorFromRGB(_ rgb: [UInt8]?) -> NSColor? {
        guard let rgb, rgb.count >= 3 else { return nil }
        return NSColor(
            srgbRed: CGFloat(rgb[0]) / 255.0,
            green: CGFloat(rgb[1]) / 255.0,
            blue: CGFloat(rgb[2]) / 255.0,
            alpha: 1.0
        )
    }

    private func colorsRoughlyEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ca = a.usingColorSpace(.sRGB), let cb = b.usingColorSpace(.sRGB) else { return false }
        return abs(ca.redComponent - cb.redComponent) < 0.02
            && abs(ca.greenComponent - cb.greenComponent) < 0.02
            && abs(ca.blueComponent - cb.blueComponent) < 0.02
    }

    private func characterAt(row: Int, col: Int, in lines: [TerminalViewportLine]) -> Character {
        guard row >= 0, row < lines.count else { return " " }
        let chars = Array(lines[row].text)
        guard col >= 0, col < chars.count else { return " " }
        return chars[col]
    }

    // MARK: - Mouse Selection, Link Click & Context Menu

    private func gridPosition(for event: NSEvent) -> GridPosition {
        let local = convert(event.locationInWindow, from: nil)
        let rawCol = Int(floor((local.x - horizontalInset) / max(1, cellWidth)))
        let rawRow = Int(floor((local.y - verticalInset) / max(1, cellHeight)))
        let maxRow = max(0, (latestSnapshot?.lines.count ?? 1) - 1)
        let maxCol = max(0, latestSnapshot?.cols ?? computedGridDimensions().cols)
        return GridPosition(
            row: min(max(0, rawRow), maxRow),
            col: min(max(0, rawCol), maxCol)
        )
    }

    private func linkAt(position: GridPosition) -> URL? {
        guard let snapshot = latestSnapshot,
              position.row >= 0,
              position.row < snapshot.lines.count
        else { return nil }
        let line = snapshot.lines[position.row]
        var trackedCol = 0
        for (idx, run) in line.runs.enumerated() {
            let startCol = (idx > 0 && run.id == 0) ? trackedCol : run.id
            let endCol = startCol + max(1, run.columnCount)
            trackedCol = endCol
            if position.col >= startCol && position.col < endCol,
               let rawURL = run.linkURL,
               let url = URL(string: rawURL)
            {
                return url
            }
        }
        return nil
    }

    override public func mouseDown(with event: NSEvent) {
        lastInteractionAt = .now
        onFocusRequested?()
        window?.makeFirstResponder(self)

        let local = convert(event.locationInWindow, from: nil)
        if !jumpToBottomRect.isEmpty && jumpToBottomRect.contains(local) {
            scrollToBottom()
            return
        }

        let pos = gridPosition(for: event)
        if event.modifierFlags.contains(.command), let url = linkAt(position: pos) {
            NSWorkspace.shared.open(url)
            return
        }

        if event.clickCount >= 3 {
            let maxCol = latestSnapshot?.cols ?? computedGridDimensions().cols
            selectionAnchor = GridPosition(row: pos.row, col: 0)
            selectionHead = GridPosition(row: pos.row, col: maxCol)
            isDraggingSelection = false
            needsDisplay = true
            return
        }

        if event.clickCount == 2 {
            selectWord(at: pos)
            isDraggingSelection = false
            needsDisplay = true
            return
        }

        if event.modifierFlags.contains(.shift), selectionAnchor != nil {
            selectionHead = pos
        } else {
            selectionAnchor = pos
            selectionHead = pos
        }
        isDraggingSelection = true
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDraggingSelection else { return }
        lastInteractionAt = .now
        selectionHead = gridPosition(for: event)
        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        if isDraggingSelection {
            isDraggingSelection = false
            if selectionAnchor == selectionHead && event.clickCount == 1 {
                clearSelection()
            }
        }
    }

    private func selectWord(at pos: GridPosition) {
        guard let snapshot = latestSnapshot,
              pos.row >= 0,
              pos.row < snapshot.lines.count
        else { return }
        let chars = Array(snapshot.lines[pos.row].text)
        guard !chars.isEmpty, pos.col < chars.count else {
            selectionAnchor = pos
            selectionHead = GridPosition(row: pos.row, col: pos.col + 1)
            return
        }
        let isWordChar: (Character) -> Bool = { ch in
            ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." || ch == "/"
        }
        let targetIsWord = isWordChar(chars[pos.col])
        var left = pos.col
        while left > 0 && isWordChar(chars[left - 1]) == targetIsWord && !chars[left - 1].isWhitespace {
            left -= 1
        }
        var right = pos.col + 1
        while right < chars.count && isWordChar(chars[right]) == targetIsWord && !chars[right].isWhitespace {
            right += 1
        }
        selectionAnchor = GridPosition(row: pos.row, col: left)
        selectionHead = GridPosition(row: pos.row, col: right)
    }

    public func clearSelection() {
        selectionAnchor = nil
        selectionHead = nil
        needsDisplay = true
    }

    private func normalizedSelection() -> (GridPosition, GridPosition)? {
        guard let a = selectionAnchor, let b = selectionHead, a != b else { return nil }
        return a < b ? (a, b) : (b, a)
    }

    public var hasSelection: Bool {
        normalizedSelection() != nil
    }

    public func selectedText() -> String? {
        guard let (start, end) = normalizedSelection(),
              let snapshot = latestSnapshot,
              !snapshot.lines.isEmpty
        else { return nil }

        let firstRow = max(0, start.row)
        let lastRow = min(snapshot.lines.count - 1, end.row)
        guard firstRow <= lastRow else { return nil }

        var output = ""
        for row in firstRow...lastRow {
            let line = snapshot.lines[row]
            let chars = Array(line.text)
            let fromCol = (row == firstRow) ? min(max(0, start.col), chars.count) : 0
            let toCol = (row == lastRow) ? min(max(0, end.col), chars.count) : chars.count
            let slice = fromCol < toCol ? String(chars[fromCol..<toCol]) : ""
            if row < lastRow {
                if line.wrapped {
                    output += slice
                } else {
                    output += slice.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + "\n"
                }
            } else {
                output += slice.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
        }
        return output.isEmpty ? nil : output
    }

    public func viewportOutputText() -> String {
        guard let snapshot = latestSnapshot else { return "" }
        var trimmedLines = snapshot.lines.map {
            $0.text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        while let last = trimmedLines.last, last.isEmpty {
            trimmedLines.removeLast()
        }
        return trimmedLines.joined(separator: "\n")
    }

    // MARK: - Copy, Paste, Select All & Context Menu

    @objc public func copy(_ sender: Any?) {
        guard let text = selectedText(), !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc public func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty else { return }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        sendInputToPTY(normalized)
    }

    override public func selectAll(_ sender: Any?) {
        guard let snapshot = latestSnapshot, !snapshot.lines.isEmpty else { return }
        selectionAnchor = GridPosition(row: 0, col: 0)
        selectionHead = GridPosition(row: snapshot.lines.count - 1, col: snapshot.cols)
        needsDisplay = true
    }

    @objc private func sendSelectionToComposerAction(_ sender: Any?) {
        if let sel = selectedText(), !sel.isEmpty {
            onSendToComposer?(sel)
        }
    }

    @objc private func sendViewportToComposerAction(_ sender: Any?) {
        let text = viewportOutputText()
        if !text.isEmpty {
            onSendToComposer?(text)
        }
    }

    @objc private func clearTerminalAction(_ sender: Any?) {
        guard let runtime, !terminalID.isEmpty else { return }
        let id = terminalID
        Task { [weak self] in
            try? await runtime.clearTerminal(id: id)
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    override public func menu(for event: NSEvent) -> NSMenu? {
        onFocusRequested?()
        window?.makeFirstResponder(self)

        let menu = NSMenu(title: "Terminal")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        pasteItem.target = self
        pasteItem.isEnabled = (NSPasteboard.general.string(forType: .string)?.isEmpty == false)
        menu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        menu.addItem(.separator())

        let sendSelItem = NSMenuItem(
            title: "Send Selection to Composer",
            action: #selector(sendSelectionToComposerAction(_:)),
            keyEquivalent: ""
        )
        sendSelItem.target = self
        sendSelItem.isEnabled = hasSelection
        menu.addItem(sendSelItem)

        let sendAllItem = NSMenuItem(
            title: "Send Viewport Output to Composer",
            action: #selector(sendViewportToComposerAction(_:)),
            keyEquivalent: ""
        )
        sendAllItem.target = self
        sendAllItem.isEnabled = !viewportOutputText().isEmpty
        menu.addItem(sendAllItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearTerminalAction(_:)), keyEquivalent: "k")
        clearItem.target = self
        menu.addItem(clearItem)

        return menu
    }

    // MARK: - Mouse Wheel Scrollback

    override public func scrollWheel(with event: NSEvent) {
        lastInteractionAt = .now
        guard let runtime, !terminalID.isEmpty else { return }

        let deltaPoints: CGFloat = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * cellHeight * 0.85

        scrollAccumulator += deltaPoints
        let lineSteps = Int((scrollAccumulator / max(1, cellHeight)).rounded(.towardZero))
        guard lineSteps != 0 else { return }
        scrollAccumulator -= CGFloat(lineSteps) * cellHeight

        let targetID = terminalID
        let cachedRev = latestSnapshot?.revision
        Task { [weak self] in
            do {
                try await runtime.scrollTerminal(id: targetID, delta: lineSteps, revision: cachedRev)
            } catch {
                try? await runtime.scrollTerminal(id: targetID, delta: lineSteps, revision: nil)
            }
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    private func scrollToBottom() {
        guard let runtime, !terminalID.isEmpty, let offset = latestSnapshot?.displayOffset, offset > 0 else { return }
        let targetID = terminalID
        Task { [weak self] in
            try? await runtime.scrollTerminal(id: targetID, delta: -offset - 20, revision: nil)
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    // MARK: - Keyboard Shortcuts & Full PTY Input Translation

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                if hasSelection {
                    copy(nil)
                    return true
                }
            case "v":
                paste(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "k":
                clearTerminalAction(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        lastInteractionAt = .now
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        // Shift+PageUp / Shift+PageDown for scrollback navigation
        if flags.contains(.shift) {
            if event.keyCode == 116 { // PageUp
                let page = max(1, (latestSnapshot?.rows ?? 20) - 2)
                scrollByLines(page)
                return
            } else if event.keyCode == 121 { // PageDown
                let page = max(1, (latestSnapshot?.rows ?? 20) - 2)
                scrollByLines(-page)
                return
            }
        }

        if let translated = translateKeyEvent(event, flags: flags) {
            if hasSelection {
                clearSelection()
            }
            sendInputToPTY(translated)
        }
    }

    private func scrollByLines(_ delta: Int) {
        guard let runtime, !terminalID.isEmpty else { return }
        let targetID = terminalID
        Task { [weak self] in
            try? await runtime.scrollTerminal(id: targetID, delta: delta, revision: nil)
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    private func sendInputToPTY(_ text: String) {
        guard let runtime, !terminalID.isEmpty, !text.isEmpty else { return }
        let targetID = terminalID
        Task { [weak self] in
            try? await runtime.sendTerminalInput(id: targetID, data: text)
            try? await Task.sleep(for: .milliseconds(12))
            await self?.pollViewportOnce(forceRedraw: true)
        }
    }

    private func translateKeyEvent(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> String? {
        let hasCtrl = flags.contains(.control)
        let hasOpt = flags.contains(.option)
        let hasShift = flags.contains(.shift)

        // 1. Special KeyCodes & Function Keys
        switch event.keyCode {
        case 36, 76: // Return / Keypad Enter
            return hasOpt ? "\u{1b}\r" : "\r"
        case 51: // Delete (Backspace)
            if hasCtrl { return "\u{08}" }
            return hasOpt ? "\u{1b}\u{7f}" : "\u{7f}"
        case 117: // Forward Delete
            return "\u{1b}[3~"
        case 48: // Tab
            return hasShift ? "\u{1b}[Z" : "\t"
        case 53: // Escape
            return "\u{1b}"
        case 126: // Up Arrow
            return csiCursorSequence(finalChar: "A", shift: hasShift, option: hasOpt, control: hasCtrl)
        case 125: // Down Arrow
            return csiCursorSequence(finalChar: "B", shift: hasShift, option: hasOpt, control: hasCtrl)
        case 124: // Right Arrow
            if hasOpt && !hasShift && !hasCtrl { return "\u{1b}f" }
            return csiCursorSequence(finalChar: "C", shift: hasShift, option: hasOpt, control: hasCtrl)
        case 123: // Left Arrow
            if hasOpt && !hasShift && !hasCtrl { return "\u{1b}b" }
            return csiCursorSequence(finalChar: "D", shift: hasShift, option: hasOpt, control: hasCtrl)
        case 115: // Home
            return "\u{1b}[H"
        case 119: // End
            return "\u{1b}[F"
        case 116: // PageUp
            return "\u{1b}[5~"
        case 121: // PageDown
            return "\u{1b}[6~"
        case 122: return "\u{1b}OP"   // F1
        case 120: return "\u{1b}OQ"   // F2
        case 99:  return "\u{1b}OR"   // F3
        case 118: return "\u{1b}OS"   // F4
        case 96:  return "\u{1b}[15~" // F5
        case 97:  return "\u{1b}[17~" // F6
        case 98:  return "\u{1b}[18~" // F7
        case 100: return "\u{1b}[19~" // F8
        case 101: return "\u{1b}[20~" // F9
        case 109: return "\u{1b}[21~" // F10
        case 103: return "\u{1b}[23~" // F11
        case 111: return "\u{1b}[24~" // F12
        default:
            break
        }

        // 2. Control + Key (Ctrl+A..Z -> 0x01..0x1A, Ctrl+Space -> 0x00, etc.)
        if hasCtrl, let raw = event.charactersIgnoringModifiers?.lowercased(), let scalar = raw.unicodeScalars.first {
            let v = scalar.value
            if v >= 0x61 && v <= 0x7A { // 'a'...'z'
                let ctrlByte = UInt8(v - 0x60)
                let seq = String(UnicodeScalar(ctrlByte))
                return hasOpt ? "\u{1b}\(seq)" : seq
            }
            switch scalar {
            case " ", "@", "2": return "\u{00}"
            case "[", "3":      return "\u{1b}"
            case "\\", "4":     return "\u{1c}"
            case "]", "5":      return "\u{1d}"
            case "^", "6":      return "\u{1e}"
            case "_", "/", "7": return "\u{1f}"
            case "?":           return "\u{7f}"
            default:            break
            }
        }

        // 3. Option-as-Meta (ESC prefix + unmodified/shifted character)
        if hasOpt, let base = event.charactersIgnoringModifiers, !base.isEmpty {
            return "\u{1b}\(base)"
        }

        // 4. Printable Unicode Characters
        if let chars = event.characters, !chars.isEmpty {
            return chars
        }
        return nil
    }

    private func csiCursorSequence(finalChar: String, shift: Bool, option: Bool, control: Bool) -> String {
        var mod = 1
        if shift { mod += 1 }
        if option { mod += 2 }
        if control { mod += 4 }
        if mod == 1 {
            return "\u{1b}[\(finalChar)"
        }
        return "\u{1b}[1;\(mod)\(finalChar)"
    }
}
