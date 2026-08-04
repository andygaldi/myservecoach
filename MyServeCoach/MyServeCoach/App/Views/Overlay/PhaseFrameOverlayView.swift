import SwiftUI

/// A phase frame with the pose skeleton drawn over it, and — when a cue is highlighted — the
/// segment that cue measured plus a visual indicator of the rule's ideal.
///
/// The image is drawn by SwiftUI and the overlay by a `Canvas` sharing the same aspect-fit rect,
/// so the two stay registered at any size.
struct PhaseFrameOverlayView: View {
    let image: UIImage
    /// `nil` when the persisted keypoints could not be decoded — the frame still shows, without
    /// a skeleton, rather than disappearing.
    let frame: BackendFrame?
    var detections: [BackendDetection] = []
    /// `nil` draws the skeleton alone: no highlight, no ideal indicator.
    var highlightedCue: Cue?

    private var severityColor: Color {
        Color(severity: highlightedCue?.severity ?? "major")
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if let frame {
                    Canvas { context, size in
                        let rect = PoseSkeletonGeometry.fittedRect(
                            imageSize: image.size,
                            in: CGRect(origin: .zero, size: size)
                        )
                        drawSkeleton(frame, in: context, rect: rect)
                        if let cue = highlightedCue {
                            drawIdeal(cue, frame, in: context, rect: rect)
                            drawHighlight(cue, frame, in: context, rect: rect)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Drawing

    private func drawSkeleton(_ frame: BackendFrame, in context: GraphicsContext, rect: CGRect) {
        var path = Path()
        for (a, b) in PoseSkeletonGeometry.boneSegments(in: frame) {
            path.move(to: PoseSkeletonGeometry.point(a, in: rect))
            path.addLine(to: PoseSkeletonGeometry.point(b, in: rect))
        }
        // Dark casing first so the dimmed skeleton stays legible over a bright court surface.
        context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        context.stroke(path, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        for joint in PoseSkeletonGeometry.jointPoints(in: frame) {
            let center = PoseSkeletonGeometry.point(joint, in: rect)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                with: .color(.white.opacity(0.7))
            )
        }
    }

    private func drawHighlight(_ cue: Cue, _ frame: BackendFrame, in context: GraphicsContext, rect: CGRect) {
        let points = CueOverlayGeometry.highlightedPolyline(for: cue, in: frame)
            .map { PoseSkeletonGeometry.point($0, in: rect) }
        guard let first = points.first else { return }

        if points.count > 1 {
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(severityColor), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        for point in points {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)),
                with: .color(severityColor)
            )
        }
    }

    private func drawIdeal(_ cue: Cue, _ frame: BackendFrame, in context: GraphicsContext, rect: CGRect) {
        guard let indicator = CueOverlayGeometry.indicator(for: cue, in: frame, detections: detections) else {
            return
        }
        let dashed = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
        let idealColor = Color.green

        switch indicator {
        case let .rays(origin, endpoints, arc):
            let start = PoseSkeletonGeometry.point(origin, in: rect)
            var rays = Path()
            for endpoint in endpoints {
                rays.move(to: start)
                rays.addLine(to: PoseSkeletonGeometry.point(endpoint, in: rect))
            }
            context.stroke(rays, with: .color(idealColor.opacity(0.9)), style: dashed)

            if arc.count > 1 {
                var arcPath = Path()
                arcPath.move(to: PoseSkeletonGeometry.point(arc[0], in: rect))
                for point in arc.dropFirst() {
                    arcPath.addLine(to: PoseSkeletonGeometry.point(point, in: rect))
                }
                context.stroke(arcPath, with: .color(severityColor.opacity(0.8)), style: StrokeStyle(lineWidth: 2))
            }

        case let .horizontalBand(minY, maxY):
            // Normalized y is up, so the *upper* bound maps to the smaller screen y.
            let top = PoseSkeletonGeometry.point(CGPoint(x: 0, y: maxY ?? 1), in: rect).y
            let bottom = PoseSkeletonGeometry.point(CGPoint(x: 0, y: minY ?? 0), in: rect).y
            fillBand(CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top),
                     in: context, color: idealColor)

        case let .verticalBand(minX, maxX):
            let left = PoseSkeletonGeometry.point(CGPoint(x: minX ?? 0, y: 0), in: rect).x
            let right = PoseSkeletonGeometry.point(CGPoint(x: maxX ?? 1, y: 0), in: rect).x
            fillBand(CGRect(x: left, y: rect.minY, width: right - left, height: rect.height),
                     in: context, color: idealColor)

        case let .box(box, ball):
            let topLeft = PoseSkeletonGeometry.point(CGPoint(x: box.minX, y: box.maxY), in: rect)
            let bottomRight = PoseSkeletonGeometry.point(CGPoint(x: box.maxX, y: box.minY), in: rect)
            let screenBox = CGRect(
                x: topLeft.x, y: topLeft.y,
                width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y
            ).standardized
            let path = Path(roundedRect: screenBox, cornerRadius: 4)
            context.fill(path, with: .color(idealColor.opacity(0.15)))
            context.stroke(path, with: .color(idealColor.opacity(0.9)), style: dashed)

            if let ball {
                let center = PoseSkeletonGeometry.point(ball, in: rect)
                let marker = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
                context.stroke(marker, with: .color(severityColor), lineWidth: 2.5)
            }
        }
    }

    private func fillBand(_ band: CGRect, in context: GraphicsContext, color: Color) {
        let path = Path(band.standardized)
        context.fill(path, with: .color(color.opacity(0.15)))
        context.stroke(path, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }
}
