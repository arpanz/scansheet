import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Text(
            'Privacy Policy',
            style: t.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.themeTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Last updated: February 26, 2026',
            style: t.textTheme.bodySmall?.copyWith(
              color: context.themeTextSecondary,
            ),
          ),
          const SizedBox(height: 24),

          _PolicySection(
            title: '1. Introduction',
            body:
                'Livin Labs ("we", "us", or "our") operates Bulk QR ("the App"). This '
                'Privacy Policy explains how we collect, use, and protect information '
                'when you use the App. By using the App, you agree to the practices '
                'described in this policy.',
          ),

          _PolicySection(
            title: '2. Information We Collect',
            body:
                'The App does not require you to create an account and does not collect '
                'personally identifiable information directly.\n\n'
                'We may collect the following non-personal data automatically:\n'
                '• Device type, operating system version, and app version\n'
                '• Crash reports and diagnostic data (via platform services)\n'
                '• Aggregate, anonymized usage statistics\n\n'
                'QR code content you generate or scan is processed entirely on-device '
                'and is never transmitted to our servers.',
          ),

          _PolicySection(
            title: '3. Third-Party Services',
            body:
                'The App uses the following third-party services that may collect data '
                'according to their own privacy policies:\n\n'
                '• Google AdMob — serves ads to free-tier users. AdMob may collect '
                'advertising identifiers and usage data. See Google\'s Privacy Policy '
                'at https://policies.google.com/privacy.\n\n'
                '• Google Play In-App Purchases — processes payments for Pro upgrades. '
                'Payment data is handled by Google and is not accessible to us.\n\n'
                '• Google Play Services — provides crash reporting and analytics.',
          ),

          _PolicySection(
            title: '4. Advertising',
            body:
                'Free-tier users may see ads served by Google AdMob. Ads may be '
                'personalised based on your interests as determined by Google. You can '
                'opt out of personalised advertising in your device\'s settings under '
                '"Google" → "Ads". Pro users can remove ads via an in-app purchase.',
          ),

          _PolicySection(
            title: '5. Data Storage & Security',
            body:
                'All user-generated content (QR codes, history, style presets) is stored '
                'locally on your device using platform-standard storage. We do not have '
                'access to this data. We implement reasonable technical measures to '
                'protect the App, but no method of electronic storage is 100% secure.',
          ),

          _PolicySection(
            title: '6. Children\'s Privacy',
            body:
                'The App is not directed at children under the age of 13. We do not '
                'knowingly collect personal information from children. If you believe '
                'a child has provided personal information through the App, please '
                'contact us so we can take appropriate action.',
          ),

          _PolicySection(
            title: '7. Your Rights',
            body:
                'Depending on your location, you may have rights regarding your personal '
                'data, including the right to access, correct, or delete it. Since we do '
                'not collect personal data directly, most requests can be fulfilled by '
                'clearing the App\'s local data on your device. For questions, contact '
                'us at connect.livinlabs@gmail.com.',
          ),

          _PolicySection(
            title: '8. Changes to This Policy',
            body:
                'We may update this Privacy Policy from time to time. Changes will be '
                'reflected by updating the "Last updated" date at the top of this page. '
                'Continued use of the App after changes constitutes your acceptance of '
                'the revised policy.',
          ),

          _PolicySection(
            title: '9. Contact Us',
            body:
                'If you have any questions or concerns about this Privacy Policy, '
                'please contact us at:\n\nconnect.livinlabs@gmail.com',
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;

  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: t.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.themeTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: t.textTheme.bodyMedium?.copyWith(
              color: context.themeTextSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
