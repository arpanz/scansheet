import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/ads/ad_manager.dart';
import 'core/services/google_sheets_service.dart';
import 'core/services/launch_actions.dart';
import 'core/services/sheets_sync_service.dart';
import 'core/services/usage_service.dart';
import 'core/services/history_service.dart';
import 'core/services/product_lookup_service.dart';
import 'core/services/scan_history_service.dart';
import 'core/services/scan_session_service.dart';
import 'core/services/scanning_preferences.dart';
import 'core/services/sync_queue_service.dart';
import 'core/services/template_service.dart';
import 'core/services/lookup_list_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_router.dart';
import 'core/utils/review_service.dart';
import 'core/utils/update_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/screens/paywall_screen.dart';
import 'features/shell/app_shell.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

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
  await LookupListService.init();
  await ProductLookupService.instance.init();

  final initialThemeMode = await _loadInitialThemeMode();
  final showOnboarding = await OnboardingScreen.shouldShow();
  final scanningPrefs = await ScanningPreferences.load();

  await GoogleSheetsService.instance.init();

  await MobileAds.instance.initialize();
  await AdManager.instance.initialize();
  await UsageService.instance.init();
  await SheetsSyncService.instance.start();
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
  unawaited(LaunchActions.init(appNavigatorKey));
}

Future<ThemeMode> _loadInitialThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';
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
      navigatorKey: appNavigatorKey,
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
      SheetsSyncService.instance.syncSoon();
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
    return const AppShell();
  }
}
