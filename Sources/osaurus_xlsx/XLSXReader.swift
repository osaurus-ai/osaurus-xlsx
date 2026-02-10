import Foundation

// MARK: - XLSX Reader

enum XLSXReader {

  /// Read an XLSX file into a Workbook model
  static func read(from filePath: String) throws -> Workbook {
    let tempDir = NSTemporaryDirectory() + "osaurus_xlsx_read_\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: tempDir)
    }

    try createDirectoryIfNeeded(tempDir)

    // Unzip the XLSX file
    let result = try runProcess("/usr/bin/unzip", arguments: ["-q", "-o", filePath, "-d", tempDir])
    if result.exitCode != 0 {
      throw XLSXError.unzipFailed(result.output)
    }

    // Parse shared strings
    let sharedStrings = try parseSharedStrings(tempDir: tempDir)

    // Parse workbook to get sheet names and rIds
    let sheetEntries = try parseWorkbook(tempDir: tempDir)

    // Parse workbook relationships to map rIds to file paths
    let relMap = try parseWorkbookRels(tempDir: tempDir)

    // Build workbook
    let workbook = Workbook()
    workbook.sourcePath = filePath

    for entry in sheetEntries {
      guard let target = relMap[entry.rId] else { continue }
      let sheetPath = "\(tempDir)/xl/\(target)"
      guard FileManager.default.fileExists(atPath: sheetPath) else { continue }

      let sheet = try parseWorksheet(at: sheetPath, name: entry.name, sharedStrings: sharedStrings)
      workbook.sheets.append(sheet)
    }

