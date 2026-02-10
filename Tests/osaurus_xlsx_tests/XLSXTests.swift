import Foundation
import Testing

@testable import osaurus_xlsx

// MARK: - Column Letter/Number Conversion Tests

@Suite("Column Conversion")
struct ColumnConversionTests {
  @Test("columnLetter: basic letters A-Z")
  func columnLetterBasic() {
    #expect(columnLetter(from: 1) == "A")
    #expect(columnLetter(from: 2) == "B")
    #expect(columnLetter(from: 26) == "Z")
  }

  @Test("columnLetter: multi-letter columns AA, AZ, BA")
  func columnLetterMulti() {
    #expect(columnLetter(from: 27) == "AA")
    #expect(columnLetter(from: 52) == "AZ")
    #expect(columnLetter(from: 53) == "BA")
    #expect(columnLetter(from: 702) == "ZZ")
    #expect(columnLetter(from: 703) == "AAA")
  }

  @Test("columnNumber: basic letters A-Z")
  func columnNumberBasic() {
    #expect(columnNumber(from: "A") == 1)
    #expect(columnNumber(from: "B") == 2)
    #expect(columnNumber(from: "Z") == 26)
  }

  @Test("columnNumber: multi-letter columns")
  func columnNumberMulti() {
    #expect(columnNumber(from: "AA") == 27)
    #expect(columnNumber(from: "AZ") == 52)
    #expect(columnNumber(from: "BA") == 53)
    #expect(columnNumber(from: "ZZ") == 702)
    #expect(columnNumber(from: "AAA") == 703)
  }

  @Test("columnNumber: case insensitive")
  func columnNumberCaseInsensitive() {
    #expect(columnNumber(from: "a") == 1)
    #expect(columnNumber(from: "aa") == 27)
  }

  @Test("Round-trip: number -> letter -> number")
  func roundTrip() {
    for n: UInt in 1...100 {
      let letter = columnLetter(from: n)
      let back = columnNumber(from: letter)
      #expect(back == n, "Round-trip failed for \(n) -> \(letter) -> \(back)")
    }
  }
}

// MARK: - Cell Reference Parsing Tests

@Suite("Cell References")
struct CellReferenceTests {
  @Test("parseCellReference: valid references")
  func parseValid() {
    let a1 = parseCellReference("A1")
    #expect(a1?.column == "A")
    #expect(a1?.row == 1)

    let z99 = parseCellReference("Z99")
    #expect(z99?.column == "Z")
    #expect(z99?.row == 99)

    let aa100 = parseCellReference("AA100")
    #expect(aa100?.column == "AA")
    #expect(aa100?.row == 100)
  }

  @Test("parseCellReference: case insensitive")
  func parseCaseInsensitive() {
    let result = parseCellReference("b5")
    #expect(result?.column == "B")
    #expect(result?.row == 5)
  }

  @Test("parseCellReference: invalid references")
  func parseInvalid() {
    #expect(parseCellReference("") == nil)
    #expect(parseCellReference("A") == nil)
    #expect(parseCellReference("1") == nil)
    #expect(parseCellReference("A0") == nil)
    #expect(parseCellReference("1A") == nil)
    #expect(parseCellReference("A1B") == nil)
  }

  @Test("parseRange: valid range")
  func parseRangeValid() {
    let range = parseRange("A1:D10")
    #expect(range?.start.column == "A")
    #expect(range?.start.row == 1)
    #expect(range?.end.column == "D")
    #expect(range?.end.row == 10)
  }

  @Test("parseRange: invalid range")
  func parseRangeInvalid() {
    #expect(parseRange("A1") == nil)
    #expect(parseRange("A1:") == nil)
    #expect(parseRange(":B2") == nil)
    #expect(parseRange("") == nil)
  }

  @Test("cellReference: builds correct string")
  func buildCellReference() {
    #expect(cellReference(column: 1, row: 1) == "A1")
    #expect(cellReference(column: 26, row: 99) == "Z99")
    #expect(cellReference(column: 27, row: 1) == "AA1")
  }
}

// MARK: - XML/JSON Escaping Tests

@Suite("Escaping")
struct EscapingTests {
  @Test("xmlEscape: special characters")
  func xmlEscapeSpecial() {
    #expect(xmlEscape("a&b") == "a&amp;b")
    #expect(xmlEscape("<tag>") == "&lt;tag&gt;")
    #expect(xmlEscape("\"quoted\"") == "&quot;quoted&quot;")
    #expect(xmlEscape("it's") == "it&apos;s")
    #expect(xmlEscape("plain") == "plain")
  }

