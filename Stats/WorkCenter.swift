import AppKit
import Kit
import SwiftUI

@MainActor
final class StatsWorkCenter {
    static let title = "工作追踪"
    static let shared = StatsWorkCenter()

    private let store = WorkStore()
    private let state = PanelState()
    private let cpuState = PanelState()
    private let combinedState = PanelState()

    private lazy var settingsHost = NSHostingView(rootView: WorkPanel(store: store, state: state))
    var settingsView: NSView { settingsHost }
    var mayClose: Bool {
        state.commitKeyword(in: store)
        cpuState.commitKeyword(in: store)
        combinedState.commitKeyword(in: store)
        return store.flush() || !store.canEdit
    }

    static func prepareLocalPreferences() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "setupProcess") == nil else { return }
        for key in ["CPU", "RAM", "GPU", "Disk", "Network", "Sensors", "Bluetooth", "Battery", "Clock"] {
            defaults.set(key == "CPU" || key == "RAM", forKey: key + "_state")
        }
        defaults.set("mini", forKey: "CPU_widget")
        defaults.set("mini", forKey: "RAM_widget")
        defaults.set(true, forKey: "CombinedModules")
        defaults.set("rings", forKey: "CombinedModules_display")
        defaults.set("Never", forKey: "update-interval")
        defaults.set(true, forKey: "setupProcess")
        importInitialWorkItems()
    }

    private static func importInitialWorkItems() {
        let target = WorkFiles.local
        let old = WorkFiles(directory: target.directory.deletingLastPathComponent()
            .appendingPathComponent("com.moolean.macworktracker", isDirectory: true))
        guard (try? target.load().isEmpty) == true,
              let existing = try? old.load(), !existing.isEmpty else { return }
        do { try target.save(existing) }
        catch { NSLog("Stats could not import the initial work items: %@", error.localizedDescription) }
    }

    func prepareMonitoringPanels(combined: CombinedView) {
        installEditMenuIfNeeded()
        modules.first(where: { $0.moduleType == .CPU })?.secondaryPopupPage = monitorPage(state: cpuState)
        combined.secondaryPopupPage = monitorPage(state: combinedState)
    }

    private func monitorPage(state: PanelState) -> PopupPage {
        PopupPage(label: Self.title, size: NSSize(width: CombinedView.panelWidth, height: 370)) { [store] in
            state.commitKeyword(in: store)
            state.requestFocus(.search)
            let host = NSHostingView(rootView: WorkPanel(store: store, state: state))
            host.sizingOptions = []
            return host
        } onClose: { [store] in
            state.commitKeyword(in: store)
            store.flush()
        }
    }

    private func installEditMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }
        let menu = NSMenu()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem()
        item.submenu = edit
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    func openInSettings(_ id: UUID? = nil) {
        guard let window = (NSApp.delegate as? AppDelegate)?.ensureSettingsWindow() else { return }
        state.commitKeyword(in: store)
        state.query = ""
        NotificationCenter.default.post(name: .clickInSettings, object: nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.open(module: Self.title)
        if let id, let item = store.item(id) {
            state.select(item)
            state.requestFocus(.notes)
        } else {
            state.requestFocus(.search)
        }
    }
}
