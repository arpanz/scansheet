import 'package:flutter/material.dart';

import '../../../../core/widgets/ss.dart';
import '../../models/scan_session.dart';

/// What the user picked in the "Bin for the next scans" sheet.
sealed class ValueChoice {
  const ValueChoice();
}

/// Use this value from now on.
class ValueSet extends ValueChoice {
  final String value;
  const ValueSet(this.value);
}

/// Read the next code as the new value (ScannerValue.dc.html).
class ValueScanLabel extends ValueChoice {
  const ValueScanLabel();
}

/// Change a Same value column mid-session. [starting] is the
/// "Ask when scanning starts" variant, where closing keeps the current value.
Future<ValueChoice?> showValueSheet(
  BuildContext context, {
  required SessionColumn column,
  bool starting = false,
}) => showSsSheet<ValueChoice>(
  context,
  builder: (_) => _ValueSheet(column: column, starting: starting),
);

class _ValueSheet extends StatefulWidget {
  final SessionColumn column;
  final bool starting;
  const _ValueSheet({required this.column, required this.starting});

  @override
  State<_ValueSheet> createState() => _ValueSheetState();
}

class _ValueSheetState extends State<_ValueSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _use() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, ValueSet(value));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final col = widget.column;
    final current = col.fixedValue ?? '';
    final recents = [
      if (current.isNotEmpty) current,
      ...col.recentValues.where((v) => v != current),
    ].take(6).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.starting
                ? 'Which ${col.name}?'
                : '${col.name} for the next scans',
            style: SsText.section(color: c.ink),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: SsText.sans(size: 13, color: c.ink2),
              children: [
                if (current.isEmpty)
                  const TextSpan(text: 'Not set yet')
                else ...[
                  const TextSpan(text: 'Now '),
                  TextSpan(
                    text: current,
                    style: SsText.mono(
                      size: 13,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
                TextSpan(
                  text: widget.starting
                      ? ' · asked each time you start scanning'
                      : ' · rows already scanned keep theirs',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SsButton(
            'Scan a ${col.name.toLowerCase()} label',
            icon: ssScanIcon,
            onPressed: () => Navigator.pop(context, const ValueScanLabel()),
          ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Recent',
              style: SsText.sans(
                size: 13,
                weight: FontWeight.w500,
                color: c.ink2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in recents)
                  _RecentChip(
                    value: v,
                    current: v == current,
                    onTap: () => Navigator.pop(context, ValueSet(v)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Or type one',
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: SsText.mono(size: 16, color: c.ink),
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: current.isEmpty ? 'e.g. B-12' : current,
                  ),
                  onSubmitted: (_) => _use(),
                ),
              ),
              const SizedBox(width: 10),
              SsButton('Use', expand: false, large: false, onPressed: _use),
            ],
          ),
          if (widget.starting) ...[
            const SizedBox(height: 8),
            SsButton.secondary(
              current.isEmpty ? 'Skip for now' : 'Keep $current',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String value;
  final bool current;
  final VoidCallback onTap;
  const _RecentChip({
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: current ? c.ink : c.line,
          width: current ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                value,
                style: SsText.mono(
                  size: 15,
                  weight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
