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
            return controller.geometry.expandedShapeSize
        }
        guard let pill = controller.pill else { return controller.geometry.notchSize }
        return controller.geometry.pillShapeSize(for: pill)
    }

    private var shapeOffset: CGFloat {
        guard !controller.isExpanded, let pill = controller.pill else { return 0 }
        return controller.geometry.pillShapeOffset(for: pill)
    }

    private var shape: NotchShape {
        NotchShape(bottomRadius: controller.isExpanded ? 24 : 12)
    }

    private var isIdle: Bool {
        !controller.isExpanded && controller.pill == nil
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
                        .padding(.top, controller.geometry.notchSize.height)
                        .padding(12)
                        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
                        .transition(.opacity)
                } else if let pill = controller.pill {
                    PillView(pill: pill, geometry: controller.geometry)
                        .frame(width: shapeSize.width, height: shapeSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipShape(shape)
            .contentShape(shape)
            .offset(x: shapeOffset)
            .onHover { controller.isHovering = $0 }
            .animation(controller.animation.animation(expanding: controller.isExpanded), value: controller.isExpanded)
            .animation(controller.animation.animation(expanding: controller.pill != nil), value: controller.pill)
            Spacer(minLength: 0)
        }
        .frame(width: controller.geometry.panelSize.width, height: controller.geometry.panelSize.height, alignment: .top)
    }
}

private let hitTestableInvisibleOpacity = 0.02

private struct PillView: View {
    let pill: PillStatus
    let geometry: NotchGeometry

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
            if let artwork = pill.artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(width: geometry.pillTrailingWidth(for: pill))
            } else {
                Text(pill.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, NotchGeometry.pillTextPadding)
                    .frame(width: geometry.pillTrailingWidth(for: pill), alignment: .leading)
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
