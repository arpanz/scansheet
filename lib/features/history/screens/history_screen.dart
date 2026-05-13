import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/widgets/pro_crown.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../../../core/models/sync_queue_item.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../history/models/history_entry.dart';
import '../../single_gen/models/generator_type.dart';
import '../../scan/models/scan_session.dart';
import '../../scan/widgets/session_export_sheet.dart';
import '../../scan/screens/scan_session_screen.dart';
import './entry_detail_screen.dart';
import '../../../core/utils/app_router.dart';

enum _SessionFilter { all, today, unsynced, csv, sheets }

// How many real items between each small native ad in the list.
const int _kAdInterval = 3;

class HistoryScreen extends StatefulWidget {
  final ValueNotifier<String?>? cloneTextListenable;

  const HistoryScreen({super.key, this.cloneTextListenable});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<ScanEntry> _visibleScans(List<ScanEntry> scans) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return scans;
    return scans.where((e) => e.raw.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.themeAccent,
          unselectedLabelColor: context.themeTextSecondary,
          indicatorColor: context.themeAccent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Scanned'),
            Tab(text: 'Sheets'),
          ],
        ),
        actions: [
          const ProCrownIcon(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (val) async {
              bool cleared = false;
              if (val == 'clear_scanned') {
                final ok = await _confirmClear(
                  context,
                  'Clear scan history?',
                  'This will permanently remove all scanned records.',
                );
                if (ok) {
                  await ScanHistoryService.clear();
                  cleared = true;
                }
              } else if (val == 'clear_sessions') {
                final ok = await _confirmClear(
                  context,
                  'Clear all sessions?',
                  'This will permanently delete all scan sessions and their rows.',
                );
                if (ok) {
                  await ScanSessionService.clearAll();
                  cleared = true;
                }
              }
              if (cleared && mounted) setState(() {});
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear_scanned',
                child: Text('Clear Scanned'),
              ),
              const PopupMenuItem(
                value: 'clear_sessions',
                child: Text('Clear Sessions'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ScannedTab(query: _query, visibleScans: _visibleScans),
                const _SessionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(
    BuildContext context,
    String title,
    String body,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.themeCard,
        title: Text(
          title,
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(color: context.themeTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: context.themeError),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

// ── helpers shared across tabs ────────────────────────────────────────────────
Future<bool> _confirmDelete(BuildContext context, String label) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: context.themeCard,
      title: Text(
        'Delete entry?',
        style: TextStyle(
          color: context.themeTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        'Remove "$label" from history? This cannot be undone.',
        style: TextStyle(color: context.themeTextSecondary, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.themeError),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

(IconData, Color) _iconAndColorFor(String type) => switch (type) {
  'url' => (Icons.link_rounded, const Color(0xFF3B82F6)),
  'wifi' => (Icons.wifi_rounded, const Color(0xFF16A34A)),
  'vcard' => (Icons.person_rounded, const Color(0xFF8B5CF6)),
  'email' => (Icons.email_rounded, const Color(0xFFEF4444)),
  'phone' => (Icons.phone_rounded, const Color(0xFF16A34A)),
  'sms' => (Icons.sms_rounded, const Color(0xFF06B6D4)),
  'geo' => (Icons.location_on_rounded, const Color(0xFFF59E0B)),
  _ => (Icons.text_fields_rounded, const Color(0xFF6B7280)),
};

String _labelFor(String type) => switch (type) {
  'url' => 'Link',
  'wifi' => 'Wi-Fi',
  'vcard' => 'Contact',
  'email' => 'Email',
  'phone' => 'Phone',
  'sms' => 'SMS',
  'geo' => 'Location',
  _ => 'Text',
};

String _vcardField(String raw, String mecardKey, String vcardKey) {
  final meMatch = RegExp('$mecardKey:(.*?);').firstMatch(raw);
  if (meMatch != null) return meMatch.group(1)?.trim() ?? '';
  final vcMatch = RegExp(
    '$vcardKey[^:]*:(.*?)(?:\r?\n|\$)',
    caseSensitive: false,
  ).firstMatch(raw);
  return vcMatch?.group(1)?.trim() ?? '';
}

// ── Ad slot helper ────────────────────────────────────────────────────────────
// Wraps a small native ad in a padded card-like container.
Widget _buildSmallNativeAdSlot() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AdManager.instance.getNativeAdWidget(),
    ),
  );
}

// Wraps a medium native ad in a padded card-like container.
Widget _buildMediumNativeAdSlot() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AdManager.instance.getNativeAdWidget(isMedium: true),
    ),
  );
}

// ── Scanned Tab ──────────────────────────────────────────────────────────────
class _ScannedTab extends StatefulWidget {
  final String query;
  final List<ScanEntry> Function(List<ScanEntry>) visibleScans;

  const _ScannedTab({required this.query, required this.visibleScans});

  @override
  State<_ScannedTab> createState() => _ScannedTabState();
}

class _ScannedTabState extends State<_ScannedTab> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ScanHistoryService.box.listenable(),
      builder: (context, _, _) {
        final scans = ScanHistoryService.getAll();
        final visible = widget.visibleScans(scans);

        if (scans.isEmpty) {
          // Empty state: medium native ad below the empty illustration.
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _EmptyState(
                icon: Icons.qr_code_scanner_rounded,
                message: 'No scans yet',
                sub: 'Every code you scan will be recorded here.',
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AdManager.instance.getNativeAdWidget(isMedium: true),
                ),
              ),
            ],
          );
        }
        if (visible.isEmpty) {
          return _NoSearchResults(query: widget.query);
        }

        final bool useMediumAd = visible.length < 3;
        // Build a merged list: real items + ad slots every _kAdInterval items.
        // If items < 3, we just show one medium ad at the end.
        final int adCount = useMediumAd ? 1 : (visible.length ~/ _kAdInterval);
        final itemCount = visible.length + adCount;

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) {
            if (useMediumAd) {
              if (i == visible.length) return _buildMediumNativeAdSlot();
            } else {
              // Every (_kAdInterval + 1)th slot is an ad.
              final adPeriod = _kAdInterval + 1;
              if ((i + 1) % adPeriod == 0) {
                return _buildSmallNativeAdSlot();
              }
            }

            final realIndex = useMediumAd ? i : i - (i ~/ (_kAdInterval + 1));
            if (realIndex >= visible.length) return const SizedBox.shrink();
            final e = visible[realIndex];
            final displayLabel = e.type == 'vcard'
                ? (_vcardField(e.raw, 'N', 'FN').isNotEmpty
                      ? _vcardField(e.raw, 'N', 'FN')
                      : 'Contact')
                : (e.raw.length > 40 ? '${e.raw.substring(0, 40)}…' : e.raw);
            return Dismissible(
              key: Key('${e.scannedAt.toIso8601String()}_${e.raw.hashCode}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(ctx, displayLabel),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: context.themeError.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: context.themeError,
                ),
              ),
              onDismissed: (_) async {
                await ScanHistoryService.deleteEntry(e);
              },
              child: _ScanEntryCard(entry: e),
            );
          },
        );
      },
    );
  }
}

