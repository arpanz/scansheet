import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/ss.dart';
import '../scan/models/column_kind.dart';
import '../scan/models/scan_session.dart';

/// [listHeaders] are the attached list's columns (code column left out);
/// the From list kind is offered only when there are some.
Future<SessionColumn?> showAddColumnSheet(
  BuildContext context, {
  SessionColumn? editing,
  List<String> listHeaders = const [],
}) => showSsSheet<SessionColumn>(
  context,
  builder: (_) => _AddColumnForm(editing: editing, listHeaders: listHeaders),
);

class _AddColumnForm extends StatefulWidget {
  final SessionColumn? editing;
  final List<String> listHeaders;
  const _AddColumnForm({this.editing, this.listHeaders = const []});

  @override
  State<_AddColumnForm> createState() => _AddColumnFormState();
}

class _AddColumnFormState extends State<_AddColumnForm> {
  late ColumnKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _step;
  late final TextEditingController _value;
  late final TextEditingController _choiceInput;
  late final TextEditingController _prefix;
  late List<String> _choices;
  late String? _defaultChoice;
  late bool _labelOn;
  late bool _askAtStart;
  late String? _listField;
  late LocationFormat _locationFormat;

  /// Step one: choose a type. A new column starts here; editing starts on
  /// step two, where Change comes back.
  late bool _picking;

  /// Once the name is typed it's the user's; until then it follows the
  /// type (and the location format or list field).
  late bool _nameTyped;

  /// Every type in one list, the ones most sheets need first.
  List<ColumnKind> get _kinds => [
    ColumnKind.scan,
    ColumnKind.number,
    ColumnKind.text,
    ColumnKind.pickList,
    ColumnKind.time,
    ColumnKind.product,
    if (widget.listHeaders.isNotEmpty) ColumnKind.fromList,
    ColumnKind.fixed,
    ColumnKind.location,
    ColumnKind.readText,
    ColumnKind.auto,
  ];

  /// A new column has no type until one is tapped, so none is marked.
  late bool _chosen;

  static String _blurb(ColumnKind kind) => switch (kind) {
    ColumnKind.scan => 'The barcode or QR code you scan',
    ColumnKind.readText => 'Printed words, like an expiry date',
    ColumnKind.product => 'Product name looked up from the barcode',
    ColumnKind.fromList => 'A field from your list, like a name',
    ColumnKind.time => 'When each code was scanned',
    ColumnKind.location => 'Where the phone was',
    ColumnKind.auto => 'Numbers the rows 1, 2, 3…',
    ColumnKind.number => 'A count with – and + buttons, like Qty',
    ColumnKind.pickList => 'One tap from set choices, like Good / Damaged',
    ColumnKind.text => 'Anything you type, like a note',
    ColumnKind.fixed => 'The same on every row, like a bin or batch',
  };

  /// The name a column of the current type gets unless one is typed.
  String get _autoName => switch (_kind) {
    ColumnKind.fromList => _listField ?? _kind.defaultName,
    ColumnKind.location when _locationFormat != LocationFormat.coordinates =>
      _locationFormat.label,
    _ => _kind.defaultName,
  };

  void _followName() {
    if (!_nameTyped) _name.text = _autoName;
  }

  @override
  void initState() {
    super.initState();
    final col = widget.editing;
    _kind = col == null ? ColumnKind.scan : ColumnKind.of(col);
    _picking = col == null;
    _chosen = col != null;
    _step = TextEditingController(text: '${col?.stepSize ?? 1}');
    _value = TextEditingController(
      text: _kind == ColumnKind.fixed
          ? col?.fixedValue ?? ''
          : col?.defaultValue ?? (_kind == ColumnKind.number ? '1' : ''),
    );
    _choiceInput = TextEditingController();
    _prefix = TextEditingController(text: col?.labelPrefix ?? '');
    _labelOn = (col?.labelPrefix ?? '').isNotEmpty;
    _askAtStart = col?.askAtStart ?? false;
    _listField = col?.listField ?? widget.listHeaders.firstOrNull;
    _locationFormat = col?.locationFormat ?? LocationFormat.coordinates;
    _choices = List.of(col?.choices ?? const ['Good', 'Damaged', 'Missing']);
    _defaultChoice =
        col?.defaultValue ?? (_choices.isEmpty ? null : _choices.first);
    _name = TextEditingController(text: col?.name ?? _autoName);
    // An existing column keeps its name unless it's still the automatic one.
    _nameTyped = col != null && col.name != _autoName;
  }

