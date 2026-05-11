import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/scan_session_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/scan_session.dart';
import '../screens/export_templates_screen.dart';

/// Lightweight bottom sheet that navigates to the full ExportTemplatesScreen.
class SessionExportSheet extends StatelessWidget {
  final ScanSession session;

  const SessionExportSheet({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final rows = ScanSessionService.getRows(session.id);
    final rowCount = rows.length;

    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeBorder,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header row
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: context.themeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.file_download_rounded,
                      color: context.themeAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Session',
                          style: TextStyle(
                            color: context.themeTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$rowCount ${rowCount == 1 ? 'row' : 'rows'} · ${session.columnCount} columns',
                          style: TextStyle(
                            color: context.themeTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: context.themeTextSecondary, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              if (rowCount == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.themeError.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.themeError.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: context.themeError, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No rows collected yet. Scan some items first.',
                            style: TextStyle(color: context.themeError, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // CTA — open full Export & Templates screen
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context); // close this sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExportTemplatesScreen(session: session),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text(
                    'Choose Format & Export',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.themeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Quick-access hint row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_rows_rounded, size: 14, color: context.themeTextSecondary),
                  const SizedBox(width: 5),
                  Text(
                    'CSV · Excel · Google Sheets · Templates',
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
