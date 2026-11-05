import SwiftUI

/// Lays a template out on a 600pt wide board, exactly as drawn in Paper, then scales the whole board
/// to the width of its card. Text wraps the same at every card width, so a template looks the same in a
/// 330pt card and a 560pt one. Give `height` for a fixed-size board (a poster); leave it nil for a board
/// that grows with its text (an article).
///
/// React: a fixed-size stage inside a `transform: scale()` wrapper, with the wrapper's height set from the stage.
struct Board<Content: View>: View {
    static var designWidth: CGFloat { 600 }

    let background: Color
    var height: CGFloat?
    @ViewBuilder var content: Content
    @State private var measured: CGFloat = 0

    var body: some View {
        let h = height ?? (measured > 0 ? measured : 600)
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(Self.designWidth / h, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let scale = geo.size.width / Self.designWidth
                    content
                        .frame(width: Self.designWidth, height: height, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: height == nil)
                        .background(background)
                        .background(GeometryReader { inner in
                            Color.clear.preference(key: BoardHeightKey.self, value: inner.size.height)
                        })
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .clipped()
            .onPreferenceChange(BoardHeightKey.self) { if height == nil, $0 > 0 { measured = $0 } }
    }
}

private struct BoardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
