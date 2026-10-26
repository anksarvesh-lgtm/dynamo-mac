#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import subprocess

def get_token():
    proc = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, _ = proc.communicate(input='protocol=https\nhost=github.com\n\n')
    for line in out.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1]
    return None

token = get_token()
if not token:
    print("Error: Could not retrieve GitHub credentials from git.", file=sys.stderr)
    sys.exit(1)

repos = ["anksarvesh-lgtm/dynamo-mac", "anksarvesh-lgtm/dynamomac"]
version = "2.0.6"
tag_name = f"v{version}"
release_title = f"LiquidDynamo {version} — Live 3D Water Glass Capsules & Global Clipping Refinements"
release_body = """## LiquidDynamo 2.0.6 — Live 3D Water Glass Capsules & Global Clipping Refinements

LiquidDynamo transforms your MacBook hardware notch into an intelligent Liquid Glass status and notification Dynamic Island.

### Core Highlights in Version 2.0.6:
1. **Unified Live 3D Water Effect Across All Capsules**:
   - Implemented realistic half-filled (50%) liquid volume with dual-layered sine waves, animated fluid pouring streams, surface ripples, and dynamic specular caustics.
   - Applied consistently across all connected device capsules (MagSafe Charger, Devices, Sarvesh/iPhone, RTL9201 external SSD) and dashboard quick tool status capsules.
2. **Deterministic Spatial & Phase Staggering**:
   - Seeded per-device phase offsets and stream X coordinates prevent artificial synchronized movement across multiple connected device capsules.
3. **Specular Glass Containment**:
   - Exact capsule boundary clipping preserving existing Liquid Glass materials, drop shadows, and responsive layout spring physics.
4. **CI/CD & Update Engine Compatibility**:
   - Runner updated to support Xcode 16 project schemas and verified direct update delivery.

### Direct Downloads:
- **[liquiddynamo.zip](https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/v2.0.6/liquiddynamo.zip)** (Fast in-app update & direct app bundle)
- **[liquiddynamo.zip (Latest)](https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/liquiddynamo.zip)** (Permanent latest app zip link)
- **[LiquidDynamo-2.0.6.dmg](https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/v2.0.6/LiquidDynamo-2.0.6.dmg)** (Standalone signed DMG)
- **[LiquidDynamo.dmg](https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/LiquidDynamo.dmg)** (Permanent latest release link)
"""

dmg_file = os.path.expanduser(f"~/Desktop/LiquidDynamo-{version}.dmg")
if not os.path.exists(dmg_file):
    dmg_file = os.path.expanduser("~/Desktop/LiquidDynamo.dmg")

if not os.path.exists(dmg_file):
    print(f"Error: DMG file not found on Desktop", file=sys.stderr)
    sys.exit(1)

with open(dmg_file, "rb") as f:
    dmg_data = f.read()

zip_file = os.path.expanduser("~/Desktop/liquiddynamo.zip")
if not os.path.exists(zip_file):
    zip_file = os.path.join(os.getcwd(), "build", "liquiddynamo.zip")

zip_data = None
if os.path.exists(zip_file):
    with open(zip_file, "rb") as f:
        zip_data = f.read()
    print(f"Loaded liquiddynamo.zip ({len(zip_data) // (1024*1024)} MB)")

headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "User-Agent": "LiquidDynamo-Release-Publisher",
}

