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
    
    // The compiler's diagnostics have gone to stdout or stderr depending on the
    // SwiftPM version, so read both through one pipe. Reading before waiting
    // keeps a full pipe buffer from blocking the child forever.
    let outputPipe = Pipe()
    process.standardError = outputPipe
    process.standardOutput = outputPipe
    
    try process.run()
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    
    // SwiftPM colorizes diagnostics even when output is piped, and the escape
    // codes land between the "N: " and "error:" that errorRegex looks for.
    let output = (String(data: outputData, encoding: .utf8) ?? "")
      .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m",
                            with: "",
                            options: .regularExpression)

    // swift build should fail due to invalid input
    if process.terminationStatus == 0 {
      XCTFail("Expected swift build to fail, but it succeeded.\noutput:\n\(output)")
      return
    }
    
    // collect expected-error lines from original source using Swift Regex
    // We parse lines like:
    // /path/to/File.swift:6:21: error: 'buildBlock()' is unavailable: Examples must not be empty
    let outputLines = output.split(whereSeparator: { $0.isNewline })
    let errorLines = outputLines.filter { $0.hasPrefix("/") && $0.contains("error:") }
    
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
    
    if expectedErrors.isEmpty {
      XCTFail("no expected errors found")
      return
    }
    
    let missingErrors = expectedErrors.filter { expected in
      !foundErrors.contains(where: { $0.line == expected.line })
    }
    let unexpectedErrors = foundErrors.filter { found in
      !expectedErrors.contains(where: { $0.line == found.line })
    }
    let sameLineErrors = foundErrors.filter { found in
      expectedErrors.contains(where: { $0.line == found.line })
    }
    let mismatchedErrors = sameLineErrors.filter { sameError in
      let expectedMessage = expectedErrors.first(where: { $0.line == sameError.line })!.message
      return !sameError.message.hasSuffix(expectedMessage)
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
  ///
  /// Comments are roughly in the form apparently used by the Swift
  /// compiler's -verify flag, which isn't available in the distribution verion
  /// of the compiler.
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
