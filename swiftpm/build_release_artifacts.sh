#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-eval_pause}"
OUT_DIR="${OUT_DIR:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/release-artifacts/$TAG}"
WORK_DIR="${WORK_DIR:-$OUT_DIR/work}"
BAZEL_OUTPUT_BASE="${BAZEL_OUTPUT_BASE:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/bazel-output-base}"
BAZEL_LINK_PREFIX="${BAZEL_LINK_PREFIX:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/bazel-links/}"
BAZEL_VERSION="$(bazel --version)"
IOS_MINIMUM_OS_VERSION="16.0"

if [ "$BAZEL_VERSION" != "bazel 7.6.1" ]; then
  echo "Expected bazel 7.6.1, got $BAZEL_VERSION" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$WORK_DIR" "$(dirname "$BAZEL_LINK_PREFIX")"

cd "$ROOT"
bazel --output_base="$BAZEL_OUTPUT_BASE" build --symlink_prefix="$BAZEL_LINK_PREFIX" //swift:CLiteRTLM

CLITERT_WORK_DIR="$WORK_DIR/CLiteRTLM"
mkdir -p "$CLITERT_WORK_DIR"
unzip -q "$BAZEL_LINK_PREFIX/bin/swift/CLiteRTLM.xcframework.zip" -d "$CLITERT_WORK_DIR"

set_platform_metadata() {
  local plist="$1"
  local sdk="$2"
  local supported_platform="$3"
  local sdk_version="$(xcrun --sdk "$sdk" --show-sdk-version)"
  local sdk_build="$(xcrun --sdk "$sdk" --show-sdk-build-version)"
  local xcode_version="$(xcodebuild -version | awk '/^Xcode / {gsub("\\.", "", $2); print $2 "0"}')"
  local xcode_build="$(xcodebuild -version | awk '/Build version/ {print $3}')"

  set_plist_string() {
    local key="$1"
    local value="$2"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  }

  /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string $supported_platform" "$plist"
  set_plist_string BuildMachineOSBuild "$(sw_vers -buildVersion)"
  set_plist_string DTCompiler com.apple.compilers.llvm.clang.1_0
  set_plist_string DTPlatformBuild "$sdk_build"
  set_plist_string DTPlatformName "$sdk"
  set_plist_string DTPlatformVersion "$sdk_version"
  set_plist_string DTSDKBuild "$sdk_build"
  set_plist_string DTSDKName "${sdk}${sdk_version}"
  set_plist_string DTXcode "$xcode_version"
  set_plist_string DTXcodeBuild "$xcode_build"
}

