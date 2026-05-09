class QrStyleProfile {
  final String id;
  final String name;
  final int foregroundArgb;
  final int eyeArgb;
  final int backgroundArgb;
  final int errorCorrectionLevel;
  final String eyeShape;
  final String moduleShape;
  final bool frameEnabled;
  final double frameThickness;
  final int frameColorArgb;
  final String? logoBase64;
  final double logoSize;
  final String logoShape;
  final String logoFitMode;
  final double logoZoom;
  final double logoOffsetX;
  final double logoOffsetY;
  final double logoPadding;
  final bool logoBgEnabled;

  const QrStyleProfile({
    required this.id,
    required this.name,
    required this.foregroundArgb,
    required this.eyeArgb,
    required this.backgroundArgb,
    required this.errorCorrectionLevel,
    required this.eyeShape,
    required this.moduleShape,
    required this.frameEnabled,
    required this.frameThickness,
    required this.frameColorArgb,
    this.logoBase64,
    required this.logoSize,
    required this.logoShape,
    required this.logoFitMode,
    required this.logoZoom,
    required this.logoOffsetX,
    required this.logoOffsetY,
    required this.logoPadding,
    required this.logoBgEnabled,
  });

  factory QrStyleProfile.defaultProfile() {
    return const QrStyleProfile(
      id: 'default',
      name: 'Default',
      foregroundArgb: 0xFF000000,
      eyeArgb: 0xFF000000,
      backgroundArgb: 0xFFFFFFFF,
      errorCorrectionLevel: 1,
      eyeShape: 'square',
      moduleShape: 'square',
      frameEnabled: false,
      frameThickness: 2,
      frameColorArgb: 0xFF000000,
      logoBase64: null,
      logoSize: 36,
      logoShape: 'square',
      logoFitMode: 'cover',
      logoZoom: 1.0,
      logoOffsetX: 0.0,
      logoOffsetY: 0.0,
      logoPadding: 4.0,
      logoBgEnabled: true,
    );
  }

  factory QrStyleProfile.brandProfile() {
    return const QrStyleProfile(
      id: 'brand',
      name: 'Brand',
      foregroundArgb: 0xFF34A853,
      eyeArgb: 0xFF34A853,
      backgroundArgb: 0xFFFFFFFF,
      errorCorrectionLevel: 1,
      eyeShape: 'square',
      moduleShape: 'square',
      frameEnabled: false,
      frameThickness: 2,
      frameColorArgb: 0xFF34A853,
      logoBase64: null,
      logoSize: 36,
      logoShape: 'square',
      logoFitMode: 'cover',
      logoZoom: 1.0,
      logoOffsetX: 0.0,
      logoOffsetY: 0.0,
      logoPadding: 4.0,
      logoBgEnabled: true,
    );
  }

  QrStyleProfile copyWith({
    String? id,
    String? name,
    int? foregroundArgb,
    int? eyeArgb,
    int? backgroundArgb,
    int? errorCorrectionLevel,
    String? eyeShape,
    String? moduleShape,
    bool? frameEnabled,
    double? frameThickness,
    int? frameColorArgb,
    String? logoBase64,
    double? logoSize,
    String? logoShape,
    String? logoFitMode,
    double? logoZoom,
    double? logoOffsetX,
    double? logoOffsetY,
    double? logoPadding,
    bool? logoBgEnabled,
  }) {
    return QrStyleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      foregroundArgb: foregroundArgb ?? this.foregroundArgb,
      eyeArgb: eyeArgb ?? this.eyeArgb,
      backgroundArgb: backgroundArgb ?? this.backgroundArgb,
      errorCorrectionLevel: errorCorrectionLevel ?? this.errorCorrectionLevel,
      eyeShape: eyeShape ?? this.eyeShape,
      moduleShape: moduleShape ?? this.moduleShape,
      frameEnabled: frameEnabled ?? this.frameEnabled,
      frameThickness: frameThickness ?? this.frameThickness,
      frameColorArgb: frameColorArgb ?? this.frameColorArgb,
      logoBase64: logoBase64 ?? this.logoBase64,
      logoSize: logoSize ?? this.logoSize,
      logoShape: logoShape ?? this.logoShape,
      logoFitMode: logoFitMode ?? this.logoFitMode,
      logoZoom: logoZoom ?? this.logoZoom,
      logoOffsetX: logoOffsetX ?? this.logoOffsetX,
      logoOffsetY: logoOffsetY ?? this.logoOffsetY,
      logoPadding: logoPadding ?? this.logoPadding,
      logoBgEnabled: logoBgEnabled ?? this.logoBgEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'foregroundArgb': foregroundArgb,
      'eyeArgb': eyeArgb,
      'backgroundArgb': backgroundArgb,
      'errorCorrectionLevel': errorCorrectionLevel,
      'eyeShape': eyeShape,
      'moduleShape': moduleShape,
      'frameEnabled': frameEnabled,
      'frameThickness': frameThickness,
      'frameColorArgb': frameColorArgb,
      'logoBase64': logoBase64,
      'logoSize': logoSize,
      'logoShape': logoShape,
      'logoFitMode': logoFitMode,
      'logoZoom': logoZoom,
      'logoOffsetX': logoOffsetX,
      'logoOffsetY': logoOffsetY,
      'logoPadding': logoPadding,
      'logoBgEnabled': logoBgEnabled,
    };
  }

  factory QrStyleProfile.fromJson(Map<String, dynamic> json) {
    return QrStyleProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      foregroundArgb: json['foregroundArgb'] as int,
      eyeArgb: json['eyeArgb'] as int,
      backgroundArgb: json['backgroundArgb'] as int,
      errorCorrectionLevel: json['errorCorrectionLevel'] as int,
      eyeShape: json['eyeShape'] as String,
      moduleShape: json['moduleShape'] as String,
      frameEnabled: json['frameEnabled'] as bool,
      frameThickness: (json['frameThickness'] as num).toDouble(),
      frameColorArgb: json['frameColorArgb'] as int,
      logoBase64: json['logoBase64'] as String?,
      logoSize: ((json['logoSize'] ?? 36) as num).toDouble(),
      logoShape: (json['logoShape'] ?? 'square') as String,
      logoFitMode: (json['logoFitMode'] ?? 'cover') as String,
      logoZoom: ((json['logoZoom'] ?? 1.0) as num).toDouble(),
      logoOffsetX: ((json['logoOffsetX'] ?? 0.0) as num).toDouble(),
      logoOffsetY: ((json['logoOffsetY'] ?? 0.0) as num).toDouble(),
      logoPadding: ((json['logoPadding'] ?? 4.0) as num).toDouble(),
      logoBgEnabled: (json['logoBgEnabled'] ?? true) as bool,
    );
  }
}
