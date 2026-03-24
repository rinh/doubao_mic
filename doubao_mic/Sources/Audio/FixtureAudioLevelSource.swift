import AVFoundation
import Foundation

final class FixtureAudioLevelSource: AudioLevelSource {
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onPlaybackFinished: (() -> Void)?

    private(set) var isRecording = false
    private var timer: DispatchSourceTimer?
    private var levels: [Float] = []
    private var currentIndex = 0
    private let updateInterval: TimeInterval
    private let logger = AppLogger.make(.audio)

    init(fixtureURL: URL, updateInterval: TimeInterval = 0.05) {
        self.updateInterval = updateInterval
        self.levels = Self.loadLevels(from: fixtureURL)
    }

    func startRecording() {
        guard !isRecording else { return }
        guard !levels.isEmpty else {
            logger.warning("Fixture audio levels are empty")
            onPlaybackFinished?()
            return
        }

        isRecording = true
        currentIndex = 0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: updateInterval)
        timer.setEventHandler { [weak self] in
            self?.emitNextLevel()
        }
        self.timer = timer
        timer.resume()
    }

    func stopRecording() {
        guard isRecording else { return }
        timer?.cancel()
        timer = nil
        isRecording = false
        currentIndex = 0
    }

    private func emitNextLevel() {
        guard isRecording else { return }
        guard currentIndex < levels.count else {
            stopRecording()
            onPlaybackFinished?()
            return
        }

        let level = levels[currentIndex]
        currentIndex += 1
        onAudioLevelUpdate?(level)
    }

    static func loadLevels(from url: URL, chunkDuration: TimeInterval = 0.05) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            return []
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil else {
            return []
        }

        let totalFrames = Int(buffer.frameLength)
        if totalFrames == 0 { return [] }

        let samples: [Float]
        if let floatData = buffer.floatChannelData {
            let channel = floatData.pointee
            samples = Array(UnsafeBufferPointer(start: channel, count: totalFrames))
        } else if let int16Data = buffer.int16ChannelData {
            let channel = int16Data.pointee
            samples = Array(UnsafeBufferPointer(start: channel, count: totalFrames)).map {
                Float($0) / Float(Int16.max)
            }
        } else {
            return []
        }

        let chunkSize = max(Int(sampleRate * chunkDuration), 1)
        var levels: [Float] = []
        levels.reserveCapacity((totalFrames / chunkSize) + 1)

        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            let chunk = samples[index..<end]
            let meanSquare = chunk.reduce(Float(0)) { partial, sample in
                partial + sample * sample
            } / Float(max(chunk.count, 1))
            let rms = sqrt(meanSquare)
            let avgPower = 20 * log10(max(rms, 0.000_01))
            let normalized = max(0, min(1, (avgPower + 50) / 50))
            levels.append(normalized)
            index = end
        }

        return levels
    }
}
