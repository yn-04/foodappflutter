class UsageConversionResult {
  final bool isValid;
  final int remainingQuantity;
  final String remainingUnit;

  const UsageConversionResult({
    required this.isValid,
    required this.remainingQuantity,
    required this.remainingUnit,
  });
}

class UnitConverter {
  static const String gram = 'กรัม';
  static const String kilogram = 'กิโลกรัม';
  static const String milliliter = 'มิลลิลิตร';
  static const String liter = 'ลิตร';

  static const Map<String, _UnitMeta> _registry = {
    kilogram: _UnitMeta(
      unit: kilogram,
      canonical: gram,
      toCanonicalFactor: 1000,
    ),
    gram: _UnitMeta(unit: gram, canonical: gram, toCanonicalFactor: 1),
    liter: _UnitMeta(
      unit: liter,
      canonical: milliliter,
      toCanonicalFactor: 1000,
    ),
    milliliter: _UnitMeta(
      unit: milliliter,
      canonical: milliliter,
      toCanonicalFactor: 1,
    ),
  };

  static int convertQuantity({
    required int quantity,
    required String from,
    required String to,
  }) {
    if (from == to) return quantity;
    final fromMeta = _resolve(from);
    final toMeta = _resolve(to);
    if (fromMeta.canonical != toMeta.canonical) {
      return quantity;
    }

    final canonicalQty = quantity * fromMeta.toCanonicalFactor;
    if (canonicalQty == 0) return 0;
    if (toMeta.toCanonicalFactor == 0) {
      return quantity;
    }

    if (canonicalQty % toMeta.toCanonicalFactor != 0) {
      return canonicalQty ~/ toMeta.toCanonicalFactor;
    }
    return canonicalQty ~/ toMeta.toCanonicalFactor;
  }

  static UsageConversionResult applyUsage({
    required int currentQty,
    required String currentUnit,
    required int useQty,
    required String useUnit,
  }) {
    final currentMeta = _resolve(currentUnit);
    final useMeta = _resolve(useUnit);

    if (currentQty < 0 || useQty < 0) {
      return UsageConversionResult(
        isValid: false,
        remainingQuantity: currentQty,
        remainingUnit: currentUnit,
      );
    }

    if (currentMeta.canonical != useMeta.canonical) {
      if (currentUnit == useUnit) {
        final remainder = currentQty - useQty;
        return UsageConversionResult(
          isValid: remainder >= 0,
          remainingQuantity: remainder < 0 ? 0 : remainder,
          remainingUnit: currentUnit,
        );
      }
      return UsageConversionResult(
        isValid: false,
        remainingQuantity: currentQty,
        remainingUnit: currentUnit,
      );
    }

    final canonicalCurrent = currentQty * currentMeta.toCanonicalFactor;
    final canonicalUse = useQty * useMeta.toCanonicalFactor;

    if (canonicalUse > canonicalCurrent) {
      return UsageConversionResult(
        isValid: false,
        remainingQuantity: currentQty,
        remainingUnit: currentUnit,
      );
    }

    final canonicalRemain = canonicalCurrent - canonicalUse;
    final targetMeta = _selectResultMeta(canonicalRemain, currentMeta, useMeta);

    final remainingQty = canonicalRemain ~/ targetMeta.toCanonicalFactor;
    return UsageConversionResult(
      isValid: true,
      remainingQuantity: remainingQty,
      remainingUnit: targetMeta.unit,
    );
  }

  static List<String> fallbackOptions(String baseUnit) {
    final meta = _resolve(baseUnit);
    final options = <String>{meta.unit};
    if (meta.unit == kilogram) {
      options.add(gram);
    } else if (meta.unit == liter) {
      options.add(milliliter);
    }
    return options.toList();
  }

  static _UnitMeta _selectResultMeta(
    int canonicalQty,
    _UnitMeta currentMeta,
    _UnitMeta useMeta,
  ) {
    if (canonicalQty == 0) {
      return useMeta;
    }

    if (useMeta.canRepresent(canonicalQty)) {
      return useMeta;
    }

    if (currentMeta.canRepresent(canonicalQty)) {
      return currentMeta;
    }

    return _resolve(currentMeta.canonical);
  }

  static _UnitMeta _resolve(String unit) {
    return _registry[unit] ??
        _UnitMeta(unit: unit, canonical: unit, toCanonicalFactor: 1);
  }
}

class _UnitMeta {
  final String unit;
  final String canonical;
  final int toCanonicalFactor;

  const _UnitMeta({
    required this.unit,
    required this.canonical,
    required this.toCanonicalFactor,
  });

  bool canRepresent(int canonicalQty) {
    if (toCanonicalFactor == 0) return false;
    return canonicalQty % toCanonicalFactor == 0;
  }
}
