// lib/models/ingredient_model.dart
class IngredientModel {
  final String name;
  final int quantity;
  final String unit;
  final String category;
  final DateTime? expiryDate;
  final double? price;
  final String? notes;

  IngredientModel({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.expiryDate,
    this.price,
    this.notes,
  });

  // สร้างจาก Firestore document
  factory IngredientModel.fromFirestore(Map<String, dynamic> data) {
    return IngredientModel(
      name: data['name'] ?? '',
      quantity: data['quantity'] ?? 0,
      unit: data['unit'] ?? '',
      category: data['category'] ?? '',
      expiryDate: data['expiry_date'] != null
          ? DateTime.parse(data['expiry_date'])
          : null,
      price: data['price']?.toDouble(),
      notes: data['notes'],
    );
  }

  // คำนวณวันที่เหลือก่อนหมดอายุ
  int get daysToExpiry {
    if (expiryDate == null) return 999; // ไม่มีวันหมดอายุ
    final now = DateTime.now();
    final difference = expiryDate!.difference(now).inDays;
    return difference < 0 ? 0 : difference;
  }

  // ตรวจสอบว่าใกล้หมดอายุไหม
  bool get isNearExpiry => daysToExpiry <= 3;

  // สำหรับส่งไปยัง AI
  Map<String, dynamic> toAIFormat() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'days_to_expiry': daysToExpiry,
      'is_near_expiry': isNearExpiry,
    };
  }
}
