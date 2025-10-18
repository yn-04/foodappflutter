//lib/foodreccom/utils/smart_unit_converter.dart
import '../../common/measurement_constants.dart';
import '../constants/unit_conversions.dart';

class SmartUnitConverter {
  /// แปลงหน่วยทั่วไป เช่น 1 cup → 240 ml, 1 oz → 28.35 g
  static CanonicalQuantity toCanonicalQuantity(
    double amount,
    String unit,
    String ingredientName,
  ) {
    final lower = unit.trim().toLowerCase();

    // น้ำหนัก
    if (weightUnits.containsKey(lower)) {
      return CanonicalQuantity(amount * weightUnits[lower]!, 'gram');
    }

    // ปริมาตร
    if (volumeUnits.containsKey(lower)) {
      return CanonicalQuantity(amount * volumeUnits[lower]!, 'milliliter');
    }

    // หน่วยชิ้น
    if (pieceUnits.contains(lower)) {
      return CanonicalQuantity(amount, 'piece');
    }

    return CanonicalQuantity(amount, 'gram');
  }

  /// แปลงกลับจาก canonical (gram/ml/piece) → หน่วยที่ต้องการ
  static double convertCanonicalToUnit({
    required String canonicalUnit,
    required double canonicalAmount,
    required String targetUnit,
    required String ingredientName,
  }) {
    final lower = targetUnit.trim().toLowerCase();

    if (canonicalUnit == 'gram' && weightUnits.containsKey(lower)) {
      return canonicalAmount / weightUnits[lower]!;
    }
    if (canonicalUnit == 'milliliter' && volumeUnits.containsKey(lower)) {
      return canonicalAmount / volumeUnits[lower]!;
    }
    return canonicalAmount;
  }
}

class CanonicalQuantity {
  final double amount;
  final String unit;
  const CanonicalQuantity(this.amount, this.unit);
}
