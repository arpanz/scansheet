import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../ads/ad_manager.dart';
import '../theme/app_theme.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: context.themeError,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save file: $e'),
            backgroundColor: context.themeError,
          ),
        );
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
    final headerIcon = isPdf
        ? Icons.picture_as_pdf_rounded
        : Icons.folder_zip_rounded;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.themeCard,
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
                  gradient: LinearGradient(
                    colors: [
                      ctx.themeAccent.withValues(alpha: 0.18),
                      ctx.themeAccent.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
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
                      decoration: BoxDecoration(
                        color: ctx.themeAccent,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: ctx.themeAccent.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(headerIcon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$ext Ready!',
                            style: TextStyle(
                              color: ctx.themeTextPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your file has been generated',
                            style: TextStyle(
                              color: ctx.themeTextSecondary,
                              fontSize: 12,
                            ),
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
                          Icons.close_rounded,
                          size: 15,
                          color: ctx.themeTextSecondary,
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
                        icon: Icons.open_in_new_rounded,
                        color: ctx.themeAccent,
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
                        icon: Icons.save_alt_rounded,
                        color: const Color(0xFF10B981),
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
                        icon: Icons.ios_share_rounded,
                        color: const Color(0xFF6366F1),
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
          mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
      }
      final result = await OpenFilex.open(filePath, type: mimeType);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open: ${result.message}'),
            backgroundColor: context.themeError,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: context.themeError,
          ),
        );
      }
    }
  }

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
          mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File saved successfully')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('File saved to $filePath')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: context.themeError,
          ),
        );
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: context.themeSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.themeBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
