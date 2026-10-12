import Foundation
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Presets
//
// A preset is a *partial recipe*: plain numbers, never pixels, so applying one adds no quality loss.
// A value is applied only when it is non-nil AND its group is listed in `Preset.includes`
// (the same rule Lightroom uses for checked groups and unwritten keys).
//
// Built-in looks express exposure / temperature / tint as *offsets*, so the photo's own exposure and
// white-balance corrections survive. Imported Lightroom presets and user presets use absolute values,
// exactly like Lightroom.
//
// The Amount slider (0...200 %) blends from the baseline recipe (captured when the preset panel opened)
// to the preset target with `PresetBlend.mix`, using one rule per parameter type.

// MARK: - File types

extension UTType {
    /// Noor's own preset file (`.noorpreset`, UTF-8 JSON). Must match `UTExportedTypeDeclarations` in Info.plist.
    static let noorPreset = UTType(exportedAs: "com.hmdalajmi.noor.preset", conformingTo: .json)

    /// Lightroom / Camera Raw `.xmp` preset. The system has no type for `.xmp`, so Info.plist declares
    /// `com.hmdalajmi.noor.lightroom-xmp` (conforms to `public.xml`, extension `xmp`) as an imported
    /// type and lists it in `CFBundleDocumentTypes`. Looked up by that identifier first, so the result
    /// never depends on what other installed apps declare; if the declaration is missing we fall back to
    /// whatever type the system derives from the extension, so the file picker still offers `.xmp` files.
    static let lightroomXMP: UTType = UTType("com.hmdalajmi.noor.lightroom-xmp")
        ?? UTType(filenameExtension: "xmp", conformingTo: .xml)
        ?? UTType(importedAs: "com.hmdalajmi.noor.lightroom-xmp", conformingTo: .xml)

    /// Every content type the preset importer accepts (for `.fileImporter`): Noor presets, Lightroom
    /// `.xmp` presets, "DNG presets" (settings inside a DNG) and folders of presets.
    /// The single list used by every preset file picker.
    static let noorPresetImportTypes: [UTType] = {
        var types: [UTType] = [.noorPreset, .lightroomXMP, .folder, .rawImage, .json, .xml]
        for ext in ["xmp", "dng", "noorpreset"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()
}

// MARK: - Model

/// Absolute white balance carried by Lightroom presets saved from RAW photos (`crs:Temperature`,
/// `crs:Tint`). It is resolved against each photo's as-shot white balance when the preset is applied.
struct AbsoluteWhiteBalance: Codable, Hashable, Sendable {
    var kelvin: Double   // 2000...50000
    var tint: Double     // -150...150 (Adobe tint units)
}

/// The values a preset carries. Every field is optional: nil means "leave the photo's value alone".
/// Scales are exactly the `EditRecipe` scales (Lightroom PV2012+).
struct PresetValues: Codable, Hashable, Sendable {
    // Light
    var exposure: Double? = nil
    var contrast: Double? = nil
    var highlights: Double? = nil
    var shadows: Double? = nil
    var whites: Double? = nil
    var blacks: Double? = nil

    // Color
    var temperature: Double? = nil
    var tint: Double? = nil
    var absoluteWhiteBalance: AbsoluteWhiteBalance? = nil
    var vibrance: Double? = nil
    var saturation: Double? = nil
    var isMonochrome: Bool? = nil

    // Effects
    var texture: Double? = nil
    var clarity: Double? = nil
    var dehaze: Double? = nil
    var vignette: Vignette? = nil
    var grain: Grain? = nil

    // Detail
    var sharpening: Double? = nil
    var sharpenRadius: Double? = nil
    var sharpenMasking: Double? = nil
    var noiseReduction: Double? = nil
    var colorNoiseReduction: Double? = nil

    // Offsets added to the photo's own value (built-in looks; never produced by XMP import).
    var exposureOffset: Double? = nil
    var temperatureOffset: Double? = nil
    var tintOffset: Double? = nil

    // Curve / grading / HSL / calibration
    var toneCurve: ToneCurves? = nil
    var grading: ColorGrading? = nil
    var hsl: [ColorBand: HSLAdjustment]? = nil
    var calibration: Calibration? = nil
}

/// A named look. Codable as one `.noorpreset` file; built-ins ship as an array in `BuiltInPresets.json`.
struct Preset: Codable, Identifiable, Hashable, Sendable {
    /// Where the preset came from. Raw values are part of the file format - never rename them.
    enum Source: String, Codable, Sendable {
        case builtIn, user, xmp, dng
    }

    /// Highest `formatVersion` this build can read. Readers reject newer files.
    static let currentFormatVersion = 1
    /// Longest preset name we keep (longer names are truncated on import / rename).
    static let maxNameLength = 80

    var formatVersion = Preset.currentFormatVersion
    var id: UUID
    var name: String
    var localizedNames: [String: String]? = nil    // language code -> name, e.g. ["ar": "كثبان ذهبية"]
    var group: String
    var localizedGroups: [String: String]? = nil
    var createdAt: Date
    var source: Source
    var supportsAmount: Bool
    var includes: Set<SettingGroup>
    var values: PresetValues
    var notes: [String]? = nil                     // user-facing import notes (XMP), shown in the info sheet

    enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, localizedNames, group, localizedGroups
        case createdAt, source, supportsAmount, includes, values, notes
    }

    /// Name in the given locale's language when the preset carries one (built-ins), else `name`.
    func displayName(_ locale: Locale = .current) -> String {
        if let code = locale.language.languageCode?.identifier,
           let localized = localizedNames?[code], !localized.isEmpty {
            return localized
        }
        return name
    }

    /// Group name in the given locale's language when the preset carries one (built-ins), else `group`.
    func displayGroup(_ locale: Locale = .current) -> String {
        if let code = locale.language.languageCode?.identifier,
           let localized = localizedGroups?[code], !localized.isEmpty {
            return localized
        }
        return group
    }

    /// A creation date with whole seconds, so a preset survives the ISO-8601 JSON round trip unchanged.
    static func creationDate() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    /// A new user preset built from the current edit (`PresetValues(recipe:groups:)`).
    static func makeUserPreset(name: String, group: String, values: PresetValues,
                               includes: Set<SettingGroup>) -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return Preset(id: UUID(),
                      name: trimmed.isEmpty ? String(localized: "My Preset") : String(trimmed.prefix(maxNameLength)),
                      group: trimmedGroup.isEmpty ? String(localized: "My Presets") : String(trimmedGroup.prefix(maxNameLength)),
                      createdAt: creationDate(),
                      source: .user,
                      supportsAmount: true,
                      includes: includes,
                      values: values)
    }

