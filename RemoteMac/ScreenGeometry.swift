import CoreGraphics

/// Display layout in the same coordinate space CGEvent uses: global, origin at the
/// top-left of the primary display, y growing downward. (`NSScreen.frame` is
/// bottom-left-origin; `CGDisplayBounds` is already top-left, so we never flip.)
enum ScreenGeometry {
    /// Active displays only, so a lid-closed MacBook's built-in panel is excluded.
    static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Keeps `point` on a real display. If it falls in a gap between displays (or
    /// off the edge), it snaps to the nearest point of the closest display, so the
    /// cursor sticks at edges that don't line up, like a physical mouse would.
    static func clamp(_ point: CGPoint, to rects: [CGRect] = displayBounds()) -> CGPoint {
        guard !rects.isEmpty else { return point }
        if rects.contains(where: { $0.contains(point) }) { return point }

        var best = point
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for rect in rects {
            // maxX/maxY are exclusive, so the last addressable point is one less.
            let candidate = CGPoint(
                x: min(max(point.x, rect.minX), rect.maxX - 1),
                y: min(max(point.y, rect.minY), rect.maxY - 1)
            )
            let distance = hypot(point.x - candidate.x, point.y - candidate.y)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
