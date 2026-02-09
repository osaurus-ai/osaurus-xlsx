import Foundation

// MARK: - XLSX Writer

enum XLSXWriter {

  /// Write a workbook to an .xlsx file at the given path
  static func write(workbook: Workbook, to outputPath: String) throws {
    let tempDir = NSTemporaryDirectory() + "osaurus_xlsx_\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: tempDir)
    }

    // Create directory structure
    try createDirectoryIfNeeded(tempDir)
    try createDirectoryIfNeeded("\(tempDir)/_rels")
    try createDirectoryIfNeeded("\(tempDir)/xl")
    try createDirectoryIfNeeded("\(tempDir)/xl/_rels")
    try createDirectoryIfNeeded("\(tempDir)/xl/worksheets")
    try createDirectoryIfNeeded("\(tempDir)/docProps")

    // Build shared string table
    let sharedStrings = buildSharedStringTable(workbook: workbook)

    // Write [Content_Types].xml
    try writeFile(
      generateContentTypesXML(sheetCount: workbook.sheets.count),
      to: "\(tempDir)/[Content_Types].xml")

    // Write _rels/.rels
    try writeFile(generateRootRelsXML(), to: "\(tempDir)/_rels/.rels")

    // Write xl/workbook.xml
    try writeFile(
      generateWorkbookXML(workbook: workbook), to: "\(tempDir)/xl/workbook.xml")

    // Write xl/_rels/workbook.xml.rels
    try writeFile(
      generateWorkbookRelsXML(sheetCount: workbook.sheets.count),
      to: "\(tempDir)/xl/_rels/workbook.xml.rels")

    // Write xl/styles.xml
    try writeFile(generateStylesXML(), to: "\(tempDir)/xl/styles.xml")

    // Write xl/sharedStrings.xml
    try writeFile(
      generateSharedStringsXML(sharedStrings: sharedStrings),
      to: "\(tempDir)/xl/sharedStrings.xml")

    // Write worksheets
    for (idx, sheet) in workbook.sheets.enumerated() {
      let sheetNum = idx + 1
      try writeFile(
        generateWorksheetXML(sheet: sheet, sharedStrings: sharedStrings),
        to: "\(tempDir)/xl/worksheets/sheet\(sheetNum).xml")
    }

    // Write docProps/core.xml
    try writeFile(generateCorePropsXML(), to: "\(tempDir)/docProps/core.xml")

    // Package as ZIP
    if FileManager.default.fileExists(atPath: outputPath) {
      try FileManager.default.removeItem(atPath: outputPath)
    }

