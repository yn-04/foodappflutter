// lib/rawmaterial/models/shopping_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ShoppingItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final DateTime? expiryDate;
  final String imageUrl;
  final bool isExpired;

  ShoppingItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    this.expiryDate,
    required this.imageUrl,
    required this.isExpired,
  });

  factory ShoppingItem.fromMap(Map<String, dynamic> map, String id) {
    DateTime? parsedExpiryDate;

    // ตรวจสอบและแปลงวันหมดอายุ
    if (map['expiry_date'] != null) {
      if (map['expiry_date'] is Timestamp) {
        parsedExpiryDate = (map['expiry_date'] as Timestamp).toDate();
      } else if (map['expiry_date'] is String) {
        try {
          parsedExpiryDate = DateTime.parse(map['expiry_date']);
        } catch (e) {
          print('Error parsing expiry_date: $e');
        }
      }
    }

    return ShoppingItem(
      id: id,
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      quantity: map['quantity'] ?? 0,
      unit: map['unit'] ?? '',
      expiryDate: parsedExpiryDate,
      imageUrl: map['imageUrl'] ?? '',
      isExpired: parsedExpiryDate != null
          ? parsedExpiryDate.isBefore(DateTime.now())
          : false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'expiry_date': expiryDate?.toIso8601String(),
      'imageUrl': imageUrl,
      'isExpired': isExpired,
    };
  }
}
