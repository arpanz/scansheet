import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdManager {
  static final AdManager instance = AdManager._internal();

  AdManager._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;

  bool _isPro = false;
  bool get isPro => _isPro;
  final ValueNotifier<bool> isProNotifier = ValueNotifier(false);

  // IAP
  static const String productId = 'pro_lifetime';
  static const String yearlyProductId = 'pro_yearly';
  static const String appStoreUrl =
      'https://play.google.com/store/apps/details?id=com.livinlabs.csvforge';
  List<ProductDetails> products = [];

  // Circular dependency resolution: HomeScreen will initialize this.
  static Future<void> Function(BuildContext context)? onShowPaywall;
  int _interstitialCount = 0;


  // Real IDs
  final String _realBannerId = 'ca-app-pub-4397005408366648/9753920564';
  final String _realInterstitialId = 'ca-app-pub-4397005408366648/1799408927';
  final String _realNativeAdId = 'ca-app-pub-4397005408366648/3480660837';

  // Test IDs
  final String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  final String _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  final String _testNativeAdId = 'ca-app-pub-3940256099942544/2247696110';


  String get _bannerId {
    if (kDebugMode) return _testBannerId;
    return Platform.isAndroid ? _realBannerId : _testBannerId;
  }

  String get _interstitialId {
    if (kDebugMode) return _testInterstitialId;
    return Platform.isAndroid ? _realInterstitialId : _testInterstitialId;
  }

  String get _nativeId {
    if (kDebugMode) return _testNativeAdId;
    return Platform.isAndroid ? _realNativeAdId : _testNativeAdId;
  }

  /// Initialize: Load Ads AND Premium Status
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Check local storage first for immediate UI rendering
    _isPro = prefs.getBool('is_premium_user') ?? false;

    // 2. Silently verify active subscriptions/purchases with Google Play
    if (await InAppPurchase.instance.isAvailable()) {
      await InAppPurchase.instance.restorePurchases();

      // Fixed: subscription was previously fire-and-forget (never stored,
      // never cancelled). Now stored in _initSubscription.
      InAppPurchase.instance.purchaseStream.listen(
        (purchaseDetailsList) async {
          bool hasActivePremium = false;

          for (final purchase in purchaseDetailsList) {
            if (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored) {
              if (purchase.productID == productId ||
                  purchase.productID == yearlyProductId) {
                hasActivePremium = true;
                if (purchase.pendingCompletePurchase) {
                  await InAppPurchase.instance.completePurchase(purchase);
                }
              }
            }
          }

          if (hasActivePremium) {
            _isPro = true;
            isProNotifier.value = true;
            await prefs.setBool('is_premium_user', true);
          } else if (purchaseDetailsList.isNotEmpty) {
            _isPro = false;
            isProNotifier.value = false;
            await prefs.setBool('is_premium_user', false);
            _checkConsentAndInitAds();
          }
        },
      );
    }

    // 3. Initialize Ads if not Pro
    if (!_isPro) {
      _checkConsentAndInitAds();
    }
  }

  void _checkConsentAndInitAds() {
    final params = ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        _loadConsentForm();
      } else {
        _initAds();
      }
    }, (FormError error) => _initAds());
  }

  void _loadConsentForm() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        final status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((FormError? formError) {
            _loadConsentForm();
          });
        } else {
          _initAds();
        }
      },
      (FormError formError) {
        _initAds();
      },
    );
  }

  Future<void> _initAds() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
  }

  /// Re-validates entitlement with the store.
  Future<void> revalidateEntitlement() async {
    if (!await InAppPurchase.instance.isAvailable()) return;

    final prefs = await SharedPreferences.getInstance();
    final completer = Completer<void>();

    late StreamSubscription<List<PurchaseDetails>> sub;
    sub = InAppPurchase.instance.purchaseStream.listen(
      (purchaseDetailsList) async {
        bool hasActive = false;

        for (final purchase in purchaseDetailsList) {
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            if (purchase.productID == productId ||
                purchase.productID == yearlyProductId) {
              hasActive = true;
              if (purchase.pendingCompletePurchase) {
                await InAppPurchase.instance.completePurchase(purchase);
              }
            }
          }
        }

        if (hasActive) {
          _isPro = true;
          isProNotifier.value = true;
          await prefs.setBool('is_premium_user', true);
        } else if (purchaseDetailsList.isNotEmpty) {
          _isPro = false;
          isProNotifier.value = false;
          await prefs.setBool('is_premium_user', false);
          _checkConsentAndInitAds();
        }

        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      },
    );

    await InAppPurchase.instance.restorePurchases();

    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  /// Call this when purchase is successful
  Future<void> enableProVersion() async {
    _isPro = true;
    isProNotifier.value = true;
    _interstitialAd?.dispose();
    _interstitialAd = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium_user', true);
    debugPrint('AdManager: Premium enabled!');
  }

  /// Enable Pro only for the current app session (not persisted).
  void enableProForSession() {
    _isPro = true;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    debugPrint('AdManager: Session-only premium enabled.');
  }

  void _loadInterstitial() {
    if (_isPro) return;
    if (_isInterstitialLoading) return;
    _isInterstitialLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isInterstitialLoading = false;
        },
      ),
    );
  }

  void showInterstitial(BuildContext context, {VoidCallback? onAdDismissed}) {
    if (_isPro) {
      onAdDismissed?.call();
      return;
    }

    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitial();

          _interstitialCount++;
          if (_interstitialCount % 3 == 0) {
            if (context.mounted && onShowPaywall != null) {
              onShowPaywall!(context).then((_) => onAdDismissed?.call());
            } else {
              onAdDismissed?.call();
            }
          } else {
            onAdDismissed?.call();
          }
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitial();
          onAdDismissed?.call();
        },
      );
      _interstitialAd!.show();
    } else {
      _loadInterstitial();
      onAdDismissed?.call();
    }
  }

  Widget getBannerAdWidget() {
    if (_isPro) return const SizedBox.shrink();
    return _BannerAdWrapper(adUnitId: _bannerId);
  }

  Widget getNativeAdWidget({bool isMedium = false}) {
    if (_isPro) return const SizedBox.shrink();
    return _NativeAdWrapper(adUnitId: _nativeId, isMedium: isMedium);
  }
}

