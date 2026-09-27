import SwiftUI

public struct NotchView<Content: View>: View {
    private let controller: NotchController
    private let content: () -> Content
    @State private var isShapeHidden = false

    public init(controller: NotchController, @ViewBuilder content: @escaping () -> Content) {
        self.controller = controller
        self.content = content
    }

    private var shapeSize: CGSize {
        if controller.isExpanded {
            return controller.expandedShapeSize
        }
        if let announcement = controller.announcement {
            return controller.geometry.announcementShapeSize(for: announcement, pill: controller.pill, contentSize: controller.contentSize)
        }
        guard let pill = controller.pill else { return controller.geometry.notchSize }
        return controller.geometry.pillShapeSize(for: pill, contentSize: controller.contentSize)
    }

    private var hoverRegionSize: CGSize {
        controller.isExpanded ? controller.expandedHoverSize : shapeSize
    }

    private var pillOffset: CGFloat {
        guard let pill = controller.pill else { return 0 }
        return controller.geometry.pillShapeOffset(for: pill, contentSize: controller.contentSize)
    }

    private var shapeOffset: CGFloat {
        controller.isExpanded || controller.announcement != nil ? 0 : pillOffset
    }

    private var shape: NotchShape {
        NotchShape(bottomRadius: controller.isExpanded ? 24 : controller.announcement == nil ? 12 : 18)
    }

    private var isIdle: Bool {
        !controller.isExpanded && controller.pill == nil && controller.announcement == nil
    }

    private var fillOpacity: Double {
        isShapeHidden ? hitTestableInvisibleOpacity : 1
    }

    private func updateShapeVisibility() async {
        let shouldHide = isIdle && !controller.settings.drawsIdleNotchShape
        if shouldHide {
            try? await Task.sleep(for: .seconds(controller.animation.collapseDuration))
            guard !Task.isCancelled else { return }
        }
        isShapeHidden = shouldHide
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                    .opacity(fillOpacity)
                    .animation(nil, value: fillOpacity)
                    .task(id: isIdle || controller.settings.drawsIdleNotchShape) {
                        await updateShapeVisibility()
                    }
                if controller.isExpanded {
                    content()
                        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
                        .transition(.opacity)
                } else if let announcement = controller.announcement {
                    VStack(spacing: 0) {
                        if let pill = controller.pill {
                            PillView(pill: pill, geometry: controller.geometry, contentSize: controller.contentSize)
                                .frame(width: controller.geometry.pillShapeSize(for: pill, contentSize: controller.contentSize).width)
                                .offset(x: pillOffset)
                                .frame(width: shapeSize.width, height: controller.geometry.notchSize.height)
                        } else {
                            Color.clear.frame(height: controller.geometry.notchSize.height)
                        }
                        AnnouncementView(announcement: announcement)
                            .frame(width: shapeSize.width, height: NotchGeometry.announcementHeight, alignment: .top)
                    }
                    .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
                    .transition(.opacity)
                } else if let pill = controller.pill {
                    PillView(pill: pill, geometry: controller.geometry, contentSize: controller.contentSize)
                        .frame(width: shapeSize.width, height: shapeSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipShape(shape)
            .contentShape(shape)
            .onHover { isInside in
                if isInside {
                    controller.pointerEnteredShape()
                }
            }
            .frame(width: hoverRegionSize.width, height: hoverRegionSize.height, alignment: .top)
            .background(
                shape.fill(.black)
                    .opacity(controller.hoverHoldSize == nil ? 0 : hitTestableInvisibleOpacity)
            )
            .contentShape(shape)
            .offset(x: shapeOffset)
            .onHover { controller.isHovering = $0 }
            .animation(controller.animation.animation(expanding: controller.isExpanded), value: controller.isExpanded)
            .animation(controller.animation.animation(expanding: controller.pill != nil), value: controller.pill)
            .animation(controller.animation.animation(expanding: controller.announcement != nil), value: controller.announcement)
            .animation(controller.animation.animation(expanding: true), value: controller.expandedShapeSize)
            Spacer(minLength: 0)
        }
        .frame(width: controller.geometry.panelSize.width, height: controller.geometry.panelSize.height, alignment: .top)
    }
}

private let hitTestableInvisibleOpacity = 0.02

private struct PillView: View {
    let pill: PillStatus
    let geometry: NotchGeometry
    let contentSize: CGSize?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let symbol = pill.systemImage {
                    Image(systemName: symbol)
                } else {
                    Circle().frame(width: 8, height: 8)
                }
            }
            .frame(width: NotchGeometry.pillLeadingWidth)
            Color.clear.frame(width: geometry.notchSize.width)
            if let ring = pill.ring {
                PillRingView(ring: ring)
                    .frame(width: NotchGeometry.pillRingDiameter, height: NotchGeometry.pillRingDiameter)
                    .frame(width: geometry.pillTrailingWidth(for: pill, contentSize: contentSize))
            } else if let artwork = pill.artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(width: geometry.pillTrailingWidth(for: pill, contentSize: contentSize))
            } else {
                Text(pill.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, NotchGeometry.pillTextPadding)
                    .frame(width: geometry.pillTrailingWidth(for: pill, contentSize: contentSize), alignment: .leading)
            }
        }
        .font(Font(NotchGeometry.pillFont))
        .foregroundStyle(color)
    }

    private var artworkSide: CGFloat {
        geometry.notchSize.height - 8
    }

    private var color: Color {
        if pill.priority >= .attention {
            return .orange
        }
        if let tint = pill.tint {
            return Color(tint)
        }
        return .white
    }
}

private struct PillRingView: View {
    let ring: PillStatus.Ring

    private static let lineWidth: CGFloat = 3
    private static let gap = 0.04

    private var arcs: [(start: Double, end: Double, tint: Color.Resolved)] {
        let segments = ring.segments.filter { $0.value > 0 }
        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        let gap = segments.count > 1 ? Self.gap : 0
        var start = 0.0
        return segments.map { segment in
            let length = segment.value / total
            defer { start += length }
            return (start + gap / 2, start + length - gap / 2, segment.tint)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: Self.lineWidth)
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(Color(arc.tint), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(Self.lineWidth / 2)
    }
}

private struct AnnouncementView: View {
    let announcement: PillAnnouncement

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = announcement.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            Text(announcement.text)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(Font(NotchGeometry.announcementFont))
        .padding(.horizontal, NotchGeometry.announcementPadding)
    }

    private var tint: Color {
        announcement.tint.map { Color($0) } ?? .white
    }
}
