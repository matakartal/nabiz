import Foundation

// The motion of a styled recording: where the pointer is drawn, how it reacts to a click, and where the camera
// looks. Everything is a pure function of time, worked out once, so the preview, a seek and the export always
// show the same frame. Positions are 0…1 of the recorded picture, origin top-left.

/// The pointer: a spring-smoothed path that still lands exactly on every click, a press-and-rebound on each
/// click, and an optional fade after standing still.
struct RecCursorPath: Sendable {
    private let raw: [(t: Double, x: Double, y: Double)]
    private let times: [Double]
    private let xs: [Double]
    private let ys: [Double]
    private let clicks: [Double]
    private let clickPoints: [(Double, Double)]
    /// Opacity at 60 steps a second (see `opacity`).
    private let fade: [Double]

    /// `smoothing` 0…1 (0 = the raw path); 0.3 trails the mouse by about 95 ms.
    init(track: RecTrack, size: CGSize, smoothing: Double) {
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        // Samples are only written when the pointer moves; hold the last spot until just before the next move,
        // or the path would drift slowly across every pause.
        var points: [(t: Double, x: Double, y: Double)] = []
        for move in track.moves.sorted(by: { $0.t < $1.t }) {
            if let last = points.last, move.t - last.t > 0.05 {
                points.append((move.t - 1.0 / 60, last.x, last.y))
            }
            points.append((move.t, move.x / w, move.y / h))
        }
        raw = points
        clicks = track.clicks.map(\.t).sorted()
        clickPoints = track.clicks.sorted { $0.t < $1.t }.map { ($0.x / w, $0.y / h) }
        fade = Self.fades(points: points, clicks: clicks, typing: track.typing.sorted())
        guard points.count > 1, smoothing > 0 else {
            times = points.map(\.t); xs = points.map(\.x); ys = points.map(\.y)
            return
        }
        // Resample at 240 Hz and run a spring-damper over it (semi-implicit Euler).
        let step = 1.0 / 240
        let start = points[0].t, end = points[points.count - 1].t
        let n = max(1, Int(((end - start) / step).rounded())) + 1
        var times = [Double](repeating: 0, count: n), rx = times, ry = times
        var j = 0
        for i in 0..<n {
            let t = i == n - 1 ? end : start + Double(i) * step
            while j + 1 < points.count && points[j + 1].t <= t { j += 1 }
            let a = points[j], b = points[min(j + 1, points.count - 1)]
            let u = b.t > a.t ? min(max((t - a.t) / (b.t - a.t), 0), 1) : 0
            times[i] = t
            rx[i] = a.x + (b.x - a.x) * u
            ry[i] = a.y + (b.y - a.y) * u
        }
        let (k, c, m) = Self.spring(smoothing)
        func run(_ target: [Double]) -> [Double] {
            var out = target, x = target[0], v = 0.0
            for i in 1..<target.count {
                let a = (-k * (x - target[i]) - c * v) / m
                v += a * step
                x += v * step
                out[i] = x
            }
            return out
        }
        self.times = times
        xs = run(rx)
        ys = run(ry)
    }

    /// The spring for a smoothing amount: (stiffness, damping, mass). Stiffer and lighter when low, softer when high.
    static func spring(_ smoothing: Double) -> (Double, Double, Double) {
        let s = min(max(smoothing, 0), 2)
        if s <= 0.5 {
            let n = s / 0.5
            return (760 - n * 420, 34 + n * 24, 0.55 + n * 0.45)
        }
        let n = (s - 0.5) / 1.5
        return (340 - n * 180, 58 + n * 22, 1 + n * 0.35)
    }

    private static func lookup(_ times: [Double], _ xs: [Double], _ ys: [Double], _ t: Double) -> (Double, Double)? {
        guard let first = times.first, let last = times.last else { return nil }
        if t <= first { return (xs[0], ys[0]) }
        if t >= last { return (xs[xs.count - 1], ys[ys.count - 1]) }
        var lo = 0, hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        let span = times[hi] - times[lo]
        let u = span > 0 ? (t - times[lo]) / span : 0
        return (xs[lo] + (xs[hi] - xs[lo]) * u, ys[lo] + (ys[hi] - ys[lo]) * u)
    }

