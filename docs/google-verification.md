# Google OAuth verification

ScanSheet's Google sign-in (Cloud project `scansheet-496017`) is in production with
verified branding. The `spreadsheets` scope still needs Google's data-access review.
Until it passes, users see "Google hasn't verified this app" and the app is capped at
100 users.

Scopes the app requests (`lib/core/services/google_sheets_service.dart`):

| Scope | Google's class |
|---|---|
| `spreadsheets` | Sensitive (needs review) |
| `drive.file` | Non-sensitive |

The home, privacy and terms pages live in `hosting/` and deploy with
`firebase deploy --only hosting`. Keep `hosting/google5ffe06773d025a94.html`: it
proves domain ownership to Search Console.

## Justification

Paste into Google Auth Platform → Data Access → "How will the scopes be used?"
(1000 characters max; this is 887):

> ScanSheet is a barcode scanner that adds each scan as a new row in the user's Google Sheet. We use the spreadsheets scope to create that sheet, read its tab names and headers, append one row per scan, and read a tab the user chooses as a checklist. We use drive.file (with Google Picker) to list only the sheets the user made or picked in the app. drive.file alone is not enough: in "Scan together", several people's phones write to one sheet owned by someone else and shared with them by email, and each teammate's app has to append rows to a sheet it never created or picked. Users who connected a sheet before we added the picker also keep writing to it. spreadsheets.readonly is not enough because writing rows is the core feature. We never browse or read sheets the user hasn't chosen in the app. Sheet data goes straight from the phone to Google and is never stored on our servers.

## Demo video

Upload to YouTube (unlisted is fine) and paste the link in the same form. Record
on a phone, in English or with English captions, and keep it to a few minutes.

1. Open ScanSheet and start Google sign-in from onboarding or Settings →
   Connect Google Sheets.
2. Show the account picker, Google's "unverified app" screen (expected), then the
   consent screen. Pause so the app name **ScanSheet** and both permissions are
   readable.
3. Create a new sheet in the app, scan two or three barcodes, then open the sheet
   in Google Sheets and show the new rows (this is the `spreadsheets` write).
4. Back in the app, tap **Choose another sheet from Drive**, pick an existing sheet
   in Google's picker, and show it in the app's list (this is `drive.file`).
5. Show a tab being used as a checklist, if possible.
6. Start Scan together, invite a teammate's email, and show the sheet shared with
   them (the `drive.file` sharing and why `spreadsheets` is needed for teammates).

Google asks for every OAuth client in the project to appear. The project has
Android clients for `com.livinlabs.scansheet` and two web clients. Recording the
Android app covers how they are used.

## Submitting

Data Access → fill both fields → Save → Verification Center → submit. Google
emails the developer contact address with questions, so check it is correct on
the Branding page first.
