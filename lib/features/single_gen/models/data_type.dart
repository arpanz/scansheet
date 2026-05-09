import 'package:flutter/material.dart';

/// The high-level data category the user is generating a code for.
enum DataType {
  text(
    'Text / URL',
    'text',
    Icons.text_fields_rounded,
    'URLs, plain text, phone numbers',
  ),
  wifi('Wi-Fi', 'wifi', Icons.wifi_rounded, 'Share network credentials'),
  vcard(
    'Contact',
    'vcard',
    Icons.person_rounded,
    'Name, phone, email, company',
  ),
  email('Email', 'email', Icons.email_rounded, 'Pre-filled email with subject');

  final String label;
  final String key;
  final IconData icon;
  final String hint;
  const DataType(this.label, this.key, this.icon, this.hint);
}
