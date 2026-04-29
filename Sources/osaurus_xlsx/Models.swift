import Foundation

// MARK: - Workbook

final class Workbook: @unchecked Sendable {
  let id: String
  var sheets: [Sheet] = []
  var sourcePath: String?  // If read from file

  init(id: String = UUID().uuidString) {
    self.id = id
  }

  /// Get a sheet by name (case-insensitive)
  func sheet(named name: String) -> Sheet? {
    sheets.first { $0.name.lowercased() == name.lowercased() }
  }

  /// Add a new sheet and return it
  @discardableResult
  func addSheet(name: String) -> Sheet {
    let sheet = Sheet(name: name)
    sheets.append(sheet)
    return sheet
  }
}

// MARK: - Sheet State

enum SheetState: String {
  case visible
  case hidden
  case veryHidden
  case unknown

  init(rawOOXMLValue: String?) {
    switch rawOOXMLValue {
    case nil, "", "visible":
      self = .visible
    case "hidden":
      self = .hidden
    case "veryHidden":
      self = .veryHidden
    default:
      self = .unknown
    }
  }

  var ooxmlValue: String? {
    switch self {
    case .hidden, .veryHidden:
      return rawValue
    case .visible, .unknown:
      return nil
    }
  }
}

// MARK: - Sheet

final class Sheet: @unchecked Sendable {
  let id: String
  var name: String
  var rows: [UInt: [Cell]] = [:]  // row number (1-based) -> cells
  var state: SheetState = .visible
  var declaredDimension: String?
  var mergedRanges: [String] = []

  init(id: String = UUID().uuidString, name: String) {
    self.id = id
    self.name = name
  }

  /// Get a cell by reference (e.g. "A1")
  func getCell(_ ref: String) -> Cell? {
    guard let parsed = parseCellReference(ref) else { return nil }
    guard let rowCells = rows[parsed.row] else { return nil }
    let col = columnNumber(from: parsed.column)
    return rowCells.first { $0.column == col }
  }

  /// Set a cell value by reference (e.g. "A1")
  func setCell(_ ref: String, value: CellValue) {
    guard let parsed = parseCellReference(ref) else { return }
    let col = columnNumber(from: parsed.column)
    let cell = Cell(reference: ref.uppercased(), column: col, value: value)

    if rows[parsed.row] != nil {
      // Remove existing cell at same column if present
      rows[parsed.row]?.removeAll { $0.column == col }
      rows[parsed.row]?.append(cell)
    } else {
      rows[parsed.row] = [cell]
    }
  }

  /// Get all row numbers sorted
  var sortedRowNumbers: [UInt] {
    rows.keys.sorted()
  }

  /// Get max column number across all rows
  var maxColumn: UInt {
    var maxCol: UInt = 0
    for (_, cells) in rows {
      for cell in cells {
        maxCol = max(maxCol, cell.column)
      }
    }
    return maxCol
  }

  /// Get max row number
  var maxRow: UInt {
    rows.keys.max() ?? 0
  }

  /// Number of non-empty cells retained in the sparse model.
  var nonEmptyCellCount: Int {
    rows.values.reduce(0) { $0 + $1.count }
  }

  /// Number of formula cells retained in the sparse model.
  var formulaCount: Int {
    var count = 0
    for cells in rows.values {
      for cell in cells {
        if case .formula = cell.value {
          count += 1
        }
      }
    }
    return count
  }

  /// Compact used range for summaries and tool output.
  var usedRange: String {
    var rangeMaxRow = maxRow
    var rangeMaxColumn = maxColumn

    for range in mergedRanges {
      guard let parsed = parseRange(range) else { continue }
      rangeMaxRow = max(rangeMaxRow, parsed.start.row, parsed.end.row)
      rangeMaxColumn = max(
        rangeMaxColumn,
        columnNumber(from: parsed.start.column),
        columnNumber(from: parsed.end.column)
      )
    }

    if rangeMaxRow > 0 && rangeMaxColumn > 0 {
      return "A1:\(cellReference(column: rangeMaxColumn, row: rangeMaxRow))"
    }
    return declaredDimension ?? "A1"
  }

  /// Delete a row and shift subsequent rows up
  func deleteRow(_ rowNum: UInt) {
    rows.removeValue(forKey: rowNum)
    // Shift rows above down by 1
    let affectedRows = rows.keys.filter { $0 > rowNum }.sorted()
    for r in affectedRows {
      if let cells = rows.removeValue(forKey: r) {
        let newRow = r - 1
        let updatedCells = cells.map { cell in
          Cell(
            reference: cellReference(column: cell.column, row: newRow),
            column: cell.column,
            value: cell.value
          )
        }
        rows[newRow] = updatedCells
      }
    }
  }

  /// Delete a column and shift subsequent columns left
  func deleteColumn(_ colNum: UInt) {
    for (rowNum, cells) in rows {
      var newCells: [Cell] = []
      for cell in cells {
        if cell.column == colNum {
          continue  // skip deleted column
        } else if cell.column > colNum {
          let newCol = cell.column - 1
          newCells.append(
            Cell(
              reference: cellReference(column: newCol, row: rowNum),
              column: newCol,
              value: cell.value
            ))
        } else {
          newCells.append(cell)
        }
      }
      rows[rowNum] = newCells.isEmpty ? nil : newCells
    }
    // Remove empty rows
    rows = rows.filter { !$0.value.isEmpty }
  }
}

// MARK: - Cell

struct Cell {
  var reference: String  // "A1", "B2"
  var column: UInt  // 1-based column number
  var value: CellValue
  var styleIndex: Int? = nil
}

// MARK: - CellValue

enum CellValue {
  case string(String)
  case number(Double)
  case boolean(Bool)
  case formula(String)
  case empty

  var typeString: String {
    switch self {
    case .string: return "string"
    case .number: return "number"
    case .boolean: return "boolean"
    case .formula: return "formula"
    case .empty: return "empty"
    }
  }

  var displayString: String {
    switch self {
    case .string(let s): return s
    case .number(let d):
      if d == d.rounded() && abs(d) < 1e15 {
        return String(Int(d))
      }
      return String(d)
    case .boolean(let b): return b ? "TRUE" : "FALSE"
    case .formula(let f): return f
    case .empty: return ""
    }
  }
}

// MARK: - XLSX Errors

enum XLSXError: Error, CustomStringConvertible {
  case zipFailed(String)
  case unzipFailed(String)
  case invalidFile(String)
  case parseError(String)
  case fileExists(String)

  var description: String {
    switch self {
    case .zipFailed(let msg): return "ZIP packaging failed: \(msg)"
    case .unzipFailed(let msg): return "Unzip failed: \(msg)"
    case .invalidFile(let msg): return "Invalid XLSX file: \(msg)"
    case .parseError(let msg): return "Parse error: \(msg)"
    case .fileExists(let msg): return "File exists: \(msg)"
    }
  }
}
