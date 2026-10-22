import 'package:flutter/material.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/template_service.dart';
import '../../../core/widgets/ss.dart';
import '../onboarding_flow.dart';

class OnbDestinationStep extends StatefulWidget {
  final OnbStateScope scope;
  const OnbDestinationStep({super.key, required this.scope});
  @override
  State<OnbDestinationStep> createState() => _OnbDestinationStepState();
}

class _OnbDestinationStepState extends State<OnbDestinationStep> {
  String _templateName() {
    final id = widget.scope.state.selectedTemplateId;
    for (final t in TemplateService.getBuiltInTemplates()) {
      if (t.id == id) return t.name;
    }
    return 'Your sheet';
  }

  final _search = TextEditingController();
  bool _loading = false;
  String? _error;
  List<SpreadsheetInfo> _files = [];
  @override
  void initState() {
    super.initState();
    if (widget.scope.state.destination == 'existing' &&
        GoogleSheetsService.instance.isSignedIn) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await GoogleSheetsService.instance.listSpreadsheets(
        query: _search.text,
      );
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load spreadsheets. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(String value) {
    setState(() {
      widget.scope.state.destination = value;
      _error = null;
    });
    if (value == 'existing' && GoogleSheetsService.instance.isSignedIn) _load();
  }

  void _continue() {
    if (widget.scope.state.destination == 'local') {
      widget.scope.goNext(context);
      return;
    }
    if (!GoogleSheetsService.instance.isSignedIn) {
      widget.scope.state.signinFromNew =
          widget.scope.state.destination == 'new';
      widget.scope.insertSigninAndGo();
      return;
    }
    if (widget.scope.state.destination == 'existing' &&
        widget.scope.state.pickedSpreadsheetId == null) {
      setState(() => _error = 'Choose a spreadsheet to continue.');
      return;
    }
    widget.scope.goNext(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where should\nyour rows go?',
            style: SsText.title(color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a spreadsheet, or start a fresh one. You can switch per sheet later.',
            style: SsText.body(color: c.ink2),
          ),
          const SizedBox(height: 20),
          ...[
            (
              'new',
              'Create a new Google Sheet',
              '${_templateName()} · in My Drive',
              LucideIcons.plus,
            ),
            (
              'existing',
              'Add to a spreadsheet I have',
              'Pick one from your Google Drive',
              LucideIcons.table2,
            ),
            (
              'local',
              'Keep it on this phone',
              'Save as Excel or CSV, share when done',
              LucideIcons.smartphone,
            ),
          ].map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _select(o.$1),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.scope.state.destination == o.$1
                          ? c.ink
                          : c.line,
                      width: widget.scope.state.destination == o.$1 ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.scope.state.destination == o.$1
                              ? c.lime
                              : c.chip,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(o.$4, size: 19, color: c.ink),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.$2, style: SsText.label(color: c.ink)),
                            const SizedBox(height: 2),
                            Text(o.$3, style: SsText.caption(color: c.muted)),
                          ],
                        ),
                      ),
                      Icon(
                        widget.scope.state.destination == o.$1
                            ? LucideIcons.circleCheck
                            : LucideIcons.circle,
                        size: 22,
                        color: widget.scope.state.destination == o.$1
                            ? c.ink
                            : c.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.scope.state.destination == 'existing' &&
              GoogleSheetsService.instance.isSignedIn) ...[
            TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.search),
                hintText: 'Search your spreadsheets',
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: SsText.caption(color: c.error))
            else if (_files.isEmpty)
              Text(
                'No spreadsheets found in your Drive yet.',
                style: SsText.caption(color: c.muted),
              )
            else
              ..._files
                  .take(4)
                  .map(
                    (f) => ListTile(
                      dense: true,
                      leading: Icon(LucideIcons.table2, color: c.emerald),
                      title: Text(
                        f.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: widget.scope.state.pickedSpreadsheetId == f.id,
                      onTap: () => setState(() {
                        widget.scope.state.pickedSpreadsheetId = f.id;
                        widget.scope.state.pickedSpreadsheetTitle = f.title;
                      }),
                    ),
                  ),
          ],
          const Spacer(),
          if (widget.scope.state.destination == 'existing' &&
              !GoogleSheetsService.instance.isSignedIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Sign in to choose a spreadsheet from Google Drive.',
                style: SsText.caption(color: c.muted),
              ),
            ),
          SsButton(
            widget.scope.state.destination == 'local'
                ? 'Continue offline'
                : 'Continue with Google',
            onPressed: _continue,
          ),
        ],
      ),
    );
  }
}
