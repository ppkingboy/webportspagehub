import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let library = try PageLibrary()
            let windowController = MainWindowController(library: library)
            mainWindowController = windowController
            windowController.onServerStateChange = { [weak self] _ in
                self?.rebuildStatusMenu()
            }

            configureStatusItem()
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)

            if CommandLine.arguments.contains("--serve") || AppPreferences.autoStart {
                windowController.startServer()
            }

            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法准备页面目录"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        mainWindowController?.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.stopServer()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.stack.fill",
            accessibilityDescription: "WebPort"
        )
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "WebPort"
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusItem, let mainWindowController else {
            return
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let toggleTitle = mainWindowController.serverIsRunning ? "停止服务" : "启动服务"
        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleServer),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "打开展示页",
            action: #selector(openHome),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.isEnabled = mainWindowController.serverIsRunning
        menu.addItem(openItem)

        let copyItem = NSMenuItem(
            title: "复制访问地址",
            action: #selector(copyAddress),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = mainWindowController.serverIsRunning
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 WebPort",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showMainWindow() {
        mainWindowController?.showMainWindow()
    }

    @objc private func toggleServer() {
        mainWindowController?.toggleServerFromMenu()
    }

    @objc private func openHome() {
        mainWindowController?.openHomePage()
    }

    @objc private func copyAddress() {
        mainWindowController?.copyAccessAddress()
    }
}
