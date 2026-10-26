// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/services/list_check.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/lookup_list_service.dart';
import '../../../core/services/product_lookup_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/scan_sound.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/services/team_service.dart';
import '../../../core/services/usage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ss.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/utils/demo_seed.dart';
import '../models/scan_session.dart';
import '../../sheet/sheet_view_screen.dart';
import 'done_for_now_screen.dart';
import 'scan_help_screen.dart';
import '../widgets/scanner/scan_confirm_sheet.dart';
import '../widgets/scanner/read_text_sheet.dart';
import '../widgets/scanner/value_sheet.dart';

class ScanSessionScreen extends StatefulWidget {
  final ScanSession session;
  const ScanSessionScreen({super.key, required this.session});

  @override
  State<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

/// "Not on list" on the dark scanner.
const _amber = Color(0xFFF2A93B);

class _ScanSessionScreenState extends State<ScanSessionScreen> {
  late final MobileScannerController _camera;
  final _visitStarted = DateTime.now();
  late ScanSession _session;
  late final bool _vibrate, _beep, _trigger;
  List<SessionRow> _rows = [];
  int _activeScanColumnIndex = 0;
  int _visitRows = 0;
  int _zoom = 0;
  bool _torch = false, _processing = false, _success = false;
  bool _multiPaused = false, _cameraError = false, _sheetOpen = false;
  bool _toastNeutral = false, _toastWarn = false;
  bool _locationNoticeShown = false;
  LookupList? _list;
  String? _lastValue, _toast;
  // Same value columns: the next code sets this column ("Scan a label"),
  // and the last change, so Undo can put the old value back.
  int? _captureLabelFor;
  ({int column, String previous})? _valueUndo;
  // The row the last scan added or bumped; the panel shows and edits it.
  int? _touchedRow;
  // "Volume buttons scan": the camera reads one code until this time.
  DateTime? _armedUntil;
  // Handheld and Bluetooth scanners type the code, then Enter or Tab.
  final _typed = StringBuffer();
  DateTime? _typedAt;
  DateTime? _lastAt;
  Timer? _toastTimer;
  List<Barcode> _multi = [];
  Size? _captureSize;
  SessionRow? _pendingRow;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    // Scanning into a finished sheet reopens it.
    if (!_session.isActive) {
      _session = _session.copyWith(isActive: true);
      ScanSessionService.saveSession(_session);
    }
    _rows = ScanSessionService.getRows(_session.id);
    _list = LookupListService.get(_session.lookupListId);
    _refreshList();
    if (_session.teamCode != null) _joinTeam();
    final prefs = context.read<ScanningPreferences>();
    _vibrate = prefs.vibrateEnabled;
    _beep = prefs.soundEnabled;
    _trigger =
        prefs.volumeScan && defaultTargetPlatform == TargetPlatform.android;
    if (_beep) ScanSound.warmUp();
    HardwareKeyboard.instance.addHandler(_onKey);
    _torch = prefs.torchDefault;
    _camera = MobileScannerController(torchEnabled: _torch);
    _resetPending();
    if (_hasLocation) {
      final location = LocationService.instance;
      location.status.addListener(_onLocationStatus);
      location.start();
    }
    if (_session.columns.any(
      (c) => c.type == SessionColumnType.fixed && c.askAtStart,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askStartValues());
    }
  }

  /// Team sheet: picks up the owner's newer list, warns if sharing
  /// stopped, and shows this phone as scanning.
  Future<void> _joinTeam() async {
    final team = await TeamService.instance.refresh(_session);
    if (!mounted || team == null) return;
    if (!team.active) {
      _flash('${team.ownerName} stopped sharing', warn: true);
      return;
    }
    final session = ScanSessionService.getSession(_session.id);
    if (session != null && session.lookupListId != _session.lookupListId) {
      setState(() {
        _session = session;
        _list = LookupListService.get(session.lookupListId);
      });
    }
    TeamService.instance.reportPresence(
      _session,
      scanning: true,
      rows: _rows.length,
    );
  }

  @override
  void dispose() {
    if (_session.teamCode != null) {
      TeamService.instance.reportPresence(
        _session,
        scanning: false,
        rows: _rows.length,
      );
    }
    if (_hasLocation) {
      LocationService.instance.status.removeListener(_onLocationStatus);
      LocationService.instance.stop();
    }
    _toastTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _camera.dispose();
    super.dispose();
  }

  bool get _hasLocation =>
      _session.columns.any((c) => c.type == SessionColumnType.location);

  /// Said once, never a dialog: rows still save, just without a location.
  void _onLocationStatus() {
    final text = switch (LocationService.instance.status.value) {
      LocationStatus.off => 'Location is off · rows save without it',
      LocationStatus.denied => 'No location access · rows save without it',
      _ => null,
    };
    if (text != null && !_locationNoticeShown) {
      _locationNoticeShown = true;
      _flash(text, neutral: true);
    }
  }

  bool get _armed =>
      !_trigger ||
      (_armedUntil != null && DateTime.now().isBefore(_armedUntil!));

