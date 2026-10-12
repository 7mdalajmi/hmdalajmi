import Foundation
import CoreGraphics
import CoreImage
import Metal
import os

/// The app-wide Core Image + Metal setup shared by the preview canvas, thumbnails, analysis and export.
///
/// Every context renders in the same linear, extended-range working space
/// (`extendedLinearDisplayP3`) with half-float (`RGBAh`) intermediates, so wide-gamut and HDR values
/// (below 0 and above 1) survive every stage and preview, thumbnails and export compute identical maths.
///
/// Thread safety: all stored properties are immutable after `init` and `CIContext` is documented as
/// thread-safe, so the engine may be used from any thread. `makeExportContext()` returns a fresh
/// context that belongs to the caller (one per export job, dropped afterwards).
final class RenderEngine: @unchecked Sendable {
    static let shared = RenderEngine()

    // MARK: Metal

    /// True when the contexts render on the GPU. Every device and simulator that runs iOS 17 has Metal;
    /// the software fallback only exists so library, thumbnails and export keep working in odd hosts.
    let isMetalAvailable: Bool
    private let metalDevice: MTLDevice?
    private let displayQueue: MTLCommandQueue?

    /// The system GPU. Only the CAMetalLayer canvas needs it; without Metal there is no canvas to draw,
    /// so asking for it there is a programming error rather than a recoverable condition.
    var device: MTLDevice {
        guard let metalDevice else { preconditionFailure("Noor: Metal is unavailable, the photo canvas cannot be created") }
        return metalDevice
    }

    /// The display queue: the preview canvas encodes and presents on it (shared with `previewContext`).
    var commandQueue: MTLCommandQueue {
        guard let displayQueue else { preconditionFailure("Noor: Metal is unavailable, the photo canvas cannot be created") }
        return displayQueue
    }

    // MARK: Color

    /// Linear Display P3 with extended range: Core Image's working space for every Noor context.
    let workingSpace: CGColorSpace

    // MARK: Contexts

    /// Interactive canvas, detail tier and proxy baking. Caches intermediates, high-quality downsampling.
    let previewContext: CIContext
    /// Thumbnails, histograms and analysis (airlight). Own command queue, low priority so it never
    /// steals GPU time from the canvas.
    let utilityContext: CIContext

    // MARK: Init

    private init() {
        // Provably safe: a built-in named color space that exists on every supported OS.
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        workingSpace = space

        let device = MTLCreateSystemDefaultDevice()
        metalDevice = device
        isMetalAvailable = device != nil

        let display = device?.makeCommandQueue()
        display?.label = "noor.display"
        displayQueue = display

        let utilityQueue = device?.makeCommandQueue()
        utilityQueue?.label = "noor.utility"

        previewContext = RenderEngine.makeContext(
            queue: display,
            options: RenderEngine.contextOptions(name: "noor.preview", workingSpace: space,
                                                 cacheIntermediates: true, lowPriority: false,
                                                 memoryTargetMB: nil))
        utilityContext = RenderEngine.makeContext(
            queue: utilityQueue,
            options: RenderEngine.contextOptions(name: "noor.utility", workingSpace: space,
                                                 cacheIntermediates: true, lowPriority: true,
                                                 memoryTargetMB: nil))
    }

    // MARK: Export

    /// A fresh context for one export job: its own command queue, no intermediate caching and an
    /// iOS 17 `memoryTarget` derived from the memory this process may still use. Drop it afterwards.
    func makeExportContext() -> CIContext {
        let queue = metalDevice?.makeCommandQueue()
        queue?.label = "noor.export"
        return Self.makeContext(
            queue: queue,
            options: Self.contextOptions(name: "noor.export", workingSpace: workingSpace,
                                         cacheIntermediates: false, lowPriority: true,
                                         memoryTargetMB: Self.exportMemoryTargetMB()))
    }

    // MARK: Memory

    /// Frees the cached intermediates and textures of the preview and utility contexts
    /// (memory warnings, before an export, when the editor closes).
    func clearCaches() {
        previewContext.clearCaches()
        utilityContext.clearCaches()
    }

    // MARK: Helpers

    /// Metal-backed context on `queue`, or Core Image's own (software when no GPU exists) without one.
    private static func makeContext(queue: MTLCommandQueue?, options: [CIContextOption: Any]) -> CIContext {
        if let queue {
            return CIContext(mtlCommandQueue: queue, options: options)
        }
        return CIContext(options: options)
    }

    private static func contextOptions(name: String, workingSpace: CGColorSpace, cacheIntermediates: Bool,
                                       lowPriority: Bool, memoryTargetMB: Int?) -> [CIContextOption: Any] {
        var options: [CIContextOption: Any] = [
            .workingColorSpace: workingSpace,
            // Must be an NSNumber holding the CIFormat raw value (RGBAf is macOS-only as a working format).
            .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
            .cacheIntermediates: cacheIntermediates,
            // The iOS default is false (single-pass, aliasing downsamples).
            .highQualityDownsample: true,
            .priorityRequestLow: lowPriority,
            .name: name,
        ]
        if let memoryTargetMB {
            options[.memoryTarget] = NSNumber(value: memoryTargetMB)    // iOS 17
        }
        return options
    }

    /// A quarter of the memory still available to the process, between 256 MB and 1 GB.
    /// `os_proc_available_memory()` reports 0 where no limit applies (simulator), hence the default.
    private static func exportMemoryTargetMB() -> Int {
        let available = os_proc_available_memory()
        guard available > 0 else { return 1024 }
        let megabytes = available / 1_048_576
        return min(1024, max(256, megabytes / 4))
    }
}