for framework in "$CLITERT_WORK_DIR"/CLiteRTLM.xcframework/*/CLiteRTLM.framework; do
  identifier="$(basename "$(dirname "$framework")")"
  binary="$framework/CLiteRTLM"
  codesign --remove-signature "$binary" 2>/dev/null || true
  install_name_tool -change \
    "@rpath/libGemmaModelConstraintProvider.dylib" \
    "@rpath/GemmaModelConstraintProvider.framework/GemmaModelConstraintProvider" \
    "$binary"
  if [[ "$identifier" = macos-* ]]; then
    set_platform_metadata "$framework/Info.plist" macosx MacOSX
  elif [ "$identifier" = "ios-arm64" ]; then
    set_platform_metadata "$framework/Info.plist" iphoneos iPhoneOS
  else
    set_platform_metadata "$framework/Info.plist" iphonesimulator iPhoneSimulator
  fi
done

(cd "$CLITERT_WORK_DIR" && zip -r -X "$OUT_DIR/CLiteRTLM.xcframework.zip" CLiteRTLM.xcframework) >/dev/null

create_framework() {
  local name="$1"
  local platform="$2"
  local library="$3"
  local sdk="$4"
  local supported_platform="$5"
  local minimum_os_version="$6"
  local framework="$WORK_DIR/frameworks/$platform/$name.framework"
  local binary="$framework/$name"
  local plist="$framework/Info.plist"

  mkdir -p "$framework"
  cp "$library" "$binary"
  codesign --remove-signature "$binary" 2>/dev/null || true
  install_name_tool -id "@rpath/$name.framework/$name" "$binary"
  if [ "$sdk" = "iphoneos" ] || [ "$sdk" = "iphonesimulator" ]; then
    local platform="ios"
    if [ "$sdk" = "iphonesimulator" ]; then
      platform="iossim"
    fi
    local binary_sdk="$(vtool -show-build "$binary" | awk '/sdk/ {print $2; exit}')"
    local versioned_binary="${binary}.versioned"
    vtool -set-build-version "$platform" "$IOS_MINIMUM_OS_VERSION" "$binary_sdk" \
      -replace -output "$versioned_binary" "$binary"
    mv "$versioned_binary" "$binary"
  fi
  plutil -create xml1 "$plist"
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleDevelopmentRegion string en" \
    -c "Add :CFBundleExecutable string $name" \
    -c "Add :CFBundleIdentifier string com.google.ai.edge.litert.$name" \
    -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
    -c "Add :CFBundleName string $name" \
    -c "Add :CFBundlePackageType string FMWK" \
    -c "Add :CFBundleShortVersionString string 1.0" \
    -c "Add :CFBundleSupportedPlatforms array" \
    -c "Add :CFBundleSupportedPlatforms:0 string $supported_platform" \
    -c "Add :CFBundleVersion string 1" \
    -c "Add :MinimumOSVersion string $minimum_os_version" \
    "$plist"
  if [ "$sdk" != "macosx" ]; then
    /usr/libexec/PlistBuddy \
      -c "Add :UIDeviceFamily array" \
      -c "Add :UIDeviceFamily:0 integer 1" \
      -c "Add :UIDeviceFamily:1 integer 2" \
      "$plist"
  fi
  /usr/libexec/PlistBuddy -c "Add :BuildMachineOSBuild string $(sw_vers -buildVersion)" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTPlatformBuild string $(xcrun --sdk "$sdk" --show-sdk-build-version)" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTPlatformName string $sdk" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string $(xcrun --sdk "$sdk" --show-sdk-version)" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTSDKBuild string $(xcrun --sdk "$sdk" --show-sdk-build-version)" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTSDKName string ${sdk}$(xcrun --sdk "$sdk" --show-sdk-version)" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTXcode string $(xcodebuild -version | awk '/^Xcode / {gsub("\\.", "", $2); print $2 "0"}')" "$plist"
  /usr/libexec/PlistBuddy -c "Add :DTXcodeBuild string $(xcodebuild -version | awk '/Build version/ {print $3}')" "$plist"
  printf '%s\n' "$framework"
}

for name in GemmaModelConstraintProvider LiteRt LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
  args=()
  macos_library="$ROOT/prebuilt/macos_arm64/lib${name}.dylib"
  if [ -f "$macos_library" ]; then
    framework="$(create_framework "$name" macos_arm64 "$macos_library" macosx MacOSX 12.0)"
    args+=(-framework "$framework")
  fi
  ios_library="$ROOT/prebuilt/ios_arm64/lib${name}.dylib"
  if [ -f "$ios_library" ]; then
    framework="$(create_framework "$name" ios_arm64 "$ios_library" iphoneos iPhoneOS "$IOS_MINIMUM_OS_VERSION")"
    args+=(-framework "$framework")
  fi
  simulator_library="$ROOT/prebuilt/ios_sim_arm64/lib${name}.dylib"
  if [ -f "$simulator_library" ]; then
    framework="$(create_framework "$name" ios_sim_arm64 "$simulator_library" iphonesimulator iPhoneSimulator "$IOS_MINIMUM_OS_VERSION")"
    args+=(-framework "$framework")
  fi
  xcodebuild -create-xcframework "${args[@]}" -output "$WORK_DIR/${name}.xcframework"
  (cd "$WORK_DIR" && zip -r -X "$OUT_DIR/${name}.xcframework.zip" "${name}.xcframework") >/dev/null
done

cd "$OUT_DIR"
for file in *.xcframework.zip; do
  printf '%s %s\n' "$file" "$(swift package compute-checksum "$file")"
done | tee checksums.txt
