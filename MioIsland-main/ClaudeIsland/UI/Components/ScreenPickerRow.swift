//
//  ScreenPickerRow.swift
//  ClaudeIsland
//
//  Screen selection picker for settings menu
//

import SwiftUI

private func screenPickerTheme() -> ThemeResolver {
    ThemeResolver(theme: NotchCustomizationStore.shared.customization.theme)
}

struct ScreenPickerRow: View {
    @ObservedObject var screenSelector: ScreenSelector
    @State private var isHovered = false
    private var theme: ThemeResolver { screenPickerTheme() }

    private var isExpanded: Bool {
        get { screenSelector.isPickerExpanded }
    }

    private func setExpanded(_ value: Bool) {
        screenSelector.isPickerExpanded = value
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - shows current selection
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    setExpanded(!isExpanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text(L10n.screen)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(currentSelectionLabel)
                        .font(.system(size: 11))
                        .foregroundColor(theme.mutedText)
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(theme.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? theme.overlay.opacity(0.22) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded screen list
            if isExpanded {
                VStack(spacing: 2) {
                    // Automatic option
                    ScreenOptionRow(
                        label: L10n.automatic,
                        sublabel: L10n.builtInOrMain,
                        isSelected: screenSelector.selectionMode == .automatic
                    ) {
                        screenSelector.selectAutomatic()
                        triggerWindowRecreation()
                        collapseAfterDelay()
                    }

                    // Individual screens
                    ForEach(screenSelector.availableScreens, id: \.self) { screen in
                        ScreenOptionRow(
                            label: screen.localizedName,
                            sublabel: screenSublabel(for: screen),
                            isSelected: screenSelector.selectionMode == .specificScreen &&
                                       screenSelector.isSelected(screen)
                        ) {
                            screenSelector.selectScreen(screen)
                            triggerWindowRecreation()
                            collapseAfterDelay()
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }

    private var currentSelectionLabel: String {
        switch screenSelector.selectionMode {
        case .automatic:
            return L10n.auto_
        case .specificScreen:
            if let screen = screenSelector.selectedScreen {
                return screen.localizedName
            }
            return L10n.auto_
        }
    }

    private var textColor: Color {
        isHovered ? theme.primaryText : theme.secondaryText
    }

    private func screenSublabel(for screen: NSScreen) -> String? {
        var parts: [String] = []
        if screen.isBuiltinDisplay {
            parts.append(L10n.builtIn)
        }
        if screen == NSScreen.main {
            parts.append(L10n.main_)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func triggerWindowRecreation() {
        // Notify to recreate the window
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func collapseAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                setExpanded(false)
            }
        }
    }
}

// MARK: - Screen Option Row

private struct ScreenOptionRow: View {
    let label: String
    let sublabel: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    private var theme: ThemeResolver { screenPickerTheme() }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? theme.doneColor : theme.border)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isHovered ? theme.primaryText : theme.secondaryText)

                    if let sublabel = sublabel {
                        Text(sublabel)
                            .font(.system(size: 10))
                            .foregroundColor(theme.mutedText)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(theme.doneColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? theme.overlay.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
