import SwiftUI

struct GlassCardModifier: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.2),
                                        .white.opacity(0.05),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

extension View {
    func glassCard(tint: Color = .clear, cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }
}
