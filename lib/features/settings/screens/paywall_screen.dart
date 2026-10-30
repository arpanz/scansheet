import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ss.dart';
import 'tos_screen.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _yearly;
  ProductDetails? _lifetime;
  ProductDetails? _selected;
  bool _available = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      if (mounted) setState(() {});
      return;
    }
    _subscription = _iap.purchaseStream.listen(
      _purchaseUpdates,
      onError: (Object e) => _snack('Store error: $e', true),
    );
    final cached = AdManager.instance.products;
    final response = await _iap.queryProductDetails({
      AdManager.productId,
      AdManager.yearlyProductId,
      ...cached.map((p) => p.id),
    });
    final products = {
      for (final p in cached) p.id: p,
      for (final p in response.productDetails) p.id: p,
    }.values.toList();
    if (!mounted) return;
    setState(() {
      AdManager.instance.products = products;
      _yearly = products.cast<ProductDetails?>().firstWhere(
        (p) => p?.id == AdManager.yearlyProductId,
        orElse: () => null,
      );
      _lifetime = products.cast<ProductDetails?>().firstWhere(
        (p) => p?.id == AdManager.productId,
        orElse: () => null,
      );
      _selected =
          _yearly ?? _lifetime ?? (products.isEmpty ? null : products.first);
    });
  }

  Future<void> _purchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _loading = true);
        continue;
      }
      if (p.status == PurchaseStatus.error) {
        _snack('Purchase failed: ${p.error?.message ?? 'Unknown error'}', true);
        if (mounted) setState(() => _loading = false);
      }
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await AdManager.instance.enableProVersion();
        if (mounted) {
          setState(() => _loading = false);
          Navigator.pop(context);
        }
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> _buy() async {
    final p = _selected;
    if (!_available || p == null) {
      _snack('No active plan available right now.', true);
      return;
    }
    setState(() => _loading = true);
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: p),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Purchase error: $e', true);
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _loading = true);
    try {
      await _iap.restorePurchases();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _loading) setState(() => _loading = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Restore failed: $e', true);
      }
    }
  }

  void _snack(String message, bool error) {
    if (!mounted) return;
    showSsToast(context, message, error: error);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Builder(
        builder: (context) {
          final c = context.ss;
          return Scaffold(
            backgroundColor: SsColors.night,
            body: Stack(
              children: [
                Positioned(
                  top: -190,
                  left: -65,
                  right: -65,
                  child: Container(
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          SsColors.brandLime.withValues(alpha: .2),
                          Colors.transparent,
                        ],
                        stops: const [0, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SsIconButton(
                                LucideIcons.x,
                                color: Colors.white,
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 28,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SsColors.brandLime,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'SCANSHEET PRO',
                                    style: SsText.mono(
                                      size: 12,
                                      weight: FontWeight.w600,
                                      spacing: 1,
                                      color: SsColors.brandInk,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Scan without\nlimits.',
                                  style: SsText.sans(
                                    size: 36,
                                    weight: FontWeight.w600,
                                    spacing: -1.2,
                                    height: 1.04,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 26),
                                const _Feature(
                                  icon: LucideIcons.infinity,
                                  title: 'Unlimited sheets',
                                  subtitle: 'Run as many sessions as you need',
                                ),
                                const SizedBox(height: 16),
                                const _Feature(
                                  icon: LucideIcons.refreshCw,
                                  title: 'Live Google Sheets sync',
                                  subtitle: 'Every row, the second you scan it',
                                ),
                                const SizedBox(height: 16),
                                const _Feature(
                                  icon: LucideIcons.ban,
                                  title: 'No ads, ever',
                                  subtitle:
                                      'Nothing between you and the camera',
                                ),
                                const SizedBox(height: 22),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SsColors.nightSurface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: SsColors.nightLine,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        LucideIcons.info,
                                        size: 16,
                                        color: SsColors.nightText,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          "You're on Free: 200 new rows a month across all sheets, and 3 Google Sheets open at once.",
                                          style: SsText.sans(
                                            size: 13,
                                            height: 1.4,
                                            color: SsColors.nightText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _PlanCard(
                                  title: 'Yearly',
                                  note: 'Cancel anytime',
                                  price: _yearly?.price ?? '—',
                                  selected: _selected?.id == _yearly?.id,
                                  badge: 'BEST VALUE',
                                  onTap: _yearly == null
                                      ? null
                                      : () =>
                                            setState(() => _selected = _yearly),
                                ),
                                const SizedBox(height: 10),
                                _PlanCard(
                                  title: 'Lifetime',
                                  note: 'Pay once, keep it forever',
                                  price: _lifetime?.price ?? '—',
                                  selected: _selected?.id == _lifetime?.id,
                                  onTap: _lifetime == null
                                      ? null
                                      : () => setState(
                                          () => _selected = _lifetime,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SsButton.lime(
                          _selected?.id == AdManager.yearlyProductId
                              ? 'Start Pro yearly'
                              : 'Get Pro for life',
                          loading: _loading,
                          onPressed: _selected == null || _loading
                              ? null
                              : _buy,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _loading ? null : _restore,
                              child: Text(
                                'Restore',
                                style: SsText.sans(
                                  size: 13,
                                  color: c.heroMuted,
                                ),
                              ),
                            ),
                            Text('·', style: SsText.sans(color: c.heroMuted)),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TosScreen(),
                                ),
                              ),
                              child: Text(
                                'Terms',
                                style: SsText.sans(
                                  size: 13,
                                  color: c.heroMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: SsColors.nightRaised,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: SsColors.nightLine),
        ),
        child: Icon(icon, size: 18, color: SsColors.brandLime),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: SsText.sans(
                size: 15,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: SsText.sans(size: 13, color: SsColors.nightMuted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PlanCard extends StatelessWidget {
  final String title, note, price;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;
  const _PlanCard({
    required this.title,
    required this.note,
    required this.price,
    required this.selected,
    this.badge,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Material(
        color: selected ? SsColors.nightSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? SsColors.brandLime : SsColors.nightLine,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SsRadio(selected: selected),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: SsText.sans(
                            size: 16,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          note,
                          style: SsText.sans(
                            size: 13,
                            color: SsColors.nightMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    price,
                    style: SsText.mono(
                      size: 16,
                      weight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (badge != null)
        Positioned(
          right: 16,
          top: -10,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: SsColors.brandLime,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              badge!,
              style: SsText.sans(
                size: 11,
                weight: FontWeight.w700,
                spacing: .4,
                color: SsColors.brandInk,
              ),
            ),
          ),
        ),
    ],
  );
}
