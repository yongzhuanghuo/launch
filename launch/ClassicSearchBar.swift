import SwiftUI
import AppKit

/// The narrow capsule search field used by the Classic presentation. The
/// menu button lives inside the field, matching BuhoLaunchpad's layout.
struct ClassicSearchBar: View {
    @ObservedObject var appStore: AppStore
    var onOpenSettings: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))

            TextField(text: $appStore.searchText,
                      prompt: Text(appStore.localized(.searchPlaceholder))
                        .foregroundStyle(.white.opacity(0.65))) {
                EmptyView()
            }
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isFocused)

            if appStore.searchText.isEmpty {
                if !appStore.hideSearchMenuButton {
                    menuButton
                } else {
                    Color.clear.frame(width: 15, height: 15)
                }
            } else {
                Button {
                    appStore.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: ClassicMetrics.searchWidth, height: ClassicMetrics.searchHeight)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.black.opacity(0.16))
        }
        .overlay(
            Capsule()
                .strokeBorder(isFocused ? Color.white.opacity(0.55) : Color.white.opacity(0.20),
                              lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 2)
        .onChange(of: isFocused) { _, focused in
            appStore.isClassicSearchFocused = focused
        }
        .onChange(of: appStore.searchFocusRequest) { _, _ in
            isFocused = true
        }
        .onDisappear {
            appStore.isClassicSearchFocused = false
        }
    }

    private var menuButton: some View {
        Menu {
            Button("Settings") { onOpenSettings() }
            Button(appStore.localized(.checkForUpdates)) {
                appStore.checkForUpdates()
            }
            Divider()
            Button("Relaunch") {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-n", Bundle.main.bundlePath]
                try? process.run()
                NSApp.terminate(nil)
            }
            Button(appStore.localized(.quit)) {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
