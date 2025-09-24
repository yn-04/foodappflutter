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

  factory ShoppingItem.fromMap(Map<String, dynamic> map, String id) {
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
    };
  }

  // ---------- helpers ----------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
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
