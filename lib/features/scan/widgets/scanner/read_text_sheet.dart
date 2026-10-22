import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/ss.dart';

/// Captures a photo and lets the user choose recognized lines of text.
Future<String?> captureText(BuildContext context) async {
  XFile? photo;
  try {
    photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
  } catch (_) {
    if (context.mounted) {
      showSsToast(context, 'Camera permission is needed to read text.');
    }
    return null;
  }
  if (photo == null || !context.mounted) return null;

  final navigator = Navigator.of(context);
  final loading = showSsSheet<void>(
    context,
    dismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Text('Reading text…', style: SsText.body(color: ctx.ss.ink)),
          ],
        ),
      ),
    ),
  );
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  List<String> lines;
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(photo.path),
    );
    lines = result.blocks
        .expand((block) => block.lines)
        .map((line) => line.text.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  } catch (_) {
    lines = [];
  } finally {
    await recognizer.close();
  }
  navigator.pop();
  await loading;
  if (!context.mounted) return null;
  if (lines.isEmpty) {
    showSsToast(context, 'No text found. Try another photo.');
    return captureText(context);
  }

  final selected = await showSsSheet<String>(
    context,
    builder: (_) => _RecognizedTextSheet(lines: lines),
  );
  if (selected == _retake) {
    if (!context.mounted) return null;
    return captureText(context);
  }
  return selected;
}

const _retake = '\u0000retake';

class _RecognizedTextSheet extends StatefulWidget {
  final List<String> lines;
  const _RecognizedTextSheet({required this.lines});

  @override
  State<_RecognizedTextSheet> createState() => _RecognizedTextSheetState();
}

class _RecognizedTextSheetState extends State<_RecognizedTextSheet> {
  final List<int> _order = [];

  String get _preview => _order.map((i) => widget.lines[i]).join(' ');

  void _toggle(int index) {
    setState(() {
      if (_order.contains(index)) {
        _order.remove(index);
      } else {
        _order.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Read text', style: SsText.heading(color: c.ink)),
          const SizedBox(height: 6),
          Text('Tap the words to keep.', style: SsText.body(color: c.muted)),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < widget.lines.length; i++)
                    _TextChip(
                      text: widget.lines[i],
                      selected: _order.contains(i),
                      onTap: () => _toggle(i),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(minHeight: 50),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(SsRadius.md),
            ),
            child: Text(
              _preview.isEmpty ? 'Selected text will appear here' : _preview,
              style: SsText.mono(
                size: 14,
                color: _preview.isEmpty ? c.muted : c.ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SsButton(
            'Use text',
            onPressed: _preview.isEmpty
                ? null
                : () => Navigator.pop(context, _preview),
          ),
          const SizedBox(height: 8),
          SsButton.secondary(
            'Retake',
            expand: true,
            onPressed: () => Navigator.pop(context, _retake),
          ),
        ],
      ),
    );
  }
}

class _TextChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _TextChip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: selected ? c.emeraldTint : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SsRadius.sm),
        side: BorderSide(color: selected ? c.emerald : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SsRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            text,
            style: SsText.mono(
              size: 13,
              color: selected ? c.emeraldDeep : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}
