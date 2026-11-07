// SPDX-License-Identifier: MIT
import SwiftUI

extension UsageFeature {
    /// AI Usage's settings, as sections of its Settings page: which providers are on, API keys, and
    /// background refresh.
    public var settingsView: some View { UsageSettings(usage: self) }
}

private struct UsageSettings: View {
    @Bindable var usage: UsageFeature

    var body: some View {
        Group {
            Section {
                ForEach(usage.providers) { provider in
                    // A closure, not a method reference: see the app's GeneralSettings.
                    Toggle(
                        isOn: Binding(
                            get: { usage.isEnabled(provider.id) }, set: { usage.setEnabled(provider.id, $0) })
                    ) {
                        HStack(spacing: 6) {
                            ProviderLogo(providerID: provider.id, name: provider.name, size: 14)
                            Text(provider.name)
                            if usage.detected.contains(provider.id) {
                                Text("Signed in on this Mac").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text(
                    "Each provider reads only the sign-in its own tool keeps on this Mac and sends it only to its "
                        + "own service."
                )
                .foregroundStyle(.secondary)
            }
            // On one section only: a modifier on the group would go on each section, and detect three times.
            .task { await usage.detect() }
            Section {
                ForEach(usage.providers.filter { usage.takesAPIKey($0.id) }) { provider in
                    APIKeyRow(usage: usage, provider: provider)
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("These have no sign-in on this Mac to reuse. A key saved here is kept in your keychain.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Refresh in the background", selection: $usage.backgroundRefresh) {
                    ForEach(UsageFeature.BackgroundRefresh.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(
                    "Spend estimates use public price lists from LiteLLM, models.dev, and OpenUsage. Usage code "
                        + "adapted from OpenUsage; provider logos from theSVG."
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A provider's API key: where the one in use comes from, and a field to save one to the keychain.
private struct APIKeyRow: View {
    let usage: UsageFeature
    let provider: UsageProvider

    @State private var draft = ""
    @State private var source = UsageFeature.KeySource.none
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProviderLogo(providerID: provider.id, name: provider.name, size: 14)
                Text(provider.name)
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                SecureField(
                    "\(provider.name) API key", text: $draft,
                    prompt: Text(source == .none ? "Paste your API key" : "Paste a new key to replace it")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
                Button("Save", action: save).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if source == .keychain {
                    Button("Remove", role: .destructive) {
                        usage.removeAPIKey(for: provider.id)
                        source = usage.keySource(provider.id)
                    }
                }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { source = usage.keySource(provider.id) }
    }

    private var status: String {
        switch source {
        case .keychain: "Saved in your keychain"
        case .shell: "From your shell (\(UsageFeature.apiKeyNames[provider.id] ?? ""))"
        case .configFile: "From a config file"
        case .none: "Not set"
        }
    }

    private func save() {
        do {
            try usage.saveAPIKey(draft, for: provider.id)
            draft = ""
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        source = usage.keySource(provider.id)
    }
}