    return workbook
  }

  /// Read just the sheet names from an XLSX file (lightweight, no cell parsing)
  static func readSheetNames(from filePath: String) throws -> [String] {
    let tempDir = NSTemporaryDirectory() + "osaurus_xlsx_list_\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: tempDir)
    }

    try createDirectoryIfNeeded(tempDir)

    // Only extract workbook.xml
    let result = try runProcess(
      "/usr/bin/unzip",
      arguments: ["-q", "-o", filePath, "xl/workbook.xml", "-d", tempDir])
    if result.exitCode != 0 {
      throw XLSXError.unzipFailed(result.output)
    }

    let entries = try parseWorkbook(tempDir: tempDir)
    return entries.map { $0.name }
  }

  // MARK: - Shared Strings

  private static func parseSharedStrings(tempDir: String) throws -> [Int: String] {
    let path = "\(tempDir)/xl/sharedStrings.xml"
    guard FileManager.default.fileExists(atPath: path) else {
      return [:]  // No shared strings file is valid
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    var strings: [Int: String] = [:]

    // Find all <si> elements
    guard let siNodes = try? doc.nodes(forXPath: "//*[local-name()='si']") else {
      return [:]
    }

    for (index, node) in siNodes.enumerated() {
      guard let siElement = node as? XMLElement else { continue }

      // Handle simple <si><t>text</t></si>
      if let tNodes = try? siElement.nodes(forXPath: "./*[local-name()='t']"),
        let tNode = tNodes.first
      {
        strings[index] = tNode.stringValue ?? ""
        continue
      }

      // Handle rich text <si><r><t>text1</t></r><r><t>text2</t></r></si>
      if let rNodes = try? siElement.nodes(forXPath: "./*[local-name()='r']") {
        var combined = ""
        for rNode in rNodes {
          if let tNodes = try? rNode.nodes(forXPath: "./*[local-name()='t']"),
            let tNode = tNodes.first
          {
            combined += tNode.stringValue ?? ""
          }
        }
        strings[index] = combined
        continue
      }

      strings[index] = ""
    }

    return strings
  }

  // MARK: - Workbook Parsing

  private struct SheetEntry {
    let name: String
    let rId: String
    let sheetId: Int
  }

  private static func parseWorkbook(tempDir: String) throws -> [SheetEntry] {
    let path = "\(tempDir)/xl/workbook.xml"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XLSXError.invalidFile("Missing workbook.xml")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    var entries: [SheetEntry] = []

    guard let sheetNodes = try? doc.nodes(forXPath: "//*[local-name()='sheet']") else {
      return []
    }

    for node in sheetNodes {
      guard let el = node as? XMLElement else { continue }

      let name = el.attribute(forName: "name")?.stringValue ?? "Sheet"
      let sheetId = Int(el.attribute(forName: "sheetId")?.stringValue ?? "0") ?? 0

      // r:id attribute — Apple's XMLDocument can be inconsistent with namespace-prefixed
      // attributes, so we chain multiple lookup strategies as fallbacks.
      let rId =
        el.attribute(forLocalName: "id", uri: OOXML.nsOfficeDocRelationships)?.stringValue
        ?? el.attribute(forName: "r:id")?.stringValue
        ?? el.attributes?.first(where: {
          $0.localName == "id" && $0.uri == OOXML.nsOfficeDocRelationships
        })?.stringValue
        ?? el.attributes?.first(where: {
          ($0.name?.hasSuffix(":id") == true) || $0.localName == "id"
        })?.stringValue
        ?? ""

      entries.append(SheetEntry(name: name, rId: rId, sheetId: sheetId))
    }

    return entries
  }

  // MARK: - Workbook Relationships

  private static func parseWorkbookRels(tempDir: String) throws -> [String: String] {
    let path = "\(tempDir)/xl/_rels/workbook.xml.rels"
    guard FileManager.default.fileExists(atPath: path) else {
      return [:]
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    var relMap: [String: String] = [:]

    guard let relNodes = try? doc.nodes(forXPath: "//*[local-name()='Relationship']") else {
      return [:]
    }

    for node in relNodes {
      guard let el = node as? XMLElement,
        let rId = el.attribute(forName: "Id")?.stringValue,
        let target = el.attribute(forName: "Target")?.stringValue
      else { continue }

      relMap[rId] = target
    }

    return relMap
  }

  // MARK: - Worksheet Parsing

  private static func parseWorksheet(
    at path: String, name: String, sharedStrings: [Int: String]
  ) throws -> Sheet {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try XMLDocument(data: data, options: [])

    let sheet = Sheet(name: name)

    guard let rowNodes = try? doc.nodes(forXPath: "//*[local-name()='row']") else {
      return sheet
    }

    for rowNode in rowNodes {
      guard let rowEl = rowNode as? XMLElement else { continue }
      let rowNum = UInt(rowEl.attribute(forName: "r")?.stringValue ?? "0") ?? 0
      if rowNum == 0 { continue }

      guard let cellNodes = try? rowEl.nodes(forXPath: "./*[local-name()='c']") else {
        continue
      }

      var cells: [Cell] = []
      for cellNode in cellNodes {
        guard let cellEl = cellNode as? XMLElement else { continue }
        let ref = cellEl.attribute(forName: "r")?.stringValue ?? ""
        let cellType = cellEl.attribute(forName: "t")?.stringValue

        // Get <v> value
        let vValue: String?
        if let vNodes = try? cellEl.nodes(forXPath: "./*[local-name()='v']"),
          let vNode = vNodes.first
        {
          vValue = vNode.stringValue
        } else {
          vValue = nil
        }

        // Get <f> formula
        let formula: String?
        if let fNodes = try? cellEl.nodes(forXPath: "./*[local-name()='f']"),
          let fNode = fNodes.first
        {
          formula = fNode.stringValue
        } else {
          formula = nil
        }

        let cellValue: CellValue

        if let formulaText = formula {
          cellValue = .formula("=\(formulaText)")
        } else {
          switch cellType {
          case "s":
            // Shared string
            if let vStr = vValue, let idx = Int(vStr), let str = sharedStrings[idx] {
              cellValue = .string(str)
            } else {
              cellValue = .empty
            }
          case "b":
            // Boolean
            cellValue = .boolean(vValue == "1")
          case "str", "inlineStr":
            // Inline string
            if cellType == "inlineStr" {
              // Look for <is><t>text</t></is>
              if let isNodes = try? cellEl.nodes(forXPath: ".//*[local-name()='t']"),
                let tNode = isNodes.first
              {
                cellValue = .string(tNode.stringValue ?? "")
              } else {
                cellValue = .string(vValue ?? "")
              }
            } else {
              cellValue = .string(vValue ?? "")
            }
          case "e":
            // Error
            cellValue = .string(vValue ?? "#ERROR!")
          default:
            // Number (no type attribute means numeric)
            if let vStr = vValue, let num = Double(vStr) {
              cellValue = .number(num)
            } else if vValue != nil {
              cellValue = .string(vValue!)
            } else {
              cellValue = .empty
            }
          }
        }

        // Skip empty cells
        if case .empty = cellValue { continue }

        guard let parsed = parseCellReference(ref) else { continue }
        let col = columnNumber(from: parsed.column)
        cells.append(Cell(reference: ref, column: col, value: cellValue))
      }

      if !cells.isEmpty {
        sheet.rows[rowNum] = cells
      }
    }

    return sheet
  }
}
