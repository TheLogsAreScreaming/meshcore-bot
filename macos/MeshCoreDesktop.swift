import AppKit
import Foundation

// MARK: - Design system
//
// Every color, font, spacing value and corner radius used by the desktop app
// comes from `Theme`. Views never hard-code styling; they ask the theme.
// Colors are dynamic, so the app follows the system Light/Dark appearance.

enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 10
        static let control: CGFloat = 6
    }

    enum Palette {
        static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        }

        static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
        }

        /// Brand teal, used for identity marks and the selected sidebar item.
        static let brand = dynamic(light: hex(0x0B7A68), dark: hex(0x3CCFAE))
        static let text = NSColor.labelColor
        static let secondaryText = NSColor.secondaryLabelColor
        static let tertiaryText = NSColor.tertiaryLabelColor
        static let card = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.055))
        static let cardBorder = dynamic(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.09))
        static let codeBackground = dynamic(light: hex(0xF7F7F8), dark: hex(0x1B1C1E))
        static let sidebarSelection = dynamic(light: NSColor(white: 0, alpha: 0.075), dark: NSColor(white: 1, alpha: 0.10))
        static let success = NSColor.systemGreen
        static let warning = NSColor.systemOrange
        static let danger = NSColor.systemRed
        static let neutral = NSColor.systemGray
    }

    enum Typography {
        static let largeTitle = NSFont.systemFont(ofSize: 24, weight: .bold)
        static let title = NSFont.systemFont(ofSize: 17, weight: .semibold)
        static let headline = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 13)
        static let callout = NSFont.systemFont(ofSize: 12)
        static let caption = NSFont.systemFont(ofSize: 11)
        static let sectionLabel = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    enum Motion {
        /// Page transitions are skipped entirely when Reduce Motion is on.
        static var pageFade: TimeInterval {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
        }
    }
}

// MARK: - Reusable components

/// Rounded surface with a hairline border; re-resolves colors when the appearance changes.
final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Theme.Radius.card
        layer?.borderWidth = 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Theme.Palette.card.cgColor
            layer?.borderColor = Theme.Palette.cardBorder.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Background behind a sidebar item; highlights the selected section.
final class SelectionBackgroundView: NSView {
    var isSelected = false { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Theme.Radius.control
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? Theme.Palette.sidebarSelection : NSColor.clear).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Multi-line label that wraps to whatever width Auto Layout gives it.
final class WrappingLabel: NSTextField {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if preferredMaxLayoutWidth != newSize.width {
            preferredMaxLayoutWidth = newSize.width
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        if preferredMaxLayoutWidth != bounds.width {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum UI {
    static func label(_ value: String, font: NSFont = Theme.Typography.body,
                      color: NSColor = Theme.Palette.text) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func paragraph(_ value: String, font: NSFont = Theme.Typography.body,
                          color: NSColor = Theme.Palette.secondaryText) -> NSTextField {
        let field = WrappingLabel(wrappingLabelWithString: value)
        field.font = font
        field.textColor = color
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func sectionLabel(_ value: String) -> NSTextField {
        label(value.uppercased(), font: Theme.Typography.sectionLabel, color: Theme.Palette.secondaryText)
    }

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    static func symbolView(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = symbol(name, size: size)
        view.contentTintColor = color
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    enum ButtonRole { case primary, standard, destructive }

    static func button(_ title: String, symbol name: String? = nil, role: ButtonRole = .standard,
                       target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = Theme.Typography.body
        if let name, let image = symbol(name, size: 12, weight: .semibold) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        switch role {
        case .primary:
            button.bezelColor = .controlAccentColor
        case .destructive:
            button.contentTintColor = Theme.Palette.danger
        case .standard:
            break
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func textField(placeholder: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.font = Theme.Typography.body
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    static func vstack(_ views: [NSView], spacing: CGFloat, fillWidth: Bool = true) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        if fillWidth {
            // Grids keep their natural width so keys and values stay next to each other.
            for view in views where !(view is NSGridView) {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return stack
    }

    static func hstack(_ views: [NSView], spacing: CGFloat = Theme.Space.s,
                       trailing: [NSView] = []) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { stack.addView($0, in: .leading) }
        trailing.forEach { stack.addView($0, in: .trailing) }
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    /// A titled card whose children span its full inner width.
    static func card(_ title: String?, _ views: [NSView], spacing: CGFloat = Theme.Space.m) -> CardView {
        let card = CardView()
        var children = views
        if let title { children.insert(sectionLabel(title), at: 0) }
        let stack = vstack(children, spacing: spacing)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.Space.l),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Space.l),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Space.l),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.Space.l),
        ])
        return card
    }

    /// Two-column key/value grid with secondary-colored keys.
    static func keyValueGrid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { [label($0.0, font: Theme.Typography.callout,
                                                       color: Theme.Palette.secondaryText), $0.1] })
        grid.rowSpacing = Theme.Space.s
        grid.columnSpacing = Theme.Space.m
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    /// Form grid: right-aligned labels, leading-aligned controls (macOS settings convention).
    static func formGrid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { [label($0.0, font: Theme.Typography.body), $0.1] })
        grid.rowSpacing = Theme.Space.m
        grid.columnSpacing = Theme.Space.m
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        // A shared label column width keeps every form on the page aligned.
        grid.column(at: 0).width = 160
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    static func valueLabel() -> NSTextField {
        let field = label("—", font: Theme.Typography.body)
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }
}

// MARK: - App model

enum Section: Int, CaseIterable {
    case overview, connection, configuration, activity, help

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .connection: return "Radio & Connection"
        case .configuration: return "Configuration"
        case .activity: return "Activity Log"
        case .help: return "Help & Files"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge"
        case .connection: return "antenna.radiowaves.left.and.right"
        case .configuration: return "slider.horizontal.3"
        case .activity: return "text.alignleft"
        case .help: return "questionmark.circle"
        }
    }

    var keyEquivalent: String { String(rawValue + 1) }
}

enum BotState: Equatable {
    case stopped
    case running(pid: Int32, since: Date)
    case stopping
    case exitedUnexpectedly(code: Int32)

    var isActive: Bool {
        switch self {
        case .running, .stopping: return true
        case .stopped, .exitedUnexpectedly: return false
        }
    }
}

enum ConnectionMethod: Int, CaseIterable {
    case serial, ble, tcp

    init(configValue: String?) {
        switch configValue?.lowercased() {
        case "ble": self = .ble
        case "tcp": self = .tcp
        default: self = .serial
        }
    }

    var configValue: String { ["serial", "ble", "tcp"][rawValue] }
    var displayName: String { ["USB cable (serial)", "Bluetooth LE", "Network (TCP)"][rawValue] }
}

// MARK: - Application

