import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

export 'package:lucide_icons_flutter/lucide_icons.dart';
export '../theme/tokens.dart';

/// Shared ScanSheet components. Every new screen builds from these so the
/// look stays identical to docs/design/mocks.

// ─────────────────────────────────────────────────────────────── Buttons

enum SsButtonKind { primary, secondary, lime, ghost, danger }

class SsButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final SsButtonKind kind;
  final IconData? icon;
  final bool expand;
  final bool loading;

  /// Large = 56 tall (screen CTA), otherwise 48.
  final bool large;

  const SsButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = SsButtonKind.primary,
    this.icon,
    this.expand = true,
    this.loading = false,
    this.large = true,
  });

  const SsButton.secondary(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.loading = false,
    this.large = false,
  }) : kind = SsButtonKind.secondary;

  const SsButton.lime(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.loading = false,
    this.large = true,
  }) : kind = SsButtonKind.lime;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final (Color bg, Color fg, BorderSide side) = switch (kind) {
      SsButtonKind.primary => (c.ink, c.onInk, BorderSide.none),
      SsButtonKind.secondary => (
        c.surface,
        c.ink,
        BorderSide(color: c.strongBorder),
      ),
      SsButtonKind.lime => (
        SsColors.brandLime,
        SsColors.brandInk,
        BorderSide.none,
      ),
      SsButtonKind.ghost => (Colors.transparent, c.ink, BorderSide.none),
      SsButtonKind.danger => (c.error, Colors.white, BorderSide.none),
    };
    final height = large ? 56.0 : 48.0;
    final radius = large ? 16.0 : SsRadius.md;
    final disabled = onPressed == null || loading;

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(
                    size: large ? 16 : 15,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          );

    final button = Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                },
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Square icon button (44 hit area), e.g. close / back / overflow.
class SsIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;

  const SsIconButton(
    this.icon, {
    super.key,
    this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: background ?? Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 22, color: color ?? context.ss.ink),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

// ─────────────────────────────────────────────────────────────── Surfaces

class SsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const SsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = SsRadius.lg,
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 36×36 rounded icon tile used in cards and rows.
class SsIconTile extends StatelessWidget {
  final IconData icon;
  final Color? background;
  final Color? color;
  final double size;

  const SsIconTile(
    this.icon, {
    super.key,
    this.background,
    this.color,
    this.size = 36,
  });

  /// Emerald-tinted variant for positive / create actions.
  factory SsIconTile.accent(BuildContext context, IconData icon) => SsIconTile(
    icon,
    background: context.ss.emeraldTint,
    color: context.ss.emerald,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? c.chip,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: color ?? c.ink),
    );
  }
}

// ─────────────────────────────────────────────────────────────── Lists

/// White card holding rows separated by hairlines.
class SsListGroup extends StatelessWidget {
  final List<Widget> children;
  const SsListGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.lineSoft),
            children[i],
          ],
        ],
      ),
    );
  }
}

class SsListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? titleColor;

  const SsListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.label(color: titleColor ?? c.ink),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SsText.caption(color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
                if (chevron) ...[
                  const SizedBox(width: 6),
                  Icon(LucideIcons.chevronRight, size: 18, color: c.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Recent sheets ........ See all"
class SsSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SsSectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Row(
      children: [
        Expanded(
          child: Text(title, style: SsText.section(color: c.ink)),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                action!,
                style: SsText.sans(
                  size: 14,
                  weight: FontWeight.w500,
                  color: c.emerald,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── Tags & status

enum SsTagKind { scan, neutral, list, auto }

/// Mono column-type tag: SCAN, COUNT, TIME, GPS, LIST, AUTO…
class SsTag extends StatelessWidget {
  final String label;
  final SsTagKind kind;
  const SsTag(this.label, {super.key, this.kind = SsTagKind.neutral});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final (Color bg, Color fg) = switch (kind) {
      SsTagKind.scan => (SsColors.brandInk, SsColors.brandLime),
      SsTagKind.neutral => (c.chip, c.ink),
      SsTagKind.list => (c.limeRow, c.ink),
      SsTagKind.auto => (c.emeraldTint, c.emeraldDeep),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SsRadius.xs),
      ),
      alignment: Alignment.center,
      child: Text(
        label.toUpperCase(),
        style: SsText.mono(size: 11, weight: FontWeight.w500, color: fg),
      ),
    );
  }
}

enum SsStatusKind { synced, queued, failed, live, neutral }

class SsStatus extends StatelessWidget {
  final String label;
  final SsStatusKind kind;
  const SsStatus(this.label, {super.key, this.kind = SsStatusKind.synced});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final (Color dot, Color text) = switch (kind) {
      SsStatusKind.synced => (c.emerald, c.emerald),
      SsStatusKind.queued => (c.amber, c.amberText),
      SsStatusKind.failed => (c.error, c.error),
      SsStatusKind.live => (SsColors.live, c.ink),
      SsStatusKind.neutral => (c.muted, c.muted),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SsDot(color: dot),
        const SizedBox(width: 5),
        Text(
          label,
          style: SsText.sans(size: 12, weight: FontWeight.w500, color: text),
        ),
      ],
    );
  }
}

class SsDot extends StatelessWidget {
  final Color color;
  final double size;
  const SsDot({super.key, required this.color, this.size = 6});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Rounded pill like "● IN PROGRESS" or "SCANSHEET PRO".
class SsPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final bool dot;

  const SsPill(
    this.label, {
    super.key,
    required this.background,
    required this.foreground,
    this.dot = false,
  });

  /// Lime-on-dark "IN PROGRESS" pill used on hero cards.
  const SsPill.live(this.label, {super.key})
    : background = const Color(0x24D4F56A),
      foreground = SsColors.brandLime,
      dot = true;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[SsDot(color: foreground), const SizedBox(width: 6)],
        Text(
          label,
          style: SsText.sans(
            size: 12,
            weight: FontWeight.w600,
            spacing: 0.4,
            color: foreground,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────── Controls

/// Track-style segmented control (Sheets | Excel | CSV).
class SsSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dark;

  const SsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final track = dark ? const Color(0x14FFFFFF) : c.track;
    final selBg = dark ? const Color(0x29FFFFFF) : c.surface;
    final fg = dark ? Colors.white : c.ink;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v == value) return;
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 34,
                  decoration: BoxDecoration(
                    color: v == value ? selBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: v == value && !dark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: SsText.sans(
                      size: 13,
                      weight: v == value ? FontWeight.w600 : FontWeight.w400,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selectable option card with a radio ring (destination / template pickers).
class SsOptionCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? child;

  const SsOptionCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    this.leading,
    this.subtitle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        border: Border.all(
          color: selected ? c.ink : c.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: SsText.label(color: c.ink)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: SsText.sans(size: 13, color: c.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SsRadio(selected: selected),
                  ],
                ),
                ?child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SsRadio extends StatelessWidget {
  final bool selected;
  const SsRadio({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: Border.all(
          color: selected ? c.ink : c.strongBorder,
          width: selected ? 6 : 1.5,
        ),
      ),
    );
  }
}

/// – N + stepper used for Number columns and Qty.
class SsStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int step;
  final int min;

  const SsStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    Widget btn(IconData icon, int delta) => SsIconButton(
      icon,
      size: 40,
      background: c.chip,
      onPressed: value + delta < min
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged(value + delta);
            },
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(LucideIcons.minus, -step),
        SizedBox(
          width: 52,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: SsText.mono(size: 18, color: c.ink),
          ),
        ),
        btn(LucideIcons.plus, step),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── Headers

/// Large page header: optional eyebrow line, title, trailing widget.
class SsPageHeader extends StatelessWidget {
  final String title;
  final Widget? eyebrow;
  final Widget? trailing;
  final VoidCallback? onBack;

  const SsPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (onBack != null) ...[
            Transform.translate(
              offset: const Offset(-10, 0),
              child: SsIconButton(
                LucideIcons.arrowLeft,
                onPressed: onBack,
                tooltip: 'Back',
              ),
            ),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  DefaultTextStyle(
                    style: SsText.sans(size: 13, color: c.ink2),
                    child: eyebrow!,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.heading(color: c.ink),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Circular avatar with the account initial (opens Settings).
class SsAvatar extends StatelessWidget {
  final String initial;
  final VoidCallback? onTap;
  const SsAvatar({super.key, required this.initial, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Semantics(
      button: true,
      label: 'Account and settings',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.avatar, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            initial.toUpperCase(),
            style: SsText.sans(
              size: 16,
              weight: FontWeight.w600,
              color: c.onAvatar,
            ),
          ),
        ),
      ),
    );
  }
}

/// Step indicator for onboarding: "02 / 04" with thin progress bars.
class SsStepBar extends StatelessWidget {
  final int step;
  final int total;
  final bool dark;
  const SsStepBar({
    super.key,
    required this.step,
    required this.total,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final on = dark ? SsColors.brandLime : c.ink;
    final off = dark ? const Color(0x24FFFFFF) : c.line;
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? on : off,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── Sheets

/// Bottom sheet with the house handle, padding and safe area.
Future<T?> showSsSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dark = false,
  bool scrollControlled = true,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: dark ? SsColors.nightSurface : context.ss.paper,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dark ? const Color(0x33FFFFFF) : ctx.ss.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// Toast-style snackbar in house style.
void showSsToast(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
}

/// The ScanSheet scan glyph (corner brackets + line).
const IconData ssScanIcon = LucideIcons.scanLine;

/// One rounded bracket of a scan frame. Place four with [top]/[left] set.
class SsScanCorner extends StatelessWidget {
  final bool top;
  final bool left;
  final Color color;
  final double size;
  final double stroke;
  final double radius;

  const SsScanCorner({
    super.key,
    required this.top,
    required this.left,
    this.color = SsColors.brandLime,
    this.size = 46,
    this.stroke = 4,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _CornerPainter(top, left, color, stroke, radius),
  );
}

class _CornerPainter extends CustomPainter {
  final bool top;
  final bool left;
  final Color color;
  final double stroke;
  final double radius;
  const _CornerPainter(
    this.top,
    this.left,
    this.color,
    this.stroke,
    this.radius,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final h = stroke / 2;
    final w = size.width - h;
    // Drawn as the top-left bracket, then mirrored into place.
    final path = Path()
      ..moveTo(h, w)
      ..lineTo(h, h + radius)
      ..arcToPoint(Offset(h + radius, h), radius: Radius.circular(radius))
      ..lineTo(w, h);
    canvas.save();
    canvas.translate(left ? 0 : size.width, top ? 0 : size.height);
    canvas.scale(left ? 1 : -1, top ? 1 : -1);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.top != top || old.left != left;
}

/// Single-field prompt (rename etc.). Returns the trimmed text, or null if
/// cancelled or empty. The field's controller lives in the dialog's own
/// state so it outlives the closing animation.
Future<String?> showSsTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String action = 'Save',
}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(
      title: title,
      label: label,
      initial: initial,
      action: action,
    ),
  );
  return (value == null || value.isEmpty) ? null : value;
}

class _TextPrompt extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String action;

  const _TextPrompt({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
  });

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
