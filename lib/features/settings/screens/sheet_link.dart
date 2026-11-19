import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/sheets_sync_service.dart';
import '../../../core/widgets/ss.dart';

/// Asks for a Google Sheets link and opens that sheet. The prompt starts
/// with the clipboard when it already holds a Sheets link. A sheet ScanSheet
/// can't reach yet opens in Google's file picker so the user can allow it.
/// Returns null if the user backs out or the sheet can't be opened (a toast
/// says why).
Future<SpreadsheetInfo?> useSheetFromLink(BuildContext context) async {
  var initial = '';
  try {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (GoogleSheetsService.spreadsheetIdFromLink(clip) != null) {
      initial = clip.trim();
    }
  } catch (_) {}
  if (!context.mounted) return null;
  final link = await showSsTextPrompt(
    context,
    title: 'Use a sheet from a link',
    label: 'Google Sheets link',
    initial: initial,
    action: 'Use sheet',
  );
  if (link == null || !context.mounted) return null;
  try {
    return await GoogleSheetsService.instance.openSpreadsheetFromLink(link);
  } on GSheetsException catch (e) {
    if (context.mounted) showSsToast(context, e.message);
    return null;
  }
}

/// Shows [spreadsheetId] in Google's file picker so the user can let
/// ScanSheet reach it, then sends the rows waiting for it. Returns whether
/// the user allowed it.
Future<bool> allowSheetAccess(
  BuildContext context,
  String spreadsheetId,
) async {
  try {
    final picked = await GoogleSheetsService.instance.pickInDrive(
      spreadsheetId: spreadsheetId,
    );
    if (picked == null) return false;
    final sync = SheetsSyncService.instance;
    sync.forgetMissing(spreadsheetId);
    sync.retryNow();
    return true;
  } on GSheetsException catch (e) {
    if (context.mounted) showSsToast(context, e.message);
    return false;
  }
}
