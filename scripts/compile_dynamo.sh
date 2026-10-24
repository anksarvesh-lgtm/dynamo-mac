#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
MODULES_DIR="/tmp/spm_deps/modules"
FRAMEWORKS_DIR="/tmp/spm_deps/frameworks_flat"
BUNDLE_FRAMEWORKS="/tmp/spm_deps/bundle_frameworks"

echo "==> LiquidDynamo CLI Compiler using SDK: $SDK"
mkdir -p "$MODULES_DIR" "$FRAMEWORKS_DIR" "$BUNDLE_FRAMEWORKS"

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

# 2. Gather all project Swift sources
python3 -c "
import os
sources = []
for root, dirs, files in os.walk('liquiddinamo'):
    for f in files:
        if f.endswith('.swift'):
            sources.append(os.path.join(root, f))
with open('/tmp/spm_deps/all_dynamo_sources.txt', 'w') as f:
    for s in sorted(sources):
        f.write(f'\"{s}\"\n')
print(f'Prepared {len(sources)} Swift source files.')
"

# 3. Compile LiquidDynamo binary
OUTPUT_BIN="/tmp/spm_deps/LiquidDynamo_test"
echo "==> Compiling LiquidDynamo executable to $OUTPUT_BIN..."
swiftc -module-name LiquidDynamo \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
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
  @/tmp/spm_deps/all_dynamo_sources.txt \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -rpath -Xlinker "$DIR/mediaremote-adapter"

# 4. Re-link install names to @rpath
for lib in AsyncXPCConnection Defaults KeyboardShortcuts LaunchAtLogin MacroVisionKit SkyLightWindow SwiftUIIntrospect; do
    install_name_tool -change "$MODULES_DIR/lib${lib}.dylib" "@rpath/lib${lib}.dylib" "$OUTPUT_BIN"
done

echo "==> Compilation complete! Output: $OUTPUT_BIN"