final class MeshCoreDesktop: NSObject, NSApplicationDelegate, NSWindowDelegate,
                             NSTextViewDelegate, NSTextFieldDelegate, NSComboBoxDelegate,
                             NSMenuItemValidation {
    private var window: NSWindow!
    private var process: Process?
    private var logPipe: Pipe?
    private var stopRequested = false
    private var restartAfterStop = false
    private var closeConfirmed = false
    private var uptimeTimer: Timer?
    private var state: BotState = .stopped { didSet { render() } }

    private let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MeshCore Bot", isDirectory: true)

    private var config: URL { home.appendingPathComponent("config.ini") }
    private var configBackup: URL { home.appendingPathComponent("config.ini.bak") }
    private var botExecutable: URL {
        Bundle.main.resourceURL!.appendingPathComponent("bot/meshcore-bot-cli")
    }

    // Navigation
    private var pages: [Section: NSView] = [:]
    private var sidebarItems: [Section: (background: SelectionBackgroundView, button: NSButton)] = [:]
    private var currentSection: Section = .overview
    private let sidebarStatusSymbol = UI.symbolView("circle.fill", size: 9, color: Theme.Palette.neutral)
    private let sidebarStatusLabel = UI.label("Stopped", font: Theme.Typography.callout, color: Theme.Palette.text)

    // Overview
    private let statusSymbol = UI.symbolView("stop.circle", size: 30, color: Theme.Palette.neutral)
    private let statusTitle = UI.label("Stopped", font: Theme.Typography.title)
    private let statusDetail = UI.label("", font: Theme.Typography.callout, color: Theme.Palette.secondaryText)
    private var toggleButton: NSButton!
    private var dashboardButton: NSButton!
    private var setupCard: NSView!
    private let radioMethodValue = UI.valueLabel()
    private let radioDeviceValue = UI.valueLabel()
    private let dashboardStateValue = UI.valueLabel()
    private let dashboardAddressValue = UI.valueLabel()
    private let recentActivity = UI.paragraph("No activity yet. Start the bot to see its output here.",
                                              font: Theme.Typography.monoSmall)
    private var recentLines: [String] = []
    private var recentRefreshScheduled = false

    // Radio & Connection
    private let methodPopup = NSPopUpButton()
    private let serialCombo = NSComboBox()
    private let bleField = UI.textField(placeholder: "Leave empty to find the first radio", width: 280)
    private let hostField = UI.textField(placeholder: "192.168.1.50 or radio.local", width: 280)
    private let tcpPortField = UI.textField(placeholder: "5000", width: 90)
    private let timeoutField = UI.textField(placeholder: "30", width: 90)
    private let retriesField = UI.textField(placeholder: "0", width: 90)
    private let dashboardCheckbox = NSButton(checkboxWithTitle: "Start the web dashboard with the bot",
                                             target: nil, action: nil)
    private let dashboardPortField = UI.textField(placeholder: "8080", width: 90)
    private var connectionGrid: NSGridView!
    private var advancedGrid: NSGridView!
    private var advancedToggle: NSButton!
    private let connectionHint = UI.paragraph("", font: Theme.Typography.callout)
    private let connectionFeedback = UI.label("", font: Theme.Typography.callout, color: Theme.Palette.secondaryText)

    // Configuration
    private var configEditor: NSTextView!
    private var savedConfigText = ""
    private let configStateLabel = UI.label("All changes saved", font: Theme.Typography.callout,
                                            color: Theme.Palette.secondaryText)
    private let configStateSymbol = UI.symbolView("checkmark.circle.fill", size: 12, color: Theme.Palette.success)

    // Activity
    private var output: NSTextView!
    private let autoScrollCheckbox = NSButton(checkboxWithTitle: "Follow new output", target: nil, action: nil)

    private var configIsDirty: Bool { configEditor != nil && configEditor.string != savedConfigText }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createConfigIfNeeded()
        NSApp.mainMenu = buildMainMenu()
        createWindow()
        reloadEditorFromDisk()
        refreshSummaries()
        loadConnectionForm()
        render()
        show(.overview, animated: false)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Pick up edits made outside the app (e.g. in Finder or another editor), unless
        // that would clobber unsaved edits in the built-in editor.
        guard window != nil, !configIsDirty else { return }
        reloadEditorFromDisk()
        refreshSummaries()
        refreshSerialPorts()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !closeConfirmed && !confirmDiscardOrSaveUnsavedConfig() {
            return .terminateCancel
        }
        // Never block the UI thread waiting for a bot or pipe reader to exit.
        uptimeTimer?.invalidate()
        logPipe?.fileHandleForReading.readabilityHandler = nil
        if let running = process, running.isRunning {
            running.terminationHandler = nil
            running.terminate()
        }
        process = nil
        logPipe = nil
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmDiscardOrSaveUnsavedConfig() else { return false }
        closeConfirmed = true
        return true
    }

    private func createConfigIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            // Seed relative-path resources without replacing user-customized files.
            for directory in ["translations", "data"] {
                if let source = Bundle.main.resourceURL?.appendingPathComponent("bot/_internal/" + directory),
                   let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
                    for case let file as URL in files {
                        let relative = String(file.path.dropFirst(source.path.count + 1))
                        let destination = home.appendingPathComponent(directory).appendingPathComponent(relative)
                        if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                        } else if !FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try FileManager.default.copyItem(at: file, to: destination)
                        }
                    }
                }
            }
            guard !FileManager.default.fileExists(atPath: config.path) else { return }
            if let example = Bundle.main.resourceURL?.appendingPathComponent("config.ini.example"),
               FileManager.default.fileExists(atPath: example.path) {
                var contents = try String(contentsOf: example, encoding: .utf8)
                // Bind the dashboard to loopback; never expose an unauthenticated dashboard on LAN.
                contents = contents.replacingOccurrences(of: "host = 0.0.0.0", with: "host = 127.0.0.1")
                // Start the loopback dashboard with the bot so Open Dashboard works out of the box.
                contents = Self.editingSection("Web_Viewer", in: contents) { section in
                    section.replacingOccurrences(of: "\nenabled = false", with: "\nenabled = true")
                        .replacingOccurrences(of: "\nauto_start = false", with: "\nauto_start = true")
                }
                try contents.write(to: config, atomically: true, encoding: .utf8)
            }
        } catch {
            showError("Could not prepare configuration", detail: error.localizedDescription)
        }
    }

    // MARK: Menu bar

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command, mine: Bool = true) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = modifiers
            if mine { menuItem.target = self }
            return menuItem
        }

        _ = submenu("MeshCore Bot", [
            item("About MeshCore Bot", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), mine: false),
            .separator(),
            item("Hide MeshCore Bot", #selector(NSApplication.hide(_:)), "h", mine: false),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], mine: false),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), mine: false),
            .separator(),
            item("Quit MeshCore Bot", #selector(NSApplication.terminate(_:)), "q", mine: false),
        ])

        let find = NSMenu(title: "Find")
        for (title, key, modifiers, tag) in [("Find…", "f", NSEvent.ModifierFlags.command, NSTextFinder.Action.showFindInterface),
                                             ("Find Next", "g", .command, .nextMatch),
                                             ("Find Previous", "g", [.command, .shift], .previousMatch),
                                             ("Use Selection for Find", "e", .command, .setSearchString)] {
            let findItem = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers, mine: false)
            findItem.tag = tag.rawValue
            find.addItem(findItem)
        }
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        _ = submenu("Edit", [
            item("Undo", Selector(("undo:")), "z", mine: false),
            item("Redo", Selector(("redo:")), "z", [.command, .shift], mine: false),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x", mine: false),
            item("Copy", #selector(NSText.copy(_:)), "c", mine: false),
            item("Paste", #selector(NSText.paste(_:)), "v", mine: false),
            item("Select All", #selector(NSText.selectAll(_:)), "a", mine: false),
            .separator(),
            findItem,
        ])

        _ = submenu("Bot", [
            item("Start Bot", #selector(startBot), "r"),
            item("Stop Bot", #selector(stopBot), "."),
            item("Restart Bot", #selector(restartBot), "r", [.command, .shift]),
            .separator(),
            item("Open Dashboard", #selector(openDashboard), "d"),
            item("Save Configuration", #selector(saveConfig), "s"),
            .separator(),
            item("Open Bot Folder", #selector(openFolder)),
        ])

        _ = submenu("View", Section.allCases.map { section in
            let viewItem = item(section.title, #selector(selectSection(_:)), section.keyEquivalent)
            viewItem.tag = section.rawValue
            return viewItem
        })

        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", mine: false),
            item("Zoom", #selector(NSWindow.performZoom(_:)), mine: false),
        ])
        NSApp.windowsMenu = windowMenu

        let helpMenu = submenu("Help", [item("MeshCore Bot Help", #selector(showHelp))])
        NSApp.helpMenu = helpMenu
        return main
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(startBot): return process == nil
        case #selector(stopBot): return process?.isRunning == true && state != .stopping
        case #selector(restartBot): return process?.isRunning == true && state != .stopping
        case #selector(openDashboard): return process?.isRunning == true
        case #selector(saveConfig): return configIsDirty
        case #selector(selectSection(_:)):
            menuItem.state = menuItem.tag == currentSection.rawValue ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: Window & navigation

    private func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "MeshCore Bot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 860, height: 580)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MeshCoreBotMainWindow")

        let root = NSView()
        window.contentView = root

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            content.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        buildSidebar(in: sidebar)

        let builders: [Section: () -> NSView] = [
            .overview: buildOverview,
            .connection: buildConnectionPage,
            .configuration: buildConfigurationPage,
            .activity: buildActivityPage,
            .help: buildHelpPage,
        ]
        for section in Section.allCases {
            let page = builders[section]!()
            page.isHidden = true
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                page.topAnchor.constraint(equalTo: content.topAnchor),
                page.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            pages[section] = page
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func buildSidebar(in sidebar: NSView) {
        let mark = UI.symbolView("antenna.radiowaves.left.and.right", size: 15, color: Theme.Palette.brand)
        let brand = UI.hstack([mark, UI.label("MeshCore Bot", font: Theme.Typography.headline)])

        brand.edgeInsets = NSEdgeInsets(top: 0, left: Theme.Space.s, bottom: 0, right: 0)
        var items: [NSView] = [brand]
        for section in Section.allCases {
            let background = SelectionBackgroundView()
            background.translatesAutoresizingMaskIntoConstraints = false
            let button = NSButton(title: section.title, target: self, action: #selector(selectSection(_:)))
            button.tag = section.rawValue
            button.isBordered = false
            button.image = UI.symbol(section.symbol, size: 13, weight: .medium)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
            button.font = Theme.Typography.body
            button.translatesAutoresizingMaskIntoConstraints = false
            button.toolTip = "\(section.title)  ⌘\(section.keyEquivalent)"
            background.addSubview(button)
            NSLayoutConstraint.activate([
                background.heightAnchor.constraint(equalToConstant: 30),
                button.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Theme.Space.s),
                button.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Theme.Space.s),
                button.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            ])
            sidebarItems[section] = (background, button)
            items.append(background)
        }

        let top = UI.vstack(items, spacing: 2)
        top.setCustomSpacing(Theme.Space.l, after: brand)
        sidebar.addSubview(top)

        let footer = UI.hstack([sidebarStatusSymbol, sidebarStatusLabel], spacing: 6)
        footer.setAccessibilityElement(true)
        footer.setAccessibilityLabel("Bot status")
        sidebar.addSubview(footer)

        let guide = window.contentLayoutGuide as? NSLayoutGuide
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: guide?.topAnchor ?? sidebar.topAnchor, constant: Theme.Space.m),
            top.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Theme.Space.m),
            top.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -Theme.Space.m),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Theme.Space.l + Theme.Space.xs),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -Theme.Space.l),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -Theme.Space.l),
        ])
    }

    @objc private func selectSection(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSButton)?.tag ?? 0
        show(Section(rawValue: tag) ?? .overview, animated: true)
    }

    @objc private func showHelp() {
        show(.help, animated: true)
    }

    private func show(_ section: Section, animated: Bool) {
        currentSection = section
        for (candidate, page) in pages {
            page.isHidden = candidate != section
        }
        for (candidate, item) in sidebarItems {
            let selected = candidate == section
            item.background.isSelected = selected
            item.button.contentTintColor = selected ? Theme.Palette.brand : Theme.Palette.text
            item.button.setAccessibilityValue(selected ? "selected" : nil)
        }
        if section == .connection { refreshSerialPorts() }
        guard let page = pages[section] else { return }
        let duration = animated ? Theme.Motion.pageFade : 0
        if duration > 0 {
            page.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                page.animator().alphaValue = 1
            }
        } else {
            page.alphaValue = 1
        }
    }

    /// Page scaffold: large title, one-line description, then either a scrolling column
    /// of cards or a body that fills the remaining height (editor and log pages).
    private func makePage(_ section: Section, subtitle: String, body: NSView, scrolls: Bool) -> NSView {
        let page = NSView()
        page.translatesAutoresizingMaskIntoConstraints = false
        let header = UI.vstack([UI.label(section.title, font: Theme.Typography.largeTitle),
                                UI.paragraph(subtitle)], spacing: Theme.Space.xs)
        page.addSubview(header)
        // The page isn't in the window yet, so offset from the page top by the title bar height
        // instead of constraining to the window's layout guide (that would throw).
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: page.topAnchor, constant: titlebarHeight + Theme.Space.s),
            header.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: Theme.Space.xxl),
            header.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -Theme.Space.xxl),
        ])

        if scrolls {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            let document = FlippedView()
            document.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = document
            document.addSubview(body)
            page.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Theme.Space.l),
                scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),
                document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
                document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                body.topAnchor.constraint(equalTo: document.topAnchor),
                body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Theme.Space.xxl),
                body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Theme.Space.xxl),
                body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Theme.Space.xxl),
            ])
        } else {
            page.addSubview(body)
            NSLayoutConstraint.activate([
                body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Theme.Space.l),
                body.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: Theme.Space.xxl),
                body.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -Theme.Space.xxl),
                body.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -Theme.Space.xl),
            ])
        }
        return page
    }

    // MARK: Overview page

    private func buildOverview() -> NSView {
        let setupText = UI.paragraph("Choose how the bot reaches your radio — USB cable, Bluetooth or network — then press Start Bot.")
        let setupButton = UI.button("Set Up Radio Connection", symbol: "arrow.right.circle", role: .primary,
                                    target: self, action: #selector(goToConnection))
        let setupTitle = UI.hstack([UI.symbolView("sparkles", size: 14, color: Theme.Palette.brand),
                                    UI.label("Finish setting up", font: Theme.Typography.headline)])
        setupCard = UI.card(nil, [setupTitle, setupText, UI.hstack([setupButton])], spacing: Theme.Space.s)

        toggleButton = UI.button("Start Bot", symbol: "play.fill", role: .primary, target: self, action: #selector(toggleBot))
        statusSymbol.setAccessibilityElement(false)
        let statusText = UI.vstack([statusTitle, statusDetail], spacing: 2, fillWidth: false)
        let statusRow = UI.hstack([statusSymbol, statusText], spacing: Theme.Space.m, trailing: [toggleButton])
        dashboardButton = UI.button("Open Dashboard", symbol: "safari", target: self, action: #selector(openDashboard))
        let actions = UI.hstack([
            dashboardButton,
            UI.button("Edit Config", symbol: "slider.horizontal.3", target: self, action: #selector(goToConfiguration)),
            UI.button("Open Bot Folder", symbol: "folder", target: self, action: #selector(openFolder)),
        ])
        let statusCard = UI.card("Bot status", [statusRow, separator(), actions])

        let radioCard = UI.card("Radio", [UI.keyValueGrid([("Method", radioMethodValue), ("Device", radioDeviceValue)]),
                                          UI.hstack([UI.button("Change…", target: self, action: #selector(goToConnection))])])
        let dashCard = UI.card("Web dashboard", [UI.keyValueGrid([("Status", dashboardStateValue),
                                                                   ("Address", dashboardAddressValue)]),
                                                  UI.hstack([UI.button("Change…", target: self, action: #selector(goToConnection))])])
        let summaries = NSStackView(views: [radioCard, dashCard])
        summaries.orientation = .horizontal
        summaries.distribution = .fillEqually
        summaries.alignment = .top
        summaries.spacing = Theme.Space.l
        summaries.translatesAutoresizingMaskIntoConstraints = false

        recentActivity.isSelectable = true
        recentActivity.maximumNumberOfLines = 6
        let viewLog = UI.button("View Activity Log", symbol: "text.alignleft", target: self, action: #selector(goToActivity))
        let activityCard = UI.card("Latest activity", [recentActivity, UI.hstack([viewLog])])

        let body = UI.vstack([setupCard, statusCard, summaries, activityCard], spacing: Theme.Space.l)
        return makePage(.overview, subtitle: "Start, stop and keep an eye on your MeshCore bot.", body: body, scrolls: true)
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    @objc private func goToConnection() { show(.connection, animated: true) }
    @objc private func goToConfiguration() { show(.configuration, animated: true) }
    @objc private func goToActivity() { show(.activity, animated: true) }

    // MARK: Radio & Connection page

    private func buildConnectionPage() -> NSView {
        methodPopup.removeAllItems()
        methodPopup.addItems(withTitles: ConnectionMethod.allCases.map(\.displayName))
        methodPopup.target = self
        methodPopup.action = #selector(connectionMethodChanged)
        methodPopup.translatesAutoresizingMaskIntoConstraints = false

        serialCombo.isEditable = true
        serialCombo.completes = true
        serialCombo.placeholderString = "/dev/cu.usbmodem…"
        serialCombo.translatesAutoresizingMaskIntoConstraints = false
        serialCombo.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let refresh = NSButton(image: UI.symbol("arrow.clockwise", size: 12, description: "Refresh port list")!,
                               target: self, action: #selector(refreshPortsPressed))
        refresh.bezelStyle = .rounded
        refresh.toolTip = "Refresh: look for connected radios again"
        let serialRow = UI.hstack([serialCombo, refresh], spacing: Theme.Space.s)
        let tcpRow = UI.hstack([hostField, UI.label("Port", color: Theme.Palette.secondaryText), tcpPortField])

        connectionGrid = UI.formGrid([("Connect using", methodPopup),
                                      ("Radio port", serialRow),
                                      ("Radio name", bleField),
                                      ("Radio address", tcpRow)])

        advancedGrid = UI.formGrid([("Connection timeout (s)", timeoutField),
                                    ("Reconnect attempts", retriesField)])
        let advancedHelp = UI.paragraph("Reconnect attempts: 0 keeps trying forever, which is best for a bot that runs unattended.",
                                        font: Theme.Typography.callout)
        let advancedBox = UI.vstack([advancedGrid, advancedHelp], spacing: Theme.Space.s)
        advancedBox.isHidden = true
        advancedToggle = NSButton(title: "Show advanced settings", target: self, action: #selector(toggleAdvanced))
        advancedToggle.bezelStyle = .disclosure
        advancedToggle.setButtonType(.pushOnPushOff)
        advancedToggle.title = ""
        let advancedLabel = UI.label("Advanced", font: Theme.Typography.body)
        let advancedRow = UI.hstack([advancedToggle, advancedLabel], spacing: Theme.Space.xs)
        advancedToggle.setAccessibilityLabel("Show advanced connection settings")

        let radioCard = UI.card("Radio", [connectionGrid, connectionHint, separator(), advancedRow, advancedBox])

        dashboardCheckbox.font = Theme.Typography.body
        let dashGrid = UI.formGrid([("", dashboardCheckbox), ("Port", dashboardPortField)])
        let dashHelp = UI.paragraph("The dashboard only listens on this Mac (127.0.0.1), so it isn't visible to other devices on your network.",
                                    font: Theme.Typography.callout)
        let dashboardCard = UI.card("Web dashboard", [dashGrid, dashHelp])

        let save = UI.button("Save Connection", symbol: "checkmark", role: .primary, target: self, action: #selector(saveConnection))
        let revert = UI.button("Revert", target: self, action: #selector(revertConnection))
        let footer = UI.hstack([connectionFeedback], trailing: [revert, save])
        let note = UI.paragraph("Saving updates config.ini and keeps a backup of the previous version. Restart the bot to apply changes.",
                                font: Theme.Typography.callout)

        for field in [bleField, hostField, tcpPortField, timeoutField, retriesField, dashboardPortField] {
            field.delegate = self
        }
        serialCombo.delegate = self
        dashboardCheckbox.target = self
        dashboardCheckbox.action = #selector(connectionFormEdited)

        let body = UI.vstack([radioCard, dashboardCard, note, footer], spacing: Theme.Space.l)
        return makePage(.connection, subtitle: "Tell the bot how to reach your MeshCore radio.", body: body, scrolls: true)
    }

    @objc private func toggleAdvanced() {
        let open = advancedToggle.state == .on
        if let box = advancedGrid.superview {
            box.isHidden = !open
        }
        advancedToggle.setAccessibilityLabel(open ? "Hide advanced connection settings" : "Show advanced connection settings")
    }

    @objc private func connectionMethodChanged() {
        updateConnectionRows()
        connectionFormEdited()
    }

    @objc private func connectionFormEdited() {
        connectionFeedback.stringValue = "Unsaved changes"
        connectionFeedback.textColor = Theme.Palette.warning
    }

    private var selectedMethod: ConnectionMethod {
        ConnectionMethod(rawValue: methodPopup.indexOfSelectedItem) ?? .serial
    }

    private func updateConnectionRows() {
        guard let grid = connectionGrid else { return }
        let method = selectedMethod
        grid.row(at: 1).isHidden = method != .serial
        grid.row(at: 2).isHidden = method != .ble
        grid.row(at: 3).isHidden = method != .tcp
        switch method {
        case .serial:
            connectionHint.stringValue = serialCombo.numberOfItems == 0
                ? "No USB radios found. Plug the radio in with a data-capable USB cable, then click Refresh."
                : "Pick your radio from the list. On a Mac, radio ports usually look like /dev/cu.usbmodem… or /dev/cu.usbserial…"
        case .ble:
            connectionHint.stringValue = "Make sure the radio is powered on and nearby. macOS will ask once for Bluetooth permission."
        case .tcp:
            connectionHint.stringValue = "Use the radio's IP address or host name. Port 5000 is the usual default."
        }
    }

    @objc private func refreshPortsPressed() {
        refreshSerialPorts()
        updateConnectionRows()
    }

    private func refreshSerialPorts() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let ports = names
            .filter { $0.hasPrefix("cu.") && !$0.localizedCaseInsensitiveContains("bluetooth") && $0 != "cu.debug-console" }
            .sorted()
            .map { "/dev/" + $0 }
        let current = serialCombo.stringValue
        serialCombo.removeAllItems()
        serialCombo.addItems(withObjectValues: ports)
        serialCombo.stringValue = current
        updateConnectionRows()
    }

    private func loadConnectionForm() {
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        func value(_ key: String, _ section: String = "Connection") -> String {
            Self.iniValue(key, section: section, in: text) ?? ""
        }
        let method = ConnectionMethod(configValue: value("connection_type"))
        methodPopup.selectItem(at: method.rawValue)
        refreshSerialPorts()
        serialCombo.stringValue = value("serial_port")
        bleField.stringValue = value("ble_device_name")
        hostField.stringValue = value("hostname")
        tcpPortField.stringValue = value("tcp_port")
        timeoutField.stringValue = value("timeout")
        retriesField.stringValue = value("reconnect_max_retries")
        let enabled = value("enabled", "Web_Viewer").lowercased() == "true"
            && value("auto_start", "Web_Viewer").lowercased() == "true"
        dashboardCheckbox.state = enabled ? .on : .off
        dashboardPortField.stringValue = value("port", "Web_Viewer")
        updateConnectionRows()
        connectionFeedback.stringValue = ""
    }

    @objc private func revertConnection() {
        loadConnectionForm()
    }

    @objc private func saveConnection() {
        guard !configIsDirty else {
            showError("Save or revert your Configuration edits first",
                      detail: "The Configuration page has unsaved changes to config.ini. Save or revert them, then save the connection.")
            return
        }
        func clean(_ field: NSTextField) -> String {
            field.stringValue.components(separatedBy: .newlines).joined().trimmingCharacters(in: .whitespaces)
        }
        func port(_ text: String, _ name: String) -> Bool {
            guard text.isEmpty || (Int(text).map { (1...65535).contains($0) } ?? false) else {
                showError("Check the \(name)", detail: "Enter a number from 1 to 65535.")
                return false
            }
            return true
        }
        let method = selectedMethod
        let serial = clean(serialCombo)
        let host = clean(hostField)
        let tcpPort = clean(tcpPortField)
        let timeout = clean(timeoutField)
        let retries = clean(retriesField)
        let dashboardPort = clean(dashboardPortField)

        if method == .serial && serial.isEmpty {
            showError("Choose a radio port", detail: "Pick your radio from the Radio port list, or type its /dev/cu… path.")
            return
        }
        if method == .tcp && (host.isEmpty || host == "0.0.0.0") {
            showError("Enter the radio's address", detail: "Use the radio's IP address or host name (not 0.0.0.0).")
            return
        }
        guard port(tcpPort, "radio port number"), port(dashboardPort, "dashboard port number") else { return }
        if !timeout.isEmpty && (Int(timeout) ?? 0) <= 0 {
            showError("Check the connection timeout", detail: "Enter a whole number of seconds greater than 0.")
            return
        }
        if !retries.isEmpty && (Int(retries) ?? -1) < 0 {
            showError("Check reconnect attempts", detail: "Enter 0 (keep trying) or a positive whole number.")
            return
        }

        guard let original = try? String(contentsOf: config, encoding: .utf8) else {
            showError("Cannot read config.ini", detail: "Open the Bot Folder and check that config.ini exists.")
            return
        }
        var text = Self.settingIniValue("connection_type", method.configValue, section: "Connection", in: original)
        switch method {
        case .serial: text = Self.settingIniValue("serial_port", serial, section: "Connection", in: text)
        case .ble: text = Self.settingIniValue("ble_device_name", clean(bleField), section: "Connection", in: text)
        case .tcp:
            text = Self.settingIniValue("hostname", host, section: "Connection", in: text)
            if !tcpPort.isEmpty { text = Self.settingIniValue("tcp_port", tcpPort, section: "Connection", in: text) }
        }
        if !timeout.isEmpty { text = Self.settingIniValue("timeout", timeout, section: "Connection", in: text) }
        if !retries.isEmpty { text = Self.settingIniValue("reconnect_max_retries", retries, section: "Connection", in: text) }
        let dashboardOn = dashboardCheckbox.state == .on ? "true" : "false"
        text = Self.settingIniValue("enabled", dashboardOn, section: "Web_Viewer", in: text)
        text = Self.settingIniValue("auto_start", dashboardOn, section: "Web_Viewer", in: text)
        if !dashboardPort.isEmpty { text = Self.settingIniValue("port", dashboardPort, section: "Web_Viewer", in: text) }

        guard text != original else {
            connectionFeedback.stringValue = "No changes to save"
            connectionFeedback.textColor = Theme.Palette.secondaryText
            return
        }
        guard writeConfigSafely(text) else { return }
        reloadEditorFromDisk()
        refreshSummaries()
        connectionFeedback.stringValue = "✓ Saved"
        connectionFeedback.textColor = Theme.Palette.success
        appendLog("Connection settings saved to config.ini.\n")
        offerRestartIfRunning()
    }

    // MARK: Configuration page

    private func buildConfigurationPage() -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = Theme.Radius.card
        configEditor = scroll.documentView as? NSTextView
        configEditor.isEditable = true
        configEditor.isRichText = false
        configEditor.allowsUndo = true
        configEditor.usesFindBar = true
        configEditor.isIncrementalSearchingEnabled = true
        // INI files must stay plain ASCII punctuation: no smart quotes, dashes or autocorrect.
        configEditor.isAutomaticQuoteSubstitutionEnabled = false
        configEditor.isAutomaticDashSubstitutionEnabled = false
        configEditor.isAutomaticTextReplacementEnabled = false
        configEditor.isAutomaticSpellingCorrectionEnabled = false
        configEditor.isContinuousSpellCheckingEnabled = false
        configEditor.font = Theme.Typography.mono
        configEditor.textColor = Theme.Palette.text
        configEditor.backgroundColor = Theme.Palette.codeBackground
        configEditor.textContainerInset = NSSize(width: Theme.Space.s, height: Theme.Space.m)
        configEditor.delegate = self
        configEditor.setAccessibilityLabel("config.ini contents")

        let restore = UI.button("Restore Backup…", symbol: "clock.arrow.circlepath", target: self, action: #selector(restoreBackup))
        let revert = UI.button("Revert", target: self, action: #selector(revertConfig))
        let save = UI.button("Save", symbol: "checkmark", role: .primary, target: self, action: #selector(saveConfig))
        save.toolTip = "Save config.ini (⌘S)"
        let toolbar = UI.hstack([configStateSymbol, configStateLabel], spacing: 6, trailing: [restore, revert, save])
        let hint = UI.paragraph("Lines starting with # or ; are comments. The [Connection] and [Bot] sections are required. Find with ⌘F.",
                                font: Theme.Typography.callout)

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        [toolbar, scroll, hint].forEach(body.addSubview)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: body.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: Theme.Space.m),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: Theme.Space.s),
            hint.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        return makePage(.configuration,
                        subtitle: "Every bot setting lives in config.ini. Changes apply the next time the bot starts.",
                        body: body, scrolls: false)
    }

    func textDidChange(_ notification: Notification) {
        if (notification.object as? NSTextView) === configEditor {
            updateConfigState()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        connectionFormEdited()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        connectionFormEdited()
    }

    private func updateConfigState() {
        let dirty = configIsDirty
        configStateLabel.stringValue = dirty ? "Unsaved changes" : "All changes saved"
        configStateSymbol.image = UI.symbol(dirty ? "pencil.circle.fill" : "checkmark.circle.fill", size: 12)
        configStateSymbol.contentTintColor = dirty ? Theme.Palette.warning : Theme.Palette.success
        window?.isDocumentEdited = dirty
    }

    private func reloadEditorFromDisk() {
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        savedConfigText = text
        if configEditor.string != text {
            configEditor.string = text
            configEditor.undoManager?.removeAllActions()
        }
        updateConfigState()
    }

    @objc private func revertConfig() {
        guard configIsDirty else { return }
        let alert = NSAlert()
        alert.messageText = "Discard your unsaved changes?"
        alert.informativeText = "config.ini will go back to how it was last saved."
        alert.addButton(withTitle: "Discard Changes").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        reloadEditorFromDisk()
    }

    @objc private func restoreBackup() {
        guard FileManager.default.fileExists(atPath: configBackup.path),
              let backupText = try? String(contentsOf: configBackup, encoding: .utf8) else {
            showError("No backup yet", detail: "A backup of config.ini is made automatically the first time you save a change.")
            return
        }
        let modified = (try? configBackup.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let when = modified.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "an earlier save"
        let alert = NSAlert()
        alert.messageText = "Restore the backup from \(when)?"
        alert.informativeText = "config.ini will be replaced with the backup. Your current settings become the new backup, so you can switch back."
            + (configIsDirty ? "\n\nUnsaved edits in the editor will be discarded." : "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore Backup").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard writeConfigSafely(backupText) else { return }
        reloadEditorFromDisk()
        refreshSummaries()
        loadConnectionForm()
        appendLog("Configuration restored from backup.\n")
        offerRestartIfRunning()
    }

    /// Returns true when it is safe to close: nothing unsaved, saved, or discarded.
    private func confirmDiscardOrSaveUnsavedConfig() -> Bool {
        guard configIsDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to config.ini before closing?"
        alert.informativeText = "Your edits will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveConfigFromEditor()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: Activity Log page

    private func buildActivityPage() -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = Theme.Radius.card
        output = scroll.documentView as? NSTextView
        output.isEditable = false
        output.isRichText = false
        output.usesFindBar = true
        output.backgroundColor = Theme.Palette.codeBackground
        output.textColor = Theme.Palette.text
        output.font = Theme.Typography.mono
        output.textContainerInset = NSSize(width: Theme.Space.s, height: Theme.Space.m)
        output.setAccessibilityLabel("LIVE ACTIVITY log output")
        output.string = "Ready. Settings and database files are stored in:\n\(home.path)\n\n"

        autoScrollCheckbox.state = .on
        autoScrollCheckbox.font = Theme.Typography.body
        let toolbar = UI.hstack([autoScrollCheckbox], trailing: [
            UI.button("Copy All", symbol: "doc.on.doc", target: self, action: #selector(copyLog)),
            UI.button("Save Log…", symbol: "square.and.arrow.down", target: self, action: #selector(saveLog)),
            UI.button("Clear", symbol: "trash", target: self, action: #selector(clearLog)),
        ])

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        [toolbar, scroll].forEach(body.addSubview)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: body.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: Theme.Space.m),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        return makePage(.activity, subtitle: "Live output from the bot. Errors are shown in red and warnings in orange.",
                        body: body, scrolls: false)
    }

    @objc private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output.string, forType: .string)
    }

    @objc private func saveLog() {
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "MeshCore Bot log \(stamp).txt"
        panel.allowedFileTypes = ["txt"]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.output.string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.showError("Could not save the log", detail: error.localizedDescription)
            }
        }
    }

    @objc private func clearLog() {
        output.string = ""
        recentLines.removeAll()
        refreshRecentActivity()
    }

    // MARK: Help & Files page

    private func buildHelpPage() -> NSView {
        let path = UI.label(home.path, font: Theme.Typography.monoSmall, color: Theme.Palette.text)
        path.isSelectable = true
        path.lineBreakMode = .byTruncatingMiddle
        let files = UI.card("Your files", [
            UI.paragraph("Settings (config.ini), its backup (config.ini.bak), the bot database and logs are kept here. Deleting the app does not remove them."),
            path,
            UI.hstack([UI.button("Open Bot Folder", symbol: "folder", target: self, action: #selector(openFolder)),
                       UI.button("Show config.ini in Finder", symbol: "magnifyingglass", target: self, action: #selector(revealConfig))]),
        ])

        let tips: [(String, String)] = [
            ("The bot stops right after starting",
             "It usually can't reach the radio. Check Radio & Connection, then look for the first red line in the Activity Log."),
            ("No radio in the port list",
             "Use a USB cable that carries data (not charge-only), plug the radio in, then click Refresh next to the port list on Radio & Connection."),
            ("Open Dashboard does nothing",
             "The dashboard runs while the bot is running. Turn it on under Radio & Connection → Web dashboard, then restart the bot."),
            ("macOS says the app can't be opened",
             "This build isn't notarized. Right-click MeshCore Bot in Applications, choose Open, then Open again. You only need to do this once."),
            ("A settings change broke something",
             "Go to Configuration → Restore Backup… to return to the version before your last save."),
        ]
        var tipViews: [NSView] = []
        for (title, detail) in tips {
            tipViews.append(UI.vstack([UI.label(title, font: Theme.Typography.headline),
                                       UI.paragraph(detail, font: Theme.Typography.callout)], spacing: 2))
        }
        let troubleshooting = UI.card("Troubleshooting", tipViews)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
        let about = UI.card("About", [UI.keyValueGrid([
            ("Version", UI.label(version)),
            ("Platform", UI.label("Intel Mac (x86_64)")),
        ])])

        let body = UI.vstack([files, troubleshooting, about], spacing: Theme.Space.l)
        return makePage(.help, subtitle: "Where your data lives and fixes for common problems.", body: body, scrolls: true)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([config])
    }

    // MARK: State rendering

    private struct StatusStyle {
        let symbol: String
        let color: NSColor
        let title: String
        let detail: String
    }

    private func statusStyle() -> StatusStyle {
        switch state {
        case .stopped:
            return StatusStyle(symbol: "stop.circle", color: Theme.Palette.neutral, title: "Stopped",
                               detail: "Press Start Bot to connect to your radio.")
        case let .running(pid, since):
            return StatusStyle(symbol: "checkmark.circle.fill", color: Theme.Palette.success, title: "Running",
                               detail: "Up \(Self.duration(since: since))  ·  PID \(pid)")
        case .stopping:
            return StatusStyle(symbol: "hourglass.circle", color: Theme.Palette.warning, title: "Stopping…",
                               detail: "Waiting for the bot to shut down cleanly.")
        case let .exitedUnexpectedly(code):
            return StatusStyle(symbol: "exclamationmark.triangle.fill", color: Theme.Palette.danger, title: "Stopped unexpectedly",
                               detail: "Exit code \(code). Check the Activity Log — often the radio couldn't be reached.")
        }
    }

    private func render() {
        guard window != nil else { return }
        let style = statusStyle()
        statusSymbol.image = UI.symbol(style.symbol, size: 30, weight: .medium, description: style.title)
        statusSymbol.contentTintColor = style.color
        statusTitle.stringValue = style.title
        statusDetail.stringValue = style.detail
        sidebarStatusSymbol.contentTintColor = style.color
        sidebarStatusLabel.stringValue = style.title
        sidebarStatusSymbol.superview?.setAccessibilityValue(style.title)

        let active = state.isActive
        toggleButton.title = active ? "Stop Bot" : "Start Bot"
        toggleButton.image = UI.symbol(active ? "stop.fill" : "play.fill", size: 12, weight: .semibold)
        toggleButton.bezelColor = active ? nil : .controlAccentColor
        toggleButton.isEnabled = state != .stopping
        dashboardButton.isEnabled = process?.isRunning == true

        if case .running = state {
            if uptimeTimer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self, case .running = self.state else { return }
                    self.statusDetail.stringValue = self.statusStyle().detail
                }
                RunLoop.main.add(timer, forMode: .common)
                uptimeTimer = timer
            }
        } else {
            uptimeTimer?.invalidate()
            uptimeTimer = nil
        }
    }

    private static func duration(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        let (h, m, s) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func refreshSummaries() {
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        func value(_ key: String, _ section: String = "Connection") -> String {
            Self.iniValue(key, section: section, in: text) ?? ""
        }
        let method = ConnectionMethod(configValue: value("connection_type"))
        radioMethodValue.stringValue = method.displayName
        var needsSetup = false
        switch method {
        case .serial:
            let port = value("serial_port")
            let present = !port.isEmpty && FileManager.default.fileExists(atPath: port)
            radioDeviceValue.stringValue = port.isEmpty ? "Not chosen" : (present ? port : "\(port) (not connected)")
            radioDeviceValue.textColor = present ? Theme.Palette.text : Theme.Palette.warning
            needsSetup = port.isEmpty || port == "/dev/ttyUSB0"
        case .ble:
            let name = value("ble_device_name")
            radioDeviceValue.stringValue = name.isEmpty ? "First radio found" : name
            radioDeviceValue.textColor = Theme.Palette.text
        case .tcp:
            let host = value("hostname")
            radioDeviceValue.stringValue = host.isEmpty ? "Not set" : "\(host):\(value("tcp_port").isEmpty ? "5000" : value("tcp_port"))"
            radioDeviceValue.textColor = host.isEmpty ? Theme.Palette.warning : Theme.Palette.text
            needsSetup = host.isEmpty
        }
        setupCard?.isHidden = !needsSetup

        let dashboardOn = value("enabled", "Web_Viewer").lowercased() == "true"
            && value("auto_start", "Web_Viewer").lowercased() == "true"
        dashboardStateValue.stringValue = dashboardOn ? "Starts with the bot" : "Off"
        dashboardStateValue.textColor = dashboardOn ? Theme.Palette.text : Theme.Palette.secondaryText
        let port = value("port", "Web_Viewer").isEmpty ? "8080" : value("port", "Web_Viewer")
        dashboardAddressValue.stringValue = dashboardOn ? "http://127.0.0.1:\(port)" : "—"
    }

    // MARK: Log

    private static let logAttributes: [NSAttributedString.Key: Any] = [.font: Theme.Typography.mono]

    private func appendLog(_ s: String) {
        DispatchQueue.main.async {
            let styled = NSMutableAttributedString()
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                var attributes = Self.logAttributes
                if line.contains("ERROR") || line.contains("CRITICAL") || line.contains("Traceback") {
                    attributes[.foregroundColor] = Theme.Palette.danger
                } else if line.contains("WARNING") {
                    attributes[.foregroundColor] = Theme.Palette.warning
                } else {
                    attributes[.foregroundColor] = Theme.Palette.text
                }
                let piece = index < lines.count - 1 ? line + "\n" : line
                styled.append(NSAttributedString(string: String(piece), attributes: attributes))
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { self.recentLines.append(trimmed) }
            }
            self.output.textStorage?.append(styled)
            // Keep the latest 250,000 UTF-16 code units to avoid runaway memory use.
            if let storage = self.output.textStorage, storage.length > 250_000 {
                storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 250_000))
            }
            if self.autoScrollCheckbox.state == .on {
                self.output.scrollToEndOfDocument(nil)
            }
            if self.recentLines.count > 6 { self.recentLines.removeFirst(self.recentLines.count - 6) }
            self.scheduleRecentActivityRefresh()
        }
    }

    /// Coalesces Overview updates so a burst of radio output redraws at most 4×/second.
    private func scheduleRecentActivityRefresh() {
        guard !recentRefreshScheduled else { return }
        recentRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.recentRefreshScheduled = false
            self?.refreshRecentActivity()
        }
    }

    private func refreshRecentActivity() {
        recentActivity.stringValue = recentLines.isEmpty
            ? "No activity yet. Start the bot to see its output here."
            : recentLines.joined(separator: "\n")
    }

    private func showError(_ title: String, detail: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.alertStyle = .warning
            if let window = self.window, window.isVisible, window.attachedSheet == nil {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    // MARK: Bot process

    @objc private func toggleBot() {
        process == nil ? startBot() : stopBot()
    }

    @objc private func startBot() {
        guard process == nil else {
            appendLog("Bot is already running or shutting down. Wait before starting again.\n")
            return
        }
        guard FileManager.default.fileExists(atPath: config.path) else {
            showError("config.ini is missing", detail: "Restore config.ini in the Bot Folder before starting.")
            return
        }
        guard let configText = try? String(contentsOf: config, encoding: .utf8),
              !configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("config.ini is empty or unreadable", detail: "Open Configuration and use Restore Backup…, or repair the file in the Bot Folder.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: botExecutable.path) else {
            showError("The bot program is missing", detail: "The bundled bot executable wasn't found. Reinstall MeshCore Bot.")
            return
        }
        if ConnectionMethod(configValue: Self.iniValue("connection_type", section: "Connection", in: configText)) == .serial {
            let port = Self.iniValue("serial_port", section: "Connection", in: configText) ?? ""
            if !FileManager.default.fileExists(atPath: port) {
                let alert = NSAlert()
                alert.messageText = "Radio not found"
                alert.informativeText = port.isEmpty
                    ? "No radio port is set. Choose your radio on Radio & Connection."
                    : "Nothing is connected at \(port). Plug in the radio or choose a different port."
                alert.addButton(withTitle: "Set Up Connection")
                alert.addButton(withTitle: "Start Anyway")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn: show(.connection, animated: true); return
                case .alertSecondButtonReturn: break
                default: return
                }
            }
        }
        let p = Process()
        p.executableURL = botExecutable
        p.arguments = ["--config", config.path]
        p.currentDirectoryURL = home
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        logPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Radio output may split UTF-8 code points between reads. Decode
            // with replacement instead of silently dropping an entire chunk.
            let decoded = String(decoding: data, as: UTF8.self)
            self?.appendLog(decoded)
        }
        p.terminationHandler = { [weak self] terminated in
            DispatchQueue.main.async {
                guard let self = self, self.process === terminated else { return }
                self.logPipe?.fileHandleForReading.readabilityHandler = nil
                self.logPipe = nil
                self.process = nil
                let requested = self.stopRequested
                self.stopRequested = false
                if requested || terminated.terminationStatus == 0 {
                    self.state = .stopped
                    self.appendLog("--- MeshCore Bot stopped ---\n")
                } else {
                    self.state = .exitedUnexpectedly(code: terminated.terminationStatus)
                    self.appendLog("--- MeshCore Bot exited unexpectedly (code \(terminated.terminationStatus)) ---\n")
                }
                if self.restartAfterStop {
                    self.restartAfterStop = false
                    self.startBot()
                }
            }
        }
        do {
            try p.run()
            process = p
            stopRequested = false
            state = .running(pid: p.processIdentifier, since: Date())
            appendLog("\n--- Starting MeshCore Bot ---\n")
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            logPipe = nil
            process = nil
            showError("The bot couldn't start", detail: error.localizedDescription)
        }
    }

    @objc private func stopBot() {
        guard let p = process, p.isRunning else {
            appendLog("Bot is not running; nothing to stop.\n")
            return
        }
        stopRequested = true
        p.terminate()
        state = .stopping
        // If the bot hangs during shutdown (e.g. a stuck radio read), force it after a grace period.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.process === p, p.isRunning else { return }
            self.appendLog("Bot did not stop within 15 seconds; forcing it to quit.\n")
            kill(p.processIdentifier, SIGKILL)
        }
    }

    @objc private func restartBot() {
        guard process?.isRunning == true else { startBot(); return }
        restartAfterStop = true
        stopBot()
    }

    private func offerRestartIfRunning() {
        guard process?.isRunning == true else { return }
        let alert = NSAlert()
        alert.messageText = "Restart the bot to apply your changes?"
        alert.informativeText = "The bot is running with the previous settings."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { restartBot() }
    }

    // MARK: Saving config.ini

    @objc private func saveConfig() {
        _ = saveConfigFromEditor()
    }

    /// Validates and saves the built-in editor. Returns true when the editor is clean afterwards.
    private func saveConfigFromEditor() -> Bool {
        let contents = savedConfigText
        let updated = configEditor.string
        guard updated != contents else { return true }
        guard writeConfigSafely(updated) else { return false }
        savedConfigText = updated
        updateConfigState()
        refreshSummaries()
        loadConnectionForm()
        appendLog("Configuration saved. Restart the bot to apply changes.\n")
        offerRestartIfRunning()
        return true
    }

    /// The single write path for config.ini: validate, back up the current file, then write atomically.
    private func writeConfigSafely(_ updated: String) -> Bool {
        guard !updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Configuration can't be empty", detail: "No changes were saved.")
            return false
        }
        let sectionHeaders = Set(updated.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("[") && $0.hasSuffix("]") && !$0.hasPrefix(";") && !$0.hasPrefix("#") })
        guard sectionHeaders.contains("[Connection]") && sectionHeaders.contains("[Bot]") else {
            showError("Missing required sections", detail: "config.ini must include [Connection] and [Bot] sections. No changes were saved.")
            return false
        }
        do {
            let backup = home.appendingPathComponent("config.ini.bak")
            let stagedBackup = home.appendingPathComponent("config.ini.bak.pending")
            if FileManager.default.fileExists(atPath: stagedBackup.path) {
                try FileManager.default.removeItem(at: stagedBackup)
            }
            try FileManager.default.copyItem(at: config, to: stagedBackup)
            if FileManager.default.fileExists(atPath: backup.path) {
                _ = try FileManager.default.replaceItemAt(backup, withItemAt: stagedBackup)
            } else {
                try FileManager.default.moveItem(at: stagedBackup, to: backup)
            }
            try updated.write(to: config, atomically: true, encoding: .utf8)
            return true
        } catch {
            showError("Could not save config.ini:", detail: error.localizedDescription)
            return false
        }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(home)
    }

    @objc private func openDashboard() {
        guard let p = process, p.isRunning else {
            showError("Start the bot first", detail: "The dashboard runs while the bot is running. If the radio can't connect, the bot and dashboard stop — check the Activity Log.")
            return
        }
        let contents: String
        do {
            contents = try String(contentsOf: config, encoding: .utf8)
        } catch {
            showError("Cannot read dashboard settings", detail: error.localizedDescription)
            return
        }
        guard contents.contains("[Web_Viewer]") else {
            showError("Dashboard settings are missing", detail: "config.ini has no [Web_Viewer] section.")
            return
        }
        func value(_ key: String) -> String? { Self.iniValue(key, section: "Web_Viewer", in: contents) }
        if value("enabled")?.lowercased() != "true" || value("auto_start")?.lowercased() != "true" {
            let alert = NSAlert()
            alert.messageText = "The web dashboard is turned off"
            alert.informativeText = "Turn it on under Radio & Connection → Web dashboard, then restart the bot."
            alert.addButton(withTitle: "Go to Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { show(.connection, animated: true) }
            return
        }
        // The desktop button should never navigate to a configured remote host.
        // The local dashboard remains accessible through loopback even if it binds to all interfaces.
        let host = "127.0.0.1"
        guard let port = Int(value("port") ?? "8080"), (1...65535).contains(port) else {
            showError("Invalid dashboard port", detail: "Set the dashboard port to a number from 1 to 65535 on Radio & Connection.")
            return
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        guard let url = components.url else {
            showError("Invalid dashboard address", detail: "Check the [Web_Viewer] settings.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: INI helpers

    /// Applies `transform` to the body of `[name]` in an INI string, up to the next section header.
    private static func editingSection(_ name: String, in contents: String, _ transform: (String) -> String) -> String {
        let marker = "[\(name)]"
        let header: Range<String.Index>?
        if contents.hasPrefix(marker) {
            header = contents.startIndex..<contents.index(contents.startIndex, offsetBy: marker.count)
        } else {
            header = contents.range(of: "\n" + marker)
        }
        guard let header else { return contents }
        let end = contents.range(of: "\n[", range: header.upperBound..<contents.endIndex)?.lowerBound ?? contents.endIndex
        var result = contents
        result.replaceSubrange(header.upperBound..<end, with: transform(String(contents[header.upperBound..<end])))
        return result
    }

    private static func assignmentKey(_ line: Substring) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"),
              let equals = trimmed.firstIndex(of: "=") else { return nil }
        return trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    }

    /// Reads an uncommented `key = value` from `[section]`.
    static func iniValue(_ key: String, section: String, in contents: String) -> String? {
        var body: String?
        _ = editingSection(section, in: contents) { body = $0; return $0 }
        guard let body else { return nil }
        for line in body.split(separator: "\n") where assignmentKey(line) == key {
            let value = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return value.count == 2 ? value[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        return nil
    }

    /// Sets `key = value` in `[section]`, editing the existing line in place so comments survive.
    static func settingIniValue(_ key: String, _ value: String, section: String, in contents: String) -> String {
        let marker = "[\(section)]"
        guard contents.hasPrefix(marker) || contents.contains("\n" + marker) else {
            let separator = contents.hasSuffix("\n") ? "" : "\n"
            return contents + separator + "\n\(marker)\n\(key) = \(value)\n"
        }
        return editingSection(section, in: contents) { body in
            var lines = body.components(separatedBy: "\n")
            if let index = lines.firstIndex(where: { assignmentKey(Substring($0)) == key }) {
                lines[index] = "\(key) = \(value)"
            } else {
                lines.insert("\(key) = \(value)", at: min(1, lines.count))
            }
            return lines.joined(separator: "\n")
        }
    }
}

let app = NSApplication.shared
let delegate = MeshCoreDesktop()
app.delegate = delegate
app.run()
