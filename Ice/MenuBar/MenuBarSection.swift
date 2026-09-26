//
//  MenuBarSection.swift
//  Ice
//

import Cocoa

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: UniversalEventMonitor?

    /// A Boolean value that indicates whether the Ice Bar should be used.
    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    /// A weak reference to the menu bar manager's Ice Bar panel.
    private weak var iceBarPanel: IceBarPanel? {
        appState?.menuBarManager.iceBarPanel
    }

    /// The best screen to show the Ice Bar on.
    private weak var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.isActiveSpaceFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if useIceBar {
            if controlItem.state == .showItems {
                return false
            }
            switch name {
            case .visible, .hidden:
                return iceBarPanel?.currentSection != .hidden
            case .alwaysHidden:
                return iceBarPanel?.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if iceBarPanel?.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideItems
        case .alwaysHidden:
            if iceBarPanel?.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideItems
        }
    }

    private var isPreparing: Bool {
        iceBarPanel?.pendingSection == (name == .alwaysHidden ? .alwaysHidden : .hidden)
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// Creates a section with the given name, control item, and app state.
    init(name: Name, controlItem: ControlItem, appState: AppState) {
        self.name = name
        self.controlItem = controlItem
        self.appState = appState
    }

    /// Creates a section with the given name and app state.
    convenience init(name: Name, appState: AppState) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .iceIcon, appState: appState)
        case .hidden:
            ControlItem(identifier: .hidden, appState: appState)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden, appState: appState)
        }
        self.init(name: name, controlItem: controlItem, appState: appState)
    }

    /// Shows the section.
    func show(requestID: UUID = UUID()) {
        Logger(category: "MenuBarSection").info("[\(requestID)] show \(name.logString), hidden=\(isHidden), useIceBar=\(useIceBar)")
        guard
            let appState,
            isHidden,
            !isPreparing
        else {
            return
        }
        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }
        switch name {
        case _ where useIceBar:
            guard let screenForIceBar else {
                Logger(category: "MenuBarSection").warning("[\(requestID)] no screen for Ice Bar")
                return
            }
            iceBarPanel?.show(section: name == .alwaysHidden ? .alwaysHidden : .hidden, on: screenForIceBar, requestID: requestID) { [weak self] in
                self?.startRehideChecks()
            }
            return
        case .visible:
            iceBarPanel?.close(reason: "section \(name.logString) visibility change")
            guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
        case .hidden:
            iceBarPanel?.close(reason: "section \(name.logString) visibility change")
            guard let visibleSection = appState.menuBarManager.section(withName: .visible) else {
                return
            }
            controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        case .alwaysHidden:
            iceBarPanel?.close(reason: "section \(name.logString) visibility change")
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let visibleSection = appState.menuBarManager.section(withName: .visible)
            else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        }
        startRehideChecks()
    }

    /// Hides the section.
    func hide(reason: String = #function) {
        guard
            let appState,
            !isHidden || isPreparing
        else {
            return
        }
        iceBarPanel?.close(reason: "section \(name.logString): \(reason)")
        switch name {
        case _ where useIceBar:
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .hideItems
            }
        case .visible:
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            hiddenSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .hidden:
            guard
                let visibleSection = appState.menuBarManager.section(withName: .visible),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            visibleSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .alwaysHidden:
            controlItem.state = .hideItems
        }
        appState.allowShowOnHover()
        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    func toggle(source: String = #function) {
        let requestID = UUID()
        Logger(category: "MenuBarSection").info("[\(requestID)] toggle source=\(source), section=\(name.logString), hidden=\(isHidden), preparing=\(iceBarPanel?.pendingSection != nil)")
        if isPreparing {
            hide(reason: "[\(requestID)] toggle cancelled preparation")
        } else if isHidden {
            show(requestID: requestID)
        } else {
            hide()
        }
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .timed = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return
        }

        let presentationID = iceBarPanel?.presentationID
        rehideMonitor = UniversalEventMonitor(mask: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(
                        withTimeInterval: appState.settingsManager.generalSettingsManager.rehideInterval,
                        repeats: false
                    ) { [weak self] _ in
                        guard
                            let self,
                            let screen = NSScreen.main
                        else {
                            return
                        }
                        if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                            Task { @MainActor in
                                guard self.iceBarPanel?.presentationID == presentationID else { return }
                                self.hide(reason: "timed auto rehide")
                            }
                        } else {
                            Task { @MainActor in
                                guard self.iceBarPanel?.presentationID == presentationID else { return }
                                self.startRehideChecks()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// Stops running checks to determine when to rehide the section.
    func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}

// MARK: MenuBarSection: BindingExposable
extension MenuBarSection: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarSection = Logger(category: "MenuBarSection")
}
