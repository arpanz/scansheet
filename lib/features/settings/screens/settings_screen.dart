import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ads/ad_manager.dart';
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

  @override
  void initState() {
    super.initState();
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
    Navigator.push(context, FadeSlideRoute(page: const PrivacyPolicyScreen()));
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
          if (!_isPro)
            AppCard(
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
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFF59E0B),
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
                          const SizedBox(height: 3),
                          Text(
                            'Remove ads \u00b7 unlimited scanning \u00b7 full export',
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
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'ScanSheet Pro',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ADE80),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Color(0xFF052E16),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'All features unlocked \u00b7 ad-free',
                          style: TextStyle(
                            color: Color(0xFFBBF7D0),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF4ADE80),
                    size: 22,
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
