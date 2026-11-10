//
//  MacLinkFilesView.swift
//  LiquidDynamo
//
//  MacLink Remote Phone File Manager: Full ADB & MTP dual-pane explorer,
//  drag-and-drop transfer between Mac and phone, and storage breakdown.
//

import AppKit
import SwiftUI

public struct MacLinkFilesView: View {
    @StateObject private var viewModel = AndroidFileManagerViewModel(deviceSerial: "USB_DEVICE_1", deviceName: "Android Phone")

    public init() {}

    public var body: some View {
        AndroidFileManagerView(viewModel: viewModel)
    }
}
