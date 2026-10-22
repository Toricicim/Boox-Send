import Foundation

struct TransferProgress: Equatable {
    enum Phase: String { case idle, connecting, preparing, sending, verifying, retrying, done, failed }
    var phase: Phase = .idle
    var filename = ""
    var sentBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var fileIndex = 0
    var fileCount = 0
    var remainingFiles = 0
    var failedFiles = 0
    var detail = ""

    var fraction: Double {
        if phase == .done { return 1 }
        guard totalBytes > 0 else { return 0 }
        // Bytes handed to Bluetooth are not a successful receiver commit.
        return min(0.99, Double(sentBytes) / Double(totalBytes))
    }
    var isActive: Bool { [.connecting, .preparing, .sending, .verifying, .retrying].contains(phase) }
    var title: String {
        switch phase {
        case .idle: return "Ready"
        case .connecting: return "Connecting to BOOX…"
        case .preparing: return "Preparing…"
        case .sending: return "Sending to BOOX"
        case .verifying: return "Verifying on BOOX…"
        case .retrying: return "Reconnecting…"
        case .done: return "Done"
        case .failed: return "Needs attention"
        }
    }
}
