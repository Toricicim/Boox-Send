import AppKit
import IOBluetooth
import SwiftUI
import UserNotifications

@main
struct BooxSendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        do {
            let urls = filenames.map { URL(fileURLWithPath: $0) }
            _ = try SharedQueue.shared.enqueue(urls: urls)
            sender.reply(toOpenOrPrint: .success)
            queueChanged()
        } catch {
            sender.reply(toOpenOrPrint: .failure)
            let content = UNMutableNotificationContent()
            content.title = "BOOX’a gönderilemedi"
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
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
        TransferCoordinator.shared.processQueue()
    }

    @objc private func queueChanged() {
        rebuildMenu()
        TransferCoordinator.shared.processQueue()
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
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

    @objc private func retry() { TransferCoordinator.shared.processQueue() }
    @objc private func openSettings() { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func rebuildMenu() {
        let pending = (try? SharedQueue.shared.jobs().filter { $0.state != .completed }.count) ?? 0
        let menu = NSMenu()
        let count = NSMenuItem(title: "Bekleyen dosya işleri: \(pending)", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        menu.addItem(item("Tekrar Dene", action: #selector(retry), key: "r"))
        menu.addItem(item("Ayarlar…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Çık", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

struct SettingsView: View {
    @StateObject private var config = ConfigurationStore.shared

    var body: some View {
        Form {
            Picker("Eşleştirilmiş BOOX", selection: $config.deviceAddress) {
                Text("Seçiniz").tag("")
                ForEach(config.pairedDevices, id: \.addressString) { device in
                    Text(device.name ?? device.addressString ?? "Bluetooth cihazı")
                        .tag(device.addressString ?? "")
                }
            }
            HStack {
                TextField("Kurulum kodu", text: $config.setupCode).textFieldStyle(.roundedBorder)
                Button("Üret") { config.generateCode() }
            }
            Text("Finder > Hızlı İşlemler > BOOX’a Gönder ile seçili dosyaları gönderin.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520)
    }
}
