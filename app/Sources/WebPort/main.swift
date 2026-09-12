import AppKit

let application = NSApplication.shared
let applicationDelegate = AppDelegate()

application.delegate = applicationDelegate
application.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let applicationMenuItem = NSMenuItem(title: "WebPort", action: nil, keyEquivalent: "")
mainMenu.addItem(applicationMenuItem)

let applicationMenu = NSMenu()
applicationMenuItem.submenu = applicationMenu
applicationMenu.addItem(
    withTitle: "关于 WebPort",
    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
    keyEquivalent: ""
)
applicationMenu.addItem(.separator())
applicationMenu.addItem(
    withTitle: "隐藏 WebPort",
    action: #selector(NSApplication.hide(_:)),
    keyEquivalent: "h"
)
applicationMenu.addItem(
    withTitle: "退出 WebPort",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
application.mainMenu = mainMenu

application.run()
