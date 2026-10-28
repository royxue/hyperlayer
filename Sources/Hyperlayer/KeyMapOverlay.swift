import AppKit
import SwiftUI

/// A floating cheat sheet of the navigation layer, centered on the active screen, with
/// switches for the optional keys. Closes on Esc, on clicking elsewhere, or when shown again.
final class KeyMapOverlay {
    private var panel: OverlayPanel?

    func toggle(settings: Settings) {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        show(settings: settings)
    }

    private func show(settings: Settings) {
        let host = NSHostingView(rootView: KeyMapView(settings: settings))
        host.setFrameSize(host.fittingSize)

        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize))
        panel.contentView = host
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - host.fittingSize.width / 2,
                                         y: visible.midY - host.fittingSize.height / 2))
        }
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }
}

private final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func resignKey() {
        super.resignKey()
        close()
    }
}

private struct KeyMapView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                Text("Navigation Layer").font(.system(size: 17, weight: .semibold))
                Switch(isOn: $settings.layerEnabled)
                Spacer()
                HStack(spacing: 4) {
                    Text("Hold").foregroundStyle(.secondary)
                    Keycap("⇪ Caps Lock")
                }
                .font(.system(size: 12))
            }

            if !settings.layerEnabled {
                Label("The layer is off, so these keys send Hyper instead.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .top, spacing: 28) {
                ForEach(NavigationLayer.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        ForEach(group.entries, id: \.keyCode) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .opacity(settings.layerEnabled ? 1 : 0.45)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Any other key").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Keycap("⌃⌥⇧⌘ + key")
                    Spacer()
                    Text("Hold ⇧ to select").foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    Text("Tap").foregroundStyle(.secondary)
                    Keycap("⇪")
                    Text("alone").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Keycap("Esc")
                    Spacer()
                    Switch(isOn: $settings.tapForEscape)
                }
            }
            .font(.system(size: 12))
        }
        .padding(24)
        .frame(width: 600)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(_ entry: NavigationLayer.Entry) -> some View {
        let isOn = entry.option.map(settings.isOn) ?? true
        HStack(spacing: 10) {
            Keycap(entry.key, minWidth: 16)
            Text(entry.description)
                .font(.system(size: 13))
                .foregroundStyle(isOn ? .primary : .tertiary)
            if let option = entry.option {
                Spacer(minLength: 12)
                Switch(isOn: Binding(get: { settings.isOn(option) }, set: { settings.set(option, on: $0) }))
                    .disabled(!settings.layerEnabled)
            }
        }
    }
}

private struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}

private struct Keycap: View {
    let label: String
    let minWidth: CGFloat?
    init(_ label: String, minWidth: CGFloat? = nil) {
        self.label = label
        self.minWidth = minWidth
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: minWidth)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}
