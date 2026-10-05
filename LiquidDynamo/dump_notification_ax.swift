import Foundation
import ApplicationServices
import AppKit

func printAXElement(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
    if depth > maxDepth { return }
    let indent = String(repeating: "  ", count: depth)
    
    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    let roleStr = role as? String ?? "UnknownRole"
    
    var subrole: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    let subroleStr = subrole as? String ?? ""
    
    var title: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    let titleStr = title as? String ?? ""
    
    var desc: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
    let descStr = desc as? String ?? ""
    
    var val: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val)
    let valStr = (val as? String) ?? (val != nil ? "\(val!)" : "")
    
    var identifier: AnyObject?
    AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifier)
    let idStr = identifier as? String ?? ""
    
    var details = ["Role: \(roleStr)"]
    if !subroleStr.isEmpty { details.append("Subrole: \(subroleStr)") }
    if !idStr.isEmpty { details.append("ID: \(idStr)") }
    if !titleStr.isEmpty { details.append("Title: \"\(titleStr)\"") }
    if !descStr.isEmpty { details.append("Desc: \"\(descStr)\"") }
    if !valStr.isEmpty { details.append("Value: \"\(valStr)\"") }
    
    print("\(indent)- [\(details.joined(separator: ", "))]")
    
    var childrenRef: AnyObject?
    let res = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    if res == .success, let children = childrenRef as? [AXUIElement] {
        for child in children {
            printAXElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

func inspectBanner(_ banner: AXUIElement) {
    var attrNames: CFArray?
    AXUIElementCopyAttributeNames(banner, &attrNames)
    print("      Banner Attributes: \((attrNames as? [String]) ?? [])")
    
    var actionNames: CFArray?
    AXUIElementCopyActionNames(banner, &actionNames)
    print("      Banner Actions: \((actionNames as? [String]) ?? [])")
    
    var desc: AnyObject?
    AXUIElementCopyAttributeValue(banner, kAXDescriptionAttribute as CFString, &desc)
    print("      Banner Description: \"\(desc as? String ?? "")\"")
    
    var idVal: AnyObject?
    AXUIElementCopyAttributeValue(banner, "AXIdentifier" as CFString, &idVal)
    print("      Banner UUID Identifier: \"\(idVal as? String ?? "")\"")
    
    var childrenRef: AnyObject?
    AXUIElementCopyAttributeValue(banner, kAXChildrenAttribute as CFString, &childrenRef)
    if let children = childrenRef as? [AXUIElement] {
        print("      Banner Children Count: \(children.count)")
        for child in children {
            var role: AnyObject?, subrole: AnyObject?, title: AnyObject?, val: AnyObject?, childId: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subrole)
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val)
            AXUIElementCopyAttributeValue(child, "AXIdentifier" as CFString, &childId)
            
            var childActions: CFArray?
            AXUIElementCopyActionNames(child, &childActions)
            
            print("        Child -> Role: \(role as? String ?? ""), Subrole: \(subrole as? String ?? ""), ID: \(childId as? String ?? ""), Val: \"\(val as? String ?? "")\", Actions: \((childActions as? [String]) ?? [])")
        }
    }
}

// Post fresh notification
let script = """
display notification "Meeting with Design Team in 10 minutes" with title "Calendar" subtitle "Team Sync"
"""
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
p.arguments = ["-e", script]
try? p.run()
p.waitUntilExit()

Thread.sleep(forTimeInterval: 0.6)

let ncApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.notificationcenterui" }
if let nc = ncApps.first {
    let appElement = AXUIElementCreateApplication(nc.processIdentifier)
    var windowsRef: AnyObject?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for w in windows {
            var title: AnyObject?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title)
            if (title as? String) == "Notification Center" {
                print("Found Notification Center window!")
                // Search for banners recursively
                func findBanners(_ elem: AXUIElement) {
                    var subrole: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subrole)
                    if (subrole as? String) == "AXNotificationCenterBanner" {
                        print(">>> Located AXNotificationCenterBanner:")
                        inspectBanner(elem)
                    }
                    var childrenRef: AnyObject?
                    if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let children = childrenRef as? [AXUIElement] {
                        for c in children {
                            findBanners(c)
                        }
                    }
                }
                findBanners(w)
            }
        }
    }
}