    /// A string usable as a file name (no path separators or reserved characters), never empty.
    static func fileSafeName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
            .union(.newlines)
        let cleaned = name.components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let short = String(cleaned.prefix(maxNameLength))
        return short.isEmpty ? "Preset" : short
    }
}

// MARK: - Tolerant decoding

extension Preset {
    /// Hand-written or older files may omit metadata; only `name` and `values` are required.
    /// (Declared in an extension so the memberwise initializer stays available.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = (try? c.decodeIfPresent(Int.self, forKey: .formatVersion)) ?? Preset.currentFormatVersion
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        let rawName = try c.decode(String.self, forKey: .name)
        name = String(rawName.prefix(Preset.maxNameLength))
        localizedNames = try? c.decodeIfPresent([String: String].self, forKey: .localizedNames)
        group = (try? c.decodeIfPresent(String.self, forKey: .group)) ?? String(localized: "Imported")
        localizedGroups = try? c.decodeIfPresent([String: String].self, forKey: .localizedGroups)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Preset.creationDate()
        source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? .user
        supportsAmount = (try? c.decodeIfPresent(Bool.self, forKey: .supportsAmount)) ?? true
        let decodedValues = try c.decode(PresetValues.self, forKey: .values)
        values = decodedValues
        includes = (try? c.decodeIfPresent(Set<SettingGroup>.self, forKey: .includes)) ?? decodedValues.presentGroups
        notes = try? c.decodeIfPresent([String].self, forKey: .notes)
    }
}

// MARK: - Codec

/// Errors reading a `.noorpreset` file.
enum PresetCodecError: LocalizedError, Equatable {
    case newerFormat(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .newerFormat:
            return String(localized: "This preset needs a newer version of Noor.")
        case .empty:
            return String(localized: "The file has no presets.")
        }
    }
}

/// `.noorpreset` reading and writing: UTF-8 JSON, one preset object or an array (a pack).
enum PresetCodec {
    static let fileExtension = "noorpreset"

    static func encode(_ preset: Preset) throws -> Data {
        try makeEncoder().encode(preset)
    }

    /// Encodes several presets as one pack file.
    static func encode(_ presets: [Preset]) throws -> Data {
        try makeEncoder().encode(presets)
    }