  @Test("jsonEscape: special characters")
  func jsonEscapeSpecial() {
    #expect(jsonEscape("line1\nline2") == "line1\\nline2")
    #expect(jsonEscape("tab\there") == "tab\\there")
    #expect(jsonEscape("back\\slash") == "back\\\\slash")
    #expect(jsonEscape("say \"hi\"") == "say \\\"hi\\\"")
  }

  @Test("jsonError: valid JSON")
  func jsonErrorFormat() {
    let result = jsonError("something broke")
    #expect(result.contains("\"error\""))
    #expect(result.contains("something broke"))
  }
}

// MARK: - CellValue Tests

@Suite("CellValue")
struct CellValueTests {
  @Test("typeString returns correct type")
  func typeStrings() {
    #expect(CellValue.string("hi").typeString == "string")
    #expect(CellValue.number(42).typeString == "number")
    #expect(CellValue.boolean(true).typeString == "boolean")
    #expect(CellValue.formula("=SUM(A1:A5)").typeString == "formula")
    #expect(CellValue.empty.typeString == "empty")
  }

  @Test("displayString: integers display without decimals")
  func displayInteger() {
    #expect(CellValue.number(42).displayString == "42")
    #expect(CellValue.number(0).displayString == "0")
    #expect(CellValue.number(-10).displayString == "-10")
  }

  @Test("displayString: decimals preserved")
  func displayDecimal() {
    #expect(CellValue.number(3.14).displayString == "3.14")
  }

  @Test("displayString: booleans")
  func displayBoolean() {
    #expect(CellValue.boolean(true).displayString == "TRUE")
    #expect(CellValue.boolean(false).displayString == "FALSE")
  }

  @Test("displayString: formula")
  func displayFormula() {
    #expect(CellValue.formula("=SUM(A1:A5)").displayString == "=SUM(A1:A5)")
  }

  @Test("displayString: empty")
  func displayEmpty() {
    #expect(CellValue.empty.displayString == "")
  }
}

// MARK: - Model Tests

@Suite("Models")
struct ModelTests {
  @Test("Workbook: add and find sheets")
  func workbookSheets() {
    let wb = Workbook()
    wb.addSheet(name: "Sheet1")
    wb.addSheet(name: "Sheet2")

    #expect(wb.sheets.count == 2)
    #expect(wb.sheet(named: "Sheet1") != nil)
    #expect(wb.sheet(named: "sheet1") != nil)  // case insensitive
    #expect(wb.sheet(named: "Sheet3") == nil)
  }

  @Test("Sheet: set and get cells")
  func sheetCells() {
    let sheet = Sheet(name: "Test")
    sheet.setCell("A1", value: .string("Hello"))
    sheet.setCell("B2", value: .number(42))

    let a1 = sheet.getCell("A1")
    #expect(a1 != nil)
    if case .string(let s) = a1?.value {
      #expect(s == "Hello")
    } else {
      Issue.record("Expected string value")
    }

    let b2 = sheet.getCell("B2")
    #expect(b2 != nil)
    if case .number(let d) = b2?.value {
      #expect(d == 42)
    } else {
      Issue.record("Expected number value")
    }
  }

  @Test("Sheet: overwrite cell")
  func sheetOverwrite() {
    let sheet = Sheet(name: "Test")
    sheet.setCell("A1", value: .string("Old"))
    sheet.setCell("A1", value: .string("New"))

    let a1 = sheet.getCell("A1")
    if case .string(let s) = a1?.value {
      #expect(s == "New")
    } else {
      Issue.record("Expected overwritten value")
    }
    // Should only have 1 cell in row 1
    #expect(sheet.rows[1]?.count == 1)
  }

  @Test("Sheet: maxRow and maxColumn")
  func sheetDimensions() {
    let sheet = Sheet(name: "Test")
    sheet.setCell("C5", value: .string("x"))
    sheet.setCell("A1", value: .string("y"))

    #expect(sheet.maxRow == 5)
    #expect(sheet.maxColumn == 3)
  }

  @Test("Sheet: deleteRow shifts rows up")
  func deleteRow() {
    let sheet = Sheet(name: "Test")
    sheet.setCell("A1", value: .string("Row1"))
    sheet.setCell("A2", value: .string("Row2"))
    sheet.setCell("A3", value: .string("Row3"))

    sheet.deleteRow(2)

    #expect(sheet.getCell("A1") != nil)
    // Row 3 should have shifted to row 2
    let shifted = sheet.getCell("A2")
    if case .string(let s) = shifted?.value {
      #expect(s == "Row3")
    } else {
      Issue.record("Expected Row3 to shift to row 2")
    }
    #expect(sheet.maxRow == 2)
  }

