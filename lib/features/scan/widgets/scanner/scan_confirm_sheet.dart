import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ss.dart';
import '../../models/scan_session.dart';

/// What the user chose in the confirm sheet.
sealed class ConfirmOutcome {
  const ConfirmOutcome();
}

/// Save [row] as a new row.
class ConfirmAdd extends ConfirmOutcome {
  final SessionRow row;
  const ConfirmAdd(this.row);
}

/// Add [qty] to the Qty cell of the existing [target] row instead.
class ConfirmMerge extends ConfirmOutcome {
  final SessionRow target;
  final int qty;
  const ConfirmMerge(this.target, this.qty);
}

/// Confirm sheet per docs/design/mocks/ConfirmScan.dc.html. Drawn light in
/// every theme because it sits over the always-dark scanner. Returns null
/// when skipped.
Future<ConfirmOutcome?> showScanConfirmSheet(
  BuildContext context, {
  required ScanSession session,
  required SessionRow row,
  required int rowNumber,
  SessionRow? duplicateOf,
}) {
  return showModalBottomSheet<ConfirmOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SsColors.light.paper,
    builder: (_) => Theme(
      data: AppTheme.lightTheme,
      child: _ConfirmSheet(
        session: session,
        row: row,
        rowNumber: rowNumber,
        duplicateOf: duplicateOf,
      ),
    ),
  );
}

class _ConfirmSheet extends StatefulWidget {
  final ScanSession session;
  final SessionRow row;
  final int rowNumber;
  final SessionRow? duplicateOf;

  const _ConfirmSheet({
    required this.session,
    required this.row,
    required this.rowNumber,
    required this.duplicateOf,
  });

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  final _text = <int, TextEditingController>{};
  final _numbers = <int, int>{};

  ScanSession get _session => widget.session;
  int get _qtyIndex => _session.qtyColumnIndex;
  SessionRow? get _dup => _qtyIndex >= 0 ? widget.duplicateOf : null;

  @override
  void initState() {
    super.initState();
    for (final i in _session.manualColumnIndices) {
      final col = _session.columns[i];
      final current = widget.row.values[i];
      final initial = current.isNotEmpty
          ? current
          : (col.defaultValue ?? (col.isNumeric ? '${col.stepSize}' : ''));
      if (col.isNumeric) {
        _numbers[i] = int.tryParse(initial) ?? col.stepSize;
      } else {
        _text[i] = TextEditingController(text: initial);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _code {
    final scans = _session.scanColumnIndices;
    for (final i in scans.reversed) {
      if (widget.row.values[i].isNotEmpty) return widget.row.values[i];
    }
    return '';
  }

  SessionRow _filledRow() {
    final values = List<String>.from(widget.row.values);
    _text.forEach((i, c) => values[i] = c.text.trim());
    _numbers.forEach((i, n) => values[i] = '$n');
    return widget.row.copyWith(values: values);
  }

  void _add() => Navigator.pop(context, ConfirmAdd(_filledRow()));

  void _merge() => Navigator.pop(
    context,
    ConfirmMerge(
      _dup!,
      _numbers[_qtyIndex] ?? _session.columns[_qtyIndex].stepSize,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final dup = _dup;
    final format = widget.row.barcodeFormat;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: c.strongBorder,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Row ${widget.rowNumber}',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
              const Spacer(),
              if (format != null) SsTag(format.replaceAll('_', '‑')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _code,
                  style: SsText.mono(
                    size: 20,
                    weight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SsIconButton(
                LucideIcons.copy,
                tooltip: 'Copy code',
                background: c.track,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _code));
                  showSsToast(context, 'Copied');
                },
              ),
            ],
          ),
          if (dup != null) ...[
            const SizedBox(height: 16),
            _DuplicateBanner(row: dup, qtyIndex: _qtyIndex),
          ],
          if (_text.isNotEmpty || _numbers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SsRadius.lg),
                border: Border.all(color: c.line),
              ),
              child: Column(
                children: [
                  for (final (k, i)
                      in _session.manualColumnIndices.indexed) ...[
                    if (k > 0) Divider(height: 1, color: c.lineSoft),
                    _numbers.containsKey(i)
                        ? _NumberField(
                            label: _session.columns[i].name,
                            value: _numbers[i]!,
                            step: _session.columns[i].stepSize,
                            onChanged: (v) => setState(() => _numbers[i] = v),
                          )
                        : _TextField(
                            label: _session.columns[i].name,
                            controller: _text[i]!,
                          ),
                  ],
                ],
              ),
            ),
          ],
          if (_contextChips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 6, runSpacing: 6, children: _contextChips),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: SsButton(
                  'Skip',
                  kind: SsButtonKind.secondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: dup != null
                    ? SsButton(
                        'Add to row ${dup.rowIndex + 1}',
                        onPressed: _merge,
                      )
                    : SsButton('Add row', onPressed: _add),
              ),
            ],
          ),
          if (dup != null)
            Center(
              child: TextButton(
                onPressed: _add,
                child: const Text('Add as a new row instead'),
              ),
            ),
        ],
      ),
    );
  }

  /// Auto-filled cells shown as read-only chips (time, fixed values, GPS).
  List<Widget> get _contextChips => [
    for (final (i, col) in _session.columns.indexed)
      switch (col.type) {
        SessionColumnType.timestamp => _Chip(
          LucideIcons.clock,
          widget.row.values[i].length >= 16
              ? widget.row.values[i].substring(11, 16)
              : widget.row.values[i],
        ),
        SessionColumnType.fixed when (col.fixedValue ?? '').isNotEmpty => _Chip(
          LucideIcons.mapPin,
          '${col.name} ${col.fixedValue}',
        ),
        SessionColumnType.location => const _Chip(
          LucideIcons.locateFixed,
          'Location on save',
        ),
        _ => null,
      },
  ].nonNulls.toList();
}

class _DuplicateBanner extends StatelessWidget {
  final SessionRow row;
  final int qtyIndex;
  const _DuplicateBanner({required this.row, required this.qtyIndex});

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF6B3D05);
    final t = row.scannedAt;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final qty = row.values[qtyIndex].isEmpty ? '1' : row.values[qtyIndex];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF1D8),
        borderRadius: BorderRadius.circular(SsRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.copy, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Already in row ${row.rowIndex + 1}',
                  style: SsText.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Scanned at $time with Qty $qty. Count it there, or skip.',
                  style: SsText.sans(size: 13, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int step;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    Widget btn(IconData icon, bool dark, VoidCallback? onTap) => Material(
      color: dark ? c.ink : c.surface,
      elevation: dark ? 0 : 0.5,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: dark ? c.onInk : c.ink),
        ),
      ),
    );
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SsText.sans(weight: FontWeight.w500, color: c.ink),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                btn(
                  LucideIcons.minus,
                  false,
                  value - step < 0 ? null : () => onChanged(value - step),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: SsText.mono(
                      size: 18,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                btn(LucideIcons.plus, true, () => onChanged(value + step)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _TextField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: SsText.sans(weight: FontWeight.w500, color: c.ink),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            style: SsText.sans(color: c.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Optional',
              fillColor: c.paper,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SsRadius.sm),
                borderSide: BorderSide(color: c.strongBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SsRadius.sm),
                borderSide: BorderSide(color: c.ink, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.track,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.ink2),
          const SizedBox(width: 6),
          Text(
            text,
            style: SsText.mono(
              size: 12,
              weight: FontWeight.w400,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
