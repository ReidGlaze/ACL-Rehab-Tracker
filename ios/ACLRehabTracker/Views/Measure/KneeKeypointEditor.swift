import SwiftUI

/// Shows the photo with hip, knee and ankle drawn on it. Each dot can be dragged, and the angle
/// updates as it moves. The number always matches the picture because both come from the same
/// three points.
///
/// The photo can be pinched to zoom and dragged to pan, so a dot can be placed precisely. Zooming
/// only changes where things are drawn: the dots are stored as fractions of the image, never as
/// screen positions, so the angle is the same at any zoom. The dots keep their size on screen.
struct KneeKeypointEditor: View {
    let image: UIImage
    @Binding var keypoints: KneeKeypoints
    var onEdit: () -> Void = {}

    @State private var activeJoint: Joint?
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// Zoom and offset when the current pinch began.
    @State private var pinchStart: (zoom: CGFloat, offset: CGSize)?
    /// Offset and finger travel when the current pan began (re-based after a pinch).
    @State private var panStart: (offset: CGSize, translation: CGSize)?
    /// True while two fingers are pinching. It clears itself however the pinch ends, including when
    /// the system cancels it, so a pan can never be left blocked.
    @GestureState private var isPinching = false

    static let maxZoom: CGFloat = 5
    static let doubleTapZoom: CGFloat = 2.5

    enum Joint: String, CaseIterable { case hip, knee, ankle }

    private var isZoomed: Bool { zoom > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            let base = fittedRect(imageSize: image.size, in: proxy.size)
            let frame = zoomedRect(base)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .accessibilityHidden(true)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .mask(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .frame(width: base.width, height: base.height)
                            .position(x: base.midX, y: base.midY)
                    )
                    .contentShape(Rectangle())
                    // One combined gesture. As separate ones the double tap swallowed the pan, and once
                    // the pan was active it kept the pinch on the container below from being seen.
                    .gesture(
                        doubleTapGesture(in: base)
                            .simultaneously(with: isZoomed ? panGesture(in: base) : nil)
                            .simultaneously(with: magnifyGesture(in: base))
                    )

                // What VoiceOver and the UI tests see as "the photo": exactly the area on screen, at
                // any zoom. (The zoomed image itself is larger than the area it shows through.)
                Color.clear
                    .frame(width: base.width, height: base.height)
                    .position(x: base.midX, y: base.midY)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("Photo with hip, knee and ankle marked")
                    .accessibilityValue(isZoomed ? String(format: "Zoomed in %.1f times", Double(zoom)) : "Not zoomed")
                    .accessibilityHint("Pinch to zoom, drag to move around, double tap to zoom in or out")
                    .accessibilityIdentifier("keypoint.photo")

                overlay(in: frame, visible: base)
                    .mask(
                        Rectangle()
                            .frame(width: base.width + 24, height: base.height + 24)
                            .position(x: base.midX, y: base.midY)
                    )

                if isZoomed {
                    Button(action: { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }) {
                        Label("Reset zoom", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(CameraPillStyle(isOn: false))
                    .position(x: base.maxX - 70, y: base.minY + 26)
                    .accessibilityIdentifier("keypoint.resetZoom")
                    .accessibilityValue(String(format: "%.1fx", Double(zoom)))
                }
            }
            // Also on the container, so a pinch that starts with a finger on a dot still zooms. Both
            // copies work from the same starting zoom, so running together they agree.
            .simultaneousGesture(magnifyGesture(in: base))
            .onChange(of: proxy.size) { _, _ in resetZoom() }
            .onChange(of: isPinching) { _, pinching in
                guard !pinching else { return }
                pinchStart = nil
                panStart = nil
                if !isZoomed { withAnimation(.easeOut(duration: 0.15)) { resetZoom() } }
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    // MARK: - Zoom and pan

    private func zoomedRect(_ base: CGRect) -> CGRect {
        CGRect(x: base.midX + offset.width - base.width * zoom / 2,
               y: base.midY + offset.height - base.height * zoom / 2,
               width: base.width * zoom, height: base.height * zoom)
    }

    private func resetZoom() {
        zoom = 1
        offset = .zero
        pinchStart = nil
        panStart = nil
    }

    /// Keeps the photo covering its frame: it can't be dragged so far that blank space shows.
    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat, in base: CGRect) -> CGSize {
        let maxX = base.width * (zoom - 1) / 2
        let maxY = base.height * (zoom - 1) / 2
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }

    /// Sets the zoom so that the part of the photo under `anchor` stays under it.
    private func setZoom(_ proposed: CGFloat, keeping anchor: CGPoint, from start: (zoom: CGFloat, offset: CGSize), in base: CGRect) {
        let newZoom = min(max(proposed, 1), Self.maxZoom)
        let relX = (anchor.x - base.midX - start.offset.width) / start.zoom
        let relY = (anchor.y - base.midY - start.offset.height) / start.zoom
        zoom = newZoom
        offset = clampedOffset(CGSize(width: anchor.x - base.midX - relX * newZoom,
                                      height: anchor.y - base.midY - relY * newZoom), zoom: newZoom, in: base)
    }

    private func magnifyGesture(in base: CGRect) -> some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, pinching, _ in pinching = true }
            .onChanged { value in
                let start = pinchStart ?? (zoom, offset)
                if pinchStart == nil { pinchStart = start }
                panStart = nil
                setZoom(start.zoom * value.magnification, keeping: value.startLocation, from: start, in: base)
            }
    }

