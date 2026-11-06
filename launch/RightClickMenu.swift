import SwiftUI
import AppKit
import launchContextMenuCore

private func redMenuSymbolImage(named symbolName: String) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    let configured = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? base
    configured.isTemplate = false
    return configured
}

extension LaunchpadItem {
    var contextMenuApp: AppInfo? {
        if case .app(let app) = self { return app }
        return nil
    }

    var contextMenuFolder: FolderInfo? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

private struct SwiftUIContextMenuContent: View {
    let entries: [AppContextMenuEntry]
    let configuration: AppContextMenuConfiguration
    let runtimeTarget: AppContextMenuRuntimeTarget
    let appStore: AppStore

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .separator:
                Divider()
            case .action(let item), .quickLaunch(let item):
                menuButton(for: item)
            case .submenu(let title, let items):
                Menu(configuration.title(for: title)) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button {
                            perform(item.action)
                        } label: {
                            Text(configuration.title(for: item.title))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menuButton(for item: AppContextMenuItem) -> some View {
        if item.role == .destructive {
            Button(role: .destructive) {
                perform(item.action)
            } label: {
                destructiveLabel(for: item)
            }
        } else {
            Button {
                perform(item.action)
            } label: {
                if let symbolName = item.symbolName {
                    Label(configuration.title(for: item.title), systemImage: symbolName)
                } else {
                    Text(configuration.title(for: item.title))
                }
            }
        }
    }

    @ViewBuilder
    private func destructiveLabel(for item: AppContextMenuItem) -> some View {
        if item.action == .uninstallWithConfiguredTool,
           let symbolName = item.symbolName,
           let redSymbol = redMenuSymbolImage(named: symbolName) {
            HStack(spacing: 6) {
                Image(nsImage: redSymbol)
                    .renderingMode(.original)
                Text(configuration.title(for: item.title))
                    .foregroundStyle(.red)
            }
        } else if let symbolName = item.symbolName {
            Label(configuration.title(for: item.title), systemImage: symbolName)
        } else {
            Text(configuration.title(for: item.title))
        }
    }

    private func perform(_ action: AppContextMenuAction) {
        guard let route = AppContextMenuRouter.route(action: action, target: runtimeTarget) else {
            assertionFailure("Unsupported context menu action for target")
            return
        }
        performAppContextMenuRoute(route, appStore: appStore)
    }
}

extension View {
    @ViewBuilder
    func launchNextHideAppContextMenu(app: AppInfo?, folder: FolderInfo? = nil, appStore: AppStore) -> some View {
        let configuration = AppContextMenuConfiguration(
            localize: { appStore.localized($0.localizationKey) },
            canShowInLayout: !appStore.isClassicLaunchpad && !appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            showQuarantineRemovalAction: appStore.showQuarantineRemovalAction && !appStore.isClassicLaunchpad,
            canUseConfiguredUninstallTool: appStore.uninstallToolAppURL != nil && !appStore.isClassicLaunchpad,
            folderQuickLaunchEnabled: appStore.folderQuickLaunchEnabled && !appStore.isClassicLaunchpad,
            classicMode: appStore.isClassicLaunchpad,
            moveToGroupTitle: "移动到分组",
            moveToGroupTargets: appStore.folders.map {
                AppContextMenuMoveTarget(id: $0.id, name: $0.name)
            }
        )

        if let app {
            let target = AppContextMenuTarget.app(container: .mainGrid)
            let entries = AppContextMenuBuilder.entries(
                for: target,
                surface: .swiftUIMainGrid,
                capabilities: configuration.capabilities(for: target)
            )
            contextMenu {
                SwiftUIContextMenuContent(
                    entries: entries,
                    configuration: configuration,
                    runtimeTarget: .app(app, folderID: nil),
                    appStore: appStore
                )
            }
        } else if let folder {
            let target = AppContextMenuTarget.folder
            let entries = AppContextMenuBuilder.entries(
                for: target,
                surface: .swiftUIMainGrid,
                capabilities: configuration.capabilities(for: target, folder: folder)
            )
            contextMenu {
                SwiftUIContextMenuContent(
                    entries: entries,
                    configuration: configuration,
                    runtimeTarget: .folder(folder),
                    appStore: appStore
                )
            }
        } else {
            self
        }
    }
}

private final class AppContextMenuInvocationBox: NSObject {
    let invocation: AppContextMenuInvocation

