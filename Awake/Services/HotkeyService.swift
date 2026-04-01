import AppKit
import Carbon
import Foundation
import os

final class HotkeyService {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private var localMonitor: Any?
    private var callback: (() -> Void)?
    private let logger = Logger(subsystem: Constants.appName, category: "Hotkey")

    private static let hotkeyID = EventHotKeyID(signature: OSType(0x4157_414B), id: 1) // "AWAK"

    func register(callback: @escaping () -> Void) {
        self.callback = callback

        // Try Carbon hotkey first (works globally without Accessibility permission)
        registerCarbonHotkey()

        // Also register local monitor as fallback for when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+A
            if event.modifierFlags.contains([.command, .shift]),
               event.keyCode == 0x00 {
                self?.callback?()
                return nil
            }
            return event
        }
    }

    private func registerCarbonHotkey() {
        // Cmd+Shift+A
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 0x00 // 'A' key

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                service.callback?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerResult == noErr else {
            logger.warning("Failed to install hotkey handler: \(handlerResult)")
            return
        }

        var hotkeyID = Self.hotkeyID
        let registerResult = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerResult == noErr {
            logger.info("Global hotkey registered: Cmd+Shift+A")
        } else {
            logger.warning("Failed to register global hotkey: \(registerResult)")
        }
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        callback = nil
    }

    deinit {
        unregister()
    }
}
