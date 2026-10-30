import 'package:flutter/material.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/lookup_list_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/template_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../../core/widgets/file_marks.dart';
import '../scan/models/column_kind.dart';
import '../scan/models/scan_session.dart';
import '../scan/screens/scan_session_screen.dart';
import '../lists/list_import_screen.dart';
import '../settings/screens/connect_sheets_screen.dart';
import '../team/join_team_screen.dart';
import '../sync/plan_limits.dart';
import 'add_column_sheet.dart';

class NewSheetScreen extends StatefulWidget {
  const NewSheetScreen({super.key, this.template, this.copyFrom});
  final SessionTemplate? template;
  final ScanSession? copyFrom;

  @override
  State<NewSheetScreen> createState() => _NewSheetScreenState();
}

class _NewSheetScreenState extends State<NewSheetScreen> {
  late final TextEditingController _name;
  late List<SessionColumn> _columns;
  String _destination = 'sheets';
  String? _templateIcon;
  SheetDestination? _existing;
  bool _mergeRepeats = true;
  bool _warnDuplicates = false;
  bool _showConfirmation = false;
  bool _loading = false;
  LookupList? _list;
  UnknownCodes _unknownCodes = UnknownCodes.ask;
  bool _newTabInFile = false;

  /// More options starts open when it already holds something to see.
  bool _moreOpen = false;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    final copyFrom = widget.copyFrom;
    _name = TextEditingController(
      text: copyFrom != null ? '${copyFrom.name} 2' : template?.name ?? '',
    );
    _columns = copyFrom != null
        ? List.of(copyFrom.columns)
        : template == null
        ? [const SessionColumn(name: 'Item code', type: SessionColumnType.scan)]
        : List.of(template.columns);
    _templateIcon = copyFrom?.iconName ?? template?.icon;
    if (copyFrom != null) {
      _destination = 'sheets';
      _newTabInFile = true;
      _existing = SheetDestination(
        spreadsheetId: copyFrom.spreadsheetId!,
        spreadsheetTitle: copyFrom.spreadsheetTitle ?? copyFrom.name,
        sheetName: '',
      );
      _mergeRepeats = copyFrom.mergeRepeats;
      _warnDuplicates = copyFrom.warnDuplicates;
      _showConfirmation = copyFrom.showScanConfirmation;
      _unknownCodes = copyFrom.unknownCodes;
      if (copyFrom.lookupListId != null) {
        _list = LookupListService.get(copyFrom.lookupListId!);
      }
      _moreOpen = _list != null || _showConfirmation;
    }
    if (template?.listPrompt != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _askForList(template!),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Several phones writing to one spreadsheet is how a team shares a sheet
  /// until team sheets exist.
  Future<void> _pickExisting() async {
    final picked = await Navigator.of(
      context,
    ).push<SheetDestination>(FadeSlideRoute(page: const ConnectSheetsScreen()));
    if (picked != null && mounted) {
      setState(() {
        _existing = picked;
        _newTabInFile = false;
      });
    }
  }

  /// List columns a From list column can show (the code column is the scan).
  List<String> get _listHeaders => [
    for (final (i, h) in (_list?.headers ?? const <String>[]).indexed)
      if (i != _list!.codeColumn && h.isNotEmpty) h,
  ];

  /// Returns whether a list is attached afterwards.
  Future<bool> _pickList() async {
    final lists = LookupListService.all();
    final picked = lists.isEmpty
        ? 'import'
        : await showSsSheet<String>(
            context,
            builder: (ctx) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Check against',
                    style: SsText.section(color: ctx.ss.ink),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SsListGroup(
                        children: [
                          for (final list in lists)
                            SsListRow(
                              title: list.name,
                              subtitle:
                                  '${list.length} entries · ${list.source.label}',
                              trailing: SsRadio(selected: list.id == _list?.id),
                              onTap: () => Navigator.pop(ctx, list.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SsButton.secondary(
                    'Import a new list',
                    icon: LucideIcons.plus,
                    onPressed: () => Navigator.pop(ctx, 'import'),
                  ),
                ],
              ),
            ),
          );
    if (!mounted || picked == null) return _list != null;
    final list = picked == 'import'
        ? await Navigator.of(
            context,
          ).push<LookupList>(FadeSlideRoute(page: const ListImportScreen()))
        : LookupListService.get(picked);
    if (list != null && mounted) _attach(list);
    return _list != null;
  }

  /// A template built around a list (Attendance, Stock count) asks for one.
  /// Without it, its From list columns become typed columns.
  Future<void> _askForList(SessionTemplate template) async {
    if (!mounted) return;
    final pick = await showSsSheet<bool>(
      context,
      builder: (ctx) {
        final c = ctx.ss;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SsIconTile(
                  LucideIcons.listChecks,
                  background: c.emeraldTint,
                  color: c.emerald,
                  size: 48,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${template.name} works best with a list',
                style: SsText.heading(color: c.ink),
              ),
              const SizedBox(height: 6),
              Text(template.listPrompt!, style: SsText.body(color: c.ink2)),
              const SizedBox(height: 20),
              SsButton(
                'Pick a list',
                icon: LucideIcons.listChecks,
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              SsButton(
                'Not now',
                kind: SsButtonKind.ghost,
                large: false,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (pick == true && await _pickList()) return;
    if (mounted) setState(() => _columns = template.columnsWithoutList);
  }

  /// Attaching a list keeps From list columns it can fill, adds one per
  /// "Fill in when scanned" column after the first scan column, and turns
  /// on Warn on repeats (attendance and audits want each code once).
  void _attach(LookupList list) {
    setState(() {
      _list = list;
      _moreOpen = true;
      _warnDuplicates = true;
      String? header(String? field) => list.headers
          .where((h) => h.toLowerCase() == field?.toLowerCase())
          .firstOrNull;
      _columns = [
        for (final col in _columns)
          if (col.type != SessionColumnType.fromList)
            col
          else if (header(col.listField) case final h?)
            col.copyWith(listField: h),
      ];
      final have = _columns.map((c) => c.listField).toSet();
      final add = [
        for (final i in list.fillColumns)
          if (i < list.headers.length && !have.contains(list.headers[i]))
            SessionColumn(
              name: list.headers[i],
              type: SessionColumnType.fromList,
              listField: list.headers[i],
            ),
      ];
      final at =
          _columns.indexWhere((c) => c.type == SessionColumnType.scan) + 1;
      final room = ScanSession.maxColumns - _columns.length;
      _columns.insertAll(at, add.take(room.clamp(0, add.length)));
    });
  }

  void _detach() => setState(() {
    _list = null;
    _columns.removeWhere((c) => c.type == SessionColumnType.fromList);
  });

  bool get _hasNumber =>
      _columns.any((c) => c.type == SessionColumnType.manual && c.isNumeric);

  Future<void> _pickTemplate(SessionTemplate template) async {
    setState(() {
      _name.text = template.name;
      _columns = List.of(template.columns);
      _templateIcon = template.icon;
    });
    // A staff list attached for Attendance is the wrong list for a stock
    // count: a template built around a list starts without one and asks.
    if (template.listPrompt != null) {
      setState(() => _list = null);
      return _askForList(template);
    }
    if (_list case final list?) _attach(list);
  }

  Future<void> _editColumn(int index) async {
    final result = await showAddColumnSheet(
      context,
      editing: _columns[index],
      listHeaders: _listHeaders,
    );
    if (result != null && mounted) setState(() => _columns[index] = result);
  }

  Future<void> _addColumn() async {
    if (_columns.length >= ScanSession.maxColumns) {
      showSsToast(
        context,
        'Maximum ${ScanSession.maxColumns} columns allowed.',
      );
      return;
    }
    final result = await showAddColumnSheet(context, listHeaders: _listHeaders);
    if (result != null && mounted) setState(() => _columns.add(result));
  }

  Future<void> _start() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSsToast(context, 'Enter a sheet name.');
      return;
    }
    if (!_columns.any((c) => c.type == SessionColumnType.scan)) {
      showSsToast(context, 'Add at least one scan column.');
      return;
    }
    if (_columns.length > ScanSession.maxColumns) {
      showSsToast(
        context,
        'Maximum ${ScanSession.maxColumns} columns allowed.',
      );
      return;
    }
    if (_list == null &&
        _columns.any((c) => c.type == SessionColumnType.fromList)) {
      showSsToast(context, 'Pick a list for the From list columns.');
      _pickList();
      return;
    }
    setState(() => _loading = true);
    try {
      String? spreadsheetId;
      String? sheetName;
      String? spreadsheetTitle;
      var createdFile = false;
      var destination = switch (_destination) {
        'sheets' => SessionDestination.googleSheets,
        'xlsx' => SessionDestination.localXlsx,
        _ => SessionDestination.localCsv,
      };
      if (destination == SessionDestination.googleSheets) {
        final service = GoogleSheetsService.instance;
        if (!service.isSignedIn) {
          final account = await service.signIn();
          if (account == null) {
            if (mounted) showSsToast(context, 'Google sign-in was cancelled.');
            return;
          }
        }
        if (!mounted) return;
        if (!UsageService.instance.canOpenSheet()) {
          switch (await showOpenSheetsLimit(context)) {
            case OpenSheetChoice.proceed:
              break;
            case OpenSheetChoice.keepOnPhone:
              destination = SessionDestination.localXlsx;
            case OpenSheetChoice.cancel:
              return;
          }
        }
        if (destination == SessionDestination.googleSheets) {
          if (_newTabInFile && _existing != null) {
            spreadsheetId = _existing!.spreadsheetId;
            spreadsheetTitle = _existing!.spreadsheetTitle;
            sheetName = await service.addTab(spreadsheetId, name);
          } else if (_existing != null) {
            spreadsheetId = _existing!.spreadsheetId;
            spreadsheetTitle = _existing!.spreadsheetTitle;
            sheetName = _existing!.sheetName;
          } else {
            spreadsheetId = await service.createSpreadsheet(
              name,
              firstTab: name,
            );
            sheetName = name;
            spreadsheetTitle = name;
            createdFile = true;
          }
        }
      }
      final session = ScanSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        columns: List.of(_columns),
        createdAt: DateTime.now(),
        isActive: true,
        warnDuplicates: _warnDuplicates,
        showScanConfirmation: _showConfirmation,
        mergeRepeats: _hasNumber && _mergeRepeats,
        destination: destination,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        spreadsheetTitle: spreadsheetTitle,
        createdFile: createdFile,
        iconName: _templateIcon ?? 'inventory',
        lookupListId: _list?.id,
        unknownCodes: _unknownCodes,
      );
      await ScanSessionService.saveSession(session);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        FadeSlideRoute(page: ScanSessionScreen(session: session)),
      );
    } catch (e) {
      debugPrint('Create sheet failed: $e');
      if (mounted) {
        showSsToast(
          context,
          '$e'.contains('sign_in_failed')
              ? 'Couldn’t sign in to Google. Try again, or save as Excel.'
              : 'Couldn’t create the sheet. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Where rows go, in words and as the preview's title: the destination
  /// mark, what gets made, and the file › tab name the rows land in.
  ({FileMark mark, String title, String detail, String file}) _where(
    bool signedIn,
  ) {
    final name = _name.text.trim().isEmpty ? 'Your sheet' : _name.text.trim();
    final account = signedIn
        ? 'Signed in as ${GoogleSheetsService.instance.currentUser?.email}'
        : 'You’ll sign in to Google when you start';
    final existing = _existing;
    return switch (_destination) {
      'xlsx' => (
        mark: FileMark.excel,
        title: 'Excel file on this phone',
        detail: 'Share or save the .xlsx whenever you like',
        file: '$name.xlsx',
      ),
      'csv' => (
        mark: FileMark.csv,
        title: 'CSV file on this phone',
        detail: 'Opens in any spreadsheet app',
        file: '$name.csv',
      ),
      _ when existing != null => (
        mark: FileMark.sheets,
        title: _newTabInFile
            ? 'New tab in “${existing.spreadsheetTitle}”'
            : '“${existing.spreadsheetTitle}” › ${existing.sheetName}',
        detail: account,
        file:
            '${existing.spreadsheetTitle} › '
            '${_newTabInFile ? name : existing.sheetName}',
      ),
      _ => (
        mark: FileMark.sheets,
        title: 'New file in your Google Drive',
        detail: account,
        file: '$name › $name',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final templates = TemplateService.getBuiltInTemplates();
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  SsIconButton(
                    LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  Text(
                    'New sheet',
                    style: SsText.sans(
                      size: 17,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showTemplates(context, templates),
                    child: Text(
                      'Templates',
                      style: SsText.sans(
                        size: 14,
                        weight: FontWeight.w500,
                        color: c.emerald,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: GoogleSheetsService.instance.signedInNotifier,
                builder: (context, signedIn, _) => AnimatedBuilder(
                  animation: _name,
                  builder: (context, _) {
                    final where = _where(signedIn);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                      children: [
                        const _Step(1, 'Name it'),
                        const SizedBox(height: 10),
                        _NameField(controller: _name),
                        const SizedBox(height: 26),
                        const _Step(2, 'Where rows go'),
                        const SizedBox(height: 10),
                        SsSegmented<String>(
                          options: const [
                            ('sheets', 'Google Sheets'),
                            ('xlsx', 'Excel'),
                            ('csv', 'CSV'),
                          ],
                          value: _destination,
                          leading: (v) => SsFileMark(switch (v) {
                            'sheets' => FileMark.sheets,
                            'xlsx' => FileMark.excel,
                            _ => FileMark.csv,
                          }, size: 16),
                          onChanged: (v) => setState(() => _destination = v),
                        ),
                        const SizedBox(height: 10),
                        _WhereCard(
                          mark: where.mark,
                          title: where.title,
                          detail: where.detail,
                          action: _destination != 'sheets'
                              ? null
                              : _existing == null
                              ? 'Use existing'
                              : 'New file',
                          onAction: _existing == null
                              ? _pickExisting
                              : () => setState(() {
                                  _existing = null;
                                  _newTabInFile = false;
                                }),
                        ),
                        const SizedBox(height: 26),
                        _Step(
                          3,
                          'What each row holds',
                          hint:
                              'One row per scan. Tap a column to change it, '
                              'hold the grip to move it.',
                        ),
                        const SizedBox(height: 10),
                        _columnList(c),
                        const SizedBox(height: 14),
                        _RowPreview(
                          file: where.file,
                          mark: where.mark,
                          columns: _columns,
                        ),
                        const SizedBox(height: 26),
                        _moreOptions(c),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  FadeSlideRoute(page: const JoinTeamScreen()),
                                ),
                            child: Text(
                              'Joining a teammate’s sheet? Enter their code',
                              style: SsText.sans(
                                size: 13,
                                weight: FontWeight.w600,
                                color: c.emerald,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: c.paper,
                boxShadow: [
                  BoxShadow(
                    color: c.paper.withValues(alpha: .9),
                    blurRadius: 16,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: SsButton(
                'Start scanning',
                icon: ssScanIcon,
                onPressed: _start,
                loading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The sheet's columns: tap to edit, drag the grip to move, swipe away
  /// to remove, Add column at the end.
  Widget _columnList(SsColors c) {
    final scanCount = _columns
        .where((x) => x.type == SessionColumnType.scan)
        .length;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _columns.length,
            onReorderItem: (oldIndex, newIndex) => setState(() {
              final item = _columns.removeAt(oldIndex);
              _columns.insert(newIndex, item);
            }),
            itemBuilder: (context, index) {
              final col = _columns[index];
              final kind = ColumnKind.of(col);
              final scanNumber =
                  _columns
                      .take(index)
                      .where((x) => x.type == SessionColumnType.scan)
                      .length +
                  1;
              return Dismissible(
                key: ValueKey('col-${identityHashCode(col)}-$index'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => setState(() => _columns.removeAt(index)),
                background: Container(
                  color: c.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(LucideIcons.trash2, color: c.onInk),
                ),
                child: InkWell(
                  onTap: () => _editColumn(index),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.only(left: 10, right: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.lineSoft)),
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            LucideIcons.gripVertical,
                            size: 16,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                col.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SsText.sans(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: c.ink,
                                ),
                              ),
                              Text(
                                ColumnKind.detailOf(
                                  col,
                                  scanNumber: scanNumber,
                                  scanCount: scanCount,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SsText.sans(size: 11, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        SsTag(kind.tag, kind: kind.tagKind),
                        const SizedBox(width: 4),
                        SsIconButton(
                          LucideIcons.moreVertical,
                          size: 40,
                          color: c.muted,
                          tooltip: 'Edit column',
                          onPressed: () => _editColumn(index),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          TextButton.icon(
            onPressed: _addColumn,
            icon: Icon(LucideIcons.plus, size: 18, color: c.emerald),
            label: Text(
              'Add column',
              style: SsText.sans(
                size: 15,
                weight: FontWeight.w600,
                color: c.emerald,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Checking against a list and how repeats and reviews work: folded
  /// away with a one-line summary, since the defaults suit most sheets.
  Widget _moreOptions(SsColors c) {
    final on = [
      if (_list case final list?) 'Checks against ${list.name}',
      if (_hasNumber && _mergeRepeats) 'Repeats add to Qty',
      if (_warnDuplicates) 'Warns on repeats',
      if (_showConfirmation) 'Review each scan',
    ];
    return SsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SsRadius.lg),
            onTap: () => setState(() => _moreOpen = !_moreOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  SsIconTile(LucideIcons.slidersHorizontal, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'More options',
                          style: SsText.sans(
                            size: 15,
                            weight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          on.isEmpty
                              ? 'Check against a list, repeats, review'
                              : on.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SsText.sans(size: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _moreOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 20,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_moreOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ListCard(
                          list: _list,
                          unknownCodes: _unknownCodes,
                          onPick: _pickList,
                          onRemove: _detach,
                          onUnknownCodes: (v) =>
                              setState(() => _unknownCodes = v),
                        ),
                        const SizedBox(height: 4),
                        if (_hasNumber)
                          _ToggleRow(
                            label: 'Repeats add to Qty',
                            hint: 'Scan the same item again to count it',
                            value: _mergeRepeats,
                            onChanged: (v) => setState(() => _mergeRepeats = v),
                          ),
                        _ToggleRow(
                          label: 'Warn on repeats',
                          hint: 'Ask before adding the same code as a new row',
                          value: _warnDuplicates,
                          onChanged: (v) => setState(() => _warnDuplicates = v),
                        ),
                        _ToggleRow(
                          label: 'Review each scan',
                          hint: 'Edit the row before it’s saved',
                          value: _showConfirmation,
                          onChanged: (v) =>
                              setState(() => _showConfirmation = v),
                          last: true,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTemplates(
    BuildContext context,
    List<SessionTemplate> templates,
  ) async {
    await showSsSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Templates',
              style: SsText.sans(
                size: 20,
                weight: FontWeight.w600,
                color: ctx.ss.ink,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SsListGroup(
                  children: [
                    for (final template in templates)
                      SsListRow(
                        leading: SsIconTile(sheetIcon(template.icon), size: 36),
                        title: template.name,
                        subtitle: template.columnSummary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickTemplate(template);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Check against a list": pick a list and what to do with codes not on it.
class _ListCard extends StatelessWidget {
  final LookupList? list;
  final UnknownCodes unknownCodes;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final ValueChanged<UnknownCodes> onUnknownCodes;
  const _ListCard({
    required this.list,
    required this.unknownCodes,
    required this.onPick,
    required this.onRemove,
    required this.onUnknownCodes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final list = this.list;
    return SsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SsIconTile(
                LucideIcons.listChecks,
                background: c.emeraldTint,
                color: c.emerald,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list?.name ?? 'Check against a list',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SsText.sans(
                        size: 15,
                        weight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      list == null
                          ? 'Staff roster, stock list or asset register'
                          : '${list.length} entries · ${list.source.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SsText.sans(size: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onPick,
                child: Text(
                  list == null ? 'Pick' : 'Change',
                  style: SsText.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: c.emerald,
                  ),
                ),
              ),
              if (list != null)
                SsIconButton(
                  LucideIcons.x,
                  size: 36,
                  color: c.muted,
                  tooltip: 'Remove list',
                  onPressed: onRemove,
                ),
            ],
          ),
          if (list != null) ...[
            const SizedBox(height: 12),
            Text(
              'Codes not on the list',
              style: SsText.sans(
                size: 13,
                weight: FontWeight.w500,
                color: c.ink2,
              ),
            ),
            const SizedBox(height: 8),
            SsSegmented<UnknownCodes>(
              options: const [
                (UnknownCodes.ask, 'Ask'),
                (UnknownCodes.flag, 'Add and flag'),
                (UnknownCodes.skip, 'Skip'),
              ],
              value: unknownCodes,
              onChanged: onUnknownCodes,
            ),
            const SizedBox(height: 6),
            Text(switch (unknownCodes) {
              UnknownCodes.ask => 'You choose each time: skip it or add it',
              UnknownCodes.flag =>
                'Added with On list = No so you can check later',
              UnknownCodes.skip => 'Not added. The scanner beeps twice',
            }, style: SsText.sans(size: 12, color: c.muted)),
          ],
        ],
      ),
    );
  }
}

/// A numbered step heading, so the page reads top to bottom as 1, 2, 3.
class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String? hint;
  const _Step(this.number, this.title, {this.hint});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
              child: Text(
                '$number',
                style: SsText.sans(
                  size: 12,
                  weight: FontWeight.w700,
                  color: c.onInk,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: SsText.sans(
                size: 16,
                weight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text(hint!, style: SsText.sans(size: 12, color: c.muted)),
          ),
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  const _NameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        style: SsText.sans(size: 16, weight: FontWeight.w500, color: c.ink),
        decoration: InputDecoration(
          hintText: 'e.g. Stock count, Attendance',
          hintStyle: SsText.sans(size: 16, color: c.muted),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.line, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.ink, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// What gets made and where: "New file in your Google Drive", the Google
/// account, and a switch between a new file and an existing one.
class _WhereCard extends StatelessWidget {
  final FileMark mark;
  final String title, detail;
  final String? action;
  final VoidCallback onAction;
  const _WhereCard({
    required this.mark,
    required this.title,
    required this.detail,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          SsFileMarkTile(mark, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(size: 12, color: c.muted),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: c.emerald,
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A small picture of the finished sheet: its file › tab, the column
/// headers, and one made-up row showing what each scan fills in.
class _RowPreview extends StatelessWidget {
  final String file;
  final FileMark mark;
  final List<SessionColumn> columns;
  const _RowPreview({
    required this.file,
    required this.mark,
    required this.columns,
  });

  /// A believable value for [col], and whether it's only a placeholder
  /// (typed later, or found at scan time).
  static (String, bool) _sample(SessionColumn col, int scanNumber) =>
      switch (ColumnKind.of(col)) {
        ColumnKind.scan => (
          scanNumber == 1 ? '8901063012345' : 'SN-20417',
          false,
        ),
        ColumnKind.product => ('Biscuits 250 g', false),
        ColumnKind.fromList => ('from list', true),
        ColumnKind.pickList => (
          col.defaultValue ?? col.choices.firstOrNull ?? '',
          false,
        ),
        ColumnKind.number => (col.defaultValue ?? '${col.stepSize}', false),
        ColumnKind.text => ('typed', true),
        ColumnKind.readText => ('03/2027', false),
        ColumnKind.time => ('10:42', false),
        ColumnKind.location => (col.locationFormat.example, false),
        ColumnKind.fixed => (
          (col.fixedValue ?? '').isEmpty ? 'set once' : col.fixedValue!,
          (col.fixedValue ?? '').isEmpty,
        ),
        ColumnKind.auto => ('1', false),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    var scans = 0;
    final cells = [
      for (final col in columns)
        (
          col,
          _sample(col, col.type == SessionColumnType.scan ? ++scans : scans),
        ),
    ];
    double width(SessionColumn col, String value) =>
        ((value.length > col.name.length ? value.length : col.name.length) *
                    7.4 +
                24)
            .clamp(64.0, 170.0);

    Widget cell(String text, double w, TextStyle style, {IconData? icon}) =>
        Container(
          width: w,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.lineSoft)),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: c.emerald),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each scan adds a row like this',
          style: SsText.sans(size: 13, weight: FontWeight.w600, color: c.ink2),
        ),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: c.chip,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SsFileMark(mark, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Few columns stretch to the card's width, like a real sheet;
              // many scroll sideways.
              LayoutBuilder(
                builder: (context, box) {
                  final natural = [
                    for (final (col, (value, _)) in cells) width(col, value),
                  ];
                  final sum = natural.fold<double>(0, (a, b) => a + b);
                  final scale = 30 + sum < box.maxWidth
                      ? (box.maxWidth - 30) / sum
                      : 1.0;
                  final w = [for (final n in natural) n * scale];
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: c.line)),
                          ),
                          child: Row(
                            children: [
                              cell('', 30, SsText.caption(color: c.muted)),
                              for (final (k, (col, _)) in cells.indexed)
                                cell(
                                  col.name.toUpperCase(),
                                  w[k],
                                  SsText.sans(
                                    size: 10,
                                    weight: FontWeight.w600,
                                    spacing: .5,
                                    color: c.muted,
                                  ),
                                  icon: col.type == SessionColumnType.scan
                                      ? LucideIcons.scanLine
                                      : null,
                                ),
                            ],
                          ),
                        ),
                        ColoredBox(
                          color: c.limeRow,
                          child: Row(
                            children: [
                              cell(
                                '1',
                                30,
                                SsText.mono(size: 11, color: c.muted),
                              ),
                              for (final (k, (_, (value, placeholder)))
                                  in cells.indexed)
                                cell(
                                  value,
                                  w[k],
                                  placeholder
                                      ? SsText.sans(
                                          size: 12,
                                          color: c.muted,
                                        ).copyWith(fontStyle: FontStyle.italic)
                                      : SsText.mono(size: 12, color: c.ink),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Columns marked '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(LucideIcons.scanLine, size: 12, color: c.emerald),
              ),
              const TextSpan(
                text:
                    ' come from the camera. The rest fill in by themselves '
                    'or with a tap while you scan.',
              ),
            ],
          ),
          style: SsText.sans(size: 12, color: c.muted),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label, hint;
  final bool value, last;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: SsText.sans(
                    size: 15,
                    weight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
                Text(hint, style: SsText.sans(size: 11, color: c.muted)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: c.emerald,
          ),
        ],
      ),
    );
  }
}
