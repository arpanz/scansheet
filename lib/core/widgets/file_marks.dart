import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/scan/models/scan_session.dart';
import '../services/sheet_summary.dart';
import 'ss.dart';

/// ScanSheet's own marks for where rows are saved, drawn as one family
/// (assets/marks): a green page with a grid for Google Sheets, an X plate
/// on a banded sheet for Excel, a plain page with commas for CSV.
enum FileMark {
  sheets('google_sheets', 'Google Sheets'),
  excel('excel', 'Excel'),
  csv('csv', 'CSV');

  final String file;
  final String label;
  const FileMark(this.file, this.label);

  String get asset => 'assets/marks/$file.svg';

  static FileMark of(SessionDestination destination) => switch (destination) {
    SessionDestination.googleSheets => sheets,
    SessionDestination.localXlsx => excel,
    SessionDestination.localCsv => csv,
  };

  /// "stock.xlsx" → Excel, "staff.csv" → CSV; null for anything else.
  static FileMark? forFile(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) return excel;
    if (lower.endsWith('.csv')) return csv;
    return null;
  }

  /// Decodes the marks once at start-up so lists don't pop them in.
  static Future<void> precache() => Future.wait([
    for (final mark in values) SvgAssetLoader(mark.asset).loadBytes(null),
  ]);
}

/// A [FileMark] on its own, [size] tall.
class SsFileMark extends StatelessWidget {
  final FileMark mark;
  final double size;
  const SsFileMark(this.mark, {super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    mark.asset,
    width: size,
    height: size,
    semanticsLabel: mark.label,
  );
}

/// A [FileMark] on a tile, where an [SsIconTile] would go.
class SsFileMarkTile extends StatelessWidget {
  final FileMark mark;
  final double size;
  final Color? background;
  const SsFileMarkTile(this.mark, {super.key, this.size = 36, this.background});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? context.ss.chip,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: SsFileMark(mark, size: size * 0.62),
  );
}

/// A sheet's own icon with where it saves as a badge on the corner, so a
/// list of sheets says "Google Sheets" or "Excel" at a glance.
class SsSheetTile extends StatelessWidget {
  final ScanSession session;
  final double size;

  /// The icon tile's colors, as on [SsIconTile] (e.g. an active sheet).
  final Color? background, color;
  const SsSheetTile(
    this.session, {
    super.key,
    this.size = 40,
    this.background,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.48;
    return SizedBox(
      width: size + badge * 0.3,
      height: size + badge * 0.3,
      child: Stack(
        children: [
          SsIconTile(
            sheetIcon(session.iconName),
            size: size,
            background: background,
            color: color,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: context.ss.surface,
                borderRadius: BorderRadius.circular(badge * 0.32),
                border: Border.all(color: context.ss.line),
              ),
              alignment: Alignment.center,
              child: SsFileMark(
                FileMark.of(session.destination),
                size: badge * 0.78,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
