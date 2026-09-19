import SwiftUI

public struct NotchView<Content: View>: View {
    private let controller: NotchController
    private let content: () -> Content

    public init(controller: NotchController, @ViewBuilder content: @escaping () -> Content) {
        self.controller = controller
        self.content = content
    }

    private var shapeSize: CGSize {
        controller.isExpanded ? controller.geometry.expandedShapeSize : controller.geometry.notchSize
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
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipShape(shape)
            .contentShape(shape)
            .onHover { controller.isHovering = $0 }
            .animation(controller.animation.animation(expanding: controller.isExpanded), value: controller.isExpanded)
            Spacer(minLength: 0)
        }
        .frame(width: controller.geometry.panelSize.width, height: controller.geometry.panelSize.height, alignment: .top)
    }
}