    var rawSamples: [(t: Double, x: Double, y: Double)] { raw }

    private static func smoothstep(_ x: Double) -> Double {
        let u = min(max(x, 0), 1)
        return u * u * (3 - 2 * u)
    }

    /// The drawn pointer: the smoothed path, pulled onto the exact clicked pixel around each click (0.25 s in,
    /// held 0.1 s, 0.25 s out), so the tip touches what was clicked even though the spring trails the mouse.
    func at(_ t: Double) -> (Double, Double)? {
        guard var (x, y) = Self.lookup(times, xs, ys, t) else { return nil }
        let approachS = 0.25, holdS = 0.1, releaseS = 0.25
        func hold(_ i: Int) -> Double { i + 1 < clicks.count ? min((clicks[i + 1] - clicks[i]) * 0.5, holdS) : holdS }
        for i in clicks.indices where clicks[i] > t - holdS - releaseS && clicks[i] < t + approachS {
            let d = t - clicks[i]
            let weight: Double
            if d < 0 {
                let approach = i > 0 ? min(max(clicks[i] - clicks[i - 1] - hold(i - 1), 0.001), approachS) : approachS
                weight = Self.smoothstep(1 + d / approach)
            } else {
                weight = 1 - Self.smoothstep((d - hold(i)) / releaseS)
            }
            let (cx, cy) = clickPoints[i]
            x += (cx - x) * weight
            y += (cy - y) * weight
        }
        return (x, y)
    }

    /// The click "bounce": the pointer presses down to 76% then springs to 116% over 0.26 s (the latest click).
    func bounce(_ t: Double, amount: Double = 1) -> Double {
        guard let last = clicks.last(where: { $0 <= t }) else { return 1 }
        let e = (t - last) / 0.26
        guard e < 1 else { return 1 }
        let press = 0.38
        let shape = e < press ? -sin(e / press * .pi) * 0.24 : sin((e - press) / (1 - press) * .pi) * 0.16
        return 1 + shape * amount
    }

    /// 1 while the pointer moves or clicks, fading out over 0.3 s after 1.5 s still.
    func opacity(_ t: Double) -> Double {
        guard !fade.isEmpty else { return 1 }
        let position = max(0, t * 60)
        let i = min(Int(position), fade.count - 1), j = min(i + 1, fade.count - 1)
        return fade[i] + (fade[j] - fade[i]) * (position - Double(i))
    }

    private static func fades(points: [(t: Double, x: Double, y: Double)], clicks: [Double], typing: [Double]) -> [Double] {
        guard let end = points.last?.t else { return [] }
        let steps = Int(end * 60) + 120
        var result = [Double](repeating: 1, count: steps)
        var j = 0, c = 0, k = 0
        var lastMove = points.first?.t ?? 0
        var typingFrom: Double?
        var previous = points.first
        for i in 0..<steps {
            let t = Double(i) / 60
            while j < points.count && points[j].t <= t {
                if let p = previous, pow(points[j].x - p.x, 2) + pow(points[j].y - p.y, 2) > 0.0005 * 0.0005 { lastMove = points[j].t }
                previous = points[j]
                j += 1
            }
            while c < clicks.count && clicks[c] <= t { lastMove = max(lastMove, clicks[c]); c += 1 }
            while k < typing.count && typing[k] <= t {
                if typing[k] > lastMove + 0.2, (typingFrom ?? -1) < lastMove { typingFrom = typing[k] }
                k += 1
            }
            let idle = max(0, t - lastMove)
            var alpha = idle <= 1.5 ? 1 : max(0, 1 - (idle - 1.5) / 0.3)
            // Typing with the mouse still: the pointer steps aside at once (0.15 s) until the mouse moves again.
            if let from = typingFrom, from > lastMove + 0.2 {
                alpha = min(alpha, max(0, 1 - (t - from) / 0.15))
            }
            result[i] = alpha
        }
        return result
    }

    var clickTimes: [Double] { clicks }
    var clickSpots: [(Double, Double)] { clickPoints }
}

