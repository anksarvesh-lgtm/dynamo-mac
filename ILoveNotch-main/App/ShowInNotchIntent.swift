// SPDX-License-Identifier: MIT
import AppIntents
import AppKit
import NotchFeatures

/// The Show in Notch action in Shortcuts: a short message in the notch for a few seconds. It runs
/// in the background; ILoveNotch starts if it isn't running.
struct ShowInNotchIntent: AppIntent {
    static let title: LocalizedStringResource = "Show in Notch"
    static let description = IntentDescription(
        "Shows a short message in the notch for a few seconds, with an SF Symbol beside it.")

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Symbol", description: "The name of an SF Symbol, like bell.fill or hammer.fill.")
    var symbol: String?

    @Parameter(title: "Seconds", description: "From 1 to 30.", default: 4)
    var seconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$message) in the notch") {
            \.$symbol
            \.$seconds
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let activity = ShowInNotch.activity(title: message, symbol: symbol, seconds: Double(seconds)) {
            (NSApp.delegate as? AppDelegate)?.showInNotch(activity)
        }
        return .result()
    }
}
