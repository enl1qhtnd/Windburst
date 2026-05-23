import AppKit
import SwiftUI
import WindburstShared

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configurePopover()
        configureStatusItem()
    }

    func update(appState: AppState) {
        self.appState = appState
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 520)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let hostingView = NSHostingView(rootView: StatusBarView(appState: appState) { [weak self] in
            self?.togglePopoverFromView()
        })
        hostingView.frame.size = NSSize(width: 100, height: 22)
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        popover.contentViewController = NSHostingController(
            rootView: PopoverView(appState: appState) { [weak self] in
                self?.closePopover()
            }
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func togglePopoverFromView() {
        togglePopover(statusItem.button)
    }

    func closePopover() {
        popover.performClose(nil)
    }
}

struct StatusBarView: View {
    @ObservedObject var appState: AppState
    var onTap: () -> Void

    private let iconGraphWidth: CGFloat = 36

    private static let windIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Windburst")
        image?.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if appState.settings.showCPUSparkline {
                    SparklineView(
                        samples: appState.monitor.cpuHistory,
                        lineColor: .secondary,
                        height: 12
                    )
                }

                if let windIcon = Self.windIcon {
                    Image(nsImage: windIcon)
                }
            }
            .frame(width: iconGraphWidth, height: 14)

            Text(TemperatureFormatter.string(appState.monitor.primaryTemperature, unit: appState.settings.temperatureUnit))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
