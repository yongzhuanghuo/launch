import SwiftUI

/// One hover material for the row. Reuse the resolved wallpaper style without
/// reading another image or adding per-frame work to the grid.
struct LaunchpadPageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let isActive: Bool
    var backgroundStyle: BackgroundLabelContrast.Style? = nil
    var classicStyle: Bool = false
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    private var showsHover: Bool { isHovered && isActive }

    private var dotDiameter: CGFloat { classicStyle ? ClassicMetrics.pageDotSize : 8 }
    private var dotHitWidth: CGFloat { classicStyle ? ClassicMetrics.pageDotHitWidth : 16 }
    private var dotRowHeight: CGFloat { classicStyle ? ClassicMetrics.pageDotRowHeight : 28 }
    // With reduced transparency the hover backing is an opaque system color.
    private var dotStyle: BackgroundLabelContrast.Style? {
        showsHover && reduceTransparency ? nil : backgroundStyle
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(0, pageCount), id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill((dotStyle.map { $0.usesWhiteText ? Color.white : Color.black } ?? .primary)
                            .opacity(currentPage == index ? 1 : (showsHover ? 0.75 : 0.55)))
                        .frame(width: dotDiameter, height: dotDiameter)
                        .frame(width: dotHitWidth, height: dotRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(Text(verbatim: (index + 1).formatted()))
                .accessibilityAddTraits(currentPage == index ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .background {
            if showsHover {
                hoverBackground
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contentShape(Capsule())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovered = inside && isActive
            }
        }
        .onChange(of: isActive) { _, active in
            if !active { isHovered = false }
        }
        .onDisappear { isHovered = false }
        .allowsHitTesting(isActive)
        // Reserve the full hit area even at zero indicator padding. Hovering
        // changes only the material, never the grid layout or button geometry.
        .frame(height: dotRowHeight)
    }

    @ViewBuilder
    private var hoverBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color(nsColor: .windowBackgroundColor))
        } else {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
