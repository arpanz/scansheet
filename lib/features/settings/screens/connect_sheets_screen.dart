import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/google_sheets_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';

/// Result returned by [ConnectSheetsScreen] when the user picks a destination.
class SheetDestination {
  final String spreadsheetId;
  final String spreadsheetTitle;
  final String sheetName;

  const SheetDestination({
    required this.spreadsheetId,
    required this.spreadsheetTitle,
    required this.sheetName,
  });
}

/// Full-page Google Sheets connection screen.
/// Push this screen and await the result — it returns a [SheetDestination]
/// when the user presses "Connect & Continue", or null if they cancel.
class ConnectSheetsScreen extends StatefulWidget {
  const ConnectSheetsScreen({super.key});

  @override
  State<ConnectSheetsScreen> createState() => _ConnectSheetsScreenState();
}

class _ConnectSheetsScreenState extends State<ConnectSheetsScreen> {
  final _gss = GoogleSheetsService.instance;
  final _searchCtrl = TextEditingController();

  bool _isSigningIn = false;
  bool _isLoadingSheets = false;
  bool _isCreating = false;

  List<SpreadsheetInfo> _spreadsheets = [];
  SpreadsheetInfo? _selected;
  List<String> _worksheets = [];
  String? _selectedSheet;
  String _searchQuery = '';

  Timer? _debounce;