    init(action: AppContextMenuAction, target: AppContextMenuRuntimeTarget) {
        invocation = AppContextMenuInvocation(action: action, target: target)
    }
}

private func makeAppKitContextMenu(
    entries: [AppContextMenuEntry],
    configuration: AppContextMenuConfiguration,
    runtimeTarget: AppContextMenuRuntimeTarget,
    handlerTarget: AnyObject,
    action: Selector
) -> NSMenu {
    let menu = NSMenu(title: "")
    for entry in entries {
        switch entry {
        case .separator:
            menu.addItem(.separator())
        case .action(let descriptor), .quickLaunch(let descriptor):
            let title = configuration.title(for: descriptor.title)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = handlerTarget
            item.representedObject = AppContextMenuInvocationBox(
                action: descriptor.action,
                target: runtimeTarget
            )
            if let symbolName = descriptor.symbolName {
                item.image = descriptor.role == .destructive
                    ? redMenuSymbolImage(named: symbolName)
                    : NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            }
            if descriptor.role == .destructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            menu.addItem(item)
        case .submenu(let title, let items):
            let parent = NSMenuItem(title: configuration.title(for: title), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: configuration.title(for: title))
            for descriptor in items {
                let item = NSMenuItem(title: configuration.title(for: descriptor.title), action: action, keyEquivalent: "")
                item.target = handlerTarget
                item.representedObject = AppContextMenuInvocationBox(
                    action: descriptor.action,
                    target: runtimeTarget
                )
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
    }
    return menu
}

extension CAGridView {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        isContextMenuTracking = true
        defer { isContextMenuTracking = false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu(for: event)
    }

    private func contextMenu(for event: NSEvent) -> NSMenu? {
        guard !isDraggingItem, !isPageDragging else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        guard let (item, _) = itemAt(location) else {
            return classicBackgroundMenu
        }

        let target: AppContextMenuTarget
        let runtimeTarget: AppContextMenuRuntimeTarget
        let folder: FolderInfo?
        switch item {
        case .app(let app):
            target = .app(container: .mainGrid)
            runtimeTarget = .app(app, folderID: nil)
            folder = nil
        case .folder(let selectedFolder):
            target = .folder
            runtimeTarget = .folder(selectedFolder)
            folder = selectedFolder
        default:
            return nil
        }

        let capabilities = contextMenuConfiguration.capabilities(
            for: target,
            folder: folder,
            isBatchSelectionActive: isBatchSelectionMode
        )
        let entries = AppContextMenuBuilder.entries(
            for: target,
            surface: .coreAnimationMainGrid,
            capabilities: capabilities
        )
        return makeAppKitContextMenu(
            entries: entries,
            configuration: contextMenuConfiguration,
            runtimeTarget: runtimeTarget,
            handlerTarget: self,
            action: #selector(handleContextMenuAction(_:))
        )
    }

    @objc private func handleContextMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? AppContextMenuInvocationBox,
              let route = invocation.invocation.route else { return }
        switch route {
        case .startBatchSelection:
            enableBatchSelectionMode()
        case .finishBatchSelection:
            disableBatchSelectionMode()
        default:
            if let onContextMenuAction {
                onContextMenuAction(route)
            }
        }
    }

    private var classicBackgroundMenu: NSMenu? {
        guard let actions = classicBackgroundMenuActions, contextMenuConfiguration.classicMode else {
            return nil
        }
        let menu = NSMenu(title: "")
        if !actions.scenes.isEmpty {
            let parent = NSMenuItem(title: "场景", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "场景")
            for (index, scene) in actions.scenes.enumerated() {
                let item = NSMenuItem(title: scene.name, action: #selector(handleBackgroundScene(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "Settings", action: #selector(handleBackgroundSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let updates = NSMenuItem(title: "Check for Updates", action: #selector(handleBackgroundUpdates(_:)), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(.separator())
        let relaunch = NSMenuItem(title: "Relaunch", action: #selector(handleBackgroundRelaunch(_:)), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)
        let quit = NSMenuItem(title: "Quit", action: #selector(handleBackgroundQuit(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func handleBackgroundScene(_ sender: NSMenuItem) {
        guard let scenes = classicBackgroundMenuActions?.scenes, scenes.indices.contains(sender.tag) else { return }
        scenes[sender.tag].action()
    }
    @objc private func handleBackgroundSettings(_ sender: Any?) { classicBackgroundMenuActions?.settings() }
    @objc private func handleBackgroundUpdates(_ sender: Any?) { classicBackgroundMenuActions?.checkForUpdates() }
    @objc private func handleBackgroundRelaunch(_ sender: Any?) { classicBackgroundMenuActions?.relaunch() }
    @objc private func handleBackgroundQuit(_ sender: Any?) { classicBackgroundMenuActions?.quit() }
}

struct ClassicBackgroundMenuActions {
    var settings: () -> Void
    var checkForUpdates: () -> Void
    var relaunch: () -> Void
    var quit: () -> Void
    var scenes: [(name: String, action: () -> Void)]
}

extension CAFolderGridView {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = folderContextMenu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        isContextMenuTracking = true
        defer { isContextMenuTracking = false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        folderContextMenu(for: event)
    }

    private func folderContextMenu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let index = contextMenuItemIndex(at: location), apps.indices.contains(index) else { return nil }

        let app = apps[index]
        let isPinned = contextMenuConfiguration.isOpenFolderAppPinned(app)
        let target = AppContextMenuTarget.app(
            container: .folder(id: contextMenuFolderID, isPinned: isPinned)
        )
        let entries = AppContextMenuBuilder.entries(
            for: target,
            surface: .coreAnimationFolderGrid,
            capabilities: contextMenuConfiguration.capabilities(for: target)
        )
        return makeAppKitContextMenu(
            entries: entries,
            configuration: contextMenuConfiguration,
            runtimeTarget: .app(app, folderID: contextMenuFolderID),
            handlerTarget: self,
            action: #selector(handleContextMenuAction(_:))
        )
    }

    @objc private func handleContextMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? AppContextMenuInvocationBox,
              let route = invocation.invocation.route else { return }
        if let onContextMenuAction {
            onContextMenuAction(route)
        }
    }
}
