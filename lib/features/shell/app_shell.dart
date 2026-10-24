import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../scan/screens/scan_session_screen.dart';
import '../scan/widgets/scan_chooser_sheet.dart';

/// Main scaffold: Home · Scan · Library (docs/design/mocks/Home.dc.html nav).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Jump to Library's code history from anywhere (e.g. Read a code).
  static final showCodeHistory = _Signal();

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    AppShell.showCodeHistory.addListener(_onShowHistory);
  }

  @override
  void dispose() {
    AppShell.showCodeHistory.removeListener(_onShowHistory);
    super.dispose();
  }

  void _onShowHistory() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    LibraryScreen.tab.value = 'history';
    setState(() => _tab = 1);
  }

  void _select(int tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
  }

  /// Straight into the sheet in progress if it was used this shift;
  /// otherwise the chooser, which leads with that sheet.
  void _onScan() {
    HapticFeedback.mediumImpact();
    final current = SheetSummary.inProgress(SheetSummary.all());
    if (current != null && current.isFreshAt(DateTime.now())) {
      Navigator.of(
        context,
      ).push(FadeSlideRoute(page: ScanSessionScreen(session: current.session)));
    } else {
      showScanChooser(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        // Toasts float clear of the raised Scan button.
        body: SsToastInset(
          bottom: 28,
          child: IndexedStack(
            index: _tab,
            children: [
              HomeScreen(onSeeAll: () => _select(1)),
              const LibraryScreen(),
            ],
          ),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: ScanSessionService.changes,
          builder: (context, _) => _NavBar(
            tab: _tab,
            onSelect: _select,
            onScan: _onScan,
            onScanLongPress: () {
              HapticFeedback.heavyImpact();
              showScanChooser(context);
            },
            // First run: halo the Scan button until the first row exists.
            highlightScan: ScanSessionService.rowsBox.isEmpty,
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;
  final VoidCallback onScanLongPress;
  final bool highlightScan;

  const _NavBar({
    required this.tab,
    required this.onSelect,
    required this.onScan,
    required this.onScanLongPress,
    required this.highlightScan,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      decoration: BoxDecoration(
        color: c.paper.withValues(alpha: 0.96),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 28),
              _NavItem(
                icon: LucideIcons.house,
                label: 'Home',
                active: tab == 0,
                onTap: () => onSelect(0),
              ),
              const Spacer(),
              _ScanButton(
                onTap: onScan,
                onLongPress: onScanLongPress,
                highlight: highlightScan,
              ),
              const Spacer(),
              _NavItem(
                icon: LucideIcons.layoutGrid,
                label: 'Library',
                active: tab == 1,
                onTap: () => onSelect(1),
              ),
              const SizedBox(width: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final color = active ? c.ink : c.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 72,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: SsText.sans(
                  size: 11,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool highlight;
  const _ScanButton({
    required this.onTap,
    required this.onLongPress,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Semantics(
      button: true,
      label: 'Scan',
      onLongPressHint: 'Choose a sheet',
      child: Transform.translate(
        offset: const Offset(0, -18),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.scanButton,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                if (highlight)
                  BoxShadow(
                    color: SsColors.brandLime.withValues(alpha: 0.45),
                    spreadRadius: 6,
                  ),
                BoxShadow(
                  color: SsColors.brandInk.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(ssScanIcon, size: 28, color: c.scanButtonIcon),
          ),
        ),
      ),
    );
  }
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
