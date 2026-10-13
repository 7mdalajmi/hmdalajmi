import Foundation
import CoreGraphics

// MARK: - Recipe
//
// The recipe is Noor's whole edit: plain numbers, never pixels. The original file is never
// modified; preview, thumbnails and export all re-render the original through the same recipe.
//
// Scales follow Lightroom / Camera Raw (Process Version 2012+) so imported XMP presets map 1:1:
//   * exposure is in EV (-5...5)
//   * most sliders are -100...100 with 0 = no change
//   * temperature / tint are "incremental" (-100...100); +temperature = warmer, +tint = magenta.
//     Engine contract: ±100 == ±150 mired / ±150 tint units (see RAWStageSettings).

struct CurvePoint: Codable, Hashable, Sendable {
    var x: Double   // input, 0...1 (perceptual / gamma-encoded tone)
    var y: Double   // output, 0...1
}

struct ToneCurves: Codable, Hashable, Sendable {
    static let linear = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    var master = ToneCurves.linear
    var red = ToneCurves.linear
    var green = ToneCurves.linear
    var blue = ToneCurves.linear

    var isIdentity: Bool {
        CurveMath.isLinear(master) && CurveMath.isLinear(red) && CurveMath.isLinear(green) && CurveMath.isLinear(blue)
    }

    subscript(channel: CurveChannel) -> [CurvePoint] {
        get {
            switch channel {
            case .master: return master
            case .red: return red
            case .green: return green
            case .blue: return blue
            }
        }
        set {
            switch channel {
            case .master: master = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }
}

enum CurveChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case master, red, green, blue
    var id: String { rawValue }
}

/// Lightroom's eight HSL / Color Mixer ranges, in hue order.
enum ColorBand: String, Codable, CaseIterable, CodingKeyRepresentable, Identifiable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta
    var id: String { rawValue }
    /// sRGB HSL hue (degrees) of the band centre, used for UI swatches.
    var displayHue: Double {
        switch self {
        case .red: return 0
        case .orange: return 30
        case .yellow: return 60
        case .green: return 120
        case .aqua: return 180
        case .blue: return 240
        case .purple: return 270
        case .magenta: return 300
        }
    }
}

struct HSLAdjustment: Codable, Hashable, Sendable {
    var hue = 0.0          // -100...100
    var saturation = 0.0   // -100...100
    var luminance = 0.0    // -100...100 (B&W mix weight when the recipe is monochrome)
    var isIdentity: Bool { hue == 0 && saturation == 0 && luminance == 0 }
}

struct GradeWheel: Codable, Hashable, Sendable {
    var hue = 0.0          // 0...360 (Lightroom wheel hue)
    var saturation = 0.0   // 0...100
    var luminance = 0.0    // -100...100
    var isIdentity: Bool { saturation == 0 && luminance == 0 }
}

enum GradeRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case shadows, midtones, highlights, global
    var id: String { rawValue }
}

struct ColorGrading: Codable, Hashable, Sendable {
    var shadows = GradeWheel()
    var midtones = GradeWheel()
    var highlights = GradeWheel()
    var global = GradeWheel()
    var blending = 50.0    // 0...100
    var balance = 0.0      // -100...100

    /// Blending and balance only shape the wheels, so a grading with neutral wheels is identity.
    var isIdentity: Bool { shadows.isIdentity && midtones.isIdentity && highlights.isIdentity && global.isIdentity }

    subscript(range: GradeRange) -> GradeWheel {
        get {
            switch range {
            case .shadows: return shadows
            case .midtones: return midtones
            case .highlights: return highlights
            case .global: return global
            }
        }
        set {
            switch range {
            case .shadows: shadows = newValue
            case .midtones: midtones = newValue
            case .highlights: highlights = newValue
            case .global: global = newValue
            }
        }
    }
}

/// Lightroom "post-crop vignette" (Highlight Priority style).
struct Vignette: Codable, Hashable, Sendable {
    var amount = 0.0       // -100...100
    var midpoint = 50.0    // 0...100
    var roundness = 0.0    // -100...100
    var feather = 50.0     // 0...100
    var highlights = 0.0   // 0...100
    var isIdentity: Bool { amount == 0 }
}

struct Grain: Codable, Hashable, Sendable {
    var amount = 0.0       // 0...100
    var size = 25.0        // 0...100 (relative to the picture, so preview == export)
    var roughness = 50.0   // 0...100
    var isIdentity: Bool { amount == 0 }
}

/// Lightroom "Calibration" panel: moves the red/green/blue primaries. All -100...100.
struct Calibration: Codable, Hashable, Sendable {
    var shadowTint = 0.0
    var redHue = 0.0
    var redSaturation = 0.0
    var greenHue = 0.0
    var greenSaturation = 0.0
    var blueHue = 0.0
    var blueSaturation = 0.0
    var isIdentity: Bool { self == Calibration() }
}

