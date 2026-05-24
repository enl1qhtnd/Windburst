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
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
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

    private static let menuBarHeight: CGFloat = 22
    private static let horizontalPadding: CGFloat = 8
    private static let contentSpacing: CGFloat = 6

    var body: some View {
        HStack(alignment: .center, spacing: Self.contentSpacing) {
            Image(systemName: "wind")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 18, height: 18, alignment: .center)

            Text(TemperatureFormatter.string(appState.monitor.primaryTemperature, unit: appState.settings.temperatureUnit))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.menuBarHeight, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
