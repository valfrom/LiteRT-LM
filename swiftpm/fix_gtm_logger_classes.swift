//
//  fix_gtm_logger_classes.swift
//  LiteRT-LM
//
//  Created by Valerii Ivanov on 13.08.2026.
//  Copyright © 2026 TapMediaLtd. All rights reserved.
//

import Foundation

enum FixError: Error {
  case missingInput
  case replacementFailed(String)
}

func fixGTMLoggerClasses(at path: String) throws {
  let url = URL(fileURLWithPath: path)
  let prefixes: [String: (String, String, String)] = [
    "CLiteRTLM": ("LRtLog", "LCG", "LCS"),
    "GemmaModelConstraintProvider": ("LGcLog", "LGG", "LGS"),
    "LiteRt": ("LCoLog", "LRG", "LRS"),
    "LiteRtMetalAccelerator": ("LMaLog", "LMG", "LMS"),
    "LiteRtTopKMetalSampler": ("LSaLog", "LSG", "LSS"),
  ]
  guard let prefix = prefixes[url.lastPathComponent] else {
    throw FixError.replacementFailed(path)
  }
  let output = Pipe()
  let inspection = Process()
  inspection.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
  inspection.arguments = ["-ov", path]
  inspection.standardOutput = output
  try inspection.run()
  let listing = output.fileHandleForReading.readDataToEndOfFile()
  inspection.waitUntilExit()
  guard inspection.terminationStatus == 0,
    let text = String(data: listing, encoding: .utf8)
  else {
    throw FixError.replacementFailed(path)
  }
  let expression = try NSRegularExpression(
    pattern: #"\bname\s+0x[0-9a-fA-F]+\s+((?:GTMLog|GIP|SRL|GSC)[A-Za-z0-9_]+)"#)
  let names = Set(expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
  let replacements = names.sorted { $0.count > $1.count }.map { name in
    var renamed = name.replacingOccurrences(of: "GTMLog", with: prefix.0)
    for (old, new) in [("GIP", prefix.1), ("SRL", prefix.2), ("GSC", String(prefix.1.prefix(2)) + "X")] {
      if renamed.hasPrefix(old) {
        renamed.replaceSubrange(renamed.startIndex..<renamed.index(renamed.startIndex, offsetBy: old.count), with: new)
      }
    }
    return (name, renamed)
  }
  var data = try Data(contentsOf: url)
  var replacementCount = 0

  for (old, new) in replacements {
    let source = Data(old.utf8)
    let replacement = Data(new.utf8)
    var searchStart = data.startIndex
    while searchStart < data.endIndex,
      let range = data.range(of: source, options: [], in: searchStart..<data.endIndex)
    {
      data.replaceSubrange(range, with: replacement)
      searchStart = range.upperBound
      replacementCount += 1
    }
    if data.range(of: source) != nil {
      throw FixError.replacementFailed(path)
    }
  }

  if replacementCount > 0 {
    try data.write(to: url)
  }
  print("Renamed \(replacementCount) embedded class occurrences in \(path)")
}

do {
  let paths = Array(CommandLine.arguments.dropFirst())
  if paths.isEmpty {
    throw FixError.missingInput
  }
  for path in paths {
    try fixGTMLoggerClasses(at: path)
  }
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
