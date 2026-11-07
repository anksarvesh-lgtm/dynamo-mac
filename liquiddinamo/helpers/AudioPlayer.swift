//
//  AudioPlayer.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import Foundation
import AppKit

class AudioPlayer {
    func play(fileName: String, fileExtension: String) {
        NSSound(contentsOf:Bundle.main.url(forResource: fileName, withExtension: fileExtension)!, byReference: false)?.play()
    }
}
