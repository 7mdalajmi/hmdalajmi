//
//  VideoTranscriber.swift
//  Laqta
//
//  What is said in a saved video, transcribed on the device with Apple's speech models.
//

import AVFoundation
import Foundation
import NaturalLanguage
import Speech

nonisolated enum TranscriptionOutcome: Sendable {
    case transcript([TranscriptLine], language: String, truncated: Bool)
    case noSpeech
    /// The speech model for this language isn't on the device yet.
    case needsDownload(language: String)
    case unavailable(String)
}

nonisolated enum VideoTranscriber {
    /// Longer videos are transcribed up to this point.
    static let maximumDuration: Double = 45 * 60

    static var isSupported: Bool {
        SpeechTranscriber.isAvailable
    }

    /// Languages to try, most likely first: the language of the text in the video,
    /// then the device's languages, then English.
    static func candidateLanguages(textHint: String?) -> [String] {
        var result: [String] = []
        func add(_ code: String?) {
            guard let code, !code.isEmpty, !result.contains(code) else { return }
            result.append(code)
        }
        if let textHint, textHint.count >= 12,
           let dominant = NLLanguageRecognizer.dominantLanguage(for: textHint) {
            add(dominant.rawValue)
        }
        for identifier in Locale.preferredLanguages {
            add(Locale(identifier: identifier).language.languageCode?.identifier)
        }
        add("en")
        return result
    }

    static func displayName(for language: String) -> String {
        Locale(identifier: "en_US").localizedString(forLanguageCode: language) ?? language
    }

    // MARK: Transcribing

    @concurrent
    static func transcribe(fileURL: URL, duration: Double, language: String, allowDownload: Bool) async -> TranscriptionOutcome {
        guard SpeechTranscriber.isAvailable else {
            return .unavailable("Reading speech isn't available on this device.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            return .unavailable("\(displayName(for: language)) speech isn't supported on this device yet.")
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            guard allowDownload else { return .needsDownload(language: language) }
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                DebugLog.write("transcribe: download failed \(error)")
                return .unavailable("\(displayName(for: language)) speech couldn't be downloaded. Try again later.")
            }
        }

        guard let audioURL = await exportAudio(from: fileURL, maxDuration: maximumDuration) else {
            return .noSpeech
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let segments = collect(transcriber.results)
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let lines = merge(try await segments)
            guard !lines.isEmpty else { return .noSpeech }
            return .transcript(lines, language: locale.identifier, truncated: duration > maximumDuration)
        } catch {
            DebugLog.write("transcribe: failed \(error)")
            return .unavailable("Laqta couldn't read the speech in this video.")
        }
    }

    private static func collect<Results: AsyncSequence>(_ results: Results) async throws -> [TranscriptLine]
    where Results.Element == SpeechTranscriber.Result {
        var lines: [TranscriptLine] = []
        for try await result in results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = result.range.start.seconds
            lines.append(TranscriptLine(seconds: start.isFinite ? start : 0, text: text))
        }
        return lines
    }

    /// Joins short pieces into readable lines of a sentence or two.
    static func merge(_ segments: [TranscriptLine], maxLength: Int = 160) -> [TranscriptLine] {
        var merged: [TranscriptLine] = []
        for segment in segments.sorted(by: { $0.seconds < $1.seconds }) {
            if var last = merged.last,
               last.text.count + segment.text.count < maxLength,
               segment.seconds - last.seconds < 20,
               !(last.text.last.map { ".?!؟".contains($0) } ?? false) {
                last.text += " " + segment.text
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    /// The video's sound as a separate audio file.
    @concurrent
    static func exportAudio(from url: URL, maxDuration: Double) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        if let duration = try? await asset.load(.duration), duration.seconds > maxDuration {
            session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxDuration, preferredTimescale: 600))
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        do {
            try await session.export(to: output, as: .m4a)
            return output
        } catch {
            DebugLog.write("transcribe: audio export failed \(error)")
            return nil
        }
    }
}
