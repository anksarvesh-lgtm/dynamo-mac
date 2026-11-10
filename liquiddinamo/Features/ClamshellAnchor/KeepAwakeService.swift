//
//  KeepAwakeService.swift
//  LiquidDynamo
//
//  Cleanroom adapter bridging legacy KeepAwakeService calls to KeepAwakeManager.
//

import Combine
import Foundation

@MainActor
public final class KeepAwakeService: ObservableObject {
    public static let shared = KeepAwakeService()

    @Published public private(set) var isKeepAwakeActive: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Forward published state from KeepAwakeManager
        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isKeepAwakeActive = active
            }
            .store(in: &cancellables)
    }

    public func toggleKeepAwake() {
        KeepAwakeManager.shared.toggle()
    }

    public func enableKeepAwake() {
        guard !KeepAwakeManager.shared.isActive else { return }
        KeepAwakeManager.shared.start(
            mode: KeepAwakeManager.shared.mode,
            duration: .preset(.h1)
        )
    }

    public func disableKeepAwake() {
        KeepAwakeManager.shared.stop()
    }
}
