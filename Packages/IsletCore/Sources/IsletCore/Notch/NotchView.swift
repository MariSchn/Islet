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

    private var pillRowSize: CGSize {
        guard let pill = controller.pill else { return controller.geometry.notchSize }
        return controller.geometry.pillShapeSize(for: pill, contentSize: controller.contentSize)
    }

    private var hitShape: CollapsedHitShape {
        let restricted = !controller.isExpanded && controller.announcement != nil
        return CollapsedHitShape(shape: shape, topRegion: restricted ? pillRowSize : nil, xOffset: pillOffset - shapeOffset)
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
                } else if controller.pill != nil || controller.announcement != nil {
                    VStack(spacing: 0) {
                        if let pill = controller.pill {
                            PillView(pill: pill, geometry: controller.geometry, contentSize: controller.contentSize)
                                .frame(width: pillRowSize.width)
                                .offset(x: pillOffset - shapeOffset)
                                .frame(width: shapeSize.width, height: pillRowSize.height)
                        } else {
                            Color.clear.frame(height: pillRowSize.height)
                        }
                        if let announcement = controller.announcement {
                            AnnouncementView(announcement: announcement)
                                .frame(width: shapeSize.width, height: NotchGeometry.announcementHeight, alignment: .top)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
                    .transition(.opacity)
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipShape(shape)
            .contentShape(hitShape)
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
            .contentShape(hitShape)
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

private struct CollapsedHitShape: Shape {
    let shape: NotchShape
    let topRegion: CGSize?
    let xOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let topRegion else { return shape.path(in: rect) }
        return Path(CGRect(x: rect.midX - topRegion.width / 2 + xOffset, y: rect.minY, width: topRegion.width, height: topRegion.height))
    }
}

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.text)
    }

    private var artworkSide: CGFloat {
        max(geometry.notchSize.height - 12, 16)
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

    private static let lineWidth: CGFloat = 2.5
    private static let visibleGap: CGFloat = 2

    private func arcs(circumference: CGFloat) -> [(start: Double, end: Double, tint: Color.Resolved)] {
        let segments = ring.segments.filter { $0.value > 0 }
        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0, circumference > 0 else { return [] }
        let gap = segments.count > 1 ? Double((Self.visibleGap + Self.lineWidth) / circumference) : 0
        var start = 0.0
        return segments.map { segment in
            let length = segment.value / total
            defer { start += length }
            let arcStart = start + gap / 2
            return (arcStart, max(start + length - gap / 2, arcStart), segment.tint)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let arcs = arcs(circumference: .pi * diameter)
            ZStack {
                if arcs.isEmpty {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: Self.lineWidth)
                }
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(Color(arc.tint), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(width: proxy.size.width, height: proxy.size.height)
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
