import AppKit
import os.log

enum DraftPhase {
    case draft
    case final
}

struct DraftState {
    let text: String
    let phase: DraftPhase
    let updatedAt: Date
}

final class FloatingWindowController: NSWindowController {
    private static let draftWidthRatioCap: CGFloat = 0.5
    private static let draftFixedMaxWidth: CGFloat = 720

    private(set) var micView: MicView!
    private let logger = AppLogger.make(.ui)
    private var draftWindow: DraftWindow?
    private var draftState: DraftState?

    convenience init() {
        let window = FloatingWindow()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window as? FloatingWindow else { return }

        micView = MicView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        micView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(micView)

        NSLayoutConstraint.activate([
            micView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            micView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            micView.widthAnchor.constraint(equalToConstant: 80),
            micView.heightAnchor.constraint(equalToConstant: 80)
        ])

        window.contentView = contentView
    }

    func show() {
        positionWindowAtBottomCenter()
        window?.orderFrontRegardless()
        showDraftWindow()
    }

    func hide() {
        window?.orderOut(nil)
        micView.reset()
        hideDraftWindow()
        logger.debug("Floating window hidden")
    }

    func beginSessionScreenLock() {
        logger.debug("Session lock API ignored: using active-space targeting")
    }

    func endSessionScreenLock() {
        logger.debug("Session unlock API ignored: using active-space targeting")
    }

    func updateAudioLevel(_ level: Float) {
        micView.updateLevel(level)
    }

    func updateDraftText(_ text: String, phase: DraftPhase) {
        let state = DraftState(text: text, phase: phase, updatedAt: Date())
        draftState = state
        ensureDraftWindow()
        draftWindow?.update(state: state)
        recalculateDraftWindowSize()
        positionDraftWindow()
        showDraftWindow()
    }

    // Reset the draft window geometry at the start of each recording session
    // so previous session expansion does not leak into the next trigger.
    func resetDraftWindowToDefaultSize() {
        ensureDraftWindow()
        draftWindow?.resetToDefaultSize()
        positionDraftWindow()
    }

    // UI-test only helpers for deterministic draft window sizing assertions.
    func setDraftWindowWidthForTesting(_ width: CGFloat) {
        ensureDraftWindow()
        draftWindow?.setWidthForTesting(width)
        positionDraftWindow()
    }

    func currentDraftWindowWidthForTesting() -> CGFloat {
        ensureDraftWindow()
        return currentDraftWindowContentWidthForTesting()
    }

    func currentDraftWindowHeightForTesting() -> CGFloat {
        ensureDraftWindow()
        return currentDraftWindowContentHeightForTesting()
    }

    func currentDraftWindowContentWidthForTesting() -> CGFloat {
        ensureDraftWindow()
        if let contentWidth = draftWindow?.contentView?.frame.width {
            return contentWidth
        }
        if let draftWindow {
            return draftWindow.contentRect(forFrameRect: draftWindow.frame).width
        }
        return 0
    }

    func currentDraftWindowContentHeightForTesting() -> CGFloat {
        ensureDraftWindow()
        if let contentHeight = draftWindow?.contentView?.frame.height {
            return contentHeight
        }
        if let draftWindow {
            return draftWindow.contentRect(forFrameRect: draftWindow.frame).height
        }
        return 0
    }

    func currentDraftWindowFrameWidthForTesting() -> CGFloat {
        ensureDraftWindow()
        return draftWindow?.frame.width ?? 0
    }

    func currentDraftWindowFrameHeightForTesting() -> CGFloat {
        ensureDraftWindow()
        return draftWindow?.frame.height ?? 0
    }

    func currentDraftWindowFrameMinXForTesting() -> CGFloat {
        ensureDraftWindow()
        return draftWindow?.frame.minX ?? 0
    }

    func currentDraftWindowFrameMinYForTesting() -> CGFloat {
        ensureDraftWindow()
        return draftWindow?.frame.minY ?? 0
    }

