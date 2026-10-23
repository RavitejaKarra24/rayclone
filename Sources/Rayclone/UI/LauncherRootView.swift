import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

struct LauncherRootView: View {
    @ObservedObject var controller: LauncherController
    @ObservedObject private var settings = AppSettings.shared
    @FocusState private var searchFocused: Bool

    private var theme: Theme { settings.activeTheme }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            list
            separator
            footer
        }
        .id(controller.presentationCount)
        .background(
            ZStack {
                VisualEffectView(material: theme.isDark ? .hudWindow : .popover)
                theme.background.opacity(theme.isDark ? 0.94 : 0.9)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Metric.radiusWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.radiusWindow, style: .continuous)
                .strokeBorder(theme.borderSecondary, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if controller.actionsVisible, let item = controller.selectedItem {
                ActionPanelView(
                    item: item,
                    theme: theme,
                    selection: controller.actionSelection,
                    onSelect: { index in
                        controller.actionSelection = index
                    },
                    onPerform: { index in
                        if item.actions.indices.contains(index) {
                            controller.perform(item: item, action: item.actions[index])
                        }
                    }
                )
                .padding(.trailing, Metric.space8)
                .padding(.bottom, Metric.footerHeight + Metric.space8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .shadow(color: .black.opacity(theme.isDark ? 0.55 : 0.25), radius: 32, x: 0, y: 14)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidShow)) { _ in
            DispatchQueue.main.async { searchFocused = true }
        }
        .animation(.easeOut(duration: 0.12), value: controller.actionsVisible)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Metric.space8) {
            if controller.mode != .root {
                modeChip
            }

            Image(systemName: controller.mode == .root ? "magnifyingglass" : controller.mode.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 22)

            ZStack(alignment: .leading) {
                TextField("", text: Binding(
                    get: { controller.query },
                    set: { controller.query = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.foreground)
                .focused($searchFocused)
                .onSubmit { controller.performSelected() }

                if controller.query.isEmpty {
                    Text(controller.mode.placeholder)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(theme.textTertiary)
                        .allowsHitTesting(false)
                }
            }

            Spacer(minLength: 0)

            if !controller.query.isEmpty {
                Button {
                    controller.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.space16)
        .frame(height: Metric.headerHeight)
    }

    private var modeChip: some View {
        HStack(spacing: Metric.space4) {
            Image(systemName: controller.mode.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(controller.mode.title)
                .font(.system(size: Metric.fontSize11, weight: .medium))
            Button {
                controller.resetToRoot()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, Metric.space8)
        .padding(.vertical, Metric.space4)
        .background(theme.fg(10), in: Capsule())
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.borderSeparator)
            .frame(height: 1)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if controller.results.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, item in
                            if showsHeader(at: index) {
                                sectionHeader(item.section)
                            }
                            ResultRow(
                                item: item,
                                theme: theme,
                                isSelected: index == controller.selection
                            )
                            .id(item.id)
                            .onTapGesture {
                                controller.selection = index
                                controller.performSelected()
                            }
                        }
                    }
                }
                .padding(.vertical, Metric.space6)
                .padding(.horizontal, Metric.space8)
            }
            .onChange(of: controller.selection) { _, _ in
                if let item = controller.selectedItem {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func showsHeader(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return controller.results[index - 1].section != controller.results[index].section
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: Metric.fontSize11, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, Metric.space8)
        .padding(.top, Metric.space8)
        .padding(.bottom, Metric.space4)
    }

    private var emptyState: some View {
        VStack(spacing: Metric.space8) {
            Image(systemName: controller.query.isEmpty ? controller.mode.symbol : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text(controller.query.isEmpty ? "Nothing here yet" : "No results for “\(controller.query)”")
                .font(.system(size: Metric.fontSize13))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.space32)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Metric.space12) {
            HStack(spacing: Metric.space6) {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("Rayclone")
                    .font(.system(size: Metric.fontSize11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }

            if !PasteService.canPaste {
                HStack(spacing: Metric.space4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("Accessibility off")
                        .font(.system(size: Metric.fontSize11))
                }
                .foregroundStyle(theme.orange)
                .onTapGesture { WindowManager.requestAccess() }
            }

            Spacer()

            footerHint(key: "⏎", label: "Action")
            footerHint(key: "⌘K", label: "Actions")
            footerHint(key: "⎋", label: "Close")
        }
        .padding(.horizontal, Metric.space12)
        .frame(height: Metric.footerHeight)
        .background(theme.actionBarSurface.opacity(0.4))
    }

    private func footerHint(key: String, label: String) -> some View {
        HStack(spacing: Metric.space4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, Metric.space4)
                .padding(.vertical, 1)
                .background(theme.fg(10), in: RoundedRectangle(cornerRadius: Metric.radius4))
            Text(label)
                .font(.system(size: Metric.fontSize11))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

// MARK: - Row

struct ResultRow: View {
    let item: SearchItem
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Metric.space8) {
            ItemIconView(icon: item.icon, theme: theme)
                .frame(width: Metric.icon22, height: Metric.icon22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: Metric.fontSize13, weight: .regular))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: Metric.fontSize11))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Metric.space8)

            if let accessory = item.accessory {
                Text(accessory)
                    .font(.system(size: Metric.fontSize11))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, Metric.space6)
                    .padding(.vertical, 1)
                    .background(theme.fg(10), in: RoundedRectangle(cornerRadius: Metric.radius4))
            }

            if isSelected, let action = item.primaryAction {
                HStack(spacing: Metric.space4) {
                    Text(action.title)
                        .font(.system(size: Metric.fontSize11))
                        .foregroundStyle(theme.textSecondary)
                    Text("⏎")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 3)
                        .background(theme.fg(10), in: RoundedRectangle(cornerRadius: 3))
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Metric.space8)
        .frame(height: Metric.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metric.radius8, style: .continuous)
                .fill(isSelected ? theme.rowSelection : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct ItemIconView: View {
    let icon: ItemIcon
    let theme: Theme

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.foreground.opacity(0.85))
        case .app(let url), .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: Metric.radius4))
        case .emoji(let symbol):
            Text(symbol)
                .font(.system(size: 18))
        case .monogram(let text, let color):
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Metric.icon22, height: Metric.icon22)
                .background(color, in: RoundedRectangle(cornerRadius: Metric.radius6))
        }
    }
}

