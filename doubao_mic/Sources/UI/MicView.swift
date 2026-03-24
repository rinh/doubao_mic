import AppKit

final class MicView: NSView {

    private let micIcon: NSImageView
    private let barWidth: CGFloat = 5
    private let barSpacing: CGFloat = 4
    private let barBottomInset: CGFloat = 10
    private let barColor = NSColor.systemGreen

    private var waveformModel = WaveformModel()
    private var barLayers: [CAShapeLayer] = []
    private var currentBarHeights: [CGFloat] = []

    internal var waveBarCount: Int {
        barLayers.count
    }

    internal var waveBarHeights: [CGFloat] {
        currentBarHeights
    }

    override init(frame frameRect: NSRect) {
        micIcon = NSImageView(frame: .zero)
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        micIcon = NSImageView(frame: .zero)
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = bounds.width / 2

        if let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone") {
            micIcon.image = micImage
            micIcon.contentTintColor = .white
            micIcon.imageScaling = .scaleProportionallyUpOrDown
        }

        micIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(micIcon)

        NSLayoutConstraint.activate([
            micIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            micIcon.widthAnchor.constraint(equalToConstant: 36),
            micIcon.heightAnchor.constraint(equalToConstant: 36)
        ])

        createBarLayers()
        applyBarHeights(waveformModel.reset(), animated: false)

        setAccessibilityIdentifier("mic_waveform_view")
    }

    private func createBarLayers() {
        for index in 0..<waveformModel.barCount {
            let bar = CAShapeLayer()
            bar.fillColor = barColor.withAlphaComponent(index == 1 || index == 2 ? 0.92 : 0.68).cgColor
            bar.strokeColor = NSColor.clear.cgColor
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        applyBarHeights(currentBarHeights.isEmpty ? waveformModel.reset() : currentBarHeights, animated: false)
    }

    func updateLevel(_ level: Float) {
        let heights = waveformModel.update(level: level)
        applyBarHeights(heights, animated: true)
    }

    func reset() {
        applyBarHeights(waveformModel.reset(), animated: true)
    }

    private func applyBarHeights(_ heights: [CGFloat], animated: Bool) {
        guard heights.count == barLayers.count else { return }

        currentBarHeights = heights

        let totalWidth = (CGFloat(barLayers.count) * barWidth) + (CGFloat(barLayers.count - 1) * barSpacing)
        let startX = bounds.midX - totalWidth / 2

        for (index, height) in heights.enumerated() {
            let clampedHeight = max(waveformModel.minHeight, min(waveformModel.maxHeight, height))
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            let y = barBottomInset
            let rect = CGRect(x: x, y: y, width: barWidth, height: clampedHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)

            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.08)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                barLayers[index].path = path
                CATransaction.commit()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                barLayers[index].path = path
                CATransaction.commit()
            }
        }

        updateAccessibilityWaveState()
    }

    private func updateAccessibilityWaveState() {
        let value = currentBarHeights.map { String(format: "%.2f", Double($0)) }.joined(separator: ",")
        setAccessibilityValue(value)
    }
}
