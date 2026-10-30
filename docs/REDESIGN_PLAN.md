# ScanSheet redesign — build plan

Design canvas (source of truth for every screen): https://claude.ai/artifact/1D7HRvSucgMdnktty1kC2T
Foundations board = tokens; States & surfaces board = error/empty/offline states.

## Visual system
- Colors: Paper `#F5F6F2`, Surface `#FFFFFF`, Ink `#0B1210`, Ink 2 `#4A5550`, Muted `#5F6964`, Line `#E3E6E0`, Emerald `#0B7D45` (+ tint `#E3F4EA`), Lime signal `#D4F56A` (+ row `#EEF9C8`), Night `#0B0F0D`, Amber `#D97706`, Error `#B42318`.
- Lime is only for scan moments and the scan button; never text on light backgrounds.
- Type: Geist (UI), Geist Mono (codes, counts, cells). Radii 10/14/18/24/28, 4 pt spacing.
- Dark mode: see "Home · dark mode" board. Scanner and camera screens are always dark.
- Motion (not drawn, must be built): scan success flash + row flying into the list, count pop, distinct haptics for success vs repeat.

## Information architecture
- Bottom nav: Home · big Scan button · Library. Settings behind the avatar.
- Scan button: sheet in progress → open scanner on it; nothing in progress → "Scan into…" chooser (continue a sheet, new sheet, read a code, join a team sheet).
- Sheets never "finish": "Done for now" shows a summary; export is available anytime.
- Library tabs: Sheets · Code history (one-off reads).

## Onboarding (4 steps to first scan)
Welcome → What will you scan? (templates) → Where rows go (new Google Sheet / existing spreadsheet / keep on phone) → Google sign-in only if Sheets chosen (with consent preview) → Camera priming → straight into the scanner. Then Home · first run with checklist + coach mark.
- Google scope: narrow (`drive.file`, files the user picks or ScanSheet creates); use Google's file picker for existing spreadsheets.
- No paywall during onboarding.

## Scanner
- Success state (lime frame + toast), "Repeats add to Qty" switch (on by default for inventory), zoom 1×/2×/5×, Barcode / Read text switch, torch, compact bottom panel with last row + Undo, Type code, Done for now.
- Several codes in view → numbered boxes, tap one or "Add all".
- Closing with zero scans → "Scan closed early" help screen with a fix per reason.

## Columns
Types: Scan (multiple allowed), Product info (auto from barcode via open product databases), Pick-list (choices + default), Number (stepper), Text, Read text (on-device ML Kit OCR), Date & time, Location, Same value, Auto number. First Scan column is used to spot repeats.

## Team sharing
"Scan together": QR + invite link per sheet, members list with live status, toggle for teammates editing columns. Needs a backend (Firebase, below).

