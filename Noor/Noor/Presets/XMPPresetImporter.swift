import Foundation
import ImageIO

// MARK: - Lightroom / Camera Raw preset import
//
// Reads Lightroom Classic, Lightroom (mobile export) and Camera Raw `.xmp` presets, and "DNG presets"
// (photos whose XMP packet carries `crs:` settings), and maps them onto a `Preset` (partial recipe).
//
// Two passes:
//   1. `XMPPropertyCollector` (SAX) flattens the packet into a property bag. It accepts attribute and
//      element form, rdf:Seq / rdf:Alt / rdf:Bag arrays, structs (nested rdf:Description,
//      rdf:parseType="Resource", field attributes) and the crs namespace under ANY prefix
//      (resolved by URI). Only top-level properties are captured; the `crs:Look` profile struct goes to
//      its own bag, so its nested Name / Group / tone curves never override the preset's own.
//   2. `XMPMapper` converts the bag to `PresetValues` (clamping every value) and collects warnings.
//
// Only settings that scale are imported. Masks, lens / geometry / crop and profile LUTs are skipped
// with a warning. A B&W profile sets `isMonochrome`. Synchronous: call from a background task.

// MARK: - Errors & warnings

/// Why a file could not be imported. Descriptions are user-facing.
enum XMPImportError: LocalizedError, Equatable {
    case tooLarge
    case noXMPPacket
    case notXMP(String)            // parser detail, for logs only
    case isProfile(String?)
    case noSupportedSettings
    case lightroomTemplate
    case archive

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return String(localized: "The file is too large to be a preset.")
        case .noXMPPacket:
            return String(localized: "No Lightroom settings were found in this file.")
        case .notXMP:
            return String(localized: "This isn't a valid XMP preset.")
        case .isProfile(let name):
            if let name {
                return String(localized: "“\(name)” is a profile, not a preset.")
            }
            return String(localized: "This is a profile, not a preset.")
        case .noSupportedSettings:
            return String(localized: "This preset has no settings Noor can use.")
        case .lightroomTemplate:
            return String(localized: "Old Lightroom presets (.lrtemplate) aren't supported. Open it in Lightroom and export it as .xmp.")
        case .archive:
            return String(localized: "Unzip the file in the Files app first, then import the presets.")
        }
    }
}

/// Something that was imported approximately or skipped. `message` is user-facing.
enum XMPImportWarning: Hashable, Sendable {
    case profileNotReproduced(String)
    case localAdjustmentsIgnored
    case lensGeometryCropIgnored
    case legacyProcessVersion
    case absoluteWhiteBalance
    case autoSettingsIgnored
    case vignetteStyleApproximated
    case rawDefaultDetailSkipped
    case parametricCurveApproximated

    var message: String {
        switch self {
        case .profileNotReproduced(let name):
            return String(localized: "Made with the “\(name)” profile. Its colors aren't reproduced.")
        case .localAdjustmentsIgnored:
            return String(localized: "Masks and local adjustments were skipped.")
        case .lensGeometryCropIgnored:
            return String(localized: "Lens, crop and geometry settings were skipped.")
        case .legacyProcessVersion:
            return String(localized: "Made for an older Lightroom version, so the result is approximate.")
        case .absoluteWhiteBalance:
            return String(localized: "White balance is adapted to each photo.")
        case .autoSettingsIgnored:
            return String(localized: "Auto settings were skipped.")
        case .vignetteStyleApproximated:
            return String(localized: "The vignette style is approximated.")
        case .rawDefaultDetailSkipped:
            return String(localized: "RAW sharpening defaults were skipped.")
        case .parametricCurveApproximated:
            return String(localized: "The region tone curve is approximated.")
        }
    }
}

/// A successfully imported preset plus its notes.
struct XMPImportResult: Sendable {
    var preset: Preset
    /// User-facing notes (also stored in `preset.notes`).
    var warnings: [String]
    /// crs properties that were present but not mapped (diagnostics only).
    var ignoredKeys: [String]
}

// MARK: - Importer

