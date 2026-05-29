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

#include "runtime/core/eval_pause.h"

namespace litert::lm {
namespace {

thread_local std::atomic<bool>* current_cancelled = nullptr;

}

void EvalPauseController::Pause() {
  std::lock_guard<std::mutex> lock(mutex_);
  paused_ = true;
}

void EvalPauseController::Resume() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    paused_ = false;
  }
  condition_.notify_all();
}

void EvalPauseController::Notify() { condition_.notify_all(); }

absl::Status EvalPauseController::WaitIfPaused(std::atomic<bool>* cancelled) {
  if (cancelled == nullptr) {
    cancelled = current_cancelled;
  }
  std::unique_lock<std::mutex> lock(mutex_);
  condition_.wait(lock, [this, cancelled] {
    return !paused_ || (cancelled != nullptr && cancelled->load());
  });
  if (cancelled != nullptr && cancelled->load()) {
    return absl::CancelledError("Process cancelled.");
  }
  return absl::OkStatus();
}

bool EvalPauseController::IsPaused() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return paused_;
}

EvalPauseCancellationScope::EvalPauseCancellationScope(
    std::atomic<bool>* cancelled)
    : previous_(current_cancelled) {
  current_cancelled = cancelled;
}

EvalPauseCancellationScope::~EvalPauseCancellationScope() {
  current_cancelled = previous_;
}

EvalPauseController& GlobalEvalPauseController() {
  static EvalPauseController controller;
  return controller;
}

}  // namespace litert::lm
