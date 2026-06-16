# Quilt Log Export Format And Schemas

Quilt Log's Mac backup export creates a ZIP file containing the quilt data and any exported image data. The format is intended to be readable outside Quilt Log and importable by later versions of the app.

## ZIP Layout

The ZIP root contains:

- `manifest.json`: the backup manifest and quilt records.
- `images/`: original photo files referenced by `manifest.json`.
- `thumbnails/`: thumbnail image files referenced by `manifest.json`.

Photo file paths in `manifest.json` are relative to the ZIP root, such as `images/<photo-uuid>.jpg`.

## Format Version

Current format version: `2`

The manifest includes:

- `formatVersion`: backup format version.
- `exportedAt`: ISO 8601 timestamp for the export.
- `syncBehavior`: descriptive text about the source library.
- `quilts`: exported quilt records.

Each quilt includes its stable `uuid`, user-facing fields, `createdAt`, `updatedAt`, and any photos. Each photo includes its stable `uuid`, metadata, and optional paths to original and thumbnail image files.

Version 2 adds structured quilt detail fields for started date, designer, fabric store, fabric line, quilting completed date, quilter, and quilting pattern. These fields were added based on user requests for more precise tracking of pattern, fabric, quilting, and timeline information.

The app can still import version 1 backups; fields introduced in version 2 default to empty strings when importing an older backup.

## Identity And Import Behavior

Quilt UUIDs are the import identity. If a backup quilt UUID does not exist in the current library, Quilt Log imports it as a new quilt. If a backup quilt UUID already exists, the Mac import flow prompts the user to skip existing quilts or replace existing quilts.

When replacing an existing quilt, Quilt Log replaces the quilt text/status/date fields and photos from the backup while preserving the current sequence number. Newly imported quilts receive new sequence numbers after the current library's highest sequence number.

Photo UUIDs are handled inside their owning quilt. Replacing a quilt replaces that quilt's photo set.

## JSON Schema

The JSON Schema for `manifest.json` is provided in:

`Documentation/quilt-log-backup.schema.json`
