import Foundation

// MARK: - Shared Decodable Types

struct FolderContext: Decodable {
  let working_directory: String
}

// MARK: - Path Validation

enum PathResult {
  case success(String)
  case failure(String)
}

func validatePath(_ path: String, workingDirectory: String?) -> PathResult {
  guard let workDir = workingDirectory else {
    if path.hasPrefix("/") {
      return .success(path)
    }
    return .failure("No working directory context. Please select a folder in Osaurus Agent Mode.")
  }

  let absolutePath: String
  if path.hasPrefix("/") {
    absolutePath = path
  } else {
    absolutePath = "\(workDir)/\(path)"
  }

  let resolved = URL(fileURLWithPath: absolutePath).standardized.path
  guard resolved.hasPrefix(workDir) else {
    return .failure("Path is outside the working directory")
  }

  return .success(resolved)
}

// MARK: - Helper: Sheet to JSON

func sheetToJSON(
  _ sheet: Sheet,
  range: (start: (column: String, row: UInt), end: (column: String, row: UInt))? = nil
) -> String {
  let startCol: UInt = range.map { columnNumber(from: $0.start.column) } ?? 1
  let endCol: UInt = range.map { columnNumber(from: $0.end.column) } ?? sheet.maxColumn
  let startRow: UInt = range?.start.row ?? 1
  let endRow: UInt = range?.end.row ?? sheet.maxRow

  var rowsJSON: [String] = []
  for rowNum in sheet.sortedRowNumbers {
    if rowNum < startRow || rowNum > endRow { continue }
    guard let cells = sheet.rows[rowNum] else { continue }

    var cellsJSON: [String] = []
    for cell in cells.sorted(by: { $0.column < $1.column }) {
      if cell.column < startCol || cell.column > endCol { continue }
      let valStr = jsonEscape(cell.value.displayString)
      var fields = [
        "\"ref\": \"\(cell.reference)\"",
        "\"type\": \"\(cell.value.typeString)\"",
        "\"value\": \"\(valStr)\"",
      ]
      if let styleIndex = cell.styleIndex {
        fields.append("\"style_id\": \(styleIndex)")
      }
      cellsJSON.append("{\(fields.joined(separator: ", "))}")
    }

    if !cellsJSON.isEmpty {
      rowsJSON.append("{\"row\": \(rowNum), \"cells\": [\(cellsJSON.joined(separator: ", "))]}")
    }
  }

  return "[\(rowsJSON.joined(separator: ", "))]"
}

func sheetSummaryJSON(_ sheet: Sheet) -> String {
  let mergedRanges = sheet.mergedRanges.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", ")
  return """
    {"name": "\(jsonEscape(sheet.name))", "state": "\(sheet.state.rawValue)", "used_range": "\(jsonEscape(sheet.usedRange))", "row_count": \(sheet.maxRow), "column_count": \(sheet.maxColumn), "non_empty_cell_count": \(sheet.nonEmptyCellCount), "formula_count": \(sheet.formulaCount), "merged_ranges": [\(mergedRanges)]}
    """
}

func workbookWarnings(_ workbook: Workbook) -> [String] {
  var warnings: [String] = []
  if workbook.sourcePath != nil {
    warnings.append(
      "Saving a loaded workbook rewrites a minimal XLSX package; styles, charts, comments, and other unsupported workbook parts may not be preserved."
    )
  }
  if workbook.sheets.contains(where: { !$0.mergedRanges.isEmpty }) {
    warnings.append("Merged ranges are preserved by this plugin, but only cell values are modeled.")
  }
  return warnings
}

// MARK: - Helper: Auto-detect CellValue from string

func detectCellValue(_ value: String, typeHint: String? = nil) -> CellValue {
  if let hint = typeHint?.lowercased() {
    switch hint {
    case "number":
      if let d = Double(value) { return .number(d) }
      return .string(value)
    case "boolean", "bool":
      return .boolean(value.lowercased() == "true" || value == "1")
    case "formula":
      return .formula(value.hasPrefix("=") ? value : "=\(value)")
    case "string":
      return .string(value)
    default:
      break
    }
  }

  // Auto-detect
  if value.hasPrefix("=") {
    return .formula(value)
  }
  if let d = Double(value) {
    return .number(d)
  }
  let lower = value.lowercased()
  if lower == "true" || lower == "false" {
    return .boolean(lower == "true")
  }
  return .string(value)
}

// MARK: - Tool: read_xlsx

struct ReadXlsxTool {
  let name = "read_xlsx"

