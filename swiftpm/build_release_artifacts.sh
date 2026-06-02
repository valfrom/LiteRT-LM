#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-eval_pause}"
OUT_DIR="${OUT_DIR:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/release-artifacts/$TAG}"
WORK_DIR="${WORK_DIR:-$OUT_DIR/work}"
BAZEL_OUTPUT_BASE="${BAZEL_OUTPUT_BASE:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/bazel-output-base}"
BAZEL_LINK_PREFIX="${BAZEL_LINK_PREFIX:-/Volumes/XBOX/tmp/LiteRT-LM/eval_pause/bazel-links/}"
BAZEL_VERSION="$(bazel --version)"

if [ "$BAZEL_VERSION" != "bazel 7.6.1" ]; then
  echo "Expected bazel 7.6.1, got $BAZEL_VERSION" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$WORK_DIR" "$(dirname "$BAZEL_LINK_PREFIX")"

cd "$ROOT"
bazel --output_base="$BAZEL_OUTPUT_BASE" build --symlink_prefix="$BAZEL_LINK_PREFIX" //swift:CLiteRTLM
cp "$BAZEL_LINK_PREFIX/bin/swift/CLiteRTLM.xcframework.zip" "$OUT_DIR/CLiteRTLM.xcframework.zip"

for name in GemmaModelConstraintProvider LiteRt LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
  xcodebuild -create-xcframework \
    -library "$ROOT/prebuilt/macos_arm64/lib${name}.dylib" \
    -output "$WORK_DIR/${name}.xcframework"
  (cd "$WORK_DIR" && zip -r -X "$OUT_DIR/${name}.xcframework.zip" "${name}.xcframework") >/dev/null
done

cd "$OUT_DIR"
for file in *.xcframework.zip; do
  printf '%s %s\n' "$file" "$(swift package compute-checksum "$file")"
done | tee checksums.txt
