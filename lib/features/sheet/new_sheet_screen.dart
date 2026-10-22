import 'package:flutter/material.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/template_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/column_kind.dart';
import '../scan/models/scan_session.dart';
import '../scan/screens/scan_session_screen.dart';
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
  bool _mergeRepeats = true;
  bool _warnDuplicates = false;
  bool _showConfirmation = false;
  bool _loading = false;

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

  bool get _hasNumber =>
      _columns.any((c) => c.type == SessionColumnType.manual && c.isNumeric);

  Future<void> _pickTemplate(SessionTemplate template) async {
    setState(() {
      _name.text = template.name;
      _columns = List.of(template.columns);
      _templateIcon = template.icon;
    });
  }

  Future<void> _editColumn(int index) async {
    final result = await showAddColumnSheet(context, editing: _columns[index]);
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
    final result = await showAddColumnSheet(context);
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
    setState(() => _loading = true);
    try {
      String? spreadsheetId;
      final destination = switch (_destination) {
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
        spreadsheetId = await service.createSpreadsheet(name);
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
        sheetName: null,
        iconName: _templateIcon ?? 'inventory',
      );
      await ScanSessionService.saveSession(session);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        FadeSlideRoute(page: ScanSessionScreen(session: session)),
      );
    } catch (e) {
      if (mounted) showSsToast(context, 'Could not create sheet: $e');
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
                    'sheets' => 'Rows sync live to a new sheet in My Drive',
                    'xlsx' =>
                      'Saved on this phone, share the .xlsx when you finish',
                    _ => 'Plain file that opens in any spreadsheet tool',
                  }, style: SsText.sans(size: 12, color: c.muted)),
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