    /// Accepts a single preset object or an array of presets.
    static func decode(_ data: Data) throws -> [Preset] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list: [Preset]
        if firstSignificantByte(of: data) == UInt8(ascii: "[") {
            list = try decoder.decode([Preset].self, from: data)
        } else {
            let single = try decoder.decode(Preset.self, from: data)
            list = [single]
        }
        guard !list.isEmpty else { throw PresetCodecError.empty }
        if let newer = list.first(where: { $0.formatVersion > Preset.currentFormatVersion }) {
            throw PresetCodecError.newerFormat(newer.formatVersion)
        }
        return list
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// First byte that is not JSON whitespace (or a UTF-8 byte-order mark).
    private static func firstSignificantByte(of data: Data) -> UInt8? {
        let skipped: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF]
        return data.first { !skipped.contains($0) }
    }
}

// MARK: - Sharing

extension Preset: Transferable {
    /// Shares / drops as a `.noorpreset` file named after the preset.
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .noorPreset) { (preset: Preset) -> Data in
            try PresetCodec.encode(preset)
        } importing: { (data: Data) -> Preset in
            guard let first = try PresetCodec.decode(data).first else { throw PresetCodecError.empty }
            return first
        }
        .suggestedFileName { (preset: Preset) -> String? in
            "\(Preset.fileSafeName(preset.displayName())).\(PresetCodec.fileExtension)"
        }
    }
}

// MARK: - Apply

/// Facts about the photo a preset is applied to.
struct PresetApplyContext: Sendable {
    /// RAW: `CIRAWFilter.neutralTemperature` / `neutralTint` as decoded (as shot). Others: 5500 K / 0.
    var asShotKelvin = 5500.0
    var asShotTint = 0.0
}

extension AbsoluteWhiteBalance {
    /// Converts to the recipe's incremental scale around the photo's as-shot white balance.
    /// Engine contract (RAWStageSettings): temperature ±100 == ∓150 mired, tint ±100 == ±150 tint units.
    func incremental(_ context: PresetApplyContext) -> (temperature: Double, tint: Double) {
        let asShot = min(max(context.asShotKelvin.isFinite ? context.asShotKelvin : 5500, 2000), 50000)
        let target = min(max(kelvin.isFinite ? kelvin : 5500, 2000), 50000)
        let deltaMired = 1_000_000 / asShot - 1_000_000 / target      // > 0: the preset is warmer
        let range = EditRecipe.Limits.bipolar
        return (range.clamp(deltaMired / 1.5), range.clamp((tint - context.asShotTint) / 1.5))
    }
}

/// One scalar slider a preset can carry: its group, where it lives in `PresetValues` and in
/// `EditRecipe`, and its valid range.
private struct PresetScalarField {
    let group: SettingGroup
    let value: WritableKeyPath<PresetValues, Double?>
    let recipe: WritableKeyPath<EditRecipe, Double>
    let range: ParamRange
}

/// Table of every scalar preset field (shared by apply, blend and "create from edit").
private enum PresetFields {
    static let scalars: [PresetScalarField] = {
        typealias L = EditRecipe.Limits
        return [
            PresetScalarField(group: .light, value: \.exposure, recipe: \.exposure, range: L.exposure),
            PresetScalarField(group: .light, value: \.contrast, recipe: \.contrast, range: L.bipolar),
            PresetScalarField(group: .light, value: \.highlights, recipe: \.highlights, range: L.bipolar),
            PresetScalarField(group: .light, value: \.shadows, recipe: \.shadows, range: L.bipolar),
            PresetScalarField(group: .light, value: \.whites, recipe: \.whites, range: L.bipolar),
            PresetScalarField(group: .light, value: \.blacks, recipe: \.blacks, range: L.bipolar),
            PresetScalarField(group: .color, value: \.temperature, recipe: \.temperature, range: L.bipolar),
            PresetScalarField(group: .color, value: \.tint, recipe: \.tint, range: L.bipolar),
            PresetScalarField(group: .color, value: \.vibrance, recipe: \.vibrance, range: L.bipolar),
            PresetScalarField(group: .color, value: \.saturation, recipe: \.saturation, range: L.bipolar),
            PresetScalarField(group: .effects, value: \.texture, recipe: \.texture, range: L.bipolar),
            PresetScalarField(group: .effects, value: \.clarity, recipe: \.clarity, range: L.bipolar),
            PresetScalarField(group: .effects, value: \.dehaze, recipe: \.dehaze, range: L.bipolar),
            PresetScalarField(group: .detail, value: \.sharpening, recipe: \.sharpening, range: L.sharpening),
            PresetScalarField(group: .detail, value: \.sharpenRadius, recipe: \.sharpenRadius, range: L.sharpenRadius),
            PresetScalarField(group: .detail, value: \.sharpenMasking, recipe: \.sharpenMasking, range: L.unit100),
            PresetScalarField(group: .detail, value: \.noiseReduction, recipe: \.noiseReduction, range: L.unit100),
            PresetScalarField(group: .detail, value: \.colorNoiseReduction, recipe: \.colorNoiseReduction, range: L.unit100),
        ]
    }()
}

