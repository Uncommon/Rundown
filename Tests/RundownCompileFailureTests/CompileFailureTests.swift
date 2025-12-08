import XCTest
import RegexBuilder

struct CompileError {
  let line: Int
  let message: String
}

extension CompileError: CustomDebugStringConvertible {
  var debugDescription: String {
    "\(line): \(message)"
  }
}

extension [CompileError] {
  var lines: String {
    self.map(\.debugDescription).joined(separator: "\n")
  }
}

final class InvalidSequencesFixtureTests: XCTestCase {
  let errorRegex = Regex {
      ZeroOrMore(.any)        // path
      ":"
      Capture {
          OneOrMore(.digit)   // line
      } transform: { Int($0)! }
      ":"
      OneOrMore(.digit)       // column (ignored)
      ":"
      OneOrMore(.whitespace)
      "error:"
      OneOrMore(.whitespace)
      Capture {
          OneOrMore(.any)     // message
      }
  }

  func testInvalidSequencesDiagnostics() throws {
    // Resolve the fixture directory relative to this test file's location
    let thisFileURL = URL(fileURLWithPath: #filePath)
    // .../Tests/RundownCompileFailureTests/CompileFailureTests.swift
    // packageRoot = ../../..
    let packageRoot = thisFileURL
      .deletingLastPathComponent() // RundownCompileFailureTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // package root
    let fixtureURL = packageRoot
      .appendingPathComponent("Tests/InvalidSequencesFixture", isDirectory: true)
    let testSourceURL = fixtureURL
      .appendingPathComponent("Sources/InvalidSequences/InvalidSequences.swift")
    
    // Sanity check the path exists
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: fixtureURL.path, isDirectory: &isDir)
    if !exists || !isDir.boolValue {
      XCTFail("InvalidSequencesFixture not found at \(fixtureURL.path)")
      return
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swift", "build"]
    process.currentDirectoryURL = fixtureURL
    
    let stderrPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardError = stderrPipe
    process.standardOutput = stdoutPipe
    
    try process.run()
    process.waitUntilExit()
    
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
    let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
    
    // swift build should fail due to invalid input
    if process.terminationStatus == 0 {
      XCTFail("Expected swift build to fail, but it succeeded.\nstdout:\n\(stdoutString)\nstderr:\n\(stderrString)")
      return
    }
    
    // collect expected-error lines from original source using Swift Regex
    // We parse lines like:
    // /path/to/File.swift:6:21: error: 'buildBlock()' is unavailable: Examples must not be empty
    let stdOutLines = stdoutString.split(whereSeparator: { $0.isNewline })
    let errorLines = stdOutLines.filter { $0.hasPrefix("/") && $0.contains("error:") }
    
    // Parse errors found from compiler output
    let foundErrors: [CompileError] = errorLines.compactMap { lineSubstr in
      let line = String(lineSubstr)

      if let match = line.wholeMatch(of: errorRegex) {
        return CompileError(line: match.output.1,
                            message: String(match.output.2))
      }
      return nil
    }
    
    // Parse expected errors from original source file
    let source = try! String(contentsOfFile: testSourceURL.path, encoding: .utf8)
    let expectedErrors = extractExpectedErrors(from: source)
    
    let missingErrors = expectedErrors.filter { expected in
      !foundErrors.contains(where: { $0.line == expected.line })
    }
    let unexpectedErrors = foundErrors.filter { found in
      !expectedErrors.contains(where: { $0.line == found.line })
    }
    let sameLineErrors = expectedErrors.filter { expected in
      foundErrors.contains(where: { $0.line == expected.line })
    }
    let mismatchedErrors = sameLineErrors.filter { sameError in
      let foundMessage = foundErrors.first(where: { $0.line == sameError.line })!.message
      return !sameError.message.hasSuffix(foundMessage)
    }
    
    XCTAssertTrue(missingErrors.isEmpty, "missing errors:\n\(missingErrors.lines)")
    XCTAssertTrue(unexpectedErrors.isEmpty, "unexpected errors:\n\(unexpectedErrors.lines)")
    XCTAssertTrue(mismatchedErrors.isEmpty, "mismatched errors:\n\(mismatchedErrors.lines)")
  }
  
  /// Parses lines like:
  ///   // expected-error {{some message here}}
  ///
  /// - Parameter source: The full contents of a Swift source file.
  /// - Returns: An array of (lineNumber, messageInsideBraces).
  func extractExpectedErrors(from source: String) -> [CompileError] {
    let regex = Regex {
      "//"
      OneOrMore(.whitespace)
      "expected-error"
      OneOrMore(.whitespace)
      "{{"
      Capture {
        ZeroOrMore {
          NegativeLookahead {
            "}}"
          }
          CharacterClass.any
        }
      }
      "}}"
    }
    
    var results: [CompileError] = []
    
    let lines = source.split(separator: "\n",
                             omittingEmptySubsequences: false)
    
    for (index, line) in lines.enumerated() {
      let lineNumber = index + 1
      let lineString = String(line)
      
      if let match = lineString.firstMatch(of: regex) {
        results.append(.init(line: lineNumber,
                             message: String(match.output.1)))
      }
    }
    
    return results
  }
}
