#!/usr/bin/env bash
set -e

DIR="$(pwd)"
python3 -c "
import os
cur_dir = os.getcwd()
with open('build/derived/Build/Intermediates.noindex/LiquidDynamo.build/Release/LiquidDynamo.build/Objects-normal/arm64/LiquidDynamo.SwiftFileList') as f:
    lines = [l.strip() for l in f if l.strip()]

clean_files = []
for l in lines:
    clean = l.replace('\\ ', ' ').replace('/Users/sarvesh/Documents/boring.notch/', '')
    full_path = os.path.join(cur_dir, clean)
    clean_files.append(full_path)

with open('scratch/project_swift_files.txt', 'w') as out:
    for cf in clean_files:
        out.write(f'\"{cf}\"\n')
print(f'Prepared {len(clean_files)} files for swiftc.')
"

echo "==> Compiling LiquidDynamo 1.9.2 with swiftc..."

swiftc -module-name LiquidDynamo \
  -target arm64-apple-macos14.0 \
  -sdk "$DIR/build/MacOSX27.sdk" \
  -O -whole-module-optimization \
  -I "$DIR/build/derived/Build/Products/Release" \
  -F "$DIR/build/derived/Build/Products/Release" \
  -F "$DIR/build/derived/Build/Products/Release/PackageFrameworks" \
  -F "$DIR/mediaremote-adapter" \
  -F "$DIR/build/MacOSX27.sdk/System/Library/PrivateFrameworks" \
  -framework MediaRemoteAdapter \
  -framework Sparkle \
  -framework Lottie \
  -framework IOKit \
  -framework AVFoundation \
  -framework CoreMediaIO \
  -framework EventKit \
  -framework CoreBluetooth \
  -framework SceneKit \
  -parse-as-library \
  -emit-executable \
  -o "$DIR/build/derived/Build/Products/Release/LiquidDynamo.app/Contents/MacOS/LiquidDynamo" \
  @scratch/project_swift_files.txt \
  "$DIR/build/derived/Build/Products/Release"/Defaults.o \
  "$DIR/build/derived/Build/Products/Release"/KeyboardShortcuts.o \
  "$DIR/build/derived/Build/Products/Release"/LaunchAtLogin.o \
  "$DIR/build/derived/Build/Products/Release"/MacroVisionKit.o \
  "$DIR/build/derived/Build/Products/Release"/OrderedCollections.o \
  "$DIR/build/derived/Build/Products/Release"/SkyLightWindow.o \
  "$DIR/build/derived/Build/Products/Release"/SwiftUIIntrospect.o \
  "$DIR/build/derived/Build/Products/Release"/AsyncXPCConnection.o \
  "$DIR/build/derived/Build/Products/Release"/DequeModule.o \
  "$DIR/build/derived/Build/Products/Release"/HeapModule.o \
  "$DIR/build/derived/Build/Products/Release"/InternalCollectionsUtilities.o \
  "$DIR/build/derived/Build/Products/Release"/BitCollections.o \
  "$DIR/build/derived/Build/Products/Release"/HashTreeCollections.o \
  "$DIR/build/derived/Build/Products/Release"/Collections.o \
  "$DIR/build/derived/Build/Products/Release"/_LottieStub.o \
  "$DIR/build/derived/Build/Products/Release"/_RopeModule.o \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -rpath -Xlinker "$DIR/mediaremote-adapter" \
  -Xlinker -rpath -Xlinker "$DIR/build/derived/Build/Products/Release"

echo "==> Compilation SUCCESSFUL!"