    func currentDraftWindowCenterXForTesting() -> CGFloat {
        ensureDraftWindow()
        guard let frame = draftWindow?.frame else { return 0 }
        return frame.midX
    }

    func currentDraftWindowCapWidthForTesting() -> CGFloat {
        guard let screen = resolvedTargetScreen() else { return 0 }
        return draftMaxWidthCap(for: screen)
    }

    func currentDraftScreenVisibleWidthForTesting() -> CGFloat {
        resolvedScreenVisibleFrame()?.width ?? 0
    }

    func currentDraftScreenVisibleHeightForTesting() -> CGFloat {
        resolvedScreenVisibleFrame()?.height ?? 0
    }

    func currentDraftScreenMidXForTesting() -> CGFloat {
        resolvedScreenFrame()?.midX ?? 0
    }

    func currentScreenDebugForTesting() -> String {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens.enumerated().map { idx, screen in
            let f = screen.frame
            let v = screen.visibleFrame
            return "s\(idx):f(\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height)))v(\(Int(v.minX)),\(Int(v.minY)),\(Int(v.width)),\(Int(v.height)))"
        }.joined(separator: ",")

        let target = resolvedTargetScreen()
        let tf = target?.frame ?? .zero
        let tv = target?.visibleFrame ?? .zero
        let draftFrame = draftWindow?.frame ?? .zero
        let draftMid = NSPoint(x: draftFrame.midX, y: draftFrame.midY)
        let landed = NSScreen.screens.first(where: { NSMouseInRect(draftMid, $0.frame, false) })
        let lf = landed?.frame ?? .zero
        let lv = landed?.visibleFrame ?? .zero
        let source = currentScreenSourceForTesting()
        return "screenSource(\(source))|mouse(\(Int(mouse.x)),\(Int(mouse.y)))|targetF(\(Int(tf.minX)),\(Int(tf.minY)),\(Int(tf.width)),\(Int(tf.height)))|targetV(\(Int(tv.minX)),\(Int(tv.minY)),\(Int(tv.width)),\(Int(tv.height)))|draftF(\(Int(draftFrame.minX)),\(Int(draftFrame.minY)),\(Int(draftFrame.width)),\(Int(draftFrame.height)))|landedF(\(Int(lf.minX)),\(Int(lf.minY)),\(Int(lf.width)),\(Int(lf.height)))|landedV(\(Int(lv.minX)),\(Int(lv.minY)),\(Int(lv.width)),\(Int(lv.height)))|all[\(screens)]"
    }

    func currentScreenSourceForTesting() -> String {
        "activeSpace"
    }

    func isMicWindowVisibleForTesting() -> Bool {
        window?.isVisible ?? false
    }

    func isDraftWindowVisibleForTesting() -> Bool {
        draftWindow?.isVisible ?? false
    }

    func isAnyFloatingUIVisibleForTesting() -> Bool {
        isMicWindowVisibleForTesting() || isDraftWindowVisibleForTesting()
    }

    // UI/unit-test helper for deterministic sizing checks with a fixed max width.
    func updateDraftTextForTesting(_ text: String, phase: DraftPhase, maxWidth: CGFloat) {
        let state = DraftState(text: text, phase: phase, updatedAt: Date())
        draftState = state
        ensureDraftWindow()
        draftWindow?.update(state: state)
        draftWindow?.recalculateSize(maxWidth: maxWidth)
        positionDraftWindow()
        draftWindow?.orderFrontRegardless()
    }

    func showDraftWindow() {
        ensureDraftWindow()
        recalculateDraftWindowSize()
        positionDraftWindow()
        draftWindow?.orderFrontRegardless()
    }

    func hideDraftWindow() {
        draftWindow?.orderOut(nil)
    }

    private func positionWindowAtBottomCenter() {
        guard let window = window,
              let screen = resolvedTargetScreen() else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + 50

        window.setFrameOrigin(NSPoint(x: x, y: y))
        logger.info(
            "Mic window positioned on target screen: screenFrame=\(String(describing: screen.frame)), visibleFrame=\(String(describing: screenFrame)), origin=(\(x), \(y))"
        )
    }

