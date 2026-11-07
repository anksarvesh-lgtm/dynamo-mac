// SPDX-License-Identifier: MIT
import AppKit

// LSUIElement (project.yml) makes this an accessory app: no Dock icon, no menu bar,
// and the notch panel never steals focus. First efficiency lever.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// No menu bar shows, but ⌘V and the rest reach text fields only through the main menu's key
// equivalents: without an Edit menu, nothing pastes into the notch or Settings.
let edit = NSMenu(title: "Edit")
edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")  // capital: ⇧⌘Z
edit.addItem(.separator())
edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
app.mainMenu = NSMenu()
app.mainMenu?.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

app.run()
