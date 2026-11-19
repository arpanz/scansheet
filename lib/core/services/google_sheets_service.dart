import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Wraps Google Sign-In + Sheets API v4 + Drive API v3.
/// All methods are safe to call when signed out — they throw [GSheetsException].
class GoogleSheetsService {
  static final GoogleSheetsService instance = GoogleSheetsService._();
  GoogleSheetsService._();

  // drive.file only: it is non-sensitive, so Google needs no data-access
  // review. It reaches the sheets ScanSheet made and any sheet the user
  // chooses in Google's file picker ([pickInDrive]); the Sheets API accepts
  // it for those files.
  static const _scopes = [drive.DriveApi.driveFileScope];

  // Google's file picker, hosted on Firebase Hosting (hosting/pick.html). It
  // returns to the app through this scheme (see AndroidManifest.xml).
  static const _pickPage = 'https://scansheet-496017.firebaseapp.com/pick.html';
  static const _pickScheme = 'scansheet-pick';

  final _googleSignIn = GoogleSignIn.instance;
  Future<void>? _initialized;

  GoogleSignInAccount? _currentUser;
  http.Client? _authClient;
  DateTime? _authClientAt;

  // Access tokens live ~60 min; rebuild the client well before that.
  static const _authClientTtl = Duration(minutes: 40);

  // ─────────────────────────────────────────────────────────────────────────
  // Auth state
  // ─────────────────────────────────────────────────────────────────────────

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// ValueNotifier so UI can react to sign-in/out without polling.
  final ValueNotifier<bool> signedInNotifier = ValueNotifier(false);

  /// Call once in main() to restore a previous sign-in silently.
  Future<void> init() async {
    await _ensureInitialized();
    _googleSignIn.authenticationEvents.listen(
      (event) => _onUserChanged(switch (event) {
        GoogleSignInAuthenticationEventSignIn(:final user) => user,
        GoogleSignInAuthenticationEventSignOut() => null,
      }),
      onError: (Object e) => debugPrint('Google sign-in event error: $e'),
    );
    try {
      final account = await _googleSignIn.attemptLightweightAuthentication();
      if (account != null) _onUserChanged(account);
    } catch (e) {
      debugPrint('Silent Google sign-in failed: $e');
    }
  }

  // GoogleSignIn.initialize must run exactly once, before any other call.
  Future<void> _ensureInitialized() =>
      _initialized ??= _googleSignIn.initialize();

  void _onUserChanged(GoogleSignInAccount? account) {
    if (account == _currentUser) return;
    _currentUser = account;
    _authClient = null; // force refresh on next API call
    signedInNotifier.value = account != null;
  }