/// Lightroom `.xmp` / DNG-preset importer. Stateless; safe to call from any thread.
enum XMPPresetImporter {
    static let maxXMPBytes = 4 << 20
    static let maxImageBytes = 400 << 20

    /// Imports a `.xmp` file (or other XML) or any image that carries Camera Raw settings in its
    /// XMP packet (DNG presets, edited JPEG/TIFF). Opens the URL's security scope itself.
    static func importPreset(from url: URL) throws -> XMPImportResult {
        let ext = url.pathExtension.lowercased()
        if ext == "lrtemplate" { throw XMPImportError.lightroomTemplate }
        if ext == "zip" { throw XMPImportError.archive }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let isXML = ext == "xmp" || ext == "xml"
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= (isXML ? maxXMPBytes : maxImageBytes) else { throw XMPImportError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        if isXML {
            return try importPreset(xmp: data, fallbackName: fallbackName, source: .xmp)
        }
        guard let packet = extractXMPPacket(from: data) else { throw XMPImportError.noXMPPacket }
        return try importPreset(xmp: packet, fallbackName: fallbackName, source: .dng)
    }

    /// Parses one XMP packet. `fallbackName` is used when the packet has no `crs:Name`.
    static func importPreset(xmp: Data, fallbackName: String, source: Preset.Source) throws -> XMPImportResult {
        let collector = XMPPropertyCollector()
        let parser = XMLParser(data: xmp)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false          // prefixes are resolved by the collector
        parser.shouldReportNamespacePrefixes = true     // ... from these callbacks and/or xmlns attributes
        parser.shouldResolveExternalEntities = false    // never touch the network or other files
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse() else {
            throw XMPImportError.notXMP(parser.parserError?.localizedDescription ?? "parse error")
        }
        guard collector.sawRDF else { throw XMPImportError.notXMP("no rdf:RDF") }
        let mapper = XMPMapper(collector)
        return try mapper.makeResult(fallbackName: fallbackName, source: source)
    }

    /// Finds the XMP packet that carries `crs:` settings inside a DNG/TIFF (tag 700) or JPEG (APP1)
    /// by scanning the bytes; falls back to ImageIO's metadata serializer.
    static func extractXMPPacket(from data: Data) -> Data? {
        let marker = Data("camera-raw-settings".utf8)
        let delimiters = [("<x:xmpmeta", "</x:xmpmeta>"), ("<x:xapmeta", "</x:xapmeta>"), ("<rdf:RDF", "</rdf:RDF>")]
        for (openTag, closeTag) in delimiters {
            let open = Data(openTag.utf8)
            let close = Data(closeTag.utf8)
            var from = data.startIndex
            while from < data.endIndex,
                  let start = data.range(of: open, in: from..<data.endIndex),
                  let end = data.range(of: close, in: start.upperBound..<data.endIndex) {
                let packet = data.subdata(in: start.lowerBound..<end.upperBound)
                if packet.range(of: marker) != nil { return packet }
                from = end.upperBound
            }
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let serialized = CGImageMetadataCreateXMPData(metadata, nil) else { return nil }
        let xmp = serialized as Data
        return xmp.range(of: marker) != nil ? xmp : nil
    }
}

// MARK: - Pass 1: SAX -> property bag

/// Flattens an XMP packet into top-level crs scalars / arrays plus the `crs:Look` struct.
/// Works with `shouldProcessNamespaces = false`: element and attribute names arrive as
/// "prefix:local" and prefixes are resolved through a scope stack fed by `xmlns` attributes and
/// prefix-mapping callbacks (whichever the Foundation implementation provides). Literal `crs:` and
/// `rdf:` are a last-resort fallback.
private final class XMPPropertyCollector: NSObject, XMLParserDelegate {
    static let crsNS = "http://ns.adobe.com/camera-raw-settings/1.0/"
    static let rdfNS = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private static let fallbackPrefixes = ["crs": crsNS, "rdf": rdfNS]

    private(set) var scalars: [String: String] = [:]   // top-level crs simple properties
    private(set) var lists: [String: [String]] = [:]    // top-level crs arrays: rdf:li texts in order
    private(set) var itemCounts: [String: Int] = [:]    // top-level crs arrays: number of rdf:li (incl. structs)
    private(set) var look: [String: String] = [:]       // crs:Look fields, nested as "Parameters.ConvertToGrayscale"
    private(set) var seen: Set<String> = []             // every top-level crs property name
    private(set) var sawRDF = false

    private enum Role {
        case outer, rdf, topDescription, ignored
        case property(String)
        case array(String)
        case item(String)
        case look(String)           // field-path prefix inside crs:Look ("" or "Parameters.")
    }

    private struct Frame {
        var role: Role
        var hasChildren = false
    }

    private var stack: [Frame] = []
    private var scopes: [[String: String]] = []         // prefix -> namespace URI, one per open element
    private var pendingMappings: [String: String] = [:] // reported just before the next start tag
    private var text = ""

    private func resolve(_ qualifiedName: String) -> (namespace: String, local: String) {
        let parts = qualifiedName.split(separator: ":", maxSplits: 1).map(String.init)
        let prefix = parts.count == 2 ? parts[0] : ""
        let local = parts.count == 2 ? parts[1] : qualifiedName
        for scope in scopes.reversed() {
            if let uri = scope[prefix] { return (uri, local) }
        }
        return (XMPPropertyCollector.fallbackPrefixes[prefix] ?? "", local)
    }

    private func crsAttributes(_ attributes: [String: String]) -> [(String, String)] {
        var result: [(String, String)] = []
        for (key, value) in attributes where key != "xmlns" && !key.hasPrefix("xmlns:") {
            let name = resolve(key)
            if name.namespace == XMPPropertyCollector.crsNS { result.append((name.local, value)) }
        }
        return result
    }

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        pendingMappings[prefix] = namespaceURI
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var scope = pendingMappings
        pendingMappings = [:]
        for (key, value) in attributeDict {
            if key == "xmlns" {
                scope[""] = value
            } else if key.hasPrefix("xmlns:") {
                scope[String(key.dropFirst(6))] = value
            }
        }
        scopes.append(scope)
        if !stack.isEmpty { stack[stack.count - 1].hasChildren = true }
        text = ""

        let name = resolve(elementName)
        let isRDF = name.namespace == XMPPropertyCollector.rdfNS
        let isCRS = name.namespace == XMPPropertyCollector.crsNS
        let parent = stack.last?.role ?? .outer
        var role = Role.ignored
        switch parent {
        case .outer:
            if isRDF && name.local == "RDF" {
                role = .rdf
                sawRDF = true
            } else {
                role = .outer
            }
        case .rdf:
            if isRDF && name.local == "Description" {
                role = .topDescription
                for (key, value) in crsAttributes(attributeDict) {
                    scalars[key] = value
                    seen.insert(key)
                }
            }
        case .topDescription:
            if isCRS {
                seen.insert(name.local)
                role = name.local == "Look" ? .look("") : .property(name.local)
            }
        case .property(let property):
            if isRDF && (name.local == "Seq" || name.local == "Alt" || name.local == "Bag") {
                role = .array(property)
            }
        case .array(let property):
            if isRDF && name.local == "li" {
                role = .item(property)
                itemCounts[property, default: 0] += 1
            }
        case .look(let prefix):
            if isRDF && name.local == "Description" {
                role = .look(prefix)
            } else if isCRS {
                role = .look(prefix + name.local + ".")
            }
        case .item, .ignored:
            role = .ignored
        }
        if case .look(let prefix) = role {
            for (key, value) in crsAttributes(attributeDict) { look[prefix + key] = value }
        }
        stack.append(Frame(role: role))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard let frame = stack.popLast() else { return }
        if !scopes.isEmpty { scopes.removeLast() }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch frame.role {
        case .property(let property) where !frame.hasChildren:
            scalars[property] = value                                   // element form
        case .item(let property) where !frame.hasChildren:
            lists[property, default: []].append(value)
        case .look(let prefix) where !frame.hasChildren && !prefix.isEmpty:
            look[String(prefix.dropLast())] = value
        default:
            break
        }
        text = ""
    }
}

// MARK: - Pass 2: property bag -> PresetValues

/// Maps Camera Raw keys to the recipe (see research spec §2). Every value is clamped.
private final class XMPMapper {
    private let s: [String: String]
    private let l: [String: [String]]
    private let itemCounts: [String: Int]
    private let look: [String: String]
    private let seen: Set<String>
    private var warnings: [XMPImportWarning] = []
    private var used: Set<String> = []

