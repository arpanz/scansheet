import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/ss.dart';
import 'scan_session.dart';

/// The ten column kinds offered when building a sheet
/// (docs/design/mocks/AddColumn.dc.html). "Number" and "Text" are both
/// stored as [SessionColumnType.manual], told apart by `isNumeric`.
enum ColumnKind {
  scan(
    'Scan',
    'SCAN',
    SsTagKind.scan,
    LucideIcons.scanLine,
    'Serial no.',
    'Filled from the camera. Add more than one to scan, say, a product and its serial into the same row.',
  ),
  product(
    'Product info',
    'AUTO',
    SsTagKind.auto,
    LucideIcons.package,
    'Product name',
    'Looks the barcode up in open product databases and fills in name, brand and size. Works for most packaged goods; blank if not found.',
  ),
  pickList(
    'Pick-list',
    'LIST',
    SsTagKind.list,
    LucideIcons.list,
    'Condition',
    'One tap from a fixed set of choices. The default is already picked, so a normal scan needs no typing.',
  ),
  number(
    'Number',
    'COUNT',
    SsTagKind.neutral,
    LucideIcons.plus,
    'Qty',
    'Shows a – / + stepper on every scan. Set the step and starting value.',
  ),
  text(
    'Text',
    'TEXT',
    SsTagKind.neutral,
    LucideIcons.textAlignStart,
    'Note',
    'Free typing, optional. It never blocks the next scan.',
  ),
  readText(
    'Read text',
    'READ',
    SsTagKind.neutral,
    LucideIcons.scanText,
    'Expiry date',
    'Point at printed text, like an expiry date or serial number, and tap the words to keep. Read on the phone, nothing uploaded.',
  ),
  time(
    'Date & time',
    'TIME',
    SsTagKind.neutral,
    LucideIcons.clock,
    'Scanned at',
    'Filled in automatically the moment the code is read.',
  ),
  location(
    'Location',
    'GPS',
    SsTagKind.neutral,
    LucideIcons.mapPin,
    'Location',
    'GPS at scan time. ScanSheet asks for location only when a sheet has this column.',
  ),
  fixed(
    'Same value',
    'FIXED',
    SsTagKind.neutral,
    LucideIcons.tag,
    'Aisle',
    'The same value on every row, like a shelf, gate or batch number.',
  ),
  auto(
    'Auto no.',
    '#1,2,3',
    SsTagKind.neutral,
    LucideIcons.hash,
    'Row no.',
    'Numbers each row 1, 2, 3… in the order you scan.',
  );

  final String label;
  final String tag;
  final SsTagKind tagKind;
  final IconData icon;
  final String defaultName;
  final String hint;

  const ColumnKind(
    this.label,
    this.tag,
    this.tagKind,
    this.icon,
    this.defaultName,
    this.hint,
  );

  static ColumnKind of(SessionColumn c) => switch (c.type) {
    SessionColumnType.scan => scan,
    SessionColumnType.productInfo => product,
    SessionColumnType.pickList => pickList,
    SessionColumnType.manual => c.isNumeric ? number : text,
    SessionColumnType.readText => readText,
    SessionColumnType.timestamp => time,
    SessionColumnType.location => location,
    SessionColumnType.fixed => fixed,
    SessionColumnType.increment => auto,
  };

  SessionColumnType get type => switch (this) {
    scan => SessionColumnType.scan,
    product => SessionColumnType.productInfo,
    pickList => SessionColumnType.pickList,
    number || text => SessionColumnType.manual,
    readText => SessionColumnType.readText,
    time => SessionColumnType.timestamp,
    location => SessionColumnType.location,
    fixed => SessionColumnType.fixed,
    auto => SessionColumnType.increment,
  };

  /// One-line description shown under a column in New sheet.
  static String detailOf(
    SessionColumn c, {
    bool firstScan = false,
  }) => switch (of(c)) {
    scan => firstScan ? 'Camera · used to spot repeats' : 'Camera',
    product => 'Name filled in from the barcode',
    pickList =>
      c.choices
          .map(
            (v) =>
                v == (c.defaultValue ?? c.choices.first) ? '$v (default)' : v,
          )
          .join(' · '),
    number =>
      'Number · steps of ${c.stepSize} · starts at ${c.defaultValue ?? c.stepSize}',
    text => 'Typed, optional',
    readText => 'Printed text, read on the phone',
    time => 'Filled in when scanned',
    location => 'GPS at scan time',
    fixed =>
      (c.fixedValue ?? '').isEmpty
          ? 'Same on every row'
          : 'Always “${c.fixedValue}”',
    auto => '1, 2, 3… in scan order',
  };
}
