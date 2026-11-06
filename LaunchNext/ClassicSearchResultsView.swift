import SwiftUI

/// Single-row search result presentation used by the Classic mode. Buho shows
/// up to seven results in the same column positions as the first grid row and
/// highlights the current item.
struct ClassicSearchResultsView: View {
    @ObservedObject var appStore: AppStore
    let items: [LaunchpadItem]
    @Binding var selectedIndex: Int?
    let iconSize: CGFloat
    let columnSpacing: CGFloat
    let onOpenApp: (AppInfo) -> Void
    let onOpenFolder: (FolderInfo) -> Void

    private let maxVisible = 7

    private var pageCount: Int {
        max(1, Int(ceil(Double(items.count) / Double(maxVisible))))
    }

    private var pageIndex: Int {
        min(max((selectedIndex ?? 0) / maxVisible, 0), pageCount - 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(0..<maxVisible, id: \.self) { local in
                    let global = pageIndex * maxVisible + local
                    if global < items.count {
                        itemButton(items[global], index: global)
                            .frame(maxWidth: .infinity)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 34)
            .frame(maxWidth: .infinity, alignment: .top)

            if pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        Button {
                            selectedIndex = min(page * maxVisible, items.count - 1)
                        } label: {
                            Circle()
                                .fill(Color.white.opacity(page == pageIndex ? 1 : 0.5))
                                .frame(width: 6, height: 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func itemButton(_ item: LaunchpadItem, index: Int) -> some View {
        LaunchpadItemButton(
            item: item,
            iconSize: iconSize,
            labelWidth: iconSize * 1.5,
            isSelected: selectedIndex == index,
            showLabel: appStore.showLabels,
            labelFontSize: appStore.isClassicLaunchpad ? ClassicMetrics.labelFontSize : CGFloat(appStore.iconLabelFontSize),
            labelFontWeight: appStore.isClassicLaunchpad ? .semibold : .medium,
            shouldAllowHover: true,
            hoverMagnificationEnabled: false,
            labelColor: appStore.classicTextColor == .light ? .white : (appStore.classicTextColor == .dark ? .black : nil),
            onTap: {
                selectedIndex = index
                open(item)
            },
            onDoubleClick: {
                selectedIndex = index
                open(item)
            }
        )
        .background {
            if selectedIndex == index {
                RoundedRectangle(cornerRadius: iconSize * 0.18, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .padding(-6)
            }
        }
    }

    private func open(_ item: LaunchpadItem) {
        switch item {
        case .app(let app):
            onOpenApp(app)
        case .folder(let folder):
            onOpenFolder(folder)
        case .missingApp, .empty:
            break
        }
    }
}