/// The camera: zoom regions eased in and out like a critically damped spring, the scale moving in log space,
/// close zooms chained with a pan instead of out-and-back, and auto regions following the pointer with a dead
/// zone (the view only moves when the pointer leaves its middle half).
struct RecLens: Sendable {
    struct Region: Sendable {
        var start: Double
        var end: Double
        var scale: Double
        /// Fixed focus (0…1); nil follows the pointer.
        var focus: (Double, Double)?
    }

    private let regions: [Region]
    /// Per auto region: the replayed view centre (t, x, y).
    private let views: [[(Double, Double, Double)]]
    private let follow: [(Double, Double, Double)]

    static let chainGap = 1.5
    static let chainPan = 1.0

    /// Seconds a zoom takes to arrive at `scale`: ~0.7 s at 1.25×, ~0.9 s at 1.8×, ~1.5 s at 5×.
    static func transition(_ scale: Double) -> Double { 0.6 + 0.55 * log(max(1, scale)) }

    /// `typing`: where the text cursor was while typing (0…1), which the camera follows like the pointer.
    init(regions: [Region], cursor: RecCursorPath, typing: [(t: Double, x: Double, y: Double)] = []) {
        // What the viewer should look at: the pointer while it moves, the text cursor while typing.
        // Each spot is held until just before the next, like the pointer's own samples.
        var attention: [(t: Double, x: Double, y: Double)] = []
        for sample in (cursor.rawSamples + typing).sorted(by: { $0.t < $1.t }) {
            if let last = attention.last, sample.t - last.t > 0.05 { attention.append((sample.t - 1.0 / 60, last.x, last.y)) }
            attention.append(sample)
        }
        let regions = regions.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        self.regions = regions
        // The camera's own, softer track of the pointer (distance-adaptive smoothing).
        var follow: [(Double, Double, Double)] = []
        for sample in attention {
            guard let previous = follow.last else { follow.append((sample.t, sample.x, sample.y)); continue }
            let dt = (sample.t - previous.0) * 1000
            guard dt > 0 else { follow.append((sample.t, previous.1, previous.2)); continue }
            let next = Self.followStep((previous.1, previous.2), (sample.x, sample.y), dt)
            follow.append((sample.t, next.0, next.1))
        }
        self.follow = follow
        views = regions.map { region in
            guard region.focus == nil else { return [] }
            let window = Self.transition(region.scale)
            return Self.replay(samples: attention, follow: follow, from: region.start - window, to: region.end + window, scale: region.scale)
        }
    }

    /// One step of the camera's follow: faster when far (factor 0.1…0.25, ramping over 0.15 of the frame),
    /// corrected for time so it doesn't depend on the frame rate.
    private static func followStep(_ from: (Double, Double), _ to: (Double, Double), _ dtMs: Double) -> (Double, Double) {
        let dx = to.0 - from.0, dy = to.1 - from.1
        let ramp = min(hypot(dx, dy) / 0.15, 1)
        let base = 0.1 + (0.25 - 0.1) * ramp
        let factor = 1 - pow(1 - base, dtMs / 25)
        return (from.0 + dx * factor, from.1 + dy * factor)
    }

