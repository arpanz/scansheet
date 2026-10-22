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
- Free: 3 open sheets, **200 synced rows per month**, first **7 days unlimited**. Scanning, Excel/CSV export and "Read a code" are never limited.
- Count rows, not scans (Qty merges don't use allowance). Show "N of 200 rows this month" on Home and Settings; heads-up at 160.
- At the limit: scanner never stops, current job finishes, new rows save on the phone, only Google Sheets sync pauses until the 1st or upgrade; upgrade prompt shown then.
- Pro: unlimited sheets and rows, team sharing, product lookup, Read text, no ads, priority support. Ads never in the scanner.
- Start at 200; watch % hitting the limit and their upgrade rate before changing it.

## Trial and usage tracking
- Limits apply only to Google Sheets sync, which already requires Google sign-in, so tracking is per Google account.
- Firebase Auth with the same Google credential + one Firestore doc per account: `trialStartedAt`, `month`, `rowsSynced`. Local cache so offline scanning never waits; update server on sync.
- Trial starts at the first synced row, not at install.
- Firebase project already exists (`scansheet-496017`, `android/app/google-services.json`); Firebase packages still need adding to `pubspec.yaml`.
- The 7-day free week is separate from any Play Store subscription trial.

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
