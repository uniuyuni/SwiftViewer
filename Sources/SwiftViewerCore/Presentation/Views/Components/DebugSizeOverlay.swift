import SwiftUI

struct DebugSizeOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                Text("\(Int(geo.size.width)) x \(Int(geo.size.height))")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .cornerRadius(4)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        )
    }
}

extension View {
    func debugSize() -> some View {
        modifier(DebugSizeOverlay())
    }
}
