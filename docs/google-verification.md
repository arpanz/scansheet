# Google OAuth verification

ScanSheet's Google sign-in (Cloud project `scansheet-496017`) is in production with
verified branding. The app asks only for `drive.file`, which is non-sensitive, so it
needs no data-access review, no demo video and has no 100-user cap.

Scope the app requests (`lib/core/services/google_sheets_service.dart`):

| Scope | Google's class |
|---|---|
| `drive.file` | Non-sensitive |

The Sheets API accepts `drive.file` for any sheet the app created or the user chose
in Google's file picker.

## History

- Nov 2026: `drive.metadata.readonly` (restricted, needs a paid CASA assessment)
  was dropped.
- Nov 8, 2026: Google's review of `spreadsheets` (sensitive) asked us to use
  `drive.file` with the Google Picker instead ("[Action Needed] OAuth Verification
  Request Acknowledgement"). The app moved to `drive.file` only; the reply to that
  email is "Confirming narrower scopes". Don't remove a scope Google has already
  approved until they say so.

## Google's file picker

Android has no native Drive picker, and Google blocks sign-in inside web views, so
the picker runs on a page in a Chrome tab:

- `hosting/pick.html` on `https://scansheet-496017.firebaseapp.com/pick.html`.
- The app opens it with `flutter_web_auth_2` (Chrome Auth Tab) and passes its own
  short-lived `drive.file` token and the sheet id in the URL fragment, which never
  reaches a server. The page strips the fragment at once.
- The picker uses the browser API key "ScanSheet Drive picker" (Picker API only,
  referrer `scansheet-496017.firebaseapp.com`) and `setAppId` with the project
  number, so a chosen sheet is granted to every client in the project.
- With a sheet id the picker shows only that sheet (`setFileIds`); the user taps
  Select. The page returns to the app on `scansheet-pick://picked?id=…`
  (`CallbackActivity` in `AndroidManifest.xml`). The app ignores the returned id
  and retries the one it asked for.
- `firebase.json` serves the page with `Cache-Control: no-store` and
  `Referrer-Policy: origin` (the key checks the origin, so not `no-referrer`).

Where the app opens it:

1. **Use a sheet from a link**: if the pasted sheet isn't reachable yet.
2. **Allow access** in the sync banner: a teammate's phone after the owner's
   ScanSheet shares the sheet (Scan together), and upgrading users whose sheet was
   reachable only through the old `spreadsheets` scope.

The Chrome tab must be signed in to the same Google account as the app. If it
isn't, the retry fails and the app says so.

The home, privacy and terms pages live in `hosting/` and deploy with
`firebase deploy --only hosting`. Keep `hosting/google5ffe06773d025a94.html`: it
proves domain ownership to Search Console.
