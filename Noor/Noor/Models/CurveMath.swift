import Foundation

/// Tone-curve maths. This is the ONLY curve evaluator in the app: the curve editor draws with it,
/// presets blend with it and the engine bakes its LUT with it, so what you see is what you export.
///
/// Monotone cubic Hermite interpolation (Fritsch–Carlson): smooth, never overshoots, never
/// reverses tones between control points. Flat outside the end points (black / white point).
enum CurveMath {
    /// Most points a curve may hold (imported Lightroom curves can carry up to ~20).
    static let maxPoints = 32
    /// Closest two control points may be in x.
    static let minSpacing = 1.0 / 1024

    static func isLinear(_ pts: [CurvePoint]) -> Bool {
        pts.allSatisfy { abs($0.x - $0.y) < 1e-6 }
    }

    /// Sorted, clamped to 0...1, finite, de-duplicated, 2...maxPoints points (else linear).
    static func sanitize(_ pts: [CurvePoint]) -> [CurvePoint] {
        var out: [CurvePoint] = []
        let sorted = pts.filter { $0.x.isFinite && $0.y.isFinite }.sorted { $0.x < $1.x }
        for p in sorted {
            let q = CurvePoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
            if let last = out.last, q.x - last.x < minSpacing {
                out[out.count - 1] = q
            } else {
                out.append(q)
            }
        }
        guard out.count >= 2 else { return ToneCurves.linear }
        if out.count > maxPoints {
            // Keep the end points and an even subset in between.
            let step = Double(out.count - 1) / Double(maxPoints - 1)
            out = (0..<maxPoints).map { out[Int((Double($0) * step).rounded())] }
        }
        return out
    }

    /// Tangents for the monotone cubic Hermite spline through `p` (sorted, >= 2 points).
    static func tangents(_ p: [CurvePoint]) -> [Double] {
        let n = p.count
        guard n >= 2 else { return [] }
        var d = [Double](repeating: 0, count: n - 1)   // secant slopes
        for i in 0..<(n - 1) {
            let h = p[i + 1].x - p[i].x
            d[i] = h > 0 ? (p[i + 1].y - p[i].y) / h : 0
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                m[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2
            }
        }
        // Fritsch–Carlson limiter: guarantees monotonicity on every segment.
        for i in 0..<(n - 1) {
            if d[i] == 0 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let a = m[i] / d[i]
            let b = m[i + 1] / d[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                m[i] = t * a * d[i]
                m[i + 1] = t * b * d[i]
            }
        }
        return m
    }

    /// Value of the curve at `x` (0...1). Flat outside the first/last control point.
    static func evaluate(_ pts: [CurvePoint], at x: Double) -> Double {
        let p = pts
        let n = p.count
        guard n >= 2 else { return x }
        if x <= p[0].x { return p[0].y }
        if x >= p[n - 1].x { return p[n - 1].y }
        let m = tangents(p)
        return evaluate(p, tangents: m, at: x)
    }

    /// Fast path when tangents are precomputed (LUT baking, drawing).
    static func evaluate(_ p: [CurvePoint], tangents m: [Double], at x: Double) -> Double {
        let n = p.count
        guard n >= 2, m.count == n else { return x }
        if x <= p[0].x { return p[0].y }
        if x >= p[n - 1].x { return p[n - 1].y }
        var lo = 0
        var hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if p[mid].x <= x { lo = mid } else { hi = mid }
        }
        let h = p[hi].x - p[lo].x
        guard h > 0 else { return p[lo].y }
        let t = (x - p[lo].x) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let y = h00 * p[lo].y + h10 * h * m[lo] + h01 * p[hi].y + h11 * h * m[hi]
        return min(max(y, 0), 1)
    }

    /// `count` evenly spaced samples of the curve over 0...1 (for the engine's LUT and for drawing).
    static func samples(_ pts: [CurvePoint], count: Int) -> [Float] {
        let p = sanitize(pts)
        let m = tangents(p)
        let n = max(count, 2)
        return (0..<n).map { i in
            Float(evaluate(p, tangents: m, at: Double(i) / Double(n - 1)))
        }
    }
}
