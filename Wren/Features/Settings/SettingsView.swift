import SwiftUI

/// Light, dark, or follow the system. Stored as a raw string so the setting
/// survives renames of the cases' order.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "don't override", which is how SwiftUI spells "system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The few things the user chooses rather than records. Diagnostics lives
/// behind it so the gear on Today has one destination.
@MainActor
struct SettingsView: View {
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(WrenTheme.storageKey) private var themeRaw = WrenTheme.lime.rawValue

    @Environment(\.wrenTheme) private var theme

    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    WrenSectionLabel(text: "Appearance")
                    appearancePicker
                    Text("Auto follows the phone's setting.")
                        .font(.caption)
                        .foregroundStyle(Color.wren.textSecondary)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    WrenSectionLabel(text: "Accent")
                    themePicker
                    Text("Used for anything you can press, whatever is selected, and the one figure a screen is about. Paper, ink and the overdue red don't change.")
                        .font(.caption)
                        .foregroundStyle(Color.wren.textSecondary)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    WrenSectionLabel(text: "Under the hood")
                    NavigationLink { DiagnosticsView() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Diagnostics")
                                    .font(WrenFont.heading)
                                    .foregroundStyle(Color.wren.textPrimary)
                                Text("Log, reminders, storage, build")
                                    .font(WrenFont.detail)
                                    .foregroundStyle(Color.wren.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.wren.textPrimary)
                        }
                        .padding(Space.m)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .wrenBox()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.wren.background)
        .navigationTitle("Settings")
    }

    /// Swatches rather than names: the colour is the thing being chosen, so
    /// the chip shows it. The selected one lifts onto its shadow, the same way
    /// every other pressable thing in the app does.
    private var themePicker: some View {
        HStack(spacing: Space.s) {
            ForEach(WrenTheme.allCases) { option in
                let isSelected = option == theme
                Button {
                    withAnimation(.snappy(duration: 0.15)) { themeRaw = option.rawValue }
                } label: {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(option.highlight)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                        )
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundStyle(option.onHighlight)
                            }
                        }
                        .wrenHardShadow(radius: Radius.chip, isLifted: isSelected)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    /// A segmented control in the house style: one box, hairlines between
    /// the options, the chosen one filled lime.
    private var appearancePicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(Appearance.allCases.enumerated()), id: \.element.id) { index, option in
                let isSelected = option == appearance
                Button {
                    withAnimation(.snappy(duration: 0.15)) { appearanceRaw = option.rawValue }
                } label: {
                    Text(option.label)
                        .font(WrenFont.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? theme.onHighlight : Color.wren.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? theme.highlight : Color.wren.surface)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if index < Appearance.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.wren.textPrimary)
                        .frame(width: Stroke.border)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .wrenBox()
    }
}
