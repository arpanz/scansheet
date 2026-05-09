import 'package:flutter/material.dart';

enum LogoFitMode {
  cover('Cover', Icons.crop_rounded, BoxFit.cover),
  contain('Contain', Icons.fit_screen_rounded, BoxFit.contain),
  fill('Fill', Icons.open_in_full_rounded, BoxFit.fill);

  final String label;
  final IconData icon;
  final BoxFit fit;
  const LogoFitMode(this.label, this.icon, this.fit);
}
