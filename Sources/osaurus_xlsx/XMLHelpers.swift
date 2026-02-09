import Foundation

// MARK: - OOXML SpreadsheetML Namespace Constants

enum OOXML {
  // Namespaces
  static let nsSpreadsheetML =
    "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  static let nsRelationships =
    "http://schemas.openxmlformats.org/package/2006/relationships"
  static let nsContentTypes =
    "http://schemas.openxmlformats.org/package/2006/content-types"
  static let nsOfficeDocRelationships =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  static let nsCoreProps =
    "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
  static let nsDC = "http://purl.org/dc/elements/1.1/"
  static let nsDCTerms = "http://purl.org/dc/terms/"
  static let nsXSI = "http://www.w3.org/2001/XMLSchema-instance"

  // Relationship types
  static let relTypeOfficeDoc =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
  static let relTypeCoreProps =
    "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
  static let relTypeWorksheet =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
  static let relTypeStyles =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
  static let relTypeSharedStrings =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"

  // Content types
  static let contentTypeWorkbook =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
  static let contentTypeWorksheet =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
  static let contentTypeStyles =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"
  static let contentTypeSharedStrings =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"
  static let contentTypeRels =
    "application/vnd.openxmlformats-package.relationships+xml"
  static let contentTypeCoreProps =
    "application/vnd.openxmlformats-package.core-properties+xml"
  static let contentTypeXML = "application/xml"
}

// MARK: - XML Escaping

func xmlEscape(_ s: String) -> String {
  s.replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "'", with: "&apos;")
}

// MARK: - JSON Escaping

func jsonEscape(_ s: String) -> String {
  s.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
    .replacingOccurrences(of: "\r", with: "\\r")
    .replacingOccurrences(of: "\t", with: "\\t")
}

// MARK: - JSON Response Helpers

func jsonSuccess(_ fields: [String: Any]) -> String {
  var parts: [String] = []
  for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
    switch value {
    case let s as String:
      parts.append("\"\(jsonEscape(key))\": \"\(jsonEscape(s))\"")
    case let i as Int:
      parts.append("\"\(jsonEscape(key))\": \(i)")
    case let u as UInt:
      parts.append("\"\(jsonEscape(key))\": \(u)")
    case let d as Double:
      parts.append("\"\(jsonEscape(key))\": \(d)")
    case let b as Bool:
      parts.append("\"\(jsonEscape(key))\": \(b ? "true" : "false")")
    case let arr as [String]:
      let items = arr.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", ")
      parts.append("\"\(jsonEscape(key))\": [\(items)]")
    default:
      if let raw = value as? JSONRaw {
        parts.append("\"\(jsonEscape(key))\": \(raw.value)")
      }
    }
  }
  return "{\(parts.joined(separator: ", "))}"
}

func jsonError(_ message: String) -> String {
  "{\"error\": \"\(jsonEscape(message))\"}"
}

/// Wrapper to pass pre-formatted JSON into jsonSuccess
struct JSONRaw {
  let value: String
  init(_ value: String) { self.value = value }
}

// MARK: - Column Letter/Number Conversion

/// Convert a 1-based column number to Excel column letters (1=A, 26=Z, 27=AA, etc.)
func columnLetter(from number: UInt) -> String {
  var result = ""
  var n = Int(number)
  while n > 0 {
    n -= 1
    let remainder = n % 26
    result = String(UnicodeScalar(65 + remainder)!) + result
    n /= 26
  }
  return result
}

/// Convert Excel column letters to 1-based column number (A=1, Z=26, AA=27, etc.)
func columnNumber(from letters: String) -> UInt {
  var result: UInt = 0
  for ch in letters.uppercased() {
    guard let ascii = ch.asciiValue, ascii >= 65, ascii <= 90 else { continue }
    result = result * 26 + UInt(ascii - 64)
  }
  return result
}

/// Parse a cell reference like "A1" into (column letters, row number)
func parseCellReference(_ ref: String) -> (column: String, row: UInt)? {
  var colPart = ""
  var rowPart = ""
  for ch in ref {
    if ch.isLetter {
      if !rowPart.isEmpty { return nil }  // Letters after digits = invalid
      colPart.append(ch)
    } else if ch.isNumber {
      rowPart.append(ch)
    } else {
      return nil
    }
  }
  guard !colPart.isEmpty, !rowPart.isEmpty, let row = UInt(rowPart), row > 0 else {
    return nil
  }
  return (colPart.uppercased(), row)
}

/// Parse a range like "A1:D10" into start and end references
func parseRange(_ range: String) -> (
  start: (column: String, row: UInt), end: (column: String, row: UInt)
)? {
  let parts = range.split(separator: ":")
  guard parts.count == 2,
    let start = parseCellReference(String(parts[0])),
    let end = parseCellReference(String(parts[1]))
  else {
    return nil
  }
  return (start, end)
}

/// Build a cell reference string from column number (1-based) and row number (1-based)
func cellReference(column: UInt, row: UInt) -> String {
  "\(columnLetter(from: column))\(row)"
}

// MARK: - Process Runner

func runProcess(_ executable: String, arguments: [String], currentDirectory: String? = nil) throws
  -> (output: String, exitCode: Int32)
{
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  if let dir = currentDirectory {
    process.currentDirectoryURL = URL(fileURLWithPath: dir)
  }

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  try process.run()
  process.waitUntilExit()

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let output = String(data: data, encoding: .utf8) ?? ""
  return (output, process.terminationStatus)
}

// MARK: - File Manager Helpers

func createDirectoryIfNeeded(_ path: String) throws {
  try FileManager.default.createDirectory(
    atPath: path,
    withIntermediateDirectories: true,
    attributes: nil
  )
}

func writeFile(_ content: String, to path: String) throws {
  try content.write(toFile: path, atomically: true, encoding: .utf8)
}

func writeData(_ data: Data, to path: String) throws {
  try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - Slide Relationship (reusable for internal rels)

struct FileRelationship {
  let rId: String
  let type: String
  let target: String
}
