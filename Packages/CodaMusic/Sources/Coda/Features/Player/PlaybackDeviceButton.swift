import AVKit
import Combine
#if os(iOS)
import MediaPlayer
#endif
import SwiftUI

#if os(iOS)
/// The device label follows the audio session's actual output, including AirPods
/// and AirPlay. The picker covers the full label's tap area.
struct CurrentPlaybackDeviceButton: View {
    var showsName = true
    var tint: Color = .white.opacity(0.85)
    @State private var deviceName = ""
    @State private var deviceSymbol = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    #if targetEnvironment(simulator)
    @State private var showsSimulatorRouteNotice = false
    #endif

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: deviceSymbol)
                .frame(width: 24)
                .font(.system(size: 19, weight: .medium))
                // Balance visible gaps beside the wider transport glyphs.
                .offset(x: showsName ? 0 : 4)
            if showsName {
                Text(deviceName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, showsName ? 8 : 0)
        .frame(minWidth: 44, maxWidth: showsName ? nil : 44, minHeight: 44)
        .accessibilityHidden(true)
        .overlay {
            #if targetEnvironment(simulator)
            // The simulator exposes MPMediaControls, but its remote route UI
            // can fail to launch and never invoke the dismissal handler.
            Button {
                showsSimulatorRouteNotice = true
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("隔空播放，当前设备：\(deviceName)")
            .accessibilityIdentifier("iPadAirPlayButton")
            .alert("播放设备", isPresented: $showsSimulatorRouteNotice) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前为 iOS 模拟器，声音通过 Mac 输出。请在 Mac 的声音设置中切换输出设备；AirPlay 和蓝牙设备选择需在 iPhone 或 iPad 真机上使用。")
            }
            #else
            AnchoredAirPlayPicker(accessibilityName: "隔空播放，当前设备：\(deviceName)")
            #endif
        }
        .onAppear(perform: updateDeviceName)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            updateDeviceName()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            updateDeviceName()
        }
    }

    private func updateDeviceName() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        var seen = Set<String>()
        let names = outputs.map { output in
            output.portType == .builtInSpeaker || output.portType == .builtInReceiver
                ? UIDevice.current.model : output.portName
        }.filter { !$0.isEmpty && seen.insert($0).inserted }
        deviceName = names.isEmpty ? UIDevice.current.model : names.joined(separator: "、")
        deviceSymbol = outputs.first.map(Self.symbol(for:))
            ?? (UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
    }

    private static func symbol(for output: AVAudioSessionPortDescription) -> String {
        let name = output.portName.lowercased().filter { !$0.isWhitespace && $0 != "-" }
        switch output.portType {
        case .builtInSpeaker, .builtInReceiver:
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            if name.contains("airpodsmax") { return "airpodsmax" }
            if name.contains("airpodspro") { return "airpodspro" }
            if name.contains("airpods") { return "airpods" }
            return "headphones"
        case .headphones:
            return "headphones"
        case .airPlay:
            if name.contains("homepodmini") { return "homepodmini" }
            if name.contains("homepod") { return "homepod" }
            if name.contains("appletv") { return "appletv" }
            if name.contains("macbook") { return "laptopcomputer" }
            if name.contains("mac") { return "desktopcomputer" }
            return "hifispeaker"
        case .HDMI, .displayPort:
            return "display"
        default:
            return "hifispeaker"
        }
    }
}

/// The iPad Music-style presentation uses a private MediaPlayer entry point.
/// Keep it isolated and capability-checked; the public picker remains available
/// when that entry point is absent. This path is not App Store safe.
private struct AnchoredAirPlayPicker: UIViewRepresentable {
    let accessibilityName: String

    final class PickerView: UIView {
        let button = UIButton(type: .custom)
        let anchor = UIView()
        let fallback = AVRoutePickerView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            overrideUserInterfaceStyle = .dark
            anchor.isUserInteractionEnabled = false
            fallback.tintColor = .clear
            fallback.activeTintColor = .clear
            fallback.prioritizesVideoDevices = false
            fallback.isUserInteractionEnabled = false
            fallback.accessibilityElementsHidden = true
            addSubview(fallback)
            addSubview(anchor)
            addSubview(button)
            button.accessibilityIdentifier = "iPadAirPlayButton"
            button.accessibilityValue = "已收起"
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            fallback.frame = bounds
            button.frame = bounds
            // Point at the icon rather than the centre of the device-name label.
            anchor.frame = CGRect(x: 0, y: 0, width: min(44, bounds.width), height: bounds.height)
        }
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        private var controls: NSObject?
        weak var picker: PickerView?

