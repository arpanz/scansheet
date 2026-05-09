import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String _seenKey = 'onboarding_seen';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_seenKey) ?? false);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenKey);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _PageData(
      icon: Icons.table_chart_rounded,
      gradient: [Color(0xFF166534), Color(0xFF16A34A)],
      glowColor: Color(0x3316A34A),
      tag: 'WELCOME TO SCANSHEET',
      title: 'Scan a code.\nGet a row.\nExport a sheet.',
      subtitle:
          'Transform your phone into a powerful data collection tool. Perfect for inventory, attendance, and asset tracking.',
      bullets: [
        _Bullet(
          Icons.qr_code_scanner_rounded,
          'Lightning fast barcode & QR scanning',
        ),
        _Bullet(Icons.table_rows_rounded, 'Export directly to CSV or Excel'),
        _Bullet(Icons.wifi_off_rounded, 'Fully offline, no account needed'),
      ],
    ),
    _PageData(
      icon: Icons.app_registration_rounded,
      gradient: [Color(0xFF15633B), Color(0xFF34A853)],
      glowColor: Color(0x334F8EF7),
      tag: 'SCAN TO SHEET',
      title: 'Custom columns\nfor your data.',
      subtitle:
          'Set up custom fields before you scan. Scan a barcode, then fill in additional details like location, name, or quantity.',
      bullets: [
        _Bullet(Icons.view_column_rounded, 'Define your own sheet columns'),
        _Bullet(Icons.edit_note_rounded, 'Add custom data to each scan'),
        _Bullet(
          Icons.save_alt_rounded,
          'Export cleanly formatted spreadsheets',
        ),
      ],
    ),
    _PageData(
      icon: Icons.history_edu_rounded,
      gradient: [Color(0xFF6B21A8), Color(0xFFBF5AF2)],
      glowColor: Color(0x33BF5AF2),
      tag: 'QUICK SCAN & HISTORY',
      title: 'Scan anything.\nAccess it\nforever.',
      subtitle:
          'Need to scan a single menu, URL, or WiFi code? Quick Scan handles it instantly. Every scan is stored in your local history.',
      bullets: [
        _Bullet(Icons.bolt_rounded, 'Quick scan mode for everyday codes'),
        _Bullet(Icons.history_rounded, 'Full scan history, stored locally'),
        _Bullet(Icons.security_rounded, 'No data leaves your device'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _goToPage(_currentPage + 1);
    } else {
      _finish();
    }
  }

  void _finish() async {
    await OnboardingScreen.markSeen();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const MainHomeScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0F),
        body: Stack(
          children: [
            // Animated glow background
            AnimatedPositioned(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              top: -size.height * 0.15,
              left: -size.width * 0.2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                width: size.width * 1.4,
                height: size.width * 1.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [page.glowColor, Colors.transparent],
                  ),
                ),
              ),
            ),

            // PageView
            PageView.builder(
              controller: _controller,
              onPageChanged: _onPageChanged,
              itemCount: _pages.length,
              itemBuilder: (context, index) =>
                  _PageContent(pageIndex: index, page: _pages[index]),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BottomBar(
                currentPage: _currentPage,
                totalPages: _pages.length,
                isLast: isLast,
                accentGradient: page.gradient,
                onSkip: _finish,
                onNext: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder removed, MainHomeScreen imported above

class _PageContent extends StatelessWidget {
  final int pageIndex;
  final _PageData page;

  const _PageContent({required this.pageIndex, required this.page});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 56),

            // Animated Hero Section
            _HeroAnimation(pageIndex: pageIndex, gradient: page.gradient),

            const SizedBox(height: 32),

            // Tag pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: page.gradient.last.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: page.gradient.last.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Text(
                page.tag,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: page.gradient.last,
                  letterSpacing: 1.1,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Title
            Text(
              page.title,
              style: GoogleFonts.inter(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
                letterSpacing: -1.0,
              ),
            ),

            const SizedBox(height: 14),

            // Subtitle
            Text(
              page.subtitle,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF8E8E93),
                height: 1.6,
              ),
            ),

            const SizedBox(height: 36),

            // Feature card
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1E).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < page.bullets.length; i++) ...[
                        _BulletRow(
                          bullet: page.bullets[i],
                          color: page.gradient.last,
                        ),
                        if (i < page.bullets.length - 1)
                          Divider(
                            color: Colors.white.withValues(alpha: 0.06),
                            height: 20,
                            thickness: 1,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroAnimation extends StatefulWidget {
  final int pageIndex;
  final List<Color> gradient;

  const _HeroAnimation({required this.pageIndex, required this.gradient});

  @override
  State<_HeroAnimation> createState() => _HeroAnimationState();
}

class _HeroAnimationState extends State<_HeroAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_HeroAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex) {
      _controller.forward(from: 0).then((_) {
        if (mounted) _controller.repeat();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: widget.gradient.last.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          switch (widget.pageIndex) {
            case 0:
              return _ScanToSheetAnimation(progress: _controller.value);
            case 1:
              return _BatchGenerateAnimation(progress: _controller.value);
            case 2:
              return _SingleCreateAnimation(progress: _controller.value);
            case 3:
              return _PrintReadyAnimation(progress: _controller.value);
            case 4:
              return _ScanHistoryAnimation(progress: _controller.value);
            default:
              return const SizedBox();
          }
        },
      ),
    );
  }
}

class _BatchGenerateAnimation extends StatelessWidget {
  final double progress;
  const _BatchGenerateAnimation({required this.progress});

