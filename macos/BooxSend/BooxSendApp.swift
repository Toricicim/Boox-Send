import AppKit
import IOBluetooth
import SwiftUI
import UserNotifications
import OSLog

@main
struct BooxSendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var idleQuitWorkItem: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "lifecycle")

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        do {
            let urls = filenames.map { URL(fileURLWithPath: $0) }
            _ = try SharedQueue.shared.enqueue(urls: urls)
            sender.reply(toOpenOrPrint: .success)
            queueChanged()
        } catch {
            sender.reply(toOpenOrPrint: .failure)
            let content = UNMutableNotificationContent()
            content.title = "Could not send to BOOX"
            content.body = error.localizedDescription
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "BOOX"
        rebuildMenu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(queueChanged), name: BooxConstants.queueNotification, object: nil
        )
        TransferCoordinator.shared.onIdle = { [weak self] in
            self?.coordinatorBecameIdle()
        }
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
        TransferCoordinator.shared.processQueue()

        let defaults = UserDefaults(suiteName: BooxConstants.appGroup)
        let deviceAddress = defaults?.string(forKey: "deviceAddress")
        let setupCode = defaults?.string(forKey: "setupCode")
        if deviceAddress.isNilOrEmpty || setupCode.isNilOrEmpty {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    @objc private func queueChanged() {
        cancelAutomaticQuit()
        rebuildMenu()
        TransferCoordinator.shared.processQueue()
    }

    private func coordinatorBecameIdle() {
        DispatchQueue.main.async { [weak self] in
            self?.rebuildMenu()
            self?.scheduleAutomaticQuit()
        }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           URL(string: value)?.host == "settings" {
            openSettings()
            return
        }
#if BOOX_LOCAL_SMOKE_TEST
        if let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           URL(string: value)?.host == "smoketest" {
            enqueueSmokeTest()
        }
#endif
        queueChanged()
    }

#if BOOX_LOCAL_SMOKE_TEST
    private func enqueueSmokeTest() {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("BOOX-Send-Test.txt")
        do {
            try Data("BOOX Send Bluetooth smoke test.\n".utf8).write(to: source, options: .atomic)
            _ = try SharedQueue.shared.enqueue(urls: [source])
            try? FileManager.default.removeItem(at: source)
        } catch {
            try? FileManager.default.removeItem(at: source)
        }
    }
#endif

    @objc private func retry() {
        cancelAutomaticQuit()
        TransferCoordinator.shared.processQueue()
    }
    @objc private func openSettings() {
        logger.notice("Opening settings window")
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "BOOX Send Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func rebuildMenu() {
        let pending = (try? SharedQueue.shared.jobs().filter { $0.state != .completed }.count) ?? 0
        let menu = NSMenu()
        let count = NSMenuItem(title: "Pending transfer jobs: \(pending)", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        menu.addItem(item("Retry", action: #selector(retry), key: "r"))
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func cancelAutomaticQuit() {
        idleQuitWorkItem?.cancel()
        idleQuitWorkItem = nil
    }

    private func scheduleAutomaticQuit() {
        cancelAutomaticQuit()
        logger.notice("Automatic quit scheduled after 60 idle seconds")
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) {
                self.logger.notice("Automatic quit postponed while a window is visible")
                self.scheduleAutomaticQuit()
            } else {
                self.logger.notice("Terminating after 60 idle seconds")
                NSApp.terminate(nil)
            }
        }
        idleQuitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty != false }
}

struct SettingsView: View {
    @StateObject private var config = ConfigurationStore.shared

    var body: some View {
        Form {
            Picker("Paired BOOX", selection: $config.deviceAddress) {
                Text("Select a device").tag("")
                ForEach(config.pairedDevices, id: \.addressString) { device in
                    Text(device.name ?? device.addressString ?? "Bluetooth device")
                        .tag(device.addressString ?? "")
                }
            }
            HStack {
                TextField("Setup code", text: $config.setupCode).textFieldStyle(.roundedBorder)
                Button("Generate") { config.generateCode() }
            }
            Text("In Finder, use Quick Actions > Send to BOOX for the selected files.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520)
    }
}