  @Test("Sheet: deleteColumn shifts columns left")
  func deleteColumn() {
    let sheet = Sheet(name: "Test")
    sheet.setCell("A1", value: .string("ColA"))
    sheet.setCell("B1", value: .string("ColB"))
    sheet.setCell("C1", value: .string("ColC"))

    sheet.deleteColumn(2)  // delete column B

    let a1 = sheet.getCell("A1")
    if case .string(let s) = a1?.value {
      #expect(s == "ColA")
    } else {
      Issue.record("Column A should remain")
    }

    // Column C should have shifted to B
    let b1 = sheet.getCell("B1")
    if case .string(let s) = b1?.value {
      #expect(s == "ColC")
    } else {
      Issue.record("Column C should shift to B")
    }

    #expect(sheet.maxColumn == 2)
  }
}

// MARK: - Value Auto-Detection Tests

@Suite("Value Detection")
struct ValueDetectionTests {
  @Test("detectCellValue: numbers")
  func detectNumbers() {
    if case .number(let d) = detectCellValue("42") {
      #expect(d == 42)
    } else {
      Issue.record("Expected number")
    }

    if case .number(let d) = detectCellValue("3.14") {
      #expect(d == 3.14)
    } else {
      Issue.record("Expected decimal")
    }

    if case .number(let d) = detectCellValue("-100") {
      #expect(d == -100)
    } else {
      Issue.record("Expected negative number")
    }
  }

  @Test("detectCellValue: formulas")
  func detectFormulas() {
    if case .formula(let f) = detectCellValue("=SUM(A1:A5)") {
      #expect(f == "=SUM(A1:A5)")
    } else {
      Issue.record("Expected formula")
    }
  }

  @Test("detectCellValue: booleans")
  func detectBooleans() {
    if case .boolean(let b) = detectCellValue("true") {
      #expect(b == true)
    } else {
      Issue.record("Expected true")
    }

    if case .boolean(let b) = detectCellValue("false") {
      #expect(b == false)
    } else {
      Issue.record("Expected false")
    }
  }

  @Test("detectCellValue: strings")
  func detectStrings() {
    if case .string(let s) = detectCellValue("Hello World") {
      #expect(s == "Hello World")
    } else {
      Issue.record("Expected string")
    }
  }

  @Test("detectCellValue: type hint override")
  func detectWithHint() {
    // Force "42" as string
    if case .string(let s) = detectCellValue("42", typeHint: "string") {
      #expect(s == "42")
    } else {
      Issue.record("Expected string with hint")
    }

    // Force formula without = prefix
    if case .formula(let f) = detectCellValue("SUM(A1:A5)", typeHint: "formula") {
      #expect(f == "=SUM(A1:A5)")
    } else {
      Issue.record("Expected formula with hint")
    }
  }
}

// MARK: - Writer + Reader Round-Trip Tests

@Suite("Round-Trip")
struct RoundTripTests {
  @Test("Write and read back: strings and numbers")
  func roundTripBasic() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Data")
    sheet.setCell("A1", value: .string("Name"))
    sheet.setCell("B1", value: .string("Age"))
    sheet.setCell("A2", value: .string("Alice"))
    sheet.setCell("B2", value: .number(30))
    sheet.setCell("A3", value: .string("Bob"))
    sheet.setCell("B3", value: .number(25))

    let tempPath = NSTemporaryDirectory() + "test_basic_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    #expect(FileManager.default.fileExists(atPath: tempPath))

    let loaded = try XLSXReader.read(from: tempPath)
    #expect(loaded.sheets.count == 1)
    #expect(loaded.sheets[0].name == "Data")

