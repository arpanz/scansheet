/// Step 1 — Welcome
/// Source: docs/design/mocks/Main.dc.html
library;

import 'package:flutter/material.dart';

import '../../../main.dart' as app;
import '../../../core/widgets/ss.dart';
import '../onboarding_flow.dart';

class OnbWelcomeStep extends StatefulWidget {
  final OnbStateScope scope;
  const OnbWelcomeStep({super.key, required this.scope});

  @override
  State<OnbWelcomeStep> createState() => _OnbWelcomeStepState();
}

class _OnbWelcomeStepState extends State<OnbWelcomeStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(_fade);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Logo row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  // ScanSheet logomark
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.ink,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Icon(
                        ssScanIcon,
                        size: 17,
                        color: SsColors.brandLime,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'ScanSheet',
                    style: SsText.sans(
                      size: 17,
                      weight: FontWeight.w600,
                      spacing: -0.2,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  // "Sign in" link — skips to main app (markSeen)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _skip(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Text(
                        'Sign in',
                        style: SsText.sans(
                          size: 15,
                          weight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Hero illustration ─────────────────────────────────────
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _HeroIllustration(c: c),
              ),
            ),

            // ── Headline + sub ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    'Scan a code.\nGet a row.',
                    style: SsText.sans(
                      size: 44,
                      weight: FontWeight.w600,
                      spacing: -1.6,
                      height: 1.02,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Turn barcodes and QR codes into clean '
                    'spreadsheets — synced to Google Sheets, '
                    'or saved as Excel and CSV.',
                    style: SsText.body(color: c.ink2),
                  ),
                ],
              ),
            ),

            // ── CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SsButton(
                    'Get started',
                    icon: LucideIcons.arrowRight,
                    onPressed: () => widget.scope.goNext(context),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Dot(c.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Free to start',
                        style: SsText.caption(color: c.muted),
                      ),
                      const SizedBox(width: 6),
                      _Dot(c.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Works offline',
                        style: SsText.caption(color: c.muted),
                      ),
                      const SizedBox(width: 6),
                      _Dot(c.muted),
                      const SizedBox(width: 6),
                      Text(
                        'No card needed',
                        style: SsText.caption(color: c.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _skip(BuildContext context) async {
    await OnboardingScreen.markSeen();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const app.MainHomeScreen()),
      (_) => false,
    );
  }
}

// ── Inline hero illustration ───────────────────────────────────────────────

class _HeroIllustration extends StatelessWidget {
  final SsColors c;
  const _HeroIllustration({required this.c});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Barcode card (top-left, rotated)
            Positioned(
              left: 0,
              top: 8,
              child: Transform.rotate(
                angle: -0.105, // ~–6 deg
                child: _BarcodeCard(c: c),
              ),
            ),

            // Lime scan beam
            Positioned(
              left: 0,
              right: 0,
              top: 60,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: SsColors.brandLime,
                  boxShadow: [
                    BoxShadow(
                      color: SsColors.brandLime.withValues(alpha: 0.9),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),

            // "Scanned in 0.2s" chip (top-right)
            Positioned(right: 0, top: 18, child: _ScannedChip(c: c)),

            // Spreadsheet card (centered below)
            Positioned(
              left: 0,
              right: 0,
              top: 128,
              child: _SpreadsheetCard(c: c),
            ),
          ],
        );
      },
    );
  }
}

class _BarcodeCard extends StatelessWidget {
  final SsColors c;
  const _BarcodeCard({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 92,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: SsColors.brandInk.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Barcode bars
          SizedBox(
            height: 42,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                for (final w in _barsWidths)
                  Container(width: w.toDouble(), color: c.ink),
              ],
            ),
          ),
          Text(
            '8 901234 56789',
            style: SsText.mono(size: 11, spacing: 1.5, color: c.ink2),
          ),
        ],
      ),
    );
  }

  static const _barsWidths = [
    3,
    1,
    1,
    2,
    4,
    1,
    3,
    1,
    2,
    4,
    1,
    2,
    3,
    1,
    4,
    2,
    1,
    3,
    2,
    1,
    4,
  ];
}