    private static let bands: [(ColorBand, String)] = [
        (.red, "Red"), (.orange, "Orange"), (.yellow, "Yellow"), (.green, "Green"),
        (.aqua, "Aqua"), (.blue, "Blue"), (.purple, "Purple"), (.magenta, "Magenta"),
    ]
    /// Profiles that are just the default rendering: importing without them loses nothing.
    private static let defaultLooks: Set<String> = ["Adobe Color", "Adobe Standard", "Adobe Default", "Camera Standard"]
    /// Lightroom local-adjustment arrays (masks, healing, red eye, point colour).
    private static let localKeys = [
        "MaskGroupBasedCorrections", "GradientBasedCorrections", "CircularGradientBasedCorrections",
        "PaintBasedCorrections", "RetouchAreas", "RetouchInfo", "RedEyeInfo", "PointColors",
    ]
    /// Lens / geometry / crop keys with their "off" value; only a different value earns a warning.
    private static let geometryDefaults: [(String, Double)] = [
        ("LensProfileEnable", 0), ("AutoLateralCA", 0), ("LensManualDistortionAmount", 0),
        ("VignetteAmount", 0), ("DefringePurpleAmount", 0), ("DefringeGreenAmount", 0),
        ("PerspectiveVertical", 0), ("PerspectiveHorizontal", 0), ("PerspectiveRotate", 0),
        ("PerspectiveAspect", 0), ("PerspectiveScale", 100), ("PerspectiveX", 0), ("PerspectiveY", 0),
        ("PerspectiveUpright", 0), ("UprightTransformMode", 0), ("CropAngle", 0), ("HasCrop", 0),
        ("ChromaticAberrationR", 0), ("ChromaticAberrationB", 0),
    ]
    /// Metadata keys that are understood but carry no settings.
    private static let metadataKeys: Set<String> = [
        "PresetType", "Cluster", "UUID", "Version", "ProcessVersion", "HasSettings", "Name", "ShortName",
        "SortName", "Group", "Description", "Copyright", "ContactInfo", "CameraModelRestriction", "Look",
        "ToneCurveName", "ToneCurveName2010", "ToneCurveName2012",
    ]

