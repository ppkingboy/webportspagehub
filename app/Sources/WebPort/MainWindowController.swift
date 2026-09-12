import AppKit

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onServerStateChange: ((Bool) -> Void)?

    var serverIsRunning: Bool {
        isServerRunning
    }

    var accessURLString: String {
        baseURL.absoluteString
    }

    private let library: PageLibrary
    private let server: StaticHTTPServer
    private var pages: [StaticPage] = []
    private var networkAddresses: [NetworkAddress] = []
    private var pageMonitor: PageDirectoryMonitor?
    private var isServerRunning = false

    private let statusBadge = NSTextField(labelWithString: "已停止")
    private let statusDetail = NSTextField(wrappingLabelWithString: "服务当前未启动")
    private let portField = NSTextField(string: "8000")
    private let startStopButton = NSButton(title: "启动服务", target: nil, action: nil)
    private let bindingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addressPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let accessCodeCheckbox = NSButton(
        checkboxWithTitle: "启用访问码",
        target: nil,
        action: nil
    )
    private let accessCodeField = NSSecureTextField(frame: .zero)
    private let autoStartCheckbox = NSButton(
        checkboxWithTitle: "启动时自动运行服务",
        target: nil,
        action: nil
    )
    private let addressField = NSTextField(labelWithString: "启动服务后显示访问地址")
    private let copyAddressButton = NSButton(title: "复制地址", target: nil, action: nil)
    private let openHomeButton = NSButton(title: "打开展示页", target: nil, action: nil)
    private let pageCountLabel = NSTextField(labelWithString: "0 个页面")
    private let accessLogLabel = NSTextField(labelWithString: "最近访问：--")
    private let tableView = NSTableView()

    init(library: PageLibrary) {
        self.library = library
        server = StaticHTTPServer(rootURL: library.rootURL, library: library)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WebPort"
        window.minSize = NSSize(width: 780, height: 600)
        window.setFrameAutosaveName("WebPortMainWindow")
        window.center()

        super.init(window: window)

        networkAddresses = LANAddress.allIPv4Addresses()
        configureUI()
        configureCallbacks()
        loadPreferences()
        startPageMonitoring()
        reloadPages()
        updateServerUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startServer() {
        guard !isServerRunning else {
            return
        }

        guard let port = UInt16(portField.stringValue),
              port > 0 else {
            showError(StaticHTTPServerError.invalidPort.localizedDescription)
            return
        }

        let accessCode: String?
        if accessCodeCheckbox.state == .on {
            let value = accessCodeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                showError("启用访问码后，必须填写访问码。")
                return
            }
            accessCode = value
        } else {
            accessCode = nil
        }

        let binding = selectedBinding
        AppPreferences.port = Int(port)
        AppPreferences.binding = binding
        AppPreferences.selectedAddress = selectedAddress ?? ""

        statusBadge.stringValue = "启动中"
        statusBadge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
        statusBadge.textColor = .systemOrange
        statusDetail.stringValue = "正在监听端口 \(port)"
        startStopButton.isEnabled = false

        do {
            try server.start(
                port: port,
                binding: binding,
                selectedAddress: selectedAddress,
                accessCode: accessCode
            )
        } catch {
            setServerRunning(false, error: error.localizedDescription)
        }
    }

    func stopServer() {
        guard isServerRunning || startStopButton.title == "停止服务" else {
            return
        }

        server.stop()
        setServerRunning(false, error: nil)
    }

    func toggleServerFromMenu() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    func copyAccessAddress() {
        guard isServerRunning else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addressField.stringValue, forType: .string)
    }

    func openHomePage() {
        guard isServerRunning else {
            return
        }
        NSWorkspace.shared.open(baseURL)
    }

    func showMainWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .width
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        mainStack.addArrangedSubview(makeHeader())
        mainStack.addArrangedSubview(makeSeparator())
        mainStack.addArrangedSubview(makeStatusRow())
        mainStack.addArrangedSubview(makeServerControls())
        mainStack.addArrangedSubview(makeBindingControls())
        mainStack.addArrangedSubview(makeSecurityControls())
        mainStack.addArrangedSubview(makeAddressRow())
        mainStack.addArrangedSubview(makePageHeader())
        mainStack.addArrangedSubview(makeTable())
        mainStack.addArrangedSubview(accessLogLabel)
    }

    private func makeHeader() -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(
            systemSymbolName: "rectangle.stack.fill",
            accessibilityDescription: "静态页面"
        )
        imageView.contentTintColor = .controlAccentColor
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "WebPort")
        title.font = .systemFont(ofSize: 24, weight: .semibold)

        let textStack = NSStackView(views: [title])
        textStack.orientation = .vertical
        textStack.alignment = .leading

        let row = NSStackView(views: [imageView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 42),
            imageView.heightAnchor.constraint(equalToConstant: 42)
        ])

        return row
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeStatusRow() -> NSView {
        statusBadge.font = .systemFont(ofSize: 13, weight: .semibold)
        statusBadge.alignment = .center
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 6
        statusBadge.translatesAutoresizingMaskIntoConstraints = false

        statusDetail.font = .systemFont(ofSize: 13)
        statusDetail.textColor = .secondaryLabelColor

        let row = NSStackView(views: [statusBadge, statusDetail])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        NSLayoutConstraint.activate([
            statusBadge.widthAnchor.constraint(equalToConstant: 78),
            statusBadge.heightAnchor.constraint(equalToConstant: 28)
        ])

        return row
    }

    private func makeServerControls() -> NSView {
        let portLabel = NSTextField(labelWithString: "端口")
        portLabel.font = .systemFont(ofSize: 13, weight: .medium)

        portField.alignment = .center
        portField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        portField.translatesAutoresizingMaskIntoConstraints = false

        startStopButton.bezelStyle = .rounded
        startStopButton.target = self
        startStopButton.action = #selector(toggleServer)
        startStopButton.keyEquivalent = "\r"

        let row = NSStackView(views: [portLabel, portField, startStopButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        NSLayoutConstraint.activate([
            portField.widthAnchor.constraint(equalToConstant: 72),
            startStopButton.widthAnchor.constraint(equalToConstant: 112)
        ])

        return row
    }

    private func makeBindingControls() -> NSView {
        let bindingLabel = NSTextField(labelWithString: "访问范围")
        bindingLabel.font = .systemFont(ofSize: 13, weight: .medium)

        bindingPopup.addItems(withTitles: ServerBinding.allCases.map(\.title))
        bindingPopup.target = self
        bindingPopup.action = #selector(bindingChanged)

        let addressLabel = NSTextField(labelWithString: "网卡")
        addressLabel.font = .systemFont(ofSize: 13, weight: .medium)

        addressPopup.target = self
        addressPopup.action = #selector(addressChanged)

        let row = NSStackView(views: [bindingLabel, bindingPopup, addressLabel, addressPopup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        bindingPopup.widthAnchor.constraint(equalToConstant: 128).isActive = true
        addressPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        return row
    }

    private func makeSecurityControls() -> NSView {
        accessCodeCheckbox.target = self
        accessCodeCheckbox.action = #selector(accessCodeChanged)

        accessCodeField.placeholderString = "访问码"
        accessCodeField.isEnabled = false
        accessCodeField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        autoStartCheckbox.target = self
        autoStartCheckbox.action = #selector(autoStartChanged)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            accessCodeCheckbox,
            accessCodeField,
            spacer,
            autoStartCheckbox
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        return row
    }

    private func makeAddressRow() -> NSView {
        let label = NSTextField(labelWithString: "访问地址")
        label.font = .systemFont(ofSize: 13, weight: .medium)

        addressField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        addressField.isSelectable = true
        addressField.lineBreakMode = .byTruncatingMiddle

        copyAddressButton.bezelStyle = .rounded
        copyAddressButton.target = self
        copyAddressButton.action = #selector(copyAddress)

        openHomeButton.bezelStyle = .rounded
        openHomeButton.target = self
        openHomeButton.action = #selector(openHome)

        let row = NSStackView(views: [label, addressField, copyAddressButton, openHomeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copyAddressButton.widthAnchor.constraint(equalToConstant: 86).isActive = true
        openHomeButton.widthAnchor.constraint(equalToConstant: 100).isActive = true

        return row
    }

    private func makePageHeader() -> NSView {
        let title = NSTextField(labelWithString: "页面列表")
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        pageCountLabel.font = .systemFont(ofSize: 12)
        pageCountLabel.textColor = .secondaryLabelColor

        let openFolderButton = NSButton(title: "打开页面目录", target: self, action: #selector(openPagesFolder))
        openFolderButton.bezelStyle = .rounded

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshPages))
        refreshButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            title,
            pageCountLabel,
            spacer,
            openFolderButton,
            refreshButton
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        return row
    }

    private func makeTable() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pages"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedPage)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.selectionHighlightStyle = .regular

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        return scrollView
    }

    private func configureCallbacks() {
        server.onStateChange = { [weak self] running, error in
            DispatchQueue.main.async {
                self?.setServerRunning(running, error: error)
            }
        }

        server.onAccess = { [weak self] entry in
            DispatchQueue.main.async {
                self?.updateAccessLog(entry)
            }
        }

        accessLogLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        accessLogLabel.textColor = .tertiaryLabelColor
        accessLogLabel.lineBreakMode = .byTruncatingMiddle
    }

    private func loadPreferences() {
        portField.stringValue = String(AppPreferences.port)

        if let index = ServerBinding.allCases.firstIndex(of: AppPreferences.binding) {
            bindingPopup.selectItem(at: index)
        }

        loadNetworkAddresses()
        autoStartCheckbox.state = AppPreferences.autoStart ? .on : .off
        bindingChanged()
    }

    private func loadNetworkAddresses() {
        addressPopup.removeAllItems()

        if networkAddresses.isEmpty {
            networkAddresses = [NetworkAddress(name: "本机", address: "127.0.0.1")]
        }

        for address in networkAddresses {
            addressPopup.addItem(withTitle: address.displayName)
            addressPopup.lastItem?.representedObject = address.address
        }

        let preferredAddress = AppPreferences.selectedAddress
        if let index = addressPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == preferredAddress
        }) {
            addressPopup.selectItem(at: index)
        } else {
            addressPopup.selectItem(at: 0)
        }
    }

    private func startPageMonitoring() {
        pageMonitor = PageDirectoryMonitor(directoryURL: library.rootURL) { [weak self] in
            DispatchQueue.main.async {
                self?.reloadPages()
            }
        }
    }

    private func setServerRunning(_ running: Bool, error: String?) {
        isServerRunning = running
        startStopButton.isEnabled = true
        portField.isEnabled = !running
        bindingPopup.isEnabled = !running
        addressPopup.isEnabled = !running && selectedBinding != .localhost
        accessCodeCheckbox.isEnabled = !running
        accessCodeField.isEnabled = !running && accessCodeCheckbox.state == .on

        if running {
            statusBadge.stringValue = "运行中"
            statusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
            statusBadge.textColor = .systemGreen
            statusDetail.stringValue = accessCodeCheckbox.state == .on
                ? "服务已启动，访问码已启用。"
                : "服务已启动，其他设备可通过访问地址连接。"
            startStopButton.title = "停止服务"
            addressField.stringValue = baseURL.absoluteString
        } else {
            statusBadge.stringValue = error == nil ? "已停止" : "启动失败"
            statusBadge.layer?.backgroundColor = (
                error == nil ? NSColor.secondaryLabelColor : NSColor.systemRed
            ).withAlphaComponent(0.14).cgColor
            statusBadge.textColor = error == nil ? .secondaryLabelColor : .systemRed
            statusDetail.stringValue = error ?? "服务当前未启动"
            startStopButton.title = "启动服务"
            addressField.stringValue = "启动服务后显示访问地址"

            if let error {
                showError(error)
            }
        }

        copyAddressButton.isEnabled = running
        openHomeButton.isEnabled = running
        onServerStateChange?(running)
    }

    private func updateServerUI() {
        setServerRunning(false, error: nil)
    }

    private func reloadPages() {
        pages = library.scanPages()
        pageCountLabel.stringValue = "\(pages.count) 个页面"
        tableView.reloadData()
    }

    private func updateAccessLog(_ entry: AccessLogEntry) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        accessLogLabel.stringValue =
            "最近访问：\(formatter.string(from: entry.date))  \(entry.remoteAddress)  \(entry.path)"
    }

    private var selectedBinding: ServerBinding {
        let index = max(bindingPopup.indexOfSelectedItem, 0)
        return ServerBinding.allCases[index]
    }

    private var selectedAddress: String? {
        if selectedBinding == .localhost {
            return "127.0.0.1"
        }
        return addressPopup.selectedItem?.representedObject as? String
    }

    private var baseURL: URL {
        let host: String

        switch selectedBinding {
        case .localhost:
            host = "127.0.0.1"
        case .lan, .all:
            host = selectedAddress ?? LANAddress.primaryIPv4Address() ?? "127.0.0.1"
        }

        let port = portField.stringValue.isEmpty ? "8000" : portField.stringValue
        return URL(string: "http://\(host):\(port)/")!
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.beginSheetModal(for: window!)
    }

    @objc private func toggleServer() {
        toggleServerFromMenu()
    }

    @objc private func bindingChanged() {
        let binding = selectedBinding
        AppPreferences.binding = binding
        addressPopup.isEnabled = !isServerRunning && binding != .localhost
        accessCodeField.isEnabled = !isServerRunning && accessCodeCheckbox.state == .on
    }

    @objc private func addressChanged() {
        AppPreferences.selectedAddress = selectedAddress ?? ""
    }

    @objc private func accessCodeChanged() {
        accessCodeField.isEnabled = accessCodeCheckbox.state == .on && !isServerRunning
        if accessCodeCheckbox.state == .off {
            accessCodeField.stringValue = ""
        }
    }

    @objc private func autoStartChanged() {
        AppPreferences.autoStart = autoStartCheckbox.state == .on
    }

    @objc private func copyAddress() {
        copyAccessAddress()
    }

    @objc private func openHome() {
        openHomePage()
    }

    @objc private func openPagesFolder() {
        NSWorkspace.shared.open(library.rootURL)
    }

    @objc private func refreshPages() {
        reloadPages()
    }

    @objc private func openSelectedPage() {
        let row = tableView.clickedRow
        guard row >= 0, row < pages.count else {
            return
        }

        let page = pages[row]
        guard page.enabled else {
            return
        }

        let pageURL = page.relativePath
            .split(separator: "/")
            .reduce(baseURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }

        NSWorkspace.shared.open(pageURL)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        pages.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PageCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PageCellView
            ?? PageCellView(identifier: identifier)
        cell.configure(with: pages[row])
        return cell
    }
}

private final class PageCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let groupLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        groupLabel.font = .systemFont(ofSize: 11, weight: .medium)
        groupLabel.alignment = .right

        let textStack = NSStackView(views: [titleLabel, pathLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        groupLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        addSubview(groupLabel)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: groupLabel.leadingAnchor, constant: -12),

            groupLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            groupLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            groupLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with page: StaticPage) {
        titleLabel.stringValue = page.title
        pathLabel.stringValue = page.relativePath
        groupLabel.stringValue = page.enabled ? page.group : "已隐藏"
        groupLabel.textColor = page.enabled ? .controlAccentColor : .secondaryLabelColor
    }
}
