# Contributing

Thanks for taking the time to contribute!

## Translations (easiest way to help)

1. Copy any file in `lang/`, rename it to your language code (e.g. `nl.ini`, `tr.ini`)
2. Translate the right-hand side of each numbered line — keep `{0}` / `{1}` placeholders in place
3. Set `name=` under `[meta]` to the language's own name (e.g. `Nederlands`)
4. Test locally: drop the file into `~/.lte-guard-lang/` and pick it from the **Language** menu — no rebuild needed
5. Open a pull request

### Key numbering rules

- Keys are **append-only and never reused**. When a feature is dropped, its key is *retired* — a stale file in someone's `~/.lte-guard-lang/` must never map to an unrelated string in a newer build.
- Currently retired: `8, 9, 19, 20, 37, 62, 63` (the sleep-policy feature removed in v1.4.0).
- New strings simply take the next free number. **Do not reserve gaps** for future features — gaps add bookkeeping without buying anything, since translators work from the English file anyway.
- When you add a string, add it to `en.ini` first (it is the fallback for every language), then to as many others as you can.

## Code

```bash
./build.sh          # compile + package into dist/
```

Requires Xcode Command Line Tools; `brew install librsvg` for icon rendering.

The whole app is one file: `src/LTEGuard.swift`. All user-facing strings must go through `T(n)` and be added to **every** `lang/*.ini` (English at minimum).

## Reporting bugs

Please include: macOS version, Mac model (Apple Silicon / Intel), the adapter's brand and USB VID:PID, plus the relevant part of `~/.lte-wake.log`.
