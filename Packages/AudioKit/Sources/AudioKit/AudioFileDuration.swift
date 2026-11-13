#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Reads the duration of an audio file that is already on disk.
///
/// Recovery and interruption finalisation cannot ask the recorder how long the
/// file is, so they read it back. `AVURLAsset` is tried first; `AVAudioPlayer`
/// is the fallback for containers the asset loader refuses.
public enum AudioFileDuration {
    /// Duration of `url` in seconds, or `nil` when the file holds no readable audio.
    public static func seconds(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let seconds = player.duration
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
#endif