/// Groups of settings. Used by presets ("includes"), copy/paste settings and panel resets.
/// Raw values are part of the .noorpreset file format - never rename them.
enum SettingGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, color, effects, detail, curve, grading, hsl, calibration
    var id: String { rawValue }
}

struct EditRecipe: Codable, Hashable, Sendable {
    static let currentVersion = 1
    static let identity = EditRecipe()

    var version = EditRecipe.currentVersion

    // Light
    var exposure = 0.0                 // EV, -5...5
    var contrast = 0.0                 // -100...100
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0

    // Color
    var temperature = 0.0              // incremental, -100...100 (+ = warmer)
    var tint = 0.0                     // incremental, -100...100 (+ = magenta)
    var vibrance = 0.0                 // -100...100
    var saturation = 0.0               // -100...100
    var isMonochrome = false           // B&W; HSL luminance then acts as the B&W mix

    // Effects (Lightroom "Presence" + "Effects")
    var texture = 0.0                  // -100...100
    var clarity = 0.0                  // -100...100
    var dehaze = 0.0                   // -100...100
    var vignette = Vignette()
    var grain = Grain()

    // Detail
    var sharpening = 0.0               // 0...150
    var sharpenRadius = 1.0            // 0.5...3.0 full-resolution pixels
    var sharpenMasking = 0.0           // 0...100
    var noiseReduction = 0.0           // 0...100 (RAW: added on top of the camera default)
    var colorNoiseReduction = 0.0      // 0...100 (RAW: added on top of the camera default)

    var toneCurve = ToneCurves()
    var hsl: [ColorBand: HSLAdjustment] = [:]
    var grading = ColorGrading()
    var calibration = Calibration()

    var geometry = Geometry()

    /// For HDR sources (gain-map HEIC/JPEG): edit and export in HDR. Ignored for SDR sources.
    var keepsHDR = true

    init() {}

    // MARK: Identity / edits

    /// True when rendering this recipe cannot change a single pixel (enables byte-exact export).
    var isIdentity: Bool { !hasEdits && geometry.isIdentity }

    /// True when any tonal/colour/effect setting differs from default (geometry excluded).
    var hasEdits: Bool {
        var r = self
        r.version = EditRecipe.currentVersion
        r.geometry = Geometry()
        r.keepsHDR = true
        r.hsl = r.hsl.filter { !$0.value.isIdentity }
        r.toneCurve = r.toneCurve.isIdentity ? ToneCurves() : r.toneCurve
        r.grading = r.grading.isIdentity ? ColorGrading() : r.grading
        r.vignette = r.vignette.isIdentity ? Vignette() : r.vignette
        r.grain = r.grain.isIdentity ? Grain() : r.grain
        if r.sharpening == 0 { r.sharpenRadius = 1.0; r.sharpenMasking = 0 }
        return r != EditRecipe.identity
    }

    func hasEdits(in group: SettingGroup) -> Bool {
        var probe = self
        probe.reset(group)
        return probe.normalizedForComparison != normalizedForComparison
    }

    private var normalizedForComparison: EditRecipe {
        var r = self
        r.hsl = r.hsl.filter { !$0.value.isIdentity }
        return r
    }

    /// Resets one group to defaults (geometry and keepsHDR are untouched).
    mutating func reset(_ group: SettingGroup) {
        let d = EditRecipe.identity
        switch group {
        case .light:
            exposure = d.exposure; contrast = d.contrast; highlights = d.highlights
            shadows = d.shadows; whites = d.whites; blacks = d.blacks
        case .color:
            temperature = d.temperature; tint = d.tint; vibrance = d.vibrance
            saturation = d.saturation; isMonochrome = d.isMonochrome
        case .effects:
            texture = d.texture; clarity = d.clarity; dehaze = d.dehaze
            vignette = d.vignette; grain = d.grain
        case .detail:
            sharpening = d.sharpening; sharpenRadius = d.sharpenRadius; sharpenMasking = d.sharpenMasking
            noiseReduction = d.noiseReduction; colorNoiseReduction = d.colorNoiseReduction
        case .curve:
            toneCurve = d.toneCurve
        case .grading:
            grading = d.grading
        case .hsl:
            hsl = d.hsl
        case .calibration:
            calibration = d.calibration
        }
    }

