//
//  main.swift
//  KeepAwakeTests Runner
//

import Foundation

@main
struct TestRunner {
    static func main() {
        Task { @MainActor in
            KeepAwakeManagerTests.runAll()
            exit(0)
        }
        RunLoop.main.run()
    }
}
