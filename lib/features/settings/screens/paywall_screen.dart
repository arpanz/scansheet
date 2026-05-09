import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/theme/app_theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with SingleTickerProviderStateMixin {
  final InAppPurchase _iap = InAppPurchase.instance;

  bool _available = true;
  bool _isLoading = false;
  ProductDetails? _yearlyProduct;
  ProductDetails? _oneTimeProduct;
  ProductDetails? _selectedProduct;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  late final AnimationController _introCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const Set<String> _candidateProductIds = {
    AdManager.productId,
    AdManager.yearlyProductId,
  };

  bool get _hasSubscriptionPlans => _yearlyProduct != null;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutCubic));
    _introCtrl.forward();
    _initStore();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _introCtrl.dispose();
    super.dispose();
  }

  Future<void> _initStore() async {
    final isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      if (mounted) setState(() => _available = false);
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        if (!mounted) return;
        _snack('Store error: $error', isError: true);
      },
    );

    final preloaded = AdManager.instance.products;
    final ids = <String>{
      ..._candidateProductIds,
      ...preloaded.map((e) => e.id),
    };

    final response = await _iap.queryProductDetails(ids);
    final merged = <String, ProductDetails>{
      for (final p in preloaded) p.id: p,
      for (final p in response.productDetails) p.id: p,
    };
    final products = merged.values.toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));

    if (!mounted) return;
    setState(() {
      AdManager.instance.products = products;
      _classifyPlans(products);
    });
  }

  void _classifyPlans(List<ProductDetails> products) {
    ProductDetails? yearly;
    ProductDetails? oneTime;

    for (final p in products) {
      if (p.id == AdManager.yearlyProductId) {
        yearly = p;
      } else if (p.id == AdManager.productId) {
        oneTime = p;
      }
    }

    _yearlyProduct = yearly;
    _oneTimeProduct = oneTime;

    _selectedProduct =
        yearly ?? oneTime ?? (products.isNotEmpty ? products.first : null);
  }

  // Fixed: was `void` async which silently swallowed errors and could not be
  // properly awaited. Changed to `Future<void>`.
  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> list) async {
    for (final purchase in list) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _isLoading = true);
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          _snack(
            'Purchase failed: ${purchase.error?.message ?? 'Unknown error'}',
            isError: true,
          );
          setState(() => _isLoading = false);
        }
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _grantPremium();
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _grantPremium() async {
    await AdManager.instance.enableProVersion();
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pop(context);
    _snack('ScanSheet Pro is now active.', isError: false);
  }

  Future<void> _buySelectedProduct() async {
    final product = _selectedProduct;
    if (!_available || product == null) {
      _snack('No active plan available right now.', isError: true);
      return;
    }

    final param = PurchaseParam(productDetails: product);
    setState(() => _isLoading = true);
    _iap.buyNonConsumable(purchaseParam: param).catchError((error) {
      if (!mounted) return false;
      setState(() => _isLoading = false);
      _snack('Purchase error: $error', isError: true);
      return false;
    });
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      await _iap.restorePurchases();
      // Fallback: if the stream doesn't fire within 3 s, clear the spinner.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isLoading) setState(() => _isLoading = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Restore failed: $e', isError: true);
    }
  }

  void _snack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? context.themeError : const Color(0xFF0EA35B),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF111827), Color(0xFF0B1220)],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Hero ────────────────────────────────────────────
                            const Center(child: _QrBeamAnimation(size: 128)),
                            const SizedBox(height: 14),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF14B8A6),
                                      Color(0xFF0EA5E9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'ScanSheet Pro',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Remove ads, unlock larger batches,\nand get the full export toolkit.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white54,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 22),

                            // ── Features ──────────────────────────────────────────
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: const Column(
                                children: [
                                  _FeatureRow(
                                    icon: Icons.block_rounded,
                                    label: 'No ads — ever',
                                  ),
                                  _FeatureRow(
                                    icon: Icons.dataset_linked_rounded,
                                    label: 'Up to 1,000 codes per batch',
                                  ),
                                  _FeatureRow(
                                    icon: Icons.tune_rounded,
                                    label: 'Full style customisation',
                                  ),
                                  _FeatureRow(
                                    icon: Icons.ios_share_rounded,
                                    label: 'Export PNG, PDF & ZIP',
                                  ),
                                  _FeatureRow(
                                    icon: Icons.table_chart_rounded,
                                    label: 'Google Sheets Sync',
                                    badge: 'Soon',
                                    last: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),

                            // ── Plan selector ─────────────────────────────────────
                            Text(
                              _hasSubscriptionPlans
                                  ? 'Choose a plan'
                                  : 'Available plan',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            if (_yearlyProduct != null) ...[
                              _PlanTile(
                                title: 'Yearly',
                                subtitle: 'Billed once a year · cancel anytime',
                                price: _yearlyProduct!.price,
                                selected:
                                    _selectedProduct?.id == _yearlyProduct!.id,
                                badge: 'Best value',
                                onTap: () => setState(
                                  () => _selectedProduct = _yearlyProduct,
                                ),
                              ),
                            ],
                            if (_oneTimeProduct != null) ...[
                              const SizedBox(height: 10),
                              _PlanTile(
                                title: 'Lifetime',
                                subtitle: 'Pay once · yours forever',
                                price: _oneTimeProduct!.price,
                                selected:
                                    _selectedProduct?.id == _oneTimeProduct!.id,
                                onTap: () => setState(
                                  () => _selectedProduct = _oneTimeProduct,
                                ),
                              ),
                            ],
                            if (_yearlyProduct == null &&
                                _oneTimeProduct == null)
                              _PlanTile(
                                title: 'Pro Access',
                                subtitle: 'Unlock premium capabilities',
                                price: _selectedProduct?.price ?? 'Unavailable',
                                selected: true,
                                onTap: () {},
                              ),
                            const SizedBox(height: 12),
                            Text(
                              _hasSubscriptionPlans
                                  ? 'Subscription renews automatically. Cancel anytime in your Google Play account.'
                                  : 'One-time payment. Access stays active on this account.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white38,
                                    height: 1.4,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Trust row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              _TrustChip(
                                icon: Icons.lock_outline_rounded,
                                label: 'Secure checkout',
                              ),
                              SizedBox(width: 16),
                              _TrustChip(
                                icon: Icons.replay_rounded,
                                label: 'Easy restore',
                              ),
                              SizedBox(width: 16),
                              _TrustChip(
                                icon: Icons.cancel_outlined,
                                label: 'Cancel anytime',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Gradient CTA button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: (_available && !_isLoading)
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF14B8A6),
                                          Color(0xFF0EA5E9),
                                        ],
                                      )
                                    : null,
                                color: (_available && !_isLoading)
                                    ? null
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: FilledButton(
                                onPressed: _available && !_isLoading
                                    ? _buySelectedProduct
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  disabledBackgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _selectedProduct?.id ==
                                                AdManager.yearlyProductId
                                            ? 'Start Pro — ${_yearlyProduct?.price ?? ""}/yr'
                                            : _selectedProduct?.id ==
                                                  AdManager.productId
                                            ? 'Get Lifetime — ${_oneTimeProduct?.price ?? ""}'
                                            : 'Unlock Pro',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _isLoading ? null : _restorePurchases,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white38,
                            ),
                            child: const Text(
                              'Restore previous purchase',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool last;
  final String? badge;

  const _FeatureRow({
    required this.icon,
    required this.label,
    this.last = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: const Color(0xFF14B8A6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    if (badge != null) ...[  
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Color(0xFF14B8A6),
              ),
            ],
          ),
        ),
        if (!last)
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
      ],
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white38),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF14B8A6).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF14B8A6)
                : Colors.white.withValues(alpha: 0.09),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF14B8A6).withValues(alpha: 0.18),
                    blurRadius: 16,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF14B8A6)
                      : Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                color: selected ? const Color(0xFF14B8A6) : Colors.transparent,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
                          ? Colors.white54
                          : Colors.white.withValues(alpha: 0.3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              price,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrBeamAnimation extends StatefulWidget {
  final double size;

  const _QrBeamAnimation({required this.size});

  @override
  State<_QrBeamAnimation> createState() => _QrBeamAnimationState();
}

class _QrBeamAnimationState extends State<_QrBeamAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final radius = BorderRadius.circular(18);

    return SizedBox(
      width: s + 16,
      height: s + 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          final beamH = s * 0.18;
          final pingPong = t < 0.75
              ? Curves.easeInOutSine.transform(t / 0.75)
              : 1 - Curves.easeInOutSine.transform((t - 0.75) / 0.25);
          final beamY = (-beamH / 2) + (s * pingPong);

          const pad = 14.0;
          final glyphH = s - pad * 2;
          final beamNorm = ((beamY + beamH / 2 - pad) / glyphH).clamp(0.0, 1.0);

          final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
          final badgeY = 2.0 + math.sin(t * math.pi * 2) * 2.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF14B8A6,
                        ).withValues(alpha: 0.08 + 0.06 * pulse),
                        blurRadius: 28,
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: ClipRRect(
                  borderRadius: radius,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1425),
                      borderRadius: radius,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _QrGlyphPainter(beamNorm: beamNorm),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: beamY,
                          child: Container(
                            height: beamH,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(
                                    0xFF5EEAD4,
                                  ).withValues(alpha: 0.0),
                                  const Color(
                                    0xFF5EEAD4,
                                  ).withValues(alpha: 0.06),
                                  const Color(
                                    0xFF5EEAD4,
                                  ).withValues(alpha: 0.18),
                                  const Color(
                                    0xFF5EEAD4,
                                  ).withValues(alpha: 0.06),
                                  const Color(
                                    0xFF5EEAD4,
                                  ).withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              height: 1.2,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    const Color(
                                      0xFF5EEAD4,
                                    ).withValues(alpha: 0.6),
                                    const Color(
                                      0xFF5EEAD4,
                                    ).withValues(alpha: 0.6),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.2, 0.8, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: badgeY,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.30),
                    ),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    size: 16,
                    color: Color(0xFFFFD166),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QrGlyphPainter extends CustomPainter {
  final double beamNorm;

  const _QrGlyphPainter({required this.beamNorm});

  static const _grid = [
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1],
    [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1],
    [0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0],
    [1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1],
    [0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
    [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1],
    [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.width / 21;
    const influence = 0.12;

    final darkPaint = Paint()..color = const Color(0xFFCBD5E1);
    final faintPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.07);
    final litPaint = Paint()..color = const Color(0xFF5EEAD4);
    final litFaintPaint = Paint()
      ..color = const Color(0xFF5EEAD4).withValues(alpha: 0.18);

    for (int y = 0; y < 21; y++) {
      for (int x = 0; x < 21; x++) {
        final filled = _grid[y][x] == 1;

        final rowNorm = (y + 0.5) / 21.0;
        final dist = (rowNorm - beamNorm).abs();
        final isLit = dist < influence;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x * module, y * module, module - 0.8, module - 0.8),
          const Radius.circular(1.2),
        );
        canvas.drawRRect(
          rect,
          isLit
              ? (filled ? litPaint : litFaintPaint)
              : (filled ? darkPaint : faintPaint),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrGlyphPainter old) => old.beamNorm != beamNorm;
}
