import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';

import '../../../core/services/scan_session_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../scan/models/scan_session.dart';

/// Full-screen detail view for a single scanned row.
/// Matches mockup screen 5.
class EntryDetailScreen extends StatefulWidget {
  final ScanSession session;
  final SessionRow row;

  /// Pass true if this row was already detected as a duplicate when scanned.
  final bool isDuplicate;

  const EntryDetailScreen({
    super.key,
    required this.session,
    required this.row,
    this.isDuplicate = false,
  });

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late List<String> _values;
  late TextEditingController _notesCtrl;
  bool _isSaving = false;
  bool _isEditing = false;
  late List<TextEditingController> _editCtrls;

  @override
  void initState() {
    super.initState();
    _values = List.from(widget.row.values);
    _notesCtrl = TextEditingController(text: _getFieldValue('Notes'));
    _editCtrls = [
      for (int i = 0; i < widget.session.columns.length; i++)
        TextEditingController(
          text: i < _values.length ? _values[i] : '',
        ),
    ];
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _editCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _getFieldValue(String colName) {
    for (int i = 0; i < widget.session.columns.length; i++) {
      if (widget.session.columns[i].name.toLowerCase() ==
          colName.toLowerCase()) {
        return i < _values.length ? _values[i] : '';
      }
    }
    return '';
  }

  String get _primaryValue {
    // First scan column, or first column if none
    final scanIdx = widget.session.scanColumnIndices;
    if (scanIdx.isNotEmpty) {
      final i = scanIdx.first;
      return i < _values.length ? _values[i] : '';
    }
    return _values.isNotEmpty ? _values.first : '';
  }

  bool get _isQrCode {
    final fmt = widget.row.barcodeFormat?.toLowerCase() ?? '';
    return fmt.contains('qr');
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final updated = widget.row.copyWith(values: List.from(_values));
    await ScanSessionService.updateRow(widget.session.id, updated);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry saved'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.themeAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Entry?'),
        content: Text(
          'Row ${widget.row.rowIndex + 1} will be permanently removed from this session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.themeTextSecondary),
            ),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: context.themeError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ScanSessionService.deleteRow(
        widget.session.id, widget.row.rowIndex);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, true); // Signal that a row was deleted
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [
                // Duplicate warning banner
                if (widget.isDuplicate)
                  _DuplicateBanner(rowIndex: widget.row.rowIndex),

                const SizedBox(height: 16),

                // Barcode visual
                _BarcodeVisual(
                  value: _primaryValue,
                  isQr: _isQrCode,
                  barcodeFormat: widget.row.barcodeFormat,
                  session: widget.session,
                ),

                const SizedBox(height: 20),

                // Field list
                _FieldCard(
                  session: widget.session,
                  values: _values,
                  row: widget.row,
                  isEditing: _isEditing,
                  controllers: _editCtrls,
                  onValueChanged: (i, v) {
                    setState(() {
                      _values[i] = v;
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Destination / sync card
                _DestinationCard(session: widget.session),

                const SizedBox(height: 24),

                // Action buttons
                if (!_isEditing)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isEditing = true);
                          },
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit Entry'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _shareEntry();
                          },
                          icon: const Icon(Icons.ios_share_rounded, size: 16),
                          label: const Text('Share'),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.themeAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                if (_isEditing)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            // Reset edit controllers to current saved values
                            for (int i = 0;
                                i < widget.session.columns.length;
                                i++) {
                              _editCtrls[i].text =
                                  i < _values.length ? _values[i] : '';
                            }
                            setState(() => _isEditing = false);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  // Apply edited values from controllers
                                  for (int i = 0;
                                      i < widget.session.columns.length;
                                      i++) {
                                    if (i < _values.length) {
                                      _values[i] = _editCtrls[i].text.trim();
                                    }
                                  }
                                  _save();
                                },
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(_isSaving ? 'Saving…' : 'Save'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: context.themeCard,
      elevation: 0,
      scrolledUnderElevation: 1,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: context.themeTextPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entry Detail',
            style: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Row ${widget.row.rowIndex + 1}',
            style: TextStyle(color: context.themeTextSecondary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: context.themeError),
          tooltip: 'Delete entry',
          onPressed: _deleteEntry,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _shareEntry() {
    final cols = widget.session.columns;
    final sb = StringBuffer();
    sb.writeln('📊 ${widget.session.name} — Row ${widget.row.rowIndex + 1}');
    sb.writeln();
    for (int i = 0; i < cols.length; i++) {
      sb.writeln('${cols[i].name}: ${i < _values.length ? _values[i] : ''}');
    }
    HapticFeedback.selectionClick();
    // We use Share from share_plus but keep import minimal
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Share copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Clipboard.setData(ClipboardData(text: sb.toString()));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DuplicateBanner extends StatelessWidget {
  final int rowIndex;
  const _DuplicateBanner({required this.rowIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This value was already scanned earlier in this session.',
              style: TextStyle(
                color: context.themeTextPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeVisual extends StatelessWidget {
  final String value;
  final bool isQr;
  final String? barcodeFormat;
  final ScanSession session;

  const _BarcodeVisual({
    required this.value,
    required this.isQr,
    required this.barcodeFormat,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF006A6B);
    final displayFormat = barcodeFormat?.isNotEmpty == true
        ? _formatLabel(barcodeFormat!)
        : isQr
            ? 'QR Code'
            : 'Barcode';

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Barcode/QR image
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: value.isEmpty
                ? Icon(
                    Icons.qr_code_rounded,
                    size: 64,
                    color: context.themeTextSecondary.withValues(alpha: 0.3),
                  )
                : isQr
                    ? QrImageView(
                        data: value,
                        version: QrVersions.auto,
                        size: 104,
                      )
                    : _tryBarcode(value),
          ),
          const SizedBox(height: 16),

          // Format label
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              displayFormat,
              style: const TextStyle(
                color: teal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Raw value (mono)
          SelectableText(
            value.isEmpty ? '—' : value,
            style: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 15,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 4),
          Text(
            session.name,
            style: const TextStyle(
              color: teal,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(String fmt) {
    return switch (fmt.toLowerCase()) {
      'qr' || 'qr_code' => 'QR Code',
      'ean13' => 'EAN-13',
      'ean8' => 'EAN-8',
      'code128' => 'Code 128',
      'code39' => 'Code 39',
      'upca' => 'UPC-A',
      'upce' => 'UPC-E',
      'pdf417' => 'PDF417',
      'aztec' => 'Aztec',
      'datamatrix' => 'Data Matrix',
      _ => fmt.toUpperCase(),
    };
  }

  Widget _tryBarcode(String value) {
    try {
      return BarcodeWidget(
        barcode: Barcode.code128(),
        data: value,
        drawText: false,
        color: Colors.black,
      );
    } catch (_) {
      return Icon(
        Icons.qr_code_rounded,
        size: 64,
        color: Colors.black54,
      );
    }
  }
}

class _FieldCard extends StatelessWidget {
  final ScanSession session;
  final List<String> values;
  final SessionRow row;
  final bool isEditing;
  final List<TextEditingController> controllers;
  final void Function(int index, String value) onValueChanged;

  const _FieldCard({
    required this.session,
    required this.values,
    required this.row,
    required this.isEditing,
    required this.controllers,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (int i = 0; i < session.columns.length; i++) ...[
            _FieldRow(
              column: session.columns[i],
              value: i < values.length ? values[i] : '',
              isEditing: isEditing &&
                  (session.columns[i].type == SessionColumnType.manual ||
                      session.columns[i].type == SessionColumnType.scan),
              controller: controllers[i],
              onChanged: (v) => onValueChanged(i, v),
            ),
            if (i < session.columns.length - 1)
              Divider(
                height: 1,
                color: context.themeBorder,
              ),
          ],
          // Scanned-at timestamp (always shown)
          Divider(height: 1, color: context.themeBorder),
          _StaticFieldRow(
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFF3B82F6),
            label: 'Scanned at',
            value: _formatTime(row.scannedAt),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final d = local.day;
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '$d ${months[local.month - 1]} ${local.year}, $h:$m';
  }
}

class _FieldRow extends StatelessWidget {
  final SessionColumn column;
  final String value;
  final bool isEditing;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FieldRow({
    required this.column,
    required this.value,
    required this.isEditing,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(column.type);
    final icon = _typeIcon(column.type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  column.name,
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (isEditing)
                  TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: TextStyle(
                      color: context.themeTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: context.themeAccent),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: context.themeAccent, width: 2),
                      ),
                    ),
                  )
                else
                  Text(
                    value.isEmpty ? '—' : value,
                    style: TextStyle(
                      color: value.isEmpty
                          ? context.themeTextSecondary
                          : context.themeTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: column.type == SessionColumnType.scan
                          ? 'monospace'
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(SessionColumnType t) => switch (t) {
        SessionColumnType.scan => const Color(0xFF22C55E),
        SessionColumnType.manual => const Color(0xFF9333EA),
        SessionColumnType.timestamp => const Color(0xFF3B82F6),
        SessionColumnType.increment => const Color(0xFFF59E0B),
        SessionColumnType.fixed => const Color(0xFF6B7280),
      };

  IconData _typeIcon(SessionColumnType t) => switch (t) {
        SessionColumnType.scan => Icons.qr_code_scanner_rounded,
        SessionColumnType.manual => Icons.edit_rounded,
        SessionColumnType.timestamp => Icons.schedule_rounded,
        SessionColumnType.increment => Icons.tag_rounded,
        SessionColumnType.fixed => Icons.push_pin_rounded,
      };
}

class _StaticFieldRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StaticFieldRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final ScanSession session;
  const _DestinationCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final isSheets =
        session.destination == SessionDestination.googleSheets;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSheets
                  ? const Color(0xFF0F9D58).withValues(alpha: 0.1)
                  : const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSheets
                  ? Icons.table_chart_rounded
                  : Icons.description_rounded,
              size: 18,
              color: isSheets
                  ? const Color(0xFF0F9D58)
                  : const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSheets ? 'Google Sheets' : 'Local File',
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isSheets && session.sheetName != null)
                  Text(
                    '${session.sheetName}',
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 11,
                    ),
                  )
                else if (!isSheets)
                  Text(
                    session.destination == SessionDestination.localXlsx
                        ? 'Excel (.xlsx)'
                        : 'CSV (.csv)',
                    style: TextStyle(
                      color: context.themeTextSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 6, color: Color(0xFF22C55E)),
                SizedBox(width: 4),
                Text(
                  'Saved',
                  style: TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