  struct Args: Decodable {
    let path: String
    let sheet_name: String?
    let range: String?
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "File not found: \(input.path)")
    }

    do {
      let workbook = try XLSXReader.read(from: absolutePath)
      workbooks[workbook.id] = workbook

      let parsedRange: (start: (column: String, row: UInt), end: (column: String, row: UInt))?
      if let rangeStr = input.range {
        guard let parsed = parseRange(rangeStr) else {
          return Envelope.failure(
            .invalidArgs, "Invalid range format: \(rangeStr). Expected format: A1:D10")
        }
        parsedRange = parsed
      } else {
        parsedRange = nil
      }

      var sheetsJSON: [String] = []
      for sheet in workbook.sheets {
        if let name = input.sheet_name, sheet.name.lowercased() != name.lowercased() {
          continue
        }
        let rowsJSON = sheetToJSON(sheet, range: parsedRange)
        sheetsJSON.append(
          "{\"name\": \"\(jsonEscape(sheet.name))\", \"state\": \"\(sheet.state.rawValue)\", \"used_range\": \"\(jsonEscape(sheet.usedRange))\", \"row_count\": \(sheet.maxRow), \"column_count\": \(sheet.maxColumn), \"non_empty_cell_count\": \(sheet.nonEmptyCellCount), \"formula_count\": \(sheet.formulaCount), \"merged_ranges\": [\(sheet.mergedRanges.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))], \"rows\": \(rowsJSON)}"
        )
      }

      return jsonSuccess([
        "workbook_id": workbook.id,
        "sheet_count": workbook.sheets.count,
        "sheets": JSONRaw("[\(sheetsJSON.joined(separator: ", "))]"),
      ])
    } catch {
      return Envelope.failure(.executionError, "Failed to read XLSX: \(error)")
    }
  }
}

// MARK: - Tool: get_cell_value

struct GetCellValueTool {
  let name = "get_cell_value"

  struct Args: Decodable {
    let workbook_id: String
    let sheet_name: String
    let cell: String?
    let range: String?
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(
        .invalidArgs, "Invalid arguments. Required: workbook_id, sheet_name, and cell or range")
    }

    guard let workbook = workbooks[input.workbook_id] else {
      return Envelope.failure(.notFound, "Workbook not found: \(input.workbook_id)")
    }

    guard let sheet = workbook.sheet(named: input.sheet_name) else {
      let available = workbook.sheets.map { $0.name }.joined(separator: ", ")
      return Envelope.failure(
        .notFound, "Sheet not found: \(input.sheet_name). Available: \(available)")
    }

    var cellsJSON: [String] = []

    if let cellRef = input.cell {
      // Single cell
      guard parseCellReference(cellRef) != nil else {
        return Envelope.failure(
          .invalidArgs, "Invalid cell reference: \(cellRef). Expected format: B5")
      }
      if let cell = sheet.getCell(cellRef) {
        cellsJSON.append(
          "{\"ref\": \"\(cell.reference)\", \"type\": \"\(cell.value.typeString)\", \"value\": \"\(jsonEscape(cell.value.displayString))\"}"
        )
      } else {
        cellsJSON.append(
          "{\"ref\": \"\(cellRef.uppercased())\", \"type\": \"empty\", \"value\": \"\"}")
      }
    } else if let rangeStr = input.range {
      // Range of cells
      guard let parsedRange = parseRange(rangeStr) else {
        return Envelope.failure(
          .invalidArgs, "Invalid range format: \(rangeStr). Expected format: A1:D10")
      }
      let rangeJSON = sheetToJSON(sheet, range: parsedRange)
      return jsonSuccess([
        "sheet_name": sheet.name,
        "range": rangeStr,
        "rows": JSONRaw(rangeJSON),
      ])
    } else {
      return Envelope.failure(
        .invalidArgs, "Provide either 'cell' (e.g. \"B5\") or 'range' (e.g. \"A1:C3\")")
    }

    return jsonSuccess([
      "sheet_name": sheet.name,
      "cells": JSONRaw("[\(cellsJSON.joined(separator: ", "))]"),
    ])
  }
}

// MARK: - Tool: list_sheets

struct ListSheetsTool {
  let name = "list_sheets"

  struct Args: Decodable {
    let path: String
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "File not found: \(input.path)")
    }

    do {
      let names = try XLSXReader.readSheetNames(from: absolutePath)
      return jsonSuccess([
        "count": names.count,
        "sheets": names,
      ])
    } catch {
      return Envelope.failure(.executionError, "Failed to read XLSX: \(error)")
    }
  }
}

