import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/template_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/screens/connect_sheets_screen.dart';
import '../models/scan_session.dart';
import 'scan_session_screen.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/services/scan_session_service.dart';

// ── Icon picker data ──────────────────────────────────────────────────────────

class _IconOption {
  final String key;
  final IconData icon;
  final Color color;
  const _IconOption(this.key, this.icon, this.color);
}

const List<_IconOption> kSessionIcons = [
  _IconOption('inventory',      Icons.inventory_2_rounded,          Color(0xFF3B82F6)),
  _IconOption('store',          Icons.storefront_rounded,            Color(0xFF10B981)),
  _IconOption('warehouse',      Icons.warehouse_rounded,             Color(0xFFF59E0B)),
  _IconOption('people',         Icons.people_rounded,                Color(0xFF8B5CF6)),
  _IconOption('local_shipping', Icons.local_shipping_rounded,        Color(0xFFEF4444)),
  _IconOption('receipt',        Icons.receipt_long_rounded,          Color(0xFF06B6D4)),
  _IconOption('devices',        Icons.devices_rounded,               Color(0xFF6366F1)),
  _IconOption('sell',           Icons.sell_rounded,                  Color(0xFFEC4899)),
  _IconOption('fact_check',     Icons.fact_check_rounded,            Color(0xFF14B8A6)),
  _IconOption('science',        Icons.science_rounded,               Color(0xFFF97316)),
  _IconOption('local_hospital', Icons.local_hospital_rounded,        Color(0xFFDC2626)),
  _IconOption('construction',   Icons.construction_rounded,          Color(0xFF92400E)),
];

IconData sessionIconData(String? key) {
  if (key == null) return Icons.grid_view_rounded;
  return kSessionIcons
      .firstWhere((o) => o.key == key,
          orElse: () => const _IconOption(
              'grid', Icons.grid_view_rounded, Color(0xFF6B7280)))
      .icon;
}

Color sessionIconColor(String? key) {
  if (key == null) return const Color(0xFF6B7280);
  return kSessionIcons
      .firstWhere((o) => o.key == key,
          orElse: () => const _IconOption(
              'grid', Icons.grid_view_rounded, Color(0xFF6B7280)))
      .color;
}

/// Full-page screen that lets the user configure a new Scan Session.
/// Optionally seeded from a [SessionTemplate].
class SessionSetupScreen extends StatefulWidget {
  /// When non-null, the screen pre-fills name + columns from this template.
  final SessionTemplate? initialTemplate;

  /// Called when the user returns from [ScanSessionScreen] back to the caller.
  final VoidCallback? onSessionEnded;

  const SessionSetupScreen({
    super.key,
    this.initialTemplate,
    this.onSessionEnded,
  });

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  late final TextEditingController _nameController;
  bool _warnDuplicates = false;
  bool _showScanConfirmation = false;
  late final List<_EditableColumn> _columns;
  String _destination = 'csv'; // 'csv', 'xlsx', 'sheets'
  String? _selectedIconKey; // null = no custom icon chosen

  static String _monthName(int m) => const [
    '',
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];

  @override
  void initState() {
    super.initState();
    final tmpl = widget.initialTemplate;
    if (tmpl != null) {
      _nameController = TextEditingController(text: tmpl.name);
      // Pre-select the template's icon if it matches one of our picker options
      if (kSessionIcons.any((o) => o.key == tmpl.icon)) {
        _selectedIconKey = tmpl.icon;
      }
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
        text: 'Sheet ${DateTime.now().day} ${_monthName(DateTime.now().month)}',
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

  IconData _colIconFor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => Icons.qr_code_scanner_rounded,
    SessionColumnType.manual => Icons.edit_rounded,
    SessionColumnType.timestamp => Icons.schedule_rounded,
    SessionColumnType.increment => Icons.tag_rounded,
    SessionColumnType.fixed => Icons.push_pin_rounded,
    SessionColumnType.location => Icons.location_on_rounded,
  };

  String _labelFor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => 'Scan',
    SessionColumnType.manual => 'Manual Input',
    SessionColumnType.timestamp => 'Timestamp',
    SessionColumnType.increment => 'Increment',
    SessionColumnType.fixed => 'Fixed Value',
    SessionColumnType.location => 'Location',
  };