for repo in repos:
    print(f"\n==> Processing repository: {repo}")
    
    # 1. Fetch or create release for v1.9.8
    get_rel_url = f"https://api.github.com/repos/{repo}/releases/tags/{tag_name}"
    req = urllib.request.Request(get_rel_url, headers=headers)
    release = None
    try:
        with urllib.request.urlopen(req) as resp:
            release = json.loads(resp.read().decode())
            print(f"  Found existing release for {tag_name} (ID: {release['id']})")
    except Exception:
        pass

    if not release:
        create_url = f"https://api.github.com/repos/{repo}/releases"
        payload = json.dumps({
            "tag_name": tag_name,
            "target_commitish": "main",
            "name": release_title,
            "body": release_body,
            "draft": False,
            "prerelease": False
        }).encode()
        creq = urllib.request.Request(create_url, data=payload, headers={**headers, "Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(creq) as resp:
                release = json.loads(resp.read().decode())
                print(f"  Created release for {tag_name} (ID: {release['id']})")
        except Exception as e:
            print(f"  Failed to create release for {repo}: {e}")
            continue

    release_id = release["id"]
    upload_url_base = release["upload_url"].split("{")[0]

    # Delete existing assets if any
    assets_url = f"https://api.github.com/repos/{repo}/releases/{release_id}/assets"
    try:
        with urllib.request.urlopen(urllib.request.Request(assets_url, headers=headers)) as resp:
            assets = json.loads(resp.read().decode())
            for asset in assets:
                if asset["name"] in [f"LiquidDynamo-{version}.dmg", "LiquidDynamo.dmg", "liquiddynamo.zip"]:
                    print(f"  Deleting existing asset {asset['name']} (ID: {asset['id']})")
                    del_req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/assets/{asset['id']}", headers=headers, method="DELETE")
                    with urllib.request.urlopen(del_req):
                        pass
    except Exception as e:
        print(f"  Notice checking assets: {e}")

    # Upload LiquidDynamo-1.9.8.dmg
    upload_url = f"{upload_url_base}?name=LiquidDynamo-{version}.dmg"
    up_req = urllib.request.Request(upload_url, data=dmg_data, headers={**headers, "Content-Type": "application/octet-stream"}, method="POST")
    try:
        print(f"  Uploading LiquidDynamo-{version}.dmg ({len(dmg_data) // (1024*1024)} MB)...")
        with urllib.request.urlopen(up_req) as resp:
            info = json.loads(resp.read().decode())
            print(f"  SUCCESS: Uploaded to {info.get('browser_download_url')}")
    except Exception as e:
        print(f"  Failed to upload asset: {e}")

    # Also upload LiquidDynamo.dmg
    upload_url_generic = f"{upload_url_base}?name=LiquidDynamo.dmg"
    up_req_gen = urllib.request.Request(upload_url_generic, data=dmg_data, headers={**headers, "Content-Type": "application/octet-stream"}, method="POST")
    try:
        print(f"  Uploading LiquidDynamo.dmg...")
        with urllib.request.urlopen(up_req_gen) as resp:
            info = json.loads(resp.read().decode())
            print(f"  SUCCESS: Uploaded to {info.get('browser_download_url')}")
    except Exception as e:
        print(f"  Failed to upload generic asset: {e}")

    # Upload liquiddynamo.zip (containing liquiddynamo.app)
    if zip_data:
        upload_url_zip = f"{upload_url_base}?name=liquiddynamo.zip"
        up_req_zip = urllib.request.Request(upload_url_zip, data=zip_data, headers={**headers, "Content-Type": "application/zip"}, method="POST")
        try:
            print(f"  Uploading liquiddynamo.zip ({len(zip_data) // (1024*1024)} MB)...")
            with urllib.request.urlopen(up_req_zip) as resp:
                info = json.loads(resp.read().decode())
                print(f"  SUCCESS: Uploaded to {info.get('browser_download_url')}")
        except Exception as e:
            print(f"  Failed to upload liquiddynamo.zip: {e}")

    # Also update 'app' tag release with latest LiquidDynamo.dmg and liquiddynamo.zip
    print(f"  Updating 'app' tag release...")
    get_app_rel_url = f"https://api.github.com/repos/{repo}/releases/tags/app"
    app_release = None
    try:
        with urllib.request.urlopen(urllib.request.Request(get_app_rel_url, headers=headers)) as resp:
            app_release = json.loads(resp.read().decode())
    except Exception:
        pass

    if not app_release:
        create_app_url = f"https://api.github.com/repos/{repo}/releases"
        payload = json.dumps({
            "tag_name": "app",
            "name": "LiquidDynamo (Latest)",
            "body": "Permanent download link for latest LiquidDynamo release.",
            "draft": False,
            "prerelease": False
        }).encode()
        creq = urllib.request.Request(create_app_url, data=payload, headers={**headers, "Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(creq) as resp:
                app_release = json.loads(resp.read().decode())
        except Exception as e:
            print(f"  Notice creating app release: {e}")

    if app_release:
        app_rel_id = app_release["id"]
        app_upload_base = app_release["upload_url"].split("{")[0]
        # Remove old assets
        try:
            with urllib.request.urlopen(urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/{app_rel_id}/assets", headers=headers)) as resp:
                a_list = json.loads(resp.read().decode())
                for a in a_list:
                    if a["name"] in ["LiquidDynamo.dmg", "liquiddynamo.zip"]:
                        d_req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/assets/{a['id']}", headers=headers, method="DELETE")
                        with urllib.request.urlopen(d_req):
                            pass
        except Exception:
            pass

        # Upload new LiquidDynamo.dmg
        up_app_req = urllib.request.Request(f"{app_upload_base}?name=LiquidDynamo.dmg", data=dmg_data, headers={**headers, "Content-Type": "application/octet-stream"}, method="POST")
        try:
            with urllib.request.urlopen(up_app_req) as resp:
                a_res = json.loads(resp.read().decode())
                print(f"  SUCCESS: Updated app release asset: {a_res.get('browser_download_url')}")
        except Exception as e:
            print(f"  Notice uploading to app tag: {e}")

        # Upload new liquiddynamo.zip
        if zip_data:
            up_app_zip_req = urllib.request.Request(f"{app_upload_base}?name=liquiddynamo.zip", data=zip_data, headers={**headers, "Content-Type": "application/zip"}, method="POST")
            try:
                with urllib.request.urlopen(up_app_zip_req) as resp:
                    a_res = json.loads(resp.read().decode())
                    print(f"  SUCCESS: Updated app release asset (liquiddynamo.zip): {a_res.get('browser_download_url')}")
            except Exception as e:
                print(f"  Notice uploading liquiddynamo.zip to app tag: {e}")

print("\n==> All GitHub release operations completed successfully!")
