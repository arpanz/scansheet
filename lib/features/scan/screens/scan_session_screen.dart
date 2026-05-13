// ignore_for_file: use_build_context_synchronously

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/scanner_overlay_widget.dart';
import '../../history/screens/entry_detail_screen.dart';
import '../models/scan_session.dart';
import '../screens/export_screen.dart';

class ScanSessionScreen extends StatefulWidget {
  final ScanSession session;

  const ScanSessionScreen({super.key, required this.session});

  @override
  State<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends State<ScanSessionScreen> {
  late MobileScannerController _cameraController;
  late ScanSession _session;
  List<SessionRow> _rows = [];

  int _activeScanColumnIndex = 0;
  int _activeManualColumnIndex =
      0; // index into manualColumnIndices while prompting

  bool _isProcessing = false;
  bool _isScannerPaused = false;
  SessionRow? _pendingRow;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController();
    _session = widget.session;
    _loadRows();
    // Pre-warm location if session has location columns
    if (_session.columns.any(
      (c) => c.type == SessionColumnType.location,
    )) {
      LocationService.instance.warmUp();
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _resetPendingRow() {
    _activeScanColumnIndex = 0;
    _activeManualColumnIndex = 0;
    _pendingRow = _session.buildEmptyRow(_rows.length);
  }

  /// Called when a barcode is detected by MobileScanner.
  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final value = barcode.rawValue?.trim() ?? '';
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

  void _showScanConfirmationSheet(SessionRow row) {
    if (!mounted) return;
    _cameraController.stop();

    final manualIndices = _session.manualColumnIndices;
    final valueControllers = <int, TextEditingController>{};
    final numericValues = <int, int>{};

    for (final colIndex in manualIndices) {
      final col = _session.columns[colIndex];
      final existing = row.values.length > colIndex ? row.values[colIndex] : '';
      final initial = existing.isNotEmpty
          ? existing
          : (col.defaultValue ?? (col.isNumeric ? '${col.stepSize}' : ''));
      if (col.isNumeric) {
        numericValues[colIndex] = int.tryParse(initial) ?? col.stepSize;
      } else {
        valueControllers[colIndex] = TextEditingController(text: initial);
      }
    }

    // Find the decoded value to display (last filled scan column)
    final scanIndices = _session.scanColumnIndices;
    final lastScanColIndex = scanIndices.isNotEmpty
        ? scanIndices[(_activeScanColumnIndex - 1).clamp(
            0,
            scanIndices.length - 1,
          )]
        : -1;
    final scannedValue =
        lastScanColIndex >= 0 && row.values.length > lastScanColIndex
            ? row.values[lastScanColIndex]
            : '';
    final scannedColumnName = lastScanColIndex >= 0
        ? _session.columns[lastScanColIndex].name
        : 'Scanned';

    void disposeControllers() {
      for (final c in valueControllers.values) {
        c.dispose();
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: ctx.themeCard,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ctx.themeBorder,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Decoded value display
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: ctx.themeAccent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.qr_code_rounded,
                            color: ctx.themeAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scannedColumnName.toUpperCase(),
                                style: TextStyle(
                                  color: ctx.themeTextSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                scannedValue.isEmpty ? '—' : scannedValue,
                                style: TextStyle(
                                  color: ctx.themeTextPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Row index badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: ctx.themeAccent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${_rows.length + 1}',
                            style: TextStyle(
                              color: ctx.themeAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Manual fields
                    if (manualIndices.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Divider(height: 1, color: ctx.themeBorder),
                      const SizedBox(height: 16),
                      for (int i = 0; i < manualIndices.length; i++) ...[
                        _buildConfirmationField(
                          ctx: ctx,
                          col: _session.columns[manualIndices[i]],
                          colIndex: manualIndices[i],
                          valueControllers: valueControllers,
                          numericValues: numericValues,
                          setSt: setSt,
                        ),
                        if (i < manualIndices.length - 1)
                          const SizedBox(height: 14),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Future.delayed(
                              const Duration(milliseconds: 50),
                              () {
                                disposeControllers();
                                _cameraController.start();
                                _isScannerPaused = false;
                                _commitRow(row);
                              },
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ctx.themeTextSecondary,
                            side: BorderSide(color: ctx.themeBorder),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('Skip'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final updatedValues =
                                  List<String>.from(row.values);
                              for (final ci in manualIndices) {
                                final col = _session.columns[ci];
                                final val = col.isNumeric
                                    ? '${numericValues[ci] ?? col.stepSize}'
                                    : (valueControllers[ci]?.text.trim() ?? '');
                                if (updatedValues.length > ci) {
                                  updatedValues[ci] = val;
                                }
                              }
                              final updatedRow =
                                  row.copyWith(values: updatedValues);
                              Navigator.pop(ctx);
                              Future.delayed(
                                const Duration(milliseconds: 50),
                                () {
                                  disposeControllers();
                                  _cameraController.start();
                                  _isScannerPaused = false;
                                  _commitRow(updatedRow);
                                },
                              );
                            },
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text(
                              'Save & Next',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isScannerPaused = false;
    });
  }

  Widget _buildConfirmationField({
    required BuildContext ctx,
    required SessionColumn col,
    required int colIndex,
    required Map<int, TextEditingController> valueControllers,
    required Map<int, int> numericValues,
    required StateSetter setSt,
  }) {
    if (col.isNumeric) {
      final current = numericValues[colIndex] ?? col.stepSize;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  col.name.toUpperCase(),
                  style: TextStyle(
                    color: ctx.themeTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Default: ${col.defaultValue ?? col.stepSize}, Step: ${col.stepSize}',
                  style: TextStyle(
                    color: ctx.themeTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ctx.themeSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ctx.themeBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: current > col.stepSize
                      ? () => setSt(
                            () => numericValues[colIndex] =
                                current - col.stepSize,
                          )
                      : null,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$current',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ctx.themeTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setSt(
                    () => numericValues[colIndex] = current + col.stepSize,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Regular text field
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          col.name.toUpperCase(),
          style: TextStyle(
            color: ctx.themeTextSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: valueControllers[colIndex],
          autofocus: colIndex == _session.manualColumnIndices.firstOrNull,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Enter ${col.name}...',
            hintStyle: TextStyle(color: ctx.themeTextSecondary),
            filled: true,
            fillColor: ctx.themeSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ctx.themeBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ctx.themeBorder),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _applyScannedValue(String value, int colIndex) {
    final scanIndices = _session.scanColumnIndices;

    final updatedValues = List<String>.from(_pendingRow!.values);
    updatedValues[colIndex] = value;
    final updatedRow = _pendingRow!.copyWith(values: updatedValues);

    HapticFeedback.mediumImpact();

    final isLastScanColumn = _activeScanColumnIndex == scanIndices.length - 1;

    if (_session.showScanConfirmation && isLastScanColumn) {
      // All scan columns filled — show confirmation sheet (handles manual fields too)
      _isScannerPaused = true;
      setState(() {
        _pendingRow = updatedRow;
        _isProcessing = false;
        _activeScanColumnIndex++;
      });
      _showScanConfirmationSheet(updatedRow);
      return;
    }

    if (isLastScanColumn) {
      // All scan columns filled — go to manual dialogs or commit
      setState(() {
        _pendingRow = updatedRow;
        _isProcessing = false;
      });
      _promptManualColumnsOrCommit(updatedRow);
    } else {
      // Advance to next scan column
      setState(() {
        _pendingRow = updatedRow;
        _activeScanColumnIndex++;
        _isProcessing = false;
      });
    }
  }

  /// After all scan columns are filled, prompt for each manual column in order.
  /// When showScanConfirmation is true, manual columns are handled in the sheet
  /// so we go straight to commit.
  void _promptManualColumnsOrCommit(SessionRow row) {
    if (_session.showScanConfirmation) {
      _commitRow(row);
      return;
    }
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
                  style: TextStyle(color: ctx.themeTextSecondary, fontSize: 12),
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

  void _commitRow(SessionRow row) async {
    final locationIndices = [
      for (int i = 0; i < _session.columns.length; i++)
        if (_session.columns[i].type == SessionColumnType.location) i,
    ];

    SessionRow finalRow = row;

    if (locationIndices.isNotEmpty) {
      final locationString = await LocationService.instance.getLocationString();

      if (mounted &&
          (locationString == 'Location denied' ||
              locationString == 'Location blocked' ||
              locationString == 'Location off')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location unavailable: $locationString. Enable it in device settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => Geolocator.openLocationSettings(),
            ),
          ),
        );
      }

      final updatedValues = List<String>.from(row.values);
      for (final i in locationIndices) {
        if (i < updatedValues.length) {
          updatedValues[i] = locationString;
        }
      }
      finalRow = row.copyWith(values: updatedValues);
    }

    await ScanSessionService.addRow(_session.id, finalRow);
    if (!mounted) return;

    setState(() {
      _rows.add(finalRow);
      _resetPendingRow();
    });

    if (_session.destination == SessionDestination.googleSheets &&
        _session.spreadsheetId != null) {
      _syncRowToSheets(finalRow);
    }
  }

  void _syncRowToSheets(SessionRow row) {
    // Fire and forget — errors are silent in background
    ScanSessionService.syncRowToSheets(
      session: _session,
      row: row,
    ).catchError((_) {});
  }

  Future<void> _loadRows() async {
    final rows = await ScanSessionService.getRows(_session.id);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _resetPendingRow();
    });
  }

  void _undoLastRow() {
    if (_rows.isEmpty) return;
    final last = _rows.last;
    ScanSessionService.deleteRow(_session.id, last.rowIndex);
    setState(() {
      _rows.removeLast();
      _resetPendingRow();
    });
    HapticFeedback.mediumImpact();
  }

  void _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'End Session?',
          style: TextStyle(color: ctx.themeTextPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will mark the session as complete. You can still export it from history.',
          style: TextStyle(color: ctx.themeTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.themeTextSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await ScanSessionService.endSession(_session.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _openExport() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportScreen(session: _session, rows: _rows),
    );
  }

  void _showDuplicateDialog(String value, int colIndex) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B),
            size: 20,
          ),
        ),
        title: Text(
          'Duplicate Scan',
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
            Text(
              '"$value" has already been scanned in this column.',
              style: TextStyle(color: ctx.themeTextSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cameraController.start();
              _isProcessing = false;
              Navigator.pop(ctx, false);
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
              Navigator.pop(ctx, true);
              _applyScannedValue(value, colIndex);
            },
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
  }

  void _toggleScannerPaused() {
    setState(() => _isScannerPaused = !_isScannerPaused);
    if (_isScannerPaused) {
      _cameraController.stop();
    } else {
      _cameraController.start();
    }
    HapticFeedback.selectionClick();
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  void _showEditColumns() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Session Columns',
          style: TextStyle(
            color: ctx.themeTextPrimary,
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
                leading: Icon(
                  _iconFor(col.type),
                  color: _typeColor(col.type),
                  size: 20,
                ),
                title: Text(
                  col.name,
                  style: TextStyle(
                    color: ctx.themeTextPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  col.type.name,
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _editColumnName(int index) {
    final ctrl = TextEditingController(text: _session.columns[index].name);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Column',
          style: TextStyle(
            color: ctx.themeTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Column name',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
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
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((newName) {
      ctrl.dispose();
      if (newName == null || newName.isEmpty || !mounted) return;
      final updatedCols = List<SessionColumn>.from(_session.columns);
      updatedCols[index] = updatedCols[index].copyWith(name: newName);
      setState(() => _session = _session.copyWith(columns: updatedCols));
      ScanSessionService.saveSession(_session);
    });
  }

  IconData _iconFor(SessionColumnType t) => switch (t) {
    SessionColumnType.scan => Icons.qr_code_scanner_rounded,
    SessionColumnType.manual => Icons.edit_rounded,
    SessionColumnType.timestamp => Icons.access_time_rounded,
    SessionColumnType.increment => Icons.format_list_numbered_rounded,
    SessionColumnType.fixed => Icons.push_pin_rounded,
    SessionColumnType.location => Icons.location_on_rounded,
  };

  void _skipColumn() {
    final scanIndices = _session.scanColumnIndices;
    if (scanIndices.isEmpty) return;

    final isLastScanColumn = _activeScanColumnIndex == scanIndices.length - 1;

    if (isLastScanColumn) {
      _promptManualColumnsOrCommit(_pendingRow!);
    } else {
      setState(() {
        _activeScanColumnIndex++;
      });
    }
    HapticFeedback.selectionClick();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
      body: Consumer<ScanningPreferences>(
        builder: (context, prefs, _) {
          if (prefs.scannerLayout == ScannerLayoutMode.fullscreen) {
            return _buildFullscreenLayout(context);
          }
          return _buildCompactLayout(context);
        },
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    final scanIndices = _session.scanColumnIndices;

    return Column(
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
            child: _buildTableContent(context),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenLayout(BuildContext context) {
    final scanIndices = _session.scanColumnIndices;
    return Stack(
      children: [
        // Full-screen camera
        Positioned.fill(
          child: MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
          ),
        ),
        // Viewfinder overlay
        Positioned.fill(
          child: ScannerOverlayWidget(
            detectionState: _isProcessing
                ? ScannerDetectionState.detected
                : ScannerDetectionState.idle,
          ),
        ),
        // Scanning target indicator
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF34A853).withValues(alpha: 0.6),
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
        // Swipe-up table sheet
        DraggableScrollableSheet(
          initialChildSize: 0.12,
          minChildSize: 0.12,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.12, 0.5, 0.85],
          builder: (ctx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: context.themeCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: context.themeBorder,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                    ),
                    // Row count pill
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: context.themeAccent.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_rows.length} ${_rows.length == 1 ? 'row' : 'rows'} scanned',
                              style: TextStyle(
                                color: context.themeAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      child: _buildTableContent(context),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTableContent(BuildContext context) {
    final scanIndices = _session.scanColumnIndices;
    return Column(
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
