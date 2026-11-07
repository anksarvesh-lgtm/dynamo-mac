NotchIsland - first launch
==========================

1. Drag NotchIsland into Applications.

2. macOS will say "Apple could not verify NotchIsland is free of malware".
   That is Gatekeeper noticing the app is not notarized: NotchIsland is free and
   open source and is signed with its own certificate, not a paid Apple
   Developer ID. To open it anyway:

   macOS 15 Sequoia and later
     - Click Done.
     - System Settings > Privacy & Security > scroll down to
       "NotchIsland was blocked" > Open Anyway > Open.

   macOS 13 and 14
     - Right-click NotchIsland in Applications > Open > Open.

   Or from Terminal (clears the download flag macOS uses to show the warning):
     xattr -dr com.apple.quarantine /Applications/NotchIsland.app

3. For notifications, give NotchIsland Full Disk Access:
   System Settings > Privacy & Security > Full Disk Access > turn on NotchIsland
   (click + and pick it from Applications if it is not listed), then relaunch.

4. Updating from an earlier version? macOS ties each permission to the build
   that asked for it. If a switch is on in System Settings but NotchIsland says
   the permission is missing, open NotchIsland's Settings > Permissions and
   click Reset next to it, then allow it again. Entries with a terminal icon
   are leftovers from a development build and do not count.

5. This is the last DMG you need. NotchIsland checks GitHub once a day and
   says so in the island when a new version is out; Settings > Updates shows
   what's new, and Update Now installs it in place (same signature, so your
   permissions carry over, and no Gatekeeper dialog).

Source, issues and releases: https://github.com/Edwardrem/NotchIsland