/// Linear interpolation that is exact at t = 0 (returns a) and t = 1 (returns b).
private func presetLerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    (1 - t) * a + t * b
}

extension Preset {
    /// The recipe at Amount = 100 %: `base` with every included, non-nil preset value substituted.
    /// Untrusted values are clamped (the result is `clamped()`), so a bad file can't produce garbage.
    func target(over base: EditRecipe, context: PresetApplyContext = .init()) -> EditRecipe {
        var r = base
        let v = values
        if includes.contains(.color), let wb = v.absoluteWhiteBalance {
            let incremental = wb.incremental(context)
            r.temperature = incremental.temperature
            r.tint = incremental.tint
        }
        for field in PresetFields.scalars where includes.contains(field.group) {
            if let x = v[keyPath: field.value] {
                r[keyPath: field.recipe] = field.range.clamp(x)
            }
        }
        if includes.contains(.light), let offset = v.exposureOffset, offset.isFinite {
            r.exposure = EditRecipe.Limits.exposure.clamp(r.exposure + offset)
        }
        if includes.contains(.color) {
            if let offset = v.temperatureOffset, offset.isFinite {
                r.temperature = EditRecipe.Limits.bipolar.clamp(r.temperature + offset)
            }
            if let offset = v.tintOffset, offset.isFinite {
                r.tint = EditRecipe.Limits.bipolar.clamp(r.tint + offset)
            }
            if let mono = v.isMonochrome { r.isMonochrome = mono }
        }
        if includes.contains(.effects) {
            if let vignette = v.vignette { r.vignette = vignette }
            if let grain = v.grain { r.grain = grain }
        }
        if includes.contains(.curve), let curves = v.toneCurve { r.toneCurve = curves }
        if includes.contains(.grading), let grading = v.grading { r.grading = grading }
        if includes.contains(.hsl), let hsl = v.hsl { r.hsl = hsl.filter { !$0.value.isIdentity } }
        if includes.contains(.calibration), let calibration = v.calibration { r.calibration = calibration }
        return r.clamped()
    }

    /// The previewed / committed recipe. `amount` is 0...2 (UI 0-200 %); `base` is the recipe captured
    /// when the preset panel opened (never a previewed result), so presets never stack while browsing.
    func applied(to base: EditRecipe, amount: Double, context: PresetApplyContext = .init()) -> EditRecipe {
        let full = target(over: base, context: context)
        let t = supportsAmount ? amount : 1
        return PresetBlend.mix(base, full, t)
    }
}

// MARK: - Amount blending

/// Blends two recipes for the preset Amount slider (t = 0 -> `a`, t = 1 -> `b`, up to t = 2).
/// One rule per parameter type; see the research spec §5.
enum PresetBlend {
    static func mix(_ a: EditRecipe, _ b: EditRecipe, _ t: Double) -> EditRecipe {
        let t = t.isFinite ? min(max(t, 0), 2) : 1
        if t == 0 { return a }       // exactly the baseline: Amount 0 % changes nothing

        // Discrete fields presets never touch (geometry, keepsHDR, version) come from `b`.
        var r = b
        for field in PresetFields.scalars {
            r[keyPath: field.recipe] = field.range.clamp(presetLerp(a[keyPath: field.recipe], b[keyPath: field.recipe], t))
        }
        // Sharpening shape follows the preset when the photo had no sharpening of its own.
        if a.sharpening == 0 {
            r.sharpenRadius = b.sharpenRadius
            r.sharpenMasking = b.sharpenMasking
        }

        // B&W: a colour -> B&W preset fades in as desaturation and switches to the B&W mix at 100 %;
        // B&W -> colour is the mirror image.
        r.isMonochrome = a.isMonochrome
        if a.isMonochrome != b.isMonochrome {
            if b.isMonochrome {
                if t < 1 {
                    r.saturation = EditRecipe.Limits.bipolar.clamp(presetLerp(a.saturation, -100, t))
                } else {
                    r.isMonochrome = true
                }
            } else {
                r.isMonochrome = false
                if t < 1 {
                    r.saturation = EditRecipe.Limits.bipolar.clamp(presetLerp(-100, b.saturation, t))
                }
            }
        }

        r.vignette = mixVignette(a.vignette, b.vignette, t)
        r.grain = mixGrain(a.grain, b.grain, t)
        r.toneCurve = ToneCurves(master: mixCurve(a.toneCurve.master, b.toneCurve.master, t),
                                 red: mixCurve(a.toneCurve.red, b.toneCurve.red, t),
                                 green: mixCurve(a.toneCurve.green, b.toneCurve.green, t),
                                 blue: mixCurve(a.toneCurve.blue, b.toneCurve.blue, t))
        r.grading = mixGrading(a.grading, b.grading, t)
        r.hsl = mixHSL(a.hsl, b.hsl, t)
        r.calibration = mixCalibration(a.calibration, b.calibration, t)
        return r.clamped()
    }

