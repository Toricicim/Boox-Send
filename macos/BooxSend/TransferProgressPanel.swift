import AppKit
import SwiftUI

private final class TransferHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TransferProgressModel: ObservableObject {
    @Published var progress = TransferProgress()
}

/// A small non-activating HUD: sending never steals Finder's keyboard focus.
@MainActor
final class TransferProgressPanel {
    let model = TransferProgressModel()
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var dismissed = false
    var retry: (() -> Void)?

    func update(_ progress: TransferProgress) {
        if progress.isActive && !model.progress.isActive { dismissed = false }
        model.progress = progress
        guard progress.phase != .idle, !dismissed else { return }
        if panel == nil {
            let panel = TransferHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 126),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: TransferProgressView(model: model,
                retry: { [weak self] in self?.retry?() }, dismiss: { [weak self] in self?.hide() }))
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.maxX - 360, y: screen.maxY - 146))
            }
            self.panel = panel
        }
        dismissWorkItem?.cancel()
        panel?.orderFrontRegardless()
        if !progress.isActive {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (progress.phase == .done ? 5 : 20), execute: work)
        }
    }

    func show() {
        guard model.progress.phase != .idle else { return }
        dismissed = false
        update(model.progress)
    }

    private func hide() {
        dismissed = true
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
    }
}

struct TransferProgressView: View {
    @ObservedObject var model: TransferProgressModel
    var retry: () -> Void
    var dismiss: () -> Void
    private var state: TransferProgress { model.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: state.phase == .done ? "checkmark.circle.fill" : state.phase == .failed ? "exclamationmark.circle" : "arrow.up.doc")
                    .foregroundStyle(state.phase == .done ? Color.green : Color.primary)
                Text(state.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if state.phase == .sending || state.phase == .verifying || state.phase == .done {
                    Text("\(Int(state.fraction * 100))%").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide progress")
            }
            ProgressView(value: state.fraction).progressViewStyle(.linear).tint(state.phase == .done ? .green : .accentColor)
                .accessibilityLabel("Transfer progress")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.filename).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    Text(state.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if state.phase == .failed {
                    Button("Retry", action: retry).controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 340, height: 126, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
