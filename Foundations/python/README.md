# Foundation Paper Piecing Templates

Generate simple foundation paper piecing template PDFs from a shape and finished size.

The outer seam allowance is fixed at `0.25"` on every side. For example, a `4"` finished square produces a `4.5"` edge-to-edge template before sewing.
The finished size defaults to `4"` when omitted.
The largest supported finished size for the current letter-page layout is `7"` (`7.5"` outer cut size).

## Usage

```sh
uv run fpp-template square 4 --output square-4in-finished.pdf
uv run fpp-template vblock --output vblock-4in-finished.pdf
uv run fpp-template triangle-in-square --output vblock-4in-finished.pdf
uv run fpp-template cornerbeam --output cornerbeam-4in-finished.pdf
uv run fpp-template square-in-square --output squareinsquare-4in-finished.pdf
uv run fpp-template economy --output economy-4in-finished.pdf
uv run fpp-template vintagekite 3 --output vintagekite-3in-finished.pdf
```

The generated PDF includes:

- Solid outer cut line
- Dashed finished-size seam line
- `1"` reference square for checking that the PDF printed at 100%

Use `--debug` to add very thin red halfway guide lines through the square frame:

```sh
uv run fpp-template vblock --debug --output vblock-4in-debug.pdf
```

Supported shapes:

- `square`
- `vblock` / `triangle-in-square`
- `cornerbeam` / `kite`
- `squareinsquare` / `square-in-square`
- `economy` / `economy-block`
- `vintagekite` / `vintage-kite`