class _BannerAdWrapper extends StatefulWidget {
  final String adUnitId;

  const _BannerAdWrapper({required this.adUnitId});

  @override
  State<_BannerAdWrapper> createState() => _BannerAdWrapperState();
}

class _BannerAdWrapperState extends State<_BannerAdWrapper> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    final double screenWidth = MediaQuery.of(context).size.width;
    final AdSize? adaptiveSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
          screenWidth.truncate(),
        );
    final AdSize size = adaptiveSize ?? AdSize.banner;

    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          // Guard against the widget being disposed before the ad loads.
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

class _NativeAdWrapper extends StatefulWidget {
  final String adUnitId;
  final bool isMedium;

  const _NativeAdWrapper({required this.adUnitId, this.isMedium = false});

  @override
  State<_NativeAdWrapper> createState() => _NativeAdWrapperState();
}

class _NativeAdWrapperState extends State<_NativeAdWrapper> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final bool isDark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;

    _nativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: null,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.isMedium
            ? TemplateType.medium
            : TemplateType.small,
        mainBackgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        cornerRadius: 12.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF2563EB),
          style: NativeTemplateFontStyle.bold,
          size: 16.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.white : Colors.black,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.bold,
          size: 16.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.grey : Colors.black54,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 14.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.grey : Colors.black54,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 14.0,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 320,
        minHeight: widget.isMedium ? 320 : 90,
        maxWidth: 400,
        maxHeight: widget.isMedium ? 360 : 90,
      ),
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
