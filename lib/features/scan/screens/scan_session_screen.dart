import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/services/scan_session_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/scan_session.dart';
import '../widgets/session_export_sheet.dart';
import '../widgets/scanner_overlay_widget.dart';
import '../../history/screens/entry_detail_screen.dart';

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
  int _activeManualColumnIndex =
      0; // index into manualColumnIndices while prompting
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

  // ───────────────────────────────────────────────────────────────────────────
  // Scan flow
  // ───────────────────────────────────────────────────────────────────────────

  void _resetPendingRow() {
    _activeScanColumnIndex = 0;
    _activeManualColumnIndex = 0;
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
      // All scan columns filled — check for manual columns before committing.
      setState(() {
        _pendingRow = updatedRow;
        _isProcessing = false;
      });
      _promptManualColumnsOrCommit(updatedRow);
    } else {
      // Advance to next scan column.
      setState(() {
        _pendingRow = updatedRow;
        _activeScanColumnIndex++;
        _isProcessing = false;
      });
    }
  }

  /// After all scan columns are filled, prompt for each manual column in order.
  void _promptManualColumnsOrCommit(SessionRow row) {
    final manualIndices = _session.manualColumnIndices;
    if (manualIndices.isEmpty) {
      _commitRow(row);
      return;
    }
    _activeManualColumnIndex = 0;
    _showManualInputDialog(row, manualIndices);
  }

  void _showManualInputDialog(SessionRow row, List<int> manualIndices) {
    if (_activeManualColumnIndex >= manualIndices.length) {
      _commitRow(row);
      return;
    }

    final colIndex = manualIndices[_activeManualColumnIndex];
    final colName = _session.columns[colIndex].name;
    final isLast = _activeManualColumnIndex == manualIndices.length - 1;
    final ctrl = TextEditingController(
      text: row.values.length > colIndex ? row.values[colIndex] : '',
    );

    _cameraController.stop();

    showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF9333EA).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.edit_rounded,
            color: Color(0xFF9333EA),
            size: 20,
          ),
        ),
        title: Text(
          colName,
          style: TextStyle(
            color: ctx.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manualIndices.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Field ${_activeManualColumnIndex + 1} of ${manualIndices.length}',
                  style: TextStyle(
                    color: ctx.themeTextSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Enter $colName...',
                hintStyle: TextStyle(color: ctx.themeTextSecondary),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(
              'Skip',
              style: TextStyle(
                color: ctx.themeTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(isLast ? 'Save Row' : 'Next'),
          ),
        ],
      ),
    ).then((typed) {
      // Delay disposal to allow the dialog's pop animation to finish, 
      // preventing the TextField from crashing when accessing a disposed controller.
      Future.delayed(const Duration(milliseconds: 400), () {
        ctrl.dispose();
      });

      if (!mounted) return;

      final updatedValues = List<String>.from(row.values);
      if (updatedValues.length > colIndex) {
        updatedValues[colIndex] = typed ?? '';
      }
      final updatedRow = row.copyWith(values: updatedValues);
      _activeManualColumnIndex++;

      if (_activeManualColumnIndex >= manualIndices.length) {
        _cameraController.start();
        _commitRow(updatedRow);
      } else {
        _showManualInputDialog(updatedRow, manualIndices);
      }
    });
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
        backgroundColor: ctx.themeCard,
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
            color: ctx.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '"$value" already exists in this session.',
              style: TextStyle(color: ctx.themeTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ctx.themeSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ctx.themeBorder),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: ctx.themeTextPrimary,
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
                color: ctx.themeTextSecondary,
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
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Session Columns',
          style: TextStyle(
            color: ctx.themeTextPrimary,
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
                    color: ctx.themeTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _labelFor(col.type),
                  style: TextStyle(
                    color: ctx.themeTextSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: ctx.themeTextSecondary,
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
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Column',
          style: TextStyle(
            color: ctx.themeTextPrimary,
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
            hintStyle: TextStyle(color: ctx.themeTextSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: ctx.themeTextSecondary),
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
    SessionColumnType.location => Icons.location_on_rounded,
  };

  String _labelFor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => 'Scan',
    SessionColumnType.manual => 'Manual',
    SessionColumnType.timestamp => 'Timestamp',
    SessionColumnType.increment => 'Increment',
    SessionColumnType.fixed => 'Fixed',
    SessionColumnType.location => 'Location',
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
          backgroundColor: ctx.themeCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Edit Row ${row.rowIndex + 1}',
            style: TextStyle(
              color: ctx.themeTextPrimary,
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
                style: TextStyle(color: ctx.themeTextSecondary),
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

  // ───────────────────────────────────────────────────────────────────────────
  // Full rows viewer
  // ───────────────────────────────────────────────────────────────────────────

  void _showAllRows() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.themeBg,
          appBar: AppBar(
            backgroundColor: ctx.themeCard,
            elevation: 0,
            scrolledUnderElevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: ctx.themeTextPrimary),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: Text(
              'All Rows (${_rows.length})',
              style: TextStyle(
                color: ctx.themeTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.file_download_rounded, color: ctx.themeAccent),
                tooltip: 'Export',
                onPressed: _openExport,
              ),
            ],
          ),
          body: _rows.isEmpty
              ? Center(
                  child: Text(
                    'No rows yet.',
                    style: TextStyle(color: ctx.themeTextSecondary),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(ctx.themeCard),
                      columns: [
                        const DataColumn(label: Text('#')),
                        for (final col in _session.columns)
                          DataColumn(label: Text(col.name)),
                      ],
                      rows: [
                        for (final row in _rows)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${row.rowIndex + 1}',
                                  style: TextStyle(
                                    color: ctx.themeTextSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () async {
                                  final deleted = await Navigator.push<bool>(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) => EntryDetailScreen(
                                        session: _session,
                                        row: row,
                                      ),
                                    ),
                                  );
                                  if (deleted == true && ctx.mounted) {
                                    Navigator.pop(ctx);
                                    _showAllRows();
                                  }
                                },
                              ),
                              for (int i = 0; i < _session.columns.length; i++)
                                DataCell(
                                  Text(
                                    i < row.values.length ? row.values[i] : '',
                                    style: TextStyle(
                                      color: ctx.themeTextPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () async {
                                    final deleted = await Navigator.push<bool>(
                                      ctx,
                                      MaterialPageRoute(
                                        builder: (_) => EntryDetailScreen(
                                          session: _session,
                                          row: row,
                                        ),
                                      ),
                                    );
                                    if (deleted == true && ctx.mounted) {
                                      Navigator.pop(ctx);
                                      _showAllRows();
                                    }
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
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
          'All scanned rows in this session will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.themeError),
            onPressed: () {
              Navigator.pop(ctx);
              ScanSessionService.clearRows(_session.id).then((_) {
                if (!mounted) return;
                setState(() {
                  _rows = [];
                  _resetPendingRow();
                });
              });
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  String get _activeColumnName {
    final scanIndices = _session.scanColumnIndices;
    if (scanIndices.isEmpty) return '';
    if (_activeScanColumnIndex >= scanIndices.length) return '';
    return _session.columns[scanIndices[_activeScanColumnIndex]].name;
  }

  Color _typeColor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => const Color(0xFF22C55E),
    SessionColumnType.manual => const Color(0xFF9333EA),
    SessionColumnType.timestamp => const Color(0xFF3B82F6),
    SessionColumnType.increment => const Color(0xFFF59E0B),
    SessionColumnType.fixed => const Color(0xFF6B7280),
    SessionColumnType.location => const Color(0xFFEF4444),
  };

  Widget _buildScannerToggleButton() {
    final color = _isScannerPaused
        ? const Color(0xFFF59E0B)
        : const Color(0xFF22C55E);
    final icon = _isScannerPaused
        ? Icons.play_arrow_rounded
        : Icons.pause_rounded;
    final label = _isScannerPaused ? 'Paused' : 'Scanning';

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
                  ScannerOverlayWidget(
                    detectionState: _isProcessing
                        ? ScannerDetectionState.detected
                        : ScannerDetectionState.idle,
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
                    // Header row
                    Container(
                      decoration: BoxDecoration(
                        color: context.themeCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.themeBorder),
                      ),
                      child: Column(
                        children: [
                          // Column headers
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '#',
                                    style: TextStyle(
                                      color: context.themeTextSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                for (final col in _session.columns)
                                  Expanded(
                                    child: Text(
                                      col.name,
                                      style: TextStyle(
                                        color: context.themeTextSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: context.themeBorder),
                          // Last 5 rows
                          for (
                            int i = (_rows.length - 1);
                            i >= 0 && i >= _rows.length - 5;
                            i--
                          ) ...[
                            InkWell(
                              onTap: () => _showEditRowDialog(_rows[i]),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '${_rows[i].rowIndex + 1}',
                                        style: TextStyle(
                                          color: context.themeTextSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    for (
                                      int j = 0;
                                      j < _session.columns.length;
                                      j++
                                    )
                                      Expanded(
                                        child: Text(
                                          j < _rows[i].values.length
                                              ? _rows[i].values[j]
                                              : '',
                                          style: TextStyle(
                                            color: context.themeTextPrimary,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (i > (_rows.length - 5) && i > 0)
                              Divider(
                                height: 1,
                                indent: 12,
                                endIndent: 12,
                                color: context.themeBorder,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // View all + export row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showAllRows,
                            icon: const Icon(
                              Icons.table_rows_rounded,
                              size: 16,
                            ),
                            label: Text('View All (${_rows.length})'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.themeTextSecondary,
                              side: BorderSide(color: context.themeBorder),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openExport,
                            icon: const Icon(
                              Icons.file_download_rounded,
                              size: 16,
                            ),
                            label: const Text('Export'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ───────────────────────────────────────────────────────────────────────────

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
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.12) : context.themeCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.4) : context.themeBorder,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isActive
                  ? color
                  : context.themeTextSecondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: TextStyle(
                  color: isActive ? Colors.white : context.themeTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
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
