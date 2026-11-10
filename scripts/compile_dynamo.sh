#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
SPM_DEPS_DIR="${SPM_DEPS_DIR:-"$DIR/.build/spm_deps"}"
export SPM_DEPS_DIR
MODULES_DIR="$SPM_DEPS_DIR/modules"
FRAMEWORKS_DIR="$SPM_DEPS_DIR/frameworks_flat"
BUNDLE_FRAMEWORKS="$SPM_DEPS_DIR/bundle_frameworks"

echo "==> LiquidDynamo CLI Compiler using SDK: $SDK (deps: $SPM_DEPS_DIR)"
mkdir -p "$MODULES_DIR" "$FRAMEWORKS_DIR" "$BUNDLE_FRAMEWORKS" "$SPM_DEPS_DIR/module-cache"

# 1. Compile 7 Swift dependencies if not already present
if [ ! -f "$MODULES_DIR/Defaults.swiftmodule" ] || [ ! -f "$MODULES_DIR/libDefaults.dylib" ] || [ ! -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    echo "==> Compiling Swift package dependencies via setup_spm_deps.sh..."
    bash "$DIR/scripts/setup_spm_deps.sh"
fi

for lib in AsyncXPCConnection Defaults KeyboardShortcuts LaunchAtLogin MacroVisionKit SkyLightWindow SwiftUIIntrospect; do
    if [ ! -f "$BUNDLE_FRAMEWORKS/lib${lib}.dylib" ]; then
        cp "$MODULES_DIR/lib${lib}.dylib" "$BUNDLE_FRAMEWORKS/"
        install_name_tool -id "@rpath/lib${lib}.dylib" "$BUNDLE_FRAMEWORKS/lib${lib}.dylib"
    fi
done

# 2. Gather all project Swift sources in an isolated snapshot to prevent timestamp race conditions
python3 -c "
import os, shutil
deps_dir = os.environ.get('SPM_DEPS_DIR', '/tmp/spm_deps')
staged_dir = os.path.join(deps_dir, 'staged_sources')
if os.path.exists(staged_dir):
    shutil.rmtree(staged_dir)
shutil.copytree('liquiddinamo', os.path.join(staged_dir, 'liquiddinamo'))
sources = []
for root, dirs, files in os.walk(staged_dir):
    for f in files:
        if f.endswith('.swift'):
            sources.append(os.path.join(root, f))
sources_file = os.path.join(deps_dir, 'all_dynamo_sources.txt')
with open(sources_file, 'w') as f:
    for s in sorted(sources):
        f.write(f'\"{s}\"\n')
print(f'Prepared {len(sources)} Swift source files in {staged_dir}.')
"

# 3. Compile LiquidDynamo binary
OUTPUT_BIN="$SPM_DEPS_DIR/LiquidDynamo_test"
if [ "${SKIP_COMPILE:-0}" = "1" ] && [ -f "$OUTPUT_BIN" ]; then
  echo "==> Reusing pre-compiled LiquidDynamo binary at $OUTPUT_BIN..."
else
  echo "==> Compiling LiquidDynamo executable to $OUTPUT_BIN..."
  swiftc -module-name LiquidDynamo \
    -target arm64-apple-macos14.0 \
    -sdk "$SDK" \
    -module-cache-path "$SPM_DEPS_DIR/module-cache" \
    -Xcc -fmodules-cache-path="$SPM_DEPS_DIR/module-cache" \
    -O -whole-module-optimization \
    -I "$MODULES_DIR" \
    -F "$FRAMEWORKS_DIR" \
    -F "$DIR/mediaremote-adapter" \
    -F "$SDK/System/Library/PrivateFrameworks" \
    -framework Sparkle \
    -framework Lottie \
    -framework IOKit \
    -framework AVFoundation \
    -framework CoreMediaIO \
    -framework EventKit \
    -framework CoreBluetooth \
    -framework IOBluetooth \
    -framework UserNotifications \
    -framework SceneKit \
    -framework ServiceManagement \
    -framework CoreWLAN \
    -framework DiskArbitration \
    -L "$MODULES_DIR" \
    -lAsyncXPCConnection \
    -lDefaults \
    -lKeyboardShortcuts \
    -lLaunchAtLogin \
    -lMacroVisionKit \
    -lSkyLightWindow \
    -lSwiftUIIntrospect \
    -parse-as-library \
    -emit-executable \
    -o "$OUTPUT_BIN" \
    @"$SPM_DEPS_DIR/all_dynamo_sources.txt" \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -Xlinker -rpath -Xlinker "$DIR/mediaremote-adapter"
fi

# 4. Re-link install names to @rpath
for lib in AsyncXPCConnection Defaults KeyboardShortcuts LaunchAtLogin MacroVisionKit SkyLightWindow SwiftUIIntrospect; do
    install_name_tool -change "$MODULES_DIR/lib${lib}.dylib" "@rpath/lib${lib}.dylib" "$OUTPUT_BIN" 2>/dev/null || true
    CURRENT_REF="$(otool -L "$OUTPUT_BIN" | awk '{print $1}' | grep "/lib${lib}\.dylib" || true)"
    if [ -n "$CURRENT_REF" ] && [ "$CURRENT_REF" != "@rpath/lib${lib}.dylib" ]; then
        echo "==> Re-linking $CURRENT_REF to @rpath/lib${lib}.dylib in $OUTPUT_BIN"
        install_name_tool -change "$CURRENT_REF" "@rpath/lib${lib}.dylib" "$OUTPUT_BIN" 2>/dev/null || true
    fi
done

if [ -d "$DIR/build/LiquidDynamo.app/Contents/MacOS" ]; then
    echo "==> Updating $DIR/build/LiquidDynamo.app/Contents/MacOS/LiquidDynamo..."
    cp "$OUTPUT_BIN" "$DIR/build/LiquidDynamo.app/Contents/MacOS/LiquidDynamo"
    mkdir -p "$DIR/build/LiquidDynamo.app/Contents/Frameworks"
    cp "$BUNDLE_FRAMEWORKS"/*.dylib "$DIR/build/LiquidDynamo.app/Contents/Frameworks/"
    cp "$DIR/mediaremote-adapter/mediaremote-adapter.pl" "$DIR/build/LiquidDynamo.app/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true
fi

echo "==> Compilation complete! Output: $OUTPUT_BIN"
