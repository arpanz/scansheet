enum GeneratorType {
  qrCode('QR Code'),
  code128('Barcode (Code 128)'),
  ean13('Barcode (EAN-13)'),
  upcA('Barcode (UPC-A)');

  final String displayName;
  const GeneratorType(this.displayName);
}