## Free plan and Pro
- Free: **200 new rows per month across every sheet** (Google Sheets, Excel and CSV), counted from day 1; 3 Google Sheets sheets open at once; lists keep their first **50** entries. No free trial.
- Count rows, not scans (Qty merges and edits don't use allowance). Show "N of 200 rows this month" on Home and Settings; heads-up at 160.
- At the limit: the scanner never stops and no scan is lost. New rows save on the phone **locked**: left out of Google Sheets sync and Excel/CSV export until the 1st (oldest unlock first, counting against the new month) or an upgrade.
- Pro: unlimited rows and sheets, full-size lists, team sharing, no ads. Ads never in the scanner.
- Start at 200; watch % hitting the limit and their upgrade rate before changing it.

## Usage tracking
- Counted on the phone (works signed out and offline) and, when signed in, mirrored to one Firestore doc per Google account (`month`, `rowsAdded`) through Firebase Auth with the same Google credential. The larger count wins, so switching accounts or reinstalling with the same account doesn't reset it.
- Firebase project: `scansheet-496017` (`android/app/google-services.json`).

## Build order
1. Theme: tokens, Geist fonts, light + dark `ThemeData`, shared components (buttons, column tags, toggles, segmented control, list rows, bottom sheets).
2. Navigation shell: Home / Scan / Library + Scan chooser.
3. Onboarding flow + Google sign-in with narrow scope + destination picker.
4. Scanner rebuild (success state, Qty merge, zoom, multi-code, scan-closed-early).
5. Columns: Pick-list, Product info, Read text, Same value rename; New sheet + Add column sheet.
6. Sheet view, Done for now, Library, Settings, swipe edit/delete with Undo.
7. States: offline, sync failed, sign-in expired, sheet unavailable, camera blocked, empty library.
8. Firebase: auth, usage doc, free-plan limits, paywall + Settings copy.
9. Team sharing (invite codes, members, live status).
10. Widget, Quick Settings tile, app shortcuts.

## Open placeholders
Prices (`[PRICE]`), user name/email, teammate names in designs.

## Lists and live values (added 2026-10-24)

Why: in persona walkthroughs (warehouse count, shift attendance, asset audit, production QC), every one of them stalled on the same two gaps. ScanSheet can't tell who or what a code is, and it can't change a bin or batch value mid-session. Canvas boards: "Lists & live values" row (ListImport, NewSheetList, ScannerList, SheetViewList, AddColumnValue, ScannerValue).

### A. Lists ("check against a list")
- A **list** is a reusable table imported once: a code column plus other columns (e.g. Badge ID → Name, Department; SKU → Item, Expected qty). It's kept on the phone and can be attached to any number of sheets (the same staff list every morning).
- **Sources:** a Google Sheets tab (reuse the existing spreadsheet list from `step3_destination.dart`, then `spreadsheets.values.get` on the tab; the current scopes already allow it) or an .xlsx/.csv from the phone (`file_picker` + `excel`/`csv`, already dependencies). Google lists refresh silently whenever scanning starts while online and fall back to the cached copy offline.
- **Import screen (ListImport):** pick the source, name the list, pick which column holds the code (show a sample value under each header), tick which columns fill in on scan, and optionally pick an "Expected count" column for stock counts.
- **Code matching:** trim, case-insensitive, and treat a UPC-A code and its EAN-13 form (with a leading 0) as the same code.
- **New sheet (NewSheetList):** a "Check against a list" card. "Codes not on the list" is a three-way choice: Ask · Add and flag · Skip. Attaching a list switches "Warn on repeats" on by default. New column kind **From list** (tag `FROM LIST`, emerald outline) fills in one field of the list's row.
- **Scanner (ScannerList):** the header shows `found/total`, and the bottom panel shows a progress bar with "N not here yet".
  - *Matched:* lime frame and a toast with the name; the card shows the name, code and fields.
  - *Not on list:* amber frame (`#F2A93B` on the dark scanner) and a card with Skip / Add anyway.
  - *Repeat:* white frame, "X is already here · 08:52", Skip / Add again.
  - Haptics: success = medium; not on list = double heavy; repeat = light.
- **Sheet view (SheetViewList):** a progress bar plus three count cards that double as tabs.
  - Attendance: Here · Not yet · Not on list.
  - Stock (when the list has an Expected column): Match · Off count (shown as `−3` in Error red, `+2` in Emerald, "37 of 40") · Not counted. Counted qty = the sum of the sheet's Qty column for that code.
- **Export:** Excel gets a second sheet and Google Sheets a second tab, named "Not scanned" (attendance) or "Count vs expected" (stock), rewritten on every Done for now. Rows added via "Add and flag" carry a trailing `On list` = `No` column.
- **Library:** a third tab, **Lists**, where you can rename, refresh, see entries, delete, and see which sheets use each list.

### B. Live values (change a Same value while scanning)
- A Same value column gains: **Change by scanning a label** with a "Labels start with" prefix (e.g. `BIN-`), and **Ask when scanning starts** (for batch, shift or gate). Tapping the chip in the scanner always works.
- **Scanner (ScannerValue):** the bottom panel shows one chip per Same value column (`Bin  B-13 ▾`).
  - Tapping a chip opens "Bin for the next scans": **Scan a bin label** (a one-shot capture that ignores the prefix), up to 6 recent values, a field to type a new one, and Use.
  - A matching label scan sets the value (the prefix is stripped) and adds no row. It shows a white frame, the toast "Bin is now B-13", the chip highlighted in lime-row, and Undo.
  - Rows already scanned keep their old value.
- **Precedence in `_handle`:** label-prefix check → list lookup → repeats/Qty merge → confirm sheet.

### Model changes
- `SessionColumn`: `labelPrefix` (String?), `askAtStart` (bool), `recentValues` (List<String>, max 6), `listField` (String?, for From list).
- New `SessionColumnType.fromList` and `ColumnKind.fromList`.
- `ScanSession`: `lookupListId` (String?), `unknownCodes` (`ask|flag|skip`).
- `SessionRow`: `notOnList` (bool).
- A value change is `session.copyWith(columns: …fixedValue…)` + `saveSession` + `_resetPending()`. `buildEmptyRow` already reads `fixedValue`.
- New `LookupList` model and `LookupListService` (Hive box `lookup_lists`). Store entries as a `Map<normalizedCode, List<String>>` with headers and import metadata.

### Build order (B first: smaller, and unblocks counts right away)
11. B1 Model fields and migration defaults; Add column UI for Same value (prefix, ask at start).
12. B2 Scanner chips, picker sheet, Undo, prefix scan, one-shot "Scan a label", ask-at-start sheet before the camera opens.
13. A1 `LookupList` model and service, file import (xlsx/csv), ListImport screen.
14. A2 Google Sheets tab import and refresh; Library › Lists tab.
15. A3 New sheet list card, From list column kind, unknown-code policy.
16. A4 Scanner matching states and progress; Sheet view tabs (attendance and stock).
17. A5 Export / Google second tab; flagged rows.
18. Templates:
    - Attendance → Badge + From list Name/Department + Time, list required.
    - Inventory → Location becomes Bin with prefix `BIN-` and ask at start.
    - New **Stock count** template (list with Expected).
    - New **Production / QC** template: Serial scan, Batch (ask at start), Pass/Fail pick-list.

### Decisions
- Free plan: lists free up to 100 entries each; Pro for larger lists (decided 2026-10-24).

### Open decisions
- Should the label prefix be stripped from the stored value? (Planned: yes.)
- Attendance In/Out (first scan = In, next = Out, with duration) is the natural follow-up, but it's out of scope here.
