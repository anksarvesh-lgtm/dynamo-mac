//
//  LottieAnimationContainer.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 29..
//

import SwiftUI
import Defaults

struct LottieAnimationContainer: View {
    @Default(.selectedVisualizer) var selectedVisualizer

    private var defaultVisualizerURL: URL {
        if let bundleURL = Bundle.main.url(forResource: "default_wave_visualizer", withExtension: "json") {
            return bundleURL
        }
        let localPath = URL(fileURLWithPath: "liquiddinamo/Resources/default_wave_visualizer.json")
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }
        // Fallback for custom or legacy URL cache
        return URL(string: "https://assets9.lottiefiles.com/packages/lf20_mniampqn.json")!
    }

    var body: some View {
        if let selected = selectedVisualizer {
            LottieView(url: selected.url, speed: selected.speed, loopMode: .loop)
        } else {
            LottieView(url: defaultVisualizerURL, speed: 1.0, loopMode: .loop)
        }
    }
}

#if DEBUG
#Preview {
    LottieAnimationContainer()
}
#endif
