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

  List<ColumnKind> get _kinds => [
    for (final kind in ColumnKind.values)
      if (kind != ColumnKind.fromList || widget.listHeaders.isNotEmpty) kind,
  ];

  @override
  void initState() {
    super.initState();
    final col = widget.editing;
    _kind = col == null ? ColumnKind.scan : ColumnKind.of(col);
    _name = TextEditingController(text: col?.name ?? _kind.defaultName);
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
    _choices = List.of(col?.choices ?? const ['Good', 'Damaged', 'Missing']);
    _defaultChoice =
        col?.defaultValue ?? (_choices.isEmpty ? null : _choices.first);
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
    setState(() {
      _kind = kind;
      if (_name.text ==
              ColumnKind.of(
                widget.editing ??
                    const SessionColumn(name: '', type: SessionColumnType.scan),
              ).defaultName ||
          _name.text.isEmpty) {
        _name.text = kind.defaultName;
      }
      if (kind == ColumnKind.pickList && _choices.isEmpty) {
        _choices = ['Good', 'Damaged', 'Missing'];
        _defaultChoice = _choices.first;
      }
      if (kind == ColumnKind.number && _value.text.isEmpty) _value.text = '1';
      if (kind == ColumnKind.fromList && _listField != null) {
        _name.text = _listField!;
      }
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.editing == null ? 'Add column' : 'Edit column',
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
                  background: c.track,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _kinds.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _kinds.length > 10 ? 6 : 5,
                mainAxisExtent: 66,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemBuilder: (context, i) {
                final kind = _kinds[i];
                final selected = kind == _kind;
                // Selected: lime icon on ink in light, ink on lime in dark.
                final (Color bg, Color icon, Color text) = !selected
                    ? (c.surface, c.ink, c.ink)
                    : context.isDark
                    ? (SsColors.brandLime, SsColors.brandInk, SsColors.brandInk)
                    : (SsColors.brandInk, SsColors.brandLime, Colors.white);
                return Material(
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: selected ? bg : c.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _select(kind),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(kind.icon, size: 20, color: icon),
                        const SizedBox(height: 5),
                        Text(
                          kind.label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: SsText.sans(
                            size: 10,
                            weight: FontWeight.w600,
                            color: text,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _kind.hint,
                style: SsText.sans(size: 13, height: 1.45, color: c.ink2),
              ),
            ),
            const SizedBox(height: 12),
            _Field(label: 'Column name', controller: _name),
            if (_kind == ColumnKind.number) ...[
              const SizedBox(height: 10),
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
            if (_kind == ColumnKind.fixed)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 10),
                  children: [
                    _Field(label: 'Starting value', controller: _value),
                    const SizedBox(height: 12),
                    Text(
                      'While scanning',
                      style: SsText.sans(
                        size: 13,
                        weight: FontWeight.w500,
                        color: c.ink2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SsListGroup(
                      children: [
                        SsListRow(
                          title: 'Change by scanning a label',
                          subtitle:
                              'Tapping the value in the scanner always works too',
                          trailing: _switch(_labelOn, (v) {
                            _labelOn = v;
                            if (v && _prefix.text.trim().isEmpty) {
                              _prefix.text = 'BIN-';
                            }
                          }),
                        ),
                        if (_labelOn)
                          SsListRow(
                            title: 'Labels start with',
                            subtitle:
                                'These set the value, they don’t add a row',
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: c.line),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: c.ink,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        SsListRow(
                          title: 'Ask when scanning starts',
                          subtitle:
                              'Good for a batch or shift that changes daily',
                          trailing: _switch(
                            _askAtStart,
                            (v) => _askAtStart = v,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (_kind == ColumnKind.pickList) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Choices',
                    style: SsText.sans(
                      size: 13,
                      weight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                  Text(
                    'Tap one to make it the default',
                    style: SsText.sans(size: 11, color: c.muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SsListGroup(
                  children: [
                    for (final choice in _choices)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: GestureDetector(
                          onTap: () => setState(() => _defaultChoice = choice),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _defaultChoice == choice
                                    ? c.ink
                                    : c.muted,
                                width: _defaultChoice == choice ? 6 : 1.5,
                              ),
                            ),
                          ),
                        ),
                        title: Text(choice),
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
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
                              decoration: const InputDecoration(
                                hintText: 'Add a choice',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _addChoice(),
                            ),
                          ),
                          IconButton(
                            onPressed: _addChoice,
                            icon: Icon(LucideIcons.arrowUp, color: c.emerald),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_kind == ColumnKind.fromList) ...[
              const SizedBox(height: 12),
              Text(
                'Field from the list',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: c.ink2,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  children: [
                    SsListGroup(
                      children: [
                        for (final header in widget.listHeaders)
                          SsListRow(
                            title: header,
                            trailing: SsRadio(selected: header == _listField),
                            onTap: () => setState(() {
                              if (_name.text == (_listField ?? '') ||
                                  _name.text == _kind.defaultName) {
                                _name.text = header;
                              }
                              _listField = header;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 12),
            SsButton(
              widget.editing == null ? 'Add column' : 'Save column',
              onPressed: _finish,
            ),
          ],
        ),
      ),
    );
  }

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
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
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
