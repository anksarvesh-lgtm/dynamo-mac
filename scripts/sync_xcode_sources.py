#!/usr/bin/env python3
import os
import re
import hashlib
import shutil
import subprocess

PBX_PATH = "LiquidDynamo.xcodeproj/project.pbxproj"

def make_id(seed: str) -> str:
    h = hashlib.sha1(seed.encode("utf-8")).hexdigest().upper()
    return "FE" + h[:22]

def sync():
    # Start from fresh backup
    if os.path.exists(PBX_PATH + ".bak_m1"):
        shutil.copyfile(PBX_PATH + ".bak_m1", PBX_PATH)

    with open(PBX_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    missing_files = []
    for root, dirs, files in os.walk("liquiddinamo"):
        for file in sorted(files):
            if file.endswith(".swift") or file.endswith(".metal"):
                if file not in content:
                    rel = os.path.relpath(os.path.join(root, file), "liquiddinamo")
                    missing_files.append((rel, file))

    print(f"Missing Swift/Metal files: {len(missing_files)}")

    # Define groups to add if missing
    new_groups = {
        "Powerload": ("Powerload", "E1A000042E60000100000001"), # Under Features
        "PhoneBridge": ("PhoneBridge", "E1A000042E60000100000001"),
        "AndroidFiles": ("AndroidFiles", "E1A000042E60000100000001"),
        "Watcher": ("Watcher", "E1A000042E60000100000001"),
        "ColorDropper": ("ColorDropper", "E1A000042E60000100000001"),
        "menu": ("menu", "14CEF4142C5CAED300855D72"), # Under LiquidDynamo root group
    }

    group_ids = {}
    for gname, (gpath, parent_id) in new_groups.items():
        gid = make_id(f"GROUP_{gname}")
        group_ids[gname] = gid

    # Build files and file references
    build_files = []
    file_refs = []
    sources_entries = []
    group_children = {k: [] for k in new_groups}
    group_children["Settings"] = []
    group_children["components"] = []
    group_children["helpers"] = []
    group_children["metal"] = []
    group_children["Network"] = []
    group_children["private"] = []
    for rel, filename in missing_files:
        if rel.startswith("private/"):
            continue
        file_id = make_id(f"FILEREF_{rel}")
        build_id = make_id(f"BUILDFILE_{rel}")
        
        file_type = "sourcecode.metal" if filename.endswith(".metal") else "sourcecode.swift"
        
        build_files.append(f"\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};")
        file_refs.append(f"\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = \"{filename}\"; sourceTree = \"<group>\"; }};")
        sources_entries.append(f"\t\t\t\t{build_id} /* {filename} in Sources */,")
        
        child_entry = f"\t\t\t\t{file_id} /* {filename} */,"
        if rel.startswith("Features/Powerload/"):
            group_children["Powerload"].append(child_entry)
        elif rel.startswith("Features/PhoneBridge/"):
            group_children["PhoneBridge"].append(child_entry)
        elif rel.startswith("Features/AndroidFiles/"):
            group_children["AndroidFiles"].append(child_entry)
        elif rel.startswith("Features/Watcher/"):
            group_children["Watcher"].append(child_entry)
        elif rel.startswith("Features/ColorDropper/"):
            group_children["ColorDropper"].append(child_entry)
        elif rel.startswith("Features/Network/"):
            group_children["Network"].append(child_entry)
        elif rel.startswith("components/Settings/"):
            group_children["Settings"].append(child_entry)
        elif rel.startswith("components/"):
            group_children["components"].append(child_entry)
        elif rel.startswith("helpers/"):
            group_children["helpers"].append(child_entry)
        elif rel.startswith("metal/"):
            group_children["metal"].append(child_entry)
        elif rel.startswith("menu/"):
            group_children["menu"].append(child_entry)
        else:
            group_children["components"].append(child_entry)

    # Frameworks: kalam.dylib & libusb.dylib
    kalam_file_id = make_id("FILEREF_kalam_dylib")
    kalam_framework_build_id = make_id("BUILDFILE_kalam_frameworks")
    kalam_embed_build_id = make_id("BUILDFILE_kalam_embed")

    libusb_file_id = make_id("FILEREF_libusb_dylib")
    libusb_framework_build_id = make_id("BUILDFILE_libusb_frameworks")
    libusb_embed_build_id = make_id("BUILDFILE_libusb_embed")

    framework_build_files = [
        f"\t\t{kalam_framework_build_id} /* kalam.dylib in Frameworks */ = {{isa = PBXBuildFile; fileRef = {kalam_file_id} /* kalam.dylib */; }};",
        f"\t\t{kalam_embed_build_id} /* kalam.dylib in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {kalam_file_id} /* kalam.dylib */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};",
        f"\t\t{libusb_framework_build_id} /* libusb.dylib in Frameworks */ = {{isa = PBXBuildFile; fileRef = {libusb_file_id} /* libusb.dylib */; }};",
        f"\t\t{libusb_embed_build_id} /* libusb.dylib in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {libusb_file_id} /* libusb.dylib */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};",
    ]

    framework_file_refs = [
        f"\t\t{kalam_file_id} /* kalam.dylib */ = {{isa = PBXFileReference; lastKnownFileType = \"compiled.mach-o.dylib\"; name = kalam.dylib; path = Frameworks/kalam.dylib; sourceTree = SOURCE_ROOT; }};",
        f"\t\t{libusb_file_id} /* libusb.dylib */ = {{isa = PBXFileReference; lastKnownFileType = \"compiled.mach-o.dylib\"; name = libusb.dylib; path = Frameworks/libusb.dylib; sourceTree = SOURCE_ROOT; }};",
    ]

    # Insert into PBXBuildFile
    all_new_build_files = "\n".join(build_files + framework_build_files)
    content = content.replace("/* Begin PBXBuildFile section */", f"/* Begin PBXBuildFile section */\n{all_new_build_files}")

    # Insert into PBXFileReference
    all_new_file_refs = "\n".join(file_refs + framework_file_refs)
    content = content.replace("/* Begin PBXFileReference section */", f"/* Begin PBXFileReference section */\n{all_new_file_refs}")

    # Insert into PBXSourcesBuildPhase for LiquidDynamo
    all_sources = "\n".join(sources_entries)
    content = re.sub(
        r'(14CEF40E2C5CAED300855D72 /\* Sources \*/ = \{[^}]+files = \()',
        r'\1\n' + all_sources,
        content
    )

    # Insert into Frameworks build phase
    frameworks_entries = f"\t\t\t\t{kalam_framework_build_id} /* kalam.dylib in Frameworks */,\n\t\t\t\t{libusb_framework_build_id} /* libusb.dylib in Frameworks */,"
    content = re.sub(
        r'(14CEF40F2C5CAED300855D72 /\* Frameworks \*/ = \{[^}]+files = \()',
        r'\1\n' + frameworks_entries,
        content
    )

    # Insert into Embed Frameworks build phase
    embed_entries = f"\t\t\t\t{kalam_embed_build_id} /* kalam.dylib in Embed Frameworks */,\n\t\t\t\t{libusb_embed_build_id} /* libusb.dylib in Embed Frameworks */,"
    content = re.sub(
        r'(B1ECFA062C6FE58A002ACD87 /\* Embed Frameworks \*/ = \{[^}]+files = \()',
        r'\1\n' + embed_entries,
        content
    )

    # Insert into Frameworks group children
    fw_group_entries = f"\t\t\t\t{kalam_file_id} /* kalam.dylib */,\n\t\t\t\t{libusb_file_id} /* libusb.dylib */,"
    content = re.sub(
        r'(14D031EC2C689DB70096E6A1 /\* Frameworks \*/ = \{[^}]+children = \()',
        r'\1\n' + fw_group_entries,
        content
    )

    # Create new group definitions
    new_group_defs = []
    features_children_to_add = []
    root_children_to_add = []

    for gname, gid in group_ids.items():
        children_str = "\n".join(group_children[gname])
        gpath, parent_id = new_groups[gname]
        gdef = f"""\t\t{gid} /* {gname} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str}
\t\t\t);
\t\t\tpath = {gpath};
\t\t\tsourceTree = "<group>";
\t\t}};"""
        new_group_defs.append(gdef)
        if parent_id == "E1A000042E60000100000001":
            features_children_to_add.append(f"\t\t\t\t{gid} /* {gname} */,")
        else:
            root_children_to_add.append(f"\t\t\t\t{gid} /* {gname} */,")

    # Add new groups to PBXGroup section
    all_new_groups = "\n".join(new_group_defs)
    content = content.replace("/* Begin PBXGroup section */", f"/* Begin PBXGroup section */\n{all_new_groups}")

    # Add new feature groups to Features group children
    feat_add_str = "\n".join(features_children_to_add)
    content = re.sub(
        r'(E1A000042E60000100000001 /\* Features \*/ = \{[^}]+children = \()',
        r'\1\n' + feat_add_str,
        content
    )

    # Add menu group to LiquidDynamo root group
    root_add_str = "\n".join(root_children_to_add)
    content = re.sub(
        r'(14CEF4142C5CAED300855D72 /\* LiquidDynamo \*/ = \{[^}]+children = \()',
        r'\1\n' + root_add_str,
        content
    )

    # Add remaining individual files to existing groups
    existing_group_mappings = {
        "Network": ("E1A000502E60000100000001", group_children["Network"]),
        "Settings": ("B18654302C6F4590000B926A", group_children["Settings"]),
        "components": ("1471639B2C5D362F0068B555", group_children["components"]),
        "helpers": ("14288DD92C6E015000B9F80C", group_children["helpers"]),
        "metal": ("E2A000002E60000100000001", group_children["metal"]),
    }

    for gname, (gid, children) in existing_group_mappings.items():
        if children:
            c_str = "\n".join(children)
            content = re.sub(
                r'(' + re.escape(gid) + r' /\* ' + re.escape(gname) + r' \*/ = \{[^}]+children = \()',
                r'\1\n' + c_str,
                content
            )

    # Add LIBRARY_SEARCH_PATHS if missing
    lib_search_paths = """\t\t\t\tLIBRARY_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"$(PROJECT_DIR)/Frameworks",
\t\t\t\t);
\t\t\t\tFRAMEWORK_SEARCH_PATHS = ("""
    if "LIBRARY_SEARCH_PATHS" not in content:
        content = re.sub(r"(?<!SYSTEM_)FRAMEWORK_SEARCH_PATHS = \(", lib_search_paths, content)

    with open(PBX_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    res = subprocess.run(["plutil", "-lint", PBX_PATH], capture_output=True, text=True)
    if res.returncode == 0:
        print("Successfully synced and validated PBX project! (plutil OK)")
    else:
        print("plutil validation failed:", res.stderr or res.stdout)
        exit(1)

if __name__ == "__main__":
    sync()
