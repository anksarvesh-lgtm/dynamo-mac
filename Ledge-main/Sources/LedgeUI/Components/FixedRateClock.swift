import SwiftUI

/// A cooperative drawing clock for small decorative animations.
///
/// `TimelineView`'s animation and periodic schedules both kept the entire
/// hosting view updating at display cadence on macOS 26, even when their
/// content interval was lower. This clock performs one state change per
/// requested frame, cancels with the view, and never catches up missed frames.
struct FixedRateClock<Content: View>: View {
    let isActive: Bool
    let interval: Duration
    @ViewBuilder var content: (Date) -> Content
    @State private var date = Date()

    var body: some View {
        content(date)
            .task(id: isActive) {
                guard isActive else { return }
                while !Task.isCancelled {
                    date = Date()
                    do { try await Task.sleep(for: interval) }
                    catch { return }
                }
            }
    }
}
