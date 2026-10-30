import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/services/sync_queue_service.dart';
import '../../../core/services/usage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ss.dart';
import '../../../core/utils/app_router.dart';
import 'connect_sheets_screen.dart';
import 'paywall_screen.dart';
import 'privacy_policy_screen.dart';
import 'tos_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted)
        setState(() => _version = '${info.version} · Made by Livin Labs');
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ScanningPreferences>();
    final theme = context.watch<ThemeProvider>();
    final colors = context.ss;
    return Scaffold(
      backgroundColor: colors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
          children: [
            Row(
              children: [
                SsIconButton(
                  LucideIcons.chevronLeft,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Settings',
                  style: SsText.sans(
                    size: 20,
                    weight: FontWeight.w600,
                    spacing: -0.4,
                    color: colors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AccountCard(onChanged: () => setState(() {})),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge([
                UsageService.instance.usage,
                AdManager.instance.isProNotifier,
              ]),
              builder: (context, _) => AdManager.instance.isPro
                  ? _PlanCard(
                      plan: AdManager.instance.proPlan,
                      // Straight to the yearly plan when we know it's the
                      // one owned; otherwise Play's subscriptions list.
                      onManage: () => _open(
                        AdManager.instance.proPlan == AdManager.yearlyProductId
                            ? 'https://play.google.com/store/account/subscriptions'
                                  '?sku=${AdManager.yearlyProductId}'
                                  '&package=com.livinlabs.scansheet'
                            : 'https://play.google.com/store/account/subscriptions',
                      ),
                    )
                  : _ProCard(
                      usage: UsageService.instance.summary,
                      onTap: () => Navigator.of(
                        context,
                      ).push(FadeSlideRoute(page: const PaywallScreen())),
                    ),
            ),
            const SizedBox(height: 18),
            _Section(
              'Scanning',
              SsListGroup(
                children: [
                  _PrefSwitch(
                    'Beep on scan',
                    prefs.soundEnabled,
                    prefs.setSoundEnabled,
                  ),
                  _PrefSwitch(
                    'Vibrate on scan',
                    prefs.vibrateEnabled,
                    prefs.setVibrateEnabled,
                  ),
                  if (defaultTargetPlatform == TargetPlatform.android)
                    _PrefSwitch(
                      'Volume buttons scan',
                      prefs.volumeScan,
                      prefs.setVolumeScan,
                      subtitle:
                          'Read a code only after a volume press or a tap. '
                          'Good with gloves.',
                    ),
                  _PrefSwitch(
                    'Torch on when scanner opens',
                    prefs.torchDefault,
                    prefs.setTorchDefault,
                  ),
                  const SsListRow(
                    title: 'Handheld scanners',
                    subtitle:
                        'Pair a Bluetooth or USB scanner as a keyboard. With '
                        'the scanner open, its codes go straight in.',
                  ),
                ],
              ),
            ),
            _Section('Sync', const _SyncGroup()),
            _Section(
              'Appearance',
              SsSegmented<ThemeMode>(
                options: const [
                  (ThemeMode.system, 'System'),
                  (ThemeMode.light, 'Light'),
                  (ThemeMode.dark, 'Dark'),
                ],
                value: theme.themeMode,
                onChanged: theme.setTheme,
              ),
            ),
            const SizedBox(height: 18),
            SsListGroup(
              children: [
                SsListRow(
                  title: 'Rate ScanSheet',
                  chevron: true,
                  onTap: () => _open(
                    'https://play.google.com/store/apps/details?id=com.livinlabs.scansheet',
                  ),
                ),
                SsListRow(
                  title: 'Share ScanSheet',
                  chevron: true,
                  onTap: () => _open('mailto:?subject=ScanSheet'),
                ),
                SsListRow(
                  title: 'Feedback',
                  chevron: true,
                  onTap: () => _open(
                    'mailto:support@livinlabs.dev?subject=ScanSheet%20feedback',
                  ),
                ),
                SsListRow(
                  title: 'Privacy Policy',
                  chevron: true,
                  onTap: () => Navigator.of(
                    context,
                  ).push(FadeSlideRoute(page: const PrivacyPolicyScreen())),
                ),
                SsListRow(
                  title: 'Terms of Service',
                  chevron: true,
                  onTap: () => Navigator.of(
                    context,
                  ).push(FadeSlideRoute(page: const TosScreen())),
                ),
                SsListRow(
                  title: 'Clear scan history',
                  titleColor: colors.error,
                  onTap: () => _clearHistory(),
                ),
                SsListRow(
                  title: 'Clear all sessions and data',
                  titleColor: colors.error,
                  onTap: () => _clearSessions(),
                ),
                SsListRow(title: 'Reset onboarding', onTap: _resetOnboarding),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'ScanSheet ${_version.isEmpty ? '' : _version}',
                style: SsText.sans(size: 12, color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearHistory() async {
    if (!await _confirm(
      'Clear scan history?',
      'All individually scanned records will be deleted.',
    ))
      return;
    await ScanHistoryService.clear();
    if (mounted) showSsToast(context, 'Scan history cleared');
  }

  Future<void> _clearSessions() async {
    if (!await _confirm(
      'Clear all sessions?',
      'All scan sessions and their rows will be deleted.',
    ))
      return;
    await ScanSessionService.clearAll();
    if (mounted) showSsToast(context, 'All sessions cleared');
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_seen');
    if (mounted) showSsToast(context, 'Onboarding reset');
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section(this.title, this.child);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: context.ss.ink2,
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class _AccountCard extends StatefulWidget {
  final VoidCallback onChanged;
  const _AccountCard({required this.onChanged});
  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final gss = GoogleSheetsService.instance;
    final user = gss.currentUser;
    final name = user?.displayName ?? 'Sign in with Google';
    final email = user?.email;
    return SsCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: context.ss.avatar,
            child: Text(
              (user?.displayName?.isNotEmpty == true
                      ? user!.displayName![0]
                      : 'G')
                  .toUpperCase(),
              style: SsText.sans(
                size: 20,
                weight: FontWeight.w600,
                color: context.ss.onAvatar,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(
                    size: 16,
                    weight: FontWeight.w600,
                    color: context.ss.ink,
                  ),
                ),
                Text(
                  email == null ? 'Google account' : 'Google · $email',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(size: 13, color: context.ss.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SsButton.secondary(
            busy
                ? '…'
                : user == null
                ? 'Sign in'
                : 'Sign out',
            expand: false,
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    if (user == null) {
                      await Navigator.of(
                        context,
                      ).push(FadeSlideRoute(page: const ConnectSheetsScreen()));
                    } else {
                      await gss.signOut();
                    }
                    if (mounted) {
                      setState(() => busy = false);
                      widget.onChanged();
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _ProCard extends StatelessWidget {
  final String? usage;
  final VoidCallback onTap;
  const _ProCard({required this.usage, required this.onTap});
  @override
  Widget build(BuildContext context) => SsCard(
    color: context.ss.hero,
    borderColor: context.ss.hero,
    radius: 20,
    padding: const EdgeInsets.all(16),
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SsColors.brandLime,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            LucideIcons.star,
            size: 20,
            color: SsColors.brandInk,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upgrade to Pro',
                style: SsText.sans(
                  size: 15,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (usage != null)
                Text(
                  usage!,
                  style: SsText.sans(size: 13, color: SsColors.nightMuted),
                ),
            ],
          ),
        ),
        const Icon(LucideIcons.chevronRight, size: 18, color: Colors.white),
      ],
    ),
  );
}

/// What a Pro user owns, with the way to manage or cancel it. Lifetime has
/// nothing to manage; an unknown plan (not yet confirmed by the store on
/// this install) still gets the link, in case it's the yearly one.
class _PlanCard extends StatelessWidget {
  final String? plan;
  final VoidCallback onManage;
  const _PlanCard({required this.plan, required this.onManage});
  @override
  Widget build(BuildContext context) {
    final lifetime = plan == AdManager.productId;
    return SsListGroup(
      children: [
        SsListRow(
          leading: Icon(LucideIcons.star, size: 18, color: context.ss.emerald),
          title: 'ScanSheet Pro',
          subtitle: switch (plan) {
            AdManager.productId => 'Lifetime · paid once, nothing renews',
            AdManager.yearlyProductId => 'Yearly plan · renews on Google Play',
            _ => 'Active on this Google Play account',
          },
        ),
        if (!lifetime)
          SsListRow(
            title: 'Manage or cancel subscription',
            chevron: true,
            onTap: onManage,
          ),
      ],
    );
  }
}

class _PrefSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final String? subtitle;
  const _PrefSwitch(this.title, this.value, this.onChanged, {this.subtitle});
  @override
  Widget build(BuildContext context) => SsListRow(
    title: title,
    subtitle: subtitle,
    trailing: Switch(
      value: value,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        onChanged(v);
      },
      activeTrackColor: context.ss.emerald,
    ),
  );
}

class _SyncGroup extends StatelessWidget {
  const _SyncGroup();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SyncQueueService.stats,
    builder: (context, stats, _) => SsListGroup(
      children: [
        SsListRow(
          leading: SsDot(
            color: stats.pendingCount + stats.failedCount > 0
                ? context.ss.amber
                : context.ss.emerald,
          ),
          title: stats.pendingCount + stats.failedCount > 0
              ? '${stats.pendingCount + stats.failedCount} rows waiting to sync'
              : 'All caught up',
          subtitle: stats.lastSyncAt == null
              ? null
              : 'Last sync ${stats.lastSyncAt}',
          trailing: stats.pendingCount + stats.failedCount > 0
              ? SsButton(
                  'Sync now',
                  expand: false,
                  large: false,
                  onPressed: () async {
                    await SyncQueueService.retryFailed();
                  },
                )
              : null,
        ),
      ],
    ),
  );
}
