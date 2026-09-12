import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let library = try PageLibrary()
            let windowController = MainWindowController(library: library)
            mainWindowController = windowController
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)

            if CommandLine.arguments.contains("--serve") {
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
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.stopServer()
    }
}

