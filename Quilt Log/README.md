# Quilt Log

Quilt Log is a macOS app for tracking quilts in an app-managed SQLite library.

## Using The App

Download the compiled app from the project releases, move it to your Applications folder, and open it like any other Mac app.

On first launch, Quilt Log creates its library in the app's Application Support folder. The live library is app-managed, and you can import or export normal `.sqlite` backups from the File menu.

From the app you can:

- Browse quilts grouped by status.
- Search by quilt name, pattern, fabric, size, date, recipient, notes, or sequence number.
- Add, edit, delete, and renumber quilt records.
- Import and manage quilt photos.
- Import and export Quilt Log SQLite backups.
- Show the app data folder in Finder.
- Export PDF views of the complete log, available-to-gift quilts, or a visual catalog.
- Set the name used in PDF export titles from Quilt Log > Settings.

## Building From Source

Open `QuiltLog.xcodeproj` in Xcode and run the `QuiltLog` scheme.

The app does not require import scripts or generated seed data. Use the File menu to import or export Quilt Log SQLite backups.

To package a notarized app for release, place `QuiltLog.app` in the ignored `dist/` folder and run:

```zsh
scripts/make_dmg.sh
```

The script checks the app signature, creates `dist/QuiltLog-<version>.dmg`, verifies the DMG, and checks the packaged app signature.

## License

Apache-2.0
