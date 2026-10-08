//
//  LiteRTDeviceTests.swift
//  LiteRT-LM
//
//  Created by Valerii Ivanov on 08.10.2026.
//  Copyright © 2026 TapMediaLtd. All rights reserved.
//

import XCTest
import UIKit
import CLiteRTLM

final class LiteRTDeviceTests: XCTestCase {
  private func checked(_ pointer: OpaquePointer?, _ operation: String) throws -> OpaquePointer {
    guard let pointer else {
      let detail = litert_lm_get_last_error_message().map { String(cString: $0) } ?? "No native error"
      throw NSError(domain: "LiteRTValidation", code: Int(litert_lm_get_last_error_code()),
                    userInfo: [NSLocalizedDescriptionKey: "\(operation): \(detail)"])
    }
    return pointer
  }

  private func withConversation(vision: String?, visionTokens: Int32? = nil, float32: Bool = false, configure: ((OpaquePointer, OpaquePointer) -> Void)? = nil, run: (OpaquePointer, OpaquePointer) throws -> Void) throws {
    litert_lm_set_min_log_level(0)
    let bundleURL = try XCTUnwrap(Bundle.main.url(forResource: "gemma-4-E2B-it-litert-lm", withExtension: "bundle"))
    let modelURL = bundleURL.appendingPathComponent("gemma-4-E2B-it.litertlm")
    let disk = try FileManager.default.attributesOfFileSystem(forPath: modelURL.path)
    print("LITERT_VALIDATION free_bytes=\(disk[.systemFreeSize] ?? 0)")
    let settings = try checked(litert_lm_engine_settings_create(modelURL.path, "gpu", vision, nil), "settings")
    defer { litert_lm_engine_settings_delete(settings) }
    litert_lm_engine_settings_set_max_num_tokens(settings, 4096)
    litert_lm_engine_settings_set_max_num_images(settings, 1)
    if let visionTokens {
      litert_lm_engine_settings_set_max_vision_tokens_per_image(settings, visionTokens)
    }
    if float32 {
      litert_lm_engine_settings_set_activation_data_type(settings, kLiteRtLmActivationDataTypeFloat32)
    }
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("litert-v018-buffer-fresh", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    litert_lm_engine_settings_set_cache_dir(settings, cache.path)
    let start = ProcessInfo.processInfo.systemUptime
    let engine = try checked(litert_lm_engine_create(settings), "engine")
    defer { litert_lm_engine_delete(engine) }
    print("LITERT_VALIDATION engine vision=\(vision ?? "none") ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
    let session = try checked(litert_lm_session_config_create(), "session config")
    defer { litert_lm_session_config_delete(session) }
    litert_lm_session_config_set_max_output_tokens(session, 80)
    let sampler = try checked(litert_lm_sampler_params_create(kLiteRtLmSamplerTypeTopP), "sampler")
    defer { litert_lm_sampler_params_delete(sampler) }
    litert_lm_sampler_params_set_temperature(sampler, 0)
    litert_lm_sampler_params_set_top_k(sampler, 1)
    litert_lm_sampler_params_set_seed(sampler, 7)
    litert_lm_session_config_set_sampler_params(session, sampler)
    let config = try checked(litert_lm_conversation_config_create(), "conversation config")
    defer { litert_lm_conversation_config_delete(config) }
    litert_lm_conversation_config_set_session_config(config, session)
    litert_lm_conversation_config_set_extra_context(config, "{\"enable_thinking\":false}")
    configure?(config, session)
    let conversation = try checked(litert_lm_conversation_create(engine, config), "conversation")
    defer { litert_lm_conversation_delete(conversation) }
    try run(engine, conversation)
  }

  private func send(_ content: [[String: String]], conversation: OpaquePointer, visionTokens: Int32? = nil, schema: String? = nil) throws -> String {
    let message = try JSONSerialization.data(withJSONObject: ["role": "user", "content": content])
    let json = try XCTUnwrap(String(data: message, encoding: .utf8))
    let args = try checked(litert_lm_conversation_optional_args_create(), "optional args")
    defer { litert_lm_conversation_optional_args_delete(args) }
    if let visionTokens {
      litert_lm_conversation_optional_args_set_visual_token_budget(args, visionTokens)
    }
    if let schema {
      litert_lm_conversation_optional_args_set_json_schema_constraint(args, schema)
    }
    let response = try checked(litert_lm_conversation_send_message(conversation, json, "{\"enable_thinking\":false}", args), "send")
    defer { litert_lm_json_response_delete(response) }
    let string = String(cString: try XCTUnwrap(litert_lm_json_response_get_string(response)))
    print("LITERT_VALIDATION response=\(string)")
    XCTAssertFalse(string.isEmpty)
    return string
  }

  func testTextOnlyGenerationAndTokenization() throws {
    try withConversation(vision: nil) { engine, conversation in
      let tokens = try checked(litert_lm_engine_tokenize(engine, "Say hello."), "tokenize")
      defer { litert_lm_tokenize_result_delete(tokens) }
      XCTAssertGreaterThan(litert_lm_tokenize_result_get_num_tokens(tokens), 0)
      let response = try send([["type": "text", "text": "Say hello."]], conversation: conversation)
      XCTAssertTrue(response.lowercased().contains("hello"))
    }
  }

  func testTextWithGPUVisionInitialized() throws {
    try withConversation(vision: "gpu") { engine, conversation in
      let rendered = try XCTUnwrap(litert_lm_conversation_render_message_to_string(conversation, "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Say hello.\"}]}"))
      let tokens = try checked(litert_lm_engine_tokenize(engine, rendered), "rendered tokenize")
      defer { litert_lm_tokenize_result_delete(tokens) }
      XCTAssertGreaterThan(litert_lm_tokenize_result_get_num_tokens(tokens), 0)
      let response = try send([["type": "text", "text": "Say hello."]], conversation: conversation)
      XCTAssertTrue(response.lowercased().contains("hello"))
    }
  }

  private func checkVision(backend: String, visionTokens: Int32? = nil, float32: Bool = false) throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
      UIColor.red.setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 96, y: 96, width: 320, height: 320))
    }
    let data = try XCTUnwrap(image.pngData())
    try withConversation(vision: backend, visionTokens: visionTokens, float32: float32) { _, conversation in
      let response = try send([
        ["type": "image", "blob": data.base64EncodedString()],
        ["type": "text", "text": "Name the color and shape in this image. Answer briefly."]
      ], conversation: conversation, visionTokens: visionTokens)
      XCTAssertTrue(response.lowercased().contains("red"), response)
      XCTAssertTrue(response.lowercased().contains("circle"), response)
    }
  }

  func testGPUVisionImage() throws {
    try checkVision(backend: "gpu")
  }

  func testCPUVisionImage() throws {
    try checkVision(backend: "cpu")
  }

  func testGPUVision70Tokens() throws {
    try checkVision(backend: "gpu", visionTokens: 70)
  }

  func testGPUVision280Tokens() throws {
    try checkVision(backend: "gpu", visionTokens: 280)
  }

  func testGPUVisionFloat32() throws {
    try checkVision(backend: "gpu", visionTokens: 280, float32: true)
  }

  func testExplicitTextModalitiesSkipVision() throws {
    try withConversation(vision: "gpu", configure: { config, _ in
      litert_lm_conversation_config_set_audio_modality_enabled(config, false)
      litert_lm_conversation_config_set_vision_modality_enabled(config, false)
    }) { _, conversation in
      let response = try send([["type": "text", "text": "Say hello."]], conversation: conversation)
      XCTAssertTrue(response.lowercased().contains("hello"))
    }
  }

  func testDeferredPrefaceAndClone() throws {
    try withConversation(vision: nil, configure: { config, _ in
      litert_lm_conversation_config_set_system_message(config, "[{\"type\":\"text\",\"text\":\"Answer briefly.\"}]")
      litert_lm_conversation_config_set_prefill_preface_on_init(config, true)
      litert_lm_conversation_config_set_defer_prefill_preface_on_init(config, true)
    }) { _, conversation in
      let state = NativeStreamState()
      let context = Unmanaged.passUnretained(state).toOpaque()
      XCTAssertEqual(litert_lm_conversation_prefill_preface_async(conversation, { context, chunk in
        NativeStreamState.receive(context, chunk)
      }, context), 0)
      XCTAssertEqual(state.done.wait(timeout: .now() + 30), .success)
      XCTAssertNil(state.error)
      let clone = try checked(litert_lm_conversation_clone(conversation), "clone")
      defer { litert_lm_conversation_delete(clone) }
      for target in [conversation, clone] {
        let response = try send([["type": "text", "text": "Say hello."]], conversation: target)
        XCTAssertTrue(response.lowercased().contains("hello"))
      }
    }
  }

  func testJSONSchemaWithCPUSampler() throws {
    try withConversation(vision: nil, configure: { config, session in
      litert_lm_session_config_set_use_cpu_sampler(session, true)
      litert_lm_conversation_config_set_session_config(config, session)
      litert_lm_conversation_config_set_enable_json_schema_constraints(config, true)
    }) { _, conversation in
      let schema = "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\",\"enum\":[\"red\"]}},\"required\":[\"color\"],\"additionalProperties\":false}"
      let response = try send([["type": "text", "text": "Return the color blue as JSON."]], conversation: conversation, schema: schema)
      let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
      let content = try XCTUnwrap(root["content"] as? [[String: Any]])
      let text = content.compactMap { $0["text"] as? String }.joined()
      let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
      XCTAssertEqual(value, ["color": "red"])
    }
  }

  func testCancellationWhilePaused() throws {
    try withConversation(vision: nil) { engine, conversation in
      let state = NativeStreamState()
      let context = Unmanaged.passUnretained(state).toOpaque()
      litert_lm_pause_eval()
      defer { litert_lm_resume_eval() }
      let result = litert_lm_conversation_send_message_stream(
        conversation, "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Count to ten.\"}]}", nil, nil,
        { context, chunk in NativeStreamState.receive(context, chunk) }, context)
      XCTAssertEqual(result, 0)
      XCTAssertEqual(state.done.wait(timeout: .now() + 0.1), .timedOut)
      litert_lm_conversation_cancel_process(conversation)
      XCTAssertEqual(state.done.wait(timeout: .now() + 5), .success)
      XCTAssertTrue(state.error?.uppercased().contains("CANCELLED") == true)
      litert_lm_resume_eval()
      let next = try checked(litert_lm_conversation_create(engine, nil), "conversation after cancellation")
      defer { litert_lm_conversation_delete(next) }
      let response = try send([["type": "text", "text": "Say hello."]], conversation: next)
      XCTAssertTrue(response.lowercased().contains("hello"))
    }
  }

}


private final class NativeStreamState {
  let done = DispatchSemaphore(value: 0)
  var error: String?

  static func receive(_ context: UnsafeMutableRawPointer?, _ chunk: OpaquePointer?) {
    guard let context, let chunk else { return }
    let state = Unmanaged<NativeStreamState>.fromOpaque(context).takeUnretainedValue()
    if let error = litert_lm_stream_chunk_get_error(chunk) {
      state.error = String(cString: error)
    }
    if litert_lm_stream_chunk_is_final(chunk) {
      state.done.signal()
    }
  }
}
