import Foundation

@MainActor
func runAll() async -> Int32 {
    registerActivityManagerTests()
    registerPresentationTests()
    registerDisplayTests()
    registerSettingsTests()
    registerFeatureTests()
    registerRegressionTests()
    registerAirPodsTests()
    return await TestKit.shared.run(filter: CommandLine.arguments.dropFirst().first)
}

let code = await runAll()
exit(code)
