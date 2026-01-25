import SwiftUI

/// View overlay showing boundaries and dimensions

public extension View {
    func debugBox(dimensions: Bool = true) -> some View {
        overlay(
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if dimensions {
                        Text("W:\(String(format: "%.1f", geometry.size.width)) H:\(String(format: "%.1f", geometry.size.height))")
                            .foregroundStyle(.red)
                            .padding(1)
                            .background(Color.white)
                            .font(.system(size: 6))
                    }
                    Rectangle().stroke().foregroundStyle(.red)
                }
            }
        )
    }
}

#Preview {
    Text("XXX")
        .padding(10)
        .debugBox()
}
