import Foundation

protocol AudioLevelSource: AnyObject {
    var onAudioLevelUpdate: ((Float) -> Void)? { get set }
    var isRecording: Bool { get }

    func startRecording()
    func stopRecording()
}
