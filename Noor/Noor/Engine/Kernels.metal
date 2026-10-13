//
//  Kernels.metal  -  Noor Core Image kernels (Metal Shading Language for Core Image)
//
//  Build (target Build Settings):
//    Other Metal Compiler Flags  (MTL_COMPILER_FLAGS) = -fcikernel
//    User-Defined                (MTLLINKER_FLAGS)    = -cikernel
//  Keep ALL Core Image kernels + their helpers in THIS ONE file (one default.metallib).
//  Swift side: Engine/NoorKernels.swift (loading + wrappers), Engine/RecipeRenderer.swift (pipeline).
//
//  Kernels (pipeline order):
//    noorChromaDenoise, noorLumaDenoise   noise reduction (non-RAW sources)
//    noorDehazeDark, noorDehaze           dark-channel dehaze
//    noorTone                             exposure (non-RAW), highlights/shadows, contrast, whites, blacks
//    noorLocalContrast                    clarity / texture / sharpening (with "masking" edge gate)
//    noorCurves                           point curve LUT (general kernel, samplers)
//    noorColorMatrix                      calibration primaries (3x3 matrix built in Swift)
//    noorHSL                              vibrance / saturation / HSL colour mixer
//    noorMonochrome                       B&W conversion with per-band mix (replaces noorHSL)
//    noorGrade                            colour grading wheels (also the calibration shadow tint)
//    noorResample                         straighten rotation, Catmull-Rom with anti-ringing
//    noorVignette, noorGrain              post-crop effects
//    noorOutputFit                        the only bounding step (SDR / headroom targets)
//    noorOutputCeiling                    its wide-gamut SDR variant (Adobe RGB / ProPhoto exports)
//
//  Conventions (every kernel):
//    * Input/output: premultiplied RGBA, LINEAR, EXTENDED range (values may be > 1 or < 0),
//      expressed in the CIContext working space (default below: extendedLinearDisplayP3).
//    * Nothing is clamped. The only bounding step is noorOutputFit / noorOutputCeiling (final output stage).
//    * Fast-math safe: no division by a value that can be 0, no log2/pow of values <= 0,
//      no mix()/smoothstep() outside their defined domains.
//    * Size-based effects receive sizes in RENDER pixels or normalized units from Swift,
//      so the preview proxy and the full-resolution export use the same recipe.
//    * Every kernel returns its input (to float rounding) at default parameters; Swift also
//      skips the call entirely in that case, so an untouched recipe stays bit-exact.
//
#include <CoreImage/CoreImage.h>
using namespace metal;

// Working space: must match CIContextOption.workingColorSpace. Default = linear Display P3.
#if !defined(NOOR_WS_SRGB) && !defined(NOOR_WS_REC2020)
#define NOOR_WS_P3 1
#endif

// 1 / std-dev of the 2-octave value noise below (measured, see stub test) -> unit variance grain.
#ifndef NOOR_GRAIN_NORM
#define NOOR_GRAIN_NORM 1.3464f
#endif
// Footprint attenuation constant, fitted so preview std == box-downsampled export std (within ~0.90-1.14, see test).
#ifndef NOOR_GRAIN_ATTEN_K
#define NOOR_GRAIN_ATTEN_K 1.05f
#endif

