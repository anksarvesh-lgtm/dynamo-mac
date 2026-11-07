//
//  CalendarModel.swift
//  Calendr
//
//  LiquidDynamo Core Team
//  Original source: https://github.com/pakerwreah/Calendr
//

import Cocoa

struct CalendarModel: Equatable {
    let id: String
    let account: String
    let title: String
    let color: NSColor
    let isSubscribed: Bool
    let isReminder: Bool // true if this is a reminder calendar
}