    private func doubleTapGesture(in base: CGRect) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { tap in
            withAnimation(.easeOut(duration: 0.2)) {
                if isZoomed {
                    resetZoom()
                } else {
                    setZoom(Self.doubleTapZoom, keeping: tap.location, from: (1, .zero), in: base)
                }
            }
        }
    }

    private func panGesture(in base: CGRect) -> some Gesture {
        // No minimum distance, like the dots: otherwise the page's scroll view takes the drag first.
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard !isPinching else { return }
                let start = panStart ?? (offset, drag.translation)
                if panStart == nil { panStart = start }
                offset = clampedOffset(CGSize(
                    width: start.offset.width + drag.translation.width - start.translation.width,
                    height: start.offset.height + drag.translation.height - start.translation.height
                ), zoom: zoom, in: base)
            }
            .onEnded { _ in panStart = nil }
    }

    // MARK: - Lines and dots

    @ViewBuilder
    private func overlay(in frame: CGRect, visible: CGRect) -> some View {
        let hip = viewPoint(keypoints.hip, frame)
        let knee = viewPoint(keypoints.knee, frame)
        let ankle = viewPoint(keypoints.ankle, frame)

        // White underlay so the lines read on any photo.
        Path { p in
            p.move(to: hip)
            p.addLine(to: knee)
            p.addLine(to: ankle)
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        .shadow(color: .black.opacity(0.35), radius: 3)
        .allowsHitTesting(false)
        .mask(Rectangle().frame(width: visible.width, height: visible.height).position(x: visible.midX, y: visible.midY))

        Path { p in
            p.move(to: hip)
            p.addLine(to: knee)
            p.addLine(to: ankle)
        }
        .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
        .mask(Rectangle().frame(width: visible.width, height: visible.height).position(x: visible.midX, y: visible.midY))

        ForEach(Joint.allCases, id: \.self) { joint in
            handle(for: joint, frame: frame, visible: visible)
        }
    }

    private func handle(for joint: Joint, frame: CGRect, visible: CGRect) -> some View {
        let point = viewPoint(value(for: joint), frame)
        let isActive = activeJoint == joint
        // A dot that is zoomed out of view must not catch touches meant for what is around the photo.
        let onScreen = visible.insetBy(dx: -12, dy: -12).contains(point)
        return ZStack {
            Circle().fill(.white).frame(width: isActive ? 30 : 24, height: isActive ? 30 : 24)
            Circle().fill(AppColors.primary).frame(width: isActive ? 20 : 15, height: isActive ? 20 : 15)
        }
        .shadow(color: .black.opacity(0.3), radius: 3)
        .frame(width: 56, height: 56) // generous touch target
        .contentShape(Circle())
        .position(point)
        .allowsHitTesting(onScreen || isActive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    activeJoint = joint
                    // Stay inside the part of the photo that is showing, then convert the screen
                    // position to a fraction of the (zoomed) image.
                    let x = min(max(drag.location.x, visible.minX), visible.maxX)
                    let y = min(max(drag.location.y, visible.minY), visible.maxY)
                    set(NormalizedPoint(
                        x: Double((x - frame.minX) / frame.width),
                        y: Double((y - frame.minY) / frame.height)
                    ).clamped, for: joint)
                }
                .onEnded { _ in
                    activeJoint = nil
                    onEdit()
                }
        )
        .accessibilityLabel("\(joint.rawValue.capitalized) point")
        .accessibilityHint("Drag to adjust")
        .accessibilityIdentifier("keypoint.\(joint.rawValue)")
    }

    private func value(for joint: Joint) -> NormalizedPoint {
        switch joint {
        case .hip: return keypoints.hip
        case .knee: return keypoints.knee
        case .ankle: return keypoints.ankle
        }
    }

    private func set(_ point: NormalizedPoint, for joint: Joint) {
        switch joint {
        case .hip: keypoints.hip = point
        case .knee: keypoints.knee = point
        case .ankle: keypoints.ankle = point
        }
    }

    private func viewPoint(_ p: NormalizedPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(p.y) * frame.height)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