// MARK: - Action panel

struct ActionPanelView: View {
    let item: SearchItem
    let theme: Theme
    let selection: Int
    let onSelect: (Int) -> Void
    let onPerform: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metric.space6) {
                ItemIconView(icon: item.icon, theme: theme)
                    .frame(width: 16, height: 16)
                Text(item.title)
                    .font(.system(size: Metric.fontSize11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Metric.space8)
            .padding(.vertical, Metric.space6)

            Rectangle().fill(theme.borderSeparator).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(item.actions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        onSelect(index)
                        onPerform(index)
                    } label: {
                        HStack(spacing: Metric.space8) {
                            Image(systemName: action.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(action.style == .destructive ? theme.red : theme.textSecondary)
                                .frame(width: 14)
                            Text(action.title)
                                .font(.system(size: Metric.fontSize13))
                                .foregroundStyle(action.style == .destructive ? theme.red : theme.foreground)
                            Spacer(minLength: Metric.space8)
                            if let shortcut = action.shortcut {
                                Text(shortcut)
                                    .font(.system(size: Metric.fontSize11, design: .rounded))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, Metric.space8)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Metric.radius6)
                                .fill(index == selection ? theme.rowSelection : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { onSelect(index) }
                    }
                }
            }
            .padding(Metric.space4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 260)
        .background(
            ZStack {
                VisualEffectView(material: .popover)
                theme.background.opacity(theme.isDark ? 0.94 : 0.94)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Metric.radius12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.radius12, style: .continuous)
                .strokeBorder(theme.borderSecondary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
