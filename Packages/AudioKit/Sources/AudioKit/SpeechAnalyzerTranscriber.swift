#if canImport(AVFoundation) && canImport(Speech)
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// On-device transcription with Apple's `SpeechAnalyzer`.
///
/// The implementation asks for final, time-indexed results only, so every
/// segment it produces is final and carries a real audio time range. Missing
/// language assets are requested once and surfaced as
/// ``AudioKitError/transcriptionUnavailable`` when they cannot be installed;
/// they are never silently dropped.
@available(iOS 26.0, macOS 26.0, *)
public actor SpeechAnalyzerTranscriber: SpeechTranscriber {
    private let locale: Locale

    /// Creates a transcriber for `locale`; it resolves to the closest supported locale.
    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Whether the on-device speech models can run on this device.
    public var isAvailable: Bool {
        Speech.SpeechTranscriber.isAvailable
    }

    /// Locales the on-device transcriber supports, whether or not they are installed.
    public var supportedLocales: [Locale] {
        get async {
            await Speech.SpeechTranscriber.supportedLocales
        }
    }

    /// Transcribes `url` with the on-device speech models.
    public func transcribe(url: URL, clipID: UUID?) async throws -> Transcript {
        guard isAvailable else { throw AudioKitError.transcriptionUnavailable }
        guard let resolved = await Speech.SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw AudioKitError.unsupportedLocale(locale.identifier)
        }

        let module = Speech.SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        let modules: [any SpeechModule] = [module]

        // Open the file before a possible language-asset download, so a bad URL
        // fails immediately.
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioKitError.transcriptionFailed(
                "could not read \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        try await installAssetsIfNeeded(modules: modules, locale: resolved)

        let fileDuration = Self.duration(of: file)
        let analyzer = SpeechAnalyzer(modules: modules)
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioKitError.transcriptionFailed(
                "could not start analysis: \(error.localizedDescription)"
            )
        }

        var raw: [(range: CMTimeRange, text: String)] = []
        do {
            for try await result in module.results {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                raw.append((result.range, text))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioKitError.transcriptionFailed(
                "analysis failed: \(error.localizedDescription)"
            )
        }

        return Transcript(
            clipID: clipID,
            language: resolved.identifier(.bcp47),
            segments: Self.segments(from: raw, fileDuration: fileDuration),
            updatedAt: Date()
        )
    }

    // MARK: - Internals

    private func installAssetsIfNeeded(
        modules: [any SpeechModule],
        locale: Locale
    ) async throws {
        guard await AssetInventory.status(forModules: modules) != .installed else {
            return
        }
        if let request = try? await AssetInventory.assetInstallationRequest(
            supporting: modules
        ) {
            do {
                try await request.downloadAndInstall()
            } catch {
                throw AudioKitError.transcriptionFailed(
                    "could not install speech assets for "
                        + "\(locale.identifier(.bcp47)): \(error.localizedDescription)"
                )
            }
        }
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw AudioKitError.transcriptionUnavailable
        }
    }

    private static func duration(of file: AVAudioFile) -> TimeInterval {
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return 0 }
        return max(0, Double(file.length) / rate)
    }

    /// Turns analyser ranges into segments whose times stay inside the file.
    ///
    /// A result without a usable range gets the gap up to the next phrase, or a
    /// minimal window at the end of the file, rather than being dropped.
    static func segments(
        from raw: [(range: CMTimeRange, text: String)],
        fileDuration: TimeInterval
    ) -> [TranscriptSegment] {
        guard !raw.isEmpty else { return [] }
        let limit = fileDuration.isFinite && fileDuration > 0 ? fileDuration : 0
        guard limit > 0 else { return [] }

        let starts = raw.map { item -> TimeInterval in
            let seconds = item.range.start.seconds
            return seconds.isFinite ? min(max(seconds, 0), limit) : 0
        }

        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(raw.count)

        for index in raw.indices {
            var start = starts[index]
            let reportedEnd = raw[index].range.end.seconds
            var end = reportedEnd.isFinite ? min(max(reportedEnd, 0), limit) : 0

            if end <= start {
                let nextStart = index + 1 < raw.count ? starts[index + 1] : limit
                if nextStart > start { end = nextStart }
            }
            if end <= start {
                // No usable timing at all: a short window at the end of the file.
                start = max(0, limit - 0.01)
                end = limit
            }
            guard end > start else { continue }

            segments.append(
                TranscriptSegment(
                    startSeconds: start,
                    endSeconds: end,
                    text: raw[index].text,
                    isFinal: true
                )
            )
        }
        return segments
    }
}
#endif
