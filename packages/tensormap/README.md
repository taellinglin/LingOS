# tensormap

**Kind:** 网灵 (web)  ·  **Version:** 2030.0.0

A small set of standalone browser demos (canvas + vanilla JS, no build step,
no dependencies) built around a mirrored Conway's Game of Life. This is the
styling reference for LingOS's `ling-life` command
(`crates/ling-kernel/src/life.rs` in the `ling` compiler repo): same B3/S23
rules, same quarter-grid 4-way mirror symmetry, same red/blue-only palette.

This is a `灵符` (lingfu) package — publishable to the Ling language's
package registry via the `lingfu` CLI (see **Publishing**, below). It is
unrelated to LingOS's own in-kernel `.lpkg`/`pkginstall` package format
described in `packages/README.md` one level up; that's a separate,
not-yet-networked mechanism for installing files onto a *booted LingOS
disk*, whereas this is an ordinary package in the `ling`/`lingfu` ecosystem,
published like any other `.ling` project.

## Structure

- `index.html` / `script.js` / `style.css` / `o.otf` — "AHO 2.0": the core
  Game of Life demo, red/blue cells, 4-way mirror symmetry.
- `index2.html` / `script2.js` — adds a matrix-rain layer (8-fold mirrored
  falling characters, HSL color cycling) and rotating "galaxy" spiral-arm
  effects, plus mouse-attraction physics and looped background audio
  (`x.wav`, not included in this checkout — see below).
- `7075.html` / `7075.js` / `7075.otf` — an earlier, simpler variant of the
  same Life engine (absolute-path font load, no matrix rain/galaxy layer).
- `LinUX/` — a themed sibling variant ("LinUX-AHO 2.0") that overlays a
  chat-style UI (Assumption/Hypothesis/Operation labeled input) on the same
  engine, with its own tuned galaxy parameters and `aho.js` for the overlay
  interactivity.

## Running locally

Open any of the `index*.html` / `7075.html` files directly in a browser.
If the `@font-face` custom font (`o.otf` / `7075.otf`) fails to load under
`file://` (some browsers block local font fetches by policy), serve the
directory instead:

```sh
python -m http.server -d packages/tensormap 8000
```

then visit `http://localhost:8000/index.html`.

## Audio assets (not checked into git)

`script2.js` (and `LinUX/script2.js`) loop `x.wav` as background audio.
`x.wav` (174MB) and `y.wav` (99MB, currently unreferenced by any script)
are excluded via the repo's `.gitignore` — both are at or over GitHub's
100MB file-size limit. The demo runs fine without them (the `Audio` element
just fails silently); drop your own `x.wav` next to `script2.js` locally if
you want the audio.

## Publishing

This package is ready to publish via `lingfu` (built from
`ling/crates/ling-fu`):

```sh
lingfu login <api-key>      # once, from the registry's /me/keys page
cd packages/tensormap
lingfu publish
```

**Before publishing**, make sure `x.wav`/`y.wav` are *not* sitting in this
directory if you've added them locally for testing — `lingfu publish`
tars the whole project directory as-is (it isn't `.gitignore`-aware, it
only skips `.git`/`.ling-build`/`target`/`.ling-shared-target`/`dist` by
name), so leftover multi-hundred-MB `.wav` files would get swept into the
uploaded artifact.
