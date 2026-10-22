import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/sync_queue_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ss.dart';
import '../models/scan_session.dart';
import 'export_templates_screen.dart';

class DoneForNowScreen extends StatelessWidget {
  final ScanSession session;
  final int addedThisVisit;
  final int totalRows;
  const DoneForNowScreen({
    super.key,
    required this.session,
    required this.addedThisVisit,
    required this.totalRows,
  });

  Future<void> _export(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExportTemplatesScreen(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final pending = session.destination == SessionDestination.googleSheets
        ? SyncQueueService.pendingForSession(session.id)
        : 0;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.arrowLeft, color: c.ink),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SAVED · STILL OPEN FOR MORE',
                style: SsText.eyebrow(color: c.emerald),
              ),
              const SizedBox(height: 8),
              Text(
                session.name,
                style: SsText.title(color: c.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                children: [
                  Text(
                    '${addedThisVisit} added this visit',
                    style: SsText.sans(size: 14, color: c.ink2),
                  ),
                  Text(
                    '$totalRows total rows',
                    style: SsText.sans(size: 14, color: c.ink2),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (session.destination == SessionDestination.googleSheets)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.table2, color: c.emerald),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'In Google Sheets',
                              style: SsText.label(color: c.ink),
                            ),
                          ),
                          Icon(
                            pending == 0
                                ? LucideIcons.circleCheck
                                : LucideIcons.refreshCw,
                            color: c.emerald,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pending == 0
                            ? 'All rows synced'
                            : '$pending rows waiting to sync',
                        style: SsText.sans(size: 13, color: c.muted),
                      ),
                      if (session.spreadsheetId != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://docs.google.com/spreadsheets/d/${session.spreadsheetId}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(LucideIcons.externalLink, size: 16),
                          label: const Text('Open in Sheets'),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              Text(
                'Need a file? Save a copy anytime',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: c.ink2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _formatCard(
                      context,
                      LucideIcons.table2,
                      'Excel',
                      '.xlsx · formatted',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _formatCard(
                      context,
                      LucideIcons.fileText,
                      'CSV',
                      '.csv · plain text',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _export(context),
                      icon: const Icon(LucideIcons.download, size: 17),
                      label: const Text('Save to Files'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _export(context),
                      icon: const Icon(LucideIcons.share2, size: 17),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: c.ink,
                  foregroundColor: c.onInk,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Done for now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(
                  'Keep scanning',
                  style: SsText.sans(
                    size: 15,
                    weight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formatCard(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final c = context.ss;
    return InkWell(
      onTap: () => _export(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 22, color: c.ink),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SsText.label(color: c.ink)),
                Text(subtitle, style: SsText.caption(color: c.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
