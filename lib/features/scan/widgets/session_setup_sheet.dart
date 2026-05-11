import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/template_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/screens/connect_sheets_screen.dart';
import '../models/scan_session.dart';
import '../screens/scan_session_screen.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/services/scan_session_service.dart';

/// Bottom sheet that lets the user configure a new Scan Session.
/// Optionally seeded from a [SessionTemplate] chosen in [TemplatePicker].
class SessionSetupSheet extends StatefulWidget {
  /// When non-null, the sheet pre-fills name + columns from this template.
  final SessionTemplate? initialTemplate;

  /// Called when the user returns from [ScanSessionScreen] back to the caller.
  /// Use this to trigger a rebuild on the parent (e.g. scan_screen).
  final VoidCallback? onSessionEnded;

  const SessionSetupSheet({
    super.key,
    this.initialTemplate,
    this.onSessionEnded,
  });

  @override
  State<SessionSetupSheet> createState() => _SessionSetupSheetState();
}

class _SessionSetupSheetState extends State<SessionSetupSheet> {
  late final TextEditingController _nameController;
  bool _warnDuplicates = false;
  late final List<_EditableColumn> _columns;
  String _destination = 'csv'; // 'csv', 'xlsx', 'sheets'

  static String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][m];

  @override
  void initState() {
    super.initState();
    final tmpl = widget.initialTemplate;
    if (tmpl != null) {
      _nameController = TextEditingController(text: tmpl.name);
      _columns = tmpl.columns
          .map(
            (c) => _EditableColumn(
              name: c.name,
              type: c.type,
              fixedValue: c.fixedValue,
              deletable: c.type != SessionColumnType.timestamp,
            ),
          )
          .toList();
    } else {
      _nameController = TextEditingController(
        text:
            'Sheet ${DateTime.now().day} ${_monthName(DateTime.now().month)}',
      );
      _columns = [
        _EditableColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
          deletable: false,
        ),
        _EditableColumn(name: 'Item Code', type: SessionColumnType.scan),
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canAddColumn => _columns.length < ScanSession.maxColumns;

  IconData _iconFor(SessionColumnType t) => switch (t) {
        SessionColumnType.scan => Icons.qr_code_scanner_rounded,
        SessionColumnType.manual => Icons.edit_rounded,
        SessionColumnType.timestamp => Icons.schedule_rounded,
        SessionColumnType.increment => Icons.tag_rounded,
        SessionColumnType.fixed => Icons.push_pin_rounded,
      };

  String _labelFor(SessionColumnType t) => switch (t) {
        SessionColumnType.scan => 'Scan',
        SessionColumnType.manual => 'Manual',
        SessionColumnType.timestamp => 'Timestamp',
        SessionColumnType.increment => 'Increment',
        SessionColumnType.fixed => 'Fixed',
      };

  Color _colorFor(SessionColumnType t) => switch (t) {
        SessionColumnType.scan => const Color(0xFF34A853),
        SessionColumnType.manual => const Color(0xFF9333EA),
        SessionColumnType.timestamp => const Color(0xFF16A34A),
        SessionColumnType.increment => const Color(0xFFF59E0B),
        SessionColumnType.fixed => const Color(0xFF64748B),
      };

  void _startSession() async {
    HapticFeedback.mediumImpact();
    final name = _nameController.text.trim();
    final navigator = Navigator.of(context);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sheet name cannot be empty.')),
      );
      return;
    }
    if (_columns.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least one column.')));
      return;
    }
    if (!_columns.any((c) => c.type == SessionColumnType.scan)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one scan column.')),
      );
      return;
    }

    final destinationEnum = switch (_destination) {
      'sheets' => SessionDestination.googleSheets,
      'xlsx' => SessionDestination.localXlsx,
      _ => SessionDestination.localCsv,
    };

    String? spreadsheetId;
    String? sheetName;

    if (destinationEnum == SessionDestination.googleSheets) {
      final dest = await navigator.push<SheetDestination>(
        MaterialPageRoute(builder: (_) => const ConnectSheetsScreen()),
      );
      if (dest == null) return; // User canceled
      spreadsheetId = dest.spreadsheetId;
      sheetName = dest.sheetName;
    }

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final session = ScanSession(
      id: sessionId,
      name: name,
      columns: _columns
          .map(
            (c) => SessionColumn(
              name: c.name,
              type: c.type,
              fixedValue: c.fixedValue,
            ),
          )
          .toList(),
      createdAt: DateTime.now(),
      isActive: true,
      warnDuplicates: _warnDuplicates,
      destination: destinationEnum,
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
    );

    ScanSessionService.saveSession(session).then((_) {
      if (!mounted) return;
      navigator.pop(); // close sheet
      navigator
          .push(FadeSlideRoute(page: ScanSessionScreen(session: session)))
          .then((_) => widget.onSessionEnded?.call());
    });
  }

  void _addColumn() {
    HapticFeedback.selectionClick();
    if (!_canAddColumn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum ${ScanSession.maxColumns} columns allowed.'),
        ),
      );
      return;
    }
    _showAddColumnDialog();
  }

  void _showAddColumnDialog({_EditableColumn? existing, int? editIndex}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final fixedCtrl = TextEditingController(text: existing?.fixedValue ?? '');
    SessionColumnType selectedType = existing?.type ?? SessionColumnType.scan;

    final types = [
      SessionColumnType.scan,
      SessionColumnType.manual,
      SessionColumnType.timestamp,
      SessionColumnType.increment,
      SessionColumnType.fixed,
    ];

    final descriptions = {
      SessionColumnType.scan: 'Camera scans into this cell',
      SessionColumnType.manual: 'Type a value — optional per row',
      SessionColumnType.timestamp: 'Auto-filled with current time',
      SessionColumnType.increment: 'Auto-numbered: 1, 2, 3…',
      SessionColumnType.fixed: 'Same value for every row',
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.themeCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            editIndex != null ? 'Edit Column' : 'Add Column',
            style: TextStyle(
              color: context.themeTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Column name',
                    labelStyle: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text(
                  'TYPE',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                ...types.map((t) {
                  final selected = selectedType == t;
                  final color = _colorFor(t);
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.08)
                            : context.themeSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? color : context.themeBorder,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(_iconFor(t), size: 18, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _labelFor(t),
                                  style: TextStyle(
                                    color: context.themeTextPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  descriptions[t]!,
                                  style: TextStyle(
                                    color: context.themeTextSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: color,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if (selectedType == SessionColumnType.fixed) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: fixedCtrl,
                    decoration: InputDecoration(
                      labelText: 'Fixed value',
                      labelStyle: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.themeTextSecondary),
              ),
            ),
            FilledButton(
              onPressed: () {
                final colName = nameCtrl.text.trim();
                if (colName.isEmpty) return;
                final col = _EditableColumn(
                  name: colName,
                  type: selectedType,
                  fixedValue: selectedType == SessionColumnType.fixed
                      ? fixedCtrl.text.trim()
                      : null,
                );
                Navigator.pop(ctx);
                setState(() {
                  if (editIndex != null) {
                    _columns[editIndex] = col;
                  } else {
                    _columns.add(col);
                  }
                });
              },
              child: Text(editIndex != null ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.themeCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themeBorder,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.table_chart_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.initialTemplate != null
                                    ? widget.initialTemplate!.name
                                    : 'New Sheet',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.initialTemplate != null
                                    ? 'Customise then start scanning'
                                    : 'Scan barcodes → collect rows → export to excel',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _StepHeader(
                    number: '1',
                    title: 'Sheet Name',
                    context: context,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Warehouse Audit',
                      hintStyle: TextStyle(
                        color: context.themeTextSecondary
                            .withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.label_outline_rounded,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: context.themeSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.themeBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.themeBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _StepHeader(
                    number: '2',
                    title: 'Destination',
                    context: context,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DestinationCard(
                          icon: Icons.table_chart_rounded,
                          title: 'Google Sheets',
                          isSelected: _destination == 'sheets',
                          onTap: () => setState(() => _destination = 'sheets'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DestinationCard(
                          icon: Icons.insert_drive_file_rounded,
                          title: 'CSV File',
                          isSelected: _destination == 'csv',
                          onTap: () => setState(() => _destination = 'csv'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DestinationCard(
                          icon: Icons.grid_on_rounded,
                          title: 'Excel (XLSX)',
                          isSelected: _destination == 'xlsx',
                          onTap: () => setState(() => _destination = 'xlsx'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _StepHeader(
                          number: '3',
                          title: 'Columns',
                          context: context,
                        ),
                      ),
                      Text(
                        '${_columns.length}/${ScanSession.maxColumns}',
                        style: TextStyle(
                          color: context.themeTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._columns.asMap().entries.map((e) {
                        final i = e.key;
                        final col = e.value;
                        return _ColumnChip(
                          column: col,
                          color: _colorFor(col.type),
                          icon: _iconFor(col.type),
                          onDelete: col.deletable ? () => setState(() => _columns.removeAt(i)) : null,
                          onTap: () => _showAddColumnDialog(existing: col, editIndex: i),
                        );
                      }),
                      if (_canAddColumn)
                        InkWell(
                          onTap: _addColumn,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: context.themeTextSecondary.withValues(alpha: 0.3),
                                style: BorderStyle.solid,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 16,
                                  color: context.themeTextSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Add Custom',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _StepHeader(
                    number: '4',
                    title: 'Table Preview',
                    context: context,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.themeSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.themeBorder),
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _columns.length,
                      separatorBuilder: (ctx, i) => Container(
                        width: 1,
                        color: context.themeBorder,
                      ),
                      itemBuilder: (ctx, i) {
                        return Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          constraints: const BoxConstraints(minWidth: 80),
                          child: Text(
                            _columns[i].name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.themeTextPrimary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  _StepHeader(
                      number: '5', title: 'Options', context: context),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.themeSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.themeBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Warn on duplicates',
                                style: TextStyle(
                                  color: context.themeTextPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Prompt to skip or keep duplicate scans',
                                style: TextStyle(
                                  color: context.themeTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _warnDuplicates,
                          onChanged: (v) =>
                              setState(() => _warnDuplicates = v),
                          activeThumbColor: context.themeAccent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startSession,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(
                      'Start Scanning',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final String number;
  final String title;
  final BuildContext context;

  const _StepHeader({
    required this.number,
    required this.title,
    required this.context,
  });

  @override
  Widget build(BuildContext _) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: context.themeAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: context.themeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EditableColumn {
  String name;
  SessionColumnType type;
  String? fixedValue;
  final bool deletable;

  _EditableColumn({
    required this.name,
    required this.type,
    this.fixedValue,
    this.deletable = true,
  });
}

class _DestinationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DestinationCard({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.themeAccent.withValues(alpha: 0.1) : context.themeSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.themeAccent : context.themeBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? context.themeAccent : context.themeTextSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? context.themeAccent : context.themeTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnChip extends StatelessWidget {
  final _EditableColumn column;
  final Color color;
  final IconData icon;
  final VoidCallback? onDelete;
  final VoidCallback onTap;

  const _ColumnChip({
    required this.column,
    required this.color,
    required this.icon,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              column.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.close_rounded, size: 14, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
