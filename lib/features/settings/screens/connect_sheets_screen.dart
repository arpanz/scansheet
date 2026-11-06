import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/sheet_summary.dart';
import '../../../core/widgets/ss.dart';
import 'drive_picker_screen.dart';

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
    if (_gss.isSignedIn) _loadSpreadsheets();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

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
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateSpreadsheetDialog(),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() => _isCreating = true);
    try {
      final id = await _gss.createSpreadsheet(title.trim());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _loadSpreadsheets();
      final newInfo = _spreadsheets.firstWhere(
        (s) => s.id == id,
        orElse: () => SpreadsheetInfo(id: id, title: title.trim()),
      );
      await _loadWorksheets(newInfo);
    } on GSheetsException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _pickFromDrive() async {
    final picked = await DrivePickerScreen.open(context);
    if (picked == null || !mounted) return;
    // It joins the list for good: picking granted drive.file access to it.
    setState(() {
      _spreadsheets = [
        picked,
        for (final s in _spreadsheets)
          if (s.id != picked.id) s,
      ];
    });
    await _loadWorksheets(picked);
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadSpreadsheets(query: value.trim().isEmpty ? null : value.trim());
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

  void _showError(String message) => showSsToast(context, message);

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final isConnected = _gss.isSignedIn;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(
                    children: [
                      SsIconButton(
                        LucideIcons.chevronLeft,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Connect Google Sheets',
                        style: SsText.sans(
                          size: 20,
                          weight: FontWeight.w600,
                          spacing: -0.4,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _AccountCard(
                    isConnected: isConnected,
                    user: _gss.currentUser,
                    isLoading: _isSigningIn,
                    onSignIn: _signIn,
                    onSignOut: _signOut,
                  ),
                  if (isConnected) ...[
                    const SizedBox(height: 18),
                    _searchField(c),
                    const SizedBox(height: 12),
                    SsCard(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      onTap: _isCreating ? null : _createSpreadsheet,
                      child: Row(
                        children: [
                          _isCreating
                              ? SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: c.emerald,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : SsIconTile.accent(context, LucideIcons.plus),
                          const SizedBox(width: 12),
                          Text(
                            'Create new spreadsheet',
                            style: SsText.label(color: c.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SsCard(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      onTap: _pickFromDrive,
                      child: Row(
                        children: [
                          const SsIconTile(LucideIcons.folderOpen),
                          const SizedBox(width: 12),
                          Text(
                            'Choose another sheet from Drive',
                            style: SsText.label(color: c.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isLoadingSheets)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(color: c.emerald),
                        ),
                      )
                    else if (_spreadsheets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No spreadsheets match “$_searchQuery”'
                                : 'Sheets you make or choose here show up in this list',
                            textAlign: TextAlign.center,
                            style: SsText.body(color: c.muted),
                          ),
                        ),
                      )
                    else ...[
                      const SsSectionHeader('Your spreadsheets'),
                      const SizedBox(height: 8),
                      SsListGroup(
                        children: [
                          for (final sheet in _spreadsheets)
                            SsListRow(
                              key: ValueKey(sheet.id),
                              leading: const SsIconTile(LucideIcons.sheet),
                              title: sheet.title,
                              subtitle: sheet.modifiedTime == null
                                  ? null
                                  : 'Modified ${relativeTime(sheet.modifiedTime!)}',
                              trailing: SsRadio(
                                selected: _selected?.id == sheet.id,
                              ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _loadWorksheets(sheet);
                              },
                            ),
                        ],
                      ),
                    ],
                    if (_selected != null && _worksheets.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const SsSectionHeader('Tab'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final worksheet in _worksheets)
                            _WorksheetChip(
                              label: worksheet,
                              selected: _selectedSheet == worksheet,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedSheet = worksheet);
                              },
                            ),
                        ],
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to browse your spreadsheets',
                      textAlign: TextAlign.center,
                      style: SsText.body(color: c.muted),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SsButton(
                'Use this sheet',
                onPressed: _selected != null && _selectedSheet != null
                    ? _connect
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(SsColors c) => TextField(
    controller: _searchCtrl,
    onChanged: _onSearchChanged,
    style: SsText.body(color: c.ink),
    decoration: InputDecoration(
      hintText: 'Search spreadsheets…',
      hintStyle: SsText.body(color: c.muted),
      prefixIcon: Icon(LucideIcons.search, size: 18, color: c.muted),
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SsRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SsRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  final bool isConnected;
  final dynamic user;
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
    final c = context.ss;
    if (!isConnected) {
      return SsCard(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                SsIconTile.accent(context, LucideIcons.sheet),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect your Google account',
                        style: SsText.label(color: c.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Access spreadsheets to sync scan data.',
                        style: SsText.caption(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SsButton(
              isLoading ? 'Signing in…' : 'Sign in with Google',
              icon: LucideIcons.logIn,
              loading: isLoading,
              onPressed: isLoading ? null : onSignIn,
            ),
          ],
        ),
      );
    }

    final email = user?.email as String? ?? '';
    final name = user?.displayName as String? ?? '';
    final initial = (name.isNotEmpty ? name : email).isNotEmpty
        ? (name.isNotEmpty ? name : email)[0]
        : 'G';
    return SsCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SsAvatar(initial: initial),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'Google account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.label(color: c.ink),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SsText.caption(color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SsButton.secondary('Switch', expand: false, onPressed: onSignOut),
        ],
      ),
    );
  }
}

class _WorksheetChip extends StatelessWidget {
  const _WorksheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: selected ? c.ink : c.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: selected ? null : Border.all(color: c.line),
          ),
          child: Text(
            label,
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: selected ? c.onInk : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateSpreadsheetDialog extends StatefulWidget {
  const _CreateSpreadsheetDialog();

  @override
  State<_CreateSpreadsheetDialog> createState() =>
      _CreateSpreadsheetDialogState();
}

class _CreateSpreadsheetDialogState extends State<_CreateSpreadsheetDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.ss.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(
      'New Spreadsheet',
      style: SsText.section(color: context.ss.ink),
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      style: SsText.body(color: context.ss.ink),
      decoration: InputDecoration(
        labelText: 'Spreadsheet name',
        hintText: 'e.g. Inventory Jan 2026',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Cancel', style: SsText.label(color: context.ss.muted)),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text('Create', style: SsText.label(color: context.ss.emerald)),
      ),
    ],
  );
}
