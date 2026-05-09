import 'package:flutter/material.dart';
import 'app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.color,
    this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.themeCard;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final container = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: elevated
              ? context.themeBorder.withValues(alpha: 0.6)
              : context.themeBorder.withValues(alpha: isDark ? 0.4 : 0.5),
          width: 1,
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    if (onTap != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            highlightColor: context.themeAccent.withValues(alpha: 0.04),
            splashColor: context.themeAccent.withValues(alpha: 0.08),
            child: container,
          ),
        ),
      );
    }

    return container;
  }
}
