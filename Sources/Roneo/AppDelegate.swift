import AppKit
import RoneoCore
import Sparkle
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let updater = Updater.make()
    private let recentMenu = NSMenu(title: "Open Recent")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = makeMainMenu()
        // Leftovers from a crash; a minute's grace spares a job another instance is sending.
        DispatchQueue.global(qos: .utility).async { Scratch.app.clear(olderThan: 60) }
    }

    /// A launch or Dock click that opens nothing shows a blank window, never the Open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        PDFFileDocument.openBlank()
        return true
    }

    // MARK: Default viewer

    private var isDefaultViewer: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: .pdf) else { return false }
        return current.resolvingSymlinksInPath().standardizedFileURL
            == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        Task { @MainActor in
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf)
            } catch {
                let alert = NSAlert(error: error)
                alert.window.animationBehavior = .none
                alert.runModal()
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(makeDefaultViewer(_:)) else { return true }
        let isDefault = isDefaultViewer
        item.title = isDefault ? "roneo is the default PDF viewer" : "Make roneo the default PDF viewer"
        return !isDefault
    }

    // MARK: Open Recent

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: FileManager.default.displayName(atPath: url.path),
                                  action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: "Clear Menu",
                                action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""))
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    // MARK: Menus

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let host = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            host.submenu = menu
            main.addItem(host)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        let updatesItem = item("Check for Updates…", nil)
        if let updater {
            updatesItem.target = updater
            updatesItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        } else {
            updatesItem.isEnabled = false
            updatesItem.toolTip = "Only the installed roneo.app updates itself"
        }
        let defaultItem = item("Make roneo the default PDF viewer", #selector(makeDefaultViewer(_:)))
        defaultItem.target = self
        add("roneo", [
            item("About roneo", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            updatesItem,
            .separator(),
            defaultItem,
            .separator(),
            item("Hide roneo", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit roneo", #selector(NSApplication.terminate(_:)), "q"),
        ])

        let recentItem = item("Open Recent", nil)
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        add("File", [
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            .separator(),
            item("Print", #selector(DocumentWindowController.printFromBar(_:)), ""),
            item("Print with System Dialog…", #selector(DocumentWindowController.printWithSystemDialog(_:)), "p"),
        ])

        let findMenu = NSMenu(title: "Find")
        [
            item("Find…", #selector(DocumentWindowController.showFind(_:)), "f"),
            item("Find Next", #selector(DocumentWindowController.findNext(_:)), "g"),
            item("Find Previous", #selector(DocumentWindowController.findPrevious(_:)), "g", [.command, .shift]),
        ].forEach(findMenu.addItem)
        let findItem = item("Find", nil)
        findItem.submenu = findMenu
        add("Edit", [
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            findItem,
        ])

        // ⌘= reaches Zoom In too: on most layouts "+" needs Shift.
        let zoomInEquals = item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "=")
        zoomInEquals.isHidden = true
        zoomInEquals.allowsKeyEquivalentWhenHidden = true
        add("View", [
            item("Hide Thumbnails", #selector(DocumentWindowController.toggleThumbnails(_:)), "2", [.command, .option]),
            .separator(),
            item("Actual Size", #selector(DocumentWindowController.actualSize(_:)), "0"),
            item("Zoom to Fit Width", #selector(DocumentWindowController.zoomToFitWidth(_:)), "9"),
            item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+"),
            zoomInEquals,
            item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"),
            .separator(),
            item("Go to Page…", #selector(DocumentWindowController.goToPage(_:)), "g", [.command, .option]),
        ])

        add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = main.items.last?.submenu
        return main
    }
}
