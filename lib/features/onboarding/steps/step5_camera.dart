import 'package:flutter/material.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/template_service.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/widgets/ss.dart';
import '../../scan/models/scan_session.dart';
import '../../scan/screens/scan_session_screen.dart';
import '../../../main.dart' as app;
import '../onboarding_flow.dart';

class OnbCameraStep extends StatefulWidget {
  final OnbStateScope scope;
  const OnbCameraStep({super.key, required this.scope});
  @override
  State<OnbCameraStep> createState() => _OnbCameraStepState();
}

class _OnbCameraStepState extends State<OnbCameraStep> {
  bool _loading = false;
  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final state = widget.scope.state;
      final template = state.selectedTemplateId == 'custom'
          ? null
          : TemplateService.getBuiltInTemplates().firstWhere(
              (t) => t.id == state.selectedTemplateId,
              orElse: () => TemplateService.getBuiltInTemplates().first,
            );
      final name = template?.name ?? 'My sheet';
      final columns =
          // No list on a first run: From list columns become typed ones.
          template?.columnsWithoutList ??
          const [
            SessionColumn(name: 'Scan', type: SessionColumnType.scan),
            SessionColumn(name: 'Time', type: SessionColumnType.timestamp),
          ];
      var destination = SessionDestination.localXlsx;
      String? spreadsheetId;
      String? sheetName;
      if (state.destination != 'local' &&
          GoogleSheetsService.instance.isSignedIn) {
        destination = SessionDestination.googleSheets;
        if (state.destination == 'existing') {
          spreadsheetId = state.pickedSpreadsheetId;
          if (spreadsheetId == null) {
            throw StateError('Choose a spreadsheet first.');
          }
          final tabs = await GoogleSheetsService.instance.getWorksheets(
            spreadsheetId,
          );
          sheetName = tabs.isEmpty ? null : tabs.first;
        } else {
          spreadsheetId = await GoogleSheetsService.instance.createSpreadsheet(
            name,
          );
          // Tab left unset: the sync engine resolves the first tab, whose
          // default name is localized ("Sheet1", "Feuille 1", …).
        }
      }
      final session = ScanSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        columns: columns,
        createdAt: DateTime.now(),
        isActive: true,
        mergeRepeats: template?.id == 'builtin_inventory',
        destination: destination,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        templateId: template?.id,
        iconName: template?.icon,
      );
      await ScanSessionService.saveSession(session);
      await OnboardingScreen.markSeen();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const app.MainHomeScreen()),
        (_) => false,
      );
      navigator.push(FadeSlideRoute(page: ScanSessionScreen(session: session)));
    } catch (e) {
      if (mounted) {
        showSsToast(
          context,
          e is StateError
              ? e.message.toString()
              : 'Could not create your sheet. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = SsColors.night;
    return Container(
      color: dark,
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 36),
          Center(
            child: SizedBox(
              width: 236,
              height: 236,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: SsColors.nightRaised,
                      border: Border.all(color: SsColors.nightLine),
                      borderRadius: BorderRadius.circular(34),
                    ),
                    child: const Icon(
                      LucideIcons.camera,
                      size: 52,
                      color: SsColors.brandLime,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: SsScanCorner(top: true, left: true),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: SsScanCorner(top: true, left: false),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: SsScanCorner(top: false, left: true),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: SsScanCorner(top: false, left: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 42),
          Text(
            'One tap, then\nyou’re scanning',
            textAlign: TextAlign.center,
            style: SsText.title(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'ScanSheet uses the camera only while the scanner is open. Nothing is recorded or uploaded.',
            textAlign: TextAlign.center,
            style: SsText.body(color: SsColors.nightMuted),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SsColors.nightSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SsColors.nightLine),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.mapPin,
                  size: 20,
                  color: SsColors.nightMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Location is asked for later, and only if a sheet has a Location column.',
                    style: SsText.sans(
                      size: 13,
                      height: 1.45,
                      color: SsColors.nightMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SsButton.lime(
            'Allow camera and scan',
            loading: _loading,
            onPressed: _loading ? null : _start,
          ),
          TextButton(
            onPressed: _loading ? null : _start,
            child: Text(
              'Not now',
              style: SsText.sans(
                size: 15,
                weight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
