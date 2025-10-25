// lib/foodreccom/constants/unit_conversions.dart
import '../../common/measurement_constants.dart';

/// 🔹 น้ำหนัก (weight units) → ค่าคูณเป็นกรัม (canonical = gram)
const Map<String, double> weightUnits = {
  'g': 1,
  'gram': 1,
  'grams': 1,
  'kg': MeasurementConstants.gramsPerKilogram,
  'kilogram': MeasurementConstants.gramsPerKilogram,
  'kilograms': MeasurementConstants.gramsPerKilogram,
  'mg': 1 / MeasurementConstants.milligramsPerGram,
  'milligram': 1 / MeasurementConstants.milligramsPerGram,
  'milligrams': 1 / MeasurementConstants.milligramsPerGram,
  'ounce': MeasurementConstants.gramsPerOunce,
  'oz': MeasurementConstants.gramsPerOunce,
  'pound': MeasurementConstants.gramsPerPound,
  'lb': MeasurementConstants.gramsPerPound,
  'lbs': MeasurementConstants.gramsPerPound,
  'กิโลกรัม': MeasurementConstants.gramsPerKilogram,
  'กรัม': 1,
};

/// 🔹 ปริมาตร (volume units) → ค่าคูณเป็นมิลลิลิตร (canonical = milliliter)
const Map<String, double> volumeUnits = {
  'ml': 1,
  'milliliter': 1,
  'milliliters': 1,
  'มิลลิลิตร': 1,
  'l': MeasurementConstants.millilitersPerLiter,
  'liter': MeasurementConstants.millilitersPerLiter,
  'liters': MeasurementConstants.millilitersPerLiter,
  'ลิตร': MeasurementConstants.millilitersPerLiter,
  'cup': MeasurementConstants.millilitersPerCup,
  'cups': MeasurementConstants.millilitersPerCup,
  'ถ้วย': MeasurementConstants.millilitersPerCup,
  'tbsp': MeasurementConstants.millilitersPerTablespoon,
  'tablespoon': MeasurementConstants.millilitersPerTablespoon,
  'tablespoons': MeasurementConstants.millilitersPerTablespoon,
  'ช้อนโต๊ะ': MeasurementConstants.millilitersPerTablespoon,
  'tsp': MeasurementConstants.millilitersPerTeaspoon,
  'teaspoon': MeasurementConstants.millilitersPerTeaspoon,
  'teaspoons': MeasurementConstants.millilitersPerTeaspoon,
  'ช้อนชา': MeasurementConstants.millilitersPerTeaspoon,
  'pint': MeasurementConstants.millilitersPerPintUS,
  'quart': MeasurementConstants.millilitersPerQuartUS,
  'gallon': MeasurementConstants.millilitersPerGallonUS,
  'pt': MeasurementConstants.millilitersPerPintUS,
  'qt': MeasurementConstants.millilitersPerQuartUS,
  'gal': MeasurementConstants.millilitersPerGallonUS,
};

/// 🔹 หน่วยชิ้น (piece units)
const Set<String> pieceUnits = {
  'piece',
  'pieces',
  'pc',
  'pcs',
  'ชิ้น',
  'ลูก',
  'หัว',
  'ฟอง',
  'กลีบ',
  'เม็ด',
  'ใบ',
  'ต้น',
  'ตัว',
  'ดอก',
  'ก้าน',
  'ฝัก',
};