    let result = try runProcess(
      "/usr/bin/zip", arguments: ["-r", "-q", outputPath, "."], currentDirectory: tempDir)
    if result.exitCode != 0 {
      throw XLSXError.zipFailed(result.output)
    }
  }

  // MARK: - Shared String Table

  private struct SharedStringTable {
    let strings: [String]  // ordered list of unique strings
    let indexMap: [String: Int]  // string -> index
  }

  private static func buildSharedStringTable(workbook: Workbook) -> SharedStringTable {
    var uniqueStrings: [String] = []
    var indexMap: [String: Int] = [:]

    for sheet in workbook.sheets {
      for (_, cells) in sheet.rows {
        for cell in cells {
          if case .string(let s) = cell.value {
            if indexMap[s] == nil {
              indexMap[s] = uniqueStrings.count
              uniqueStrings.append(s)
            }
          }
        }
      }
    }

    return SharedStringTable(strings: uniqueStrings, indexMap: indexMap)
  }

  // MARK: - Content Types

  private static func generateContentTypesXML(sheetCount: Int) -> String {
    var overrides = ""
    overrides +=
      "  <Override PartName=\"/xl/workbook.xml\" ContentType=\"\(OOXML.contentTypeWorkbook)\"/>\n"
    overrides +=
      "  <Override PartName=\"/xl/styles.xml\" ContentType=\"\(OOXML.contentTypeStyles)\"/>\n"
    overrides +=
      "  <Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"\(OOXML.contentTypeSharedStrings)\"/>\n"
    overrides +=
      "  <Override PartName=\"/docProps/core.xml\" ContentType=\"\(OOXML.contentTypeCoreProps)\"/>\n"

    for i in 1...max(sheetCount, 1) {
      overrides +=
        "  <Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"\(OOXML.contentTypeWorksheet)\"/>\n"
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="\(OOXML.nsContentTypes)">
        <Default Extension="rels" ContentType="\(OOXML.contentTypeRels)"/>
        <Default Extension="xml" ContentType="\(OOXML.contentTypeXML)"/>
      \(overrides)</Types>
      """
  }

  // MARK: - Root Relationships

  private static func generateRootRelsXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="\(OOXML.nsRelationships)">
      <Relationship Id="rId1" Type="\(OOXML.relTypeOfficeDoc)" Target="xl/workbook.xml"/>
      <Relationship Id="rId2" Type="\(OOXML.relTypeCoreProps)" Target="docProps/core.xml"/>
    </Relationships>
    """
  }

  // MARK: - Workbook XML

  private static func generateWorkbookXML(workbook: Workbook) -> String {
    var sheetsXML = ""
    for (idx, sheet) in workbook.sheets.enumerated() {
      let sheetNum = idx + 1
      sheetsXML +=
        "    <sheet name=\"\(xmlEscape(sheet.name))\" sheetId=\"\(sheetNum)\" r:id=\"rIdSheet\(sheetNum)\"/>\n"
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="\(OOXML.nsSpreadsheetML)" xmlns:r="\(OOXML.nsOfficeDocRelationships)">
        <sheets>
      \(sheetsXML)  </sheets>
      </workbook>
      """
  }

  // MARK: - Workbook Relationships

  private static func generateWorkbookRelsXML(sheetCount: Int) -> String {
    var rels = ""
    var rIdNum = 1

    // Worksheet relationships
    for i in 1...max(sheetCount, 1) {
      rels +=
        "  <Relationship Id=\"rIdSheet\(i)\" Type=\"\(OOXML.relTypeWorksheet)\" Target=\"worksheets/sheet\(i).xml\"/>\n"
      rIdNum = i + 1
    }

    // Styles relationship
    rels +=
      "  <Relationship Id=\"rId\(rIdNum)\" Type=\"\(OOXML.relTypeStyles)\" Target=\"styles.xml\"/>\n"
    rIdNum += 1

    // Shared strings relationship
    rels +=
      "  <Relationship Id=\"rId\(rIdNum)\" Type=\"\(OOXML.relTypeSharedStrings)\" Target=\"sharedStrings.xml\"/>\n"

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="\(OOXML.nsRelationships)">
      \(rels)</Relationships>
      """
  }

  // MARK: - Styles XML (minimal)

  private static func generateStylesXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="\(OOXML.nsSpreadsheetML)">
      <fonts count="1">
        <font>
          <sz val="11"/>
          <name val="Calibri"/>
        </font>
      </fonts>
      <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
      </fills>
      <borders count="1">
        <border>
          <left/><right/><top/><bottom/><diagonal/>
        </border>
      </borders>
      <cellStyleXfs count="1">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
      </cellStyleXfs>
      <cellXfs count="1">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
      </cellXfs>
    </styleSheet>
    """
  }

  // MARK: - Shared Strings XML

  private static func generateSharedStringsXML(sharedStrings: SharedStringTable) -> String {
    let count = sharedStrings.strings.count
    var items = ""
    for s in sharedStrings.strings {
      items += "  <si><t>\(xmlEscape(s))</t></si>\n"
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <sst xmlns="\(OOXML.nsSpreadsheetML)" count="\(count)" uniqueCount="\(count)">
      \(items)</sst>
      """
  }

  // MARK: - Worksheet XML

  private static func generateWorksheetXML(
    sheet: Sheet, sharedStrings: SharedStringTable
  ) -> String {
    var sheetDataXML = ""

    let sortedRows = sheet.rows.keys.sorted()
    for rowNum in sortedRows {
      guard let cells = sheet.rows[rowNum], !cells.isEmpty else { continue }

      // Sort cells by column
      let sortedCells = cells.sorted { $0.column < $1.column }

      var rowXML = "    <row r=\"\(rowNum)\">\n"
      for cell in sortedCells {
        rowXML += generateCellXML(cell: cell, sharedStrings: sharedStrings)
      }
      rowXML += "    </row>\n"

      sheetDataXML += rowXML
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="\(OOXML.nsSpreadsheetML)">
        <sheetData>
      \(sheetDataXML)  </sheetData>
      </worksheet>
      """
  }

  // MARK: - Cell XML

  private static func generateCellXML(cell: Cell, sharedStrings: SharedStringTable) -> String {
    let ref = cell.reference

    switch cell.value {
    case .string(let s):
      if let idx = sharedStrings.indexMap[s] {
        return "      <c r=\"\(ref)\" t=\"s\"><v>\(idx)</v></c>\n"
      } else {
        return "      <c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(s))</t></is></c>\n"
      }

    case .number(let d):
      let numStr: String
      if d == d.rounded() && abs(d) < 1e15 {
        numStr = String(Int(d))
      } else {
        numStr = String(d)
      }
      return "      <c r=\"\(ref)\"><v>\(numStr)</v></c>\n"

    case .boolean(let b):
      return "      <c r=\"\(ref)\" t=\"b\"><v>\(b ? "1" : "0")</v></c>\n"

    case .formula(let f):
      // Strip leading = if present
      let formulaText = f.hasPrefix("=") ? String(f.dropFirst()) : f
      return "      <c r=\"\(ref)\"><f>\(xmlEscape(formulaText))</f></c>\n"

    case .empty:
      return ""
    }
  }

  // MARK: - Core Properties

  private static func generateCorePropsXML() -> String {
    let dateStr = ISO8601DateFormatter().string(from: Date())
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <cp:coreProperties xmlns:cp="\(OOXML.nsCoreProps)" xmlns:dc="\(OOXML.nsDC)" xmlns:dcterms="\(OOXML.nsDCTerms)" xmlns:xsi="\(OOXML.nsXSI)">
        <dc:creator>Osaurus XLSX Plugin</dc:creator>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(dateStr)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(dateStr)</dcterms:modified>
      </cp:coreProperties>
      """
  }
}