// MARK: - Tool: xlsx_describe_workbook

struct XlsxDescribeWorkbookTool {
  let name = "xlsx_describe_workbook"

  struct Args: Decodable {
    let path: String
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "File not found: \(input.path)")
    }

    do {
      let workbook = try XLSXReader.read(from: absolutePath)
      workbooks[workbook.id] = workbook
      let sheetsJSON = workbook.sheets.map(sheetSummaryJSON).joined(separator: ", ")
      return jsonSuccess([
        "workbook_id": workbook.id,
        "sheet_count": workbook.sheets.count,
        "sheets": JSONRaw("[\(sheetsJSON)]"),
        "warnings": workbookWarnings(workbook),
      ])
    } catch {
      return Envelope.failure(.executionError, "Failed to describe XLSX: \(error)")
    }
  }
}

// MARK: - Tool: create_xlsx

struct CreateXlsxTool {
  let name = "create_xlsx"

  struct SheetDef: Decodable {
    let name: String
    let headers: [String]?
    let rows: [[String]]?
  }

  struct Args: Decodable {
    let sheets: [SheetDef]
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(
        .invalidArgs, "Invalid arguments. Required: sheets (array of {name, headers?, rows?})")
    }

    guard !input.sheets.isEmpty else {
      return Envelope.failure(.invalidArgs, "Must provide at least one sheet")
    }

    let workbook = Workbook()

    for sheetDef in input.sheets {
      let sheet = workbook.addSheet(name: sheetDef.name)

      var currentRow: UInt = 1

      // Add headers if provided
      if let headers = sheetDef.headers {
        for (colIdx, header) in headers.enumerated() {
          let col = UInt(colIdx + 1)
          let ref = cellReference(column: col, row: currentRow)
          sheet.setCell(ref, value: .string(header))
        }
        currentRow += 1
      }

      // Add rows
      if let rows = sheetDef.rows {
        for row in rows {
          for (colIdx, value) in row.enumerated() {
            let col = UInt(colIdx + 1)
            let ref = cellReference(column: col, row: currentRow)
            sheet.setCell(ref, value: detectCellValue(value))
          }
          currentRow += 1
        }
      }
    }

    workbooks[workbook.id] = workbook

    let sheetNames = workbook.sheets.map { $0.name }
    return jsonSuccess([
      "workbook_id": workbook.id,
      "sheet_count": workbook.sheets.count,
      "sheets": sheetNames,
    ])
  }
}

// MARK: - Tool: write_cells

struct WriteCellsTool {
  let name = "write_cells"

  struct CellWrite: Decodable {
    let ref: String
    let value: String
    let type: String?  // "string", "number", "boolean", "formula"
  }

  struct Args: Decodable {
    let workbook_id: String
    let sheet_name: String
    let cells: [CellWrite]
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid arguments. Required: workbook_id, sheet_name, cells (array of {ref, value})")
    }

    guard let workbook = workbooks[input.workbook_id] else {
      return Envelope.failure(.notFound, "Workbook not found: \(input.workbook_id)")
    }

    // Find or create sheet
    let sheet: Sheet
    if let existing = workbook.sheet(named: input.sheet_name) {
      sheet = existing
    } else {
      sheet = workbook.addSheet(name: input.sheet_name)
    }

    var written = 0
    for cellWrite in input.cells {
      guard parseCellReference(cellWrite.ref) != nil else {
        continue  // skip invalid references
      }
      let cellValue = detectCellValue(cellWrite.value, typeHint: cellWrite.type)
      sheet.setCell(cellWrite.ref, value: cellValue)
      written += 1
    }

    return jsonSuccess([
      "cells_written": written,
      "sheet_name": sheet.name,
      "workbook_id": workbook.id,
    ])
  }
}

// MARK: - Tool: save_xlsx

struct SaveXlsxTool {
  let name = "save_xlsx"

  struct Args: Decodable {
    let workbookID: String
    let path: String
    let overwrite: Bool?
    let dryRun: Bool?
    let _context: FolderContext?

    enum CodingKeys: String, CodingKey {
      case workbookID = "workbook_id"
      case path
      case overwrite
      case dryRun = "dry_run"
      case _context
    }
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: workbook_id, path")
    }

