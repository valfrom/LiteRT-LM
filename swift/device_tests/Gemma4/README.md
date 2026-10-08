# Gemma 4 device regressions

Requires Xcode, XcodeGen, Bazel 7.6.1, Git LFS and an unlocked physical iPhone.
The model is not checked in. Set `GEMMA4_MODEL_BUNDLE` to the Gemma 4 E2B bundle
containing `gemma-4-E2B-it.litertlm`.

Build frameworks with `swiftpm/build_release_artifacts.sh`, overriding `OUT_DIR`,
`WORK_DIR`, `BAZEL_OUTPUT_USER_ROOT`, `BAZEL_OUTPUT_BASE` and `BAZEL_LINK_PREFIX`
to directories under `/Volumes/XBOX/tmp/`. Extract each resulting XCFramework
archive into one directory and set `LITERT_FRAMEWORK_ROOT` to that directory.

```sh
xcodegen generate --spec swift/device_tests/Gemma4/project.yml
xcodebuild -project swift/device_tests/Gemma4/LiteRTValidation.xcodeproj \
  -scheme LiteRTValidation -destination 'platform=iOS,name=iPhone16Plus' \
  -derivedDataPath /Volumes/XBOX/tmp/tmp/LiteRT-LM/gemma4-validation/DerivedData \
  -resultBundlePath /Volumes/XBOX/tmp/tmp/LiteRT-LM/gemma4-validation/Results.xcresult \
  -allowProvisioningUpdates test
```

Tests cover text generation/tokenization, explicit modality flags, real CPU/GPU
vision inputs, visual budgets, float32, deferred prefill, cloning, JSON schema
constraints with CPU sampling, and cancellation while paused followed by a new conversation on the same engine.
Vision requests retain GPU language inference. When Metal cannot initialize the
vision encoder, Apple builds log the failure and retry only that encoder on CPU.
The 70-token regression exercises Metal without that fallback on iPhone16Plus.

Each run logs free disk space, engine startup timing and generated answers.
The same on-device cache is shared between tests. No cache is deleted by tests.
