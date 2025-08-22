import SwiftUI

struct InnerShadow: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let x: CGFloat
    let y: CGFloat
    let color: Color
    
    init(
        radius: CGFloat = 12,
        opacity: Double = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 12,
        color: Color = .black
    ) {
        self.radius = radius
        self.opacity = opacity
        self.x = x
        self.y = y
        self.color = color
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(opacity), lineWidth: 1)
                    .blur(radius: radius)
                    .offset(x: x, y: y)
                    .mask(content)
            )
    }
}

extension View {
    func innerShadow(
        radius: CGFloat = 12,
        opacity: Double = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 12,
        color: Color = .black
    ) -> some View {
        self.modifier(InnerShadow(
            radius: radius,
            opacity: opacity,
            x: x,
            y: y,
            color: color
        ))
    }
}
