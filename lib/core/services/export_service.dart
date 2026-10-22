import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../ads/ad_manager.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ss.dart';
import '../widgets/beautiful_loading_widget.dart';

class ExportService {
  static Future<void> processExport<T>({
    required BuildContext context,
    required String loadingMessage,
    required Future<T> Function() generator,
    required String fileExtension,
    required String shareText,
    required Future<(String, Uint8List)> Function(T data) onGetFileData,
  }) async {
    bool isCancelled = false;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: BeautifulLoadingWidget(
          message: loadingMessage,
          showAd: true,
          onCancel: () {
            isCancelled = true;
            Navigator.pop(ctx);
          },
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 300));

    T? result;
    try {
      result = await generator();
    } catch (e) {
      if (isCancelled) return;
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSsToast(context, 'Export failed: $e', error: true);
      }
      return;
    }

    if (isCancelled) return;
    if (!context.mounted) return;
    Navigator.pop(context);

    String filePath;
    Uint8List fileBytes;
    try {
      (filePath, fileBytes) = await onGetFileData(result as T);
    } catch (e) {
      if (context.mounted) {
        showSsToast(context, 'Could not save file: $e', error: true);
      }
      return;
    }

    if (!context.mounted) return;

    await _showSuccessDialog(
      context: context,
      filePath: filePath,
      fileBytes: fileBytes,
      fileExtension: fileExtension,
      shareText: shareText,
    );
  }

  static Future<void> _showSuccessDialog({
    required BuildContext context,
    required String filePath,
    required Uint8List fileBytes,
    required String fileExtension,
    required String shareText,
  }) async {
    final isPdf = fileExtension == 'pdf';
    final ext = fileExtension.toUpperCase();
    final headerIcon = isPdf ? LucideIcons.fileText : LucideIcons.fileArchive;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.ss.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: ctx.ss.paper,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      child: SsIconTile.accent(ctx, headerIcon),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$ext Ready!',
                            style: TextStyle(
                              color: ctx.ss.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your file has been generated',
                            style: TextStyle(color: ctx.ss.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: ctx.themeTextSecondary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.x,
                          size: 15,
                          color: ctx.ss.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (!AdManager.instance.isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AdManager.instance.getNativeAdWidget(
                      isMedium: false,
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: LucideIcons.externalLink,
                        color: ctx.ss.emerald,
                        label: 'Open',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _handleOpen(context, filePath, fileExtension);
                          if (context.mounted) {
                            AdManager.instance.showInterstitial(context);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: LucideIcons.save,
                        color: ctx.ss.emerald,
                        label: 'Save',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _handleSave(
                            context,
                            filePath,
                            fileBytes,
                            fileExtension,
                          );
                          if (context.mounted) {
                            AdManager.instance.showInterstitial(context);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: LucideIcons.share2,
                        color: ctx.ss.ink2,
                        label: 'Share',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(filePath)],
                              text: shareText,
                            ),
                          );
                          if (context.mounted) {
                            AdManager.instance.showInterstitial(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _handleOpen(
    BuildContext context,
    String filePath,
    String fileExtension,
  ) async {
    try {
      String? mimeType;
      switch (fileExtension.toLowerCase()) {
        case 'pdf':
          mimeType = 'application/pdf';
          break;
        case 'zip':
          mimeType = 'application/zip';
          break;
        case 'csv':
          mimeType = 'text/csv';
          break;
        case 'xlsx':
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
      }
      final result = await OpenFilex.open(filePath, type: mimeType);
      if (result.type != ResultType.done && context.mounted) {
        showSsToast(context, 'Could not open: ${result.message}', error: true);
      }
    } catch (e) {
      if (context.mounted) {
        showSsToast(context, 'Error opening file: $e', error: true);
      }
    }
  }

  /// Save straight to Files (system save dialog), no export dialog.
  static Future<void> saveFile(
    BuildContext context,
    String filePath,
    Uint8List fileBytes,
    String fileExtension,
  ) => _handleSave(context, filePath, fileBytes, fileExtension);

  /// Open the share sheet straight away.
  static Future<void> shareFile(String filePath, String text) => SharePlus
      .instance
      .share(ShareParams(files: [XFile(filePath)], text: text));

  static Future<void> _handleSave(
    BuildContext context,
    String filePath,
    Uint8List fileBytes,
    String fileExtension,
  ) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'ScanSheet_$ts.$fileExtension';

      String? mimeType;
      switch (fileExtension.toLowerCase()) {
        case 'pdf':
          mimeType = 'application/pdf';
          break;
        case 'zip':
          mimeType = 'application/zip';
          break;
        case 'csv':
          mimeType = 'text/csv';
          break;
        case 'xlsx':
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
        default:
          mimeType = 'application/octet-stream';
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final params = SaveFileDialogParams(
          data: fileBytes,
          fileName: fileName,
          mimeTypesFilter: [mimeType],
        );
        final savedPath = await FlutterFileDialog.saveFile(params: params);
        if (savedPath != null && context.mounted) {
          showSsToast(context, 'Saved to Files');
        }
      } else {
        if (context.mounted) {
          showSsToast(context, 'File saved to $filePath');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSsToast(context, 'Save failed: $e', error: true);
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SsButton.secondary(
      label,
      icon: icon,
      onPressed: onTap,
      large: false,
    );
  }
}