class _ScannedChip extends StatelessWidget {
  final SsColors c;
  const _ScannedChip({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.check, size: 14, color: SsColors.brandLime),
          const SizedBox(width: 6),
          Text(
            'Scanned in 0.2s',
            style: SsText.sans(
              size: 12,
              weight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpreadsheetCard extends StatelessWidget {
  final SsColors c;
  const _SpreadsheetCard({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: SsColors.brandInk.withValues(alpha: 0.10),
            blurRadius: 50,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sheet header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.emeraldTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.grid2x2,
                      size: 13,
                      color: c.emerald,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Warehouse audit',
                  style: SsText.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                Text('42 rows', style: SsText.caption(color: c.muted)),
              ],
            ),
          ),
          // Column headers
          _TableHeader(c: c),
          // Rows
          _TableRow(
            no: '40',
            code: '4006381333931',
            qty: '12',
            time: '10:41',
            c: c,
          ),
          _TableRow(
            no: '41',
            code: '5012345678900',
            qty: '3',
            time: '10:42',
            c: c,
          ),
          // Highlighted last row
          _TableRow(
            no: '42',
            code: '8901234567890',
            qty: '1',
            time: 'now',
            c: c,
            highlight: true,
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final SsColors c;
  const _TableHeader({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.chip,
        border: Border(
          top: BorderSide(color: c.line),
          bottom: BorderSide(color: c.line),
        ),
      ),
      child: Row(
        children: [
          _TH('#', 34, c),
          _TH('Item code', null, c, flex: 1),
          _TH('Qty', 46, c),
          _TH('Time', 64, c, align: TextAlign.right),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  final double? width;
  final int? flex;
  final SsColors c;
  final TextAlign align;
  const _TH(
    this.text,
    this.width,
    this.c, {
    this.flex,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final cell = Padding(
      padding:
          EdgeInsets.symmetric(
            horizontal: width == null ? 8 : (text == '#' ? 0 : 8),
            vertical: 9,
          ).copyWith(
            left: text == '#' ? 16 : null,
            right: text == 'Time' ? 16 : null,
          ),
      child: Text(
        text,
        textAlign: align,
        style: SsText.mono(
          size: 11,
          weight: FontWeight.w600,
          spacing: 0.6,
          color: c.muted,
        ),
      ),
    );
    if (width != null) return SizedBox(width: width, child: cell);
    return Expanded(flex: flex ?? 1, child: cell);
  }
}

class _TableRow extends StatelessWidget {
  final String no;
  final String code;
  final String qty;
  final String time;
  final SsColors c;
  final bool highlight;

  const _TableRow({
    required this.no,
    required this.code,
    required this.qty,
    required this.time,
    required this.c,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlight ? c.limeRow : Colors.transparent;
    final fg = highlight ? c.ink : c.ink2;
    final weight = highlight ? FontWeight.w600 : FontWeight.w400;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          _TD(no, 34, c, fg: fg, weight: weight),
          Expanded(
            child: _TD(code, null, c, fg: fg, weight: weight, isCode: true),
          ),
          _TD(qty, 46, c, fg: fg, weight: weight, isCode: true),
          _TD(
            time,
            64,
            c,
            fg: fg,
            weight: weight,
            isCode: true,
            align: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

class _TD extends StatelessWidget {
  final String text;
  final double? width;
  final SsColors c;
  final Color fg;
  final FontWeight weight;
  final bool isCode;
  final TextAlign align;

  const _TD(
    this.text,
    this.width,
    this.c, {
    required this.fg,
    this.weight = FontWeight.w400,
    this.isCode = false,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final style = isCode
        ? SsText.mono(size: 12, weight: weight, color: fg)
        : SsText.sans(size: 12, weight: weight, color: fg);
    final cell = Padding(
      padding: width == 34
          ? const EdgeInsets.fromLTRB(16, 10, 0, 10)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 10).copyWith(
              right: align == TextAlign.right ? 16 : null,
            ),
      child: Text(
        text,
        style: style,
        textAlign: align,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (width != null) return SizedBox(width: width, child: cell);
    return cell;
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
