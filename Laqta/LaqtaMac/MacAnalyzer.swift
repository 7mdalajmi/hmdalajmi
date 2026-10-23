import Foundation
import PDFKit
import Synchronization
import Vision

nonisolated struct MacAnalysisResult: Sendable {
    let analysis: ShotAnalysis
    let completed: Bool

    static func failure(_ note: String) -> Self {
        var analysis = ShotAnalysis()
        analysis.analyzedAt = .now
        analysis.basis = "لم تكتمل قراءة النص على هذا الماك"
        analysis.tips = [note, "ملفك الأصلي محفوظ ويمكن عرضه وتصديره. استخدم إعادة قراءة النص للمحاولة لاحقًا."]
        return Self(analysis: analysis, completed: false)
    }
}

nonisolated enum MacAnalyzer {
    private static let running = Mutex(false)
    #if DEBUG
    static var hasRunningRequest: Bool { running.withLock { $0 } }
    #endif

    /// A deadline resumes the caller independently of Vision's synchronous `perform`.
    /// Keep a single flight until Vision actually exits, even if the OS ignores cancellation.
    static func analyze(url: URL, kind: MediaKind, timeout: TimeInterval = 20) async -> MacAnalysisResult {
        let acquired = running.withLock { value in
            if value { return false }
            value = true
            return true
        }
        guard acquired else {
            return .failure("محرك قراءة النص لا يزال ينهي طلبًا سابقًا. ستستمر بقية وظائف المكتبة.")
        }
        return await withCheckedContinuation { continuation in
            let flight = MacAnalysisFlight(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(timeout, 0.05)) {
                flight.expire()
            }
            Task.detached(priority: .utility) {
                defer { running.withLock { $0 = false } }
                do {
                    let analysis = try await analyzeWork(url: url, kind: kind, flight: flight)
                    flight.finish(MacAnalysisResult(analysis: analysis, completed: true))
                } catch {
                    flight.finish(.failure("تعذر قراءة النص: \(error.localizedDescription)"))
                }
            }
        }
    }

    @concurrent
    private static func analyzeWork(url: URL, kind: MediaKind, flight: MacAnalysisFlight) async throws -> ShotAnalysis {
        var result = ShotAnalysis()
        result.analyzedAt = .now
        result.basis = "تحليل محلي على هذا الماك"
        var text = ""
        if kind == .document, let document = PDFDocument(url: url) {
            // Keep very large documents bounded; original PDF remains complete.
            for index in 0..<min(document.pageCount, 80) {
                if flight.hasExpired { throw CancellationError() }
                guard let page = document.page(at: index) else { continue }
                let extracted = page.string ?? ""
                if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let image = MediaInspector.render(page, maxPixelSize: 2200) {
                    text += (try recognize(image, flight: flight)) + "\n"
                } else { text += extracted + "\n" }
                if text.count > 200_000 { text = String(text.prefix(200_000)); break }
            }
            if document.pageCount > 80 { result.tips = ["تمت فهرسة أول 80 صفحة؛ الملف الأصلي محفوظ بالكامل."] }
        } else if let image = await MediaInspector.thumbnail(forFileAt: url, kind: kind, maxPixelSize: 2600, allowFullDecode: true, duration: nil) {
            text = try recognize(image, flight: flight)
            let request = VNClassifyImageRequest()
            guard flight.register(request) else { throw CancellationError() }
            if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil {
                result.labels = VisionLabels.display(Array((request.results ?? []).filter { $0.confidence > 0.4 }.prefix(6).map(\.identifier)))
            }
            if kind == .video { result.transcriptNote = "قراءة النص من إطار معاينة الفيديو. التفريغ الصوتي غير متاح في هذه النسخة." }
        }
        result.text = text.isEmpty ? nil : text
        result.entities = EntityDetector.detect(in: text)
        result.prices = EntityDetector.priceRows(in: text)
        return result
    }

    private static func recognize(_ image: CGImage, flight: MacAnalysisFlight) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if let supported = try? request.supportedRecognitionLanguages() {
            request.recognitionLanguages = ["ar-SA", "en-US"].filter(supported.contains)
        }
        guard flight.register(request) else { throw CancellationError() }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

/// State is protected by the lock. Vision supports cancelling a request while `perform` runs.
nonisolated final class MacAnalysisFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [VNRequest] = []
    private var continuation: CheckedContinuation<MacAnalysisResult, Never>?
    private var expired = false

    init(_ continuation: CheckedContinuation<MacAnalysisResult, Never>) { self.continuation = continuation }

    var hasExpired: Bool {
        lock.lock(); defer { lock.unlock() }
        return expired
    }

    func register(_ request: VNRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !expired else { return false }
        requests.append(request)
        return true
    }

    func finish(_ result: MacAnalysisResult) {
        lock.lock()
        let pending = continuation
        continuation = nil
        requests.removeAll()
        lock.unlock()
        pending?.resume(returning: result)
    }

    func expire() {
        lock.lock()
        guard let pending = continuation else { lock.unlock(); return }
        continuation = nil
        expired = true
        let active = requests
        requests.removeAll()
        lock.unlock()
        pending.resume(returning: .failure("تجاوزت قراءة النص مهلة 20 ثانية. قد تكون نماذج القراءة في macOS غير متاحة حاليًا."))
        for request in active { request.cancel() }
    }
}
