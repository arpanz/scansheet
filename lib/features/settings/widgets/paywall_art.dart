import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Decorative animated illustrations for the paywall screen.
/// Drawn with [CustomPainter]; no external assets or new packages required.
///
/// Both widgets:
///   • respect [MediaQueryData.disableAnimations] (paint frame-zero when true)
///   • wrap the painter in [ExcludeSemantics]
///   • scale to fill their slot via [FittedBox] around a fixed-logical-size
///     [CustomPaint], so they shrink gracefully on narrow phones

// ─────────────────────────────────────────────────────── PayOnceArt

/// Barcode-label + spreadsheet card illustration, 350 × 140 logical pixels.
///
/// Animated: a lime scan-glow sweeps across the barcode label.
class PayOnceArt extends StatefulWidget {
  const PayOnceArt({super.key});

  @override
  State<PayOnceArt> createState() => _PayOnceArtState();
}

class _PayOnceArtState extends State<PayOnceArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disable = MediaQuery.of(context).disableAnimations;
    if (disable) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 350,
        height: 140,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 350,
            height: 140,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PayOnceArtPainter(_ctrl),
                size: const Size(350, 140),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PayOnceArtPainter extends CustomPainter {
  _PayOnceArtPainter(this._anim) : super(repaint: _anim);

  final Animation<double> _anim;

  // ── colour constants ─────────────────────────────────────────────────────
  static const _white = Color(0xFFFFFFFF);
  static const _cardBorder = Color(0xFFDDE1DA);
  static const _ink = SsColors.brandInk;
  static const _lime = SsColors.brandLime;
  static const _emerald = Color(0xFF0B7D45);
  static const _barcodeText = Color(0xFF5B6660);
  static const _pill1 = Color(0xFF9AA59F);
  static const _pill2Ink = Color(0xFF0B1210);
  static const _gridLine = Color(0xFFEEF0EC);
  static const _lastRowBg = Color(0xFFF1FBD3);
  static const _headerBg = Color(0xFF0B7D45);

  @override
  void paint(Canvas canvas, Size size) {
    final t = _anim.value; // 0..1

    // scan y: 40 → 76 → 40 with ease-in-out
    final scanT = math.sin(t * math.pi);
    final scanGlowY = 40.0 + scanT * 36.0;
    final scanLineY = 45.0 + scanT * 36.0;

    // ── Barcode label group (rotated -6° around (75, 70)) ─────────────────
    canvas.save();
    _rotateDeg(canvas, -6, const Offset(75, 70));
    _drawBarcodeCard(canvas, scanGlowY, scanLineY);
    canvas.restore();

    // ── Dashed arc connector ───────────────────────────────────────────────
    _drawDashedArc(canvas);

    // ── Three small signal rects ───────────────────────────────────────────
    _drawSignalRects(canvas);

    // ── Spreadsheet card ──────────────────────────────────────────────────
    _drawSpreadsheetCard(canvas);

    // ── Infinity badge ────────────────────────────────────────────────────
    _drawInfinityBadge(canvas);
  }

  // ── Barcode card (painted in rotated coordinate space) ──────────────────

  void _drawBarcodeCard(Canvas canvas, double scanGlowY, double scanLineY) {
    const cardRect = RRect.fromLTRBXY(20, 30, 130, 110, 12, 12);

    // white card fill
    canvas.drawRRect(cardRect, Paint()..color = _white);
    // card stroke
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = _cardBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // barcode bars
    const bars = [
      (34.0, 3.0),
      (40.0, 6.0),
      (49.0, 2.0),
      (54.0, 4.0),
      (61.0, 2.0),
      (66.0, 7.0),
      (76.0, 2.0),
      (81.0, 4.0),
      (88.0, 3.0),
      (94.0, 6.0),
      (103.0, 2.0),
      (108.0, 5.0),
    ];
    final barPaint = Paint()..color = _ink;
    for (final (x, w) in bars) {
      canvas.drawRect(Rect.fromLTWH(x, 44, w, 40), barPaint);
    }

    // barcode text (Geist Mono 8)
    _paintText(
      canvas,
      '0 123456 789012',
      SsText.mono(size: 8, color: _barcodeText),
      Offset(75, 100),
      TextAlign.center,
      maxWidth: 110,
    );

    // animated scan glow + line (clipped to card interior)
    canvas.save();
    canvas.clipRRect(cardRect);

    canvas.drawRect(
      Rect.fromLTWH(26, scanGlowY, 98, 12),
      Paint()..color = _lime.withValues(alpha: 0.55),
    );
    canvas.drawRect(
      Rect.fromLTWH(26, scanLineY, 98, 2),
      Paint()..color = _emerald,
    );
    canvas.restore();
  }

  // ── Dashed cubic-bezier arc ──────────────────────────────────────────────

  void _drawDashedArc(Canvas canvas) {
    final arcPath = Path()
      ..moveTo(138, 64)
      ..cubicTo(160, 34, 184, 34, 204, 52);

    _drawDashedPath(
      canvas,
      arcPath,
      Paint()
        ..color = _emerald
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
      dashOn: 3,
      dashOff: 5,
    );
  }

  // ── Three signal rects ───────────────────────────────────────────────────

  void _drawSignalRects(Canvas canvas) {
    // emerald solid
    canvas.drawRRect(
      RRect.fromLTRBXY(150, 44, 161, 52, 2, 2),
      Paint()..color = _emerald,
    );
    // lime with ink stroke
    canvas.drawRRect(
      RRect.fromLTRBXY(168, 36, 179, 44, 2, 2),
      Paint()..color = _lime,
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(168, 36, 179, 44, 2, 2),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // emerald 55% opacity
    canvas.drawRRect(
      RRect.fromLTRBXY(186, 40, 197, 48, 2, 2),
      Paint()..color = _emerald.withValues(alpha: 0.55),
    );
  }

  // ── Spreadsheet card ─────────────────────────────────────────────────────

  void _drawSpreadsheetCard(Canvas canvas) {
    const cardL = 206.0, cardT = 18.0, cardR = 330.0, cardB = 122.0;
    const r = 12.0;
    final cardRRect = RRect.fromLTRBXY(cardL, cardT, cardR, cardB, r, r);

    // card fill
    canvas.drawRRect(cardRRect, Paint()..color = _white);
    // card stroke
    canvas.drawRRect(
      cardRRect,
      Paint()
        ..color = _cardBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // header band (top 22px, top corners rounded, bottom square)
    final headerPath = Path()
      ..moveTo(cardL + r, cardT)
      ..lineTo(cardR - r, cardT)
      ..quadraticBezierTo(cardR, cardT, cardR, cardT + r)
      ..lineTo(cardR, cardT + 22)
      ..lineTo(cardL, cardT + 22)
      ..lineTo(cardL, cardT + r)
      ..quadraticBezierTo(cardL, cardT, cardL + r, cardT)
      ..close();
    canvas.drawPath(headerPath, Paint()..color = _headerBg);

    // last-row highlight (bottom corners follow card radius)
    final lastRowPath = Path()
      ..moveTo(cardL + 1, cardB - 17)
      ..lineTo(cardR - 1, cardB - 17)
      ..lineTo(cardR - 1, cardB - r)
      ..quadraticBezierTo(cardR - 1, cardB - 1, cardR - r, cardB - 1)
      ..lineTo(cardL + r, cardB - 1)
      ..quadraticBezierTo(cardL + 1, cardB - 1, cardL + 1, cardB - r)
      ..close();
    canvas.drawPath(lastRowPath, Paint()..color = _lastRowBg);

    // grid lines — horizontals
    final gridPaint = Paint()
      ..color = _gridLine
      ..strokeWidth = 1;
    for (final y in [56.0, 72.0, 88.0, 104.0]) {
      canvas.drawLine(Offset(cardL, y), Offset(cardR, y), gridPaint);
    }
    // grid lines — vertical
    canvas.drawLine(const Offset(236, 40), const Offset(236, cardB), gridPaint);

    // column-1 pills: muted grey, x=214 w=14 h=4
    final col1Paint = Paint()..color = _pill1;
    for (final y in [46.0, 62.0, 78.0, 94.0, 110.0]) {
      canvas.drawRRect(RRect.fromLTRBXY(214, y, 228, y + 4, 2, 2), col1Paint);
    }

    // column-2 pills: ink 75%, x=244 h=4
    const col2Data = [
      (46.0, 52.0),
      (62.0, 44.0),
      (78.0, 56.0),
      (94.0, 48.0),
      (110.0, 52.0),
    ];
    final col2Paint = Paint()..color = _pill2Ink.withValues(alpha: 0.75);
    for (final (y, w) in col2Data) {
      canvas.drawRRect(
        RRect.fromLTRBXY(244, y, 244 + w, y + 4, 2, 2),
        col2Paint,
      );
    }

    // column-3 pills: emerald, x=306 h=4
    const col3Data = [
      (46.0, 14.0),
      (62.0, 10.0),
      (78.0, 14.0),
      (94.0, 10.0),
      (110.0, 14.0),
    ];
    final col3Paint = Paint()..color = _emerald;
    for (final (y, w) in col3Data) {
      canvas.drawRRect(
        RRect.fromLTRBXY(306, y, 306 + w, y + 4, 2, 2),
        col3Paint,
      );
    }
  }

  // ── Infinity badge ────────────────────────────────────────────────────────

  void _drawInfinityBadge(Canvas canvas) {
    canvas.drawCircle(const Offset(324, 20), 18, Paint()..color = _ink);
    _paintText(
      canvas,
      '∞',
      SsText.sans(size: 24, weight: FontWeight.w600, color: _lime),
      const Offset(324, 28),
      TextAlign.center,
      maxWidth: 36,
    );
  }

  @override
  bool shouldRepaint(_PayOnceArtPainter old) => old._anim != _anim;
}

// ─────────────────────────────────────────────────────── LockedRowsArt

/// Stacked row cards + lock disc illustration, 350 × 120 logical pixels.
///
/// Animated: a pulse ring radiates from the lock disc.
class LockedRowsArt extends StatefulWidget {
  const LockedRowsArt({super.key});

  @override
  State<LockedRowsArt> createState() => _LockedRowsArtState();
}

class _LockedRowsArtState extends State<LockedRowsArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disable = MediaQuery.of(context).disableAnimations;
    if (disable) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 350,
        height: 120,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 350,
            height: 120,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LockedRowsArtPainter(_ctrl),
                size: const Size(350, 120),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedRowsArtPainter extends CustomPainter {
  _LockedRowsArtPainter(this._anim) : super(repaint: _anim);

  final Animation<double> _anim;

  static const _lime = SsColors.brandLime;
  static const _ink = SsColors.brandInk;
  static const _rowFill = Color(0xFF151E1A);
  static const _rowStroke = Color(0xFF24302A);
  static const _textBack = Color(0xFF9AA59F);
  static const _textMid = Color(0xFFC9D1CC);
  static const _textFront = Color(0xFFF5F6F2);

  @override
  void paint(Canvas canvas, Size size) {
    final t = _anim.value; // 0..1

    // pulse: radius 28→40, opacity 0.5→0, over 2s loop
    final pulseRadius = 28.0 + t * 12.0;
    final pulseOpacity = 0.5 * (1.0 - t);

    // ── Row cards ─────────────────────────────────────────────────────────
    _drawRowCard(
      canvas,
      x: 52,
      y: 8,
      opacity: 0.45,
      strokeColor: _rowStroke,
      barcode: '8901030865278',
      qty: '×3',
      textColor: _textBack,
      qtyColor: _textBack,
      textX: 66,
      baselineY: 31,
      qtyEndX: 246,
    );
    _drawRowCard(
      canvas,
      x: 36,
      y: 32,
      opacity: 0.75,
      strokeColor: _rowStroke,
      barcode: '0123456789012',
      qty: '×1',
      textColor: _textMid,
      qtyColor: _textMid,
      textX: 50,
      baselineY: 55,
      qtyEndX: 230,
    );
    _drawRowCard(
      canvas,
      x: 20,
      y: 58,
      opacity: 1,
      strokeColor: _lime.withValues(alpha: 0.5),
      barcode: '4006381333931',
      qty: '×12',
      textColor: _textFront,
      qtyColor: _lime,
      textX: 34,
      baselineY: 81,
      qtyEndX: 214,
    );

    // ── Dashed connector ─────────────────────────────────────────────────
    _drawDashedPath(
      canvas,
      Path()
        ..moveTo(238, 77)
        ..lineTo(260, 77),
      Paint()
        ..color = _lime
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
      dashOn: 3,
      dashOff: 4,
    );

    // ── Pulse ring ────────────────────────────────────────────────────────
    if (pulseOpacity > 0) {
      canvas.drawCircle(
        const Offset(296, 72),
        pulseRadius,
        Paint()
          ..color = _lime.withValues(alpha: pulseOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // ── Lock disc ─────────────────────────────────────────────────────────
    canvas.drawCircle(const Offset(296, 72), 28, Paint()..color = _lime);

    // padlock body
    canvas.drawRRect(
      RRect.fromLTRBXY(284, 70, 308, 88, 4, 4),
      Paint()..color = _ink,
    );

    // open shackle: M294 67 v-6 a7 7 0 0 1 14 0
    final shacklePath = Path()
      ..moveTo(294, 67)
      ..relativeLineTo(0, -6)
      ..relativeArcToPoint(
        const Offset(14, 0),
        radius: const Radius.circular(7),
        largeArc: false,
        clockwise: true,
      );
    canvas.drawPath(
      shacklePath,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // keyhole circle (filled lime to "punch through")
    canvas.drawCircle(const Offset(296, 79), 2.4, Paint()..color = _lime);
  }

  void _drawRowCard(
    Canvas canvas, {
    required double x,
    required double y,
    required double opacity,
    required Color strokeColor,
    required String barcode,
    required String qty,
    required Color textColor,
    required Color qtyColor,
    required double textX,
    required double baselineY,
    required double qtyEndX,
  }) {
    canvas.save();
    if (opacity < 1) {
      canvas.saveLayer(
        Rect.fromLTWH(x, y, 210, 38),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }

    final rr = RRect.fromLTRBXY(x, y, x + 210, y + 38, 10, 10);
    canvas.drawRRect(rr, Paint()..color = _rowFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // barcode label
    _paintText(
      canvas,
      barcode,
      SsText.mono(size: 11, color: textColor),
      Offset(textX, baselineY),
      TextAlign.left,
      maxWidth: 160,
    );

    // qty label – right-aligned ending at qtyEndX
    _paintTextRightAligned(
      canvas,
      qty,
      SsText.mono(size: 11, color: qtyColor),
      Offset(qtyEndX, baselineY),
      maxWidth: 40,
    );

    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockedRowsArtPainter old) => old._anim != _anim;
}

// ─────────────────────────────────────────────────────── Shared helpers

/// Rotate [canvas] by [degrees] around [pivot].
void _rotateDeg(Canvas canvas, double degrees, Offset pivot) {
  canvas.translate(pivot.dx, pivot.dy);
  canvas.rotate(degrees * math.pi / 180);
  canvas.translate(-pivot.dx, -pivot.dy);
}

/// Paint text with the given [style]; [origin] is the **baseline** midpoint
/// (for [TextAlign.center]) or baseline-left (for [TextAlign.left]).
void _paintText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset origin,
  TextAlign align, {
  required double maxWidth,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  final double dx = switch (align) {
    TextAlign.center => origin.dx - tp.width / 2,
    TextAlign.right => origin.dx - tp.width,
    _ => origin.dx,
  };
  // origin.dy is the baseline; subtract the ascent to get the top-left y
  tp.paint(
    canvas,
    Offset(
      dx,
      origin.dy - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    ),
  );
}

/// Paint [text] right-aligned so its right edge sits at [origin.dx].
void _paintTextRightAligned(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset origin, {
  required double maxWidth,
}) {
  _paintText(canvas, text, style, origin, TextAlign.right, maxWidth: maxWidth);
}

/// Stroke [path] as a dashed line with [dashOn] / [dashOff] lengths.
void _drawDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dashOn,
  required double dashOff,
}) {
  final metrics = path.computeMetrics();
  for (final metric in metrics) {
    double dist = 0;
    bool drawing = true;
    while (dist < metric.length) {
      final len = drawing ? dashOn : dashOff;
      if (drawing) {
        canvas.drawPath(
          metric.extractPath(dist, math.min(dist + len, metric.length)),
          paint,
        );
      }
      dist += len;
      drawing = !drawing;
    }
  }
}
