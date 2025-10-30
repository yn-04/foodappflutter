// lib/rawmaterial/models/shopping_item.dart — โมเดลข้อมูลวัตถุดิบ + แปลงจาก/เป็น Firestore
import 'package:cloud_firestore/cloud_firestore.dart';

class ShoppingItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final DateTime? expiryDate;
  final String imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String ownerId;
  final String? familyId;
  final DocumentReference<Map<String, dynamic>>? reference;
  final double? price;
  final double? pricePerCanonicalUnit;
  final String? priceCanonicalUnit;
  final DateTime? priceRecordedAt;
  final DateTime? priceRecordedAtLocal;

  ShoppingItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    this.expiryDate,
    required this.imageUrl,
    this.createdAt,
    this.updatedAt,
    this.ownerId = '',
    this.familyId,
    this.reference,
    this.price,
    this.pricePerCanonicalUnit,
    this.priceCanonicalUnit,
    this.priceRecordedAt,
    this.priceRecordedAtLocal,
  });

  /// อนุพันธ์: ไม่ต้องเก็บลง Firestore
  bool get isExpired {
    if (expiryDate == null) return false;
    return _dateOnly(expiryDate!).isBefore(_today());
  }

  /// เหลือกี่วัน (ตัดเวลาออก)
  int? get daysLeft {
    if (expiryDate == null) return null;
    return _dateOnly(expiryDate!).difference(_today()).inDays;
  }

  factory ShoppingItem.fromMap(
    Map<String, dynamic> map,
    String id, {
    String? ownerId,
    String? familyId,
    DocumentReference<Map<String, dynamic>>? reference,
  }) {
    String _normalizeString(dynamic value) {
      if (value is String) return value.trim();
      if (value == null) return '';
      return value.toString().trim();
    }

    final String resolvedOwner = _normalizeString(
      ownerId ?? map['ownerId'] ?? map['owner_id'],
    );
    final String resolvedFamily = _normalizeString(
      familyId ?? map['familyId'] ?? map['family_id'],
    );

    return ShoppingItem(
      id: id,
      name: (map['name'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      quantity: _toInt(map['quantity']),
      unit: (map['unit'] ?? '').toString(),
      expiryDate: _toDateTime(map['expiry_date']),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      ownerId: resolvedOwner,
      familyId: resolvedFamily.isEmpty ? null : resolvedFamily,
      reference: reference,
      price: _toDouble(map['price']),
      pricePerCanonicalUnit: _toDouble(map['price_per_canonical_unit']),
      priceCanonicalUnit:
          (map['price_canonical_unit'] ?? '').toString().trim().isEmpty
              ? null
              : (map['price_canonical_unit'] ?? '').toString(),
      priceRecordedAt: _toDateTime(map['price_recorded_at']),
      priceRecordedAtLocal: _toDateTime(map['price_recorded_at_local']),
    );
  }

  /// ใช้สำหรับเขียนกลับ Firestore (อย่าบันทึก isExpired)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      // แนะนำให้แปลงเป็น Timestamp ตอนเขียน (ดูตัวอย่างด้านล่าง)
      'expiry_date': expiryDate,
      'imageUrl': imageUrl,
      'created_at': createdAt,
      'updated_at': updatedAt,
      if (ownerId.isNotEmpty) 'ownerId': ownerId,
      if ((familyId ?? '').isNotEmpty) 'familyId': familyId,
      if (price != null) 'price': price,
      if (pricePerCanonicalUnit != null)
        'price_per_canonical_unit': pricePerCanonicalUnit,
      if ((priceCanonicalUnit ?? '').isNotEmpty)
        'price_canonical_unit': priceCanonicalUnit,
      if (priceRecordedAt != null) 'price_recorded_at': priceRecordedAt,
      if (priceRecordedAtLocal != null)
        'price_recorded_at_local': priceRecordedAtLocal,
    };
  }

  ShoppingItem copyWith({
    String? name,
    String? category,
    int? quantity,
    String? unit,
    DateTime? expiryDate,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerId,
    String? familyId,
    DocumentReference<Map<String, dynamic>>? reference,
    double? price,
    double? pricePerCanonicalUnit,
    String? priceCanonicalUnit,
    DateTime? priceRecordedAt,
    DateTime? priceRecordedAtLocal,
  }) {
    return ShoppingItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      expiryDate: expiryDate ?? this.expiryDate,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
      familyId: familyId ?? this.familyId,
      reference: reference ?? this.reference,
      price: price ?? this.price,
      pricePerCanonicalUnit:
          pricePerCanonicalUnit ?? this.pricePerCanonicalUnit,
      priceCanonicalUnit: priceCanonicalUnit ?? this.priceCanonicalUnit,
      priceRecordedAt: priceRecordedAt ?? this.priceRecordedAt,
      priceRecordedAtLocal:
          priceRecordedAtLocal ?? this.priceRecordedAtLocal,
    );
  }

  // ---------- helpers ----------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }
    if (v is int) {
      // เผื่อเก็บเป็น epoch ms
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {}
    }
    return null;
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
