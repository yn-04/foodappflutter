// lib/rawmaterial/utils/price_estimator.dart
// ประมาณช่วงราคาจากหมวดหมู่และหน่วยมาตรฐาน เพื่อกัน outlier

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'package:my_app/rawmaterial/utils/unit_converter.dart';

enum PriceDimension { weight, volume, piece }

class PriceBounds {
  final double minPerUnit;
  final double maxPerUnit;

  const PriceBounds({required this.minPerUnit, required this.maxPerUnit});

  bool contains(double value) => value >= minPerUnit && value <= maxPerUnit;
}

class PriceEstimate {
  final double minTotal;
  final double maxTotal;
  final double minPerUnit;
  final double maxPerUnit;
  final String canonicalUnit;
  final bool usedRecordedPrice;

  const PriceEstimate({
    required this.minTotal,
    required this.maxTotal,
    required this.minPerUnit,
    required this.maxPerUnit,
    required this.canonicalUnit,
    required this.usedRecordedPrice,
  });

  double get midTotal => (minTotal + maxTotal) / 2;
  double get midPerUnit => (minPerUnit + maxPerUnit) / 2;
}

class PriceEstimator {
  static PriceEstimate? estimate(ShoppingItem item) {
    final canonical = UnitConverter.toCanonicalQuantity(
      quantity: item.quantity,
      unit: item.unit,
    );
    if (canonical.amount <= 0) return null;

    final recorded = _resolveRecordedPerUnit(item, canonical.amount);
    return estimateFromCanonical(
      category: item.category,
      canonicalAmount: canonical.amount,
      canonicalUnit: canonical.unit,
      recordedPerUnit: recorded,
    );
  }

  static PriceEstimate? estimateFromCanonical({
    required String category,
    required double canonicalAmount,
    required String canonicalUnit,
    double? recordedPerUnit,
  }) {
    if (canonicalAmount <= 0) return null;
    final dimension = _dimensionForCanonical(canonicalUnit);
    final bounds = _resolveBounds(category, dimension);

    final _Range perUnitRange = _buildPerUnitRange(
      bounds,
      recordedPerUnit,
    );

    final double minTotal = perUnitRange.min * canonicalAmount;
    final double maxTotal = perUnitRange.max * canonicalAmount;

    return PriceEstimate(
      minTotal: minTotal,
      maxTotal: maxTotal,
      minPerUnit: perUnitRange.min,
      maxPerUnit: perUnitRange.max,
      canonicalUnit: canonicalUnit,
      usedRecordedPrice: perUnitRange.usedRecorded,
    );
  }

  static PriceBounds _resolveBounds(String? rawCategory, PriceDimension dim) {
    final normalized = _normalizeCategoryForBounds(rawCategory ?? '');
    final categoryMap = _categoryBounds[normalized];
    if (categoryMap != null) {
      final bounds = categoryMap[dim];
      if (bounds != null) return bounds;
    }
    final fallback = _defaultBounds[dim];
    if (fallback != null) return fallback;
    return const PriceBounds(minPerUnit: 0.02, maxPerUnit: 1.8);
  }

  static PriceDimension _dimensionForCanonical(String canonicalUnit) {
    final unit = canonicalUnit.trim().toLowerCase();
    if (unit == UnitConverter.gram || unit == 'gram' || unit == 'กรัม') {
      return PriceDimension.weight;
    }
    if (unit == UnitConverter.milliliter ||
        unit == 'milliliter' ||
        unit == 'มิลลิลิตร' ||
        unit == 'ml' ||
        unit == 'ลิตร' ||
        unit == 'liter') {
      return PriceDimension.volume;
    }
    return PriceDimension.piece;
  }

  static double? _resolveRecordedPerUnit(
    ShoppingItem item,
    double canonicalAmount,
  ) {
    if (item.pricePerCanonicalUnit != null &&
        item.pricePerCanonicalUnit! > 0) {
      return item.pricePerCanonicalUnit;
    }
    if (item.price != null && item.price! > 0 && canonicalAmount > 0) {
      return item.price! / canonicalAmount;
    }
    return null;
  }

  static _Range _buildPerUnitRange(PriceBounds bounds, double? recorded) {
    if (recorded != null && recorded > 0) {
      final bool plausible = recorded >= bounds.minPerUnit * 0.5 &&
          recorded <= bounds.maxPerUnit * 1.5;
      if (plausible) {
        final double slack = _relativeSlack(recorded);
        final double lower = _clamp(
          recorded * (1 - slack),
          bounds.minPerUnit,
          bounds.maxPerUnit,
        );
        final double upper = _clamp(
          recorded * (1 + slack),
          bounds.minPerUnit,
          bounds.maxPerUnit,
        );
        if (lower <= upper) {
          return _Range(lower, upper, usedRecorded: true);
        }
      }
    }
    return _Range(bounds.minPerUnit, bounds.maxPerUnit);
  }

  static double _relativeSlack(double value) {
    if (value < 1) return 0.35;
    if (value < 5) return 0.25;
    if (value < 20) return 0.2;
    return 0.15;
  }

  static double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

class _Range {
  final double min;
  final double max;
  final bool usedRecorded;