        @objc func showPicker(_ sender: UIButton) {
            guard controls == nil, let picker, picker.window != nil else { return }
            // Embedded music must not invoke the original app's private iPad presenter.
            // Keep the public system route picker and the upstream UI button intact.
            if CodaIdentity.isEmbeddedHost {
                showFallback(in: picker)
                return
            }
            guard let controlsType = NSClassFromString("MPMediaControls") as? NSObject.Type else {
                showFallback(in: picker)
                return
            }
            let controls = controlsType.init()
            let selectors = ["setSourceView:", "setPreferredWidth:", "setDismissHandler:", "present", "dismiss"]
            guard selectors.allSatisfy({ controls.responds(to: NSSelectorFromString($0)) }) else {
                showFallback(in: picker)
                return
            }
            picker.layoutIfNeeded()
            controls.setValue(picker.anchor, forKey: "sourceView")
            controls.setValue(294.0, forKey: "preferredWidth")
            let dismiss: @convention(block) () -> Void = { [weak self] in
                DispatchQueue.main.async {
                    self?.controls = nil
                    self?.picker?.button.accessibilityValue = "已收起"
                }
            }
            controls.setValue(dismiss, forKey: "dismissHandler")
            self.controls = controls
            controls.perform(NSSelectorFromString("present"))
            picker.button.accessibilityValue = "已展开"
        }

        private func showFallback(in picker: PickerView) {
            picker.fallback.subviews.compactMap { $0 as? UIButton }.first?
                .sendActions(for: .touchUpInside)
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            picker?.button.accessibilityValue = "已展开"
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            picker?.button.accessibilityValue = "已收起"
        }

