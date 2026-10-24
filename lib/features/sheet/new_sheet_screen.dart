import 'package:flutter/material.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/lookup_list_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/template_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/column_kind.dart';
import '../scan/models/scan_session.dart';
import '../scan/screens/scan_session_screen.dart';
import '../lists/list_import_screen.dart';
import '../settings/screens/connect_sheets_screen.dart';
import '../sync/plan_limits.dart';
import 'add_column_sheet.dart';

class NewSheetScreen extends StatefulWidget {
  const NewSheetScreen({super.key, this.template});
  final SessionTemplate? template;

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

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _name = TextEditingController(text: template?.name ?? '');
    _columns = template == null
        ? [const SessionColumn(name: 'Item code', type: SessionColumnType.scan)]
        : List.of(template.columns);
    _templateIcon = template?.icon;
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
    if (picked != null && mounted) setState(() => _existing = picked);
  }

  /// List columns a From list column can show (the code column is the scan).
  List<String> get _listHeaders => [
    for (final (i, h) in (_list?.headers ?? const <String>[]).indexed)
      if (i != _list!.codeColumn && h.isNotEmpty) h,
  ];

  Future<void> _pickList() async {
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
    if (!mounted || picked == null) return;
    final list = picked == 'import'
        ? await Navigator.of(
            context,
          ).push<LookupList>(FadeSlideRoute(page: const ListImportScreen()))
        : LookupListService.get(picked);
    if (list != null && mounted) _attach(list);
  }

  /// Attaching a list keeps From list columns it can fill, adds one per
  /// "Fill in when scanned" column after the first scan column, and turns
  /// on Warn on repeats (attendance and audits want each code once).
  void _attach(LookupList list) {
    setState(() {
      _list = list;
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
          spreadsheetId =
              _existing?.spreadsheetId ?? await service.createSpreadsheet(name);
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
        sheetName: spreadsheetId == null ? null : _existing?.sheetName,
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

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final templates = TemplateService.getBuiltInTemplates();
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                children: [
                  Row(
                    children: [
                      SsIconButton(
                        LucideIcons.x,
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
                  const SizedBox(height: 20),
                  _LabeledField(label: 'Name', controller: _name),
                  const SizedBox(height: 18),
                  Text(
                    'Save to',
                    style: SsText.sans(
                      size: 13,
                      weight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SsSegmented<String>(
                    options: const [
                      ('sheets', 'Google Sheets'),
                      ('xlsx', 'Excel'),
                      ('csv', 'CSV'),
                    ],
                    value: _destination,
                    onChanged: (v) => setState(() => _destination = v),
                  ),
                  const SizedBox(height: 7),
                  Text(switch (_destination) {
                    'sheets' when _existing != null =>
                      'Rows go to “${_existing!.spreadsheetTitle}” › '
                          '${_existing!.sheetName}. Teammates can pick the '
                          'same spreadsheet on their phones.',
                    'sheets' => 'Rows sync live to a new sheet in My Drive',
                    'xlsx' =>
                      'Saved on this phone, share the .xlsx when you finish',
                    _ => 'Plain file that opens in any spreadsheet tool',
                  }, style: SsText.sans(size: 12, color: c.muted)),
                  if (_destination == 'sheets')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _existing == null
                            ? _pickExisting
                            : () => setState(() => _existing = null),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: c.emerald,
                        ),
                        child: Text(
                          _existing == null
                              ? 'Use an existing spreadsheet'
                              : 'Make a new one instead',
                          style: SsText.sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: c.emerald,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _ListCard(
                    list: _list,
                    unknownCodes: _unknownCodes,
                    onPick: _pickList,
                    onRemove: _detach,
                    onUnknownCodes: (v) => setState(() => _unknownCodes = v),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Columns',
                        style: SsText.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: c.ink2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Drag to reorder',
                        style: SsText.sans(size: 12, color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Material(
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
                            return Dismissible(
                              key: ValueKey(
                                'col-${identityHashCode(col)}-$index',
                              ),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) =>
                                  setState(() => _columns.removeAt(index)),
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
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    right: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: c.lineSoft),
                                    ),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                firstScan:
                                                    _columns
                                                        .take(index)
                                                        .where(
                                                          (x) =>
                                                              x.type ==
                                                              SessionColumnType
                                                                  .scan,
                                                        )
                                                        .isEmpty &&
                                                    col.type ==
                                                        SessionColumnType.scan,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: SsText.sans(
                                                size: 11,
                                                color: c.muted,
                                              ),
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
                          icon: Icon(
                            LucideIcons.plus,
                            size: 18,
                            color: c.emerald,
                          ),
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
                  ),
                  const SizedBox(height: 16),
                  SsCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
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
                ],
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
            for (final template in templates)
              ListTile(
                title: Text(template.name),
                subtitle: Text(template.columnSummary),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickTemplate(template);
                },
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

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _LabeledField({required this.label, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: SsText.sans(size: 13, weight: FontWeight.w500, color: c.ink2),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: TextField(
            controller: controller,
            style: SsText.sans(size: 16, weight: FontWeight.w500, color: c.ink),
            decoration: InputDecoration(
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
