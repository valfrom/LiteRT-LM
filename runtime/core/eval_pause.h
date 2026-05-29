// Copyright 2026 The ODML Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef THIRD_PARTY_ODML_LITERT_LM_RUNTIME_CORE_EVAL_PAUSE_H_
#define THIRD_PARTY_ODML_LITERT_LM_RUNTIME_CORE_EVAL_PAUSE_H_

#include <atomic>
#include <condition_variable>
#include <mutex>

#include "absl/status/status.h"  // from @com_google_absl

namespace litert::lm {

class EvalPauseController {
 public:
  void Pause();
  void Resume();
  void Notify();
  absl::Status WaitIfPaused(std::atomic<bool>* cancelled = nullptr);
  bool IsPaused() const;

 private:
  mutable std::mutex mutex_;
  std::condition_variable condition_;
  bool paused_ = false;
};

class EvalPauseCancellationScope {
 public:
  explicit EvalPauseCancellationScope(std::atomic<bool>* cancelled);
  ~EvalPauseCancellationScope();

 private:
  std::atomic<bool>* previous_;
};

EvalPauseController& GlobalEvalPauseController();

}  // namespace litert::lm

#endif  // THIRD_PARTY_ODML_LITERT_LM_RUNTIME_CORE_EVAL_PAUSE_H_