    /// Copies the given groups from `other` (used by Paste Settings).
    mutating func copy(_ groups: Set<SettingGroup>, from other: EditRecipe) {
        for g in groups {
            switch g {
            case .light:
                exposure = other.exposure; contrast = other.contrast; highlights = other.highlights
                shadows = other.shadows; whites = other.whites; blacks = other.blacks
            case .color:
                temperature = other.temperature; tint = other.tint; vibrance = other.vibrance
                saturation = other.saturation; isMonochrome = other.isMonochrome
            case .effects:
                texture = other.texture; clarity = other.clarity; dehaze = other.dehaze
                vignette = other.vignette; grain = other.grain
            case .detail:
                sharpening = other.sharpening; sharpenRadius = other.sharpenRadius
                sharpenMasking = other.sharpenMasking; noiseReduction = other.noiseReduction
                colorNoiseReduction = other.colorNoiseReduction
            case .curve:
                toneCurve = other.toneCurve
            case .grading:
                grading = other.grading
            case .hsl:
                hsl = other.hsl
            case .calibration:
                calibration = other.calibration
            }
        }
    }

    // MARK: HSL access

    subscript(band band: ColorBand) -> HSLAdjustment {
        get { hsl[band] ?? HSLAdjustment() }
        set { hsl[band] = newValue.isIdentity ? nil : newValue }
    }

    // MARK: Validation

    /// Every value forced into its documented range (and NaN/inf removed). The engine calls this
    /// before rendering, so a hand-edited or third-party preset can never produce garbage.
    func clamped() -> EditRecipe {
        var r = self
        r.exposure = Limits.exposure.clamp(exposure)
        let bipolarFields: [WritableKeyPath<EditRecipe, Double>] = [
            \.contrast, \.highlights, \.shadows, \.whites, \.blacks, \.temperature, \.tint,
            \.vibrance, \.saturation, \.texture, \.clarity, \.dehaze,
        ]
        for kp in bipolarFields {
            r[keyPath: kp] = Limits.bipolar.clamp(r[keyPath: kp])
        }
        r.sharpening = Limits.sharpening.clamp(sharpening)
        r.sharpenRadius = Limits.sharpenRadius.clamp(sharpenRadius)
        r.sharpenMasking = Limits.unit100.clamp(sharpenMasking)
        r.noiseReduction = Limits.unit100.clamp(noiseReduction)
        r.colorNoiseReduction = Limits.unit100.clamp(colorNoiseReduction)
        r.vignette = Vignette(amount: Limits.bipolar.clamp(vignette.amount),
                              midpoint: Limits.unit100.clamp(vignette.midpoint),
                              roundness: Limits.bipolar.clamp(vignette.roundness),
                              feather: Limits.unit100.clamp(vignette.feather),
                              highlights: Limits.unit100.clamp(vignette.highlights))
        r.grain = Grain(amount: Limits.unit100.clamp(grain.amount),
                        size: Limits.unit100.clamp(grain.size),
                        roughness: Limits.unit100.clamp(grain.roughness))
        r.toneCurve = ToneCurves(master: CurveMath.sanitize(toneCurve.master),
                                 red: CurveMath.sanitize(toneCurve.red),
                                 green: CurveMath.sanitize(toneCurve.green),
                                 blue: CurveMath.sanitize(toneCurve.blue))
        var bands: [ColorBand: HSLAdjustment] = [:]
        for (band, a) in hsl {
            let c = HSLAdjustment(hue: Limits.bipolar.clamp(a.hue),
                                  saturation: Limits.bipolar.clamp(a.saturation),
                                  luminance: Limits.bipolar.clamp(a.luminance))
            if !c.isIdentity { bands[band] = c }
        }
        r.hsl = bands
        func wheel(_ w: GradeWheel) -> GradeWheel {
            var h = w.hue.isFinite ? w.hue.truncatingRemainder(dividingBy: 360) : 0
            if h < 0 { h += 360 }
            return GradeWheel(hue: h, saturation: Limits.unit100.clamp(w.saturation),
                              luminance: Limits.bipolar.clamp(w.luminance))
        }
        r.grading = ColorGrading(shadows: wheel(grading.shadows), midtones: wheel(grading.midtones),
                                 highlights: wheel(grading.highlights), global: wheel(grading.global),
                                 blending: Limits.unit100.clamp(grading.blending),
                                 balance: Limits.bipolar.clamp(grading.balance))
        let c = calibration
        r.calibration = Calibration(shadowTint: Limits.bipolar.clamp(c.shadowTint),
                                    redHue: Limits.bipolar.clamp(c.redHue),
                                    redSaturation: Limits.bipolar.clamp(c.redSaturation),
                                    greenHue: Limits.bipolar.clamp(c.greenHue),
                                    greenSaturation: Limits.bipolar.clamp(c.greenSaturation),
                                    blueHue: Limits.bipolar.clamp(c.blueHue),
                                    blueSaturation: Limits.bipolar.clamp(c.blueSaturation))
        r.geometry = geometry.clamped()
        return r
    }

