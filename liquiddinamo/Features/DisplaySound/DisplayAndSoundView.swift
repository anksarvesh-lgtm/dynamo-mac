//
//  DisplayAndSoundView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import SwiftUI

struct DisplayAndSoundView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left Column: Audio Output & Volume
            VolumeControlView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Right Column: Displays & Brightness
            MultiDisplayBrightnessView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
