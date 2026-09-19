import SwiftUI

public struct NotchView<Content: View>: View {
    private let controller: NotchController
    private let content: () -> Content

    public init(controller: NotchController, @ViewBuilder content: @escaping () -> Content) {
        self.controller = controller
        self.content = content
    }

    private var shapeSize: CGSize {
        if controller.isExpanded {
            return controller.geometry.expandedShapeSize
        }
        return controller.pill == nil ? controller.geometry.notchSize : controller.geometry.pillShapeSize
    }

    private var shape: NotchShape {
        NotchShape(bottomRadius: controller.isExpanded ? 24 : 12)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                if controller.isExpanded {
                    content()
                        .padding(.top, controller.geometry.notchSize.height)
                        .padding(12)
                        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
                        .transition(.opacity)
                } else if let pill = controller.pill {
                    PillView(pill: pill, notchWidth: controller.geometry.notchSize.width)
                        .frame(width: shapeSize.width, height: shapeSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipShape(shape)
            .contentShape(shape)
            .onHover { controller.isHovering = $0 }
            .animation(controller.animation.animation(expanding: controller.isExpanded), value: controller.isExpanded)
            .animation(controller.animation.animation(expanding: controller.pill != nil), value: controller.pill == nil)
            Spacer(minLength: 0)
        }
        .frame(width: controller.geometry.panelSize.width, height: controller.geometry.panelSize.height, alignment: .top)
    }
}

private struct PillView: View {
    let pill: PillStatus
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let symbol = pill.systemImage {
                    Image(systemName: symbol)
                } else {
                    Circle().frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            Text(pill.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(pill.priority >= .attention ? .orange : .white)
        .padding(.horizontal, 10)
    }
}