namespace noor {

// ---------------------------------------------------------------------------------------------
// Working-space constants. toLMS rows are normalised to sum to 1 so that D65 white maps to
// LMS (1,1,1) -> OKLab a = b = 0 exactly (neutrals never pick up a tint).
// ---------------------------------------------------------------------------------------------
#if defined(NOOR_WS_P3)
static inline float3 lumaW()    { return float3(0.2289745641f, 0.6917385218f, 0.0792869141f); }
static inline float3 toLMS0()   { return float3(0.4813798551f, 0.4621183723f, 0.0565017725f); }
static inline float3 toLMS1()   { return float3(0.2288319424f, 0.6532168190f, 0.1179512386f); }
static inline float3 toLMS2()   { return float3(0.0839457536f, 0.2241652693f, 0.6918889771f); }
static inline float3 fromLMS0() { return float3(3.1277689573f, -2.2571357663f, 0.1293668090f); }
static inline float3 fromLMS1() { return float3(-1.0910090160f, 2.4133317135f, -0.3223226975f); }
static inline float3 fromLMS2() { return float3(-0.0260108092f, -0.5080413222f, 1.5340521314f); }
#elif defined(NOOR_WS_REC2020)
static inline float3 lumaW()    { return float3(0.2627002120f, 0.6779980715f, 0.0593017165f); }
static inline float3 toLMS0()   { return float3(0.6167557879f, 0.3601984021f, 0.0230458100f); }
static inline float3 toLMS1()   { return float3(0.2651330603f, 0.6358393714f, 0.0990275683f); }
static inline float3 toLMS2()   { return float3(0.1001026313f, 0.2039065205f, 0.6959908482f); }
static inline float3 fromLMS0() { return float3(2.1399067200f, -1.2463894955f, 0.1064827755f); }
static inline float3 fromLMS1() { return float3(-0.8847358342f, 2.1632309413f, -0.2784951071f); }
static inline float3 fromLMS2() { return float3(-0.0485737534f, -0.4545031403f, 1.5030768938f); }
#else // NOOR_WS_SRGB (Core Image default working space: extended linear sRGB)
static inline float3 lumaW()    { return float3(0.2126390059f, 0.7151686788f, 0.0721923154f); }
static inline float3 toLMS0()   { return float3(0.4122214714f, 0.5363325387f, 0.0514459899f); }
static inline float3 toLMS1()   { return float3(0.2119034963f, 0.6806995503f, 0.1073969533f); }
static inline float3 toLMS2()   { return float3(0.0883024602f, 0.2817188378f, 0.6299787021f); }
static inline float3 fromLMS0() { return float3(4.0767416183f, -3.3077115445f, 0.2309699262f); }
static inline float3 fromLMS1() { return float3(-1.2684379701f, 2.6097573528f, -0.3413193826f); }
static inline float3 fromLMS2() { return float3(-0.0041960840f, -0.7034186077f, 1.7076146917f); }
#endif

static inline float luma(float3 c) { return dot(c, lumaW()); }

// Sign-preserving power. Never evaluates log2(0) or pow(negative, y).
static inline float spow(float x, float p) {
    float a = abs(x);
    float r = exp2(p * log2(max(a, 1e-20f)));
    r = (a < 1e-20f) ? 0.0f : r;
    return (x < 0.0f) ? -r : r;
}

// Perceptual encoding used by tone/curves/grain/vignette: pure power 1/2.2, odd-symmetric,
// C-infinity for x > 0, enc(1) = 1, extends naturally above 1 (HDR) and below 0.
static inline float enc(float y) { return spow(y, 0.45454545f); }
static inline float dec(float p) { return spow(p, 2.2f); }

// p + d, but never crosses 0 when d < 0 (smooth, monotone in d, ~p + d for |d| << p).
static inline float addPositive(float p, float d) {
    return (d >= 0.0f) ? (p + d) : (p / (1.0f - d / max(p, 1e-6f)));
}

// Smooth floor: identity above k, decays exponentially toward 0 below k (C1 at k, always > 0).
static inline float softFloor(float x, float k) {
    return (x >= k) ? x : k * exp(max(x / k - 1.0f, -80.0f));
}

// Retarget luminance Y -> Yt while keeping chromaticity (all channels scaled by one gain).
// When the required gain exceeds kMaxGain (Y ~ 0, e.g. lifting pure black) the remainder is
// added as neutral (D65) light: luma(float3(1)) == 1 in every working space above.
static inline float3 retargetLuma(float3 rgb, float Y, float Yt) {
    const float kMaxGain = 64.0f;
    float Ys = max(Y, 0.0f);
    float Yp = max(Yt, 0.0f);
    float g = min(Yp / max(Ys, 1e-8f), kMaxGain);
    float off = max(Yp - g * Ys, 0.0f);
    return rgb * g + float3(off);
}

// OKLab (Ottosson) from the linear working space. Signed cube root keeps extended-range and
// out-of-gamut (negative) values finite and invertible.
static inline float3 toOklab(float3 c) {
    float l = spow(dot(toLMS0(), c), 0.33333333f);
    float m = spow(dot(toLMS1(), c), 0.33333333f);
    float s = spow(dot(toLMS2(), c), 0.33333333f);
    float3 lms = float3(l, m, s);
    return float3(dot(float3(0.2104542553f, 0.7936177850f, -0.0040720468f), lms),
                  dot(float3(1.9779984951f, -2.4285922050f, 0.4505937099f), lms),
                  dot(float3(0.0259040371f, 0.7827717662f, -0.8086757660f), lms));
}

static inline float3 fromOklab(float3 lab) {
    float l = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    float3 lms = float3(l * l * l, m * m * m, s * s * s);
    return float3(dot(fromLMS0(), lms), dot(fromLMS1(), lms), dot(fromLMS2(), lms));
}

// (cos x, sin x) by Taylor series: exact at 0 (identity stays bit-identical), error < 3e-8 for
// |x| <= 1, independent of fast-math trig accuracy (fast sin/cos: abs error up to 2^-13).
static inline float2 cosSinSmall(float x) {
    float t = clamp(x, -1.5707963f, 1.5707963f);
    float t2 = t * t;
    float c = 1.0f + t2 * (-0.5f + t2 * (0.0416666667f + t2 * (-0.0013888889f + t2 * (0.0000248016f - t2 * 0.0000002756f))));
    float s = t * (1.0f + t2 * (-0.1666666667f + t2 * (0.0083333333f + t2 * (-0.0001984127f + t2 * (0.0000027557f - t2 * 0.0000000251f)))));
    return float2(c, s);
}

// ---------------------------------------------------------------------------------------------
// Tone (Lightroom PV2012-style) - all curves are strictly monotone by construction.
// q is perceptual luminance (enc of linear Y): 0 = black, 1 = SDR diffuse white, > 1 = HDR.
// ---------------------------------------------------------------------------------------------

// Shadows: bump q(1-q)^2 (peak 4/27 at q=1/3, |slope| <= 1). Gain 0.9 (lift) / 0.6 (darken)
// keeps the slope >= 0.1; darkening is gentler because the 2.2 power amplifies it in linear.
static inline float toneShadows(float q, float amt) {
    if (q <= 0.0f || q >= 1.0f) return q;
    float w = q * (1.0f - q) * (1.0f - q);
    return q + ((amt > 0.0f) ? 0.9f : 0.6f) * amt * w;
}

// Highlights: amt > 0 brightens upper tones (bump q^2(1-q), white point fixed);
// amt < 0 is a rational shoulder from a knee at 0.55 that also pulls super-white (HDR / RAW)
// data back toward white = highlight recovery.
static inline float toneHighlights(float q, float amt) {
    if (amt >= 0.0f) {
        if (q <= 0.0f || q >= 1.0f) return q;
        float w = q * q * (1.0f - q);
        return q + 0.9f * amt * w;
    }
    const float k = 0.55f;
    if (q <= k) return q;
    float s = -amt * 0.6f;
    float x = (q - k) / (1.0f - k);
    return k + (1.0f - k) * x / (1.0f + s * x);
}

// Whites: q^3 weight, endpoint moves by 0.2 * amt, linear (C1) continuation above 1.
static inline float toneWhites(float q, float amt) {
    if (q <= 0.0f) return q;
    if (q <= 1.0f) return q + 0.2f * amt * q * q * q;
    return q + 0.2f * amt * (1.0f + 3.0f * (q - 1.0f));
}

// Blacks: amt < 0 crushes with f(q) = q^2 (1+t)/(q+t)  (f(0)=0, f(1)=1, f' >= 0);
//         amt > 0 lifts with the exact inverse of the same curve (so +x then -x cancels).
static inline float toneBlacks(float q, float amt) {
    if (q <= 0.0f || q >= 1.0f) return q;
    float t = 0.1f * abs(amt);
    if (t < 1e-6f) return q;
    if (amt < 0.0f) return q * q * (1.0f + t) / (q + t);
    return (q + sqrt(q * q + 4.0f * (1.0f + t) * t * q)) / (2.0f * (1.0f + t));
}

// Contrast: blend toward a piecewise-power S-curve pivoting at middle grey
// (enc(0.18) = 0.4587). Gamma 1.9 => S' in [0, 1.9]; |k| <= 0.75 => slope >= 0.25.
static inline float toneContrast(float q, float amt) {
    const float pivot = 0.4587f;
    const float g = 1.9f;
    float k = 0.75f * amt;
    if (q <= 0.0f) return q * (1.0f - k);
    if (q >= 1.0f) return 1.0f + (q - 1.0f) * min(1.0f - k, 1.0f);   // never expand HDR
    float sc = (q < pivot)
        ? pivot * spow(q / pivot, g)
        : 1.0f - (1.0f - pivot) * spow((1.0f - q) / (1.0f - pivot), g);
    return q + k * (sc - q);
}

// ---------------------------------------------------------------------------------------------
// HSL band lookup. Band centres = OKLCH hue of sRGB HSL hues 0,30,60,120,180,240,270,300
// (Lightroom: red, orange, yellow, green, aqua, blue, purple, magenta).
// Weights form a partition of unity with smoothstep (C1) transitions between neighbours.
// ---------------------------------------------------------------------------------------------
struct BandPos {
    int i;      // segment start band 0..7 (segment i -> i+1, band 8 == band 0)
    float t;    // smooth weight of band i+1
};

static inline BandPos bandPos(float hueDeg) {
    float c[9] = {29.23f, 52.77f, 109.79f, 142.51f, 194.81f, 264.06f, 293.77f, 328.35f, 389.23f};
    float h = (hueDeg < c[0]) ? (hueDeg + 360.0f) : hueDeg;
    int i = 0;
    for (int k = 1; k < 8; ++k) {
        if (h >= c[k]) i = k;
    }
    float t = clamp((h - c[i]) / (c[i + 1] - c[i]), 0.0f, 1.0f);
    BandPos r;
    r.i = i;
    r.t = t * t * (3.0f - 2.0f * t);
    return r;
}

static inline float bandValue(BandPos b, float4 lo, float4 hi) {
    float v[9] = {lo.x, lo.y, lo.z, lo.w, hi.x, hi.y, hi.z, hi.w, lo.x};
    return v[b.i] + (v[b.i + 1] - v[b.i]) * b.t;
}

static inline float bandWeight(BandPos b, int band) {
    int j = (b.i + 1) % 8;
    float w = 0.0f;
    if (b.i == band) w += 1.0f - b.t;
    if (j == band) w += b.t;
    return w;
}

// ---------------------------------------------------------------------------------------------
// Film grain: integer hash (deterministic on every GPU) + value noise.
// ---------------------------------------------------------------------------------------------
static inline uint hash3(uint x, uint y, uint z) {
    uint h = (x * 0x8da6b343u) ^ (y * 0xd8163841u) ^ (z * 0xcb1ab31fu);
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return h;
}

// Triangular-distributed lattice value with unit variance.
static inline float latticeValue(int x, int y, uint seed) {
    uint h = hash3(uint(x), uint(y), seed);
    float u1 = float(h & 0xffffu) * (1.0f / 65536.0f);
    float u2 = float(h >> 16) * (1.0f / 65536.0f);
    return (u1 + u2 - 1.0f) * 2.4494897f;
}

static inline float valueNoise(float2 p, uint seed) {
    float2 i = floor(p);
    float2 f = p - i;
    int ix = int(i.x);
    int iy = int(i.y);
    float v00 = latticeValue(ix, iy, seed);
    float v10 = latticeValue(ix + 1, iy, seed);
    float v01 = latticeValue(ix, iy + 1, seed);
    float v11 = latticeValue(ix + 1, iy + 1, seed);
    float2 u = f * f * (3.0f - 2.0f * f);
    return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

// One grain octave. P: full-res pixel coords; cell: grain cell (full-res px); fp: full-res px per
// render px. The lattice is rotated (cs = cos/sin) so pixel centres never sit at a fixed phase
// (no periodic pattern). If a render pixel spans several cells, the noise is evaluated at the
// render-pixel scale and its amplitude follows the box-average law sigma ~ 1/sqrt(1+(fp/cell/K)^2)
// (asymptote K*cell/fp, the 1/sqrt(N) law for averaging N independent cells; K fitted on CPU).
// Returns ~unit variance when fp << cell.
static inline float grainOctave(float2 P, float cell, float fp, float2 cs, float2 offset, uint seed) {
    float ce = max(cell, fp);
    float r = fp / max(cell, 1e-3f);
    float g = 1.0f / sqrt(1.0f + r * r * (1.0f / (NOOR_GRAIN_ATTEN_K * NOOR_GRAIN_ATTEN_K)));
    float2 q = float2(cs.x * P.x - cs.y * P.y, cs.y * P.x + cs.x * P.y) / ce + offset;
    return valueNoise(q, seed) * NOOR_GRAIN_NORM * g;
}

// Two octaves (second 2.17x finer, different rotation). roughness 0 = even, 1 = clumpy.
static inline float grainNoise(float2 P, float cell, float fp, uint seed, float roughness) {
    float r = clamp(roughness, 0.0f, 1.0f);
    float n1 = grainOctave(P, cell, fp, float2(0.8f, 0.6f), float2(0.0f), seed);
    float n2 = grainOctave(P, cell * 0.4608295f, fp, float2(0.9230769f, -0.3846154f), float2(17.31f, 41.93f), seed ^ 0x9e3779b9u);
    return (n1 + r * n2) / sqrt(1.0f + r * r);
}

} // namespace noor

extern "C" {
namespace coreimage {

// =============================================================================================
// 1. TONE  (CIColorKernel)  exposure, contrast, highlights, shadows, whites, blacks
//    base: low-frequency, edge-preserving copy of the image (see Swift); pass the image itself
//    for purely global behaviour. Highlights/Shadows are evaluated on the base (local
//    adaptation, detail preserved); Contrast/Whites/Blacks act on the pixel itself.
//    Sliders are Lightroom value / 100 (-1...1); exposureEV in stops; localAmount 0...1.
// =============================================================================================
float4 noorTone(sample_t s, sample_t base, float exposureEV, float contrast, float highlights,
                float shadows, float whites, float blacks, float localAmount)
{
    float4 c = unpremultiply(s);
    float gain = exp2(exposureEV);
    float3 rgb = c.rgb * gain;
    float Y = max(noor::luma(rgb), 0.0f);
    float Bl = max(noor::luma(unpremultiply(base).rgb) * gain, 0.0f);
    float B = Y + (Bl - Y) * clamp(localAmount, 0.0f, 1.0f);

    // Local stage: highlights / shadows on the base, applied as a smooth gain.
    float qB = noor::enc(B);
    float qB2 = noor::toneShadows(noor::toneHighlights(qB, highlights), shadows);
    const float eps = 1e-5f;
    float gLocal = (noor::dec(qB2) + eps) / (B + eps);
    float Y1 = Y * gLocal;

    // Global stage on the pixel: contrast -> whites -> blacks.
    float q = noor::enc(Y1);
    q = noor::toneContrast(q, contrast);
    q = noor::toneWhites(q, whites);
    q = noor::toneBlacks(q, blacks);
    float Yt = noor::dec(q);

    return premultiply(float4(noor::retargetLuma(rgb, Y, Yt), c.a));
}

// =============================================================================================
// 2. HSL MIXER + VIBRANCE/SATURATION  (CIColorKernel), in OKLCH.
//    hueLo/hueHi : per-band hue rotation in RADIANS   (bands 0-3 / 4-7, order R O Y G A B P M)
//    satLo/satHi : per-band chroma change  -1...1      (-1 = fully desaturate band)
//    lumLo/lumHi : per-band log2 multiplier on OKLab L (+-0.5 ~ +-1.5 EV)
//    vibrance, saturation: Lightroom value / 100.
// =============================================================================================
float4 noorHSL(sample_t s, float4 hueLo, float4 hueHi, float4 satLo, float4 satHi,
               float4 lumLo, float4 lumHi, float vibrance, float saturation)
{
    float4 c = unpremultiply(s);
    float3 lab = noor::toOklab(c.rgb);
    float C = length(float2(lab.y, lab.z));
    if (C < 1e-6f) return s;                      // neutral: no hue, nothing to change

    float hue = atan2(lab.z, lab.y) * 57.29577951f;
    if (hue < 0.0f) hue += 360.0f;
    noor::BandPos bp = noor::bandPos(hue);

    // Global saturation + vibrance (vibrance favours low-chroma colours, protects skin/orange).
    float skin = noor::bandWeight(bp, 1);
    float lowChroma = 1.0f - clamp(C / 0.25f, 0.0f, 1.0f);
    float vib = vibrance * lowChroma * ((vibrance > 0.0f) ? (1.0f - 0.6f * skin) : 1.0f);
    float chromaGain = max(1.0f + saturation, 0.0f) * max(1.0f + vib, 0.0f);

    // Per-band mixer (weights from the ORIGINAL hue).
    float dh = noor::bandValue(bp, hueLo, hueHi);
    float ds = noor::bandValue(bp, satLo, satHi);
    float dl = noor::bandValue(bp, lumLo, lumHi);
    float colorful = smoothstep(0.0f, 0.06f, C);  // luminance moves only coloured pixels
    float Lgain = exp2(dl * colorful);
    chromaGain *= max(1.0f + ds, 0.0f) * sqrt(Lgain);   // keep saturation ~constant when L moves

    float2 cs = noor::cosSinSmall(dh);
    float a = (lab.y * cs.x - lab.z * cs.y) * chromaGain;
    float b = (lab.y * cs.y + lab.z * cs.x) * chromaGain;
    float3 outRGB = noor::fromOklab(float3(lab.x * Lgain, a, b));
    return premultiply(float4(outRGB, c.a));
}

// =============================================================================================
// 3. COLOR GRADING  (CIColorKernel), Lightroom 3-way + global wheels, in OKLab.
//    each wheel float3 = (da, db, dLog2L): da/db = OKLab chroma offset per unit lightness
//    (computed in Swift from wheel hue/saturation), dLog2L = region luminance (log2 on L).
//    blending 0...1 (LR 0...100, default 0.5), balance -1...1 (LR -100...100, default 0).
// =============================================================================================
float4 noorGrade(sample_t s, float3 shadowsW, float3 midtonesW, float3 highlightsW,
                 float3 globalW, float blending, float balance)
{
    float4 c = unpremultiply(s);
    float3 lab = noor::toOklab(c.rgb);
    float L = max(lab.x, 0.0f);

    float t = noor::spow(clamp(L, 0.0f, 1.0f), exp2(-clamp(balance, -1.0f, 1.0f)));
    float w = 0.06f + 0.24f * clamp(blending, 0.0f, 1.0f);
    float ws = 1.0f - smoothstep(0.33333333f - w, 0.33333333f + w, t);
    float wh = smoothstep(0.66666667f - w, 0.66666667f + w, t);
    float wm = (1.0f - ws) * (1.0f - wh);
    float norm = 1.0f / (ws + wm + wh);           // == 1 / (1 + ws*wh) >= 0.5, never 0

    float3 g = (shadowsW * ws + midtonesW * wm + highlightsW * wh) * norm + globalW;
    float3 outLab = float3(lab.x * exp2(g.z), lab.y + g.x * L, lab.z + g.y * L);
    return premultiply(float4(noor::fromOklab(outLab), c.a));
}

// =============================================================================================
// 4. TONE CURVES  (CIKernel - needs a sampler for the LUT)
//    lut: lutWidth x 2 RGBAf image, extent (0,0,lutWidth,2), colorSpace nil (not colour managed)
//         row 0 (y = 0.5): master curve (in R; G,B duplicates; A = 1)
//         row 1 (y = 1.5): per-channel curves in R, G, B (A = 1)
//    Domain/range: enc() values 0...1; outside that the end slopes are extrapolated (HDR safe).
//    ROI: index 0 -> rect, index 1 -> lut.extent.
// =============================================================================================
float4 noorCurves(sampler src, sampler lut, float lutWidth)
{
    float4 c = unpremultiply(src.sample(src.coord()));
    float last = max(lutWidth - 1.0f, 1.0f);
    float3 e = float3(noor::enc(c.r), noor::enc(c.g), noor::enc(c.b));
    float3 outE = float3(0.0f);

    for (int pass = 0; pass < 2; ++pass) {
        float row = (pass == 0) ? 0.5f : 1.5f;
        for (int ch = 0; ch < 3; ++ch) {
            float v = (ch == 0) ? e.x : ((ch == 1) ? e.y : e.z);
            float x = clamp(v, 0.0f, 1.0f) * last;
            float4 f = lut.sample(lut.transform(float2(x + 0.5f, row)));
            if (v < 0.0f) {
                float4 f1 = lut.sample(lut.transform(float2(1.5f, row)));
                f = f + (f1 - f) * (v * last);
            } else if (v > 1.0f) {
                float4 f0 = lut.sample(lut.transform(float2(last - 0.5f, row)));
                f = f + (f - f0) * ((v - 1.0f) * last);
            }
            // master row: all channels hold the master curve -> take R
            float r = (pass == 0) ? f.x : ((ch == 0) ? f.x : ((ch == 1) ? f.y : f.z));
            if (ch == 0) outE.x = r; else if (ch == 1) outE.y = r; else outE.z = r;
        }
        e = outE;
    }
    float3 rgb = float3(noor::dec(e.x), noor::dec(e.y), noor::dec(e.z));
    return premultiply(float4(rgb, c.a));
}

// =============================================================================================
// 5. FILM GRAIN  (CIColorKernel + destination)
//    origin        : extent.origin of the (cropped) image in render space
//    fullPerRender : full-resolution pixels per render pixel (= 1 / renderScale; 1 at export)
//    cellFull      : grain cell size in FULL-RES pixels (Swift derives it from Size and the
//                    full-res long edge, so grain scales with the picture)
//    amount 0...1, roughness 0...1, seed: integer-valued float (a constant from Swift, so the
//    pattern never changes between renders, previews and exports)
//    Grain is evaluated at full-res coordinates (anchored to the image origin, so it does not
//    swim when panning); when a render pixel covers more than one grain cell the noise is
//    evaluated at render-pixel scale with an analytically reduced amplitude (box-average law),
//    which statistically matches downsampling the full-res export (see test: ratio ~1).
// =============================================================================================
float4 noorGrain(sample_t s, float2 origin, float fullPerRender, float cellFull, float amount,
                 float roughness, float seed, destination dest)
{
    float4 c = unpremultiply(s);
    float Y = max(noor::luma(c.rgb), 0.0f);
    float p = noor::enc(Y);
    float mid = sqrt(clamp(4.0f * p * (1.0f - p), 0.0f, 1.0f));   // 0 at black/white

    float fpr = max(fullPerRender, 1e-3f);
    float2 P = (dest.coord() - origin) * fpr;                      // full-res pixel coords
    float n = noor::grainNoise(P, max(cellFull, 0.05f), fpr, uint(max(seed, 0.0f)), roughness);

    float d = clamp(amount, 0.0f, 1.0f) * 0.06f * mid * n;
    float Yt = noor::dec(noor::addPositive(p, d));
    return premultiply(float4(noor::retargetLuma(c.rgb, Y, Yt), c.a));
}

// =============================================================================================
// 6. POST-CROP VIGNETTE  (CIColorKernel + destination)
//    rect = crop rectangle in render space (x, y, w, h)  -> resolution independent
//    amount -1...1, midpoint 0...1, roundness -1...1, feather 0...1, highlights 0...1
// =============================================================================================
float4 noorVignette(sample_t s, float4 rect, float amount, float midpoint, float roundness,
                    float feather, float highlights, destination dest)
{
    float4 c = unpremultiply(s);
    float2 hs = max(rect.zw * 0.5f, float2(1.0f));
    float2 center = rect.xy + hs;
    float r = clamp(roundness, -1.0f, 1.0f);
    float rc = sqrt(hs.x * hs.y);
    float2 radii = (r > 0.0f) ? (hs + (float2(rc) - hs) * r) : hs;   // r>0: toward a circle
    float n = (r < 0.0f) ? (2.0f - 6.0f * r) : 2.0f;                 // r<0: toward a rectangle
    float2 u = abs(dest.coord() - center) / radii;
    float d = noor::spow(noor::spow(u.x, n) + noor::spow(u.y, n), 1.0f / n);

    float r0 = 0.25f + clamp(midpoint, 0.0f, 1.0f);
    float hw = max(clamp(feather, 0.0f, 1.0f) * r0, 0.005f);
    float v = smoothstep(r0 - hw, r0 + hw, d);

    float Y = max(noor::luma(c.rgb), 0.0f);
    float p = noor::enc(Y);
    float a = clamp(amount, -1.0f, 1.0f);
    float Yt;
    if (a < 0.0f) {
        float protect = clamp(highlights, 0.0f, 1.0f) * smoothstep(0.5f, 1.0f, p);
        Yt = Y * exp2(a * 2.5f * v * (1.0f - protect));           // up to -2.5 EV
    } else {
        float pt = (p < 1.0f) ? (p + (1.0f - p) * a * 0.85f * v) : p;
        Yt = noor::dec(pt);
    }
    return premultiply(float4(noor::retargetLuma(c.rgb, Y, Yt), c.a));
}

// =============================================================================================
// 7a. DEHAZE pass 1 (CIColorKernel): normalised dark channel  min_c( I_c / A_c ).
//     Run on a small, fixed-size copy (e.g. long edge 512); followed in Swift by
//     CIMorphologyMinimum (patch), a Gaussian blur and CIEdgePreserveUpsample to render size.
// =============================================================================================
float4 noorDehazeDark(sample_t s, float3 airlight)
{
    float4 c = unpremultiply(s);
    float3 nrm = c.rgb / max(airlight, float3(1e-3f));
    float d = min(nrm.x, min(nrm.y, nrm.z));
    return float4(d, d, d, 1.0f);
}

// 7b. DEHAZE pass 2 (CIColorKernel): J = (I - A) / t + A, t = 1 - omega * dark.
//     amount -1...1 (LR Dehaze / 100); omega ~0.95; tMin ~0.1. Negative amount adds haze.
float4 noorDehaze(sample_t s, sample_t dark, float3 airlight, float amount, float omega, float tMin)
{
    float4 c = unpremultiply(s);
    float t = clamp(1.0f - omega * dark.r, max(tMin, 0.02f), 1.0f);
    float a = clamp(amount, -1.0f, 1.0f);
    if (a == 0.0f) return s;
    float3 rgb;
    if (a > 0.0f) {
        float te = 1.0f + (t - 1.0f) * a;                          // in [t, 1], never 0
        rgb = (c.rgb - airlight) / te + airlight;
        rgb = float3(noor::softFloor(rgb.x, 1e-4f), noor::softFloor(rgb.y, 1e-4f),
                     noor::softFloor(rgb.z, 1e-4f));
    } else {
        float h = -a * 0.7f * (1.0f - 0.5f * t);                   // more haze where already hazy
        rgb = c.rgb + (airlight - c.rgb) * h;
    }
    return premultiply(float4(rgb, c.a));
}

// =============================================================================================
// 8. LOCAL CONTRAST - Clarity / Texture / Sharpening  (CIColorKernel)
//    detail = enc(luma(fine)) - enc(luma(coarse))
//      Clarity  : fine = image,          coarse = big blur (edge-aware recommended), midtoneFocus 1
//      Texture  : fine = small blur,     coarse = medium blur,                     midtoneFocus 0.3
//      Sharpen  : fine = image,          coarse = Gaussian(radius),                midtoneFocus 0
//    amount: signed gain (negative = soften), threshold: detail gate ("Masking"), maxDelta: soft
//    limit on the perceptual change (prevents halos / clipping).
// =============================================================================================
float4 noorLocalContrast(sample_t s, sample_t fine, sample_t coarse, float amount,
                         float midtoneFocus, float threshold, float maxDelta)
{
    float4 c = unpremultiply(s);
    float Y = max(noor::luma(c.rgb), 0.0f);
    float p = noor::enc(Y);
    float pf = noor::enc(max(noor::luma(unpremultiply(fine).rgb), 0.0f));
    float pc = noor::enc(max(noor::luma(unpremultiply(coarse).rgb), 0.0f));
    float detail = pf - pc;

    float th = max(threshold, 0.0f);
    float gate = smoothstep(th, 2.0f * th + 1e-5f, abs(detail));
    float pm = clamp(p, 0.0f, 1.0f);
    float midW = clamp(4.0f * pm * (1.0f - pm), 0.0f, 1.0f);
    float focus = 1.0f + (midW - 1.0f) * clamp(midtoneFocus, 0.0f, 1.0f);

    float d = amount * detail * gate * focus;
    d = d / (1.0f + abs(d) / max(maxDelta, 1e-4f));
    float Yt = noor::dec(noor::addPositive(p, d));
    return premultiply(float4(noor::retargetLuma(c.rgb, Y, Yt), c.a));
}

// =============================================================================================
// 9. CHROMA NOISE REDUCTION (non-RAW)  (CIColorKernel): keep L from the image, take a/b from
//    a blurred copy. amount 0...1. (For RAW use CIRAWFilter.colorNoiseReductionAmount.)
//    Edge-aware: near a lightness edge (the blurred L differs from the pixel's L) the blurred
//    chroma would bleed colour across the edge, so the replacement fades out there.
// =============================================================================================
float4 noorChromaDenoise(sample_t s, sample_t blurred, float amount)
{
    float4 c = unpremultiply(s);
    float3 lab = noor::toOklab(c.rgb);
    float3 labB = noor::toOklab(unpremultiply(blurred).rgb);
    float edge = smoothstep(0.04f, 0.15f, abs(labB.x - lab.x));
    float k = clamp(amount, 0.0f, 1.0f) * (1.0f - edge);
    float3 outLab = float3(lab.x, lab.y + (labB.y - lab.y) * k, lab.z + (labB.z - lab.z) * k);
    return premultiply(float4(noor::fromOklab(outLab), c.a));
}

// =============================================================================================
// 10. OUTPUT FIT  (CIColorKernel) - the ONLY bounding step, last node before render/encode.
//    1) negative (out-of-gamut) channels: desaturate toward luminance just enough (hue kept);
//    2) highlight shoulder mapping [knee, inMax] -> [knee, outMax] (C1, monotone).
//       inMax <= outMax => identity (no shoulder);
//    3) ceiling: a pixel whose largest channel is still above outMax keeps its hue (all channels
//       scaled by one factor) and rolls toward white as it gets brighter (like film / a sensor),
//       instead of the per-channel clip of the encoder, which shifts hue (bright sky -> cyan).
//       Pixels at or below outMax are untouched.
//    SDR targets (RecipeRenderer.fitToSDR): knee = inMax = outMax = 1, so every in-gamut value in
//    [0, 1] passes through unchanged (an unedited SDR photo stays identical).
// =============================================================================================
float4 noorOutputFit(sample_t s, float knee, float inMax, float outMax)
{
    float4 c = unpremultiply(s);
    float3 rgb = c.rgb;
    float Y = noor::luma(rgb);
    float mn = min(rgb.x, min(rgb.y, rgb.z));
    if (mn < 0.0f) {
        if (Y > 0.0f) {
            float k = Y / max(Y - mn, 1e-8f);
            rgb = float3(Y) + (rgb - float3(Y)) * k;
        } else {
            rgb = float3(0.0f);
        }
    }
    float kn = max(knee, 0.01f);
    float mx = max(rgb.x, max(rgb.y, rgb.z));
    if (inMax > outMax && outMax > kn && mx > kn) {
        float x = mx - kn;
        float cc = 1.0f / (outMax - kn) - 1.0f / max(inMax - kn, 1e-6f);
        float y = x / (1.0f + cc * x);
        rgb = rgb * ((kn + y) / mx);
    }
    float top = max(rgb.x, max(rgb.y, rgb.z));
    if (outMax > 0.0f && top > outMax) {
        float r = outMax / top;                                    // in (0, 1)
        float3 scaled = rgb * r;                                   // hue kept, max channel = outMax
        float w = 1.0f - sqrt(r);                                  // 0 at the ceiling -> 1 when very bright
        rgb = scaled + (float3(outMax) - scaled) * w;              // every channel stays in [0, outMax]
    }
    return premultiply(float4(rgb, c.a));
}

// =============================================================================================
// 10b. OUTPUT CEILING  (CIColorKernel) - SDR bound for targets WIDER than the P3 working space
//    (Adobe RGB / ProPhoto exports: RecipeRenderer.fitToSDR(_:preservingWideGamut: true)).
//    Step 3 of noorOutputFit only (hue-preserving roll toward white above outMax), WITHOUT its
//    gamut fix: a channel that is negative in linear P3 is a colour outside P3 but inside the
//    wider target gamut, so it is kept for the encoder's colour conversion. Only a pixel whose
//    luminance is not positive (not a real colour in any RGB gamut) becomes black, as in
//    noorOutputFit. Pixels whose largest channel is at or below outMax are untouched.
// =============================================================================================
float4 noorOutputCeiling(sample_t s, float outMax)
{
    float4 c = unpremultiply(s);
    float3 rgb = c.rgb;
    float mn = min(rgb.x, min(rgb.y, rgb.z));
    if (mn < 0.0f && noor::luma(rgb) <= 0.0f) {
        rgb = float3(0.0f);
    }
    float top = max(rgb.x, max(rgb.y, rgb.z));
    if (outMax > 0.0f && top > outMax) {
        float r = outMax / top;                                    // in (0, 1)
        float3 scaled = rgb * r;                                   // hue kept, max channel = outMax
        float w = 1.0f - sqrt(r);                                  // 0 at the ceiling -> 1 when very bright
        rgb = scaled + (float3(outMax) - scaled) * w;              // every channel stays <= outMax
    }
    return premultiply(float4(rgb, c.a));
}

// =============================================================================================
// 11. BLACK & WHITE MIX  (CIColorKernel) - replaces noorHSL when the recipe is monochrome.
//    Neutral grey from perceptual lightness (OKLab L; L^3 == Y exactly for neutral pixels), then
//    the Lightroom-style B&W mix: each colour band brightens/darkens its pixels by up to +-1.5 EV,
//    weighted by chroma (greys are unaffected) and by the SAME smooth band partition as noorHSL.
//    mixLo/mixHi: per-band mix, Lightroom B&W slider / 100 (-1...1), order R O Y G | A B P M.
//    At mix 0 neutral pixels come back unchanged; colour pixels become their perceptual grey.
// =============================================================================================
float4 noorMonochrome(sample_t s, float4 mixLo, float4 mixHi)
{
    float4 c = unpremultiply(s);
    float3 lab = noor::toOklab(c.rgb);
    float C = length(float2(lab.y, lab.z));
    float gain = 1.0f;
    if (C > 1e-6f) {
        float hue = atan2(lab.z, lab.y) * 57.29577951f;
        if (hue < 0.0f) hue += 360.0f;
        noor::BandPos bp = noor::bandPos(hue);
        float m = clamp(noor::bandValue(bp, mixLo, mixHi), -1.0f, 1.0f);
        float w = smoothstep(0.0f, 0.16f, C);                       // chroma weight, 0 for greys
        gain = exp2(1.5f * m * w);
    }
    float L = lab.x;
    float Y = L * L * L * gain;                                     // linear grey (sign kept)
    return premultiply(float4(float3(Y), c.a));
}

// =============================================================================================
// 12. COLOUR MATRIX  (CIColorKernel) - calibration primaries. out = M * rgb, rows r0/r1/r2.
//    M is linear without offset, so it applies to premultiplied values directly (alpha kept).
//    Built in Swift so that white (1,1,1) maps to itself; nothing is clamped.
// =============================================================================================
float4 noorColorMatrix(sample_t s, float3 r0, float3 r1, float3 r2)
{
    float3 c = s.rgb;
    return float4(dot(r0, c), dot(r1, c), dot(r2, c), s.a);
}

// =============================================================================================
// 13. LUMINANCE NOISE REDUCTION (non-RAW)  (CIColorKernel) - sigma filter on perceptual luma.
//    blurred: Gaussian copy (radius in full-res px * renderScale, from Swift).
//    Where the pixel differs from its neighbourhood by less than ~threshold (noise) it moves
//    toward the blurred value; larger differences (edges, real detail) are kept. Colour ratios
//    are kept (luminance-only change). amount 0...1, threshold in enc() units.
// =============================================================================================
float4 noorLumaDenoise(sample_t s, sample_t blurred, float amount, float threshold)
{
    float4 c = unpremultiply(s);
    float Y = max(noor::luma(c.rgb), 0.0f);
    float p = noor::enc(Y);
    float pb = noor::enc(max(noor::luma(unpremultiply(blurred).rgb), 0.0f));
    float d = pb - p;
    float th = max(threshold, 1e-4f);
    float keep = smoothstep(th, 3.0f * th, abs(d));                // 1 = edge / detail
    float k = clamp(amount, 0.0f, 1.0f) * (1.0f - keep);
    float Yt = noor::dec(noor::addPositive(p, d * k));
    return premultiply(float4(noor::retargetLuma(c.rgb, Y, Yt), c.a));
}

// =============================================================================================
// 14. RESAMPLE  (CIKernel - sampler) - straighten rotation (+ crop offset) in ONE resampling.
//    Output pixel q (working space) reads the source at p = A q + t, with A = (m.x m.z; m.y m.w)
//    (CGAffineTransform a, b, c, d) and t = (tx, ty). Catmull-Rom bicubic (16 texel-centre taps,
//    sharper than the bilinear sampler), then clamped to the min/max of the 4 nearest texels so
//    edges never ring (no halos, no new negative values, HDR range kept).
//    src should be clampedToExtent() so rotated edges repeat picture pixels instead of black.
//    ROI (Swift): output rect mapped through (A, t), outset by 3 px.
// =============================================================================================
float4 noorResample(sampler src, float4 m, float2 t, destination dest)
{
    float2 q = dest.coord();
    float2 p = float2(m.x * q.x + m.z * q.y + t.x, m.y * q.x + m.w * q.y + t.y);
    float2 pc = p - float2(0.5f);                                   // texel-centre lattice
    float2 b = floor(pc);
    float2 f = pc - b;

    // Catmull-Rom weights (sum to 1 exactly; w = (0, 1, 0, 0) when f == 0 -> exact copy)
    float wx[4];
    float wy[4];
    wx[0] = ((-0.5f * f.x + 1.0f) * f.x - 0.5f) * f.x;
    wx[1] = (1.5f * f.x - 2.5f) * f.x * f.x + 1.0f;
    wx[2] = ((-1.5f * f.x + 2.0f) * f.x + 0.5f) * f.x;
    wx[3] = (0.5f * f.x - 0.5f) * f.x * f.x;
    wy[0] = ((-0.5f * f.y + 1.0f) * f.y - 0.5f) * f.y;
    wy[1] = (1.5f * f.y - 2.5f) * f.y * f.y + 1.0f;
    wy[2] = ((-1.5f * f.y + 2.0f) * f.y + 0.5f) * f.y;
    wy[3] = (0.5f * f.y - 0.5f) * f.y * f.y;

    float4 near0 = src.sample(src.transform(b + float2(0.5f, 0.5f)));
    float4 lo = near0;
    float4 hi = near0;
    float4 acc = float4(0.0f);
    for (int j = 0; j < 4; ++j) {
        float y = b.y + float(j) - 0.5f;
        for (int i = 0; i < 4; ++i) {
            float x = b.x + float(i) - 0.5f;
            float4 v = src.sample(src.transform(float2(x, y)));
            acc += v * (wx[i] * wy[j]);
            if (i >= 1 && i <= 2 && j >= 1 && j <= 2) {
                lo = min(lo, v);
                hi = max(hi, v);
            }
        }
    }
    return clamp(acc, lo, hi);
}

} // namespace coreimage
} // extern "C"
