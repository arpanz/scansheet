import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/scan/models/scan_session.dart';
import '../services/lookup_list_service.dart';
import '../services/scan_session_service.dart';
import '../services/template_service.dart';

/// Store-screenshot data: `flutter run --dart-define=DEMO_SEED=true` replaces
/// every sheet and list with a believable working day. Debug builds only.
class DemoSeed {
  static const enabled = bool.fromEnvironment('DEMO_SEED');

  /// Stands in for the camera: a photo pushed with
  /// `adb shell run-as com.livinlabs.scansheet cp … files/demo_camera.png`
  /// (the photo is docs/store/demo_camera.png).
  static Widget cameraFeed() => Image.file(
    File('/data/user/0/com.livinlabs.scansheet/files/demo_camera.png'),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );

  static Future<void> run() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    await prefs.setBool('is_premium_user', true);

    await ScanSessionService.clearAll();
    await Hive.box('sync_queue').clear();
    for (final l in LookupListService.all()) {
      await LookupListService.delete(l.id);
    }

    final now = DateTime.now();
    final rnd = Random(7);
    final templates = {
      for (final t in TemplateService.getBuiltInTemplates()) t.id: t,
    };

    // ── Staff roster, checked by Morning attendance ──
    const people = [
      ('EMP-0142', 'Rahul Verma', 'Packing'),
      ('EMP-0157', 'Priya Nair', 'Dispatch'),
      ('EMP-0163', 'Aman Gupta', 'Packing'),
      ('EMP-0171', 'Sneha Iyer', 'Quality'),
      ('EMP-0188', 'Vikram Singh', 'Dispatch'),
      ('EMP-0192', 'Fatima Sheikh', 'Packing'),
      ('EMP-0204', 'Arjun Mehta', 'Stores'),
      ('EMP-0216', 'Kavya Reddy', 'Quality'),
      ('EMP-0223', 'Rohan Das', 'Stores'),
      ('EMP-0231', 'Neha Joshi', 'Packing'),
      ('EMP-0245', 'Imran Khan', 'Dispatch'),
      ('EMP-0258', 'Ananya Rao', 'Quality'),
      ('EMP-0262', 'Suresh Kumar', 'Stores'),
      ('EMP-0277', 'Meera Pillai', 'Packing'),
      ('EMP-0283', 'Karan Malhotra', 'Dispatch'),
      ('EMP-0291', 'Divya Menon', 'Packing'),
      ('EMP-0305', 'Harpreet Kaur', 'Quality'),
      ('EMP-0312', 'Nikhil Bose', 'Stores'),
      ('EMP-0326', 'Pooja Shah', 'Dispatch'),
      ('EMP-0334', 'Aditya Kulkarni', 'Packing'),
      ('EMP-0347', 'Riya Banerjee', 'Quality'),
      ('EMP-0351', 'Sanjay Patel', 'Stores'),
      ('EMP-0368', 'Lakshmi Narayan', 'Packing'),
      ('EMP-0374', 'Zoya Ahmed', 'Dispatch'),
      ('EMP-0389', 'Manoj Tiwari', 'Stores'),
      ('EMP-0393', 'Tanvi Desai', 'Quality'),
      ('EMP-0402', 'Gaurav Chauhan', 'Packing'),
      ('EMP-0415', 'Ishita Roy', 'Dispatch'),
      ('EMP-0427', 'Deepak Yadav', 'Stores'),
      ('EMP-0436', 'Sara Thomas', 'Packing'),
    ];
    final roster = LookupList(
      id: 'demo_roster',
      name: 'Staff roster',
      headers: const ['Badge', 'Name', 'Department'],
      rows: [
        for (final p in people) [p.$1, p.$2, p.$3],
      ],
      codeColumn: 0,
      fillColumns: const [1, 2],
      expectedColumn: null,
      source: const ListSource.sheets(
        spreadsheetId: 'demo_hr',
        spreadsheetTitle: 'HR roster',
        tab: 'Staff',
      ),
      importedAt: now.subtract(const Duration(days: 3)),
    );
    await LookupListService.save(roster);

    // ── Stock list, checked by Stock count ──
    const items = [
      ('8901234500017', 'Basmati rice 5 kg', 24),
      ('8901234500024', 'Sunflower oil 1 L', 36),
      ('8901234500031', 'Whole wheat atta 10 kg', 12),
      ('8901234500048', 'Toor dal 1 kg', 40),
      ('8901234500055', 'Green tea 100 bags', 18),
      ('8901234500062', 'Dish soap 750 ml', 30),
      ('8901234500079', 'Paper towels 6 pack', 15),
      ('8901234500086', 'Instant coffee 200 g', 20),
      ('8901234500093', 'Rolled oats 1 kg', 22),
      ('8901234500109', 'Honey 500 g', 16),
      ('8901234500116', 'Peanut butter 340 g', 14),
      ('8901234500123', 'Laundry liquid 2 L', 10),
      ('8901234500130', 'Sea salt 1 kg', 28),
      ('8901234500147', 'Brown sugar 1 kg', 25),
    ];
    final stockList = LookupList(
      id: 'demo_stock',
      name: 'Stock on hand',
      headers: const ['SKU', 'Item', 'Expected'],
      rows: [
        for (final i in items) [i.$1, i.$2, '${i.$3}'],
      ],
      codeColumn: 0,
      fillColumns: const [1],
      expectedColumn: 2,
      source: const ListSource.file('stock_october.xlsx'),
      importedAt: now.subtract(const Duration(days: 1)),
    );
    await LookupListService.save(stockList);