    private static func interpolate(_ samples: [(Double, Double, Double)], _ t: Double) -> (Double, Double)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.0 { return (first.1, first.2) }
        if t >= last.0 { return (last.1, last.2) }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].0 <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let u = b.0 > a.0 ? (t - a.0) / (b.0 - a.0) : 0
        return (a.1 + (b.1 - a.1) * u, a.2 + (b.2 - a.2) * u)
    }

    /// The view centre of an auto zoom, replayed from `t0` at 60 steps a second: it stays put while what the viewer
    /// looks at moves inside the middle half of the view, and catches up just enough when it leaves. Two soft
    /// followers in a row, so the camera never starts or stops with a jolt, even when the text cursor jumps.
    private static func replay(samples: [(t: Double, x: Double, y: Double)], follow: [(Double, Double, Double)], from t0: Double, to tEnd: Double,
                               scale: Double) -> [(Double, Double, Double)] {
        let half = 0.5 / max(scale, 1), dead = half * 0.5
        let reach = { (v: Double) in min(max(v, half), 1 - half) }
        let pull = { (pointer: Double, view: Double) in pointer - min(max(pointer - view, -dead), dead) }
        guard let start = interpolate(follow, t0) else { return [] }
        var lead = (reach(start.0), reach(start.1))
        var view = lead
        var states = [(t0, view.0, view.1)]
        var index = samples.firstIndex { $0.t > t0 } ?? samples.count
        var target = samples.last(where: { $0.t <= t0 }).map { ($0.x, $0.y) } ?? start
        let step = 1.0 / 60
        var t = t0
        while t < tEnd {
            let dt = min(step, tEnd - t)
            t += dt
            while index < samples.count && samples[index].t <= t { target = (samples[index].x, samples[index].y); index += 1 }
            let next = followStep(lead, (pull(target.0, view.0), pull(target.1, view.1)), dt * 1000)
            lead = (reach(next.0), reach(next.1))
            let settled = followStep(view, lead, dt * 1000)
            view = (reach(settled.0), reach(settled.1))
            states.append((t, view.0, view.1))
        }
        return states
    }

    /// A critically damped spring's rise, landing exactly on 1: no jolt at the start, a soft arrival.
    static func easeSpring(_ t: Double) -> Double {
        let omega = 7.0
        let x = omega * min(max(t, 0), 1)
        let end = 1 - (1 + omega) * exp(-omega)
        return (1 - (1 + x) * exp(-x)) / end
    }

    /// cubic-bezier(x1, y1, x2, y2) at `t` (Newton, then bisection).
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        func sample(_ a: Double, _ b: Double, _ s: Double) -> Double { let o = 1 - s; return 3 * a * o * o * s + 3 * b * o * s * s + s * s * s }
        func slope(_ a: Double, _ b: Double, _ s: Double) -> Double { let o = 1 - s; return 3 * a * o * o + 6 * (b - a) * o * s + 3 * (1 - b) * s * s }
        let target = min(max(t, 0), 1)
        var s = target
        for _ in 0..<8 {
            let dx = sample(x1, x2, s) - target, d = slope(x1, x2, s)
            if abs(dx) < 1e-6 || abs(d) < 1e-6 { break }
            s -= dx / d
        }
        var lo = 0.0, hi = 1.0
        s = min(max(s, 0), 1)
        for _ in 0..<10 {
            let x = sample(x1, x2, s)
            if abs(x - target) < 1e-6 { break }
            if x < target { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return sample(y1, y2, s)
    }

    /// Scale between a and b in log space: 1×→2× reads like 2×→4×.
    private static func scaleLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a * pow(b / a, t) }

    private func focus(of index: Int, at t: Double) -> (Double, Double) {
        let region = regions[index]
        if let fixed = region.focus { return fixed }
        return Self.interpolate(views[index], t) ?? (0.5, 0.5)
    }

    private func strength(_ region: Region, _ t: Double) -> Double {
        let window = Self.transition(region.scale)
        if t < region.start - window || t > region.end + window { return 0 }
        if t < region.start { return Self.easeSpring((t - (region.start - window)) / window) }
        if t <= region.end { return 1 }
        return 1 - Self.easeSpring((t - region.end) / window)
    }

    /// Scale and the centre the zoomed view looks at (0…1), at time `t`.
    func state(at t: Double) -> (scale: Double, focus: (Double, Double)) {
        guard !regions.isEmpty else { return (1, (0.5, 0.5)) }
        // Close neighbours are chained: a pan from one to the next, then the next held.
        var pairs: [(Int, Int, Double, Double)] = []
        for i in 0..<(regions.count - 1) where regions[i + 1].start - regions[i].end <= Self.chainGap {
            pairs.append((i, i + 1, regions[i].end, regions[i].end + Self.chainPan))
        }
        for (current, next, start, end) in pairs where t >= start && t <= end {
            let p = Self.bezier(0.1, 0, 0.2, 1, (t - start) / max(end - start, 0.001))
            let a = focus(of: current, at: t), b = focus(of: next, at: t)
            return (Self.scaleLerp(regions[current].scale, regions[next].scale, p), (a.0 + (b.0 - a.0) * p, a.1 + (b.1 - a.1) * p))
        }
        for (_, next, _, end) in pairs where t > end && t < regions[next].start {
            return (regions[next].scale, focus(of: next, at: t))
        }
        var best: (Int, Double)?
        for (i, region) in regions.enumerated() {
            if pairs.contains(where: { $0.0 == i && t > region.end }) { continue }
            if pairs.contains(where: { $0.1 == i && t < $0.3 }) { continue }
            let s = strength(region, t)
            if s > 0, s >= (best?.1 ?? 0) { best = (i, s) }
        }
        guard let (index, s) = best else { return (1, (0.5, 0.5)) }
        let scale = Self.scaleLerp(1, regions[index].scale, s)
        let f = focus(of: index, at: t)
        // The focus point moves to the middle of the screen linearly with the zoom's strength.
        let ease = { (v: Double) in v - (v - 0.5) * (1 - s) / max(scale, 0.001) }
        return (scale, (ease(f.0), ease(f.1)))
    }
}