  @override
  void initState() {
    super.initState();
    if (_gss.isSignedIn) {
      _loadSpreadsheets();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Data loading
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      await _gss.signIn();
      if (!mounted) return;
      await _loadSpreadsheets();
    } on GSheetsException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _signOut() async {
    await _gss.signOut();
    if (!mounted) return;
    setState(() {
      _spreadsheets = [];
      _selected = null;
      _worksheets = [];
      _selectedSheet = null;
    });
  }

  Future<void> _loadSpreadsheets({String? query}) async {
    if (!_gss.isSignedIn) return;
    setState(() => _isLoadingSheets = true);
    try {
      final sheets = await _gss.listSpreadsheets(query: query);
      if (!mounted) return;
      setState(() => _spreadsheets = sheets);
    } on GSheetsException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isLoadingSheets = false);
    }
  }

  Future<void> _loadWorksheets(SpreadsheetInfo info) async {
    setState(() {
      _selected = info;
      _worksheets = [];
      _selectedSheet = null;
    });
    try {
      final sheets = await _gss.getWorksheets(info.id);
      if (!mounted) return;
      setState(() {
        _worksheets = sheets;
        _selectedSheet = sheets.isNotEmpty ? sheets.first : null;
      });
    } on GSheetsException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  Future<void> _createSpreadsheet() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Spreadsheet'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Spreadsheet name',
            hintText: 'e.g. Inventory Jan 2026',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    setState(() => _isCreating = true);
    try {
      final id = await _gss.createSpreadsheet(ctrl.text.trim());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      // Reload list and auto-select the new sheet.
      await _loadSpreadsheets();
      final newInfo = _spreadsheets.firstWhere(
        (s) => s.id == id,
        orElse: () => SpreadsheetInfo(
          id: id,
          title: ctrl.text.trim(),
        ),
      );
      await _loadWorksheets(newInfo);
    } on GSheetsException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _onSearchChanged(String v) {
    _searchQuery = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadSpreadsheets(query: v.trim().isEmpty ? null : v.trim());
    });
  }

  void _connect() {
    if (_selected == null || _selectedSheet == null) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(
      context,
      SheetDestination(
        spreadsheetId: _selected!.id,
        spreadsheetTitle: _selected!.title,
        sheetName: _selectedSheet!,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: context.themeError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected = _gss.isSignedIn;

    return Scaffold(
      backgroundColor: context.themeBg,
      appBar: AppBar(
        backgroundColor: context.themeCard,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text('Connect Google Sheets'),
        titleTextStyle: TextStyle(
          color: context.themeTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.themeTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: _selected != null && _selectedSheet != null
          ? _ConnectBottomBar(
              spreadsheetTitle: _selected!.title,
              sheetName: _selectedSheet!,
              onConnect: _connect,
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── Auth card ──────────────────────────────────────────────────────
          _AccountCard(
            isConnected: isConnected,
            user: _gss.currentUser,
            isLoading: _isSigningIn,
            onSignIn: _signIn,
            onSignOut: _signOut,
          ),
          const SizedBox(height: 20),

          if (!isConnected)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Icon(
                    Icons.table_chart_rounded,
                    size: 64,
                    color: context.themeTextSecondary.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to browse your spreadsheets',
                    style: TextStyle(color: context.themeTextSecondary),
                  ),
                ],
              ),
            )
          else ...[
            // ── Search ───────────────────────────────────────────────────────
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search spreadsheets…',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: context.themeTextSecondary,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
            const SizedBox(height: 12),

            // ── Create new ───────────────────────────────────────────────────
            AppCard(
              onTap: _isCreating ? null : _createSpreadsheet,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: context.themeBorder,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isCreating
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.themeAccent,
                            ),
                          )
                        : Icon(
                            Icons.add_rounded,
                            color: context.themeTextSecondary,
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Create new spreadsheet',
                    style: TextStyle(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Spreadsheet list ─────────────────────────────────────────────
            if (_isLoadingSheets)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_spreadsheets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'No spreadsheets match "$_searchQuery"'
                        : 'No spreadsheets found',
                    style: TextStyle(color: context.themeTextSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              Text(
                'RECENT SPREADSHEETS',
                style: TextStyle(
                  color: context.themeTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              for (final sheet in _spreadsheets) ...[
                _SpreadsheetTile(
                  sheet: sheet,
                  isSelected: _selected?.id == sheet.id,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _loadWorksheets(sheet);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],

            // ── Worksheet picker ─────────────────────────────────────────────
            if (_selected != null && _worksheets.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'WORKSHEETS',
                style: TextStyle(
                  color: context.themeTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final ws in _worksheets) ...[
                      _WorksheetChip(
                        label: ws,
                        isActive: _selectedSheet == ws,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedSheet = ws);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],

            // Bottom padding for the sticky bar
            const SizedBox(height: 100),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final bool isConnected;
  final dynamic user; // GoogleSignInAccount?
  final bool isLoading;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  const _AccountCard({
    required this.isConnected,
    required this.user,
    required this.isLoading,
    required this.onSignIn,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    const googleBlue = Color(0xFF4285F4);

    if (!isConnected) {
      return AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.table_chart_rounded, color: googleBlue, size: 36),
            const SizedBox(height: 12),
            Text(
              'Connect your Google account',
              style: TextStyle(
                color: context.themeTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Access your spreadsheets to sync scan data directly.',
              style: TextStyle(color: context.themeTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onSignIn,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: Text(isLoading ? 'Signing in…' : 'Sign in with Google'),
                style: FilledButton.styleFrom(
                  backgroundColor: googleBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Connected state
    final email = user?.email as String? ?? '';
    final displayName = user?.displayName as String? ?? '';

    return AppCard(
      color: const Color(0xFF4285F4).withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: googleBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (displayName.isNotEmpty
                        ? displayName[0]
                        : email.isNotEmpty
                            ? email[0]
                            : 'G')
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Connected',
                      style: TextStyle(
                        color: context.themeTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: Color(0xFF22C55E),
                    ),
                  ],
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onSignOut,
            style: TextButton.styleFrom(
              foregroundColor: context.themeTextSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Switch', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SpreadsheetTile extends StatelessWidget {
  final SpreadsheetInfo sheet;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpreadsheetTile({
    required this.sheet,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const sheetsGreen = Color(0xFF0F9D58);

    return AppCard(
      onTap: onTap,
      color: isSelected
          ? const Color(0xFF3F5AA9).withValues(alpha: 0.08)
          : null,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF3F5AA9),
                  width: 1.5,
                ),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: sheetsGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.table_chart_rounded,
                color: sheetsGreen,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sheet.title,
                    style: TextStyle(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sheet.modifiedTime != null)
                    Text(
                      _formatModified(sheet.modifiedTime!),
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF3F5AA9),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  String _formatModified(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _WorksheetChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _WorksheetChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? context.themeAccent.withValues(alpha: 0.12)
              : context.themeCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? context.themeAccent : context.themeBorder,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? context.themeAccent : context.themeTextSecondary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ConnectBottomBar extends StatelessWidget {
  final String spreadsheetTitle;
  final String sheetName;
  final VoidCallback onConnect;

  const _ConnectBottomBar({
    required this.spreadsheetTitle,
    required this.sheetName,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: context.themeCard,
        border: Border(top: BorderSide(color: context.themeBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_rounded,
                  color: Color(0xFF0F9D58), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$spreadsheetTitle › $sheetName',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Connect & Continue'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B2D61),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
