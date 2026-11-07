// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchUsage

struct UsageBundleTests {
    @Test func thePricingSnapshotsShipWithTheModule() {
        for name in ["pricing_litellm_snapshot", "pricing_models_dev_snapshot", "pricing_supplement"] {
            #expect(Bundle.openUsageResources.url(forResource: name, withExtension: "json") != nil, "\(name)")
        }
    }
}
