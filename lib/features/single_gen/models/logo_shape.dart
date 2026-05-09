import 'package:flutter/material.dart';

enum LogoShape {
  square('Square', Icons.crop_square_rounded),
  rounded('Rounded', Icons.rounded_corner_rounded),
  circle('Circle', Icons.circle_outlined);

  final String label;
  final IconData icon;
  const LogoShape(this.label, this.icon);
}
