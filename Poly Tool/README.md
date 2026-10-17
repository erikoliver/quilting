# Poly Tool

A native macOS quilt-design app built with SwiftUI and an AppKit drawing canvas.
Requires macOS 14 or later and Xcode 15 or later. No external packages are required.

## Run the app

1. Open `PolyTool.xcodeproj` in Xcode.
2. Select the **PolyTool** scheme and **My Mac** destination.
3. Press **Command-R**.
4. Choose **New Document** in the file dialog, or use **File > New**.
5. Click **Try a star example**, or drag a shape onto the grid.

The project uses local ad-hoc signing. A developer account is not required for local use.

## Design a quilt

1. Select a finished height from **1″ through 8″**, in **½″ increments**.
2. Select a fabric color.
3. Drag a shape from the palette onto the canvas.
4. Click a piece to select it.
5. Drag the selected piece to move it.

Pieces snap to the nearest vertex of the ¼″ triangular grid. The canvas rejects overlapping pieces but permits shared edges.
The palette contains triangles, diamonds, trapezoids, parallelograms, hexagons, jewels, regular side-setting triangles, and 120° side-setting triangles.
A 2″ triangle covers four 1″ triangles.

The color palette sets the fabric for new pieces. **Use [fabric name]** applies that fabric to the selected piece.
The plus button adds a named fabric color. **Flip new shapes** sets the mirror orientation for new pieces. **Orientation** sets the rotation for new pieces.

| Control | Action |
| --- | --- |
| F / Flip button | Mirror the selected piece, or the next shape |
| R | Rotate the selected piece by 60°, or rotate the next shape |
| Command-D | Duplicate the selected piece in a nearby open space |
| Delete | Delete the selected piece |
| Escape | Cancel a move and clear the selection |
| Scroll / two-finger scroll | Pan the canvas |
| Space + drag / hand tool | Pan the canvas |
| Drag empty canvas | Pan the canvas |
| Pinch / Option-scroll | Zoom around the pointer |
| Fit button beside zoom | Fit the complete design into the canvas |
| Command-Z / Shift-Command-Z | Undo / redo an edit |
| Command-S | Save the document |

Canvas keyboard controls require canvas focus. Click the canvas after you edit a text field.

## Save and share

Documents use the `.polyquilt` extension and contain readable JSON. The app also opens and saves `.json` files.
The standard macOS document system provides Open, Save, autosave, and multiple document windows.

**Summary** shows counts by fabric, shape, and size. **Export summary CSV** creates a spreadsheet-compatible inventory.
The summary also shows the design bounds and the total area of its shapes.

## Size convention

Size means the nominal finished height, measured perpendicular to the strip edges. Hexagons use their full flat-to-flat height.
The default height is 2″. The available heights range from 1″ through 8″, in ½″ increments.
Jewels use the parent diamond size. Their clipped tip matches a triangle with half that size.
Regular side-setting triangles are mirror-image 30°–60°–90° halves, as shown on page 9 of Dancing Dahlias.
Their size matches the parent equilateral triangle height. The 120° side-setting triangle uses the altitude to its long base. Parallelograms currently use a 2:1 side ratio.
The jewel outline follows the trimmed diamond on page 4 of Dancing Dahlias.
The lattice side length is `2 / sqrt(3)` inches per grid unit.

Nominal strip widths follow the requested planning convention: finished height plus ½″.
Thus, 2″ pieces show a 2½″ strip and 1″ pieces show a 1½″ strip.
These values describe a design convention, not exact cutting instructions.
Ruler markings, seam allowances, and trimmed tips require a separate cutting model.

Design bounds include gaps and exclude seam allowances. Shape area excludes seam allowances, cutting waste, borders, and backing.
The app does not yet calculate yardage or assembly order.

## JSON format, version 1

Each file contains:

- `schemaVersion`: the file format version.
- `title`, `units`, and `sizeConvention`: the design metadata.
- `fabrics`: named colors with UUID identifiers and six-digit RGB values.
- `pieces`: independent shapes with UUID identifiers, a fabric reference, size, rotation, and origin.

Each origin uses axial coordinates in multiples of 0.25 `{ "q": 0, "r": 0 }`.
Rotation uses an integer from 0 through 5, in clockwise 60° steps on the screen.
The `flipped` Boolean mirrors the shape across its local vertical anchor line before rotation.
Flip works on every shape and supports undo. The regular side triangle uses Flip to change handedness.
Coordinates support negative values. The origin is also the rotation anchor, shown as a dot on the selected piece.

Quarter-inch snapping accommodates the vertices of half-inch-sized hexagons and jewels. Fine grid lines appear as you zoom in.

The app rejects unsupported versions, invalid colors, duplicate identifiers, invalid sizes, and missing fabric references.
The file `Examples/Juniper Star.polyquilt` contains an editable sample.

## Development

Build the app:

```sh
xcodebuild -project PolyTool.xcodeproj -scheme PolyTool -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PolyTool-DerivedData build
```

Run the geometry and document tests:

```sh
swift test
```

`Sources/PolyCore` contains the geometry, document schema, and summary calculations.
`Sources/PolyTool` contains the SwiftUI interface, document integration, and canvas input.
Tests cover rotations, mixed sizes, snapping, collisions, the sample design, JSON round trips, and invalid files.

The shape choices draw on the local ruler instructions and pattern references in `Scratch`.
Those references remain local and are excluded from Git. The app contains no copies of the supplied patterns.
The document integration follows [Apple's document-based SwiftUI guidance](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui/).

## Current scope

This first version supports single-piece selection, solid colors, and eight shape choices.
It does not yet support groups, fabric images, print templates, borders, or a cutting plan.
The canvas draws the visible grid and supports broad pan and zoom ranges.
Very large piece counts still need performance measurements.