  @override
  Widget build(BuildContext context) {
    final sheetScale = progress < 0.2
        ? Curves.easeOutBack.transform(progress / 0.2)
        : (progress < 0.4
              ? 1.0
              : (progress < 0.5 ? 1.0 - ((progress - 0.4) / 0.1) : 0.0));

    return Stack(
      alignment: Alignment.center,
      children: [
        if (sheetScale > 0)
          Transform.scale(
            scale: sheetScale.clamp(0.0, 1.2),
            child: const Icon(
              Icons.table_chart_rounded,
              color: Colors.white,
              size: 50,
            ),
          ),
        if (progress > 0.45)
          ...List.generate(8, (index) {
            final delay = index * 0.05;
            final p = (progress - 0.45 - delay) / 0.3;
            if (p < 0 || p > 1) return const SizedBox();

            final curveP = Curves.easeOut.transform(p);
            final angle = (index * 45) * math.pi / 180;
            final distance = curveP * 40;

            return Transform.translate(
              offset: Offset(
                distance * math.cos(angle),
                distance * math.sin(angle),
              ),
              child: Transform.scale(
                scale: 1.0 - curveP,
                child: Opacity(
                  opacity: 1.0 - curveP,
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _SingleCreateAnimation extends StatelessWidget {
  final double progress;
  const _SingleCreateAnimation({required this.progress});

  @override
  Widget build(BuildContext context) {
    final scaleInOut = progress < 0.2
        ? Curves.easeOutBack.transform(progress / 0.2)
        : (progress > 0.8
              ? 1.0 - Curves.easeIn.transform((progress - 0.8) / 0.2)
              : 1.0);

    final logoScale = progress < 0.2
        ? 0.0
        : (progress < 0.4
              ? Curves.easeOutBack.transform((progress - 0.2) / 0.2)
              : 1.0);

    return Transform.scale(
      scale: scaleInOut.clamp(0.0, 1.2),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 66),
          Transform.scale(
            scale: logoScale.clamp(0.0, 1.2),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFF1A7A3C),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrintReadyAnimation extends StatelessWidget {
  final double progress;
  const _PrintReadyAnimation({required this.progress});

  @override
  Widget build(BuildContext context) {
    final offset = (progress * 90) % 30;

    return Center(
      child: Container(
        width: 60,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: List.generate(5, (row) {
            return Positioned(
              top: (row * 30.0) - offset,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(2, (col) {
                  return const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.black87,
                    size: 20,
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ScanHistoryAnimation extends StatelessWidget {
  final double progress;
  const _ScanHistoryAnimation({required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = progress * 2 * math.pi;
    final laserY = math.sin(t) * 30;

    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(
          Icons.qr_code_scanner_rounded,
          color: Colors.white30,
          size: 80,
        ),
        const Icon(Icons.qr_code_2_rounded, color: Colors.white70, size: 50),
        Transform.translate(
          offset: Offset(0, laserY),
          child: Container(
            height: 2,
            width: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF00FFCC),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FFCC).withValues(alpha: 0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanToSheetAnimation extends StatelessWidget {
  final double progress;
  const _ScanToSheetAnimation({required this.progress});

  @override
  Widget build(BuildContext context) {
    // Animate 3 "rows" scanning in one by one, then fade and repeat.
    final cycle = (progress * 3).floor().clamp(0, 2);
    final rowProgress = Curves.easeOut.transform(
      ((progress * 3) % 1.0).clamp(0.0, 1.0),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background spreadsheet icon
        Opacity(
          opacity: 0.25,
          child: const Icon(
            Icons.table_chart_rounded,
            color: Colors.white,
            size: 80,
          ),
        ),
        // Animated row tiles
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final isActive = i == cycle;
            final isDone = i < cycle;
            final rowOpacity = isDone ? 1.0 : (isActive ? rowProgress : 0.0);
            final rowWidth = isDone
                ? 70.0
                : (isActive ? (20 + 50 * rowProgress) : 20.0);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Opacity(
                opacity: rowOpacity.clamp(0.0, 1.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white54,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: rowWidth,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isActive && !isDone
                            ? const Color(0xFF4ADE80)
                            : Colors.white70,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        // Scan beam on the active row
        if (progress < 0.95)
          Transform.translate(
            offset: Offset(0, -14 + cycle * 16.0),
            child: Container(
              height: 2,
              width: 60 * rowProgress,
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.8),
                    blurRadius: 6,
                  ),
                ],
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final _Bullet bullet;
  final Color color;
  const _BulletRow({required this.bullet, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(bullet.icon, size: 18, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            bullet.label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFE8E8EA),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool isLast;
  final List<Color> accentGradient;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.isLast,
    required this.accentGradient,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(
            left: 28,
            right: 28,
            top: 20,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0F).withValues(alpha: 0.7),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Skip button
              AnimatedOpacity(
                opacity: isLast ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: GestureDetector(
                  onTap: isLast ? null : onSkip,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Dot indicators
              Row(
                children: List.generate(totalPages, (i) {
                  final isActive = i == currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: isActive
                          ? accentGradient.last
                          : const Color(0xFF3C3C42),
                    ),
                  );
                }),
              ),

              const Spacer(),

              // Next / Get Started button
              GestureDetector(
                onTap: onNext,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  width: isLast ? 140 : 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: accentGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(isLast ? 14 : 24),
                    boxShadow: [
                      BoxShadow(
                        color: accentGradient.last.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isLast
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Get Started',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Data models
class _PageData {
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor;
  final String tag;
  final String title;
  final String subtitle;
  final List<_Bullet> bullets;
  const _PageData({
    required this.icon,
    required this.gradient,
    required this.glowColor,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });
}

class _Bullet {
  final IconData icon;
  final String label;
  const _Bullet(this.icon, this.label);
}