  /// Volume press or a tap on the camera: read the next code within 2 s.
  void _arm() {
    if (!_trigger || _sheetOpen) return;
    HapticFeedback.selectionClick();
    setState(
      () => _armedUntil = DateTime.now().add(const Duration(seconds: 2)),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_armed) setState(() => _armedUntil = null);
    });
  }

  /// Keys while the scanner is on top: volume buttons as the trigger, and
  /// codes typed by a handheld or Bluetooth scanner paired as a keyboard.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    if (_trigger &&
        (key == LogicalKeyboardKey.audioVolumeDown ||
            key == LogicalKeyboardKey.audioVolumeUp)) {
      if (event is KeyDownEvent) _arm();
      return true; // don't change the volume
    }
    // Sheets and dialogs on top have their own text fields.
    if (_sheetOpen || ModalRoute.of(context)?.isCurrent != true) return false;
    final now = DateTime.now();
    // Scanners type far faster than people; a pause starts a new code.
    if (_typedAt != null &&
        now.difference(_typedAt!) > const Duration(milliseconds: 500)) {
      _typed.clear();
    }
    _typedAt = now;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      final code = _typed.toString().trim();
      _typed.clear();
      if (code.isEmpty) return false;
      _lastAt = null;
      _handleValue(code, format: 'SCANNER');
      return true;
    }
    final char = event.character;
    if (char == null || char.isEmpty || char.codeUnitAt(0) < 32) return false;
    _typed.write(char);
    return true;
  }

  /// A Google Sheets list is read again each time scanning starts; offline,
  /// the copy on the phone is used.
  Future<void> _refreshList() async {
    final list = _list;
    if (list == null || !list.source.isSheets) return;
    final updated = await LookupListService.refresh(
      list,
      pro: UsageService.instance.isPro,
    );
    if (updated == null) return;
    TeamService.instance.pushList(_session, updated);
    if (mounted) setState(() => _list = updated);
  }

  /// Haptics and the beep for one outcome; [notice] for no new row, [warn]
  /// for a code that isn't on the list.
  void _feedback({bool notice = false, bool warn = false}) {
    if (_beep) notice || warn ? ScanSound.notice() : ScanSound.ok();
    if (!_vibrate) return;
    if (warn) {
      HapticFeedback.heavyImpact();
      Future.delayed(
        const Duration(milliseconds: 140),
        HapticFeedback.heavyImpact,
      );
    } else if (notice) {
      HapticFeedback.lightImpact();
      Future.delayed(
        const Duration(milliseconds: 120),
        HapticFeedback.lightImpact,
      );
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  void _resetPending() {
    _activeScanColumnIndex = 0;
    _pendingRow = _session.buildEmptyRow(_rows.length);
  }

  void _detect(BarcodeCapture capture) {
    if (_processing || _sheetOpen || _multiPaused || !_armed) return;
    if (_trigger && capture.barcodes.isNotEmpty) _armedUntil = null;
    final distinct = <String, Barcode>{};
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim() ?? '';
      if (value.isNotEmpty) distinct.putIfAbsent(value, () => barcode);
    }
    if (distinct.length > 1) {
      _camera.stop();
      setState(() {
        _multi = distinct.values.toList();
        _captureSize = capture.size;
        _multiPaused = true;
      });
      return;
    }
    if (distinct.isNotEmpty) {
      _handleValue(
        distinct.keys.first,
        format: distinct.values.first.format.name.toUpperCase(),
      );
    }
  }

  Future<void> _handleValue(
    String value, {
    bool skipConfirmation = false,
    String? format,
  }) async {
    final now = DateTime.now();
    if (_processing ||
        _sheetOpen ||
        (_lastValue == value &&
            _lastAt != null &&
            now.difference(_lastAt!) < const Duration(milliseconds: 1200)))
      return;
    _lastValue = value;
    _lastAt = now;
    final label = _labelTarget(value);
    if (label != null) return _setValue(label.column, label.value);
    final scans = _session.scanColumnIndices;
    if (scans.isEmpty) return;
    setState(() => _processing = true);

    // The list check comes before repeats, so a code that isn't on the list
    // never bumps a Qty.
    final list = _list;
    final listRow = list != null && _activeScanColumnIndex == 0
        ? list.lookup(value)
        : null;
    var notOnList = false;
    if (list != null && _activeScanColumnIndex == 0 && listRow == null) {
      switch (_session.unknownCodes) {
        case UnknownCodes.skip:
          _feedback(warn: true);
          _flash('$value isn’t on the list', warn: true);
          return;
        case UnknownCodes.flag:
          notOnList = true;
        case UnknownCodes.ask:
          _processing = false;
          _sheetOpen = true;
          _feedback(warn: true);
          await _camera.stop();
          if (!mounted) return;
          final add = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(LucideIcons.circleAlert, color: _amber),
              title: const Text('Not on the list'),
              content: Text('$value isn’t on ${list.name}.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Skip'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add anyway'),
                ),
              ],
            ),
          );
          _sheetOpen = false;
          if (add != true) {
            _resume();
            return;
          }
          _processing = true;
          notOnList = true;
      }
    }

    // Repeats add to Qty has precedence over the warning dialog.
    final qtyIndex = _session.qtyColumnIndex;
    final firstScan = scans.first;
    // With a list, a repeat matches the way the list does (emp-1 = EMP-1).
    bool same(SessionRow r, int i) =>
        r.values.length > i &&
        (list == null
            ? r.values[i] == value
            : LookupList.normalize(r.values[i]) == LookupList.normalize(value));
    final existing = _rows.where((r) => same(r, firstScan)).firstOrNull;
    if (_session.mergeRepeats && qtyIndex >= 0 && existing != null) {
      await _mergeQty(existing, _session.columns[qtyIndex].stepSize);
      return;
    }
    // Text and Number columns never stop the camera: they're filled in from
    // the bottom panel afterwards. Only "Review each scan" opens the sheet.
    final showSheet = !skipConfirmation && _session.showScanConfirmation;
    final colIndex = scans[_activeScanColumnIndex.clamp(0, scans.length - 1)];
    // With the confirm sheet, repeats are handled by its banner instead.
    if (!showSheet &&
        _session.warnDuplicates &&
        _rows.any((r) => same(r, colIndex))) {
      _processing = false;
      _sheetOpen = true;
      _feedback(notice: true);
      await _camera.stop();
      if (!mounted) return;
      final who = listRow == null ? value : list!.titleFor(listRow);
      final at = existing == null
          ? ''
          : ' · ${TimeOfDay.fromDateTime(existing.scannedAt).format(context)}';
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already scanned'),
          content: Text('$who is already here$at.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add again'),
            ),
          ],
        ),
      );
      _sheetOpen = false;
      if (add != true) {
        _resume();
        return;
      }
    }
    final values = List<String>.from(_pendingRow!.values)..[colIndex] = value;
    if (listRow != null) {
      for (final (i, col) in _session.columns.indexed) {
        if (col.type != SessionColumnType.fromList) continue;
        values[i] = list!.field(listRow, col.listField ?? col.name);
      }
    }
    final productIndex = _session.productColumnIndex;
    if (productIndex >= 0 && colIndex == firstScan) {
      values[productIndex] =
          await ProductLookupService.instance.lookup(value) ?? '';
      if (!mounted) return;
    }
    final updated = _pendingRow!.copyWith(
      values: values,
      barcodeFormat: format,
      notOnList: notOnList ? true : null,
    );
    final last = _activeScanColumnIndex == scans.length - 1;
    if (!last) {
      setState(() {
        _pendingRow = updated;
        _activeScanColumnIndex++;
        _processing = false;
      });
      return;
    }
    if (showSheet) {
      _pendingRow = updated;
      _processing = false;
      _sheetOpen = true;
      await _camera.stop();
      if (!mounted) return;
      final outcome = await showScanConfirmSheet(
        context,
        session: _session,
        row: updated,
        rowNumber: _rows.length + 1,
        duplicateOf: colIndex == firstScan ? existing : null,
      );
      _sheetOpen = false;
      switch (outcome) {
        case ConfirmAdd(:final row):
          await _commit(row);
        case ConfirmMerge(:final target, :final qty):
          await _mergeQty(target, qty);
        case null:
          if (mounted) setState(_resetPending);
      }
      if (mounted) _resume();
      return;
    }
    await _commit(updated);
  }

  Future<void> _commit(SessionRow row) async {
    final finalRow = row;
    await ScanSessionService.addRow(_session.id, finalRow);
    if (_hasLocation) unawaited(_fillLocation(_session, finalRow.rowIndex));
    if (!mounted) return;
    setState(() {
      _rows = ScanSessionService.getRows(_session.id);
      _visitRows++;
      _processing = false;
      _success = true;
      _valueUndo = null;
      _touchedRow = finalRow.rowIndex;
      _resetPending();
    });
    final rowNo = finalRow.rowIndex + 1;
    if (_session.teamCode != null) {
      TeamService.instance.reportPresence(
        _session,
        scanning: true,
        rows: _rows.length,
      );
    }
    if (finalRow.notOnList) {
      _feedback(notice: true);
      _flash('Not on list · row $rowNo', warn: true);
      return;
    }
    _feedback();
    final title = _titleFor(finalRow);
    _flash(title == null ? 'Added · row $rowNo' : '$title · row $rowNo');
  }

  /// The list's name for a row's code ("Rahul Verma"), null if none.
  String? _titleFor(SessionRow row) {
    final list = _list;
    final scan = _session.scanColumnIndices.firstOrNull;
    if (list == null || scan == null || scan >= row.values.length) return null;
    final match = list.lookup(row.values[scan]);
    return match == null ? null : list.titleFor(match);
  }

  /// Location cells are filled after the row is saved, so a scan never
  /// waits for a fix or a place lookup. Runs on even if the scanner closes.
  static Future<void> _fillLocation(ScanSession session, int rowIndex) async {
    final location = LocationService.instance;
    final columns = [
      for (final (i, c) in session.columns.indexed)
        if (c.type == SessionColumnType.location) (i, c.locationFormat),
    ];
    final pos = await location.position();
    final place = pos != null && columns.any((c) => c.$2.needsPlace)
        ? await location.placeAt(pos)
        : null;
    // Re-read: the row may have been edited or undone meanwhile.
    final current = ScanSessionService.getRows(
      session.id,
    ).where((r) => r.rowIndex == rowIndex).firstOrNull;
    if (current == null) return;
    final values = List.of(current.values);
    for (final (i, format) in columns) {
      if (i >= values.length || values[i].isNotEmpty) continue;
      values[i] = pos == null
          ? location.unavailableText ?? 'Location unavailable'
          : formatLocation(format, pos.latitude, pos.longitude, place);
    }
    await ScanSessionService.updateRow(
      session.id,
      current.copyWith(values: values),
    );
  }

  /// "Repeats add to Qty": bump the existing row instead of adding one.
  Future<void> _mergeQty(SessionRow target, int add) async {
    final qtyIndex = _session.qtyColumnIndex;
    final oldQty = int.tryParse(target.values[qtyIndex].trim()) ?? 1;
    final nextQty = oldQty + add;
    final values = List<String>.from(target.values)..[qtyIndex] = '$nextQty';
    await ScanSessionService.updateRow(
      _session.id,
      target.copyWith(values: values),
    );
    if (_beep) ScanSound.ok();
    if (_vibrate) {
      HapticFeedback.selectionClick();
      Future.delayed(
        const Duration(milliseconds: 90),
        HapticFeedback.selectionClick,
      );
    }
    if (!mounted) return;
    setState(() {
      _rows = ScanSessionService.getRows(_session.id);
      _valueUndo = null;
      _touchedRow = target.rowIndex;
      _resetPending();
    });
    _flash('Qty $nextQty · row ${target.rowIndex + 1}');
  }

  /// A code that sets a Same value column instead of adding a row: the next
  /// code after "Scan a label", or one starting with the column's prefix.
  ({int column, String value})? _labelTarget(String code) {
    final capture = _captureLabelFor;
    if (capture != null) {
      _captureLabelFor = null;
      return (column: capture, value: code);
    }
    return _session.labelFor(code);
  }

  /// Switches a Same value column for the rows scanned from now on.
  Future<void> _setValue(int index, String value, {bool undo = false}) async {
    _processing = true;
    final col = _session.columns[index];
    final previous = col.fixedValue ?? '';
    if (value == previous) {
      _flash('${col.name} is already $value', neutral: true);
      return;
    }
    final columns = List.of(_session.columns)
      ..[index] = undo ? col.copyWith(fixedValue: value) : col.withValue(value);
    final changed = _session.copyWith(columns: columns);
    await ScanSessionService.saveSession(changed);
    if (!mounted) return;
    setState(() {
      _session = changed;
      // A row half-way through its scan columns takes the new value too.
      final pending = _pendingRow;
      if (pending != null) {
        _pendingRow = pending.copyWith(
          values: List.of(pending.values)..[index] = value,
        );
      }
      _valueUndo = undo ? null : (column: index, previous: previous);
    });
    _feedback(notice: true);
    _flash(
      undo ? '${col.name} back to $value' : '${col.name} is now $value',
      neutral: true,
    );
  }

  Future<void> _changeValue(int index) async {
    _sheetOpen = true;
    await _camera.stop();
    if (!mounted) return;
    final choice = await showValueSheet(
      context,
      column: _session.columns[index],
    );
    _sheetOpen = false;
    await _applyValueChoice(index, choice);
    if (mounted) _resume();
  }

  Future<void> _applyValueChoice(int index, ValueChoice? choice) async {
    switch (choice) {
      case ValueSet(:final value):
        await _setValue(index, value);
      case ValueScanLabel():
        if (mounted) setState(() => _captureLabelFor = index);
      case null:
        break;
    }
  }

  /// "Ask when scanning starts": one sheet per column, before the first scan.
  /// Choosing "Scan a label" stops asking; the rest keep their values.
  Future<void> _askStartValues() async {
    _sheetOpen = true;
    await _camera.stop();
    for (var i = 0; i < _session.columns.length; i++) {
      final col = _session.columns[i];
      if (col.type != SessionColumnType.fixed || !col.askAtStart) continue;
      if (!mounted) return;
      final choice = await showValueSheet(context, column: col, starting: true);
      await _applyValueChoice(i, choice);
      if (choice is ValueScanLabel) break;
    }
    _sheetOpen = false;
    _resume();
  }

  void _flash(String message, {bool neutral = false, bool warn = false}) {
    if (!mounted) return;
    setState(() {
      _toast = message;
      _toastNeutral = neutral;
      _toastWarn = warn;
      _success = !neutral && !warn;
      _processing = false;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 1), () {
      if (mounted)
        setState(() {
          _toast = null;
          _success = false;
        });
    });
  }

  Future<void> _resume() async {
    if (mounted) {
      setState(() => _processing = false);
      await _camera.start();
    }
  }

  Future<void> _undo() async {
    final change = _valueUndo;
    if (change != null) {
      return _setValue(change.column, change.previous, undo: true);
    }
    if (_rows.isEmpty) return;
    await ScanSessionService.deleteRow(_session.id, _rows.last.rowIndex);
    if (mounted)
      setState(() => _rows = ScanSessionService.getRows(_session.id));
  }

  Future<void> _toggleMerge(bool value) async {
    final changed = _session.copyWith(mergeRepeats: value);
    await ScanSessionService.saveSession(changed);
    if (mounted) setState(() => _session = changed);
  }

  Future<void> _typeCode() async {
    _sheetOpen = true;
    await _camera.stop();
    if (!mounted) return;
    final value = await showSsSheet<String>(
      context,
      builder: (_) => const _TypeCodeSheet(),
    );
    _sheetOpen = false;
    if (value != null && value.isNotEmpty) {
      _lastAt = null;
      await _handleValue(value);
    }
    if (mounted) _resume();
  }

  Future<void> _readText() async {
    _sheetOpen = true;
    await _camera.stop();
    if (!mounted) return;
    final value = await captureText(context);
    _sheetOpen = false;
    if (value != null && value.isNotEmpty && mounted) {
      _lastAt = null;
      await _handleValue(value);
    }
    if (mounted) _resume();
  }

  Future<void> _openSheet() async {
    _sheetOpen = true;
    await _camera.stop();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(FadeSlideRoute(page: SheetViewScreen(session: _session)));
    _sheetOpen = false;
    if (!mounted) return;
    // The sheet may have been renamed, shared or left from there.
    final latest = ScanSessionService.getSession(_session.id) ?? _session;
    final joined = latest.teamCode != null && _session.teamCode == null;
    setState(() {
      _session = latest;
      _rows = ScanSessionService.getRows(_session.id);
    });
    if (joined) _joinTeam();
    _resume();
  }

  Future<void> _done() async {
    if (_visitRows == 0 && _rows.isEmpty) return _showHelp();
    await _camera.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      FadeSlideRoute(
        page: DoneForNowScreen(
          session: _session,
          addedThisVisit: _visitRows,
          totalRows: _rows.length,
          visitStarted: _visitStarted,
        ),
      ),
    );
    if (mounted) _resume();
  }

  Future<void> _close() async {
    if (_rows.isEmpty) return _showHelp();
    if (mounted) Navigator.pop(context);
  }

  /// "No scan this time" — act on what the user picked.
  Future<void> _showHelp() async {
    _sheetOpen = true;
    await _camera.stop();
    if (!mounted) return;
    final choice = await Navigator.of(
      context,
    ).push<ScanHelpChoice>(FadeSlideRoute(page: const ScanHelpScreen()));
    _sheetOpen = false;
    if (!mounted) return;
    switch (choice) {
      case ScanHelpChoice.torch:
        await _resume();
        if (!_torch) {
          await _camera.toggleTorch();
          if (mounted) setState(() => _torch = true);
        }
      case ScanHelpChoice.type:
        await _typeCode(); // resumes the camera when the sheet closes
      case ScanHelpChoice.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
      case ScanHelpChoice.close:
        Navigator.pop(context);
      case null:
        await _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final warn = _toast != null && _toastWarn;
    final cornerColor = warn
        ? _amber
        : _success
        ? SsColors.brandLime
        : Colors.white.withValues(alpha: .8);
    final list = _list;
    final check = list == null ? null : ListCheck(list, _session, _rows);
    // Value changes and "Scan a label" use a white toast; rows use lime.
    final capture = _captureLabelFor;
    final toastText =
        _toast ??
        (capture == null
            ? null
            : 'Scan a ${_session.columns[capture].name.toLowerCase()} label') ??
        (!_trigger
            ? null
            : _armed
            ? 'Reading…'
            : 'Press volume or tap to scan');
    final neutral = _toast == null || _toastNeutral;
    final toastColor = warn
        ? _amber
        : neutral
        ? Colors.white
        : SsColors.brandLime;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Theme(
        data: AppTheme.darkTheme.copyWith(
          scaffoldBackgroundColor: SsColors.night,
        ),
        child: Scaffold(
          backgroundColor: SsColors.night,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _arm,
                child: kDebugMode && DemoSeed.enabled
                    ? DemoSeed.cameraFeed()
                    : MobileScanner(
                        controller: _camera,
                        onDetect: _detect,
                        errorBuilder: (ctx, error) {
                          if (!_cameraError) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !_cameraError)
                                setState(() => _cameraError = true);
                            });
                          }
                          return const ColoredBox(color: SsColors.night);
                        },
                      ),
              ),
              if (_multiPaused && _captureSize != null)
                LayoutBuilder(
                  builder: (ctx, box) {
                    final image = _captureSize!;
                    final scale = (box.maxWidth / image.width).clamp(
                      box.maxHeight / image.height,
                      double.infinity,
                    );
                    final dx = (box.maxWidth - image.width * scale) / 2;
                    final dy = (box.maxHeight - image.height * scale) / 2;
                    return Stack(
                      children: [
                        for (var i = 0; i < _multi.length; i++)
                          _barcodeBox(_multi[i], i, scale, dx, dy),
                      ],
                    );
                  },
                ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          _roundButton(LucideIcons.x, onTap: _close),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: _openSheet,
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  check == null
                                      ? '${_session.name}  ·  ${_rows.length}'
                                      : '${_session.name}  ·  '
                                            '${check.found}/${check.total}',
                                  style: SsText.sans(
                                    size: 14,
                                    weight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _roundButton(
                            LucideIcons.flashlight,
                            active: _torch,
                            onTap: () async {
                              await _camera.toggleTorch();
                              setState(() => _torch = !_torch);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _mode('Barcode', true),
                          GestureDetector(
                            onTap: _readText,
                            child: _mode('Read text', false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 36,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: toastText == null
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey(toastText),
                                height: 36,
                                padding: const EdgeInsets.only(
                                  left: 6,
                                  right: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: toastColor,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: toastColor.withValues(alpha: .25),
                                      blurRadius: 22,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: SsColors.brandInk,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        warn
                                            ? LucideIcons.circleAlert
                                            : neutral
                                            ? LucideIcons.tag
                                            : LucideIcons.check,
                                        color: warn
                                            ? _amber
                                            : neutral
                                            ? Colors.white
                                            : SsColors.brandLime,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      toastText,
                                      style: SsText.sans(
                                        size: 14,
                                        weight: FontWeight.w600,
                                        color: SsColors.brandInk,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 270,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: cornerColor.withValues(alpha: .22),
                            blurRadius: 40,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          SsScanCorner(
                            color: cornerColor,
                            left: true,
                            top: true,
                            size: 34,
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: SsScanCorner(
                              color: cornerColor,
                              left: false,
                              top: true,
                              size: 34,
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: SsScanCorner(
                              color: cornerColor,
                              left: true,
                              top: false,
                              size: 34,
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: SsScanCorner(
                              color: cornerColor,
                              left: false,
                              top: false,
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 82),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              setState(() => _zoom = i);
                              _camera.setZoomScale([0.0, .35, .8][i]);
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _zoom == i
                                    ? Colors.white
                                    : Colors.black.withValues(alpha: .45),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ['1×', '2×', '5×'][i],
                                style: SsText.mono(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: _zoom == i
                                      ? SsColors.brandInk
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (_cameraError) _cameraBlocked(),
              _bottomPanel(check),
              if (_multiPaused && _captureSize == null) _multiList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(
    IconData icon, {
    required VoidCallback onTap,
    bool active = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active
            ? SsColors.brandLime
            : Colors.white.withValues(alpha: .14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: active ? SsColors.brandInk : Colors.white,
        size: 20,
      ),
    ),
  );
  Widget _mode(String text, bool selected) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
    ),
    alignment: Alignment.center,
    child: Text(
      text,
      style: SsText.sans(
        size: 13,
        weight: FontWeight.w600,
        color: selected ? SsColors.brandInk : Colors.white,
      ),
    ),
  );
  Widget _barcodeBox(
    Barcode barcode,
    int index,
    double scale,
    double dx,
    double dy,
  ) {
    final points = barcode.corners
        .map((p) => Offset(p.dx * scale + dx, p.dy * scale + dy))
        .toList();
    if (points.isEmpty) return const SizedBox.shrink();
    final left = points.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
        right = points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final top = points.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
        bottom = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    return Positioned(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
      child: GestureDetector(
        onTap: () => _chooseBarcode(barcode),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: SsColors.brandLime, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.topLeft,
          child: CircleAvatar(
            radius: 13,
            backgroundColor: SsColors.brandLime,
            child: Text(
              '${index + 1}',
              style: SsText.mono(size: 13, color: SsColors.brandInk),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseBarcode(Barcode b) async {
    final v = b.rawValue?.trim();
    setState(() {
      _multi.clear();
      _multiPaused = false;
    });
    if (v?.isNotEmpty == true)
      await _handleValue(v!);
    else
      _resume();
  }

  Widget _multiList() => Positioned(
    left: 16,
    right: 16,
    bottom: 310,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SsColors.nightSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _multi.length; i++)
            ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(_multi[i].rawValue ?? ''),
              onTap: () => _chooseBarcode(_multi[i]),
            ),
          TextButton(
            onPressed: () async {
              final items = List<Barcode>.from(_multi);
              setState(() {
                _multi.clear();
                _multiPaused = false;
              });
              for (final b in items) {
                final v = b.rawValue?.trim();
                if (v?.isNotEmpty == true) {
                  _lastAt = null;
                  await _handleValue(v!, skipConfirmation: true);
                }
              }
              _resume();
            },
            child: Text('Add all ${_multi.length}'),
          ),
        ],
      ),
    ),
  );
  Widget _cameraBlocked() => Positioned.fill(
    child: ColoredBox(
      color: SsColors.night,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.cameraOff, size: 42, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Camera access is off',
                style: SsText.heading(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow camera access in Settings, or type your code instead.',
                textAlign: TextAlign.center,
                style: SsText.body(color: SsColors.nightText),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: Geolocator.openAppSettings,
                child: const Text('Open settings'),
              ),
              TextButton(
                onPressed: _typeCode,
                child: const Text('Type code instead'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _bottomPanel(ListCheck? check) {
    // The panel is drawn light in every theme (Scanner.dc.html).
    const c = SsColors.light;
    final last =
        _rows.where((r) => r.rowIndex == _touchedRow).firstOrNull ??
        _rows.lastOrNull;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Theme(
        data: AppTheme.lightTheme,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F6F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9CFC6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),
              if (check != null) ...[
                _listProgress(check),
                const SizedBox(height: 12),
              ],
              if (_session.columns.any(
                (c) => c.type == SessionColumnType.fixed,
              )) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _session.columns.length; i++)
                        if (_session.columns[i].type == SessionColumnType.fixed)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _valueChip(i),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Just scanned',
                      style: SsText.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: const Color(0xFF4A5550),
                      ),
                    ),
                  ),
                  if (_session.qtyColumnIndex >= 0) _mergeSwitch(),
                ],
              ),
              const SizedBox(height: 10),
              if (_multiPaused) ...[
                Text(
                  '${_multi.length} codes in view',
                  style: SsText.label(color: c.ink),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final items = List<Barcode>.from(_multi);
                    setState(() {
                      _multi.clear();
                      _multiPaused = false;
                    });
                    for (final b in items) {
                      final v = b.rawValue?.trim();
                      if (v?.isNotEmpty == true) {
                        _lastAt = null;
                        await _handleValue(v!, skipConfirmation: true);
                      }
                    }
                    _resume();
                  },
                  child: Text('Add all ${_multi.length}'),
                ),
              ] else ...[
                _lastRow(last),
                if (last != null && _session.manualColumnIndices.isNotEmpty)
                  ..._fieldsRow(last),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _typeCode,
                      icon: const Icon(LucideIcons.keyboard, size: 18),
                      label: const Text('Type code'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: c.ink,
                        side: BorderSide(color: c.strongBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _done,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: SsColors.brandInk,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Done for now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "12 not here yet" and a bar: how much of the list is scanned.
  Widget _listProgress(ListCheck check) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              check.notYet == 0
                  ? 'Everyone on the list is in'
                  : '${check.notYet} ${check.hasExpected ? 'not counted' : 'not here'} yet',
              style: SsText.sans(
                size: 13,
                weight: FontWeight.w600,
                color: const Color(0xFF4A5550),
              ),
            ),
          ),
          if (check.notOnList.isNotEmpty) ...[
            Text(
              '${check.notOnList.length} not on list',
              style: SsText.sans(
                size: 12,
                weight: FontWeight.w600,
                color: const Color(0xFFB4690E),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${check.found}/${check.total}',
            style: SsText.mono(size: 12, color: SsColors.brandInk),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: check.progress,
          minHeight: 6,
          color: SsColors.brandInk,
          backgroundColor: const Color(0xFFE3E6E0),
        ),
      ),
    ],
  );

  Widget _lastRow(SessionRow? row) {
    final value = row == null || row.values.isEmpty
        ? 'Scan a code to begin'
        : row.values[_session.scanColumnIndices.firstOrNull ?? 0];
    final title = row == null ? null : _titleFor(row);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E6E0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF9C8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.package,
              size: 20,
              color: SsColors.brandInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SsText.sans(
                      size: 15,
                      weight: FontWeight.w600,
                      color: SsColors.brandInk,
                    ),
                  ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.mono(size: 12, color: SsColors.brandInk),
                ),
                Text(
                  row == null
                      ? 'Ready to scan'
                      : row.notOnList
                      ? 'Not on list · row ${row.rowIndex + 1}'
                      : 'row ${row.rowIndex + 1}',
                  style: SsText.caption(
                    color: row?.notOnList ?? false
                        ? const Color(0xFFB4690E)
                        : const Color(0xFF5F6964),
                  ),
                ),
              ],
            ),
          ),
          AnimatedScale(
            scale: _success ? 1.15 : 1,
            duration: const Duration(milliseconds: 220),
            child: Text(
              '${_rows.length}',
              style: SsText.mono(
                size: 20,
                weight: FontWeight.w600,
                color: SsColors.brandInk,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _undo,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2EE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.undo2,
                size: 16,
                color: SsColors.brandInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Text and Number columns of the row just scanned, edited in place so the
  /// camera never stops: a stepper per Number, a tap-to-type chip per Text.
  List<Widget> _fieldsRow(SessionRow row) => [
    const SizedBox(height: 8),
    SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final i in _session.manualColumnIndices)
            if (i < row.values.length)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _session.columns[i].isNumeric
                    ? _numberField(row, i)
                    : _textField(row, i),
              ),
        ],
      ),
    ),
  ];

  Widget _fieldBox({required Widget child, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE3E6E0)),
          ),
          child: child,
        ),
      );

  Widget _numberField(SessionRow row, int index) {
    final col = _session.columns[index];
    final value = int.tryParse(row.values[index].trim()) ?? 0;
    return _fieldBox(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            col.name,
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: const Color(0xFF4A5550),
            ),
          ),
          const SizedBox(width: 6),
          _stepButton(
            LucideIcons.minus,
            '${col.name} down',
            value - col.stepSize < 0
                ? null
                : () => _editField(row, index, '${value - col.stepSize}'),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: SsText.mono(
                size: 16,
                weight: FontWeight.w600,
                color: SsColors.brandInk,
              ),
            ),
          ),
          _stepButton(
            LucideIcons.plus,
            '${col.name} up',
            () => _editField(row, index, '${value + col.stepSize}'),
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2EE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: onTap == null
                  ? const Color(0xFFB7BEB9)
                  : SsColors.brandInk,
            ),
          ),
        ),
      );

  Widget _textField(SessionRow row, int index) {
    final col = _session.columns[index];
    final value = row.values[index];
    return Semantics(
      button: true,
      label: '${col.name}: ${value.isEmpty ? 'empty' : value}, edit',
      child: _fieldBox(
        onTap: () => _typeField(row, index),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              col.name,
              style: SsText.sans(
                size: 13,
                weight: FontWeight.w500,
                color: const Color(0xFF4A5550),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                value.isEmpty ? 'Add' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SsText.sans(
                  size: 14,
                  weight: FontWeight.w600,
                  color: value.isEmpty
                      ? const Color(0xFF0B7D45)
                      : SsColors.brandInk,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _typeField(SessionRow row, int index) async {
    final col = _session.columns[index];
    _sheetOpen = true;
    final value = await showSsTextPrompt(
      context,
      title: col.name,
      label: 'Row ${row.rowIndex + 1}',
      initial: row.values[index],
    );
    _sheetOpen = false;
    if (value != null) await _editField(row, index, value.trim());
  }

  /// Saves one cell of an existing row; synced rows update in place.
  Future<void> _editField(SessionRow row, int index, String value) async {
    final current = _rows.where((r) => r.rowIndex == row.rowIndex).firstOrNull;
    if (current == null || current.values[index] == value) return;
    await ScanSessionService.updateRow(
      _session.id,
      current.copyWith(values: List.of(current.values)..[index] = value),
    );
    if (mounted) {
      setState(() => _rows = ScanSessionService.getRows(_session.id));
    }
  }

  /// "Bin  B-13 ▾": tap to change a Same value column (ScannerValue.dc.html).
  /// Highlighted right after a change and while waiting for its label.
  Widget _valueChip(int index) {
    final col = _session.columns[index];
    final value = col.fixedValue ?? '';
    final active = _valueUndo?.column == index || _captureLabelFor == index;
    return Semantics(
      button: true,
      label: '${col.name} ${value.isEmpty ? 'not set' : value}, change',
      child: GestureDetector(
        onTap: () => _changeValue(index),
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEEF9C8) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? SsColors.brandInk : const Color(0xFFD3D8D1),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                col.name,
                style: SsText.sans(
                  size: 14,
                  weight: FontWeight.w500,
                  color: const Color(0xFF4A5550),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value.isEmpty ? 'Set' : value,
                style: SsText.mono(
                  size: 14,
                  weight: FontWeight.w600,
                  color: SsColors.brandInk,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: SsColors.brandInk,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mergeSwitch() => GestureDetector(
    onTap: () => _toggleMerge(!_session.mergeRepeats),
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _session.mergeRepeats
            ? const Color(0xFFEEF9C8)
            : const Color(0xFFE9ECE6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _session.mergeRepeats
                  ? const Color(0xFF0B7D45)
                  : const Color(0xFFB7BEB9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Align(
              alignment: _session.mergeRepeats
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Repeats add to Qty',
            style: SsText.sans(
              size: 12,
              weight: FontWeight.w600,
              color: SsColors.brandInk,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Manual entry; runs the same flow as a scan. Owns its controller so it is
/// disposed only after the sheet's exit animation.
class _TypeCodeSheet extends StatefulWidget {
  const _TypeCodeSheet();

  @override
  State<_TypeCodeSheet> createState() => _TypeCodeSheetState();
}

class _TypeCodeSheetState extends State<_TypeCodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Type a code', style: SsText.section(color: c.ink)),
          const SizedBox(height: 4),
          Text(
            'For labels the camera can’t read.',
            style: SsText.sans(size: 13, color: c.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            style: SsText.mono(size: 16, color: c.ink),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Barcode or code'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          SsButton('Add row', onPressed: _submit),
        ],
      ),
    );
  }
}