    let s = loaded.sheets[0]
    // Check strings
    if case .string(let v) = s.getCell("A1")?.value {
      #expect(v == "Name")
    } else {
      Issue.record("A1 should be 'Name'")
    }
    if case .string(let v) = s.getCell("A2")?.value {
      #expect(v == "Alice")
    } else {
      Issue.record("A2 should be 'Alice'")
    }
    // Check numbers
    if case .number(let v) = s.getCell("B2")?.value {
      #expect(v == 30)
    } else {
      Issue.record("B2 should be 30")
    }
    if case .number(let v) = s.getCell("B3")?.value {
      #expect(v == 25)
    } else {
      Issue.record("B3 should be 25")
    }
  }

  @Test("Write and read back: booleans")
  func roundTripBooleans() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Bools")
    sheet.setCell("A1", value: .boolean(true))
    sheet.setCell("A2", value: .boolean(false))

    let tempPath = NSTemporaryDirectory() + "test_bool_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)
    let s = loaded.sheets[0]

    if case .boolean(let v) = s.getCell("A1")?.value {
      #expect(v == true)
    } else {
      Issue.record("A1 should be true")
    }
    if case .boolean(let v) = s.getCell("A2")?.value {
      #expect(v == false)
    } else {
      Issue.record("A2 should be false")
    }
  }

  @Test("Write and read back: formulas")
  func roundTripFormulas() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Formulas")
    sheet.setCell("A1", value: .number(10))
    sheet.setCell("A2", value: .number(20))
    sheet.setCell("A3", value: .formula("=SUM(A1:A2)"))

    let tempPath = NSTemporaryDirectory() + "test_formula_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)
    let s = loaded.sheets[0]

    if case .formula(let f) = s.getCell("A3")?.value {
      #expect(f == "=SUM(A1:A2)")
    } else {
      Issue.record("A3 should be formula =SUM(A1:A2)")
    }
  }

  @Test("Write and read back: multiple sheets")
  func roundTripMultiSheet() throws {
    let wb = Workbook()
    let s1 = wb.addSheet(name: "Sheet1")
    s1.setCell("A1", value: .string("First"))
    let s2 = wb.addSheet(name: "Sheet2")
    s2.setCell("A1", value: .string("Second"))
    let s3 = wb.addSheet(name: "Sheet3")
    s3.setCell("A1", value: .string("Third"))

    let tempPath = NSTemporaryDirectory() + "test_multi_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)

    #expect(loaded.sheets.count == 3)
    #expect(loaded.sheets.map { $0.name } == ["Sheet1", "Sheet2", "Sheet3"])

    if case .string(let v) = loaded.sheet(named: "Sheet2")?.getCell("A1")?.value {
      #expect(v == "Second")
    } else {
      Issue.record("Sheet2 A1 should be 'Second'")
    }
  }

  @Test("Write and read back: special characters")
  func roundTripSpecialChars() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Special")
    sheet.setCell("A1", value: .string("Hello & World"))
    sheet.setCell("A2", value: .string("<tag>value</tag>"))
    sheet.setCell("A3", value: .string("Line1\nLine2"))
    sheet.setCell("A4", value: .string("Quote \"here\""))

    let tempPath = NSTemporaryDirectory() + "test_special_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)
    let s = loaded.sheets[0]

    if case .string(let v) = s.getCell("A1")?.value {
      #expect(v == "Hello & World")
    } else {
      Issue.record("A1 should handle & character")
    }
    if case .string(let v) = s.getCell("A2")?.value {
      #expect(v == "<tag>value</tag>")
    } else {
      Issue.record("A2 should handle angle brackets")
    }
  }

  @Test("Write and read back: empty sheet")
  func roundTripEmptySheet() throws {
    let wb = Workbook()
    wb.addSheet(name: "Empty")

    let tempPath = NSTemporaryDirectory() + "test_empty_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)

    #expect(loaded.sheets.count == 1)
    #expect(loaded.sheets[0].name == "Empty")
    #expect(loaded.sheets[0].rows.isEmpty)
  }

  @Test("readSheetNames: returns sheet names without full parse")
  func readSheetNames() throws {
    let wb = Workbook()
    wb.addSheet(name: "Sales")
    wb.addSheet(name: "Expenses")
    wb.addSheet(name: "Summary")

    let tempPath = NSTemporaryDirectory() + "test_names_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let names = try XLSXReader.readSheetNames(from: tempPath)

    #expect(names == ["Sales", "Expenses", "Summary"])
  }

  @Test("Write and read back: decimal numbers")
  func roundTripDecimals() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Decimals")
    sheet.setCell("A1", value: .number(3.14159))
    sheet.setCell("A2", value: .number(0.001))
    sheet.setCell("A3", value: .number(-99.99))

    let tempPath = NSTemporaryDirectory() + "test_decimal_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)
    let s = loaded.sheets[0]

    if case .number(let v) = s.getCell("A1")?.value {
      #expect(abs(v - 3.14159) < 0.0001)
    } else {
      Issue.record("A1 should be 3.14159")
    }
    if case .number(let v) = s.getCell("A3")?.value {
      #expect(abs(v - (-99.99)) < 0.01)
    } else {
      Issue.record("A3 should be -99.99")
    }
  }

  @Test("Large column references: beyond Z")
  func roundTripLargeColumns() throws {
    let wb = Workbook()
    let sheet = wb.addSheet(name: "Wide")
    sheet.setCell("A1", value: .string("First"))
    sheet.setCell("AA1", value: .string("Col27"))
    sheet.setCell("AZ1", value: .string("Col52"))

    let tempPath = NSTemporaryDirectory() + "test_wide_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    try XLSXWriter.write(workbook: wb, to: tempPath)
    let loaded = try XLSXReader.read(from: tempPath)
    let s = loaded.sheets[0]

    if case .string(let v) = s.getCell("AA1")?.value {
      #expect(v == "Col27")
    } else {
      Issue.record("AA1 should be 'Col27'")
    }
    if case .string(let v) = s.getCell("AZ1")?.value {
      #expect(v == "Col52")
    } else {
      Issue.record("AZ1 should be 'Col52'")
    }
  }
}

