import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/sync_queue_item.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/services/sync_queue_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pro_crown.dart';
import 'connect_sheets_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _clearingData = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanPrefs = context.watch<ScanningPreferences>();
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [ProCrownIcon()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Google Sheets ────────────────────────────────────────────────────
          _SectionHeader(label: 'Google Sheets'),
          _GoogleAccountCard(),
          const SizedBox(height: 20),

          // ── Appearance ──────────────────────────────────────────────────────
          _SectionHeader(label: 'Appearance'),
          AppCard(
            child: Column(children: [_ThemeTile(provider: themeProvider)]),
          ),
          const SizedBox(height: 20),

          // ── Scanning ────────────────────────────────────────────────────────
          _SectionHeader(label: 'Scanning'),
          AppCard(
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.volume_up_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Sound on scan',
                  subtitle: 'Play a beep when a code is scanned',
                  value: scanPrefs.soundEnabled,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    scanPrefs.setSoundEnabled(v);
                  },
                ),
                _Divider(),
                _SwitchTile(
                  icon: Icons.vibration_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate on successful scan',
                  value: scanPrefs.vibrateEnabled,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    scanPrefs.setVibrateEnabled(v);
                  },
                ),
                _Divider(),
                _SwitchTile(
                  icon: Icons.flashlight_on_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Torch on by default',
                  subtitle: 'Start scanner with torch enabled',
                  value: scanPrefs.torchDefault,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    scanPrefs.setTorchDefault(v);
                  },
                ),
                _Divider(),
                _SwitchTile(
                  icon: Icons.center_focus_strong_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: 'Auto-focus',
                  subtitle: 'Continuously auto-focus camera',
                  value: scanPrefs.autoFocus,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    scanPrefs.setAutoFocus(v);
                  },
                ),
                _Divider(),
                _LayoutModeTile(scanPrefs: scanPrefs),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Sessions ────────────────────────────────────────────────────────
          _SectionHeader(label: 'Sessions'),
          AppCard(child: _DuplicateTile(scanPrefs: scanPrefs)),
          const SizedBox(height: 20),

          // ── Data ────────────────────────────────────────────────────────────
          _SectionHeader(label: 'Data'),
          AppCard(
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.delete_sweep_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Clear scan history',
                  subtitle: 'Remove all individually scanned records',
                  trailing: _clearingData
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: () => _confirmClear(
                    context,
                    title: 'Clear scan history?',
                    body:
                        'All individually scanned records will be permanently deleted.',
                    onConfirm: () async {
                      setState(() => _clearingData = true);
                      await ScanHistoryService.clear();
                      setState(() => _clearingData = false);
                      if (mounted) _showSnack('Scan history cleared');
                    },
                  ),
                ),
                _Divider(),
                _ActionTile(
                  icon: Icons.table_rows_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Clear all sessions',
                  subtitle: 'Delete all scan sessions and their rows',
                  onTap: () => _confirmClear(
                    context,
                    title: 'Clear all sessions?',
                    body:
                        'All sessions and their scanned rows will be permanently deleted.',
                    onConfirm: () async {
                      setState(() => _clearingData = true);
                      await ScanSessionService.clearAll();
                      setState(() => _clearingData = false);
                      if (mounted) _showSnack('All sessions cleared');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Sync Queue ──────────────────────────────────────────────────────
          _SectionHeader(label: 'Offline Sync'),
          _SyncQueueCard(),
          const SizedBox(height: 20),

          // ── About ────────────────────────────────────────────────────────────
          _SectionHeader(label: 'About'),
          AppCard(
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Rate ScanSheet',
                  subtitle: 'Enjoying the app? Leave a review',
                  onTap: () => _launchUrl(
                    'https://play.google.com/store/apps/details?id=com.arpanz.scansheet',
                  ),
                ),
                _Divider(),
                _ActionTile(
                  icon: Icons.privacy_tip_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Privacy Policy',
                  subtitle: null,
                  onTap: () =>
                      _launchUrl('https://arpanz.github.io/scansheet/privacy'),
                ),
                _Divider(),
                _InfoTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: context.themeTextSecondary,
                  title: 'Version',
                  value: _version.isEmpty ? '…' : _version,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made with ♥ by Arpan',
              style: TextStyle(
                fontSize: 12,
                color: context.themeTextSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
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
    if (ok == true) await onConfirm();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: context.themeSuccess,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Theme tile ────────────────────────────────────────────────────────────────
class _ThemeTile extends StatelessWidget {
  final ThemeProvider provider;
  const _ThemeTile({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Theme',
                style: TextStyle(
                  color: context.themeTextPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ThemeOption(
                label: 'Light',
                icon: Icons.wb_sunny_rounded,
                selected: provider.themeMode == ThemeMode.light,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.setTheme(ThemeMode.light);
                },
              ),
              const SizedBox(width: 8),
              _ThemeOption(
                label: 'Dark',
                icon: Icons.nightlight_round,
                selected: provider.themeMode == ThemeMode.dark,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.setTheme(ThemeMode.dark);
                },
              ),
              const SizedBox(width: 8),
              _ThemeOption(
                label: 'System',
                icon: Icons.brightness_auto_rounded,
                selected: provider.themeMode == ThemeMode.system,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.setTheme(ThemeMode.system);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? context.themeAccent.withValues(alpha: 0.12)
                : context.themeSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? context.themeAccent : context.themeBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? context.themeAccent
                    : context.themeTextSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? context.themeAccent
                      : context.themeTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Duplicate handling tile ───────────────────────────────────────────────────
class _DuplicateTile extends StatelessWidget {
  final ScanningPreferences scanPrefs;
  const _DuplicateTile({required this.scanPrefs});

  String _label(DuplicateHandling h) => switch (h) {
    DuplicateHandling.warn => 'Warn',
    DuplicateHandling.increment => 'Increment count',
    DuplicateHandling.skip => 'Skip silently',
    DuplicateHandling.allow => 'Allow duplicates',
  };

  String _sub(DuplicateHandling h) => switch (h) {
    DuplicateHandling.warn => 'Show a warning before adding',
    DuplicateHandling.increment => 'Add to quantity column automatically',
    DuplicateHandling.skip => 'Ignore duplicate scans',
    DuplicateHandling.allow => 'Add every scan regardless',
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.copy_rounded,
                color: Color(0xFFF59E0B),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Duplicate handling',
                    style: TextStyle(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _sub(scanPrefs.duplicateHandling),
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.themeAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _label(scanPrefs.duplicateHandling),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.themeAccent,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.themeTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DuplicateSheet(scanPrefs: scanPrefs),
    );
  }
}

class _DuplicateSheet extends StatelessWidget {
  final ScanningPreferences scanPrefs;
  const _DuplicateSheet({required this.scanPrefs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: SafeArea(
        top: false,
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
            Text(
              'Duplicate handling',
              style: TextStyle(
                color: context.themeTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How should ScanSheet handle duplicate barcodes in a session?',
              style: TextStyle(color: context.themeTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...DuplicateHandling.values.map((h) {
              final selected = scanPrefs.duplicateHandling == h;
              return _DuplicateOption(
                handling: h,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  scanPrefs.setDuplicateHandling(h);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DuplicateOption extends StatelessWidget {
  final DuplicateHandling handling;
  final bool selected;
  final VoidCallback onTap;

  const _DuplicateOption({
    required this.handling,
    required this.selected,
    required this.onTap,
  });

  String get _title => switch (handling) {
    DuplicateHandling.warn => 'Warn',
    DuplicateHandling.increment => 'Increment count',
    DuplicateHandling.skip => 'Skip silently',
    DuplicateHandling.allow => 'Allow duplicates',
  };

  String get _desc => switch (handling) {
    DuplicateHandling.warn => 'Show a warning and let the user decide',
    DuplicateHandling.increment => 'Automatically add to a quantity column',
    DuplicateHandling.skip => 'Silently ignore the duplicate scan',
    DuplicateHandling.allow => 'Add every scan, even if it already exists',
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? context.themeAccent.withValues(alpha: 0.08)
              : context.themeSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.themeAccent : context.themeBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: TextStyle(
                      color: selected
                          ? context.themeAccent
                          : context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _desc,
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: context.themeAccent,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Scanner layout tile ──────────────────────────────────────────────────────
class _LayoutModeTile extends StatelessWidget {
  final ScanningPreferences scanPrefs;
  const _LayoutModeTile({required this.scanPrefs});

  @override
  Widget build(BuildContext context) {
    final isFullscreen =
        scanPrefs.scannerLayout == ScannerLayoutMode.fullscreen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fullscreen_rounded,
              color: Color(0xFF10B981),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanner layout',
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  isFullscreen
                      ? 'Full-screen camera with swipe-up table'
                      : 'Compact camera with table below',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<ScannerLayoutMode>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            segments: const [
              ButtonSegment(
                value: ScannerLayoutMode.compact,
                icon: Icon(Icons.view_agenda_rounded, size: 15),
                label: Text('Compact'),
              ),
              ButtonSegment(
                value: ScannerLayoutMode.fullscreen,
                icon: Icon(Icons.fullscreen_rounded, size: 15),
                label: Text('Full'),
              ),
            ],
            selected: {scanPrefs.scannerLayout},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              scanPrefs.setScannerLayout(s.first);
            },
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: context.themeTextSecondary,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 64, color: context.themeBorder);
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.themeAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.themeTextSecondary,
                ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.themeTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: context.themeTextSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google account card
// ─────────────────────────────────────────────────────────────────────────────

class _GoogleAccountCard extends StatefulWidget {
  const _GoogleAccountCard();

  @override
  State<_GoogleAccountCard> createState() => _GoogleAccountCardState();
}

class _GoogleAccountCardState extends State<_GoogleAccountCard> {
  final _gss = GoogleSheetsService.instance;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final isConnected = _gss.isSignedIn;
    const sheetsGreen = Color(0xFF0F9D58);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: sheetsGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SvgPicture.asset('assets/sheets.svg', width: 20, height: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isConnected
                      ? (_gss.currentUser?.email ?? '')
                      : 'Sign in to sync to Google Sheets',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    if (isConnected) {
                      setState(() => _isLoading = true);
                      await _gss.signOut();
                      if (mounted) setState(() => _isLoading = false);
                    } else {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ConnectSheetsScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isConnected ? 'Sign out' : 'Connect',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync queue card
// ─────────────────────────────────────────────────────────────────────────────

class _SyncQueueCard extends StatefulWidget {
  const _SyncQueueCard();

  @override
  State<_SyncQueueCard> createState() => _SyncQueueCardState();
}

class _SyncQueueCardState extends State<_SyncQueueCard> {
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncQueueStats>(
      valueListenable: SyncQueueService.stats,
      builder: (_, stats, _) {
        final hasPending = stats.pendingCount > 0 || stats.failedCount > 0;

        return AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Stats row
              Row(
                children: [
                  _StatBadge(
                    label: 'Pending',
                    count: stats.pendingCount,
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  _StatBadge(
                    label: 'Failed',
                    count: stats.failedCount,
                    color: const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  _StatBadge(
                    label: 'Synced',
                    count: stats.syncedCount,
                    color: const Color(0xFF22C55E),
                  ),
                ],
              ),

              if (stats.lastSyncAt != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Last sync: ${_fmtTime(stats.lastSyncAt!)}',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],

              if (hasPending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSyncing
                            ? null
                            : () async {
                                HapticFeedback.selectionClick();
                                setState(() => _isSyncing = true);
                                await SyncQueueService.retryFailed();
                                // processQueue needs a real handler; show info
                                if (mounted) setState(() => _isSyncing = false);
                                if (mounted) _showSyncStarted();
                              },
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: const Text('Sync Now'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await SyncQueueService.clearSynced();
                      },
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Clear synced'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'All caught up',
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showSyncStarted() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sync started — connect to Google Sheets first'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m, ${local.day}/${local.month}';
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: context.themeTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
