// ModernBackground is no longer used.
// Background is now the static scaffold color defined in context.themeBg.
// This file is kept to avoid breaking stray imports.
import 'package:flutter/material.dart';

class ModernBackground extends StatelessWidget {
  final Widget child;
  const ModernBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
