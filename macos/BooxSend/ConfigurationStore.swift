import Foundation
import IOBluetooth

@MainActor
final class ConfigurationStore: ObservableObject {
    static let shared = ConfigurationStore()

    private let defaults = UserDefaults(suiteName: BooxConstants.appGroup)!

    @Published var deviceAddress: String {
        didSet { defaults.set(deviceAddress, forKey: "deviceAddress") }
    }
    @Published var setupCode: String {
        didSet { defaults.set(setupCode, forKey: "setupCode") }
    }

    private init() {
        deviceAddress = defaults.string(forKey: "deviceAddress") ?? ""
        setupCode = defaults.string(forKey: "setupCode") ?? ""
    }

    var pairedDevices: [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    func generateCode() {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        setupCode = String((0..<8).compactMap { _ in alphabet.randomElement() })
    }
}