    /// Picks a shape parameter: the preset's at 100 % or when the base effect is off, the base's when
    /// the preset turns the effect off, otherwise interpolated.
    private static func shape(_ x: Double, _ y: Double, baseOff: Bool, targetOff: Bool, _ t: Double) -> Double {
        if baseOff || t == 1 { return y }
        if targetOff { return x }
        return presetLerp(x, y, t)
    }

    static func mixVignette(_ a: Vignette, _ b: Vignette, _ t: Double) -> Vignette {
        let aOff = a.amount == 0, bOff = b.amount == 0
        return Vignette(amount: presetLerp(a.amount, b.amount, t),
                        midpoint: shape(a.midpoint, b.midpoint, baseOff: aOff, targetOff: bOff, t),
                        roundness: shape(a.roundness, b.roundness, baseOff: aOff, targetOff: bOff, t),
                        feather: shape(a.feather, b.feather, baseOff: aOff, targetOff: bOff, t),
                        highlights: shape(a.highlights, b.highlights, baseOff: aOff, targetOff: bOff, t))
    }

    static func mixGrain(_ a: Grain, _ b: Grain, _ t: Double) -> Grain {
        let aOff = a.amount == 0, bOff = b.amount == 0
        return Grain(amount: presetLerp(a.amount, b.amount, t),
                     size: shape(a.size, b.size, baseOff: aOff, targetOff: bOff, t),
                     roughness: shape(a.roughness, b.roughness, baseOff: aOff, targetOff: bOff, t))
    }

    static func mixGrading(_ a: ColorGrading, _ b: ColorGrading, _ t: Double) -> ColorGrading {
        let aOff = a.isIdentity, bOff = b.isIdentity
        return ColorGrading(shadows: mixWheel(a.shadows, b.shadows, t),
                            midtones: mixWheel(a.midtones, b.midtones, t),
                            highlights: mixWheel(a.highlights, b.highlights, t),
                            global: mixWheel(a.global, b.global, t),
                            blending: shape(a.blending, b.blending, baseOff: aOff, targetOff: bOff, t),
                            balance: shape(a.balance, b.balance, baseOff: aOff, targetOff: bOff, t))
    }

    /// Interpolates in the (a, b) colour plane: no hue wrap-around problem, and a neutral base keeps
    /// the preset's hue while its saturation scales with the Amount.
    static func mixWheel(_ a: GradeWheel, _ b: GradeWheel, _ t: Double) -> GradeWheel {
        if t == 1 || a == b { return b }
        if t == 0 { return a }
        let ra = a.hue * .pi / 180
        let rb = b.hue * .pi / 180
        let x = presetLerp(a.saturation * cos(ra), b.saturation * cos(rb), t)
        let y = presetLerp(a.saturation * sin(ra), b.saturation * sin(rb), t)
        let saturation = min(hypot(x, y), 100)
        var hue: Double
        if saturation < 1e-6 {
            hue = b.saturation > 0 ? b.hue : a.hue
        } else {
            hue = atan2(y, x) * 180 / .pi
            if hue < 0 { hue += 360 }
        }
        return GradeWheel(hue: hue, saturation: saturation, luminance: presetLerp(a.luminance, b.luminance, t))
    }

