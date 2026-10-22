import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ss.dart';

class TosScreen extends StatelessWidget {
  const TosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  SsIconButton(
                    LucideIcons.chevronLeft,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Terms of Service',
                      style: SsText.sans(
                        size: 20,
                        weight: FontWeight.w600,
                        spacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text('Terms of Service', style: SsText.heading(color: c.ink)),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated: February 26, 2026',
                    style: SsText.caption(color: c.muted),
                  ),
                  const SizedBox(height: 24),

                  _TosSection(
                    title: '1. Acceptance of Terms',
                    body:
                        'By downloading, installing, or using Bulk QR ("the App"), you agree to be '
                        'bound by these Terms of Service ("Terms"). If you do not agree to these '
                        'Terms, do not use the App.',
                  ),

                  _TosSection(
                    title: '2. Description of Service',
                    body:
                        'Bulk QR is a mobile application that allows users to generate, scan, and '
                        'manage QR codes. The App offers both free and paid ("Pro") features. '
                        'Pro features are unlocked through an in-app purchase or subscription.',
                  ),

                  _TosSection(
                    title: '3. User Responsibilities',
                    body:
                        'You agree to use the App only for lawful purposes. You must not use the '
                        'App to encode or distribute harmful, fraudulent, or illegal content. '
                        'You are solely responsible for any content you encode into QR codes '
                        'generated with the App.',
                  ),

                  _TosSection(
                    title: '4. In-App Purchases & Subscriptions',
                    body:
                        'Pro features may be purchased as a one-time purchase or via a recurring '
                        'subscription (yearly). Subscriptions automatically renew '
                        'unless cancelled at least 24 hours before the end of the current billing '
                        'period. You can manage and cancel subscriptions in your device\'s app '
                        'store account settings. Payments are charged to your app store account '
                        'upon confirmation. We do not offer refunds except where required by law.',
                  ),

                  _TosSection(
                    title: '5. Intellectual Property',
                    body:
                        'All content, design, graphics, and code within the App are the exclusive '
                        'property of the developer and are protected by applicable intellectual '
                        'property laws. You may not copy, modify, distribute, or reverse-engineer '
                        'any part of the App.',
                  ),

                  _TosSection(
                    title: '6. Privacy',
                    body:
                        'Your use of the App is also governed by our Privacy Policy, which is '
                        'incorporated into these Terms by reference. The App does not upload your '
                        'QR code data or generated images to any external server.',
                  ),

                  _TosSection(
                    title: '7. Disclaimer of Warranties',
                    body:
                        'The App is provided on an "AS IS" and "AS AVAILABLE" basis without any '
                        'warranties of any kind, either express or implied, including but not '
                        'limited to implied warranties of merchantability, fitness for a particular '
                        'purpose, and non-infringement.',
                  ),

                  _TosSection(
                    title: '8. Limitation of Liability',
                    body:
                        'To the maximum extent permitted by applicable law, the developer shall '
                        'not be liable for any indirect, incidental, special, consequential, or '
                        'punitive damages, including loss of data, arising out of or in connection '
                        'with your use of the App.',
                  ),

                  _TosSection(
                    title: '9. Changes to Terms',
                    body:
                        'We reserve the right to modify these Terms at any time. We will notify '
                        'you of significant changes by updating the "Last updated" date. Continued '
                        'use of the App after changes constitutes your acceptance of the revised '
                        'Terms.',
                  ),

                  _TosSection(
                    title: '10. Governing Law',
                    body:
                        'These Terms shall be governed by and construed in accordance with the '
                        'laws of the jurisdiction in which the developer is located, without '
                        'regard to its conflict of law provisions.',
                  ),

                  _TosSection(
                    title: '11. Contact',
                    body:
                        'If you have any questions about these Terms, please contact us via the '
                        '"Contact support" option in the app settings.',
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TosSection extends StatelessWidget {
  final String title;
  final String body;

  const _TosSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SsText.label(color: c.ink)),
          const SizedBox(height: 6),
          Text(body, style: SsText.body(color: c.ink2).copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
