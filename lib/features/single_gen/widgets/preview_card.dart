import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/generator_type.dart';
import '../models/logo_fit_mode.dart';
import '../models/logo_shape.dart';

class PreviewCard extends StatelessWidget {
  final String data;
  final GeneratorType type;
  final Color foregroundColor;
  final Color? eyeColor;
  final Color backgroundColor;
  final int errorCorrectionLevel;
  final ImageProvider? embeddedLogo;
  final double logoSize;
  final LogoShape logoShape;
  final LogoFitMode logoFitMode;
  final double logoZoom;
  final double logoOffsetX;
  final double logoOffsetY;
  final double logoPadding;
  final bool logoBgEnabled;
  final QrEyeShape eyeShape;
  final QrDataModuleShape moduleShape;
  final bool frameEnabled;
  final double frameThickness;
  final Color frameColor;
  final GlobalKey? exportKey;

  const PreviewCard({
    super.key,
    required this.data,
    required this.type,
    this.foregroundColor = Colors.black,
    this.eyeColor,
    this.backgroundColor = Colors.white,
    this.errorCorrectionLevel = QrErrorCorrectLevel.M,
    this.embeddedLogo,
    this.logoSize = 36,
    this.logoShape = LogoShape.square,
    this.logoFitMode = LogoFitMode.cover,
    this.logoZoom = 1.0,
    this.logoOffsetX = 0.0,
    this.logoOffsetY = 0.0,
    this.logoPadding = 4,
    this.logoBgEnabled = true,
    this.eyeShape = QrEyeShape.square,
    this.moduleShape = QrDataModuleShape.square,
    this.frameEnabled = false,
    this.frameThickness = 0,
    this.frameColor = Colors.black,
    this.exportKey,
  });

  @override
  Widget build(BuildContext context) {
    final displayData = data.isEmpty ? "12345678" : data;

    // Provide a neat inner package for exporting (less padding, no card shadows)
    final innerContent = Container(
      color: type == GeneratorType.qrCode ? backgroundColor : Colors.white,
      padding: const EdgeInsets.all(12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: _buildBarcodeWidget(displayData),
      ),
    );

    // We use a physical card look for the screen preview itself
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: type == GeneratorType.qrCode ? backgroundColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: foregroundColor.withValues(
              alpha: type == GeneratorType.qrCode ? 0.2 : 0.0,
            ),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: exportKey != null
            ? RepaintBoundary(key: exportKey, child: innerContent)
            : innerContent,
      ),
    );
  }

  Widget _buildBarcodeWidget(String currentData) {
    try {
      if (type == GeneratorType.qrCode) {
        final qrBase = QrImageView(
          data: currentData,
          version: QrVersions.auto,
          backgroundColor: backgroundColor,
          eyeStyle: QrEyeStyle(
            eyeShape: eyeShape,
            color: eyeColor ?? foregroundColor,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: moduleShape,
            color: foregroundColor,
          ),
          errorCorrectionLevel: errorCorrectionLevel,
          // Logo rendered via overlay, not embeddedImage
        );

        return Container(
          key: ValueKey(
            '${currentData}_qr_${foregroundColor.toARGB32()}_${(eyeColor ?? foregroundColor).toARGB32()}_${backgroundColor.toARGB32()}_${logoShape.name}_${logoFitMode.name}_${logoZoom.toStringAsFixed(2)}_${logoOffsetX.toStringAsFixed(2)}_${logoOffsetY.toStringAsFixed(2)}_${logoPadding.toStringAsFixed(2)}_${logoBgEnabled}_${frameEnabled}_${frameThickness.toStringAsFixed(1)}_${frameColor.toARGB32()}',
          ),
          constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (frameEnabled)
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: frameColor,
                      width: frameThickness.clamp(0, 10),
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(frameEnabled ? frameThickness + 4 : 0),
                child: qrBase,
              ),
              if (embeddedLogo != null) _buildLogoOverlay(),
            ],
          ),
        );
      } else {
        Barcode barcodeType;
        switch (type) {
          case GeneratorType.code128:
            barcodeType = Barcode.code128();
            break;
          case GeneratorType.ean13:
            barcodeType = Barcode.ean13();
            if (currentData.length < 12) {
              return _buildErrorState('EAN-13 requires 12 or 13 digits.');
            }
            break;
          case GeneratorType.upcA:
            barcodeType = Barcode.upcA();
            if (currentData.length < 11) {
              return _buildErrorState('UPC-A requires 11 or 12 digits.');
            }
            break;
          default:
            barcodeType = Barcode.code128();
        }

        return Container(
          key: ValueKey('${currentData}_${type.name}'),
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 150),
          child: BarcodeWidget(
            barcode: barcodeType,
            data: currentData,
            errorBuilder: (context, error) =>
                _buildErrorState('Invalid data for ${type.displayName}'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: Colors.black,
            ),
          ),
        );
      }
    } catch (e) {
      return _buildErrorState('Cannot generate code.');
    }
  }

  Widget _buildLogoOverlay() {
    final totalSize = logoSize + logoPadding * 2;

    BorderRadius borderRadius;
    switch (logoShape) {
      case LogoShape.square:
        borderRadius = BorderRadius.circular(2);
        break;
      case LogoShape.rounded:
        borderRadius = BorderRadius.circular(totalSize * 0.22);
        break;
      case LogoShape.circle:
        borderRadius = BorderRadius.circular(totalSize);
        break;
    }

    Widget logoImage = ClipRRect(
      borderRadius: logoShape == LogoShape.circle
          ? BorderRadius.circular(logoSize)
          : logoShape == LogoShape.rounded
          ? BorderRadius.circular(logoSize * 0.18)
          : BorderRadius.circular(0),
      child: SizedBox(
        width: logoSize,
        height: logoSize,
        child: ClipRect(
          child: Align(
            alignment: Alignment(logoOffsetX, logoOffsetY),
            child: Transform.scale(
              scale: logoZoom.clamp(1.0, 3.0),
              child: Image(
                image: embeddedLogo!,
                width: logoSize,
                height: logoSize,
                fit: logoFitMode.fit,
              ),
            ),
          ),
        ),
      ),
    );

    if (logoBgEnabled) {
      return Container(
        width: totalSize,
        height: totalSize,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: logoImage),
      );
    }

    return logoImage;
  }

  Widget _buildErrorState(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
