import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/lookup_list_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../settings/screens/connect_sheets_screen.dart';

/// "Add a list" (ListImport.dc.html): read a Google Sheets tab or an
/// .xlsx/.csv file, pick the code column and the columns to fill in.
/// Pops with the saved [LookupList].
class ListImportScreen extends StatefulWidget {
  const ListImportScreen({super.key});

  @override
  State<ListImportScreen> createState() => _ListImportScreenState();
}

class _ListImportScreenState extends State<ListImportScreen> {
  final _name = TextEditingController();
  String _from = 'sheets';
  List<List<String>>? _table;
  ListSource? _source;
  int _code = 0;
  final Set<int> _fill = {};
  int? _expected;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<String> get _headers => _table?.first ?? const [];
  int get _entries => (_table?.length ?? 1) - 1;

  Future<void> _pick() async {
    setState(() => _loading = true);
    try {
      if (_from == 'file') {
        await _pickFile();
      } else {
        await _pickSheet();
      }
    } on GSheetsException catch (e) {
      if (mounted) showSsToast(context, e.message);
    } catch (e) {
      if (mounted) showSsToast(context, 'Couldn’t read that file.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    final table = LookupListService.parseFile(
      file.bytes!,
      file.extension ?? 'csv',
    );
    _use(table, ListSource.file(file.name), _stem(file.name));
  }

  Future<void> _pickSheet() async {
    final picked = await Navigator.of(
      context,
    ).push<SheetDestination>(FadeSlideRoute(page: const ConnectSheetsScreen()));
    if (picked == null) return;
    final table = await GoogleSheetsService.instance.readTab(
      picked.spreadsheetId,
      picked.sheetName,
    );
    _use(
      table,
      ListSource.sheets(
        spreadsheetId: picked.spreadsheetId,
        spreadsheetTitle: picked.spreadsheetTitle,
        tab: picked.sheetName,
      ),
      picked.sheetName,
    );
  }

  static String _stem(String file) =>
      file.contains('.') ? file.substring(0, file.lastIndexOf('.')) : file;

  /// Takes a freshly read table and guesses the columns from its headers.
  void _use(List<List<String>> table, ListSource source, String name) {
    if (table.length < 2) {
      showSsToast(context, 'That has no rows under its header.');
      return;
    }
    final headers = table.first.map((h) => h.toLowerCase()).toList();
    int? find(RegExp pattern) {
      final i = headers.indexWhere(pattern.hasMatch);
      return i < 0 ? null : i;
    }

    final code =
        find(RegExp(r'\b(id|code|barcode|badge|sku|tag|serial|ean|upc)\b')) ??
        0;
    final expected = find(
      RegExp(r'\b(qty|quantity|count|stock|expected|on hand)\b'),
    );
    setState(() {
      _table = table;
      _source = source;
      _code = code;
      _expected = expected == code ? null : expected;
      _fill
        ..clear()
        ..addAll([
          for (var i = 0; i < headers.length; i++)
            if (i != _code && i != _expected) i,
        ]);
      if (_name.text.trim().isEmpty) _name.text = name;
    });
  }

  Future<void> _save() async {
    final table = _table;
    final source = _source;
    if (table == null || source == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSsToast(context, 'Give the list a name.');
      return;
    }
    final pro = UsageService.instance.isPro;
    final list = LookupList(
      id: 'list_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      headers: table.first,
      rows: const [],
      codeColumn: _code,
      fillColumns: _fill.toList()..sort(),
      expectedColumn: _expected,
      source: source,
      importedAt: DateTime.now(),
    ).withTable(table, pro: pro);
    await LookupListService.save(list);
    if (!mounted) return;
    if (list.truncatedFrom > 0) {
      showSsToast(
        context,
        'Free plan keeps the first ${LookupListService.freeEntryLimit} of '
        '${list.truncatedFrom}. Pro keeps them all.',
      );
    }
    Navigator.pop(context, list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final table = _table;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(
                    children: [
                      SsIconButton(
                        LucideIcons.chevronLeft,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Add a list',
                        style: SsText.sans(
                          size: 17,
                          weight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SsSegmented<String>(
                    options: const [
                      ('sheets', 'Google Sheets'),
                      ('file', 'File on phone'),
                    ],
                    value: _from,
                    onChanged: (v) => setState(() => _from = v),
                  ),
                  const SizedBox(height: 8),
                  _SourceCard(
                    title: table == null
                        ? (_from == 'file'
                              ? 'Pick an Excel or CSV file'
                              : 'Pick a spreadsheet tab')
                        : _source!.label,
                    subtitle: table == null
                        ? 'First row is the header: one column of codes, '
                              'any others you like'
                        : '$_entries rows · ${_headers.length} columns',
                    action: table == null ? 'Choose' : 'Change',
                    loading: _loading,
                    onTap: _pick,
                  ),
                  if (table != null) ...[
                    const SizedBox(height: 18),
                    _Label('List name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _name,
                      style: SsText.sans(
                        size: 16,
                        weight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Label('Which column has the code?'),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 3,
                      children: [
                        for (var i = 0; i < _headers.length; i++)
                          _HeaderChoice(
                            header: _headers[i],
                            sample: _sample(i),
                            selected: i == _code,
                            onTap: () => setState(() {
                              _fill
                                ..remove(i)
                                ..add(_code);
                              if (_expected == i) _expected = null;
                              _code = i;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Label('Fill in when scanned'),
                    const SizedBox(height: 8),
                    SsListGroup(
                      children: [
                        for (var i = 0; i < _headers.length; i++)
                          if (i != _code)
                            SsListRow(
                              onTap: () => setState(
                                () => _fill.contains(i)
                                    ? _fill.remove(i)
                                    : _fill.add(i),
                              ),
                              leading: Icon(
                                _fill.contains(i)
                                    ? LucideIcons.squareCheck
                                    : LucideIcons.square,
                                color: _fill.contains(i) ? c.emerald : c.muted,
                              ),
                              title: _headers[i],
                              trailing: Text(
                                _sample(i),
                                style: SsText.mono(size: 12, color: c.muted),
                              ),
                            ),
                        SsListRow(
                          title: 'Expected count',
                          subtitle:
                              'For stock counts: the column with the system qty',
                          trailing: PopupMenuButton<int>(
                            initialValue: _expected ?? -1,
                            onSelected: (i) =>
                                setState(() => _expected = i < 0 ? null : i),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: -1,
                                child: Text('None'),
                              ),
                              for (var i = 0; i < _headers.length; i++)
                                if (i != _code)
                                  PopupMenuItem(
                                    value: i,
                                    child: Text(_headers[i]),
                                  ),
                            ],
                            child: _Dropdown(
                              _expected == null ? 'None' : _headers[_expected!],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _source!.isSheets
                          ? 'Refreshes from Google Sheets each time you start '
                                'scanning.'
                          : 'Kept on this phone. Import again to update it.',
                      textAlign: TextAlign.center,
                      style: SsText.caption(color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (table != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SsButton(
                  'Save list · $_entries ${_entries == 1 ? 'entry' : 'entries'}',
                  onPressed: _save,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _sample(int column) {
    final row = _table!
        .skip(1)
        .firstWhere(
          (r) => column < r.length && r[column].isNotEmpty,
          orElse: () => const [],
        );
    return column < row.length ? row[column] : '';
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: SsText.sans(
      size: 13,
      weight: FontWeight.w500,
      color: context.ss.ink2,
    ),
  );
}

class _SourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String action;
  final bool loading;
  final VoidCallback onTap;
  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsListGroup(
      children: [
        SsListRow(
          onTap: loading ? null : onTap,
          leading: SsIconTile(
            LucideIcons.sheet,
            background: c.emeraldTint,
            color: c.emerald,
            size: 40,
          ),
          title: title,
          subtitle: subtitle,
          trailing: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  action,
                  style: SsText.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: c.emerald,
                  ),
                ),
        ),
      ],
    );
  }
}

class _HeaderChoice extends StatelessWidget {
  final String header;
  final String sample;
  final bool selected;
  final VoidCallback onTap;
  const _HeaderChoice({
    required this.header,
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final (bg, fg, sub) = selected
        ? (c.ink, c.paper, SsColors.brandLime)
        : (c.surface, c.ink, c.muted);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? bg : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                header,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SsText.sans(
                  size: 14,
                  weight: FontWeight.w600,
                  color: fg,
                ),
              ),
              Text(
                sample,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SsText.mono(size: 11, color: sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  const _Dropdown(this.label);
  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.strongBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SsText.sans(size: 14, color: c.ink),
            ),
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronDown, size: 14, color: c.ink),
        ],
      ),
    );
  }
}