  Color _colorFor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => const Color(0xFF34A853),
    SessionColumnType.manual => const Color(0xFF9333EA),
    SessionColumnType.timestamp => const Color(0xFF16A34A),
    SessionColumnType.increment => const Color(0xFFF59E0B),
    SessionColumnType.fixed => const Color(0xFF64748B),
    SessionColumnType.location => const Color(0xFF3B82F6),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one column.')));
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
      if (dest == null) return;
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
              defaultValue: c.defaultValue,
              isNumeric: c.isNumeric,
              stepSize: c.stepSize,
            ),
          )
          .toList(),
      createdAt: DateTime.now(),
      isActive: true,
      warnDuplicates: _warnDuplicates,
      showScanConfirmation: _showScanConfirmation,
      destination: destinationEnum,
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      iconName: _selectedIconKey,
    );

    ScanSessionService.saveSession(session).then((_) {
      if (!mounted) return;
      navigator.pop();
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
    final defaultValueCtrl = TextEditingController(
      text: editIndex != null ? _columns[editIndex].defaultValue ?? '' : '',
    );
    final stepSizeCtrl = TextEditingController(
      text: editIndex != null ? '${_columns[editIndex].stepSize}' : '1',
    );
    final isNumericNotifier = ValueNotifier<bool>(
      editIndex != null ? _columns[editIndex].isNumeric : false,
    );
    SessionColumnType selectedType = existing?.type ?? SessionColumnType.scan;

    final types = [
      SessionColumnType.scan,
      SessionColumnType.manual,
      SessionColumnType.timestamp,
      SessionColumnType.increment,
      SessionColumnType.fixed,
      SessionColumnType.location,
    ];

    final descriptions = {
      SessionColumnType.scan: 'Camera scans into this cell',
      SessionColumnType.manual: 'Type a value — optional per row',
      SessionColumnType.timestamp: 'Auto-filled with current time',
      SessionColumnType.increment: 'Auto-numbered: 1, 2, 3…',
      SessionColumnType.fixed: 'Same value for every row',
      SessionColumnType.location: 'Auto-filled with GPS coordinates',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: context.themeBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.themeBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          editIndex != null ? 'Edit Column' : 'Add Column',
                          style: TextStyle(
                            color: context.themeTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: context.themeTextPrimary,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
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
                                filled: true,
                                fillColor: context.themeSurface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: context.themeBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: context.themeBorder,
                                  ),
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
                                onTap: () =>
                                    setSheetState(() => selectedType = t),
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
                                      color: selected
                                          ? color
                                          : context.themeBorder,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_colIconFor(t),
                                          size: 18, color: color),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                color:
                                                    context.themeTextSecondary,
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
                                  filled: true,
                                  fillColor: context.themeSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: context.themeBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: context.themeBorder,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (selectedType == SessionColumnType.manual) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: defaultValueCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Default value (optional)',
                                  hintText: 'Pre-fills on every scan',
                                  labelStyle: TextStyle(
                                    color: context.themeTextSecondary,
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: context.themeSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: context.themeBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: context.themeBorder,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              StatefulBuilder(
                                builder: (ctx, setSt) => Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Numeric stepper',
                                            style: TextStyle(
                                              color: ctx.themeTextPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            'Shows – N + instead of keyboard',
                                            style: TextStyle(
                                              color: ctx.themeTextSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: isNumericNotifier.value,
                                      onChanged: (v) {
                                        isNumericNotifier.value = v;
                                        setSt(() {});
                                      },
                                      activeThumbColor: ctx.themeAccent,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ),
                              if (isNumericNotifier.value) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: stepSizeCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Step size',
                                    hintText: '1',
                                    labelStyle: TextStyle(
                                      color: context.themeTextSecondary,
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: context.themeSurface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: context.themeBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: context.themeBorder,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  final colName = nameCtrl.text.trim();
                                  if (colName.isEmpty) return;
                                  final col = _EditableColumn(
                                    name: colName,
                                    type: selectedType,
                                    fixedValue:
                                        selectedType == SessionColumnType.fixed
                                        ? fixedCtrl.text.trim()
                                        : null,
                                    defaultValue:
                                        selectedType == SessionColumnType.manual
                                        ? defaultValueCtrl.text.trim().isEmpty
                                              ? null
                                              : defaultValueCtrl.text.trim()
                                        : null,
                                    isNumeric:
                                        selectedType == SessionColumnType.manual
                                        ? isNumericNotifier.value
                                        : false,
                                    stepSize:
                                        selectedType ==
                                                SessionColumnType.manual &&
                                            isNumericNotifier.value
                                        ? int.tryParse(
                                                stepSizeCtrl.text.trim(),
                                              ) ??
                                              1
                                        : 1,
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
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  editIndex != null
                                      ? 'Save Changes'
                                      : 'Add Column',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeBg,
      appBar: AppBar(
        backgroundColor: context.themeBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.initialTemplate != null ? 'Setup Session' : 'New Session',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.themeTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                children: [
                  // 1. Details Card
                  _buildSectionCard(
                    title: '1. Sheet Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'e.g. Warehouse Audit',
                            hintStyle: TextStyle(
                              color: context.themeTextSecondary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            prefixIcon: const Icon(
                              Icons.label_outline_rounded,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: context.themeSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: context.themeBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: context.themeBorder,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Icon picker
                        Text(
                          'ICON  (optional)',
                          style: TextStyle(
                            color: context.themeTextSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _IconPickerRow(
                          selectedKey: _selectedIconKey,
                          onSelected: (key) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              // Tapping the already-selected icon deselects it
                              _selectedIconKey =
                                  _selectedIconKey == key ? null : key;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Destination
                  _buildSectionCard(
                    title: '2. Destination',
                    child: Row(
                      children: [
                        Expanded(
                          child: _DestinationCard(
                            icon: Icons.table_chart_rounded,
                            customIcon: SvgPicture.asset(
                                'assets/sheets.svg',
                                width: 24,
                                height: 24),
                            title: 'Google Sheets',
                            isSelected: _destination == 'sheets',
                            onTap: () =>
                                setState(() => _destination = 'sheets'),
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
                  ),
                  const SizedBox(height: 20),

                  // 3. Columns List
                  _buildSectionCard(
                    title: '3. Data Columns',
                    trailing: Text(
                      '${_columns.length}/${ScanSession.maxColumns}',
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: context.themeBorder),
                            borderRadius: BorderRadius.circular(12),
                            color: context.themeSurface,
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _columns.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (oldIndex < newIndex) newIndex -= 1;
                                final item = _columns.removeAt(oldIndex);
                                _columns.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final col = _columns[index];
                              final color = _colorFor(col.type);
                              final isLast = index == _columns.length - 1;
                              return Material(
                                key: ValueKey(index),
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _showAddColumnDialog(
                                    existing: col,
                                    editIndex: index,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: isLast
                                          ? null
                                          : Border(
                                              bottom: BorderSide(
                                                color: context.themeBorder,
                                                width: 0.5,
                                              ),
                                            ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                                left: 4,
                                              ),
                                              child: Icon(
                                                Icons.drag_handle_rounded,
                                                color: context.themeTextSecondary
                                                    .withValues(alpha: 0.5),
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              _colIconFor(col.type),
                                              size: 16,
                                              color: color,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  col.name,
                                                  style: TextStyle(
                                                    color: context
                                                        .themeTextPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  col.type ==
                                                          SessionColumnType
                                                              .fixed
                                                      ? '${_labelFor(col.type)}: ${col.fixedValue}'
                                                      : _labelFor(col.type),
                                                  style: TextStyle(
                                                    color: context
                                                        .themeTextSecondary,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (col.deletable)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                              ),
                                              color: context.themeTextSecondary,
                                              onPressed: () {
                                                setState(
                                                  () => _columns
                                                      .removeAt(index),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_canAddColumn) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _addColumn,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Column'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.themeTextPrimary,
                              side: BorderSide(color: context.themeBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Advanced Options
                  _buildSectionCard(
                    title: '4. Advanced Options',
                    child: Column(
                      children: [
                        _switchRow(
                          title: 'Warn on duplicates',
                          sub: 'Prompt to skip or keep duplicate scans',
                          value: _warnDuplicates,
                          onChanged: (v) =>
                              setState(() => _warnDuplicates = v),
                        ),
                        const SizedBox(height: 8),
                        _switchRow(
                          title: 'Scan confirmation panel',
                          sub: 'Review decoded value and fill fields after each scan',
                          value: _showScanConfirmation,
                          onChanged: (v) =>
                              setState(() => _showScanConfirmation = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                color: context.themeCard,
                border:
                    Border(top: BorderSide(color: context.themeBorder)),
              ),
              child: SafeArea(
                top: false,
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

  Widget _switchRow({
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  title,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.themeAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Icon Picker Row ───────────────────────────────────────────────────────────

class _IconPickerRow extends StatelessWidget {
  final String? selectedKey;
  final ValueChanged<String> onSelected;

  const _IconPickerRow({
    required this.selectedKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kSessionIcons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final opt = kSessionIcons[index];
          final isSelected = selectedKey == opt.key;
          return GestureDetector(
            onTap: () => onSelected(opt.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? opt.color.withValues(alpha: 0.15)
                    : context.themeSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? opt.color : context.themeBorder,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Icon(
                opt.icon,
                size: 24,
                color: isSelected ? opt.color : context.themeTextSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Editable column model ─────────────────────────────────────────────────────

class _EditableColumn {
  String name;
  SessionColumnType type;
  String? fixedValue;
  String? defaultValue;
  bool isNumeric;
  int stepSize;
  final bool deletable;

  _EditableColumn({
    required this.name,
    required this.type,
    this.fixedValue,
    this.defaultValue,
    this.isNumeric = false,
    this.stepSize = 1,
    this.deletable = true,
  });
}

// ── Destination card ──────────────────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DestinationCard({
    required this.icon,
    this.customIcon,
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
          color: isSelected
              ? context.themeAccent.withValues(alpha: 0.1)
              : context.themeSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.themeAccent : context.themeBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            customIcon ??
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? context.themeAccent
                      : context.themeTextSecondary,
                ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? context.themeAccent
                    : context.themeTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
