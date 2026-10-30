import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/services/lookup_list_service.dart';
import '../../../core/services/usage_service.dart';
import '../../../core/widgets/ss.dart';
import '../widgets/paywall_art.dart';
import 'privacy_policy_screen.dart';
import 'tos_screen.dart';

enum _Plan { lifetime, monthly }

/// Pro paywall. With [waiting] set (rows held back by the free limit) it
/// opens as the dark "unlock them now" version; otherwise the light one.
class PaywallScreen extends StatefulWidget {
  final int? waiting;
  const PaywallScreen({super.key, this.waiting});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _monthly;
  ProductDetails? _lifetime;
  _Plan _plan = _Plan.lifetime;
  bool _available = true;
  bool _loading = false;

  ProductDetails? get _selected =>
      _plan == _Plan.lifetime ? _lifetime : _monthly;

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
      AdManager.monthlyProductId,
      ...cached.map((p) => p.id),
    });
    final products = {
      for (final p in cached) p.id: p,
      for (final p in response.productDetails) p.id: p,
    }.values.toList();
    ProductDetails? find(String id) => products
        .cast<ProductDetails?>()
        .firstWhere((p) => p?.id == id, orElse: () => null);
    if (!mounted) return;
    setState(() {
      AdManager.instance.products = products;
      _monthly = find(AdManager.monthlyProductId);
      _lifetime = find(AdManager.productId);
      if (_lifetime == null && _monthly != null) _plan = _Plan.monthly;
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
      if (p.status == PurchaseStatus.canceled) {
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
      _snack('This plan isn’t available right now.', true);
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

  void _pick(_Plan plan) {
    HapticFeedback.selectionClick();
    setState(() => _plan = plan);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.waiting;
    final dark = waiting != null;
    final skin = dark ? _Skin.dark : _Skin.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: skin.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-10, 0),
                        child: SsIconButton(
                          LucideIcons.x,
                          color: skin.ink,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _loading ? null : _restore,
                        child: Text(
                          'Restore',
                          style: SsText.sans(
                            size: 14,
                            weight: FontWeight.w500,
                            color: skin.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: dark ? _limitHead(waiting, skin) : _mainHead(skin),
                  ),
                ),
                const SizedBox(height: 12),
                _PlanTile(
                  skin: skin,
                  title: 'Lifetime',
                  note: dark
                      ? 'No subscription'
                      : 'One payment · yours for good',
                  price: _lifetime?.price ?? '—',
                  badge: dark ? 'PAY ONCE' : 'NO SUBSCRIPTION',
                  selected: _plan == _Plan.lifetime,
                  onTap: () => _pick(_Plan.lifetime),
                ),
                const SizedBox(height: 10),
                _PlanTile(
                  skin: skin,
                  title: 'Monthly',
                  note: dark
                      ? 'Cancel anytime'
                      : 'Cancel anytime in Google Play',
                  price: _monthly?.price ?? '—',
                  per: '/mo',
                  selected: _plan == _Plan.monthly,
                  onTap: () => _pick(_Plan.monthly),
                ),
                const SizedBox(height: 16),
                _Cta(
                  skin: skin,
                  label: dark
                      ? 'Unlock $waiting ${waiting == 1 ? 'row' : 'rows'}'
                      : _plan == _Plan.lifetime
                      ? 'Get lifetime access'
                      : 'Start monthly plan',
                  loading: _loading,
                  onPressed: _loading ? null : _buy,
                ),
                if (dark)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Wait until ${_nextMonth()}',
                      style: SsText.sans(
                        size: 14,
                        weight: FontWeight.w500,
                        color: skin.muted,
                      ),
                    ),
                  )
                else
                  _FinePrint(
                    skin: skin,
                    lead: _plan == _Plan.lifetime
                        ? 'One-time purchase via Google Play'
                        : 'Renews monthly · cancel anytime',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainHead(_Skin skin) {
    final life = _plan == _Plan.lifetime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),
        const Center(child: PayOnceArt()),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(life),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                life
                    ? 'Pay once.\nScan forever.'
                    : 'No limits.\nMonth by month.',
                style: SsText.sans(
                  size: 40,
                  weight: FontWeight.w700,
                  spacing: -1.4,
                  height: 1.02,
                  color: skin.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                life
                    ? 'No subscription to remember to cancel. Every row, every sheet, for good.'
                    : 'Unlimited rows from today. Stop in two taps when the job is done.',
                style: SsText.sans(size: 15, height: 1.45, color: skin.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final (title, free) in const [
          ('Unlimited rows every month', 'FREE: ${Usage.monthlyRows}'),
          ('As many Google Sheets as you need', 'FREE: ${Usage.openSheets}'),
          (
            'Check scans against full lists',
            'FREE: ${LookupListService.freeEntryLimit}',
          ),
          ('Scan together with your team', ''),
          ('No ads, ever', ''),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: skin.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: SsText.sans(
                      size: 15,
                      weight: FontWeight.w500,
                      color: skin.ink,
                    ),
                  ),
                ),
                if (free.isNotEmpty)
                  Text(free, style: SsText.mono(size: 11, color: skin.muted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _limitHead(int waiting, _Skin skin) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: skin.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: skin.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'THIS MONTH',
                  style: SsText.mono(size: 11, spacing: 1.2, color: skin.muted),
                ),
                const Spacer(),
                Text(
                  '${Usage.monthlyRows} / ${Usage.monthlyRows} rows',
                  style: SsText.mono(size: 13, color: skin.accent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: skin.accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: skin.line,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.lock, size: 20, color: skin.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$waiting new ${waiting == 1 ? 'row' : 'rows'}',
                          style: TextStyle(
                            color: skin.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' ${waiting == 1 ? 'is' : 'are'} safe on this phone, waiting to reach your sheet and exports.',
                        ),
                      ],
                    ),
                    style: SsText.sans(
                      size: 14,
                      height: 1.4,
                      color: SsColors.nightText,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Center(child: LockedRowsArt()),
      const SizedBox(height: 14),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Unlock them now.\n'),
            TextSpan(
              text: 'Never hit a limit again.',
              style: TextStyle(color: skin.accent),
            ),
          ],
        ),
        style: SsText.sans(
          size: 36,
          weight: FontWeight.w700,
          spacing: -1.2,
          height: 1.05,
          color: skin.ink,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Pro sends every waiting row the moment you upgrade, and every row after it. Unlimited sheets, full lists, team scanning, no ads.',
        style: SsText.sans(size: 15, height: 1.45, color: skin.muted),
      ),
    ],
  );

  /// The day free rows reset, e.g. "1 Nov".
  static String _nextMonth() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    return '1 ${months[now.month % 12]}';
  }
}

