import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private var panel: DropdownPanel!
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeading
        }

        panel = DropdownPanel(content: PopoverView(store: store))

        store.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        store.start()
        // Mantiene al día la cuenta atrás del reinicio en la barra entre peticiones.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let percent = store.sessionPercent
        button.image = UsageBarsIcon.make(session: percent, weekly: store.usage?.sevenDay?.utilization)
        let text = percent.map { "\(Int($0.rounded()))%" } ?? "–"
        button.attributedTitle = NSAttributedString(
            string: menuBarTitle(sessionPercent: percent, reset: store.usage?.fiveHour?.resetDate),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        switch MenuBarAlert(percent: percent) {
        case .critical: button.contentTintColor = .systemRed
        case .warning: button.contentTintColor = .systemOrange
        case .none: button.contentTintColor = nil
        }
        var tip = "Claude · sesión 5h: \(text)"
        if let reset = store.usage?.fiveHour?.resetDate { tip += " · reinicio \(formatResetTime(reset))" }
        if let weekly = store.usage?.sevenDay?.utilization { tip += "\nSemana: \(Int(weekly.rounded()))%" }
        if let error = store.error { tip += "\n\(error)" }
        button.toolTip = tip
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.close()
        } else {
            store.refreshIfStale()
            panel.show(below: button)
        }
    }
}

/// Desplegable propio en lugar de NSPopover: NSPopover lo colocaba parcialmente por encima
/// del borde superior de la pantalla al cambiar de tamaño. Aquí la posición se calcula a mano
/// y siempre queda dentro del área visible, justo debajo de la barra de menús.
@MainActor
final class DropdownPanel: NSPanel {
    private let hostingView: SizeTrackingHostingView<PopoverView>
    private weak var anchor: NSView?
    private var monitors: [Any] = []

    init(content: PopoverView) {
        hostingView = SizeTrackingHostingView(rootView: content)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background

        // El contenido crece al llegar los datos: se recoloca para seguir dentro de la pantalla.
        hostingView.onSizeChange = { [weak self] in
            DispatchQueue.main.async { if self?.isVisible == true { self?.reposition() } }
        }
    }

    override var canBecomeKey: Bool { true }

    func show(below anchor: NSView) {
        self.anchor = anchor
        reposition()
        makeKeyAndOrderFront(nil)

        // Cierra al hacer clic fuera o al pulsar Esc.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        } as Any)
    }

    override func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        super.close()
    }

    private func reposition() {
        guard let anchor, let anchorWindow = anchor.window,
              let screen = anchorWindow.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = hostingView.fittingSize
        let height = min(size.height, visible.height - 12)

        var x = anchorRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = visible.maxY - 6 - height
        setFrame(NSRect(x: x, y: y, width: size.width, height: height), display: true)
        invalidateShadow()
    }
}

final class SizeTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// Dos barras verticales finas que se llenan de abajo arriba: sesión de 5 h (izquierda)
/// y semana (derecha).
enum UsageBarsIcon {
    static func make(session: Double?, weekly: Double?) -> NSImage {
        let barWidth: CGFloat = 4, gap: CGFloat = 2.5, height: CGFloat = 14
        let size = NSSize(width: barWidth * 2 + gap + 1, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, percent) in [session, weekly].enumerated() {
                let track = NSRect(x: 0.5 + CGFloat(index) * (barWidth + gap), y: 0.5,
                                   width: barWidth, height: height - 1)
                let outline = NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5)
                outline.lineWidth = 1
                NSColor.black.withAlphaComponent(0.4).setStroke()
                outline.stroke()

                if let percent, percent > 0 {
                    let fillHeight = max(1.5, track.height * CGFloat(min(percent, 100) / 100))
                    NSColor.black.setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width, height: fillHeight),
                                 xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
