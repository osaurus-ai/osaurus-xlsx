# XLSX Fidelity Contract

This plugin owns XLSX-specific parsing, writing, and spreadsheet tools. Osaurus Core should only route plugin capabilities and enforce host-level permissions.

## Supported Input

- Workbook sheet inventory.
- Sheet visibility state: visible, hidden, and very hidden.
- Worksheet used range.
- Merged cell ranges.
- Sparse cell reads by sheet, cell, or range.
- Shared strings and inline strings.
- Numbers, booleans, formulas, and simple error cells.
- Compact workbook metadata through `xlsx_describe_workbook`.

## Supported Output

- New minimal `.xlsx` workbooks.
- Multiple sheets.
- Strings, numbers, booleans, and formulas.
- Sheet visibility state.
- Merged cell ranges.
- Atomic write into the final path.
- Explicit overwrite protection through `save_xlsx`.
- `dry_run` save previews.

## Partial Fidelity

Loaded workbooks are represented by the plugin's sparse model. If a loaded workbook is saved again, the plugin rewrites a minimal XLSX package from that model.

The following workbook parts may be detected later but are not preserved by this writer today:

- styles and rich formatting
- comments
- charts
- tables
- pivot tables
- data validation
- conditional formatting
- macros
- external links

The plugin returns warnings when saving loaded workbooks so the model and user do not mistake minimal writeback for full Excel preservation.

## Safety Model

- Read and describe operations are read-only.
- Mutating operations require Osaurus permission policy `ask`.
- `save_xlsx` does not overwrite an existing file unless `overwrite` is explicitly `true`.
- `dry_run` validates the planned save and reports whether it would overwrite without writing a file.
- Paths are constrained to the selected working directory when Osaurus provides folder context.

