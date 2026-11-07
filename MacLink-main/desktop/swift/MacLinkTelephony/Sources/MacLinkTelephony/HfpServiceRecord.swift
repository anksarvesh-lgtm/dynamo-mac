// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOBluetooth

/**
 * Publishes the Bluetooth Hands-Free Profile (HFP 1.7) SDP service record on macOS
 * so paired Android phones recognize this Mac as a phone call audio device.
 */
public final class HfpServiceRecord: NSObject {
    public static let shared = HfpServiceRecord()

    private var record: IOBluetoothSDPServiceRecord?

    public private(set) var isPublished: Bool = false

    private override init() {
        super.init()
    }

    /**
     * Publishes the HFP Hands-Free SDP record.
     */
    public func publish(rfcommChannel: UInt8 = 6) -> Bool {
        guard !isPublished else { return true }

        let sdpDict: [String: Any] = [
            // 0x0001: ServiceClassIDList
            "0001 - ServiceClassIDList": [
                Data([0x11, 0x1E]), // Handsfree
                Data([0x12, 0x03]), // Generic Audio
            ],
            // 0x0004: ProtocolDescriptorList
            "0004 - ProtocolDescriptorList": [
                [
                    Data([0x01, 0x00]), // L2CAP
                ],
                [
                    Data([0x00, 0x03]), // RFCOMM
                    NSNumber(value: rfcommChannel),
                ],
            ],
            // 0x0009: BluetoothProfileDescriptorList
            "0009 - BluetoothProfileDescriptorList": [
                [
                    Data([0x11, 0x1E]), // Handsfree
                    NSNumber(value: 0x0107), // Version 1.7
                ],
            ],
            // 0x0100: ServiceName
            "0100 - ServiceName": "MacLink Hands-Free Audio",
            // 0x0311: SupportedFeatures (HFP 1.7 bitmap)
            "0311 - SupportedFeatures": NSNumber(value: 0x00A0), // EC/NR + Codec Negotiation
            "LocalAttributes": [
                "Persistent": false,
            ],
        ]

        if let rec = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: sdpDict) {
            self.record = rec
            self.isPublished = true
            return true
        }

        return false
    }

    /**
     * Unpublishes the SDP record.
     */
    public func unpublish() {
        if let rec = record {
            _ = rec.remove()
        }
        record = nil
        isPublished = false
    }
}

