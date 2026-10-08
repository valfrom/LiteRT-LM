# LiteRT-LM v0.18.0 Apple validation

Validated on 8 October 2026 using unlocked iPhone16Plus, iOS 26.5.2 and Xcode 26.5.

The fork merges upstream `v0.18.0` (`b2f686e2`) and retains AMAAI's pause/resume,
modality switches, deferred prefill, cloning, sampler updates and JSON constraints.
Apple accelerator libraries match that release and are packaged as frameworks.
Private Objective-C class identifiers are namespaced per binary during packaging.

## Vision behavior

The upstream Metal encoder still fails texture allocation at default and 280-token
visual budgets on this device. On Apple platforms, failed GPU vision initialization
is logged and retried with a CPU vision encoder. GPU language inference is unchanged.
The 70-token vision test succeeds on Metal without falling back. CPU settings are
owned by the encoder so the retry cannot retain a temporary settings reference.

## Results

| Suite | Passed | Coverage |
| --- | --- | --- |
| Native device harness | 11/11 | Text, tokenization, CPU/GPU image inputs, visual budgets, FP32, modality flags, deferred prefill, cloning, JSON constraints and paused cancellation |
| AMAAI main | 4/4 | Provider text generation, message token counting, explicit text-only control and image understanding |
| AMAAI ios16-compat | 4/4 | Same integration tests using the compatibility branch |

Cancellation is followed by a new conversation on the same engine. Upstream does
not support reusing a cancelled conversation. The native harness shares one cache;
no test deletes caches. See `swift/device_tests/Gemma4/README.md` for reproduction.

## Consumer update

The v0.18 C stream callback receives `(userData, chunk)`. Read text, final state and
errors through `litert_lm_stream_chunk_get_text`, `litert_lm_stream_chunk_is_final`
and `litert_lm_stream_chunk_get_error`. AMAAI updates both adapters alongside the
binary URLs and checksums. Raw C consumers must update their callback adapters too.

Archive hashes are recorded in `swiftpm/checksums.txt`. FM, VR and QR project files
and dependency lockfiles are not changed by this validation.