// MARK: - Tool Integration Tests

@Suite("Tool Integration")
struct ToolIntegrationTests {

  /// Helper to simulate a tool call with JSON payload
  private func makePayload(_ dict: [String: Any]) -> String {
    // Build JSON manually for test payloads
    var parts: [String] = []
    for (key, value) in dict {
      switch value {
      case let s as String:
        parts.append(
          "\"\(key)\": \"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        )
      case let i as Int:
        parts.append("\"\(key)\": \(i)")
      case let b as Bool:
        parts.append("\"\(key)\": \(b ? "true" : "false")")
      case let arr as [[String: String]]:
        let items = arr.map { dict in
          let innerParts = dict.map { k, v in "\"\(k)\": \"\(v)\"" }
          return "{\(innerParts.joined(separator: ", "))}"
        }
        parts.append("\"\(key)\": [\(items.joined(separator: ", "))]")
      case let arr as [[String]]:
        let items = arr.map { row in
          let vals = row.map { "\"\($0)\"" }
          return "[\(vals.joined(separator: ", "))]"
        }
        parts.append("\"\(key)\": [\(items.joined(separator: ", "))]")
      case let arr as [Any]:
        // Handle array of sheet defs
        if let sheetDefs = arr as? [[String: Any]] {
          let items = sheetDefs.map { def -> String in
            var defParts: [String] = []
            for (k, v) in def {
              if let s = v as? String {
                defParts.append("\"\(k)\": \"\(s)\"")
              } else if let headers = v as? [String] {
                let h = headers.map { "\"\($0)\"" }.joined(separator: ", ")
                defParts.append("\"\(k)\": [\(h)]")
              } else if let rows = v as? [[String]] {
                let r = rows.map { row in
                  let vals = row.map { "\"\($0)\"" }
                  return "[\(vals.joined(separator: ", "))]"
                }.joined(separator: ", ")
                defParts.append("\"\(k)\": [\(r)]")
              }
            }
            return "{\(defParts.joined(separator: ", "))}"
          }
          parts.append("\"\(key)\": [\(items.joined(separator: ", "))]")
        }
      default:
        break
      }
    }
    return "{\(parts.joined(separator: ", "))}"
  }

  @Test("create_xlsx + save_xlsx + read_xlsx round-trip")
  func createSaveRead() throws {
    var workbooks: [String: Workbook] = [:]
    let createTool = CreateXlsxTool()
    let saveTool = SaveXlsxTool()
    let readTool = ReadXlsxTool()

    // Create
    let createPayload = """
      {"sheets": [{"name": "Employees", "headers": ["Name", "Department", "Salary"], "rows": [["Alice", "Engineering", "120000"], ["Bob", "Marketing", "95000"]]}]}
      """
    let createResult = createTool.run(args: createPayload, workbooks: &workbooks)
    #expect(!createResult.contains("\"error\""))
    #expect(createResult.contains("workbook_id"))

    // Extract workbook_id
    let wbId = workbooks.keys.first!

    // Save
    let tempPath = NSTemporaryDirectory() + "test_tool_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let savePayload = "{\"workbook_id\": \"\(wbId)\", \"path\": \"\(tempPath)\"}"
    let saveResult = saveTool.run(args: savePayload, workbooks: &workbooks)
    #expect(!saveResult.contains("\"error\""))
    #expect(FileManager.default.fileExists(atPath: tempPath))

    // Read back
    let readPayload = "{\"path\": \"\(tempPath)\"}"
    let readResult = readTool.run(args: readPayload, workbooks: &workbooks)
    #expect(!readResult.contains("\"error\""))
    #expect(readResult.contains("Employees"))
    #expect(readResult.contains("Alice"))
    #expect(readResult.contains("Engineering"))
    #expect(readResult.contains("120000"))
  }

  @Test("write_cells: adds cells to workbook")
  func writeCells() {
    var workbooks: [String: Workbook] = [:]
    let createTool = CreateXlsxTool()
    let writeTool = WriteCellsTool()

    let createPayload = """
      {"sheets": [{"name": "Sheet1"}]}
      """
    _ = createTool.run(args: createPayload, workbooks: &workbooks)
    let wbId = workbooks.keys.first!

    let writePayload = """
      {"workbook_id": "\(wbId)", "sheet_name": "Sheet1", "cells": [{"ref": "A1", "value": "Hello"}, {"ref": "B1", "value": "42"}, {"ref": "C1", "value": "=A1"}]}
      """
    let writeResult = writeTool.run(args: writePayload, workbooks: &workbooks)
    #expect(!writeResult.contains("\"error\""))
    #expect(writeResult.contains("\"cells_written\": 3"))

    let sheet = workbooks[wbId]!.sheets[0]
    if case .string(let v) = sheet.getCell("A1")?.value {
      #expect(v == "Hello")
    } else {
      Issue.record("A1 should be 'Hello'")
    }
    if case .number(let v) = sheet.getCell("B1")?.value {
      #expect(v == 42)
    } else {
      Issue.record("B1 should be 42")
    }
    if case .formula = sheet.getCell("C1")?.value {
      // ok
    } else {
      Issue.record("C1 should be a formula")
    }
  }

  @Test("write_cells: creates sheet if not exists")
  func writeCellsCreatesSheet() {
    var workbooks: [String: Workbook] = [:]
    let createTool = CreateXlsxTool()
    let writeTool = WriteCellsTool()

    _ = createTool.run(
      args: "{\"sheets\": [{\"name\": \"Sheet1\"}]}", workbooks: &workbooks)
    let wbId = workbooks.keys.first!

    let writePayload = """
      {"workbook_id": "\(wbId)", "sheet_name": "NewSheet", "cells": [{"ref": "A1", "value": "test"}]}
      """
    let result = writeTool.run(args: writePayload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(workbooks[wbId]!.sheets.count == 2)
    #expect(workbooks[wbId]!.sheet(named: "NewSheet") != nil)
  }

  @Test("list_sheets: returns sheet names")
  func listSheets() throws {
    var workbooks: [String: Workbook] = [:]
    let listTool = ListSheetsTool()

    let wb = Workbook()
    wb.addSheet(name: "Alpha")
    wb.addSheet(name: "Beta")

    let tempPath = NSTemporaryDirectory() + "test_list_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }
    try XLSXWriter.write(workbook: wb, to: tempPath)

    let payload = "{\"path\": \"\(tempPath)\"}"
    let result = listTool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(result.contains("Alpha"))
    #expect(result.contains("Beta"))
    #expect(result.contains("\"count\": 2"))
  }

  @Test("get_cell_value: retrieves specific cell")
  func getCellValue() {
    var workbooks: [String: Workbook] = [:]

    let wb = Workbook()
    let sheet = wb.addSheet(name: "Data")
    sheet.setCell("A1", value: .string("Hello"))
    sheet.setCell("B1", value: .number(99))
    workbooks[wb.id] = wb

    let tool = GetCellValueTool()
    let payload = "{\"workbook_id\": \"\(wb.id)\", \"sheet_name\": \"Data\", \"cell\": \"B1\"}"
    let result = tool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(result.contains("99"))
    #expect(result.contains("number"))
  }

  @Test("xlsx_to_csv: exports CSV text")
  func xlsxToCsv() throws {
    var workbooks: [String: Workbook] = [:]

    let wb = Workbook()
    let sheet = wb.addSheet(name: "Data")
    sheet.setCell("A1", value: .string("Name"))
    sheet.setCell("B1", value: .string("Age"))
    sheet.setCell("A2", value: .string("Alice"))
    sheet.setCell("B2", value: .number(30))

    let tempPath = NSTemporaryDirectory() + "test_csv_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }
    try XLSXWriter.write(workbook: wb, to: tempPath)

    let tool = XlsxToCsvTool()
    let payload = "{\"path\": \"\(tempPath)\"}"
    let result = tool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(result.contains("Name"))
    #expect(result.contains("Alice"))
    #expect(result.contains("30"))
  }

  @Test("csv_to_xlsx: imports CSV data")
  func csvToXlsx() {
    var workbooks: [String: Workbook] = [:]
    let tool = CsvToXlsxTool()

    let payload =
      "{\"csv_data\": \"Name,Age\\nAlice,30\\nBob,25\", \"has_header\": true, \"sheet_name\": \"People\"}"
    let result = tool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(result.contains("People"))
    #expect(result.contains("\"row_count\": 3"))

    let wbId = workbooks.keys.first!
    let sheet = workbooks[wbId]!.sheet(named: "People")!

    // Header should be string
    if case .string(let v) = sheet.getCell("A1")?.value {
      #expect(v == "Name")
    } else {
      Issue.record("A1 should be 'Name' (header)")
    }

    // Data should be auto-detected
    if case .number(let v) = sheet.getCell("B2")?.value {
      #expect(v == 30)
    } else {
      Issue.record("B2 should be number 30")
    }
  }

  @Test("modify_xlsx: batch operations")
  func modifyXlsx() {
    var workbooks: [String: Workbook] = [:]

    let wb = Workbook()
    let sheet = wb.addSheet(name: "Data")
    sheet.setCell("A1", value: .string("Old"))
    sheet.setCell("A2", value: .string("Keep"))
    sheet.setCell("A3", value: .string("Row3"))
    workbooks[wb.id] = wb

    let tool = ModifyXlsxTool()
    let payload = """
      {"workbook_id": "\(wb.id)", "sheet_name": "Data", "operations": [{"type": "set_cell", "ref": "A1", "value": "New"}, {"type": "set_formula", "ref": "B1", "formula": "=SUM(C1:C10)"}, {"type": "add_sheet", "name": "Summary"}]}
      """
    let result = tool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""))
    #expect(result.contains("\"operations_applied\": 3"))

    // Verify modifications
    if case .string(let v) = sheet.getCell("A1")?.value {
      #expect(v == "New")
    } else {
      Issue.record("A1 should be 'New'")
    }
    if case .formula = sheet.getCell("B1")?.value {
      // ok
    } else {
      Issue.record("B1 should be a formula")
    }
    #expect(wb.sheets.count == 2)
    #expect(wb.sheet(named: "Summary") != nil)
  }

  @Test("read_xlsx: reads q4_sales_report.xlsx with inline strings and absolute Target paths")
  func readQ4SalesReport() throws {
    // This file has:
    // 1. xmlns:r declared on <sheet> element (not root <workbook>)
    // 2. Relationship Target with absolute path "/xl/worksheets/sheet1.xml"
    // 3. All cells use inlineStr (t="inlineStr") or numeric (t="n") types
    var workbooks: [String: Workbook] = [:]
    let readTool = ReadXlsxTool()

    // Find the test file relative to the package root
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // XLSXTests.swift -> osaurus_xlsx_tests/
      .deletingLastPathComponent()  // osaurus_xlsx_tests/ -> Tests/
      .deletingLastPathComponent()  // Tests/ -> package root
    let xlsxPath = packageRoot.appendingPathComponent("q4_sales_report.xlsx").path

    guard FileManager.default.fileExists(atPath: xlsxPath) else {
      Issue.record("q4_sales_report.xlsx not found at \(xlsxPath)")
      return
    }

    let payload = "{\"path\": \"\(xlsxPath)\"}"
    let result = readTool.run(args: payload, workbooks: &workbooks)
    #expect(!result.contains("\"error\""), "read_xlsx returned error: \(result)")
    #expect(result.contains("\"sheet_count\": 1"))
    #expect(result.contains("Q4 2025 Report"))
    #expect(result.contains("Acme Corp"))
    #expect(result.contains("North America"))
    #expect(result.contains("1580000"))

    // Verify the workbook was stored
    let wbId = workbooks.keys.first!
    let wb = workbooks[wbId]!
    #expect(wb.sheets.count == 1)
    #expect(wb.sheets[0].name == "Q4 2025 Report")

    // Verify specific cells
    let sheet = wb.sheets[0]
    if case .string(let v) = sheet.getCell("A1")?.value {
      #expect(v == "Acme Corp - Q4 2025 Sales Report")
    } else {
      Issue.record("A1 should be the title string")
    }
    if case .number(let v) = sheet.getCell("E5")?.value {
      #expect(v == 1_580_000)
    } else {
      Issue.record("E5 should be 1580000")
    }
    // Verify formula cells
    if case .formula(let f) = sheet.getCell("B9")?.value {
      #expect(f == "=SUM(B5:B8)")
    } else {
      Issue.record("B9 should be formula =SUM(B5:B8)")
    }
  }

  @Test("Error handling: file not found")
  func errorFileNotFound() {
    var workbooks: [String: Workbook] = [:]
    let tool = ReadXlsxTool()
    let result = tool.run(
      args: "{\"path\": \"/nonexistent/file.xlsx\"}", workbooks: &workbooks)
    #expect(result.contains("\"error\""))
    #expect(result.contains("not found"))
  }

  @Test("Error handling: workbook not found")
  func errorWorkbookNotFound() {
    var workbooks: [String: Workbook] = [:]
    let tool = GetCellValueTool()
    let result = tool.run(
      args: "{\"workbook_id\": \"fake-id\", \"sheet_name\": \"Sheet1\", \"cell\": \"A1\"}",
      workbooks: &workbooks)
    #expect(result.contains("\"error\""))
    #expect(result.contains("not found"))
  }

  @Test("Error handling: sheet not found")
  func errorSheetNotFound() {
    var workbooks: [String: Workbook] = [:]

    let wb = Workbook()
    wb.addSheet(name: "Data")
    workbooks[wb.id] = wb

    let tool = GetCellValueTool()
    let result = tool.run(
      args:
        "{\"workbook_id\": \"\(wb.id)\", \"sheet_name\": \"NonExistent\", \"cell\": \"A1\"}",
      workbooks: &workbooks)
    #expect(result.contains("\"error\""))
    #expect(result.contains("not found"))
  }

  @Test("Path validation: rejects traversal")
  func pathTraversal() {
    let result = validatePath("../../etc/passwd", workingDirectory: "/Users/test/project")
    if case .failure(let msg) = result {
      #expect(msg.contains("outside"))
    } else {
      Issue.record("Should reject path traversal")
    }
  }

  @Test("Path validation: allows relative paths")
  func pathRelative() {
    let result = validatePath("data/file.xlsx", workingDirectory: "/Users/test/project")
    if case .success(let p) = result {
      #expect(p == "/Users/test/project/data/file.xlsx")
    } else {
      Issue.record("Should allow relative paths")
    }
  }

  @Test("Path validation: allows absolute paths")
  func pathAbsolute() {
    let result = validatePath("/absolute/path.xlsx", workingDirectory: nil)
    if case .success(let p) = result {
      #expect(p == "/absolute/path.xlsx")
    } else {
      Issue.record("Should allow absolute paths without working dir")
    }
  }

  @Test("Full end-to-end: create, modify, save, read, export CSV")
  func endToEnd() throws {
    var workbooks: [String: Workbook] = [:]

    // 1. Create
    let createTool = CreateXlsxTool()
    let createResult = createTool.run(
      args: """
        {"sheets": [{"name": "Sales", "headers": ["Product", "Price", "Qty"], "rows": [["Widget", "9.99", "100"], ["Gadget", "24.99", "50"]]}]}
        """,
      workbooks: &workbooks)
    #expect(!createResult.contains("\"error\""))
    let wbId = workbooks.keys.first!

    // 2. Modify: add formula
    let modTool = ModifyXlsxTool()
    _ = modTool.run(
      args: """
        {"workbook_id": "\(wbId)", "sheet_name": "Sales", "operations": [{"type": "set_formula", "ref": "D2", "formula": "=B2*C2"}, {"type": "set_formula", "ref": "D3", "formula": "=B3*C3"}]}
        """,
      workbooks: &workbooks)

    // 3. Save
    let tempPath = NSTemporaryDirectory() + "test_e2e_\(UUID().uuidString).xlsx"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let saveTool = SaveXlsxTool()
    let saveResult = saveTool.run(
      args: "{\"workbook_id\": \"\(wbId)\", \"path\": \"\(tempPath)\"}",
      workbooks: &workbooks)
    #expect(!saveResult.contains("\"error\""))

    // 4. Read back
    let readTool = ReadXlsxTool()
    let readResult = readTool.run(
      args: "{\"path\": \"\(tempPath)\"}",
      workbooks: &workbooks)
    #expect(!readResult.contains("\"error\""))
    #expect(readResult.contains("Widget"))
    #expect(readResult.contains("formula"))

    // 5. Export CSV
    let csvTool = XlsxToCsvTool()
    let csvResult = csvTool.run(
      args: "{\"path\": \"\(tempPath)\"}",
      workbooks: &workbooks)
    #expect(!csvResult.contains("\"error\""))
    #expect(csvResult.contains("Widget"))
    #expect(csvResult.contains("9.99"))
  }
}
