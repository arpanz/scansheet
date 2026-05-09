import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/style/qr_style_profile.dart';
import '../../../core/style/qr_style_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/utils/review_service.dart';
import '../../../core/utils/update_service.dart';
import '../../../core/widgets/pro_crown.dart';
import 'paywall_screen.dart';
import 'privacy_policy_screen.dart';
import 'tos_screen.dart';
import '../../onboarding/onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get _isPro => AdManager.instance.isPro;
  List<QrStyleProfile> _styleProfiles = const [];
  String _activeStyleProfileId = 'default';

  @override
  void initState() {
    super.initState();
    _loadStyleProfiles();
  }

  Future<void> _loadStyleProfiles() async {
    final profiles = await QrStyleService.getProfiles();
    final activeId = await QrStyleService.getActiveProfileId();
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      _activeStyleProfileId = profiles.any((p) => p.id == activeId)
          ? activeId
          : profiles.first.id;
    });
  }

  Future<void> _setActiveStyleProfile(String profileId) async {
    await QrStyleService.setActiveProfile(profileId);
    if (!mounted) return;
    setState(() => _activeStyleProfileId = profileId);
  }

  Future<void> _deleteStyleProfile(String profileId) async {
    final profile = _styleProfiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => QrStyleProfile.defaultProfile(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('"${profile.name}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.themeError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = await QrStyleService.deleteProfile(profileId);
    if (!mounted) return;
    final newActive = updated.any((p) => p.id == _activeStyleProfileId)
        ? _activeStyleProfileId
        : updated.first.id;
    setState(() {
      _styleProfiles = updated;
      _activeStyleProfileId = newActive;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${profile.name}" deleted.'),
        backgroundColor: context.themeSuccess,
      ),
    );
  }

  Future<void> _resetStylePresets() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset style presets?'),
        content: const Text(
          'This removes custom presets and keeps Default + Brand.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final profiles = await QrStyleService.resetToDefaults();
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      _activeStyleProfileId = profiles.first.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Style presets reset.'),
        backgroundColor: context.themeSuccess,
      ),
    );
  }

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

    final openedMailto = await launchUrl(
      mailtoUri,
      mode: LaunchMode.externalApplication,
    );
    if (openedMailto) return;

    final gmailComposeUri = Uri.parse(
      'https://mail.google.com/mail/?view=cm&fs=1&to=$supportEmail&su=Batch%20QR%20%E2%80%94%20Support',
    );
    final openedGmail = await launchUrl(
      gmailComposeUri,
      mode: LaunchMode.externalApplication,
    );

    if (!openedGmail && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email support: connect.livinlabs@gmail.com'),
        ),
      );
    }
  }

  void _privacyPolicy() {
    Navigator.push(
      context,
      FadeSlideRoute(page: const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [ProCrownIcon()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Pro banner
          if (!_isPro)
            AppCard(
              onTap: () => Navigator.push(
                context,
                FadeSlideRoute(page: const PaywallScreen()),
              ).then((_) => setState(() {})),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2206),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFF5A623),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upgrade to Pro',
                            style: t.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.themeTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Remove ads \u00b7 1,000 codes per batch \u00b7 full export',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: context.themeTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.themeTextSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A2A1A), Color(0xFF1A2430)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2206),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFF5A623),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'QR & Barcode Tools Pro',
                              style: t.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'All features unlocked \u00b7 ad-free',
                          style: t.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF22C55E),
                    size: 20,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 28),

          // Appearance
          _sectionLabel('Appearance'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      size: 18,
                      color: context.themeTextSecondary,
                    ),
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

          // Generation
          _sectionLabel('Generation'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.style_outlined,
                      size: 18,
                      color: context.themeTextSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Default Style Preset',
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.themeTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Preset list with inline delete buttons
                ..._styleProfiles.map((profile) {
                  final isActive = profile.id == _activeStyleProfileId;
                  final isProtected =
                      profile.id == 'default' || profile.id == 'brand';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => _setActiveStyleProfile(profile.id),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? context.themeAccentContainer
                              : context.themeSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? context.themeAccent
                                : context.themeBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: isActive
                                  ? context.themeAccent
                                  : context.themeTextSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                profile.name,
                                style: t.textTheme.bodyMedium?.copyWith(
                                  color: isActive
                                      ? context.themeAccent
                                      : context.themeTextPrimary,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isProtected)
                              GestureDetector(
                                onTap: () => _deleteStyleProfile(profile.id),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: context.themeError
                                        .withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetStylePresets,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset Presets'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Support
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
                  onTap: _privacyPolicy,
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.gavel_rounded,
                  label: 'Terms of service',
                  subtitle: 'Usage rules & legal information',
                  onTap: () => Navigator.push(
                    context,
                    FadeSlideRoute(page: const TosScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Debug
          _sectionLabel('Debug'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: [
                _Tile(
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
              ],
            ),
          ),
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

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

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
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.themeTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: context.themeTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