  const _Range(this.min, this.max, {this.usedRecorded = false});
}

String _normalizeCategoryForBounds(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final normalized = Categories.normalize(trimmed);
  if (_categoryBounds.containsKey(normalized)) return normalized;
  final lower = normalized.toLowerCase();
  for (final entry in _categorySynonyms.entries) {
    if (lower.contains(entry.key.toLowerCase())) return entry.value;
  }
  return normalized;
}

const Map<String, String> _categorySynonyms = {
  'ผัก': 'ผักผลไม้สด',
  'ผลไม้': 'ผักผลไม้สด',
  'ผักผลไม้': 'ผักผลไม้สด',
  'ผักสด': 'ผักผลไม้สด',
  'ผลผลิต': 'ผักผลไม้สด',
  'เนื้อสัตว์': 'เนื้อสัตว์/อาหารทะเล',
  'ซีฟู้ด': 'เนื้อสัตว์/อาหารทะเล',
  'อาหารทะเล': 'เนื้อสัตว์/อาหารทะเล',
  'ปลา': 'เนื้อสัตว์/อาหารทะเล',
  'กุ้ง': 'เนื้อสัตว์/อาหารทะเล',
  'ไก่': 'เนื้อสัตว์/อาหารทะเล',
  'ไข่': 'ไข่',
  'ผลิตภัณฑ์จากนม': 'นม/ชีส/ไข่',
  'ชีส': 'นม/ชีส/ไข่',
  'ของแห้ง': 'ของแห้ง/เครื่องปรุง',
  'เครื่องเทศ': 'ของแห้ง/เครื่องปรุง',
  'เครื่องปรุง': 'ของแห้ง/เครื่องปรุง',
  'แป้ง': 'ของแห้ง/เครื่องปรุง',
  'ข้าว': 'ของแห้ง/เครื่องปรุง',
  'ถั่ว': 'ของแห้ง/เครื่องปรุง',
  'ธัญพืช': 'ของแห้ง/เครื่องปรุง',
  'เบเกอรี่': 'เบเกอรี่/ขนม',
  'ขนม': 'เบเกอรี่/ขนม',
  'ของหวาน': 'เบเกอรี่/ขนม',
  'เครื่องดื่ม': 'เครื่องดื่ม',
  'น้ำผลไม้': 'เครื่องดื่ม',
  'น้ำซุป': 'กับข้าว/พร้อมทาน',
  'กับข้าว': 'กับข้าว/พร้อมทาน',
  'กับข้าวสำเร็จ': 'กับข้าว/พร้อมทาน',
  'ของพร้อมทาน': 'กับข้าว/พร้อมทาน',
  'อาหารพร้อมทาน': 'กับข้าว/พร้อมทาน',
  'น้ำมัน': 'น้ำมัน',
  'ของแช่แข็ง': 'กับข้าว/พร้อมทาน',
};

const Map<String, Map<PriceDimension, PriceBounds>> _categoryBounds = {
  'ไข่': {
    PriceDimension.piece: PriceBounds(minPerUnit: 3, maxPerUnit: 12),
    PriceDimension.weight: PriceBounds(minPerUnit: 0.05, maxPerUnit: 0.3),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.03, maxPerUnit: 0.2),
  },
  'ผักผลไม้สด': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.02, maxPerUnit: 0.4),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.015, maxPerUnit: 0.25),
    PriceDimension.piece: PriceBounds(minPerUnit: 4, maxPerUnit: 80),
  },
  'เนื้อสัตว์/อาหารทะเล': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.05, maxPerUnit: 1.6),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.04, maxPerUnit: 0.9),
    PriceDimension.piece: PriceBounds(minPerUnit: 10, maxPerUnit: 220),
  },
  'นม/ชีส/ไข่': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.03, maxPerUnit: 0.9),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.02, maxPerUnit: 0.4),
    PriceDimension.piece: PriceBounds(minPerUnit: 4, maxPerUnit: 25),
  },
  'ของแห้ง/เครื่องปรุง': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.02, maxPerUnit: 2.4),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.015, maxPerUnit: 1.2),
    PriceDimension.piece: PriceBounds(minPerUnit: 5, maxPerUnit: 90),
  },
  'กับข้าว/พร้อมทาน': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.04, maxPerUnit: 1.2),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.03, maxPerUnit: 0.8),
    PriceDimension.piece: PriceBounds(minPerUnit: 15, maxPerUnit: 180),
  },
  'เบเกอรี่/ขนม': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.03, maxPerUnit: 1.5),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.02, maxPerUnit: 0.9),
    PriceDimension.piece: PriceBounds(minPerUnit: 8, maxPerUnit: 120),
  },
  'เครื่องดื่ม': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.02, maxPerUnit: 0.7),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.015, maxPerUnit: 0.35),
    PriceDimension.piece: PriceBounds(minPerUnit: 10, maxPerUnit: 90),
  },
  'น้ำมัน': {
    PriceDimension.weight: PriceBounds(minPerUnit: 0.03, maxPerUnit: 0.6),
    PriceDimension.volume: PriceBounds(minPerUnit: 0.025, maxPerUnit: 0.4),
    PriceDimension.piece: PriceBounds(minPerUnit: 20, maxPerUnit: 160),
  },
};

const Map<PriceDimension, PriceBounds> _defaultBounds = {
  PriceDimension.weight: PriceBounds(minPerUnit: 0.02, maxPerUnit: 1.8),
  PriceDimension.volume: PriceBounds(minPerUnit: 0.015, maxPerUnit: 0.9),
  PriceDimension.piece: PriceBounds(minPerUnit: 5, maxPerUnit: 200),
};
