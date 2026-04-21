import AppKit
import Combine
import SwiftUI

// MARK: - App Entry Point

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A no-op Settings scene is required to satisfy the SwiftUI App protocol
        // when the real UI is driven by NSApplicationDelegate / NSStatusItem.
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var viewModel: MenuBarViewModel!
    private var cancellables = Set<AnyCancellable>()
    private var onboardingWindow: NSWindow?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon — pure menu-bar app.
        NSApp.setActivationPolicy(.accessory)

        viewModel = MenuBarViewModel()

        setupPopover()
        setupStatusItem()
        observeViewModel()

        if viewModel.showOnboarding {
            showOnboarding()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(viewModel)
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.action = #selector(handleButtonEvent(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        updateStatusItem()
    }

    @objc private func handleButtonEvent(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Right-Click Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        // Toggle
        let isAwake = viewModel.isAwake
        let toggleItem = NSMenuItem(
            title: isAwake ? "Deactivate Awake" : "Activate Awake",
            action: #selector(menuToggleAwake),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Quick timer presets
        let presets: [(String, Int)] = [
            ("30 Minutes", 30),
            ("1 Hour",     60),
            ("2 Hours",   120),
            ("4 Hours",   240),
        ]
        for (label, minutes) in presets {
            let item = NSMenuItem(title: label, action: #selector(menuStartTimer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Stop session
        let stopItem = NSMenuItem(title: "Stop Session", action: #selector(menuStopSession), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = isAwake
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        // Assign temporarily so NSStatusItem shows it, then clear so left-click still opens the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggleAwake() { viewModel.toggleManual() }
    @objc private func menuStopSession() { viewModel.stopAllSessions() }
    @objc private func menuStartTimer(_ sender: NSMenuItem) {
        viewModel.startTimer(minutes: sender.tag)
    }

    // MARK: - Status Item Appearance

    private func observeViewModel() {
        viewModel.$isAwake
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        // timerRemaining updates every second — drives the countdown in the menu bar.
        viewModel.$timerRemaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        // Onboarding dismissal closes the window.
        viewModel.$showOnboarding
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if !show {
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if viewModel.isAwake {
            // Orange sun — not a template so it renders in colour.
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button.image = NSImage(
                systemSymbolName: "sun.max.fill",
                accessibilityDescription: "Awake is active"
            )?.withSymbolConfiguration(cfg)

            // Show countdown if a timer is running.
            if let remaining = viewModel.timerRemaining {
                button.title = " \(formatTimer(remaining))"
            } else {
                button.title = ""
            }
        } else {
            // Moon — template so it follows the system appearance.
            let img = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Awake is inactive")
            img?.isTemplate = true
            button.image = img
            button.title = ""
        }
    }

    private func formatTimer(_ interval: TimeInterval) -> String {
        let total   = Int(interval)
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let vc = NSHostingController(
            rootView: OnboardingView().environmentObject(viewModel)
        )
        let window = NSWindow(contentViewController: vc)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
