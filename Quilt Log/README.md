# Quilt Log

Quilt Log is a macOS app for tracking quilts in a portable SQLite database file.

## Using The App

Download the compiled app from the project releases, move it to your Applications folder, and open it like any other Mac app.

On first launch, Quilt Log asks you to create a new database or open an existing one. The database is a normal `.sqlite` file that stores quilt records and imported photos, so you can keep it anywhere you normally store documents.

From the app you can:

- Browse quilts grouped by status.
- Search by quilt name, pattern, fabric, size, date, recipient, notes, or sequence number.
- Add, edit, delete, and renumber quilt records.
- Import and manage quilt photos.
- Show the current database in Finder.
- Export PDF views of the complete log, available-to-gift quilts, or a visual catalog.
- Set the name used in PDF export titles from Quilt Log > Settings.

## Building From Source

Open `QuiltLog.xcodeproj` in Xcode and run the `QuiltLog` scheme.

The app does not require import scripts or generated seed data. Use the File menu to create a new database or open an existing Quilt Log database.

## License

Apache-2.0