// ── Scan entry card ──────────────────────────────────────────────────────────
class _ScanEntryCard extends StatelessWidget {
  final ScanEntry entry;
  const _ScanEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (icon, color) = _iconAndColorFor(entry.type);
    final typeLabel = _labelFor(entry.type);

    Widget leadingWidget;
    String titleText;
    if (entry.type == 'vcard') {
      final name = _vcardField(entry.raw, 'N', 'FN');
      final initials = name
          .trim()
          .split(RegExp(r'\s+'))
          .take(2)
          .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
          .join();
      leadingWidget = CircleAvatar(
        radius: 22,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
      titleText = name.isEmpty ? 'Unknown Contact' : name;
    } else {
      leadingWidget = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      );
      titleText = entry.raw;
    }

    return AppCard(
      onTap: () {
        HapticFeedback.selectionClick();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ScanDetailSheet(entry: entry),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d · h:mm a').format(entry.scannedAt),
                        style: t.textTheme.labelSmall?.copyWith(
                          color: context.themeTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: entry.type == 'url'
                          ? context.themeAccent
                          : context.themeTextPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (entry.type == 'vcard') ...[
                    const SizedBox(height: 2),
                    Builder(
                      builder: (ctx) {
                        final org = _vcardField(entry.raw, 'ORG', 'ORG');
                        final phone = _vcardField(entry.raw, 'TEL', 'TEL');
                        final sub = org.isNotEmpty ? org : phone;
                        if (sub.isEmpty) return const SizedBox.shrink();
                        return Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: context.themeTextSecondary,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.themeTextSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scan detail bottom sheet ──────────────────────────────────────────────────
class _ScanDetailSheet extends StatelessWidget {
  final ScanEntry entry;
  const _ScanDetailSheet({required this.entry});

  (IconData, Color) get _ic => _iconAndColorFor(entry.type);

  String get _typeLabel => switch (entry.type) {
    'url' => 'Web Link',
    'wifi' => 'Wi-Fi Network',
    'vcard' => 'Contact / vCard',
    'email' => 'Email Address',
    'phone' => 'Phone Number',
    'sms' => 'SMS Message',
    'geo' => 'Location',
    _ => 'Plain Text',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (icon, color) = _ic;
    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel,
                          style: t.textTheme.titleMedium?.copyWith(
                            color: context.themeTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateFormat(
                            'MMM d, y • h:mm a',
                          ).format(entry.scannedAt),
                          style: t.textTheme.bodySmall?.copyWith(
                            color: context.themeTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: context.themeTextSecondary,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildContent(context, t.textTheme, color),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: _buildActions(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TextTheme t, Color color) {
    if (entry.type == 'vcard') return _buildVcardCard(context, t, color);
    if (entry.type == 'wifi') return _buildWifiCard(context, t);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themeBorder),
      ),
      child: SelectableText(
        entry.raw,
        style: t.bodyMedium?.copyWith(
          color: entry.type == 'url'
              ? context.themeAccent
              : context.themeTextPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildWifiCard(BuildContext context, TextTheme t) {
    final ssid = RegExp(r'S:(.*?);').firstMatch(entry.raw)?.group(1) ?? '';
    final password = RegExp(r';P:(.*?);').firstMatch(entry.raw)?.group(1) ?? '';
    final security =
        RegExp(r'T:(.*?);').firstMatch(entry.raw)?.group(1) ?? 'WPA';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        children: [
          _DetailRow(icon: Icons.wifi_rounded, label: 'Network', value: ssid),
          if (password.isNotEmpty) ...[
            Divider(height: 16, color: context.themeBorder),
            _DetailRow(
              icon: Icons.lock_rounded,
              label: 'Password',
              value: password,
            ),
          ],
          Divider(height: 16, color: context.themeBorder),
          _DetailRow(
            icon: Icons.security_rounded,
            label: 'Security',
            value: security,
          ),
        ],
      ),
    );
  }

  Widget _buildVcardCard(BuildContext context, TextTheme t, Color color) {
    final name = _vcardField(entry.raw, 'N', 'FN');
    final phone = _vcardField(entry.raw, 'TEL', 'TEL');
    final email = _vcardField(entry.raw, 'EMAIL', 'EMAIL');
    final org = _vcardField(entry.raw, 'ORG', 'ORG');
    final url = _vcardField(entry.raw, 'URL', 'URL');
    final address = _vcardField(entry.raw, 'ADR', 'ADR');
    final note = _vcardField(entry.raw, 'NOTE', 'NOTE');

    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Container(
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Unknown Contact' : name,
                        style: t.titleMedium?.copyWith(
                          color: context.themeTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (org.isNotEmpty)
                        Text(
                          org,
                          style: t.bodySmall?.copyWith(
                            color: context.themeTextSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                if (phone.isNotEmpty)
                  _VcardFieldTile(
                    icon: Icons.phone_rounded,
                    color: const Color(0xFF16A34A),
                    label: 'Phone',
                    value: phone,
                  ),
                if (email.isNotEmpty)
                  _VcardFieldTile(
                    icon: Icons.email_rounded,
                    color: const Color(0xFFEA4335),
                    label: 'Email',
                    value: email,
                  ),
                if (url.isNotEmpty)
                  _VcardFieldTile(
                    icon: Icons.link_rounded,
                    color: const Color(0xFF1E5BEA),
                    label: 'Website',
                    value: url,
                  ),
                if (address.isNotEmpty)
                  _VcardFieldTile(
                    icon: Icons.location_on_rounded,
                    color: const Color(0xFFF59E0B),
                    label: 'Address',
                    value: address,
                  ),
                if (note.isNotEmpty)
                  _VcardFieldTile(
                    icon: Icons.notes_rounded,
                    color: const Color(0xFF64748B),
                    label: 'Note',
                    value: note,
                  ),
                if (phone.isEmpty &&
                    email.isEmpty &&
                    url.isEmpty &&
                    address.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      entry.raw,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      ActionChip(
        avatar: const Icon(Icons.copy_rounded, size: 15),
        label: const Text('Copy'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: entry.raw));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Copied to clipboard'),
                backgroundColor: context.themeSuccess,
                duration: const Duration(seconds: 1),
              ),
            );
            Navigator.pop(context);
          }
        },
      ),
      if (entry.type == 'url')
        ActionChip(
          avatar: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('Open'),
          onPressed: () async {
            final uri = Uri.tryParse(entry.raw);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            if (context.mounted) Navigator.pop(context);
          },
        ),
      if (entry.type == 'phone')
        ActionChip(
          avatar: const Icon(Icons.call_rounded, size: 15),
          label: const Text('Call'),
          onPressed: () async {
            final uri = Uri.tryParse('tel:${entry.raw}');
            if (uri != null) await launchUrl(uri);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      if (entry.type == 'email')
        ActionChip(
          avatar: const Icon(Icons.send_rounded, size: 15),
          label: const Text('Send Email'),
          onPressed: () async {
            final uri = Uri.tryParse('mailto:${entry.raw}');
            if (uri != null) await launchUrl(uri);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      if (entry.type == 'wifi')
        ActionChip(
          avatar: const Icon(Icons.password_rounded, size: 15),
          label: const Text('Copy Password'),
          onPressed: () async {
            final pass =
                RegExp(r';P:(.*?);').firstMatch(entry.raw)?.group(1) ?? '';
            await Clipboard.setData(ClipboardData(text: pass));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Password copied'),
                  backgroundColor: context.themeSuccess,
                  duration: const Duration(seconds: 1),
                ),
              );
              Navigator.pop(context);
            }
          },
        ),
      ActionChip(
        avatar: const Icon(Icons.share_rounded, size: 15),
        label: const Text('Share'),
        onPressed: () async {
          await SharePlus.instance.share(ShareParams(text: entry.raw));
          if (context.mounted) {
            AdManager.instance.showInterstitial(context);
          }
        },
      ),
    ];
  }
}

// ── vCard field tile (detail sheet) ──────────────────────────────────────────
class _VcardFieldTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _VcardFieldTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied'),
                backgroundColor: context.themeSuccess,
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: context.themeTextSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.themeTextPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 14,
                color: context.themeTextSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail row (wifi card) ────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: context.themeTextSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: context.themeTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 13, color: context.themeTextPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
class HistoryDetailScreen extends StatefulWidget {
  final HistoryEntry entry;
  final ValueNotifier<String?>? cloneListenable;

  const HistoryDetailScreen({
    super.key,
    required this.entry,
    this.cloneListenable,
  });

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final _key = GlobalKey();
  bool _isSavingToGallery = false;

  Future<Uint8List?> _captureBytes() async {
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final boundary =
          _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _share() async {
    final bytes = await _captureBytes();
    if (bytes == null) return;
    final tmp = await getTemporaryDirectory();
    final path =
        '${tmp.path}/qr_share_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    if (mounted) AdManager.instance.showInterstitial(context);
  }

  Future<void> _saveToGallery() async {
    setState(() => _isSavingToGallery = true);
    try {
      final bytes = await _captureBytes();
      if (bytes == null) throw Exception('Could not render image');
      final tmp = await getTemporaryDirectory();
      final path =
          '${tmp.path}/qr_save_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(bytes);
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to gallery'),
            backgroundColor: context.themeSuccess,
          ),
        );
        AdManager.instance.showInterstitial(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: context.themeError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingToGallery = false);
    }
  }

  void _regenerate() {
    final notifier = widget.cloneListenable;
    if (notifier == null) return;
    notifier.value = widget.entry.data;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final genType = GeneratorType.values.firstWhere(
      (g) => g.name == e.generatorType,
      orElse: () => GeneratorType.qrCode,
    );
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(e.label, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.cloneListenable != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Re-generate',
              onPressed: _regenerate,
            ),
          IconButton(
            icon: _isSavingToGallery
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 20),
            tooltip: 'Save to gallery',
            onPressed: _isSavingToGallery ? null : _saveToGallery,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            tooltip: 'Share',
            onPressed: _share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: RepaintBoundary(
                  key: _key,
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    color: Colors.white,
                    child: e.imagePath == null
                        ? _buildCodeWidget(e, genType)
                        : FutureBuilder<bool>(
                            future: File(e.imagePath!).exists(),
                            builder: (ctx, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox(
                                  width: 240,
                                  height: 240,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              if (snap.data == true) {
                                return Image.file(
                                  File(e.imagePath!),
                                  width: 240,
                                  height: 240,
                                  fit: BoxFit.contain,
                                );
                              }
                              return _buildCodeWidget(e, genType);
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.data_object_rounded,
                      size: 16,
                      color: context.themeTextSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Encoded Data',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: context.themeTextSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: e.data));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Copied'),
                              backgroundColor: context.themeSuccess,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: context.themeTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  e.data,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: context.themeTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _TypeBadge(dataType: e.dataType),
                const SizedBox(width: 6),
                _TypeBadge(dataType: e.generatorType, isGenType: true),
                const Spacer(),
                Text(
                  DateFormat('MMM d, y • h:mm a').format(e.createdAt),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: context.themeTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AdManager.instance.getNativeAdWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeWidget(HistoryEntry e, GeneratorType genType) {
    if (genType == GeneratorType.qrCode) {
      return QrImageView(
        data: e.data.isEmpty ? '.' : e.data,
        version: QrVersions.auto,
        size: 240,
      );
    }
    return BarcodeWidget(
      barcode: Barcode.code128(),
      data: e.data.isEmpty ? '12345' : e.data,
      width: 260,
      height: 100,
    );
  }
}


class _TypeBadge extends StatelessWidget {
  final String dataType;
  final bool isGenType;
  const _TypeBadge({required this.dataType, this.isGenType = false});

  @override
  Widget build(BuildContext context) {
    final label = isGenType
        ? (dataType == 'qrCode' ? 'QR' : dataType.toUpperCase())
        : dataType.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.themeAccentContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: context.themeAccent,
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SyncBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  final String query;
  const _NoSearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: context.themeTextSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.themeTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.themeAccent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: context.themeAccent.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.themeTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.themeTextSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsTab extends StatefulWidget {
  const _SessionsTab();

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  List<ScanSession> _sessions = [];
  _SessionFilter _filter = _SessionFilter.all;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    // Listen to metadata box changes.
    ScanSessionService.metaBox.listenable().addListener(_loadSessions);
    SyncQueueService.stats.addListener(_loadSessions);
  }

  @override
  void dispose() {
    ScanSessionService.metaBox.listenable().removeListener(_loadSessions);
    SyncQueueService.stats.removeListener(_loadSessions);
    super.dispose();
  }

  void _loadSessions() {
    if (!mounted) return;
    final all = ScanSessionService.getAllSessions();
    setState(() {
      _sessions = all.where((s) {
        switch (_filter) {
          case _SessionFilter.all:
            return true;
          case _SessionFilter.today:
            final now = DateTime.now();
            return s.createdAt.year == now.year &&
                s.createdAt.month == now.month &&
                s.createdAt.day == now.day;
          case _SessionFilter.unsynced:
            final items = SyncQueueService.getAll()
                .where((i) => i.sessionId == s.id).toList();
            return s.destination == SessionDestination.googleSheets &&
                items.any((i) => i.status != SyncStatus.synced);
          case _SessionFilter.csv:
            return s.destination == SessionDestination.localCsv ||
                s.destination == SessionDestination.localXlsx;
          case _SessionFilter.sheets:
            return s.destination == SessionDestination.googleSheets;
        }
      }).toList();
    });
  }

  Future<void> _deleteSession(ScanSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text(
          '"${session.name}" and all its rows will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ScanSessionService.deleteSession(session.id);
      _loadSessions();
    }
  }

  void _openRowsList(BuildContext context, ScanSession session) {
    final rows = ScanSessionService.getRows(session.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.themeBg,
          appBar: AppBar(
            backgroundColor: ctx.themeCard,
            elevation: 0,
            scrolledUnderElevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: ctx.themeTextPrimary),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: TextStyle(
                    color: ctx.themeTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${rows.length} ${rows.length == 1 ? 'row' : 'rows'}',
                  style: TextStyle(
                    color: ctx.themeTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          body: rows.isEmpty
              ? Center(
                  child: Text(
                    'No rows yet.',
                    style: TextStyle(color: ctx.themeTextSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemCount: rows.length,
                  itemBuilder: (ctx2, i) {
                    final row = rows[i];
                    final primary =
                        row.values.isNotEmpty ? row.values.first : '—';
                    return Material(
                      color: ctx2.themeCard,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push<bool>(
                          ctx2,
                          MaterialPageRoute(
                            builder: (_) => EntryDetailScreen(
                              session: session,
                              row: row,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: ctx2.themeAccent
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${row.rowIndex + 1}',
                                    style: TextStyle(
                                      color: ctx2.themeAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  primary,
                                  style: TextStyle(
                                    color: ctx2.themeTextPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: ctx2.themeTextSecondary,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _filterLabel(_SessionFilter f) => switch (f) {
    _SessionFilter.all => 'All',
    _SessionFilter.today => 'Today',
    _SessionFilter.unsynced => 'Unsynced',
    _SessionFilter.csv => 'CSV / XLSX',
    _SessionFilter.sheets => 'Sheets',
  };

  Widget _buildGroupedList(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Build ordered groups: each entry is (headerLabel, [sessions])
    final Map<String, List<ScanSession>> groups = {};
    for (final s in _sessions) {
      final d = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
      final String key;
      if (d == today) {
        key = 'TODAY';
      } else if (d == yesterday) {
        key = 'YESTERDAY';
      } else {
        key = DateFormat('d MMM yyyy').format(s.createdAt).toUpperCase();
      }
      groups.putIfAbsent(key, () => []).add(s);
    }

    return CustomScrollView(
      slivers: [
        for (final entry in groups.entries) ...[
          // Date group header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                entry.key,
                style: TextStyle(
                  color: context.themeTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          // Cards for this group
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemCount: entry.value.length,
              itemBuilder: (ctx, i) =>
                  _buildSessionCard(ctx, entry.value[i]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildSessionCard(BuildContext ctx, ScanSession session) {
    final rowCount = ScanSessionService.getRowCount(session.id);
    final timeStr = DateFormat('h:mm a').format(session.createdAt);

    // Format icon + color
    final bool isSheets = session.destination == SessionDestination.googleSheets;
    final formatIcon =
        isSheets ? Icons.table_chart_rounded : Icons.grid_on_rounded;
    final formatColor =
        isSheets ? const Color(0xFF16A34A) : const Color(0xFF6B7280);
    final formatLabel = isSheets ? 'Sheets' : (session.destination ==
            SessionDestination.localXlsx ? 'XLSX' : 'CSV');

    final sessionQueueItems = SyncQueueService.getAll()
        .where((i) => i.sessionId == session.id)
        .toList();

    final pendingCount = sessionQueueItems
        .where((i) => i.status == SyncStatus.pending || i.status == SyncStatus.syncing)
        .length;
    final hasFailed = sessionQueueItems.any((i) => i.status == SyncStatus.failed);
    final allSynced = sessionQueueItems.isNotEmpty &&
        sessionQueueItems.every((i) => i.status == SyncStatus.synced);

    // Product name preview: first values of each row's first scan column
    final rows = ScanSessionService.getRows(session.id);
    final previewNames = rows
        .take(3)
        .map((r) => r.values.isNotEmpty ? r.values.first : null)
        .whereType<String>()
        .where((v) => v.isNotEmpty && v != '…')
        .toList();
    final previewStr = previewNames.isNotEmpty
        ? previewNames.join(', ') + (rowCount > 3 ? '…' : '')
        : null;

    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
      ),
      confirmDismiss: (_) async {
        await _deleteSession(session);
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
          color: ctx.themeCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ctx.themeBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: formatColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: formatColor.withValues(alpha: 0.25)),
            ),
            child: Icon(formatIcon, color: formatColor, size: 20),
          ),
          title: Row(
            children: [
              if (session.isActive) ...[
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4F8EF7), shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  session.name,
                  style: TextStyle(
                    color: ctx.themeTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSheets) ...[
                const SizedBox(width: 8),
                if (allSynced)
                  const _SyncBadge(label: 'Synced', color: Color(0xFF16A34A))
                else if (hasFailed)
                  const _SyncBadge(label: 'Failed', color: Color(0xFFEF4444))
                else if (pendingCount > 0)
                  _SyncBadge(label: 'Queued • $pendingCount', color: const Color(0xFFF59E0B))
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              // Row count + format + time
              Row(
                children: [
                  Text(
                    '$rowCount ${rowCount == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      color: ctx.themeTextSecondary, fontSize: 12,
                    ),
                  ),
                  Text(
                    ' · $formatLabel · $timeStr',
                    style: TextStyle(
                      color: ctx.themeTextSecondary, fontSize: 12,
                    ),
                  ),
                ],
              ),
              // Product name preview
              if (previewStr != null) ...[
                const SizedBox(height: 2),
                Text(
                  previewStr,
                  style: TextStyle(
                    color: ctx.themeTextSecondary, fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.format_list_numbered_rounded,
                    size: 20, color: ctx.themeTextSecondary),
                tooltip: 'View rows',
                onPressed:
                    rowCount == 0 ? null : () => _openRowsList(ctx, session),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined,
                    size: 20, color: ctx.themeAccent),
                tooltip: 'Export',
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SessionExportSheet(session: session),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: ctx.themeTextSecondary),
                onSelected: (v) async {
                  if (v == 'end') {
                    await ScanSessionService.endSession(session.id);
                    _loadSessions();
                  }
                  if (v == 'delete') _deleteSession(session);
                },
                itemBuilder: (_) => [
                  if (session.isActive)
                    const PopupMenuItem(
                      value: 'end', child: Text('End Session'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => Navigator.push(
            ctx, FadeSlideRoute(page: ScanSessionScreen(session: session)),
          ).then((_) => _loadSessions()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ScanSessionService.getAllSessions().isEmpty) {
      return _emptyState(context);
    }

    return Column(
      children: [
        // ── Filter chips ────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in _SessionFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filterLabel(f)),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _loadSessions();
                    },
                    selectedColor: context.themeAccent.withValues(alpha: 0.15),
                    checkmarkColor: context.themeAccent,
                    labelStyle: TextStyle(
                      color: _filter == f
                          ? context.themeAccent
                          : context.themeTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _filter == f
                          ? context.themeAccent.withValues(alpha: 0.4)
                          : context.themeBorder,
                    ),
                    backgroundColor: context.themeCard,
                    shape: const StadiumBorder(),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
            ],
          ),
        ),

        // ── Grouped list ────────────────────────────────────
        Expanded(
          child: _sessions.isEmpty
              ? Center(
                  child: Text(
                    'No sessions match this filter.',
                    style: TextStyle(color: context.themeTextSecondary),
                  ),
                )
              : _buildGroupedList(context),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.table_chart_outlined,
            size: 56,
            color: context.themeTextSecondary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'No scan sessions yet.',
            style: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Go to Scan tab and tap 📋 to start a session.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.themeTextSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
