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
  let source = Data("GTMLog".utf8)
  let replacement = Data("LRtLog".utf8)
  var data = try Data(contentsOf: url)
  var searchStart = data.startIndex
  var replacementCount = 0

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

  if replacementCount > 0 {
    try data.write(to: url)
  }

  let output = try Data(contentsOf: url)
  if output.range(of: source) != nil {
    throw FixError.replacementFailed(path)
  }

  print("Renamed \(replacementCount) GTMLogger occurrences in \(path)")
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
