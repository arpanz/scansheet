import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/services/scan_session_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/scan_session.dart';
import '../widgets/session_export_sheet.dart';

/// Full-screen session scanning experience.
/// Camera + column indicator + mini table + undo.
class ScanSessionScreen extends StatefulWidget {
  final ScanSession session;

  const ScanSessionScreen({super.key, required this.session});

  @override
  State<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends State<ScanSessionScreen> {
  late ScanSession _session;
  late MobileScannerController _cameraController;

  List<SessionRow> _rows = [];
  int _activeScanColumnIndex = 0; // index into _session.scanColumnIndices
  SessionRow? _pendingRow; // row being built for the current scan cycle

  bool _isProcessing = false;
  bool _isScannerPaused = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _cameraController = MobileScannerController();
    WakelockPlus.enable();
    _rows = ScanSessionService.getRows(_session.id);
    _resetPendingRow();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scan flow
  // ─────────────────────────────────────────────────────────────────────────

  void _resetPendingRow() {
    _activeScanColumnIndex = 0;
    _pendingRow = _session.buildEmptyRow(_rows.length);
  }

  /// Called when a barcode is detected by MobileScanner.
  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final value = barcode.rawValue!.trim();
    if (value.isEmpty) return;

    _handleScannedValue(value);
  }

  void _handleScannedValue(String value) {
    if (_isProcessing) return;
    _isProcessing = true;

    final scanIndices = _session.scanColumnIndices;
    if (scanIndices.isEmpty) {
      _isProcessing = false;
      return;
    }

    // Which column (in the full columns list) is active?
    final colIndex = scanIndices[_activeScanColumnIndex];

    // Duplicate check — pause and prompt
    if (_session.warnDuplicates &&
        ScanSessionService.isDuplicate(_session.id, colIndex, value)) {
      _cameraController.stop();
      _showDuplicateDialog(value, colIndex);
      return;
    }

    _applyScannedValue(value, colIndex);
  }

  void _applyScannedValue(String value, int colIndex) {
    final scanIndices = _session.scanColumnIndices;

    // Fill the value
    final updatedValues = List<String>.from(_pendingRow!.values);
    updatedValues[colIndex] = value;
    final updatedRow = _pendingRow!.copyWith(values: updatedValues);

    HapticFeedback.mediumImpact();

    final isLastScanColumn = _activeScanColumnIndex == scanIndices.length - 1;

    if (isLastScanColumn) {
      // All scan columns filled — commit the row.
      _commitRow(updatedRow);
    } else {
      // Advance to next scan column.
      setState(() {
        _pendingRow = updatedRow;
        _activeScanColumnIndex++;
        _isProcessing = false;
      });
    }
  }

