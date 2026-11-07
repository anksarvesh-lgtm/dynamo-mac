import IslandActivities
import IslandKit
import SwiftUI

/// The open island while an update is on offer: which version, what is new in it, and the button
/// that hands over to Sparkle's window.
///
/// Drawn in place of the activity's own body — `BuiltInActivity.updateAvailable` publishes an empty
/// `expanded` slot so `ActivityLayerView` stands down, the arrangement the shelf and the drop history
/// already use. The notes scroll the way Up Next's rows do: the shell feeds trackpad samples to
/// `UpdateAvailableModel.scroll(_:)` and this view follows `scrollTarget`, because the panel never
/// becomes key and a `ScrollView` left to its own devices would not see the wheel.
struct UpdateAvailableLayerView: View {

    let model: IslandScreenModel
    let update: UpdateAvailableModel

    @State private var scrollPosition = ScrollPosition(y: 0)

    var body: some View {
        GeometryReader { proxy in
            let metrics = model.contentMetrics
            let origin = IslandLayout.bodyOrigin(for: metrics, in: proxy.size)
            let width = max(0, metrics.bodySize.width - UpdateAvailableLayout.horizontalPadding * 2)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: UpdateAvailableLayout.headerHeight)
                    .padding(.bottom, UpdateAvailableLayout.headerSpacing)

                notes(width: width)

                installButton
                    .padding(.top, UpdateAvailableLayout.buttonSpacing)
            }
            .padding(.horizontal, UpdateAvailableLayout.horizontalPadding)
            .frame(
                width: metrics.bodySize.width,
                height: max(0, model.contentBodySize.height - model.cutoutSize.height),
                alignment: .topLeading
            )
            .padding(.top, UpdateAvailableLayout.topPadding)
            .offset(x: origin.x, y: origin.y + model.cutoutSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var primaryOpacity: Double { model.increaseContrast ? 1 : 0.9 }
    private var secondaryOpacity: Double { model.increaseContrast ? 1 : 0.55 }

    private var header: some View {
        HStack(spacing: 8) {
            headerIcon
                .accessibilityHidden(true)
            Text(islandText("update.header", "Isleta \(update.version ?? "") is available"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(primaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(islandText("update.whatsNew", "What’s New"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(secondaryOpacity))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Isleta's own icon, from the same store the flanks draw it from; the download glyph for the
    /// frame before it has been decoded.
    @ViewBuilder
    private var headerIcon: some View {
        let side: CGFloat = 18
        if let icon = ApplicationIconStore.shared.icon(named: applicationName) {
            Image(decorative: icon, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: side * ApplicationIconMetrics.canvasScale, height: side * ApplicationIconMetrics.canvasScale)
                .frame(width: side, height: side)
        } else {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(primaryOpacity))
        }
    }

    private var applicationName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Isleta"
    }

    @ViewBuilder
    private func notes(width: CGFloat) -> some View {
        let viewport = UpdateAvailableLayout.viewportHeight
        if update.notes.isEmpty {
            Text(islandText("update.noNotes", "This update has no release notes."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(secondaryOpacity))
                .frame(width: width, height: viewport, alignment: .topLeading)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: UpdateAvailableLayout.blockSpacing) {
                    ForEach(Array(update.notes.enumerated()), id: \.offset) { _, block in
                        row(block)
                    }
                }
                .frame(width: width - UpdateAvailableLayout.indicatorWidth * 4, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    update.notesHeight = height
                }
            }
            .scrollIndicators(.hidden)
            // The shell drives the offset — see the type's note.
            .scrollDisabled(true)
            .scrollPosition($scrollPosition)
            .frame(width: width, height: viewport, alignment: .topLeading)
            .onChange(of: update.scrollTarget, initial: true) { _, target in
                scrollPosition.scrollTo(y: target.offset)
            }
            .overlay(alignment: .topTrailing) {
                if let indicator = UpdateAvailableLayout.indicator(
                    offset: update.scrollOffset,
                    contentHeight: update.notesHeight
                ) {
                    Capsule()
                        .fill(.white.opacity(model.increaseContrast ? 0.6 : 0.25))
                        .frame(width: UpdateAvailableLayout.indicatorWidth, height: indicator.length)
                        .offset(y: indicator.top)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ block: UpdateNotesBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(secondaryOpacity))
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "•")
                    .accessibilityHidden(true)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(primaryOpacity))
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(primaryOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installButton: some View {
        Button { update.onInstall?() } label: {
            Text(islandText("update.install", "Install Update…"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: UpdateAvailableLayout.buttonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(.white.opacity(model.increaseContrast ? 1 : 0.92)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(islandText("update.install.a11y", "Install the update"))
        .help(islandText("update.install.help", """
            Closes the island and opens the update window, where you can install it and restart \
            Isleta.
            """))
    }
}