/// The two looks share layout; only colors differ.
class _Skin {
  final Color bg, card, ink, muted, line, accent, ctaBg, ctaFg, badgeBg;
  final Color badgeFg, selectedBorder;
  const _Skin({
    required this.bg,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.ctaBg,
    required this.ctaFg,
    required this.badgeBg,
    required this.badgeFg,
    required this.selectedBorder,
  });

  static const light = _Skin(
    bg: Color(0xFFF5F6F2),
    card: Colors.white,
    ink: SsColors.brandInk,
    muted: Color(0xFF5B6660),
    line: Color(0xFFDDE1DA),
    accent: Color(0xFF0B7D45),
    ctaBg: SsColors.brandInk,
    ctaFg: Colors.white,
    badgeBg: SsColors.brandLime,
    badgeFg: SsColors.brandInk,
    selectedBorder: Color(0xFF0B7D45),
  );

  static const dark = _Skin(
    bg: SsColors.brandInk,
    card: Color(0xFF151E1A),
    ink: Color(0xFFF5F6F2),
    muted: Color(0xFF9AA59F),
    line: Color(0xFF24302A),
    accent: SsColors.brandLime,
    ctaBg: SsColors.brandLime,
    ctaFg: SsColors.brandInk,
    badgeBg: SsColors.brandLime,
    badgeFg: SsColors.brandInk,
    selectedBorder: SsColors.brandLime,
  );
}

class _PlanTile extends StatelessWidget {
  final _Skin skin;
  final String title, note, price;
  final String? per, badge;
  final bool selected;
  final VoidCallback onTap;
  const _PlanTile({
    required this.skin,
    required this.title,
    required this.note,
    required this.price,
    required this.selected,
    required this.onTap,
    this.per,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? skin.selectedBorder : skin.line;
    final light = identical(skin, _Skin.light);
    return Semantics(
      button: true,
      selected: selected,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: skin.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border, width: 2),
                ),
                child: Row(
                  children: [
                    if (light) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: border, width: 2),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? border : Colors.transparent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: SsText.sans(
                                  size: 16,
                                  weight: FontWeight.w600,
                                  color: skin.ink,
                                ),
                              ),
                              if (badge != null && !light) ...[
                                const SizedBox(width: 8),
                                _Badge(badge!, skin: skin),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            note,
                            style: SsText.sans(size: 13, color: skin.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text.rich(
                      TextSpan(
                        text: price,
                        children: [
                          if (per != null && price != '—')
                            TextSpan(
                              text: per,
                              style: SsText.sans(
                                size: 13,
                                weight: FontWeight.w500,
                                color: skin.muted,
                              ),
                            ),
                        ],
                      ),
                      style: SsText.sans(
                        size: 18,
                        weight: FontWeight.w700,
                        spacing: -0.3,
                        color: skin.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (badge != null && light)
            Positioned(
              top: -11,
              right: 16,
              child: IgnorePointer(child: _Badge(badge!, skin: skin)),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final _Skin skin;
  const _Badge(this.text, {required this.skin});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: skin.badgeBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: SsText.mono(size: 10.5, spacing: 0.8, color: skin.badgeFg),
    ),
  );
}

class _Cta extends StatelessWidget {
  final _Skin skin;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const _Cta({
    required this.skin,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: skin.ctaBg,
        foregroundColor: skin.ctaFg,
        disabledBackgroundColor: skin.ctaBg,
        disabledForegroundColor: skin.ctaFg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: skin.ctaFg,
              ),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Text(
                label,
                key: ValueKey(label),
                style: SsText.sans(
                  size: 16,
                  weight: FontWeight.w600,
                  color: skin.ctaFg,
                ),
              ),
            ),
    ),
  );
}

class _FinePrint extends StatelessWidget {
  final _Skin skin;
  final String lead;
  const _FinePrint({required this.skin, required this.lead});

  @override
  Widget build(BuildContext context) {
    final style = SsText.sans(size: 12, color: skin.muted);
    final link = SsText.sans(
      size: 12,
      weight: FontWeight.w500,
      color: skin.accent,
    );
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$lead · ', style: style),
          InkWell(
            onTap: () => open(const TosScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Terms', style: link),
            ),
          ),
          Text(' · ', style: style),
          InkWell(
            onTap: () => open(const PrivacyPolicyScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Privacy', style: link),
            ),
          ),
        ],
      ),
    );
  }
}
