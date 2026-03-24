import AVFoundation
import Foundation
import os.log

final class AudioCapture: AudioLevelSource {
    private let targetSampleRate: Double = 16000

    var onAudioLevelUpdate: ((Float) -> Void)?
    var onAudioDataAvailable: ((Data) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    private(set) var isRecording = false
    private var isSettingUp = false
    private var capturedChunkCount = 0
    private var processedBufferCount = 0
    private let logger = AppLogger.make(.audio)

    init() {}

    func startRecording() {
        guard !isRecording else {
            logger.info("startRecording ignored: already recording")
            return
        }
        logger.info("startRecording requested. mainThread=\(Thread.isMainThread)")

        // Ensure we run on main thread using performOnMainThread
        if Thread.isMainThread && !isSettingUp {
            startRecordingInternal()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startRecordingInternal()
            }
        }
    }

    private func startRecordingInternal() {
        guard !isRecording, !isSettingUp else {
            logger.info("startRecordingInternal ignored: isRecording=\(self.isRecording), isSettingUp=\(self.isSettingUp)")
            return
        }

        isSettingUp = true

        // Defensive cleanup in case a previous session did not fully tear down.
        teardownAudioEngine(reason: "start_preflight")

        // Create engine on main thread
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            isSettingUp = false
            return
        }

        inputNode = engine.inputNode

        let format = inputNode?.outputFormat(forBus: 0)
        if let format {
            logger.info("Audio input format: sampleRate=\(format.sampleRate), channels=\(format.channelCount), commonFormat=\(format.commonFormat.rawValue)")
            logger.info("Audio capture target sampleRate=\(self.targetSampleRate)")
        } else {
            logger.error("Failed to read audio input format")
        }

        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            isRecording = true
            capturedChunkCount = 0
            processedBufferCount = 0
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }

        isSettingUp = false
    }

    func stopRecording() {
        guard isRecording else {
            logger.info("stopRecording ignored: not recording")
            return
        }
        logger.info("stopRecording requested. mainThread=\(Thread.isMainThread)")

        if Thread.isMainThread {
            stopRecordingInternal()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopRecordingInternal()
            }
        }
    }

    private func stopRecordingInternal() {
        guard isRecording else { return }

        teardownAudioEngine(reason: "stop")
        isRecording = false
        logger.info("Recording stopped")
    }

    private func teardownAudioEngine(reason: String) {
        if inputNode != nil {
            inputNode?.removeTap(onBus: 0)
        }
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
        }
        inputNode = nil
        audioEngine = nil
        logger.info("Audio engine torn down: reason=\(reason)")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        processedBufferCount += 1
        let frameLength = Int(buffer.frameLength)
        let inputRate = buffer.format.sampleRate
        if frameLength <= 0 { return }

        let samples = extractFloatSamples(from: buffer)
        guard !samples.isEmpty else {
            if processedBufferCount <= 3 || processedBufferCount % 50 == 0 {
                logger.info(
                    "Audio buffer had no readable channel data: callbackCount=\(self.processedBufferCount), frameLength=\(frameLength), commonFormat=\(buffer.format.commonFormat.rawValue), interleaved=\(buffer.format.isInterleaved)"
                )
            }
            return
        }

        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let avgPower = 20 * log10(rms)
        let normalizedLevel = max(0, min(1, (avgPower + 50) / 50))
        let peakAbs = samples.map { abs($0) }.max() ?? 0

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelUpdate?(normalizedLevel)
        }

        capturedChunkCount += 1
        var mutableSamples = samples
        let pcmData = downsampleTo16kPcm(input: &mutableSamples, frameLength: frameLength, inputSampleRate: inputRate)
        if capturedChunkCount <= 3 || capturedChunkCount % 20 == 0 {
            logger.info(
                "Audio chunk captured: chunkCount=\(self.capturedChunkCount), callbackCount=\(self.processedBufferCount), inputFrames=\(frameLength), inputRate=\(inputRate), rms=\(rms), peakAbs=\(peakAbs), outputBytes=\(pcmData.count)"
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.onAudioDataAvailable?(pcmData)
        }
    }

    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }

        if let channelData = buffer.floatChannelData {
            let base = channelData.pointee
            return stride(from: 0, to: frameLength, by: buffer.stride).map { base[$0] }
        }

        if let int16Data = buffer.int16ChannelData {
            let base = int16Data.pointee
            return stride(from: 0, to: frameLength, by: buffer.stride).map {
                Float(base[$0]) / Float(Int16.max)
            }
        }

        return []
    }

    private func downsampleTo16kPcm(input: inout [Float], frameLength: Int, inputSampleRate: Double) -> Data {
        guard frameLength > 0 else { return Data() }

        if abs(inputSampleRate - targetSampleRate) < 0.5 {
            var pcmData = Data(capacity: frameLength * 2)
            for i in 0..<frameLength {
                let clamped = max(-1.0, min(1.0, input[i]))
                var intSample = Int16(clamped * Float(Int16.max))
                pcmData.append(Data(bytes: &intSample, count: 2))
            }
            return pcmData
        }

        let ratio = inputSampleRate / targetSampleRate
        let outputFrames = max(Int(Double(frameLength) / ratio), 1)
        var pcmData = Data(capacity: outputFrames * 2)

        for outIndex in 0..<outputFrames {
            let sourcePos = Double(outIndex) * ratio
            let index0 = min(Int(sourcePos), frameLength - 1)
            let index1 = min(index0 + 1, frameLength - 1)
            let frac = Float(sourcePos - Double(index0))
            let sample0 = input[index0]
            let sample1 = input[index1]
            let interpolated = sample0 + (sample1 - sample0) * frac
            let clamped = max(-1.0, min(1.0, interpolated))
            var intSample = Int16(clamped * Float(Int16.max))
            pcmData.append(Data(bytes: &intSample, count: 2))
        }

        return pcmData
    }
}