    private typealias L = EditRecipe.Limits

    init(_ c: XMPPropertyCollector) {
        s = c.scalars
        l = c.lists
        itemCounts = c.itemCounts
        look = c.look
        seen = c.seen
    }

    // MARK: Value readers

    /// "+0.35", "-40", " 128" -> Double (finite only).
    static func number(_ raw: String?) -> Double? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("+") { t.removeFirst() }
        guard let value = Double(t), value.isFinite else { return nil }
        return value
    }

    /// "True" / "false" / "1" / "0" -> Bool.
    static func boolean(_ raw: String?) -> Bool? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch value {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    private func num(_ key: String, _ range: ParamRange) -> Double? {
        guard let value = XMPMapper.number(s[key]) else { return nil }
        used.insert(key)
        return range.clamp(value)
    }

    private func flag(_ key: String) -> Bool? {
        guard let value = XMPMapper.boolean(s[key]) else { return nil }
        used.insert(key)
        return value
    }

    /// "x, y" points (0...255) -> sanitized 0...1 curve.
    private func curve(_ key: String) -> [CurvePoint]? {
        guard let items = l[key] else { return nil }
        used.insert(key)
        let points = items.compactMap { item -> CurvePoint? in
            let xy = item.split(separator: ",").compactMap { XMPMapper.number(String($0)) }
            return xy.count == 2 ? CurvePoint(x: xy[0] / 255, y: xy[1] / 255) : nil
        }
        return points.count >= 2 ? CurveMath.sanitize(points) : nil
    }

    /// Lang-alt (x-default first) or attribute-form text.
    private func text(_ key: String) -> String? {
        let raw = l[key]?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? s[key]
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Preset.maxNameLength))
    }

    private func warn(_ warning: XMPImportWarning) {
        if !warnings.contains(warning) { warnings.append(warning) }
    }

    // MARK: Result

    func makeResult(fallbackName: String, source: Preset.Source) throws -> XMPImportResult {
        let lookName = look["Name"].flatMap { $0.isEmpty ? nil : $0 }
        if s["PresetType"]?.caseInsensitiveCompare("Look") == .orderedSame {
            throw XMPImportError.isProfile(text("Name") ?? lookName)
        }
        let processVersion = XMPMapper.number(s["ProcessVersion"]) ?? 11
        let legacy = processVersion < 6.7          // PV2003 / PV2010: keys without the "2012" suffix
        if legacy { warn(.legacyProcessVersion) }

        var v = PresetValues()
        mapLight(&v, legacy: legacy)
        mapColor(&v, lookName: lookName)
        mapEffects(&v, legacy: legacy)
        mapDetail(&v)
        mapCurves(&v, legacy: legacy)
        mapHSL(&v)
        mapGrading(&v)
        mapCalibration(&v)
        checkSkippedFamilies()

        let groups = v.presentGroups
        guard !groups.isEmpty else { throw XMPImportError.noSupportedSettings }

        let messages = warnings.map(\.message)
        let ignored = seen.filter { key in
            !used.contains(key) && !XMPMapper.metadataKeys.contains(key)
                && !["Supports", "Parametric", "GrayMixer"].contains { key.hasPrefix($0) }
        }.sorted()
        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(id: XMPMapper.uuid(s["UUID"]) ?? UUID(),
                            name: text("Name") ?? (fallback.isEmpty ? String(localized: "Imported Preset") : String(fallback.prefix(Preset.maxNameLength))),
                            group: text("Group") ?? String(localized: "Imported"),
                            createdAt: Preset.creationDate(),
                            source: source,
                            supportsAmount: true,
                            includes: groups,
                            values: v,
                            notes: messages.isEmpty ? nil : messages)
        return XMPImportResult(preset: preset, warnings: messages, ignoredKeys: ignored)
    }

    // MARK: Light

    private func mapLight(_ v: inout PresetValues, legacy: Bool) {
        v.exposure = num("Exposure2012", L.exposure) ?? (legacy ? num("Exposure", L.exposure) : nil)
        v.contrast = num("Contrast2012", L.bipolar)
            ?? (legacy ? num("Contrast", ParamRange(-50, 100)).map { $0 - 25 } : nil)
        v.highlights = num("Highlights2012", L.bipolar)
            ?? (legacy ? num("HighlightRecovery", L.unit100).map { -$0 } : nil)
        v.shadows = num("Shadows2012", L.bipolar) ?? (legacy ? num("FillLight", L.unit100) : nil)
        v.whites = num("Whites2012", L.bipolar)
        v.blacks = num("Blacks2012", L.bipolar)
            ?? (legacy ? num("Shadows", L.unit100).map { L.bipolar.clamp(5 - $0) } : nil)
    }

    // MARK: Color

    private func mapColor(_ v: inout PresetValues, lookName: String?) {
        let whiteBalance = s["WhiteBalance"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if whiteBalance != nil { used.insert("WhiteBalance") }
        v.temperature = num("IncrementalTemperature", L.bipolar)
        v.tint = num("IncrementalTint", L.bipolar)
        if whiteBalance == "As Shot" {
            if v.temperature == nil { v.temperature = 0 }
            if v.tint == nil { v.tint = 0 }
        } else if v.temperature == nil, let kelvin = num("Temperature", ParamRange(2000, 50000)) {
            // RAW preset: absolute Kelvin, resolved against each photo's as-shot white balance.
            v.absoluteWhiteBalance = AbsoluteWhiteBalance(kelvin: kelvin, tint: num("Tint", ParamRange(-150, 150)) ?? 0)
            warn(.absoluteWhiteBalance)
        }
        let autoFlags = ["AutoTone", "AutoExposure", "AutoContrast", "AutoShadows", "AutoBrightness"]
        if whiteBalance == "Auto" || autoFlags.contains(where: { flag($0) == true }) {
            warn(.autoSettingsIgnored)
        }
        v.vibrance = num("Vibrance", L.bipolar)
        v.saturation = num("Saturation", L.bipolar)

        // B&W: an explicit ConvertToGrayscale wins; otherwise a B&W profile implies it (genuine
        // Lightroom B&W presets often only carry the "Adobe Monochrome" look).
        let lookParametersMono = XMPMapper.boolean(look["Parameters.ConvertToGrayscale"]) == true
        let monochromeLook = lookParametersMono || lookName.map(XMPMapper.isMonochromeLookName) == true
        v.isMonochrome = flag("ConvertToGrayscale") ?? (monochromeLook ? true : nil)
        if let name = lookName, !XMPMapper.defaultLooks.contains(name), !monochromeLook {
            warn(.profileNotReproduced(name))
        }
    }

    private static func isMonochromeLookName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("monochrome") || n.contains("b&w") || n.contains("black & white")
            || n.contains("black and white")
    }

    // MARK: Effects

    private func mapEffects(_ v: inout PresetValues, legacy: Bool) {
        v.texture = num("Texture", L.bipolar)
        v.clarity = num("Clarity2012", L.bipolar) ?? (legacy ? num("Clarity", L.bipolar) : nil)
        v.dehaze = num("Dehaze", L.bipolar)
        if let amount = num("PostCropVignetteAmount", L.bipolar) {
            v.vignette = Vignette(amount: amount,
                                  midpoint: num("PostCropVignetteMidpoint", L.unit100) ?? 50,
                                  roundness: num("PostCropVignetteRoundness", L.bipolar) ?? 0,
                                  feather: num("PostCropVignetteFeather", L.unit100) ?? 50,
                                  highlights: num("PostCropVignetteHighlightContrast", L.unit100) ?? 0)
            // 1 = Highlight Priority (what the engine renders); 2 Color Priority, 3 Paint Overlay.
            if let style = num("PostCropVignetteStyle", ParamRange(1, 3)), style != 1, amount != 0 {
                warn(.vignetteStyleApproximated)
            }
        }
        if let amount = num("GrainAmount", L.unit100) {
            v.grain = Grain(amount: amount,
                            size: num("GrainSize", L.unit100) ?? 25,
                            roughness: num("GrainFrequency", L.unit100) ?? num("GrainRoughness", L.unit100) ?? 50)
        }
    }

    // MARK: Detail

    /// Presets saved from RAW files often carry Lightroom's RAW detail defaults (Sharpening 40,
    /// Radius 1.0, Masking 0, Luminance NR 0, Color NR 25). Applied to an iPhone JPEG/HEIC that would
    /// sharpen twice, so exactly those defaults are skipped.
    private func mapDetail(_ v: inout PresetValues) {
        let sharpening = num("Sharpness", L.sharpening)
        let radius = num("SharpenRadius", L.sharpenRadius) ?? num("SharpnessRadius", L.sharpenRadius)
        let masking = num("SharpenEdgeMasking", L.unit100)
        let luminanceNR = num("LuminanceSmoothing", L.unit100)
        let colorNR = num("ColorNoiseReduction", L.unit100)
        guard sharpening != nil || radius != nil || masking != nil || luminanceNR != nil || colorNR != nil else { return }
        let isRAWDefault = (sharpening ?? 40) == 40 && (radius ?? 1) == 1 && (masking ?? 0) == 0
            && (luminanceNR ?? 0) == 0 && (colorNR ?? 25) == 25
        if isRAWDefault {
            if sharpening != nil || colorNR != nil { warn(.rawDefaultDetailSkipped) }
            return
        }
        v.sharpening = sharpening
        v.sharpenRadius = radius
        v.sharpenMasking = masking
        v.noiseReduction = luminanceNR
        v.colorNoiseReduction = colorNR
    }

    // MARK: Tone curve

    private func mapCurves(_ v: inout PresetValues, legacy: Bool) {
        var master = curve("ToneCurvePV2012") ?? (legacy ? curve("ToneCurve") : nil)
        let red = curve("ToneCurvePV2012Red")
        let green = curve("ToneCurvePV2012Green")
        let blue = curve("ToneCurvePV2012Blue")
        if let region = parametricCurve() {
            // Region curve first, then the point curve, sampled on the union of both control points.
            let point = master ?? ToneCurves.linear
            var xs = Set(region.map(\.x))
            for p in point { xs.insert(p.x) }
            let regionTangents = CurveMath.tangents(region)
            let pointTangents = CurveMath.tangents(point)
            master = CurveMath.sanitize(xs.sorted().map { x -> CurvePoint in
                let y = CurveMath.evaluate(region, tangents: regionTangents, at: x)
                return CurvePoint(x: x, y: CurveMath.evaluate(point, tangents: pointTangents, at: y))
            })
            warn(.parametricCurveApproximated)
        }
        guard master != nil || red != nil || green != nil || blue != nil else { return }
        let linear = ToneCurves.linear
        v.toneCurve = ToneCurves(master: master ?? linear, red: red ?? linear,
                                 green: green ?? linear, blue: blue ?? linear)
    }

    /// Lightroom's region ("parametric") curve as control points: one point per zone centre, moved by
    /// the zone's slider and kept monotone. An approximation of Lightroom's own region curve.
    private func parametricCurve() -> [CurvePoint]? {
        let values = ["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"]
            .map { num($0, L.bipolar) ?? 0 }
        guard values.contains(where: { $0 != 0 }) else { return nil }
        let s1 = (num("ParametricShadowSplit", ParamRange(10, 90)) ?? 25) / 100
        let s2 = max(s1, (num("ParametricMidtoneSplit", ParamRange(10, 90)) ?? 50) / 100)
        let s3 = max(s2, (num("ParametricHighlightSplit", ParamRange(10, 90)) ?? 75) / 100)
        let centres = [s1 / 2, (s1 + s2) / 2, (s2 + s3) / 2, (s3 + 1) / 2]
        var points = [CurvePoint(x: 0, y: 0)]
        for (centre, value) in zip(centres, values) {
            let amplitude = min(0.12, 0.6 * min(centre, 1 - centre))
            let previous = points[points.count - 1].y
            let y = min(max(centre + value / 100 * amplitude, previous), 1)
            points.append(CurvePoint(x: centre, y: y))
        }
        points.append(CurvePoint(x: 1, y: 1))
        return CurveMath.sanitize(points)
    }

    // MARK: HSL / B&W mix

    private func mapHSL(_ v: inout PresetValues) {
        var hsl: [ColorBand: HSLAdjustment] = [:]
        var present = false
        for (band, suffix) in XMPMapper.bands {
            let hue = num("HueAdjustment" + suffix, L.bipolar)
            let saturation = num("SaturationAdjustment" + suffix, L.bipolar)
            let luminance = num("LuminanceAdjustment" + suffix, L.bipolar)
            if hue != nil || saturation != nil || luminance != nil {
                present = true
                hsl[band] = HSLAdjustment(hue: hue ?? 0, saturation: saturation ?? 0, luminance: luminance ?? 0)
            }
        }
        // Engine contract: when the recipe is monochrome, HSL luminance per band IS the B&W mix.
        if v.isMonochrome == true {
            var mix: [ColorBand: HSLAdjustment] = [:]
            var hasMix = false
            for (band, suffix) in XMPMapper.bands {
                if let weight = num("GrayMixer" + suffix, L.bipolar) {
                    hasMix = true
                    mix[band] = HSLAdjustment(hue: 0, saturation: 0, luminance: weight)
                }
            }
            if hasMix {
                hsl = mix
                present = true
            }
        }
        if present { v.hsl = hsl.filter { !$0.value.isIdentity } }
    }

    // MARK: Color grading

    /// Color Grading (Lightroom 2020+) still stores the shadow / highlight wheels in the old
    /// SplitToning* keys; only midtones, global, luminance and blending use ColorGrade* keys.
    private func mapGrading(_ v: inout PresetValues) {
        let gradeKeys = s.keys.filter { $0.hasPrefix("SplitToning") || $0.hasPrefix("ColorGrade") }
        guard !gradeKeys.isEmpty else { return }
        let modern = gradeKeys.contains { $0.hasPrefix("ColorGrade") }
        func first(_ keys: [String], _ range: ParamRange) -> Double? {
            keys.compactMap { num($0, range) }.first
        }
        func wheel(hue: [String], saturation: [String], luminance: String) -> GradeWheel {
            GradeWheel(hue: first(hue, ParamRange(0, 360)) ?? 0,
                       saturation: first(saturation, L.unit100) ?? 0,
                       luminance: num(luminance, L.bipolar) ?? 0)
        }
        v.grading = ColorGrading(
            shadows: wheel(hue: ["SplitToningShadowHue", "ColorGradeShadowHue"],
                           saturation: ["SplitToningShadowSaturation", "ColorGradeShadowSat"],
                           luminance: "ColorGradeShadowLum"),
            midtones: wheel(hue: ["ColorGradeMidtoneHue"], saturation: ["ColorGradeMidtoneSat"],
                            luminance: "ColorGradeMidtoneLum"),
            highlights: wheel(hue: ["SplitToningHighlightHue", "ColorGradeHighlightHue"],
                              saturation: ["SplitToningHighlightSaturation", "ColorGradeHighlightSat"],
                              luminance: "ColorGradeHighlightLum"),
            global: wheel(hue: ["ColorGradeGlobalHue"], saturation: ["ColorGradeGlobalSat"],
                          luminance: "ColorGradeGlobalLum"),
            // Pre-2020 split toning had no blending control; 100 reproduces it most closely.
            blending: num("ColorGradeBlending", L.unit100) ?? (modern ? 50 : 100),
            balance: num("SplitToningBalance", L.bipolar) ?? num("ColorGradeBalance", L.bipolar) ?? 0)
        used.formUnion(gradeKeys)
    }

    // MARK: Calibration

    private func mapCalibration(_ v: inout PresetValues) {
        let keys = ["ShadowTint", "RedHue", "RedSaturation", "GreenHue", "GreenSaturation", "BlueHue", "BlueSaturation"]
        let values = keys.map { num($0, L.bipolar) }
        guard values.contains(where: { $0 != nil }) else { return }
        let c = values.map { $0 ?? 0 }
        v.calibration = Calibration(shadowTint: c[0], redHue: c[1], redSaturation: c[2], greenHue: c[3],
                                    greenSaturation: c[4], blueHue: c[5], blueSaturation: c[6])
    }

    // MARK: Skipped families

    private func checkSkippedFamilies() {
        if XMPMapper.localKeys.contains(where: { (itemCounts[$0] ?? 0) > 0 }) {
            warn(.localAdjustmentsIgnored)
        }
        let geometryActive = XMPMapper.geometryDefaults.contains { entry -> Bool in
            let (key, offValue) = entry
            guard let raw = s[key] else { return false }
            if let value = XMPMapper.number(raw) { return value != offValue }
            if let on = XMPMapper.boolean(raw) { return on != (offValue != 0) }
            return false
        }
        if geometryActive { warn(.lensGeometryCropIgnored) }
    }

    // MARK: Identity

    /// crs:UUID (32 hex digits) -> a stable id, so re-importing the same .xmp replaces instead of
    /// duplicating. Also accepts the hyphenated form.
    static func uuid(_ raw: String?) -> UUID? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let direct = UUID(uuidString: raw) { return direct }
        let hex = Array(raw)
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { return nil }
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return UUID(uuidString: parts.joined(separator: "-"))
    }
}