    /// Per band and component; a missing band counts as zero; neutral bands are dropped.
    static func mixHSL(_ a: [ColorBand: HSLAdjustment], _ b: [ColorBand: HSLAdjustment],
                       _ t: Double) -> [ColorBand: HSLAdjustment] {
        var out: [ColorBand: HSLAdjustment] = [:]
        for band in ColorBand.allCases {
            let x = a[band] ?? HSLAdjustment()
            let y = b[band] ?? HSLAdjustment()
            let m = HSLAdjustment(hue: presetLerp(x.hue, y.hue, t),
                                  saturation: presetLerp(x.saturation, y.saturation, t),
                                  luminance: presetLerp(x.luminance, y.luminance, t))
            if !m.isIdentity { out[band] = m }
        }
        return out
    }

    static func mixCalibration(_ a: Calibration, _ b: Calibration, _ t: Double) -> Calibration {
        Calibration(shadowTint: presetLerp(a.shadowTint, b.shadowTint, t),
                    redHue: presetLerp(a.redHue, b.redHue, t),
                    redSaturation: presetLerp(a.redSaturation, b.redSaturation, t),
                    greenHue: presetLerp(a.greenHue, b.greenHue, t),
                    greenSaturation: presetLerp(a.greenSaturation, b.greenSaturation, t),
                    blueHue: presetLerp(a.blueHue, b.blueHue, t),
                    blueSaturation: presetLerp(a.blueSaturation, b.blueSaturation, t))
    }

    /// Evaluates both curves (with `CurveMath`, the engine's evaluator) on the union of their control
    /// points and interpolates the outputs. t = 0 / t = 1 return the exact input curves.
    static func mixCurve(_ a: [CurvePoint], _ b: [CurvePoint], _ t: Double) -> [CurvePoint] {
        let pa = CurveMath.sanitize(a)
        let pb = CurveMath.sanitize(b)
        if pa == pb || t == 1 { return pb }
        if t == 0 { return pa }
        var xs: [Double] = []
        for x in (pa + pb).map(\.x).sorted() {
            if let last = xs.last, x - last <= 1.0 / 512 { continue }
            xs.append(x)
        }
        if xs.count > CurveMath.maxPoints {
            xs = (0...16).map { Double($0) / 16 }
        }
        let ma = CurveMath.tangents(pa)
        let mb = CurveMath.tangents(pb)
        let points = xs.map { x -> CurvePoint in
            let ya = CurveMath.evaluate(pa, tangents: ma, at: x)
            let yb = CurveMath.evaluate(pb, tangents: mb, at: x)
            return CurvePoint(x: x, y: min(max(presetLerp(ya, yb, t), 0), 1))
        }
        return CurveMath.sanitize(points)
    }
}

// MARK: - Create a preset from the current edit

extension PresetValues {
    /// Captures the given groups of `recipe` (the "Save Preset" sheet). Never produces offsets or
    /// absolute white balance.
    init(recipe r: EditRecipe, groups: Set<SettingGroup>) {
        self.init()
        for field in PresetFields.scalars where groups.contains(field.group) {
            self[keyPath: field.value] = r[keyPath: field.recipe]
        }
        if groups.contains(.color) { isMonochrome = r.isMonochrome }
        if groups.contains(.effects) {
            vignette = r.vignette
            grain = r.grain
        }
        if groups.contains(.curve) { toneCurve = r.toneCurve }
        if groups.contains(.grading) { grading = r.grading }
        if groups.contains(.hsl) { hsl = r.hsl.filter { !$0.value.isIdentity } }
        if groups.contains(.calibration) { calibration = r.calibration }
    }

    /// Groups that actually carry data (pre-ticks the save sheet; fills `includes` on import).
    var presentGroups: Set<SettingGroup> {
        var groups = Set<SettingGroup>()
        for field in PresetFields.scalars where self[keyPath: field.value] != nil {
            groups.insert(field.group)
        }
        if exposureOffset != nil { groups.insert(.light) }
        if absoluteWhiteBalance != nil || isMonochrome != nil || temperatureOffset != nil || tintOffset != nil {
            groups.insert(.color)
        }
        if vignette != nil || grain != nil { groups.insert(.effects) }
        if toneCurve != nil { groups.insert(.curve) }
        if grading != nil { groups.insert(.grading) }
        if hsl != nil { groups.insert(.hsl) }
        if calibration != nil { groups.insert(.calibration) }
        return groups
    }

    /// True when the preset would not change anything.
    var isEmpty: Bool { presentGroups.isEmpty }
}
