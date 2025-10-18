// lib/foodreccom/utils/ingredient_measure_utils.dart
import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart'
    as piece_converter; // 🍳 หน่วยต่อชิ้น เช่น ฟอง ลูก กลีบ
import 'package:my_app/foodreccom/utils/smart_unit_converter.dart'
    as unit_converter; // 🧪 หน่วยทั่วไป เช่น g/ml/cup
import 'thai_localizer.dart';

class UnitConversion {
  final String canonicalUnit; // gram, milliliter, piece
  final double toCanonicalFactor;

  const UnitConversion({
    required this.canonicalUnit,
    required this.toCanonicalFactor,
  });

  double toCanonical(double amount) => amount * toCanonicalFactor;
  double fromCanonical(double canonicalAmount) => toCanonicalFactor == 0
      ? canonicalAmount
      : canonicalAmount / toCanonicalFactor;
}

class CanonicalQuantity {
  final double amount;
  final String unit; // canonical unit

  const CanonicalQuantity({required this.amount, required this.unit});
}

class DisplayQuantity {
  final int quantity;
  final String unit;

  const DisplayQuantity({required this.quantity, required this.unit});

  String get text => unit.isEmpty ? '$quantity' : '$quantity $unit';
}

class IngredientMeasureUtils {
  static double scaleAmount(
    double baseAmount,
    int servingsToMake,
    int baseServings,
  ) {
    if (baseServings == 0) return baseAmount;
    return baseAmount * (servingsToMake / baseServings);
  }

  static UnitConversion conversionFor(String unitRaw, String ingredientName) {
    final normalized = unitRaw.trim().toLowerCase();
    final normalizedName = ingredientName.trim().toLowerCase();

    // 🍳 หน่วยต่อชิ้น เช่น ไข่ 1 ฟอง, กลีบกระเทียม
    final pieceGrams = piece_converter.SmartUnitConverter.gramsFromPiece(
      1,
      normalized,
      normalizedName,
    );
    if (pieceGrams != null) {
      return UnitConversion(
        canonicalUnit: 'gram',
        toCanonicalFactor: pieceGrams,
      );
    }

    if (piece_converter.SmartUnitConverter.isPieceUnit(normalized)) {
      final gramsPerPiece = piece_converter.SmartUnitConverter.gramsPerPiece(
        normalizedName,
      );
      if (gramsPerPiece != null) {
        return UnitConversion(
          canonicalUnit: 'gram',
          toCanonicalFactor: gramsPerPiece,
        );
      }
      return const UnitConversion(canonicalUnit: 'piece', toCanonicalFactor: 1);
    }

    // 🧪 หน่วยทั่วไป (เช่น กิโลกรัม กรัม ลิตร มิลลิลิตร)
    if (_weightUnits.containsKey(normalized)) {
      return UnitConversion(
        canonicalUnit: 'gram',
        toCanonicalFactor: _weightUnits[normalized]!,
      );
    }

    if (_volumeUnits.containsKey(normalized)) {
      return UnitConversion(
        canonicalUnit: 'milliliter',
        toCanonicalFactor: _volumeUnits[normalized]!,
      );
    }

    return const UnitConversion(canonicalUnit: 'piece', toCanonicalFactor: 1);
  }

  static CanonicalQuantity toCanonical(
    double amount,
    String unitRaw,
    String ingredientName,
  ) {
    final conversion = conversionFor(unitRaw, ingredientName);
    return CanonicalQuantity(
      amount: conversion.toCanonical(amount),
      unit: conversion.canonicalUnit,
    );
  }

  static double fromCanonical(
    double canonicalAmount,
    String canonicalUnit,
    String targetUnit,
    String ingredientName,
  ) {
    final conversion = conversionFor(targetUnit, ingredientName);
    if (conversion.canonicalUnit != canonicalUnit) {
      return canonicalAmount;
    }
    return conversion.fromCanonical(canonicalAmount);
  }

  static DisplayQuantity displayQuantity({
    required double amount,
    required String unitRaw,
    required String ingredientName,
  }) {
    final unit = displayUnit(unitRaw, ingredientName);
    final qty = amount.isFinite ? (amount <= 0 ? 0 : amount.ceil()) : 0;
    return DisplayQuantity(quantity: qty, unit: unit);
  }

  static String displayUnit(String unitRaw, String ingredientName) {
    final pieceRule = piece_converter.SmartUnitConverter.pieceRuleFor(
      ingredientName,
      unitRaw,
    );
    if (pieceRule != null) return pieceRule.displayUnit;

    final mapped = ThaiLocalizer.toThaiUnit(unitRaw.trim());
    if (mapped.trim().isNotEmpty && mapped != unitRaw) {
      return mapped;
    }

    final normalized = unitRaw.trim().toLowerCase();
    if (_weightUnits.containsKey(normalized)) return 'กรัม';
    if (_volumeUnits.containsKey(normalized)) return 'มิลลิลิตร';
    if (_pieceUnits.contains(normalized)) return 'ชิ้น';
    return ThaiLocalizer.toThaiUnit(unitRaw.trim());
  }

  static const Map<String, double> _weightUnits = {
    'kg': MeasurementConstants.gramsPerKilogram,
    'kilogram': MeasurementConstants.gramsPerKilogram,
    'kilograms': MeasurementConstants.gramsPerKilogram,
    'กิโลกรัม': MeasurementConstants.gramsPerKilogram,
    'g': 1,
    'gram': 1,
    'grams': 1,
    'กรัม': 1,
  };

  static const Map<String, double> _volumeUnits = {
    'l': MeasurementConstants.millilitersPerLiter,
    'liter': MeasurementConstants.millilitersPerLiter,
    'liters': MeasurementConstants.millilitersPerLiter,
    'ลิตร': MeasurementConstants.millilitersPerLiter,
    'ml': 1,
    'milliliter': 1,
    'milliliters': 1,
    'มิลลิลิตร': 1,
    'tbsp': MeasurementConstants.millilitersPerTablespoon,
    'tablespoon': MeasurementConstants.millilitersPerTablespoon,
    'tablespoons': MeasurementConstants.millilitersPerTablespoon,
    'ช้อนโต๊ะ': MeasurementConstants.millilitersPerTablespoon,
    'tsp': MeasurementConstants.millilitersPerTeaspoon,
    'teaspoon': MeasurementConstants.millilitersPerTeaspoon,
    'teaspoons': MeasurementConstants.millilitersPerTeaspoon,
    'ช้อนชา': MeasurementConstants.millilitersPerTeaspoon,
    'cup': MeasurementConstants.millilitersPerCup,
    'cups': MeasurementConstants.millilitersPerCup,
    'ถ้วย': MeasurementConstants.millilitersPerCup,
  };

  static const Set<String> _pieceUnits = {
    'piece',
    'pieces',
    'ชิ้น',
    'pcs',
    'pc',
    'ลูก',
    'ผล',
    'หัว',
    'กลีบ',
    'เม็ด',
    'ฟอง',
    'ใบ',
    'ต้น',
    'ก้าน',
    'ดอก',
    'ฝัก',
    'ตัว',
  };
}