    private func ensureDraftWindow() {
        if draftWindow == nil {
            draftWindow = DraftWindow()
            if let draftState {
                draftWindow?.update(state: draftState)
            }
        }
    }

    private func recalculateDraftWindowSize() {
        guard let draftWindow else { return }
        guard let screen = resolvedTargetScreen() else { return }
        let cap = draftMaxWidthCap(for: screen)
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        logger.info(
            "Draft sizing context: screenWidth=\(screenFrame.width), visibleWidth=\(visibleFrame.width), screenHeight=\(screenFrame.height), cap=\(cap)"
        )
        draftWindow.recalculateSize(maxWidth: cap)
    }

    private func resolvedTargetScreen() -> NSScreen? {
        preferredTargetScreen() ?? NSScreen.main
    }

    private func resolvedScreenVisibleFrame() -> NSRect? {
        resolvedTargetScreen()?.visibleFrame
    }

    private func resolvedScreenFrame() -> NSRect? {
        resolvedTargetScreen()?.frame
    }

    private func preferredTargetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main
    }

    private func positionDraftWindow() {
        guard let micWindow = window,
              let draftWindow else { return }
        let micFrame = micWindow.frame
        guard let screenVisibleFrame = resolvedScreenVisibleFrame(),
              let screenFrame = resolvedScreenFrame() else {
            return
        }
        let maxWidthCap = draftMaxWidthCap(for: resolvedTargetScreen())
        _ = draftWindow.enforceFrameWidthCap(maxWidth: maxWidthCap)
        var draftSize = draftWindow.frame.size

        let x = screenFrame.midX - draftSize.width / 2
        let defaultBelowY = micFrame.minY - draftSize.height - 8
        let fallbackAboveY = micFrame.maxY + 8
        let minY = screenVisibleFrame.minY + 4
        let maxY = screenVisibleFrame.maxY - draftSize.height - 4

        // Prefer below the mic window; if it doesn't fit, place it above.
        let preferredY = defaultBelowY >= minY ? defaultBelowY : fallbackAboveY
        let y = min(max(preferredY, minY), maxY)

        draftWindow.setFrameOrigin(NSPoint(x: x, y: y))
        if draftWindow.enforceFrameWidthCap(maxWidth: maxWidthCap) {
            draftSize = draftWindow.frame.size
            let reclampedX = screenFrame.midX - draftSize.width / 2
            draftWindow.setFrameOrigin(NSPoint(x: reclampedX, y: y))
        }

    }

    private func draftMaxWidthCap(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.draftFixedMaxWidth }
        let baseWidth = min(screen.frame.width, screen.visibleFrame.width)
        return min(baseWidth * Self.draftWidthRatioCap, Self.draftFixedMaxWidth)
    }

}