  @override
  void dispose() {
    _name.dispose();
    _step.dispose();
    _value.dispose();
    _choiceInput.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _select(ColumnKind kind) {
    HapticFeedback.selectionClick();
    setState(() {
      _kind = kind;
      _chosen = true;
      _picking = false;
      if (kind == ColumnKind.pickList && _choices.isEmpty) {
        _choices = ['Good', 'Damaged', 'Missing'];
        _defaultChoice = _choices.first;
      }
      if (kind == ColumnKind.number && _value.text.isEmpty) _value.text = '1';
      _followName();
    });
  }

  void _finish() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSsToast(context, 'Enter a column name.');
      return;
    }
    final value = _value.text.trim();
    final fixed = _kind == ColumnKind.fixed;
    final prefix = _prefix.text.trim();
    Navigator.of(context).pop(
      SessionColumn(
        name: name,
        type: _kind.type,
        fixedValue: _kind == ColumnKind.fixed ? value : null,
        defaultValue: _kind == ColumnKind.pickList
            ? _defaultChoice
            : _kind == ColumnKind.number
            ? (value.isEmpty ? '1' : value)
            : null,
        isNumeric: _kind == ColumnKind.number,
        stepSize: _kind == ColumnKind.number
            ? (int.tryParse(_step.text) ?? 1).clamp(1, 999999)
            : 1,
        choices: _kind == ColumnKind.pickList
            ? List.unmodifiable(_choices)
            : const [],
        labelPrefix: fixed && _labelOn && prefix.isNotEmpty ? prefix : null,
        askAtStart: fixed && _askAtStart,
        recentValues: fixed
            ? widget.editing?.recentValues ?? const []
            : const [],
        listField: _kind == ColumnKind.fromList ? _listField : null,
        locationFormat: _kind == ColumnKind.location
            ? _locationFormat
            : LocationFormat.coordinates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final adding = widget.editing == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .84,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _picking
                        ? 'What goes in it?'
                        : adding
                        ? 'Add column'
                        : 'Edit column',
                    style: SsText.sans(
                      size: 20,
                      weight: FontWeight.w600,
                      spacing: -.4,
                      color: c.ink,
                    ),
                  ),
                ),
                SsIconButton(
                  LucideIcons.x,
                  tooltip: 'Close',
                  background: c.track,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(child: _picking ? _typeList(c) : _details(c)),
            if (!_picking) ...[
              const SizedBox(height: 12),
              SsButton(
                adding ? 'Add column' : 'Save column',
                onPressed: _finish,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Step one: every type at once.
  Widget _typeList(SsColors c) => ListView(
    shrinkWrap: true,
    children: [
      SsListGroup(
        children: [
          for (final kind in _kinds)
            SsListRow(
              leading: _KindTile(kind, selected: _chosen && kind == _kind),
              title: kind.label,
              subtitle: _blurb(kind),
              onTap: () => _select(kind),
            ),
        ],
      ),
    ],
  );

  /// Step two: the chosen type, the column's name and the type's options.
  Widget _details(SsColors c) => ListView(
    shrinkWrap: true,
    children: [
      SsCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onTap: () => setState(() => _picking = true),
        child: Row(
          children: [
            _KindTile(_kind, selected: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kind.label,
                    style: SsText.sans(
                      size: 15,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    _blurb(_kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SsText.sans(size: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _picking = true),
              child: Text(
                'Change',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: c.emerald,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Field(
        label: 'Column name',
        controller: _name,
        onChanged: (v) => _nameTyped = v.trim().isNotEmpty,
      ),
      ..._options(c),
    ],
  );

  /// The settings only some types have.
  List<Widget> _options(SsColors c) => switch (_kind) {
    ColumnKind.number => [
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Field(
              label: 'Step',
              controller: _step,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Field(
              label: 'Starting value',
              controller: _value,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
    ],
    ColumnKind.fixed => [
      const SizedBox(height: 12),
      _Field(label: 'Starting value', controller: _value),
      const SizedBox(height: 14),
      _label('While scanning', c),
      SsListGroup(
        children: [
          SsListRow(
            title: 'Change by scanning a label',
            subtitle: 'Tapping the value in the scanner always works too',
            trailing: _switch(_labelOn, (v) {
              _labelOn = v;
              if (v && _prefix.text.trim().isEmpty) _prefix.text = 'BIN-';
            }),
          ),
          if (_labelOn)
            SsListRow(
              title: 'Labels start with',
              subtitle: 'These set the value, they don’t add a row',
              trailing: SizedBox(
                width: 92,
                height: 44,
                child: TextField(
                  controller: _prefix,
                  style: SsText.mono(size: 15, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'BIN-',
                    filled: true,
                    fillColor: c.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.ink, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          SsListRow(
            title: 'Ask when scanning starts',
            subtitle: 'Good for a batch or shift that changes daily',
            trailing: _switch(_askAtStart, (v) => _askAtStart = v),
          ),
        ],
      ),
    ],
    ColumnKind.pickList => [
      const SizedBox(height: 14),
      _label('Choices · tap one to make it the default', c),
      SsListGroup(
        children: [
          for (final choice in _choices)
            SsListRow(
              leading: SsRadio(selected: _defaultChoice == choice),
              title: choice,
              onTap: () => setState(() => _defaultChoice = choice),
              trailing: SsIconButton(
                LucideIcons.x,
                size: 36,
                color: c.muted,
                tooltip: 'Remove $choice',
                onPressed: () => setState(() {
                  _choices.remove(choice);
                  if (_defaultChoice == choice) {
                    _defaultChoice = _choices.firstOrNull;
                  }
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(LucideIcons.plus, size: 18, color: c.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _choiceInput,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a choice',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: (_) => _addChoice(),
                  ),
                ),
                IconButton(
                  tooltip: 'Add choice',
                  onPressed: _addChoice,
                  icon: Icon(LucideIcons.arrowUp, color: c.emerald),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
    ColumnKind.location => [
      const SizedBox(height: 14),
      _label('Record as', c),
      SsListGroup(
        children: [
          for (final format in LocationFormat.values)
            SsListRow(
              title: format.label,
              subtitle: format.example,
              trailing: SsRadio(selected: format == _locationFormat),
              onTap: () => setState(() {
                _locationFormat = format;
                _followName();
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Names come from the phone’s map service and need internet. '
        'Offline, the cell gets the coordinates.',
        style: SsText.sans(size: 12, color: c.muted),
      ),
    ],
    ColumnKind.fromList => [
      const SizedBox(height: 14),
      _label('Field from the list', c),
      SsListGroup(
        children: [
          for (final header in widget.listHeaders)
            SsListRow(
              title: header,
              trailing: SsRadio(selected: header == _listField),
              onTap: () => setState(() {
                _listField = header;
                _followName();
              }),
            ),
        ],
      ),
    ],
    _ => const [],
  };

  Widget _label(String text, SsColors c) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: SsText.sans(size: 13, weight: FontWeight.w500, color: c.ink2),
    ),
  );

  Widget _switch(bool value, void Function(bool) onChanged) => Switch(
    value: value,
    onChanged: (v) {
      HapticFeedback.selectionClick();
      setState(() => onChanged(v));
    },
    activeTrackColor: context.ss.emerald,
  );

  void _addChoice() {
    final value = _choiceInput.text.trim();
    if (value.isEmpty || _choices.contains(value)) return;
    setState(() {
      _choices.add(value);
      _defaultChoice ??= value;
      _choiceInput.clear();
    });
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.onChanged,
  });
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
        const SizedBox(height: 6),
        SizedBox(
          height: 50,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: SsText.sans(size: 16, weight: FontWeight.w500, color: c.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
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

/// A type's icon on a tile; lime on ink once chosen (ink on lime in dark).
class _KindTile extends StatelessWidget {
  final ColumnKind kind;
  final bool selected;
  const _KindTile(this.kind, {this.selected = false});

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Color? fg) = !selected
        ? (null, null)
        : context.isDark
        ? (SsColors.brandLime, SsColors.brandInk)
        : (SsColors.brandInk, SsColors.brandLime);
    return SsIconTile(kind.icon, size: 40, background: bg, color: fg);
  }
}
