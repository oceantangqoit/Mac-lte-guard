# Contributing

Thanks for taking the time to contribute!

## Translations (easiest way to help)

1. Copy any file in `lang/`, rename it to your language code (e.g. `nl.ini`, `tr.ini`)
2. Translate the right-hand side of each numbered line — keep `{0}` / `{1}` placeholders in place
3. Set `name=` under `[meta]` to the language's own name (e.g. `Nederlands`)
4. Test locally: drop the file into `~/.lte-guard-lang/` and pick it from the **Language** menu — no rebuild needed
5. Open a pull request

## Code

```bash
./build.sh          # compile + package into dist/
```

Requires Xcode Command Line Tools; `brew install librsvg` for icon rendering.

The whole app is one file: `src/LTEGuard.swift`. All user-facing strings must go through `T(n)` and be added to **every** `lang/*.ini` (English at minimum).

## Reporting bugs

Please include: macOS version, Mac model (Apple Silicon / Intel), the adapter's brand and USB VID:PID, plus the relevant part of `~/.lte-wake.log`.
