#!/bin/bash
set -e

BASE="${SPM_DEPS_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/spm_deps.XXXXXX")}"
export SPM_DEPS_DIR="$BASE"
OUT_DIR="$BASE/modules"
FW_DIR="$BASE/frameworks_flat"
BUNDLE_DIR="$BASE/bundle_frameworks"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"

mkdir -p "$BASE" "$OUT_DIR" "$FW_DIR" "$BUNDLE_DIR"

echo "==> Setting up SPM dependencies under $BASE..."

# 1. Clone source repos from SPM cache if not present
python3 -c "
import os, subprocess

base = '$BASE'
deps = [
    ('AsyncXPCConnection', 'https://github.com/ChimeHQ/AsyncXPCConnection.git', '1.3.0'),
    ('Defaults', 'https://github.com/sindresorhus/Defaults.git', 'v9.0.0-beta.4'),
    ('KeyboardShortcuts', 'https://github.com/sindresorhus/KeyboardShortcuts.git', 'v1.9.4'),
    ('LaunchAtLogin', 'https://github.com/sindresorhus/LaunchAtLogin-Modern.git', 'v1.1.0'),
    ('MacroVisionKit', 'https://github.com/TheBoredTeam/MacroVisionKit.git', 'v0.2.0'),
    ('SkyLightWindow', 'https://github.com/Lakr233/SkyLightWindow.git', 'main'),
    ('SwiftUIIntrospect', 'https://github.com/siteline/swiftui-introspect.git', '27.1.0'),
]

for name, repo_path, tag in deps:
    target_dir = os.path.join(base, name)
    if not os.path.exists(target_dir):
        print(f'Cloning {name} from {repo_path}...')
        subprocess.run(['git', 'clone', repo_path, target_dir], check=True, capture_output=True)
        subprocess.run(['git', '-C', target_dir, 'checkout', tag], check=True, capture_output=True)
"

# 2. Add resource accessor for KeyboardShortcuts
cat << 'EOF' > "$BASE/KeyboardShortcuts/Sources/KeyboardShortcuts/resource_bundle_accessor.swift"
import Foundation
extension Bundle {
    static let module: Bundle = {
        let bundleName = "KeyboardShortcuts_KeyboardShortcuts"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleToken.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        return Bundle.main
    }()
}
private final class BundleToken {}
EOF

# 3. Compile all 7 Swift modules
echo "=== Building AsyncXPCConnection ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name AsyncXPCConnection \
  -emit-module -emit-module-path "$OUT_DIR/AsyncXPCConnection.swiftmodule" \
  -emit-library -o "$OUT_DIR/libAsyncXPCConnection.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libAsyncXPCConnection.dylib" \
  "$BASE/AsyncXPCConnection/Sources/AsyncXPCConnection/"*.swift

echo "=== Building Defaults ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name Defaults \
  -emit-module -emit-module-path "$OUT_DIR/Defaults.swiftmodule" \
  -emit-library -o "$OUT_DIR/libDefaults.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libDefaults.dylib" \
  "$BASE/Defaults/Sources/Defaults/"*.swift

echo "=== Building KeyboardShortcuts ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name KeyboardShortcuts \
  -emit-module -emit-module-path "$OUT_DIR/KeyboardShortcuts.swiftmodule" \
  -emit-library -o "$OUT_DIR/libKeyboardShortcuts.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libKeyboardShortcuts.dylib" \
  "$BASE/KeyboardShortcuts/Sources/KeyboardShortcuts/"*.swift

echo "=== Building LaunchAtLogin ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name LaunchAtLogin \
  -emit-module -emit-module-path "$OUT_DIR/LaunchAtLogin.swiftmodule" \
  -emit-library -o "$OUT_DIR/libLaunchAtLogin.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libLaunchAtLogin.dylib" \
  "$BASE/LaunchAtLogin/Sources/LaunchAtLogin/"*.swift

echo "=== Building MacroVisionKit ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name MacroVisionKit \
  -emit-module -emit-module-path "$OUT_DIR/MacroVisionKit.swiftmodule" \
  -emit-library -o "$OUT_DIR/libMacroVisionKit.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libMacroVisionKit.dylib" \
  "$BASE/MacroVisionKit/Sources/MacroVisionKit/"*.swift

echo "=== Building SkyLightWindow ==="
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name SkyLightWindow \
  -emit-module -emit-module-path "$OUT_DIR/SkyLightWindow.swiftmodule" \
  -emit-library -o "$OUT_DIR/libSkyLightWindow.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libSkyLightWindow.dylib" \
  "$BASE/SkyLightWindow/Sources/SkyLightWindow/"*.swift

echo "=== Building SwiftUIIntrospect ==="
find "$BASE/SwiftUIIntrospect/Sources" -name "*.swift" > "$BASE/introspect_sources.txt"
swiftc -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-name SwiftUIIntrospect \
  -emit-module -emit-module-path "$OUT_DIR/SwiftUIIntrospect.swiftmodule" \
  -emit-library -o "$OUT_DIR/libSwiftUIIntrospect.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libSwiftUIIntrospect.dylib" \
  @"$BASE/introspect_sources.txt"

# 4. Fetch Sparkle headers/framework if not in frameworks_flat
if [ ! -d "$FW_DIR/Sparkle.framework" ]; then
    echo "=== Downloading Sparkle.framework 2.6.4 ==="
    mkdir -p "$FW_DIR"
    curl -sL https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz | tar -xJ -C "$FW_DIR"
fi

# 5. Copy or download Lottie.framework
if [ ! -d "$FW_DIR/Lottie.framework" ]; then
    if [ -d "$DIR/Frameworks/Lottie.framework" ]; then
        cp -R "$DIR/Frameworks/Lottie.framework" "$FW_DIR/"
    elif [ -d "/Applications/LiquidDynamo.app/Contents/Frameworks/Lottie.framework" ] && [ -d "/Applications/LiquidDynamo.app/Contents/Frameworks/Lottie.framework/Modules" ]; then
        cp -R "/Applications/LiquidDynamo.app/Contents/Frameworks/Lottie.framework" "$FW_DIR/"
    else
        echo "=== Downloading Lottie.xcframework 4.5.0 ==="
        curl -sL https://github.com/airbnb/lottie-ios/releases/download/4.5.0/Lottie.xcframework.zip -o "$BASE/lottie.zip"
        unzip -q "$BASE/lottie.zip" -d "$BASE"
        cp -R "$BASE"/Lottie.xcframework/macos*/*.framework "$FW_DIR/"
    fi
fi

# 6. Re-link install names to @rpath in both OUT_DIR and BUNDLE_DIR
for lib in AsyncXPCConnection Defaults KeyboardShortcuts LaunchAtLogin MacroVisionKit SkyLightWindow SwiftUIIntrospect; do
    install_name_tool -id "@rpath/lib${lib}.dylib" "$OUT_DIR/lib${lib}.dylib" 2>/dev/null || true
    cp -f "$OUT_DIR/lib${lib}.dylib" "$BUNDLE_DIR/"
    install_name_tool -id "@rpath/lib${lib}.dylib" "$BUNDLE_DIR/lib${lib}.dylib" 2>/dev/null || true
done

echo "==> All SPM dependencies successfully configured!"
