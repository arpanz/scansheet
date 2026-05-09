import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// A clean, labeled input field used inside type-specific forms.
class _FormField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscureText;
  final Widget? suffixIcon;
  final int? maxLength;

  const _FormField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.themeTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            final hasText = value.text.isNotEmpty;
            return TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: obscureText ? 1 : maxLines,
              obscureText: obscureText,
              maxLength: maxLength,
              maxLengthEnforcement: maxLength != null
                  ? MaxLengthEnforcement.enforced
                  : null,
              buildCounter: maxLength != null
                  ? (_, {required currentLength, required isFocused, maxLength}) =>
                      null
                  : null,
              inputFormatters: maxLength != null
                  ? [LengthLimitingTextInputFormatter(maxLength)]
                  : null,
              style: TextStyle(color: context.themeTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                suffixIcon:
                    suffixIcon ??
                    (hasText
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: controller.clear,
                            tooltip: 'Clear',
                          )
                        : null),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Text / URL form ───────────────────────────────────────────────────────────
class TextForm extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onScanTap;
  const TextForm({super.key, required this.controller, this.onScanTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormField(
          label: 'Content',
          hint: 'Enter URL, plain text, phone number\u2026',
          controller: controller,
          maxLines: 5,
          maxLength: 500,
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: controller.clear,
                      tooltip: 'Clear',
                    ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    onPressed: onScanTap,
                    tooltip: 'Scan to Clone',
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            final len = value.text.length;
            return Row(
              children: [
                Icon(
                  Icons.text_snippet_outlined,
                  size: 12,
                  color: context.themeTextSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$len character${len == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: len > 2953
                        ? context.themeError
                        : context.themeTextSecondary,
                  ),
                ),
                if (len > 2953) ...[
                  const SizedBox(width: 6),
                  Text(
                    '\u2022 May exceed QR capacity',
                    style: TextStyle(fontSize: 11, color: context.themeError),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── Wi-Fi form ────────────────────────────────────────────────────────────────
class WifiForm extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const WifiForm({super.key, required this.onChanged});

  @override
  State<WifiForm> createState() => _WifiFormState();
}

class _WifiFormState extends State<WifiForm> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  String _security = 'WPA';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _ssid.addListener(_emit);
    _pass.addListener(_emit);
  }

  void _emit() {
    final s = _security == 'None'
        ? 'WIFI:T:nopass;S:${_ssid.text};;'
        : 'WIFI:T:$_security;S:${_ssid.text};P:${_pass.text};;';
    widget.onChanged(s);
  }

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FormField(
          label: 'Network Name (SSID)',
          hint: 'MyHomeNetwork',
          controller: _ssid,
        ),
        const SizedBox(height: 14),
        _FormField(
          label: 'Password',
          hint: 'Password',
          controller: _pass,
          keyboardType: TextInputType.visiblePassword,
          obscureText: _obscurePassword,
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _pass,
            builder: (_, value, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: _pass.clear,
                      tooltip: 'Clear',
                    ),
                  IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Security',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.themeTextSecondary,
              ),
            ),
            const SizedBox(width: 16),
            ...['WPA', 'WEP', 'None'].map(
              (s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  selected: _security == s,
                  onSelected: (_) => setState(() {
                    _security = s;
                    _emit();
                  }),
                  selectedColor: context.themeAccentContainer,
                  backgroundColor: context.themeCard,
                  side: BorderSide(color: context.themeBorder),
                  labelStyle: TextStyle(
                    color: _security == s
                        ? context.themeAccent
                        : context.themeTextSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── vCard / Contact form ──────────────────────────────────────────────────────
class VCardForm extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const VCardForm({super.key, required this.onChanged});

  @override
  State<VCardForm> createState() => _VCardFormState();
}

class _VCardFormState extends State<VCardForm> {
  final _name    = TextEditingController();
  final _phone   = TextEditingController();
  final _email   = TextEditingController();
  final _company = TextEditingController();
  final _url     = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _email, _company, _url]) {
      c.addListener(_emit);
    }
  }

  void _emit() {
    final buffer = StringBuffer('MECARD:');
    buffer.write('N:${_name.text};');
    buffer.write('TEL:${_phone.text};');
    if (_email.text.trim().isNotEmpty) buffer.write('EMAIL:${_email.text};');
    if (_company.text.trim().isNotEmpty) buffer.write('ORG:${_company.text};');
    if (_url.text.trim().isNotEmpty) buffer.write('URL:${_url.text};');
    buffer.write(';');
    widget.onChanged(buffer.toString());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _company, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FormField(label: 'Full Name *', hint: 'Jane Doe', controller: _name),
        const SizedBox(height: 14),
        _FormField(
          label: 'Phone *',
          hint: '+1 555 000 1234',
          controller: _phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),
        _FormField(
          label: 'Email (optional)',
          hint: 'jane@company.com',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
        ),
        if (_email.text.trim().isNotEmpty &&
            !_emailRegex.hasMatch(_email.text.trim())) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Enter a valid email address.',
              style: TextStyle(color: context.themeError, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _FormField(
          label: 'Company (optional)',
          hint: 'Acme Corp',
          controller: _company,
        ),
        const SizedBox(height: 14),
        _FormField(
          label: 'Website URL (optional)',
          hint: 'https://janedoe.com',
          controller: _url,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}

// ── Email form ────────────────────────────────────────────────────────────────
class EmailForm extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const EmailForm({super.key, required this.onChanged});

  @override
  State<EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<EmailForm> {
  final _to      = TextEditingController();
  final _subject = TextEditingController();
  final _body    = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_to, _subject, _body]) {
      c.addListener(_emit);
    }
  }

  void _emit() {
    final s =
        'mailto:${_to.text}?subject=${Uri.encodeComponent(_subject.text)}&body=${Uri.encodeComponent(_body.text)}';
    widget.onChanged(s);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_to, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FormField(
          label: 'To',
          hint: 'recipient@email.com',
          controller: _to,
          keyboardType: TextInputType.emailAddress,
        ),
        if (_to.text.trim().isNotEmpty &&
            !_emailRegex.hasMatch(_to.text.trim())) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Enter a valid recipient email.',
              style: TextStyle(color: context.themeError, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _FormField(
          label: 'Subject',
          hint: 'Meeting follow-up\u2026',
          controller: _subject,
        ),
        const SizedBox(height: 14),
        _FormField(
          label: 'Body (optional)',
          hint: 'Hi there,',
          controller: _body,
          maxLines: 3,
        ),
      ],
    );
  }
}
