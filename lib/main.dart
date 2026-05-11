import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/ads/ad_manager.dart';
import 'core/services/google_sheets_service.dart';
import 'core/services/history_service.dart';
import 'core/services/scan_history_service.dart';
import 'core/services/scan_session_service.dart';
import 'core/services/scanning_preferences.dart';
import 'core/services/sync_queue_service.dart';
import 'core/services/template_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_router.dart';
import 'core/utils/review_service.dart';
import 'core/utils/update_service.dart';
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
  await SyncQueueService.init();
  await TemplateService.init();

  final initialThemeMode = await _loadInitialThemeMode();
  final showOnboarding   = await OnboardingScreen.shouldShow();
  final scanningPrefs    = await ScanningPreferences.load();

  await GoogleSheetsService.instance.init();

  await MobileAds.instance.initialize();
  await AdManager.instance.initialize();
  await ReviewService.trackDailyLaunch();

  AdManager.onShowPaywall = (context) async {
    await Navigator.push(context, FadeSlideRoute(page: const PaywallScreen()));
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(initialThemeMode: initialThemeMode),
        ),
        ChangeNotifierProvider.value(value: scanningPrefs),
      ],
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
      title: 'ScanSheet',
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateInstallSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: IndexedStack(
            key: ValueKey(_currentIndex),
            index: _currentIndex,
            children: [
              ScanScreen(isActive: _currentIndex == 0),
              const HistoryScreen(),
              const SettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C22)
                    : const Color(0xFFFCFCFD),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A2A32).withValues(alpha: 0.6)
                      : const Color(0xFFE4E4EB).withValues(alpha: 0.6),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = i);
                },
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                animationDuration: const Duration(milliseconds: 360),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                height: 60,
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    selectedIcon: Icon(
                      Icons.qr_code_scanner,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: 'Scan',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.history_rounded),
                    selectedIcon: Icon(
                      Icons.history,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: 'History',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_rounded),
                    selectedIcon: Icon(
                      Icons.settings,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
