import CoreGraphics
import Foundation

struct WaveformModel {
    let barCount: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let attack: CGFloat
    let release: CGFloat

    private(set) var smoothedLevel: CGFloat = 0

    private let barGains: [CGFloat]

    init(
        barCount: Int = 4,
        minHeight: CGFloat = 4,
        maxHeight: CGFloat = 22,
        attack: CGFloat = 0.55,
        release: CGFloat = 0.25,
        barGains: [CGFloat] = [0.58, 1.0, 1.0, 0.58]
    ) {
        self.barCount = barCount
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.attack = attack
        self.release = release
        self.barGains = barGains
    }

    mutating func update(level: Float) -> [CGFloat] {
        let target = CGFloat(max(0, min(1, level)))
        if target >= smoothedLevel {
            smoothedLevel += (target - smoothedLevel) * attack
        } else {
            smoothedLevel += (target - smoothedLevel) * release
        }
        smoothedLevel = max(0, min(1, smoothedLevel))
        return makeHeights(for: smoothedLevel)
    }

    mutating func reset() -> [CGFloat] {
        smoothedLevel = 0
        return makeHeights(for: smoothedLevel)
    }

    private func makeHeights(for level: CGFloat) -> [CGFloat] {
        let span = maxHeight - minHeight
        return (0..<barCount).map { index in
            let gain = barGains[index]
            return minHeight + span * level * gain
        }
    }
}
