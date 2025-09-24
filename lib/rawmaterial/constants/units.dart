// lib/rawmaterial/constants/units.dart — ค่าหน่วยวัตถุดิบ + helper ตรวจสอบ/ทำให้ปลอดภัย
class Units {
  static const List<String> all = [
    'กรัม',
    'ฟอง',
    'กิโลกรัม',
    'ลิตร',
    'มิลลิลิตร',
    'ขวด',
    'ชิ้น',
  ];

  /// ตรวจสอบว่า unit ที่ส่งมาอยู่ใน list ไหม
  static bool isValid(String? unit) {
    if (unit == null) return false;
    return all.contains(unit);
  }

  /// คืนค่า unit ที่ปลอดภัย ถ้าไม่ valid จะ fallback เป็นค่าแรก
  static String safe(String? unit) {
    if (unit == null || !isValid(unit)) {
      return all.first; // ค่า default = 'กรัม'
    }
    return unit;
  }
}