        func dismiss() {
            controls?.perform(NSSelectorFromString("dismiss"))
            controls = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PickerView {
        let view = PickerView()
        context.coordinator.picker = view
        view.fallback.delegate = context.coordinator
        view.button.addTarget(context.coordinator, action: #selector(Coordinator.showPicker(_:)), for: .touchUpInside)
        return view
    }
    func updateUIView(_ view: PickerView, context: Context) {
        view.button.accessibilityLabel = accessibilityName
    }
    static func dismantleUIView(_ view: PickerView, coordinator: Coordinator) {
        coordinator.dismiss()
    }
}

#elseif os(macOS)
import AppKit

/// The popover body. Hover and the arrow keys share one highlight, the way a
/// native menu does; Return / Space picks the highlighted row, Esc closes
/// (the popover's own behaviour), and any pick closes it.
private struct OutputDevicePanel: View {
    @ObservedObject var controller: AudioOutputController
    let dismiss: () -> Void

    /// Keyboard highlight only. Hover lives inside each row (see `PanelRow`),
    /// so moving the mouse across the list invalidates one row rather than
    /// the whole panel.
    @State private var highlighted: Row?
    /// Grouped once per device-list change instead of once per body pass:
    /// `sections` dedupes, sorts and runs four filters.
    @State private var sections: [AudioOutputSection] = []
    /// Which row the mouse is over, for the arrow keys to start from. A plain
    /// reference on purpose — writing it must not invalidate anything.
    @State private var hovered = HoveredRow()
    @FocusState private var focused: Bool

    enum Row: Hashable {
        case systemDefault
        case device(uid: String)
        case soundSettings
    }

    final class HoveredRow {
        var row: Row?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("输出设备")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            deviceRow(
                .systemDefault,
                title: Text("系统默认"),
                subtitle: controller.systemDefaultName.map { Text(verbatim: $0) }
                    ?? Text("跟随系统设置"),
                symbol: "speaker.wave.2",
                isSelected: controller.selection == .systemDefault)

            ForEach(sections, id: \.group) { section in
                sectionHeader(section.group)
                ForEach(section.devices) { device in
                    deviceRow(
                        .device(uid: device.uid),
                        title: Text(verbatim: device.name),
                        subtitle: device.kind.transportLabel,
                        symbol: device.symbolName,
                        isSelected: controller.selection == .device(uid: device.uid))
                }
                if section.group == .airPlay, section.devices.isEmpty {
                    Text("AirPlay 音箱需先在控制中心或“声音”设置中选择一次，才会出现在这里")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
            }

            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

            settingsRow
        }
        .padding(.bottom, 6)
        .frame(width: 290)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) { move(by: 1, in: sections); return .handled }
        .onKeyPress(.upArrow) { move(by: -1, in: sections); return .handled }
        .onKeyPress(.return) { activateHighlighted() }
        .onKeyPress(.space) { activateHighlighted() }
        .onReceive(controller.$devices) { sections = AudioOutputDevices.sections($0) }
        .onAppear {
            sections = AudioOutputDevices.sections(controller.devices)
            controller.refresh()
            focused = true
        }
    }

    // MARK: Rows

    private func sectionHeader(_ group: AudioOutputGroup) -> some View {
        Text(group.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func deviceRow(
        _ row: Row, title: Text, subtitle: Text?, symbol: String, isSelected: Bool
    ) -> some View {
        PanelRow(isHighlighted: highlighted == row,
                 onHover: { hover(row, $0) },
                 action: { pick(row) }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(Theme.accent)
                                         : AnyShapeStyle(Color.primary.opacity(0.1)))
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                                    : AnyShapeStyle(.primary))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if let subtitle {
                        subtitle
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var settingsRow: some View {
        PanelRow(isHighlighted: highlighted == .soundSettings,
                 onHover: { hover(.soundSettings, $0) },
                 action: { pick(.soundSettings) }) {
            HStack {
                Text("声音设置…")
                    .font(.system(size: 13))
                Spacer()
            }
        }
        .accessibilityHint("打开系统设置中的“声音”")
    }

    // MARK: Interaction

    /// The mouse taking over clears the keyboard highlight, so exactly one row
    /// is ever lit — but only when there *is* one to clear, which keeps an
    /// ordinary mouse move free of any panel-level state write.
    private func hover(_ row: Row, _ inside: Bool) {
        if inside {
            hovered.row = row
            if highlighted != nil { highlighted = nil }
        } else if hovered.row == row {
            hovered.row = nil
        }
    }

    private func rows(in sections: [AudioOutputSection]) -> [Row] {
        [.systemDefault]
            + sections.flatMap { $0.devices.map { Row.device(uid: $0.uid) } }
            + [.soundSettings]
    }

    /// The first arrow press starts from the checked row, as a native menu
    /// opened on its current value would.
    private func move(by step: Int, in sections: [AudioOutputSection]) {
        let all = rows(in: sections)
        let current = highlighted ?? hovered.row
        let anchor: Row = current ?? {
            switch controller.selection {
            case .systemDefault: return .systemDefault
            case .device(let uid): return .device(uid: uid)
            }
        }()
        guard let index = all.firstIndex(of: anchor) else {
            highlighted = all.first
            return
        }
        if current == nil {
            highlighted = anchor
            return
        }
        highlighted = all[min(max(index + step, 0), all.count - 1)]
    }

    private func activateHighlighted() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        pick(highlighted)
        return .handled
    }

    private func pick(_ row: Row) {
        dismiss()
        switch row {
        case .systemDefault:
            select(.systemDefault)
        case .device(let uid):
            select(.device(uid: uid))
        case .soundSettings:
            SoundSettings.open()
        }
    }

    /// Re-picking the current row is a no-op here: `select` always re-points
    /// the engine, which is an audible rebuild for nothing.
    private func select(_ selection: AudioOutputSelection) {
        guard selection != controller.selection else { return }
        controller.select(selection)
    }
}

/// One row of the panel, owning its own hover state.
///
/// The hover highlight used to live on the panel, so a mouse move across the
/// list re-evaluated every row's body — including the grouping pass and each
/// row's `AnyShapeStyle`s. Here it invalidates this row and nothing else.
private struct PanelRow<Content: View>: View {
    let isHighlighted: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Color.primary.opacity(isHovered || isHighlighted ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { inside in
            isHovered = inside
            onHover(inside)
        }
    }
}

private extension AudioOutputGroup {
    var title: LocalizedStringKey {
        switch self {
        case .thisMac: return "此 Mac"
        case .external: return "外接设备"
        case .virtual: return "虚拟设备"
        case .airPlay: return "AirPlay"
        }
    }
}

private extension AudioOutputKind {
    /// The picker's secondary line — the "类型" column of System Settings ›
    /// Sound, for the sections whose header does not already say it.
    var transportLabel: Text? {
        switch self {
        case .bluetooth: return Text("蓝牙")
        case .usb: return Text(verbatim: "USB")
        case .hdmi: return Text(verbatim: "HDMI")
        case .displayPort: return Text(verbatim: "DisplayPort")
        case .thunderbolt: return Text(verbatim: "Thunderbolt")
        case .virtual: return Text("虚拟")
        case .aggregate: return Text("聚合")
        case .builtInSpeakers, .builtInHeadphones, .airPlay, .other: return nil
        }
    }
}

/// System Settings › Sound. The extension ID is what the Sound pane
/// registers on macOS 13+ (`/System/Library/ExtensionKit/Extensions/
/// Sound.appex`, `CFBundleIdentifier` = `com.apple.Sound-Settings.extension`);
/// the legacy prefPane ID is kept as a fallback, then System Settings itself.
@MainActor
enum SoundSettings {
    static let urls = [
        "x-apple.systempreferences:com.apple.Sound-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.sound",
    ]

    static func open() {
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        if let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }
}
#endif

#if os(macOS)
/// Same device-and-name utility row as iPad, backed by the Mac audio engine.
struct CurrentPlaybackDeviceButton: View {
    var showsName = true
    var tint: Color = .white.opacity(0.85)
    @ObservedObject private var controller = AudioOutputController.shared
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: controller.isRoutedAway ? "hifispeaker" : "laptopcomputer")
                    .frame(width: 24)
                    .font(.system(size: 19, weight: .medium))
                    .offset(x: showsName ? 0 : 4)
                if showsName {
                    Text(controller.currentDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, showsName ? 8 : 0)
            .frame(minWidth: 44, maxWidth: showsName ? nil : 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            OutputDevicePanel(controller: controller) { isPresented = false }
        }
        .accessibilityLabel("输出设备")
        .accessibilityValue(controller.currentDisplayName)
    }
}
#endif