    guard let workbook = workbooks[input.workbookID] else {
      return Envelope.failure(.notFound, "Workbook not found: \(input.workbookID)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    let finalPath = absolutePath.hasSuffix(".xlsx") ? absolutePath : "\(absolutePath).xlsx"
    let exists = FileManager.default.fileExists(atPath: finalPath)
    let warnings = workbookWarnings(workbook)

    if input.dryRun == true {
      return jsonSuccess([
        "dry_run": true,
        "path": finalPath,
        "sheet_count": workbook.sheets.count,
        "would_overwrite": exists,
        "workbook_id": workbook.id,
        "warnings": warnings,
      ])
    }

    do {
      try XLSXWriter.write(workbook: workbook, to: finalPath, overwrite: input.overwrite == true)
      return jsonSuccess([
        "path": finalPath,
        "sheet_count": workbook.sheets.count,
        "workbook_id": workbook.id,
        "warnings": warnings,
      ])
    } catch {
      return Envelope.failure(.executionError, "Failed to save XLSX: \(error)")
    }
  }
}

// MARK: - Tool: xlsx_to_csv

struct XlsxToCsvTool {
  let name = "xlsx_to_csv"

  struct Args: Decodable {
    let path: String
    let sheet_name: String?
    let format: String?  // "csv" or "tsv"
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: path (string)")
    }

    let pathResult = validatePath(input.path, workingDirectory: input._context?.working_directory)
    let absolutePath: String
    switch pathResult {
    case .success(let p): absolutePath = p
    case .failure(let msg): return Envelope.failure(.invalidArgs, msg)
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      return Envelope.failure(.notFound, "File not found: \(input.path)")
    }

    do {
      let workbook = try XLSXReader.read(from: absolutePath)
      let delimiter = (input.format?.lowercased() == "tsv") ? "\t" : ","

      // Find the target sheet
      let sheet: Sheet
      if let name = input.sheet_name {
        guard let s = workbook.sheet(named: name) else {
          let available = workbook.sheets.map { $0.name }.joined(separator: ", ")
          return Envelope.failure(.notFound, "Sheet not found: \(name). Available: \(available)")
        }
        sheet = s
      } else {
        guard let s = workbook.sheets.first else {
          return Envelope.failure(.notFound, "Workbook has no sheets")
        }
        sheet = s
      }

      let maxCol = sheet.maxColumn
      let maxRow = sheet.maxRow

      guard maxRow > 0 && maxCol > 0 else {
        return jsonSuccess([
          "data": "",
          "row_count": 0,
          "column_count": 0,
          "sheet_name": sheet.name,
        ])
      }

      var csvLines: [String] = []
      for rowNum: UInt in 1...maxRow {
        var values: [String] = []
        for colNum: UInt in 1...maxCol {
          let ref = cellReference(column: colNum, row: rowNum)
          if let cell = sheet.getCell(ref) {
            let val = cell.value.displayString
            // Escape for CSV: quote if contains delimiter, newline, or quote
            if val.contains(delimiter) || val.contains("\n") || val.contains("\"") {
              values.append("\"\(val.replacingOccurrences(of: "\"", with: "\"\""))\"")
            } else {
              values.append(val)
            }
          } else {
            values.append("")
          }
        }
        csvLines.append(values.joined(separator: delimiter))
      }

      let csvData = csvLines.joined(separator: "\n")

      return jsonSuccess([
        "data": csvData,
        "row_count": Int(maxRow),
        "column_count": Int(maxCol),
        "sheet_name": sheet.name,
      ])
    } catch {
      return Envelope.failure(.executionError, "Failed to read XLSX: \(error)")
    }
  }
}

// MARK: - Tool: csv_to_xlsx

struct CsvToXlsxTool {
  let name = "csv_to_xlsx"

  struct Args: Decodable {
    let csv_data: String
    let sheet_name: String?
    let has_header: Bool?
    let delimiter: String?
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments. Required: csv_data (string)")
    }

    let delimiter: Character
    if let d = input.delimiter, !d.isEmpty {
      delimiter = d == "\\t" || d == "tab" ? "\t" : d.first!
    } else {
      delimiter = ","
    }

    let sheetName = input.sheet_name ?? "Sheet1"
    let workbook = Workbook()
    let sheet = workbook.addSheet(name: sheetName)

    let lines = parseCSVLines(input.csv_data, delimiter: delimiter)

    var rowNum: UInt = 1
    for line in lines {
      for (colIdx, value) in line.enumerated() {
        let col = UInt(colIdx + 1)
        let ref = cellReference(column: col, row: rowNum)
        if input.has_header == true && rowNum == 1 {
          sheet.setCell(ref, value: .string(value))
        } else {
          sheet.setCell(ref, value: detectCellValue(value))
        }
      }
      rowNum += 1
    }

