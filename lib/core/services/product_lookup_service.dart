import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Barcode → product name via the free Open Food Facts / Open Products
/// Facts databases. Results (including misses) are cached in Hive so
/// repeat scans and offline use are instant.
class ProductLookupService {
  ProductLookupService._();
  static final ProductLookupService instance = ProductLookupService._();

  static const _boxName = 'product_lookup';
  static const _timeout = Duration(milliseconds: 2500);
  static const _hosts = [
    'world.openfoodfacts.org',
    'world.openproductsfacts.org',
  ];

  Box<String>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Cached answer without touching the network; '' means a known miss.
  String? cached(String barcode) => _box?.get(barcode);

  /// "Name · Brand · Size", or null when not found / offline.
  Future<String?> lookup(String barcode) async {
    if (!RegExp(r'^\d{8,14}$').hasMatch(barcode)) return null;
    final hit = cached(barcode);
    if (hit != null) return hit.isEmpty ? null : hit;
    for (final host in _hosts) {
      try {
        final uri = Uri.https(host, '/api/v2/product/$barcode.json', {
          'fields': 'product_name,brands,quantity',
        });
        final res = await http
            .get(uri, headers: {'User-Agent': 'ScanSheet/1.5 (Android)'})
            .timeout(_timeout);
        if (res.statusCode == 404) continue;
        if (res.statusCode != 200) return null;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final product = body['product'] as Map<String, dynamic>?;
        final name = _describe(product);
        if (name != null) {
          await _box?.put(barcode, name);
          return name;
        }
      } catch (e) {
        debugPrint('Product lookup failed for $barcode: $e');
        return null; // Offline or slow: don't cache, try again next time.
      }
    }
    await _box?.put(barcode, '');
    return null;
  }

  static String? _describe(Map<String, dynamic>? p) {
    if (p == null) return null;
    String clean(Object? v) => (v as String? ?? '').trim();
    final name = clean(p['product_name']);
    if (name.isEmpty) return null;
    final brand = clean(p['brands']).split(',').first.trim();
    final size = clean(p['quantity']);
    return [
      name,
      if (brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase()))
        brand,
      if (size.isNotEmpty) size,
    ].join(' · ');
  }
}
