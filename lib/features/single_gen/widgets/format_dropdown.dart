import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/generator_type.dart';

class FormatDropdown extends StatelessWidget {
  final GeneratorType selectedType;
  final ValueChanged<GeneratorType> onChanged;

  const FormatDropdown({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  static const _barcodeTypes = [
    GeneratorType.code128,
    GeneratorType.ean13,
    GeneratorType.upcA,
  ];

  static const _barcodeInfo = <GeneratorType, ({IconData icon, String desc})>{
    GeneratorType.code128: (
      icon: Icons.view_column_rounded,
      desc: 'Alphanumeric — variable length',
    ),
    GeneratorType.ean13: (
      icon: Icons.shopping_cart_outlined,
      desc: 'Retail products — 13 digits',
    ),
    GeneratorType.upcA: (
      icon: Icons.storefront_outlined,
      desc: 'North America — 12 digits',
    ),
  };

  bool get _isBarcode => _barcodeTypes.contains(selectedType);

  String get _barcodeSubtitle {
    if (!_isBarcode) return '';
    return selectedType.displayName
        .replaceAll('Barcode ', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
  }

  void _showBarcodeDialog(BuildContext context) {
    showModalBottomSheet<GeneratorType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: context.themeCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.view_column_rounded,
                      size: 18,
                      color: context.themeAccent,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Choose Barcode Type',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Divider(height: 1, color: context.themeBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  children: _barcodeTypes.map((type) {
                    final meta = _barcodeInfo[type]!;
                    final isActive = type == selectedType;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? context.themeAccent.withValues(alpha: 0.10)
                                : context.themeSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isActive
                                  ? context.themeAccent
                                  : context.themeBorder,
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? context.themeAccent.withValues(
                                          alpha: 0.12,
                                        )
                                      : context.themeBorder.withValues(
                                          alpha: 0.3,
                                        ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  meta.icon,
                                  size: 20,
                                  color: isActive
                                      ? context.themeAccent
                                      : context.themeTextSecondary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      type.displayName
                                          .replaceAll('Barcode ', '')
                                          .replaceAll('(', '')
                                          .replaceAll(')', ''),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isActive
                                            ? context.themeAccent
                                            : context.themeTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      meta.desc,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.themeTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isActive)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: context.themeAccent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    ).then((result) {
      if (result != null) onChanged(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // QR Code option
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(GeneratorType.qrCode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: !_isBarcode
                    ? context.themeAccent.withValues(alpha: 0.12)
                    : context.themeSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !_isBarcode
                      ? context.themeAccent
                      : context.themeBorder,
                  width: !_isBarcode ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 24,
                    color: !_isBarcode
                        ? context.themeAccent
                        : context.themeTextSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'QR Code',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: !_isBarcode
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: !_isBarcode
                          ? context.themeAccent
                          : context.themeTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Barcode option
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (!_isBarcode) {
                onChanged(GeneratorType.code128);
              }
              _showBarcodeDialog(context);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isBarcode
                    ? context.themeAccent.withValues(alpha: 0.12)
                    : context.themeSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isBarcode ? context.themeAccent : context.themeBorder,
                  width: _isBarcode ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.view_column_rounded,
                    size: 24,
                    color: _isBarcode
                        ? context.themeAccent
                        : context.themeTextSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Barcode',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _isBarcode
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _isBarcode
                          ? context.themeAccent
                          : context.themeTextPrimary,
                    ),
                  ),
                  if (_isBarcode) ...[
                    const SizedBox(height: 2),
                    Text(
                      _barcodeSubtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.themeAccent.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
