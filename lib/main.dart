import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/ads/ad_manager.dart';
import 'core/services/history_service.dart';
import 'core/services/scan_history_service.dart';
import 'core/services/scan_session_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_router.dart';
import 'core/utils/review_service.dart';
import 'core/utils/update_service.dart';
import 'features/generate/screens/generate_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/scan/screens/scan_screen.dart';
import 'features/settings/screens/paywall_screen.dart';
import 'features/settings/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  await Hive.initFlutter();
  await HistoryService.init();
  await ScanHistoryService.init();
  await ScanSessionService.init();
  final initialThemeMode = await _loadInitialThemeMode();
  final showOnboarding = await OnboardingScreen.shouldShow();

  await MobileAds.instance.initialize();
  await AdManager.instance.initialize();
  await ReviewService.trackDailyLaunch();

  AdManager.onShowPaywall = (context) async {
    await Navigator.push(
      context,
      FadeSlideRoute(page: const PaywallScreen()),
    );
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(initialThemeMode: initialThemeMode),
      child: MyApp(showOnboarding: showOnboarding),
    ),
  );
}

Future<ThemeMode> _loadInitialThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'dark';
  return savedTheme == 'light'
      ? ThemeMode.light
      : savedTheme == 'system'
      ? ThemeMode.system
      : ThemeMode.dark;
}

class MyApp extends StatelessWidget {
  final bool showOnboarding;
  const MyApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'QR & Barcode Tools',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(),
      ),
      home: showOnboarding ? const OnboardingScreen() : const MainHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final ValueNotifier<String?> _cloneTextNotifier = ValueNotifier<String?>(
    null,
  );
  StreamSubscription<dynamic>? _updateInstallSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateInstallSubscription = UpdateService.bindInstallListener(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.maybeCheckForUpdate(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AdManager.instance.revalidateEntitlement();
      UpdateService.handleAppResume(context);
    }
  }

  void _handleCloneEdit(String data) {
    _cloneTextNotifier.value = data;
    if (mounted) setState(() => _currentIndex = 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateInstallSubscription?.cancel();
    _cloneTextNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: IndexedStack(
            key: ValueKey(_currentIndex),
            index: _currentIndex,
            children: [
              ScanScreen(
                isActive: _currentIndex == 0,
                onCloneEdit: _handleCloneEdit,
              ),
              const GenerateScreen(),
              const HistoryScreen(),
              const SettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = i);
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            animationDuration: const Duration(milliseconds: 350),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: _NavPill(
                  icon: Icons.qr_code_scanner_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: 'Scan',
              ),
              NavigationDestination(
                icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                selectedIcon: _NavPill(
                  icon: Icons.auto_awesome_mosaic_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: 'Generate',
              ),
              NavigationDestination(
                icon: const Icon(Icons.history_outlined),
                selectedIcon: _NavPill(
                  icon: Icons.history_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: 'History',
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: _NavPill(
                  icon: Icons.settings_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _NavPill({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(icon, color: color),
    );
  }
}