  void _commitRow(SessionRow row) {
    ScanSessionService.addRow(_session.id, row).then((_) {
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, row];
        _isProcessing = false;
        _resetPendingRow();
      });
    });
  }

  void _skipColumn() {
    final scanIndices = _session.scanColumnIndices;
    if (scanIndices.isEmpty) return;

    final isLastScanColumn = _activeScanColumnIndex == scanIndices.length - 1;
    HapticFeedback.selectionClick();

    if (isLastScanColumn) {
      // Skip last column → commit row with empty value.
      _commitRow(_pendingRow!);
    } else {
      setState(() {
        _activeScanColumnIndex++;
        _isProcessing = false;
      });
    }
  }

  void _undoLastRow() {
    if (_rows.isEmpty) return;
    HapticFeedback.mediumImpact();
    ScanSessionService.deleteLastRow(_session.id).then((_) {
      if (!mounted) return;
      setState(() {
        _rows = _rows.sublist(0, _rows.length - 1);
        _resetPendingRow();
      });
    });
  }

  Future<void> _toggleScannerPaused() async {
    HapticFeedback.selectionClick();
    if (_isScannerPaused) {
      await _cameraController.start();
      if (!mounted) return;
      setState(() => _isScannerPaused = false);
    } else {
      await _cameraController.stop();
      if (!mounted) return;
      setState(() {
        _isScannerPaused = true;
        _isProcessing = false;
      });
    }
  }

  void _endSession() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Session?'),
        content: Text(
          'This session (${_rows.length} rows) will be saved to History. You can still export it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScanSessionService.endSession(_session.id).then((_) {
                if (mounted) Navigator.pop(context);
              });
            },
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  void _showDuplicateDialog(String value, int colIndex) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.content_copy_rounded,
            color: Color(0xFFF59E0B),
            size: 22,
          ),
        ),
        title: Text(
          'Duplicate Detected',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '"$value" already exists in this session.',
              style: TextStyle(color: context.themeTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.themeSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.themeBorder),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: context.themeTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _isProcessing = false;
              _cameraController.start();
            },
            child: Text(
              'Skip',
              style: TextStyle(
                color: context.themeTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _applyScannedValue(value, colIndex);
              _cameraController.start();
            },
            child: const Text('Keep Anyway'),
          ),
        ],
      ),
    );
  }

  void _showEditColumns() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Session Columns',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _session.columns.length,
            itemBuilder: (_, i) {
              final col = _session.columns[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _typeColor(col.type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(col.type),
                    size: 16,
                    color: _typeColor(col.type),
                  ),
                ),
                title: Text(
                  col.name,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _labelFor(col.type),
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: context.themeTextSecondary,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editColumnName(i);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _editColumnName(int index) {
    final col = _session.columns[index];
    final ctrl = TextEditingController(text: col.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Column',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Column name',
            hintStyle: TextStyle(color: context.themeTextSecondary),
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
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              final dialogNavigator = Navigator.of(ctx);
              final updatedCols = List<SessionColumn>.from(_session.columns);
              updatedCols[index] = updatedCols[index].copyWith(name: newName);
              final updatedSession = _session.copyWith(columns: updatedCols);
              ScanSessionService.saveSession(updatedSession).then((_) {
                if (!mounted) return;
                dialogNavigator.pop();
                setState(() => _session = updatedSession);
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

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

  void _openExport() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionExportSheet(session: _session),
    );
  }

  Future<bool> _showEditRowDialog(SessionRow row) async {
    final controllers = [
      for (int i = 0; i < _session.columns.length; i++)
        TextEditingController(text: i < row.values.length ? row.values[i] : ''),
    ];

    try {
      final updatedRow = await showDialog<SessionRow>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.themeCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Edit Row ${row.rowIndex + 1}',
            style: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < _session.columns.length; i++) ...[
                    TextField(
                      controller: controllers[i],
                      decoration: InputDecoration(
                        labelText: _session.columns[i].name,
                        prefixIcon: Icon(
                          _iconFor(_session.columns[i].type),
                          size: 18,
                          color: _typeColor(_session.columns[i].type),
                        ),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    if (i < _session.columns.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
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
                final values = controllers.map((c) => c.text.trim()).toList();
                Navigator.pop(ctx, row.copyWith(values: values));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (updatedRow == null) return false;
      await ScanSessionService.updateRow(_session.id, updatedRow);
      if (!mounted) return false;
      setState(() {
        final index = _rows.indexWhere((r) => r.rowIndex == row.rowIndex);
        if (index >= 0) {
          _rows[index] = updatedRow;
        }
      });
      HapticFeedback.selectionClick();
      return true;
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full rows viewer
  // ─────────────────────────────────────────────────────────────────────────

  void _showAllRows() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            decoration: BoxDecoration(
              color: context.themeCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Handle + header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Column(
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
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'All Rows',
                            style: TextStyle(
                              color: context.themeTextPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.themeAccent.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_rows.length}',
                              style: TextStyle(
                                color: context.themeAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: context.themeTextSecondary,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Scrollable table
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 38,
                        dataRowMaxHeight: 38,
                        columnSpacing: 16,
                        horizontalMargin: 12,
                        headingTextStyle: TextStyle(
                          color: context.themeTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        dataTextStyle: TextStyle(
                          color: context.themeTextPrimary,
                          fontSize: 12,
                        ),
                        border: TableBorder(
                          horizontalInside: BorderSide(
                            color: context.themeBorder,
                            width: 0.5,
                          ),
                        ),
                        columns: [
                          const DataColumn(label: Text('#')),
                          ..._session.columns.map(
                            (col) => DataColumn(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _typeColor(col.type),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(col.name),
                                ],
                              ),
                            ),
                          ),
                          const DataColumn(label: Text('')),
                        ],
                        rows: _rows
                            .map(
                              (row) => DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      '${row.rowIndex + 1}',
                                      style: TextStyle(
                                        color: context.themeTextSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  ...row.values.map(
                                    (v) => DataCell(
                                      Text(
                                        v.isEmpty ? '—' : v,
                                        style: TextStyle(
                                          color: v.isEmpty
                                              ? context.themeTextSecondary
                                              : context.themeTextPrimary,
                                          fontSize: 12,
                                          fontStyle: v.isEmpty
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 16,
                                      color: context.themeAccent,
                                    ),
                                    onTap: () async {
                                      final changed = await _showEditRowDialog(
                                        row,
                                      );
                                      if (changed) setSheetState(() {});
                                    },
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  String get _activeColumnName {
    final scanIndices = _session.scanColumnIndices;
    if (scanIndices.isEmpty) return '';
    final colIndex = scanIndices[_activeScanColumnIndex];
    return _session.columns[colIndex].name;
  }

  Color _typeColor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => const Color(0xFF34A853),
    SessionColumnType.manual => const Color(0xFF9333EA),
    SessionColumnType.timestamp => const Color(0xFF16A34A),
    SessionColumnType.increment => const Color(0xFFF59E0B),
    SessionColumnType.fixed => const Color(0xFF64748B),
  };

  // Last 5 rows for the mini table (most recent at top).
  List<SessionRow> get _recentRows {
    if (_rows.length <= 5) return _rows.reversed.toList();
    return _rows.sublist(_rows.length - 5).reversed.toList();
  }

  Widget _buildScannerToggleButton() {
    final color = _isScannerPaused
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    final icon = _isScannerPaused
        ? Icons.play_arrow_rounded
        : Icons.pause_rounded;
    final label = _isScannerPaused ? 'Resume' : 'Pause';

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: _isScannerPaused ? 'Resume scanner' : 'Pause scanner',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleScannerPaused,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 36,
              padding: const EdgeInsets.only(left: 8, right: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanIndices = _session.scanColumnIndices;

    return Scaffold(
      backgroundColor: context.themeBg,
      appBar: AppBar(
        title: Text(
          _session.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          _buildScannerToggleButton(),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'end') _endSession();
              if (v == 'clear') _showClearConfirm();
              if (v == 'edit_cols') _showEditColumns();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit_cols', child: Text('Edit Columns')),
              PopupMenuItem(value: 'end', child: Text('End Session')),
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  'Clear All Rows',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _cameraController,
                    onDetect: _onDetect,
                  ),
                  // Viewfinder overlay
                  Positioned.fill(
                    child: CustomPaint(painter: _SessionScannerOverlay()),
                  ),
                  // Scanning target indicator
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(
                              0xFF34A853,
                            ).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          _isScannerPaused
                              ? 'Scanner paused'
                              : scanIndices.isEmpty
                              ? 'No scan columns configured'
                              : 'Scanning → $_activeColumnName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column indicator chips
                  if (scanIndices.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < scanIndices.length; i++) ...[
                            _ColumnChip(
                              label: _session.columns[scanIndices[i]].name,
                              isActive: i == _activeScanColumnIndex,
                              stepNumber: i + 1,
                              color: const Color(0xFF34A853),
                            ),
                            if (i < scanIndices.length - 1)
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: Colors.grey,
                              ),
                          ],
                          const SizedBox(width: 8),
                          // Skip button
                          OutlinedButton.icon(
                            onPressed: _skipColumn,
                            icon: const Icon(Icons.skip_next_rounded, size: 16),
                            label: const Text('Skip'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.themeTextSecondary,
                              side: BorderSide(color: context.themeBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Row counter + undo
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: context.themeAccent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_rows.length} ${_rows.length == 1 ? 'row' : 'rows'}',
                          style: TextStyle(
                            color: context.themeAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_rows.isNotEmpty)
                        TextButton.icon(
                          onPressed: _undoLastRow,
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: const Text('Undo Last'),
                          style: TextButton.styleFrom(
                            foregroundColor: context.themeTextSecondary,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Mini table
                  if (_rows.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 40,
                              color: context.themeTextSecondary.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Scan an item to begin collecting rows.',
                              style: TextStyle(
                                color: context.themeTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    _MiniTable(
                      session: _session,
                      rows: _recentRows,
                      typeColorFn: _typeColor,
                    ),
                    GestureDetector(
                      onTap: _showAllRows,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _rows.length > 5
                                  ? 'View all ${_rows.length} rows'
                                  : 'Edit rows',
                              style: TextStyle(
                                color: context.themeAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: context.themeAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      // ── Sticky bottom action bar ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              // Export button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _rows.isEmpty ? null : _openExport,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text('Export (${_rows.length})'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // End session button
              OutlinedButton.icon(
                onPressed: _endSession,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('End'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.themeError,
                  side: BorderSide(
                    color: context.themeError.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Rows?'),
        content: const Text(
          'This will delete all scanned rows from this session. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScanSessionService.clearRows(_session.id).then((_) {
                if (mounted) {
                  setState(() {
                    _rows = [];
                    _resetPendingRow();
                  });
                }
              });
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column step chip
// ─────────────────────────────────────────────────────────────────────────────

class _ColumnChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final int stepNumber;
  final Color color;

  const _ColumnChip({
    required this.label,
    required this.isActive,
    required this.stepNumber,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.15) : context.themeSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? color : context.themeBorder,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                size: 10,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 5),
          ] else ...[
            Text(
              '$stepNumber',
              style: TextStyle(
                color: context.themeTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: isActive ? color : context.themeTextSecondary,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini table widget — shows last N rows
// ─────────────────────────────────────────────────────────────────────────────

class _MiniTable extends StatelessWidget {
  final ScanSession session;
  final List<SessionRow> rows;
  final Color Function(SessionColumnType) typeColorFn;

  const _MiniTable({
    required this.session,
    required this.rows,
    required this.typeColorFn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themeBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 40,
            columnSpacing: 16,
            horizontalMargin: 12,
            headingTextStyle: TextStyle(
              color: context.themeTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            dataTextStyle: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 12,
            ),
            border: TableBorder(
              horizontalInside: BorderSide(
                color: context.themeBorder,
                width: 0.5,
              ),
            ),
            columns: session.columns
                .map(
                  (col) => DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: typeColorFn(col.type),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(col.name),
                      ],
                    ),
                  ),
                )
                .toList(),
            rows: rows
                .map(
                  (row) => DataRow(
                    cells: row.values
                        .map(
                          (v) => DataCell(
                            Text(
                              v.isEmpty ? '—' : v,
                              style: TextStyle(
                                color: v.isEmpty
                                    ? context.themeTextSecondary
                                    : context.themeTextPrimary,
                                fontSize: 12,
                                fontStyle: v.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Viewfinder overlay for session scanner
// ─────────────────────────────────────────────────────────────────────────────

class _SessionScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cutoutSize = size.shortestSide * 0.65;
    final double left = (size.width - cutoutSize) / 2;
    final double top = (size.height - cutoutSize) / 2;
    final cutoutRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
      const Radius.circular(18),
    );

    final bgPaint = Paint()..color = const Color(0x88000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutoutRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    const double bracketLen = 24;
    final bracketPaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double r = 18;
    final double x1 = left, y1 = top;
    final double x2 = left + cutoutSize, y2 = top + cutoutSize;

    canvas.drawPath(
      Path()
        ..moveTo(x1, y1 + bracketLen)
        ..lineTo(x1, y1 + r)
        ..quadraticBezierTo(x1, y1, x1 + r, y1)
        ..lineTo(x1 + bracketLen, y1),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x2 - bracketLen, y1)
        ..lineTo(x2 - r, y1)
        ..quadraticBezierTo(x2, y1, x2, y1 + r)
        ..lineTo(x2, y1 + bracketLen),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x1, y2 - bracketLen)
        ..lineTo(x1, y2 - r)
        ..quadraticBezierTo(x1, y2, x1 + r, y2)
        ..lineTo(x1 + bracketLen, y2),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x2 - bracketLen, y2)
        ..lineTo(x2 - r, y2)
        ..quadraticBezierTo(x2, y2, x2, y2 - r)
        ..lineTo(x2, y2 - bracketLen),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
