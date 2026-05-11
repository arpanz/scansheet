import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

/// Wraps Google Sign-In + Sheets API v4 + Drive API v3.
/// All methods are safe to call when signed out — they throw [GSheetsException].
class GoogleSheetsService {
  static final GoogleSheetsService instance = GoogleSheetsService._();
  GoogleSheetsService._();

  static const _scopes = [
    sheets.SheetsApi.spreadsheetsScope,
    drive.DriveApi.driveMetadataReadonlyScope,
    drive.DriveApi.driveFileScope,
  ];

  final _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentUser;
  http.Client? _authClient;

  // ─────────────────────────────────────────────────────────────────────────
  // Auth state
  // ─────────────────────────────────────────────────────────────────────────

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// ValueNotifier so UI can react to sign-in/out without polling.
  final ValueNotifier<bool> signedInNotifier = ValueNotifier(false);

  /// Call once in main() to restore a previous sign-in silently.
  Future<void> init() async {
    _googleSignIn.onCurrentUserChanged.listen(_onUserChanged);
    await _googleSignIn.signInSilently();
  }

  void _onUserChanged(GoogleSignInAccount? account) {
    _currentUser = account;
    _authClient = null; // force refresh on next API call
    signedInNotifier.value = account != null;
  }

  /// Opens the Google account picker.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      return account;
    } catch (e) {
      throw GSheetsException('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _authClient = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal: authenticated HTTP client
  // ─────────────────────────────────────────────────────────────────────────

  Future<http.Client> _getClient() async {
    if (_currentUser == null) throw GSheetsException('Not signed in.');
    if (_authClient != null) return _authClient!;
    final auth = await _currentUser!.authHeaders;
    _authClient = GoogleAuthClient(auth);
    return _authClient!;
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

  /// List the user's spreadsheets (most recently modified first).
  /// Optionally filter by [query] string matched against title.
  Future<List<SpreadsheetInfo>> listSpreadsheets({String? query}) async {
    try {
      final api = await _driveApi();
      var q = "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false";
      if (query != null && query.isNotEmpty) {
        q += " and name contains '${query.replaceAll("'", "\\'")}'"; 
      }
      final result = await api.files.list(
        q: q,
        orderBy: 'modifiedTime desc',
        pageSize: 50,
        $fields: 'files(id,name,modifiedTime,owners)',
      );
      return (result.files ?? []).map((f) => SpreadsheetInfo(
        id: f.id ?? '',
        title: f.name ?? 'Untitled',
        modifiedTime: f.modifiedTime,
        ownerEmail: f.owners?.firstOrNull?.emailAddress,
      )).toList();
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

  /// Create a new blank spreadsheet with the given title.
  /// Returns the new spreadsheet ID.
  Future<String> createSpreadsheet(String title) async {
    try {
      final api = await _sheetsApi();
      final result = await api.spreadsheets.create(
        sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: title),
        ),
      );
      return result.spreadsheetId ?? '';
    } catch (e) {
      throw GSheetsException('Failed to create spreadsheet: $e');
    }
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

  /// Append rows to a worksheet. [rows] is a list of string lists.
  Future<void> appendRows(
    String spreadsheetId,
    String sheetName,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return;
    try {
      final api = await _sheetsApi();
      final range = "'$sheetName'!A1";
      await api.spreadsheets.values.append(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    } catch (e) {
      throw GSheetsException('Failed to append rows: $e');
    }
  }

  /// Write a header row if the sheet is empty, then append data rows.
  Future<void> appendWithHeaders(
    String spreadsheetId,
    String sheetName,
    List<String> headers,
    List<List<String>> dataRows,
  ) async {
    final existing = await getSheetHeaders(spreadsheetId, sheetName);
    final toAppend = <List<String>>[];
    if (existing.isEmpty) toAppend.add(headers);
    toAppend.addAll(dataRows);
    await appendRows(spreadsheetId, sheetName, toAppend);
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
