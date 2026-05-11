import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated scanner viewfinder overlay.
/// Draws corner brackets, an animated scan line, and a LIVE badge.
/// When [detectionState] transitions to [ScannerDetectionState.detected],
/// the overlay switches to a pulsing teal border + "DETECTED" label.
enum ScannerDetectionState { idle, detected }

class ScannerOverlayWidget extends StatefulWidget {
  final ScannerDetectionState detectionState;
  final String? barcodeFormat; // shown in the detected state, e.g. "QR Code"

  const ScannerOverlayWidget({
    super.key,
    this.detectionState = ScannerDetectionState.idle,
    this.barcodeFormat,
  });

  @override
  State<ScannerOverlayWidget> createState() => _ScannerOverlayWidgetState();
}

class _ScannerOverlayWidgetState extends State<ScannerOverlayWidget>
    with TickerProviderStateMixin {
  late final AnimationController _scanLineCtrl;
  late final Animation<double> _scanLineAnim;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  late final AnimationController _liveDotCtrl;
  late final Animation<double> _liveDotAnim;

  @override
  void initState() {
    super.initState();

    // Scan line — vertical sweep 2.8s, repeating
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _scanLineAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut),
    );

    // Pulse ring for detected state
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // LIVE dot blinking
    _liveDotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _liveDotAnim = Tween<double>(begin: 0.3, end: 1.0).animate(_liveDotCtrl);
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _pulseCtrl.dispose();
    _liveDotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDetected =
        widget.detectionState == ScannerDetectionState.detected;
    final teal = const Color(0xFF00F5D4);
    const white = Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) *
            0.68; // viewfinder is 68% of the shorter dimension
        final cornerLen = size * 0.12;
        const cornerStroke = 4.0;
        final cornerRadius = cornerStroke * 5;

        return Stack(
          children: [
            // ── Background dim ───────────────────────────────────────────────
            ColoredBox(color: Colors.black.withValues(alpha: 0.46)),

            // ── Viewfinder cutout + overlay ──────────────────────────────────
            Center(
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    // Clear the background inside the viewfinder
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: isDetected
                            ? null
                            : Border.all(color: Colors.transparent),
                      ),
                    ),

                    // ── Pulse border (detected) ──────────────────────────────
                    if (isDetected)
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, _) => Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cornerRadius),
                            border: Border.all(
                              color: teal.withValues(alpha: _pulseAnim.value),
                              width: 3,
                            ),
                          ),
                        ),
                      ),

                    // ── Corner brackets (idle) ───────────────────────────────
                    if (!isDetected) ...[
                      // Top-left
                      Positioned(
                        top: 0,
                        left: 0,
                        child: _CornerBracket(
                          corner: _Corner.topLeft,
                          color: white,
                          length: cornerLen,
                          stroke: cornerStroke,
                          radius: cornerRadius,
                        ),
                      ),
                      // Top-right
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _CornerBracket(
                          corner: _Corner.topRight,
                          color: white,
                          length: cornerLen,
                          stroke: cornerStroke,
                          radius: cornerRadius,
                        ),
                      ),
                      // Bottom-left
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: _CornerBracket(
                          corner: _Corner.bottomLeft,
                          color: white,
                          length: cornerLen,
                          stroke: cornerStroke,
                          radius: cornerRadius,
                        ),
                      ),
                      // Bottom-right
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: _CornerBracket(
                          corner: _Corner.bottomRight,
                          color: white,
                          length: cornerLen,
                          stroke: cornerStroke,
                          radius: cornerRadius,
                        ),
                      ),
                    ],

                    // ── Animated scan line (idle) ────────────────────────────
                    if (!isDetected)
                      AnimatedBuilder(
                        animation: _scanLineAnim,
                        builder: (_, _) {
                          final yFraction = _scanLineAnim.value;
                          // Fade in/out at edges
                          final alpha = yFraction < 0.1
                              ? yFraction / 0.1
                              : yFraction > 0.9
                                  ? (1 - yFraction) / 0.1
                                  : 1.0;
                          return Positioned(
                            top: yFraction * (size - 2),
                            left: 0,
                            right: 0,
                            child: Opacity(
                              opacity: alpha.clamp(0, 1),
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      teal.withValues(alpha: 0.8),
                                      teal,
                                      teal.withValues(alpha: 0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    // ── Detected label (center) ──────────────────────────────
                    if (isDetected)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: teal,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            widget.barcodeFormat?.isNotEmpty == true
                                ? '${widget.barcodeFormat!.toUpperCase()} DETECTED'
                                : 'CODE DETECTED',
                            style: const TextStyle(
                              color: Color(0xFF003C3A),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── LIVE badge (top-left) ────────────────────────────────────────
            if (!isDetected)
              Positioned(
                top: 20,
                left: 20,
                child: _LiveBadge(animation: _liveDotAnim),
              ),

            // ── Hint text (below viewfinder) ─────────────────────────────────
            Align(
              alignment: const Alignment(0, 0.72),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  isDetected ? 'Hold still…' : 'Point at a barcode or QR code',
                  key: ValueKey(isDetected),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerBracket extends StatelessWidget {
  final _Corner corner;
  final Color color;
  final double length;
  final double stroke;
  final double radius;

  const _CornerBracket({
    required this.corner,
    required this.color,
    required this.length,
    required this.stroke,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(length, length),
      painter: _CornerPainter(
        corner: corner,
        color: color,
        stroke: stroke,
        radius: radius,
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final _Corner corner;
  final Color color;
  final double stroke;
  final double radius;

  const _CornerPainter({
    required this.corner,
    required this.color,
    required this.stroke,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = radius.clamp(0.0, math.min(w, h) / 2);

    switch (corner) {
      case _Corner.topLeft:
        final path = Path()
          ..moveTo(0, h)
          ..lineTo(0, r)
          ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
          ..lineTo(w, 0);
        canvas.drawPath(path, paint);
      case _Corner.topRight:
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
          ..lineTo(w, h);
        canvas.drawPath(path, paint);
      case _Corner.bottomLeft:
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(0, h - r)
          ..arcToPoint(Offset(r, h), radius: Radius.circular(r))
          ..lineTo(w, h);
        canvas.drawPath(path, paint);
      case _Corner.bottomRight:
        final path = Path()
          ..moveTo(0, h)
          ..lineTo(w - r, h)
          ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r))
          ..lineTo(w, 0);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.corner != corner ||
      old.color != color ||
      old.stroke != stroke ||
      old.radius != radius;
}

class _LiveBadge extends StatelessWidget {
  final Animation<double> animation;

  const _LiveBadge({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromRGBO(
                  34,
                  197,
                  94,
                  animation.value,
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