    /// Documented parameter ranges (shared by UI sliders, preset import and the engine).
    enum Limits {
        static let exposure = ParamRange(-5, 5)
        static let bipolar = ParamRange(-100, 100)
        static let unit100 = ParamRange(0, 100)
        static let sharpening = ParamRange(0, 150)
        static let sharpenRadius = ParamRange(0.5, 3)
        static let straighten = ParamRange(-45, 45)
        static let amount = ParamRange(0, 200)     // preset Amount, percent
    }

    // MARK: Codable (tolerant: missing keys fall back to defaults, so older files keep loading)

    enum CodingKeys: String, CodingKey {
        case version, exposure, contrast, highlights, shadows, whites, blacks
        case temperature, tint, vibrance, saturation, isMonochrome
        case texture, clarity, dehaze, vignette, grain
        case sharpening, sharpenRadius, sharpenMasking, noiseReduction, colorNoiseReduction
        case toneCurve, hsl, grading, calibration, geometry, keepsHDR
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EditRecipe.identity
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        version = v(.version, d.version)
        exposure = v(.exposure, d.exposure)
        contrast = v(.contrast, d.contrast)
        highlights = v(.highlights, d.highlights)
        shadows = v(.shadows, d.shadows)
        whites = v(.whites, d.whites)
        blacks = v(.blacks, d.blacks)
        temperature = v(.temperature, d.temperature)
        tint = v(.tint, d.tint)
        vibrance = v(.vibrance, d.vibrance)
        saturation = v(.saturation, d.saturation)
        isMonochrome = v(.isMonochrome, d.isMonochrome)
        texture = v(.texture, d.texture)
        clarity = v(.clarity, d.clarity)
        dehaze = v(.dehaze, d.dehaze)
        vignette = v(.vignette, d.vignette)
        grain = v(.grain, d.grain)
        sharpening = v(.sharpening, d.sharpening)
        sharpenRadius = v(.sharpenRadius, d.sharpenRadius)
        sharpenMasking = v(.sharpenMasking, d.sharpenMasking)
        noiseReduction = v(.noiseReduction, d.noiseReduction)
        colorNoiseReduction = v(.colorNoiseReduction, d.colorNoiseReduction)
        toneCurve = v(.toneCurve, d.toneCurve)
        hsl = v(.hsl, d.hsl)
        grading = v(.grading, d.grading)
        calibration = v(.calibration, d.calibration)
        geometry = v(.geometry, d.geometry)
        keepsHDR = v(.keepsHDR, d.keepsHDR)
    }
}

/// A closed numeric range with clamping that also removes NaN / infinity.
struct ParamRange: Hashable, Sendable {
    let lower: Double
    let upper: Double
    init(_ lower: Double, _ upper: Double) { self.lower = lower; self.upper = upper }
    var closed: ClosedRange<Double> { lower...upper }
    func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return min(max(0, lower), upper) }
        return min(max(v, lower), upper)
    }
}

// MARK: - RAW stage

/// Settings that are applied while decoding a RAW file (CIRAWFilter), where they are lossless:
/// white balance on sensor data, exposure before the tone curve, noise reduction before demosaic
/// artefacts are amplified. For non-RAW sources the RecipeRenderer applies exposure/WB itself.
struct RAWStageSettings: Hashable, Sendable {
    var kelvin: Float            // CIRAWFilter.neutralTemperature (2000...50000)
    var tint: Float              // CIRAWFilter.neutralTint (-150...150)
    var exposureEV: Float        // added to the filter's default exposure
    var luminanceNR: Float       // 0...1 extra amount above the camera default (0 = camera default)
    var colorNR: Float           // 0...1 extra amount above the camera default (0 = camera default)
    var hdr: Bool                // extendedDynamicRangeAmount > 0

    /// Incremental temperature/tint (Lightroom JPEG scale) mapped around the as-shot white balance:
    /// ±100 temperature == ∓150 mired (warmer = higher kelvin), ±100 tint == ±150 tint units.
    init(recipe r: EditRecipe, asShotKelvin: Double, asShotTint: Double, sourceIsHDR: Bool) {
        let asShot = min(max(asShotKelvin, 2000), 50000)
        let mired = max(1_000_000 / asShot - 1.5 * r.temperature, 20)   // 20 mired == 50000 K
        kelvin = Float(min(max(1_000_000 / mired, 2000), 50000))
        tint = Float(min(max(asShotTint + 1.5 * r.tint, -150), 150))
        exposureEV = Float(r.exposure)
        luminanceNR = Float(r.noiseReduction / 100)
        colorNR = Float(r.colorNoiseReduction / 100)
        hdr = sourceIsHDR && r.keepsHDR
    }
}
