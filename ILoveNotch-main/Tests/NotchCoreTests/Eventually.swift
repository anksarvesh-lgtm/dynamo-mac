// SPDX-License-Identifier: MIT

/// Waits until `condition` holds, checking every 20 ms, for at most `timeout`. Timing tests use it
/// instead of fixed sleeps, which flake on busy CI runners where tests share the main actor.
@MainActor
func eventually(within timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}