  /// Opens the Google account picker, then asks for Sheets and Drive access.
  /// Returns null if the user backs out of either step.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _ensureInitialized();
      final account = await _googleSignIn.authenticate(scopeHint: _scopes);
      // Sign-in and access are separate steps since google_sign_in 7.
      final client = account.authorizationClient;
      final authz = await client.authorizeScopes(_scopes);
      // Play services can hand back a cached token the user has since revoked
      // (Google Account → Linked apps). Drop it and ask again, which shows
      // Google's consent screen instead of failing every request with a 401.
      if (!await _tokenWorks(authz.accessToken)) {
        await client.clearAuthorizationToken(accessToken: authz.accessToken);
        await client.authorizeScopes(_scopes);
      }
      _authClient = null;
      _onUserChanged(account);
      return account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw GSheetsException('Sign-in failed: ${e.description ?? e.code}');
    } catch (e) {
      debugPrint('┌── GOOGLE SIGN-IN ERROR ──────────────────────');
      debugPrint('│ $e');
      debugPrint('│ Type: ${e.runtimeType}');
      debugPrint('└──────────────────────────────────────────────');
      throw GSheetsException('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    // Forget the cached token too, so the next sign-in gets a fresh one.
    try {
      final authz = await _currentUser?.authorizationClient
          .authorizationForScopes(_scopes);
      if (authz != null) {
        await _currentUser!.authorizationClient.clearAuthorizationToken(
          accessToken: authz.accessToken,
        );
      }
    } catch (e) {
      debugPrint('Clearing Google token failed: $e');
    }
    await _googleSignIn.signOut();
    _onUserChanged(null);
  }

  /// Whether Google still accepts [token]. A network failure counts as yes,
  /// so being offline never forces a second consent prompt.
  Future<bool> _tokenWorks(String token) async {
    try {
      final res = await http
          .get(
            Uri.https('oauth2.googleapis.com', '/tokeninfo', {
              'access_token': token,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return true;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal: authenticated HTTP client
  // ─────────────────────────────────────────────────────────────────────────

  Future<http.Client> _getClient() async {
    if (_currentUser == null) throw GSheetsException('Not signed in.');
    final fresh =
        _authClientAt != null &&
        DateTime.now().difference(_authClientAt!) < _authClientTtl;
    if (_authClient != null && fresh) return _authClient!;
    // Never prompts: this runs from background sync. A null means access was
    // revoked, and the "sign-in expired" state asks the user to sign in again.
    final auth = await _currentUser!.authorizationClient.authorizationHeaders(
      _scopes,
    );
    if (auth == null) {
      // "Not signed in" is what SheetsSyncService reads as auth expired.
      throw GSheetsException('Not signed in: Google access expired.');
    }
    _authClient = GoogleAuthClient(auth);
    _authClientAt = DateTime.now();
    return _authClient!;
  }

  /// A raw access token for Google's file picker page.
  Future<String> accessToken() async {
    if (_currentUser == null) throw GSheetsException('Not signed in.');
    final auth = await _currentUser!.authorizationClient.authorizationForScopes(
      _scopes,
    );
    if (auth == null) {
      throw GSheetsException('Not signed in: Google access expired.');
    }
    return auth.accessToken;
  }

  Future<sheets.SheetsApi> _sheetsApi() async {
    final client = await _getClient();
    return sheets.SheetsApi(client);
  }

  Future<drive.DriveApi> _driveApi() async {
    final client = await _getClient();
    return drive.DriveApi(client);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spreadsheet operations
  // ─────────────────────────────────────────────────────────────────────────

  /// List the spreadsheets ScanSheet can see (most recently modified first):
  /// ones it created and ones picked in Google's picker, not the whole Drive.
  /// Optionally filter by [query] string matched against title.
  Future<List<SpreadsheetInfo>> listSpreadsheets({String? query}) async {
    try {
      final api = await _driveApi();
      var q =
          "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false";
      if (query != null && query.isNotEmpty) {
        q += " and name contains '${query.replaceAll("'", "\\'")}'";
      }
      final result = await api.files.list(
        q: q,
        orderBy: 'modifiedTime desc',
        pageSize: 50,
        $fields: 'files(id,name,modifiedTime,owners)',
      );
      return (result.files ?? [])
          .map(
            (f) => SpreadsheetInfo(
              id: f.id ?? '',
              title: f.name ?? 'Untitled',
              modifiedTime: f.modifiedTime,
              ownerEmail: f.owners?.firstOrNull?.emailAddress,
            ),
          )
          .toList();
    } catch (e) {
      throw GSheetsException('Failed to list spreadsheets: $e');
    }
  }

  /// Get all worksheet (tab) names within a spreadsheet.
  Future<List<String>> getWorksheets(String spreadsheetId) async {
    try {
      final api = await _sheetsApi();
      final result = await api.spreadsheets.get(
        spreadsheetId,
        $fields: 'sheets.properties.title',
      );
      return (result.sheets ?? [])
          .map((s) => s.properties?.title ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (e) {
      throw GSheetsException('Failed to get worksheets: $e');
    }
  }

  /// Gives [email] edit access to a spreadsheet (Scan together). Works for
  /// any sheet ScanSheet can reach through drive.file, as long as this
  /// account may share it.
  Future<void> shareWith(String spreadsheetId, String email) async {
    try {
      final api = await _driveApi();
      await api.permissions.create(
        drive.Permission(type: 'user', role: 'writer', emailAddress: email),
        spreadsheetId,
        sendNotificationEmail: false,
      );
    } catch (e) {
      throw GSheetsException('Failed to share spreadsheet: $e');
    }
  }

  /// Takes [email]'s access away again. Best effort.
  Future<void> unshare(String spreadsheetId, String email) async {
    try {
      final api = await _driveApi();
      final list = await api.permissions.list(
        spreadsheetId,
        $fields: 'permissions(id,emailAddress,role)',
      );
      for (final p in list.permissions ?? const <drive.Permission>[]) {
        if (p.role != 'owner' &&
            p.emailAddress?.toLowerCase() == email.toLowerCase()) {
          await api.permissions.delete(spreadsheetId, p.id!);
        }
      }
    } catch (e) {
      debugPrint('Unshare failed: $e');
    }
  }

  /// Create a new blank spreadsheet with the given title.
  /// Returns the new spreadsheet ID.
  Future<String> createSpreadsheet(String title, {String? firstTab}) async {
    try {
      final api = await _sheetsApi();
      final result = await api.spreadsheets.create(
        sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: title),
          sheets: firstTab == null
              ? null
              : [
                  sheets.Sheet(
                    properties: sheets.SheetProperties(title: firstTab),
                  ),
                ],
        ),
      );
      return result.spreadsheetId ?? '';
    } catch (e) {
      throw GSheetsException('Failed to create spreadsheet: $e');
    }
  }

  /// Add a tab, choosing the first available numbered name when needed.
  Future<String> addTab(String spreadsheetId, String title) async {
    try {
      final worksheets = await getWorksheets(spreadsheetId);
      var actualTitle = title;
      var suffix = 2;
      while (worksheets.contains(actualTitle)) {
        actualTitle = '$title $suffix';
        suffix++;
      }
      await _addSheet(spreadsheetId, actualTitle);
      return actualTitle;
    } catch (e) {
      throw GSheetsException('Failed to add tab: $e');
    }
  }

  Future<void> _addSheet(String spreadsheetId, String title) async {
    final api = await _sheetsApi();
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: title),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  /// Move a Google file to Drive trash.
  Future<void> trashFile(String fileId) async {
    try {
      final api = await _driveApi();
      await api.files.update(drive.File()..trashed = true, fileId);
    } catch (e) {
      throw GSheetsException('Failed to trash spreadsheet: $e');
    }
  }

  /// Fetch the Drive title for a spreadsheet. Missing access is best effort.
  Future<String?> spreadsheetTitle(String spreadsheetId) async {
    try {
      final api = await _sheetsApi();
      final sheet = await api.spreadsheets.get(
        spreadsheetId,
        $fields: 'properties.title',
      );
      return sheet.properties?.title;
    } catch (e) {
      debugPrint('Failed to get spreadsheet title: $e');
      return null;
    }
  }

  /// The spreadsheet id in a Google Sheets link
  /// (`docs.google.com/spreadsheets/d/ID/…`), or a bare id; null if neither.
  static String? spreadsheetIdFromLink(String text) {
    final value = text.trim();
    final link = RegExp(
      r'/spreadsheets/d/([a-zA-Z0-9_-]{20,})',
    ).firstMatch(value);
    if (link != null) return link.group(1);
    return RegExp(r'^[a-zA-Z0-9_-]{30,}$').hasMatch(value) ? value : null;
  }

  /// Opens a sheet the user pasted a link to. A sheet ScanSheet hasn't seen
  /// yet opens in Google's file picker first, where choosing it grants
  /// drive.file access. Returns null if the user backs out of the picker.
  Future<SpreadsheetInfo?> openSpreadsheetFromLink(String link) async {
    final id = spreadsheetIdFromLink(link);
    if (id == null) {
      throw GSheetsException('That isn’t a Google Sheets link.');
    }
    try {
      return await _openById(id);
    } on _NoAccess {
      if (await pickInDrive(spreadsheetId: id) == null) return null;
      // Retry the id we asked for, not whatever came back from the browser.
      try {
        return await _openById(id);
      } on _NoAccess {
        final email = _currentUser?.email ?? 'your Google account';
        throw GSheetsException(
          'Couldn’t open that sheet as $email. Check that Chrome is signed '
          'in to it and that the sheet is shared with it as an editor.',
        );
      }
    }
  }

  Future<SpreadsheetInfo> _openById(String id) async {
    try {
      final api = await _sheetsApi();
      final sheet = await api.spreadsheets.get(id, $fields: 'properties.title');
      return SpreadsheetInfo(
        id: id,
        title: sheet.properties?.title ?? 'Untitled spreadsheet',
      );
    } on sheets.DetailedApiRequestError catch (e) {
      // drive.file answers 403 or 404 for a sheet not granted to the app.
      if (e.status == 403 || e.status == 404) throw _NoAccess();
      throw GSheetsException('Couldn’t open that sheet: ${e.message}');
    } on GSheetsException {
      rethrow;
    } catch (e) {
      throw GSheetsException(
        'Couldn’t open that sheet. Check your connection.',
      );
    }
  }

  /// Opens Google's file picker in a Chrome tab. Choosing a sheet there
  /// grants ScanSheet drive.file access to it. With [spreadsheetId] the
  /// picker shows just that sheet, so the user only confirms it. Returns the
  /// chosen sheet, or null if the user backs out.
  Future<SpreadsheetInfo?> pickInDrive({String? spreadsheetId}) async {
    final token = await accessToken();
    final fragment = Uri(
      queryParameters: {'token': token, 'id': ?spreadsheetId},
    ).query;
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: '$_pickPage#$fragment',
        callbackUrlScheme: _pickScheme,
        // The picker needs a signed-in Google session and third-party
        // cookies, which Chrome has and browsers like Brave often don't.
        // Falls back to the default browser when Chrome isn't installed.
        options: const FlutterWebAuth2Options(
          customTabsPackageOrder: ['com.android.chrome'],
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      debugPrint('Picker failed: ${e.code} ${e.message}');
      throw GSheetsException('Couldn’t open Google Drive. Try again.');
    }
    final uri = Uri.parse(result);
    if (uri.host == 'error') {
      throw GSheetsException('Couldn’t open Google Drive. Try again.');
    }
    final id = uri.queryParameters['id'];
    if (uri.host != 'picked' || id == null || id.isEmpty) return null;
    final name = uri.queryParameters['name'];
    return SpreadsheetInfo(
      id: id,
      title: name == null || name.isEmpty ? 'Untitled spreadsheet' : name,
    );
  }

  /// Get the header row (first row) of a worksheet.
  Future<List<String>> getSheetHeaders(
    String spreadsheetId,
    String sheetName,
  ) async {
    try {
      final api = await _sheetsApi();
      final range = "'$sheetName'!1:1";
      final result = await api.spreadsheets.values.get(spreadsheetId, range);
      final rows = result.values;
      if (rows == null || rows.isEmpty) return [];
      return rows.first.map((e) => e.toString()).toList();
    } catch (e) {
      throw GSheetsException('Failed to get headers: $e');
    }
  }

  /// Every filled row of a tab, header first, as text (used to import lists).
  Future<List<List<String>>> readTab(String spreadsheetId, String tab) async {
    try {
      final api = await _sheetsApi();
      final result = await api.spreadsheets.values.get(
        spreadsheetId,
        "'$tab'",
        valueRenderOption: 'FORMATTED_VALUE',
      );
      return [
        for (final row in result.values ?? const <List<Object?>>[])
          [for (final cell in row) '${cell ?? ''}'.trim()],
      ].where((r) => r.any((c) => c.isNotEmpty)).toList();
    } catch (e) {
      throw GSheetsException('Failed to read $tab: $e');
    }
  }

  /// The given 1-based rows of a tab, raw (`UNFORMATTED_VALUE`): numbers
  /// as numbers, dates as serials. A blank row comes back empty.
  Future<List<List<Object?>>> readRows(
    String spreadsheetId,
    String tab,
    List<int> rows,
  ) async {
    try {
      final api = await _sheetsApi();
      final out = <List<Object?>>[];
      // Ranges ride in the URL, so ask for a hundred rows at a time.
      for (var i = 0; i < rows.length; i += 100) {
        final chunk = rows.sublist(i, (i + 100).clamp(0, rows.length));
        final result = await api.spreadsheets.values.batchGet(
          spreadsheetId,
          ranges: [for (final r in chunk) "'$tab'!$r:$r"],
          valueRenderOption: 'UNFORMATTED_VALUE',
        );
        final ranges = result.valueRanges ?? const [];
        for (var k = 0; k < chunk.length; k++) {
          out.add(k < ranges.length ? ranges[k].values?.firstOrNull ?? [] : []);
        }
      }
      return out;
    } catch (e) {
      throw GSheetsException('Failed to read rows: $e');
    }
  }

  /// Every row of a tab from row 1, blanks kept so indexes are row numbers,
  /// raw like [readRows].
  Future<List<List<Object?>>> readTabRaw(
    String spreadsheetId,
    String tab,
  ) async {
    try {
      final api = await _sheetsApi();
      final result = await api.spreadsheets.values.get(
        spreadsheetId,
        "'$tab'",
        valueRenderOption: 'UNFORMATTED_VALUE',
      );
      // The range starts at the first filled row, not always row 1.
      final start = _firstRowOf(result.range) ?? 1;
      return [
        for (var r = 1; r < start; r++) const <Object?>[],
        ...?result.values,
      ];
    } catch (e) {
      throw GSheetsException('Failed to read $tab: $e');
    }
  }

  /// Replaces a tab's contents with [rows], creating the tab if needed.
  /// Used for the "Not scanned" / "Count vs expected" check tab.
  Future<void> writeTab(
    String spreadsheetId,
    String tab,
    List<List<String>> rows,
  ) async {
    try {
      if (!(await getWorksheets(spreadsheetId)).contains(tab)) {
        await _addSheet(spreadsheetId, tab);
      }
      final api = await _sheetsApi();
      await api.spreadsheets.values.clear(
        sheets.ClearValuesRequest(),
        spreadsheetId,
        "'$tab'",
      );
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        "'$tab'!A1",
        valueInputOption: 'RAW',
      );
    } catch (e) {
      throw GSheetsException('Failed to write $tab: $e');
    }
  }

  /// Append rows to a worksheet. [rows] is a list of string lists.
  /// Returns the 1-based sheet row number of the first appended row, when
  /// the API reports it.
  Future<int?> appendRows(
    String spreadsheetId,
    String sheetName,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return null;
    try {
      final api = await _sheetsApi();
      final range = "'$sheetName'!A1";
      final result = await api.spreadsheets.values.append(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      return _firstRowOf(result.updates?.updatedRange);
    } catch (e) {
      throw GSheetsException('Failed to append rows: $e');
    }
  }

  /// Overwrite one sheet row (1-based) starting at column A.
  Future<void> updateRow(
    String spreadsheetId,
    String sheetName,
    int row,
    List<String> values,
  ) async {
    try {
      final api = await _sheetsApi();
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [values]),
        spreadsheetId,
        "'$sheetName'!A$row",
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      throw GSheetsException('Failed to update row: $e');
    }
  }

  /// Blank out one sheet row (1-based). Rows are cleared rather than deleted
  /// so row numbers of everything below stay stable.
  Future<void> clearRow(String spreadsheetId, String sheetName, int row) async {
    try {
      final api = await _sheetsApi();
      await api.spreadsheets.values.clear(
        sheets.ClearValuesRequest(),
        spreadsheetId,
        "'$sheetName'!$row:$row",
      );
    } catch (e) {
      throw GSheetsException('Failed to clear row: $e');
    }
  }

  /// Parses the start row from an A1 range like `'Sheet1'!A5:E7`.
  static int? _firstRowOf(String? a1) {
    if (a1 == null) return null;
    final cells = a1.split('!').last;
    final match = RegExp(r'[A-Z]+(\d+)').firstMatch(cells);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Write a header row if the sheet is empty, then append data rows.
  /// Returns the sheet row number of the first data row, when known.
  Future<int?> appendWithHeaders(
    String spreadsheetId,
    String sheetName,
    List<String> headers,
    List<List<String>> dataRows,
  ) async {
    final existing = await getSheetHeaders(spreadsheetId, sheetName);
    final toAppend = <List<String>>[];
    if (existing.isEmpty) toAppend.add(headers);
    toAppend.addAll(dataRows);
    final first = await appendRows(spreadsheetId, sheetName, toAppend);
    if (first == null) return null;
    return existing.isEmpty ? first + 1 : first;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class GSheetsException implements Exception {
  final String message;
  const GSheetsException(this.message);
  @override
  String toString() => 'GSheetsException: $message';
}

class SpreadsheetInfo {
  final String id;
  final String title;
  final DateTime? modifiedTime;
  final String? ownerEmail;

  const SpreadsheetInfo({
    required this.id,
    required this.title,
    this.modifiedTime,
    this.ownerEmail,
  });
}

/// HTTP client that injects Google auth headers into every request.
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class _NoAccess implements Exception {}