    workbooks[workbook.id] = workbook

    return jsonSuccess([
      "workbook_id": workbook.id,
      "sheet_name": sheetName,
      "row_count": Int(rowNum - 1),
      "column_count": lines.first?.count ?? 0,
    ])
  }

  /// Parse CSV respecting quoted fields
  private func parseCSVLines(_ text: String, delimiter: Character) -> [[String]] {
    var result: [[String]] = []
    var currentField = ""
    var currentRow: [String] = []
    var inQuotes = false
    var i = text.startIndex

    while i < text.endIndex {
      let ch = text[i]

      if inQuotes {
        if ch == "\"" {
          let next = text.index(after: i)
          if next < text.endIndex && text[next] == "\"" {
            // Escaped quote
            currentField.append("\"")
            i = text.index(after: next)
            continue
          } else {
            inQuotes = false
          }
        } else {
          currentField.append(ch)
        }
      } else {
        if ch == "\"" {
          inQuotes = true
        } else if ch == delimiter {
          currentRow.append(currentField)
          currentField = ""
        } else if ch == "\n" {
          currentRow.append(currentField)
          currentField = ""
          if !currentRow.allSatisfy({ $0.isEmpty }) || !currentRow.isEmpty {
            result.append(currentRow)
          }
          currentRow = []
        } else if ch == "\r" {
          // Skip \r (handle \r\n)
        } else {
          currentField.append(ch)
        }
      }

      i = text.index(after: i)
    }

    // Handle last field/row
    if !currentField.isEmpty || !currentRow.isEmpty {
      currentRow.append(currentField)
      result.append(currentRow)
    }

    return result
  }
}

// MARK: - Tool: modify_xlsx

struct ModifyXlsxTool {
  let name = "modify_xlsx"

  struct Operation: Decodable {
    let type: String
    // set_cell / set_formula
    let ref: String?
    let value: String?
    let formula: String?
    // delete_row
    let row: Int?
    // delete_column
    let column: String?
    // rename_sheet
    let new_name: String?
    // add_sheet
    let name: String?
  }

  struct Args: Decodable {
    let workbook_id: String
    let sheet_name: String?
    let operations: [Operation]
    let _context: FolderContext?
  }

  func run(args: String, workbooks: inout [String: Workbook]) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(
        .invalidArgs,
        "Invalid arguments. Required: workbook_id, operations (array of operation objects)")
    }

    guard let workbook = workbooks[input.workbook_id] else {
      return Envelope.failure(.notFound, "Workbook not found: \(input.workbook_id)")
    }

    // Find target sheet (may be nil for add_sheet operations)
    let targetSheet: Sheet?
    if let sheetName = input.sheet_name {
      targetSheet = workbook.sheet(named: sheetName)
      if targetSheet == nil {
        return Envelope.failure(
          .notFound,
          "Sheet not found: \(sheetName). Available: \(workbook.sheets.map { $0.name }.joined(separator: ", "))"
        )
      }
    } else {
      targetSheet = workbook.sheets.first
    }

    var applied = 0

    for op in input.operations {
      switch op.type {
      case "set_cell":
        guard let sheet = targetSheet, let ref = op.ref, let value = op.value else { continue }
        sheet.setCell(ref, value: detectCellValue(value))
        applied += 1

      case "set_formula":
        guard let sheet = targetSheet, let ref = op.ref, let formula = op.formula else { continue }
        sheet.setCell(ref, value: .formula(formula.hasPrefix("=") ? formula : "=\(formula)"))
        applied += 1

      case "delete_row":
        guard let sheet = targetSheet, let row = op.row, row > 0 else { continue }
        sheet.deleteRow(UInt(row))
        applied += 1

      case "delete_column":
        guard let sheet = targetSheet, let colStr = op.column else { continue }
        let colNum = columnNumber(from: colStr)
        if colNum > 0 {
          sheet.deleteColumn(colNum)
          applied += 1
        }

      case "rename_sheet":
        guard let sheet = targetSheet, let newName = op.new_name else { continue }
        sheet.name = newName
        applied += 1

      case "add_sheet":
        guard let sheetName = op.name else { continue }
        workbook.addSheet(name: sheetName)
        applied += 1

      default:
        continue
      }
    }

    return jsonSuccess([
      "operations_applied": applied,
      "workbook_id": workbook.id,
      "sheet_count": workbook.sheets.count,
    ])
  }
}
