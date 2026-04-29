# osaurus-xlsx

An [Osaurus](https://osaurus.ai) plugin for reading, creating, and modifying Excel (.xlsx) spreadsheets. Pure Swift with zero external dependencies.

## Tools

| Tool | Description |
| --- | --- |
| `read_xlsx` | Read an .xlsx file into memory, returning structured cell data |
| `get_cell_value` | Get the value of a specific cell or range from a loaded workbook |
| `list_sheets` | List all sheet names in an .xlsx file |
| `create_xlsx` | Create a new workbook in memory with sheets, headers, and data |
| `write_cells` | Write or update specific cells in a loaded workbook |
| `save_xlsx` | Save a workbook from memory to an .xlsx file on disk |
| `xlsx_to_csv` | Convert a sheet from an .xlsx file to CSV or TSV text |
| `csv_to_xlsx` | Import CSV/TSV text data into a new workbook |
| `modify_xlsx` | Batch operations: set cells, formulas, delete rows/columns, rename/add sheets |

## Workflow

The plugin uses a stateful, in-memory model:

1. **Load or create** a workbook (`read_xlsx` or `create_xlsx`) to get a `workbook_id`
2. **Modify** the workbook (`write_cells`, `modify_xlsx`)
3. **Save** to disk (`save_xlsx`)

For quick operations, `list_sheets` and `xlsx_to_csv` read directly from disk without loading into memory.

## ABI compatibility

The plugin exports both `osaurus_plugin_entry_v2` and the legacy `osaurus_plugin_entry` entry point. Osaurus hosts that support v2 load the full v2 API table, while older hosts can still fall back to the legacy entry point.

## Development

### Build

```bash
swift build -c release
```

### Test

```bash
swift test
```

### Install locally

```bash
osaurus manifest extract .build/release/libosaurus-xlsx.dylib
osaurus tools package osaurus.xlsx 0.1.0
osaurus tools install ./osaurus.xlsx-0.1.0.zip
```

## Publishing

This project includes a GitHub Actions workflow (`.github/workflows/release.yml`) that automatically builds and releases the plugin when you push a version tag.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

MIT