final class FloatingWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DraftWindow: NSPanel {
    private static let defaultFrameSize = NSSize(width: 360, height: 72)
    private static let minFrameWidth: CGFloat = 360
    private static let topInset: CGFloat = 10
    private static let bottomInset: CGFloat = 10
    private static let sideInset: CGFloat = 12
    private static let phaseToTextSpacing: CGFloat = 6

    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let phaseLabel = NSTextField(labelWithString: "")
    private let content = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 360, height: 72)))
    private let logger = AppLogger.make(.ui)
    private var cachedMaxWidthCap: CGFloat = 360

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultFrameSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.66).cgColor
        content.layer?.cornerRadius = 12

        phaseLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        phaseLabel.textColor = .systemGray
        phaseLabel.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textLabel.textColor = .white
        textLabel.lineBreakMode = .byCharWrapping
        textLabel.maximumNumberOfLines = 0
        if let cell = textLabel.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.usesSingleLineMode = false
            cell.truncatesLastVisibleLine = false
            cell.lineBreakMode = .byCharWrapping
        }
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(phaseLabel)
        content.addSubview(textLabel)
        NSLayoutConstraint.activate([
            phaseLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            phaseLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            phaseLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            textLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            textLabel.topAnchor.constraint(equalTo: phaseLabel.bottomAnchor, constant: 6),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -10)
        ])

        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(state: DraftState) {
        switch state.phase {
        case .draft:
            phaseLabel.stringValue = "Draft"
            phaseLabel.textColor = .systemOrange
        case .final:
            phaseLabel.stringValue = "Final"
            phaseLabel.textColor = .systemGreen
        }

        textLabel.stringValue = state.text.isEmpty ? "..." : state.text
    }

    func resetToDefaultSize() {
        applyContentSize(Self.defaultFrameSize, maxWidthCap: Self.defaultFrameSize.width)
    }

    func setWidthForTesting(_ width: CGFloat) {
        applyContentSize(NSSize(width: width, height: Self.defaultFrameSize.height), maxWidthCap: width)
    }

    func recalculateSize(maxWidth: CGFloat) {
        let boundedMaxWidth = max(1, maxWidth)
        let effectiveMinWidth = min(Self.minFrameWidth, boundedMaxWidth)
        cachedMaxWidthCap = boundedMaxWidth
        let text = textLabel.stringValue.isEmpty ? "..." : textLabel.stringValue
        let textFont = textLabel.font ?? NSFont.systemFont(ofSize: 14, weight: .regular)

        let singleLineWidth = ceil(
            (text as NSString).boundingRect(
                with: NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: textFont]
            ).width
        )
        let horizontalInsets = Self.sideInset * 2
        let targetWidth = min(
            boundedMaxWidth,
            max(effectiveMinWidth, singleLineWidth + horizontalInsets)
        )

        let textWidth = max(80, targetWidth - horizontalInsets)
        textLabel.preferredMaxLayoutWidth = textWidth
        let textHeight = measureWrappedTextHeight(text, width: textWidth, font: textFont)
        let phaseHeight = ceil(phaseLabel.intrinsicContentSize.height)
        let targetHeight = max(
            Self.defaultFrameSize.height,
            Self.topInset + phaseHeight + Self.phaseToTextSpacing + textHeight + Self.bottomInset
        )

        let size = NSSize(width: targetWidth, height: targetHeight)
        applyContentSize(size, maxWidthCap: boundedMaxWidth)
    }

    @discardableResult
    func enforceFrameWidthCap(maxWidth: CGFloat) -> Bool {
        let boundedMaxWidth = max(1, maxWidth)
        cachedMaxWidthCap = boundedMaxWidth
        let contentRect = contentRect(forFrameRect: frame)
        guard contentRect.width > boundedMaxWidth + 0.5 else { return false }
        let clamped = NSSize(width: boundedMaxWidth, height: contentRect.height)
        applyContentSize(clamped, maxWidthCap: boundedMaxWidth)
        return true
    }

    private func applyContentSize(_ size: NSSize, maxWidthCap: CGFloat) {
        let effectiveMinWidth = min(Self.minFrameWidth, maxWidthCap)
        let boundedWidth = min(max(effectiveMinWidth, size.width), maxWidthCap)
        let boundedSize = NSSize(width: boundedWidth, height: max(Self.defaultFrameSize.height, size.height))
        let frameRect = frameRect(forContentRect: NSRect(origin: .zero, size: boundedSize))
        var newFrame = frame
        newFrame.size = frameRect.size
        setFrame(newFrame, display: false)
        content.frame = NSRect(origin: .zero, size: boundedSize)
        logger.info(
            "Draft window size applied: cap=\(maxWidthCap), contentWidth=\(boundedSize.width), frameWidth=\(newFrame.size.width), height=\(boundedSize.height), textLength=\(textLabel.stringValue.count)"
        )
    }

    private func measureWrappedTextHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let storage = NSTextStorage(string: text, attributes: attrs)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byCharWrapping
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        _ = layoutManager.glyphRange(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }
}