/// The automatic zooms, planned in shots the way an editor would. The video opens and ends on the whole
/// screen; clicks close in time (3 s) and in space share one zoom, as deep as still shows them all with a margin;
/// a zoom is in 0.5 s before its first click and holds 1.5 s after its last (at least 1.8 s); two zooms never
/// come back to back without a real wide shot (1.5 s) between them; the stop click is ignored.
enum RecZoomPlanner {
    static let depths = [1.25, 1.5, 1.8]

    /// `carets`: where the text cursor was while typing; a burst of typing gets its shot like a burst of clicks.
    static func plan(clicks: [RecTrack.Point], carets: [RecTrack.Point] = [], size: CGSize, duration: Double) -> [RecZoom] {
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        let usable = (clicks + carets).filter { $0.t < duration - 1 }.sorted { $0.t < $1.t }
        struct Box { var minX, maxX, minY, maxY: Double }
        func union(_ a: Box, _ b: Box) -> Box { Box(minX: min(a.minX, b.minX), maxX: max(a.maxX, b.maxX), minY: min(a.minY, b.minY), maxY: max(a.maxY, b.maxY)) }
        func fit(_ box: Box) -> Double? {
            let size = max(box.maxX - box.minX, box.maxY - box.minY) + 2 * 0.12
            return depths.last { $0 * size <= 1 }
        }
        var groups: [(times: [Double], box: Box)] = []
        for click in usable {
            let point = Box(minX: click.x / w, maxX: click.x / w, minY: click.y / h, maxY: click.y / h)
            if let last = groups.last, let lastTime = last.times.last, click.t - lastTime <= 3 {
                let merged = union(last.box, point)
                if fit(merged) != nil {
                    groups[groups.count - 1].times.append(click.t)
                    groups[groups.count - 1].box = merged
                    continue
                }
            }
            groups.append(([click.t], point))
        }
        struct Shot { var start, end, scale: Double; var box: Box; var clicks: Int }
        var shots: [Shot] = []
        for group in groups {
            let scale = fit(group.box) ?? depths[0]
            let ramp = RecLens.transition(scale)
            let earliest = 2.5 + ramp, latest = duration - 1 - ramp
            guard let first = group.times.first, let last = group.times.last else { continue }
            let start = max(min(first - 0.5, latest - 1.8), earliest)
            let end = min(max(last + 1.5, start + 1.8), latest)
            guard end - start >= 1.8, group.times.contains(where: { $0 >= start && $0 <= end }) else { continue }
            shots.append(Shot(start: start, end: end, scale: scale, box: group.box, clicks: group.times.count))
        }
        // No yo-yo: merge two shots that are too close (if they fit together), else drop the one with fewer clicks.
        var changed = true
        while changed {
            changed = false
            shots.sort { $0.start < $1.start }
            for i in 0..<max(0, shots.count - 1) {
                let a = shots[i], b = shots[i + 1]
                let wide = b.start - (a.end + RecLens.transition(a.scale)) - RecLens.transition(b.scale)
                guard wide < 1.5 else { continue }
                let box = union(a.box, b.box)
                if let scale = fit(box) {
                    shots[i] = Shot(start: a.start, end: max(a.end, b.end), scale: scale, box: box, clicks: a.clicks + b.clicks)
                    shots.remove(at: i + 1)
                } else {
                    shots.remove(at: a.clicks >= b.clicks ? i + 1 : i)
                }
                changed = true
                break
            }
        }
        return shots.map { RecZoom(start: $0.start, end: $0.end, scale: $0.scale) }
    }
}
