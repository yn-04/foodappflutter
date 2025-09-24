// lib/rawmaterial/constants/categories.dart — รายชื่อหมวดหมู่ + helper icon + label "ทั้งหมด"
import 'package:flutter/material.dart';

/// ตัวช่วยจัดการหมวดหมู่ของวัตถุดิบ
class Categories {
  /// ป้าย “ทั้งหมด” ใช้เป็นค่าเริ่มต้นของตัวกรอง
  static const String allLabel = 'ทั้งหมด';

  /// alias ให้เรียกสั้น ๆ ได้
  static String get all => allLabel;

  /// รายชื่อหมวดมาตรฐาน (ไม่รวม “ทั้งหมด”)
  static const List<String> list = <String>[
    'เนื้อสัตว์',
    'ไข่',
    'ผัก',
    'ผลไม้',
    'ผลิตภัณฑ์จากนม',
    'ข้าว',
    'เครื่องเทศ',
    'เครื่องปรุง',
    'แป้ง',
    'น้ำมัน',
    'เครื่องดื่ม',
    'ของแห้ง',
    'ของแช่แข็ง',
  ];

  /// คืนรายการหมวดที่มี “ทั้งหมด” อยู่หน้าเสมอ
  static List<String> withAll([List<String>? extras]) {
    final set = <String>{...list, ...?extras};
    return [allLabel, ...set.toList()..sort()];
  }

  /// ตรวจชื่อหมวดว่าอยู่ในชุดมาตรฐานหรือไม่ (ไม่รวม “ทั้งหมด”)
  static bool isKnown(String category) => list.contains(category);

  /// เลือกไอคอนให้เหมาะกับหมวด
  static IconData iconFor(String category) {
    switch (category) {
      case 'เนื้อสัตว์':
        return Icons.set_meal;
      case 'ไข่':
        return Icons.egg_alt;
      case 'ผัก':
        return Icons.eco;
      case 'ผลไม้':
        return Icons.apple;
      case 'ผลิตภัณฑ์จากนม':
        return Icons.icecream;
      case 'ข้าว':
        return Icons.rice_bowl;
      case 'เครื่องเทศ':
        return Icons.grain;
      case 'เครื่องปรุง':
        return Icons.soup_kitchen;
      case 'แป้ง':
        return Icons.bakery_dining;
      case 'น้ำมัน':
        return Icons.opacity;
      case 'เครื่องดื่ม':
        return Icons.local_drink;
      case 'ของแห้ง':
        return Icons.inventory_2;
      case 'ของแช่แข็ง':
        return Icons.ac_unit;
      case allLabel:
        return Icons.all_inclusive_rounded;
      default:
        return Icons.category;
    }
  }

  /// ทำความสะอาดชื่อหมวด (trim) และ map ชื่อที่ใกล้เคียงให้เป็นหมวดที่รู้จัก
  static String normalize(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return s;
    // ถ้าตรงก็ใช้เลย
    if (isKnown(s) || s == allLabel) return s;

    // ตัวอย่าง mapping เพิ่มเติม (แก้ typo ทั่วไป)
    switch (s) {
      case 'นม':
        return 'ผลิตภัณฑ์จากนม';
      case 'แป้ง/เบเกอรี่':
        return 'แป้ง';
      case 'สไปซ์':
        return 'เครื่องเทศ';
      default:
        return s; // ไม่รู้จักก็คืนค่าเดิม
    }
  }
}