    String stamp(DateTime t) => t.toString().substring(0, 19);

    Future<void> sheet({
      required String id,
      required String name,
      required String templateId,
      required String icon,
      required DateTime start,
      required List<String> Function(DateTime at, int i) row,
      required int count,
      required Duration gap,
      List<SessionColumn>? columns,
      SessionDestination destination = SessionDestination.googleSheets,
      String? lookupListId,
      bool active = false,
    }) async {
      final cols = columns ?? templates[templateId]!.columns;
      await ScanSessionService.saveSession(
        ScanSession(
          id: id,
          name: name,
          columns: cols,
          createdAt: start.subtract(const Duration(minutes: 3)),
          completedAt: active ? null : start.add(gap * count),
          isActive: active,
          destination: destination,
          templateId: templateId,
          spreadsheetId: destination == SessionDestination.googleSheets
              ? 'demo_$id'
              : null,
          sheetName: destination == SessionDestination.googleSheets
              ? 'Sheet1'
              : null,
          iconName: icon,
          lookupListId: lookupListId,
          unknownCodes: lookupListId == null
              ? UnknownCodes.ask
              : UnknownCodes.flag,
          showScanConfirmation: true,
        ),
      );
      for (var i = 0; i < count; i++) {
        final jitter = Duration(seconds: rnd.nextInt(gap.inSeconds ~/ 2 + 1));
        final at = start.add(gap * i + jitter);
        final values = row(at, i);
        await ScanSessionService.rowsBox.put('${id}_$i', {
          'rowIndex': i,
          'values': values,
          'scannedAt': at.toIso8601String(),
          'barcodeFormat': 'code128',
          'notOnList': false,
        });
      }
    }

    // Stock count in progress, the sheet the Scan button reopens.
    final stockOrder = [0, 1, 3, 2, 5, 4, 6, 8, 7, 9, 10];
    final stockCols = templates['builtin_stock_count']!.columns
        .map((c) => c.name == 'Bin' ? c.withValue('B4-12') : c)
        .toList();
    await sheet(
      id: 'demo_stock_count',
      name: 'Stock count · Bay 4',
      templateId: 'builtin_stock_count',
      icon: 'inventory_2_rounded',
      columns: stockCols,
      lookupListId: stockList.id,
      active: true,
      start: now.subtract(const Duration(minutes: 34)),
      gap: const Duration(minutes: 3),
      count: stockOrder.length,
      row: (at, i) {
        final item = items[stockOrder[i]];
        final qty = i == 4 ? item.$3 - 2 : item.$3;
        return [item.$1, item.$2, '$qty', 'B4-12', stamp(at)];
      },
    );

    // Attendance from this morning: 24 of 30 in.
    final order = List.generate(people.length, (i) => i)..shuffle(rnd);
    final present = order.take(24).toList();
    await sheet(
      id: 'demo_attendance',
      name: 'Morning attendance',
      templateId: 'builtin_attendance',
      icon: 'people_rounded',
      lookupListId: roster.id,
      start: DateTime(now.year, now.month, now.day, 8, 52),
      gap: const Duration(seconds: 25),
      count: present.length,
      row: (at, i) {
        final p = people[present[i]];
        return [p.$1, p.$2, p.$3, 'In', stamp(at)];
      },
    );

    // Yesterday's asset audit, saved as Excel.
    const conditions = ['Good', 'Good', 'Good', 'Good', 'Damaged', 'Good'];
    const rooms = ['Floor 3 · East', 'Floor 3 · West', 'Meeting room B'];
    const kinds = ['Laptop', 'Monitor', 'Desk phone', 'Projector', 'Chair'];
    final yesterday = now.subtract(const Duration(days: 1));
    await sheet(
      id: 'demo_assets',
      name: 'Asset audit · 3rd floor',
      templateId: 'builtin_asset_tracking',
      icon: 'devices_rounded',
      destination: SessionDestination.localXlsx,
      start: DateTime(yesterday.year, yesterday.month, yesterday.day, 15, 10),
      gap: const Duration(seconds: 70),
      count: 52,
      row: (at, i) => [
        'AST-${(3100 + i * 7).toString().padLeft(5, '0')}',
        '${kinds[i % kinds.length]} ${(i ~/ kinds.length) + 1}',
        conditions[i % conditions.length],
        rooms[(i ~/ 18) % rooms.length],
        stamp(at),
      ],
    );

    // Last weekend's event check-in, CSV.
    const attendees = [
      'Ayesha Kapoor',
      'Rahul Jain',
      'Nisha Varghese',
      'Omar Siddiqui',
      'Tara Bhatt',
      'Kabir Anand',
      'Shreya Ghosh',
      'Vivek Rana',
    ];
    final saturday = now.subtract(Duration(days: (now.weekday + 1) % 7 + 1));
    await sheet(
      id: 'demo_event',
      name: 'Book fair check-in',
      templateId: 'builtin_event_checkin',
      icon: 'confirmation_number_rounded',
      destination: SessionDestination.localCsv,
      start: DateTime(saturday.year, saturday.month, saturday.day, 10),
      gap: const Duration(seconds: 40),
      count: 128,
      row: (at, i) => [
        'BF26-${(48210 + i * 13)}',
        attendees[i % attendees.length],
        stamp(at),
        i.isEven ? 'Main' : 'Gate 2',
      ],
    );
  }
}
