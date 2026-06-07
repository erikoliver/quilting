# Quilt Log

A personal macOS SwiftUI app for tracking quilts in a single SQLite database file.

## Open The Project

Open `QuiltLog.xcodeproj` in Xcode and run the `QuiltLog` scheme.

During development, the app can seed its working database from `Database/Quilt Log.sqlite` if that file exists.

- Development seed: `Database/Quilt Log.sqlite`
- Working copy created on first launch: `~/Documents/Quilt Log.sqlite`

The working copy is the single editable database file. Quilt metadata and imported photos are stored in SQLite.

## First Pass Features

- Browse quilts grouped by status.
- Search by quilt name, pattern, fabric, or recipient.
- Edit the core fields from the spreadsheet.
- Add new quilts.
- Import photos into the SQLite `photos` table as BLOBs.
- Reveal the working database in Finder.
- Export a basic landscape PDF table.

## One-Time Import Scripts

The import scripts are developer utilities, not app features:

- `Scripts/fix_sequence_numbers.mjs` normalized `Seq #` values to `1...120`.
- `Scripts/import_quilt_log.mjs` rebuilds `Database/Quilt Log.sqlite`.

Re-run the import only if you intentionally want to regenerate the seed database from the Excel file.
