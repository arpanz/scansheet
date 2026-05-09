import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A clean, minimal card with a solid surface color and subtle border.
/// No blur, no glass — just structure.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 14.0,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.themeCard;

    final container = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: context.themeBorder, width: 1),
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    if (onTap != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, child: container),
        ),
      );
    }

    return container;
  }
}
