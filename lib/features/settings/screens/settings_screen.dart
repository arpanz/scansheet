import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/services/sync_queue_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/utils/review_service.dart';
import '../../../core/utils/update_service.dart';
import '../../../core/widgets/pro_crown.dart';
import '../../onboarding/onboarding_screen.dart';
import 'paywall_screen.dart';
import 'privacy_policy_screen.dart';
import 'tos_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get _isPro => AdManager.instance.isPro;

  // ── Google Sheets ──────────────────────────────────────────────────────────
  bool _gsLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _gsLoading = true);
    try {
      await GoogleSheetsService.instance.signIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _gsLoading = false);
    }
  }

  Future<void> _handleGoogleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google account?'),
        content: const Text(
          'Scans will no longer sync to Google Sheets until you reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await GoogleSheetsService.instance.signOut();
      if (mounted) setState(() {});
    }
  }

  // ── Sync queue ─────────────────────────────────────────────────────────────
  Future<void> _retryFailed() async {
    await SyncQueueService.retryFailed();
    if (mounted) setState(() {});
  }

  Future<void> _clearSynced() async {
    await SyncQueueService.clearSynced();
    if (mounted) setState(() {});
  }

  // ── Support ────────────────────────────────────────────────────────────────
  Future<void> _rateApp() async {
    await ReviewService.openStoreListing(context);
  }

  Future<void> _checkForUpdates() async {
    await UpdateService.checkForUpdateFromSettings(context);
  }

  Future<void> _contactSupport() async {
    const supportEmail = 'connect.livinlabs@gmail.com';
    final subject = Uri.encodeComponent('ScanSheet - Support Request');
    final mailtoUri = Uri.parse('mailto:$supportEmail?subject=$subject');
    final openedMailto =
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
    if (openedMailto) return;
    final gmailUri = Uri.parse(
      'https://mail.google.com/mail/?view=cm&fs=1&to=$supportEmail&su=ScanSheet%20%E2%80%94%20Support',
    );
    final openedGmail =
        await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
    if (!openedGmail && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email: connect.livinlabs@gmail.com')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final scanPrefs = Provider.of<ScanningPreferences>(context);
    final gsService = GoogleSheetsService.instance;
    final syncStats = SyncQueueService.stats.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [ProCrownIcon()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── Pro banner ────────────────────────────────────────────────────
          _proBanner(t),

          const SizedBox(height: 28),

          // ── Google Sheets ─────────────────────────────────────────────────
          _sectionLabel('Google Sheets'),
          const SizedBox(height: 10),
          ValueListenableBuilder<bool>(
            valueListenable: gsService.signedInNotifier,
            builder: (_, signedIn, __) {
              if (signedIn) {
                final user = gsService.currentUser!;
                return AppCard(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: user.photoUrl != null
                                  ? NetworkImage(user.photoUrl!)
                                  : null,
                              backgroundColor: context.themeAccentContainer,
                              child: user.photoUrl == null
                                  ? Icon(Icons.person_rounded,
                                      color: context.themeAccent, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.displayName ?? 'Google Account',
                                    style: t.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: context.themeTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.email,
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: context.themeTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.themeAccentContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Connected',
                                style: t.textTheme.labelSmall?.copyWith(
                                  color: context.themeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _Tile(
                        icon: Icons.link_off_rounded,
                        label: 'Disconnect account',
                        subtitle: 'Stop syncing to Google Sheets',
                        onTap: _handleGoogleSignOut,
                      ),
                    ],
                  ),
                );
              }
              // Not signed in
              return AppCard(
                onTap: _gsLoading ? null : _handleGoogleSignIn,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.themeAccentContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _gsLoading
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.themeAccent,
                              ),
                            )
                          : Icon(Icons.add_link_rounded,
                              color: context.themeAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connect Google Account',
                            style: t.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.themeTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Sync scans directly to Google Sheets',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: context.themeTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: context.themeTextSecondary, size: 20),
                  ],
                ),
              );
            },
          ),

          // ── Sync queue status ─────────────────────────────────────────────
          if (syncStats.totalCount > 0) ...([
            const SizedBox(height: 10),
            ValueListenableBuilder<SyncQueueStats>(
              valueListenable: SyncQueueService.stats,
              builder: (_, stats, __) => AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sync_rounded,
                            size: 17, color: context.themeTextSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Sync Queue',
                          style: t.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.themeTextPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (stats.failedCount > 0)
                          GestureDetector(
                            onTap: _retryFailed,
                            child: Text(
                              'Retry failed',
                              style: t.textTheme.labelSmall?.copyWith(
                                color: context.themeAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _QueueChip(
                            label: '${stats.pendingCount} pending',
                            color: context.themeTextSecondary),
                        const SizedBox(width: 8),
                        _QueueChip(
                            label: '${stats.failedCount} failed',
                            color: stats.failedCount > 0
                                ? const Color(0xFFEF4444)
                                : context.themeTextSecondary),
                        const SizedBox(width: 8),
                        _QueueChip(
                            label: '${stats.syncedCount} synced',
                            color: context.themeAccent),
                      ],
                    ),
                    if (stats.syncedCount > 0) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _clearSynced,
                        child: Text(
                          'Clear synced items',
                          style: t.textTheme.labelSmall?.copyWith(
                            color: context.themeTextSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),

          const SizedBox(height: 28),

          // ── Scanning preferences ──────────────────────────────────────────
          _sectionLabel('Scanning'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.volume_up_rounded,
                  label: 'Sound on scan',
                  subtitle: 'Play a beep when a code is scanned',
                  value: scanPrefs.soundEnabled,
                  onChanged: scanPrefs.setSoundEnabled,
                ),
                const Divider(height: 1),
                _SwitchTile(
                  icon: Icons.vibration_rounded,
                  label: 'Vibrate on scan',
                  subtitle: 'Haptic feedback for each scan',
                  value: scanPrefs.vibrateEnabled,
                  onChanged: scanPrefs.setVibrateEnabled,
                ),
                const Divider(height: 1),
                _SwitchTile(
                  icon: Icons.flashlight_on_rounded,
                  label: 'Torch on by default',
                  subtitle: 'Turn on the torch when scanning starts',
                  value: scanPrefs.torchDefault,
                  onChanged: scanPrefs.setTorchDefault,
                ),
                const Divider(height: 1),
                _SwitchTile(
                  icon: Icons.center_focus_strong_rounded,
                  label: 'Auto-focus',
                  subtitle: 'Continuous camera auto-focus',
                  value: scanPrefs.autoFocus,
                  onChanged: scanPrefs.setAutoFocus,
                ),
                const Divider(height: 1),
                _DuplicateTile(prefs: scanPrefs),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Appearance ────────────────────────────────────────────────────
          _sectionLabel('Appearance'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        size: 18, color: context.themeTextSecondary),
                    const SizedBox(width: 10),
                    Text(
                      'App Theme',
                      style: t.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 16),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded, size: 16),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded, size: 16),
                      label: Text('System'),
                    ),
                  ],
                  selected: {themeProvider.themeMode},
                  onSelectionChanged: (s) => themeProvider.setTheme(s.first),
                  style: SegmentedButton.styleFrom(
                    backgroundColor: context.themeSurface,
                    selectedBackgroundColor: context.themeAccentContainer,
                    selectedForegroundColor: context.themeAccent,
                    foregroundColor: context.themeTextSecondary,
                    side: BorderSide(color: context.themeBorder),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Support & Legal ───────────────────────────────────────────────
          _sectionLabel('Support & Legal'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: [
                _Tile(
                  icon: Icons.system_update_rounded,
                  label: 'Check for updates',
                  subtitle: 'Download the latest fixes and features',
                  onTap: _checkForUpdates,
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.star_outline_rounded,
                  label: 'Rate us',
                  subtitle: 'Open the store listing to leave a review',
                  onTap: _rateApp,
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Contact support',
                  subtitle: 'Bug reports & feature requests',
                  onTap: _contactSupport,
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy policy',
                  subtitle: 'How we handle your data',
                  onTap: () => Navigator.push(
                      context, FadeSlideRoute(page: const PrivacyPolicyScreen())),
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.gavel_rounded,
                  label: 'Terms of service',
                  subtitle: 'Usage rules & legal information',
                  onTap: () => Navigator.push(
                      context, FadeSlideRoute(page: const TosScreen())),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Debug ─────────────────────────────────────────────────────────
          _sectionLabel('Debug'),
          const SizedBox(height: 10),
          AppCard(
            child: _Tile(
              icon: Icons.auto_awesome_motion_rounded,
              label: 'Replay Onboarding',
              subtitle: 'Watch the introductory tour again',
              onTap: () async {
                await OnboardingScreen.reset();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  FadeSlideRoute(page: const OnboardingScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Pro banner ─────────────────────────────────────────────────────────────
  Widget _proBanner(ThemeData t) {
    if (!_isPro) {
      return AppCard(
        margin: const EdgeInsets.only(bottom: 6),
        onTap: () => Navigator.push(
          context,
          FadeSlideRoute(page: const PaywallScreen()),
        ).then((_) => setState(() {})),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upgrade to Pro',
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.themeTextPrimary,
                        )),
                    const SizedBox(height: 3),
                    Text('Remove ads · unlimited scanning · full export',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: context.themeTextSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: context.themeTextSecondary, size: 20),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF15803D), Color(0xFF166534)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('ScanSheet Pro',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 15,
                        )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ADE80),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF052E16),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text('All features unlocked · ad-free',
                    style: TextStyle(
                        color: Color(0xFFBBF7D0), fontSize: 12.5)),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF4ADE80), size: 22),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.themeTextSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: context.themeTextSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.themeTextPrimary,
                        fontWeight: FontWeight.w500,
                      )),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.themeTextSecondary,
                          fontSize: 11,
                        )),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: context.themeTextSecondary),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: context.themeTextSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.themeTextSecondary,
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: context.themeAccent,
          ),
        ],
      ),
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  final ScanningPreferences prefs;
  const _DuplicateTile({required this.prefs});

  static const _labels = {
    DuplicateHandling.warn: 'Warn me',
    DuplicateHandling.increment: 'Increment qty',
    DuplicateHandling.skip: 'Skip duplicate',
    DuplicateHandling.allow: 'Allow duplicates',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.copy_rounded,
              size: 19, color: context.themeTextSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Duplicate scan',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 2),
                Text('What to do when the same code is scanned again',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.themeTextSecondary,
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          DropdownButton<DuplicateHandling>(
            value: prefs.duplicateHandling,
            underline: const SizedBox(),
            isDense: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.themeAccent,
              fontWeight: FontWeight.w600,
            ),
            items: DuplicateHandling.values
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(_labels[e] ?? e.name),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) prefs.setDuplicateHandling(v);
            },
          ),
        ],
      ),
    );
  }
}

class _QueueChip extends StatelessWidget {
  final String label;
  final Color color;
  const _QueueChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
