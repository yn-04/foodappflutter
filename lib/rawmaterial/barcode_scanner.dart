// lib/rawmaterial/barcode_scanner.dart — สแกนบาร์โค้ดด้วย ML Kit + Image Picker
// หน้าที่: เลือกรูป/ถ่ายรูป -> อ่านบาร์โค้ด -> ดึงข้อมูลสินค้า/เติมฟอร์ม
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:my_app/rawmaterial/addraw.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class WorkingBarcodeScanner extends StatefulWidget {
  @override
  _WorkingBarcodeScannerState createState() => _WorkingBarcodeScannerState();
}

class _WorkingBarcodeScannerState extends State<WorkingBarcodeScanner> {
  final ImagePicker _picker = ImagePicker();
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isProcessing = false;

  @override
  void dispose() {
    _barcodeScanner.close();
    super.dispose();
  }

  // สแกนจากกล้อง
  Future<void> _scanFromCamera() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      _showError('ไม่ได้รับอนุญาตใช้กล้อง');
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (image != null) {
        await _processImage(image.path);
      }
    } catch (e) {
      _showError('เกิดข้อผิดพลาด: $e');
    }
  }

  // สแกนจากรูปใน Gallery
  Future<void> _scanFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null) {
        await _processImage(image.path);
      }
    } catch (e) {
      _showError('เกิดข้อผิดพลาด: $e');
    }
  }

  // ประมวลผลรูปภาพ
  Future<void> _processImage(String imagePath) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        final barcode = barcodes.first.rawValue;
        if (barcode != null && barcode.isNotEmpty) {
          // print('Barcode found: $barcode');
          await _handleBarcodeFound(barcode);
        } else {
          _showError('ไม่พบบาร์โค้ดในรูปภาพ');
        }
      } else {
        _showError('ไม่พบบาร์โค้ดในรูปภาพ');
      }
    } catch (e) {
      // print('Process image error: $e');
      _showError('ไม่สามารถประมวลผลรูปภาพได้');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // จัดการเมื่อพบบาร์โค้ด
  Future<void> _handleBarcodeFound(String barcode) async {
    // Loading

    Map<String, dynamic>? productData;
    try {
      productData = await _getProductFromOpenFoodFacts(barcode);
      productData ??= await _searchProductInFirebase(barcode);
    } finally {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop(); // ปิด loading
      }
    }

    if (!mounted) return;

    // ไปหน้า AddRawMaterialPage ทันที
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddRawMaterialPage(
          scannedBarcode: barcode,
          scannedProductData: productData,
        ),
      ),
    );

    // กลับจากหน้า Add แล้วปิดหน้า Scanner เอง
    if (mounted) {
      Navigator.of(context).pop(); // กลับไป ShoppingListScreen
    }
  }

  // ดึงข้อมูลจาก OpenFoodFacts API
  Future<Map<String, dynamic>?> _getProductFromOpenFoodFacts(
    String barcode,
  ) async {
    try {
      // print('Fetching product data from OpenFoodFacts for barcode: $barcode');
      final url =
          'https://world.openfoodfacts.org/api/v0/product/$barcode.json';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              // ใส่ UA จริงเพื่อให้ OFF ติดต่อได้ (แนะนำแก้เป็นของริน)
              'User-Agent': 'RawMaterialApp/1.0 (contact: app@example.com)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];

          // แปลงหน่วยและปริมาณ
          final unitData = _parseQuantityAndUnit(product);

          return {
            'name': _getProductName(product),
            'category': _mapToOurCategory(product),
            'brand': _getBrand(product),
            'description': _getDescription(product),
            'imageUrl': _getImageUrl(product),
            'ingredients': _getIngredients(product),
            'nutrition': _getNutritionInfo(product),
            'defaultQuantity': unitData['quantity'],
            'unit': unitData['unit'],
            'originalQuantity': product['quantity'], // เก็บค่าเดิมไว้อ้างอิง
            'fromOpenFoodFacts': true,
          };
        }
      }
      return null;
    } catch (e) {
      // print('Error fetching from OpenFoodFacts: $e');
      return null;
    }
  }

  // แปลงหน่วยและปริมาณจากข้อมูล OpenFoodFacts
  Map<String, dynamic> _parseQuantityAndUnit(Map<String, dynamic> product) {
    String quantityStr = product['quantity']?.toString().toLowerCase() ?? '';

    // ลบช่องว่างและจัดรูปแบบ
    quantityStr = quantityStr.replaceAll(' ', '');

    // Pattern สำหรับจับค่าตัวเลขและหน่วย
    final patterns = [
      // กรัม: g, gram, grams, กรัม
      RegExp(r'(\d+(?:\.\d+)?)\s*g(?:ram)?s?(?![a-z])', caseSensitive: false),
      RegExp(r'(\d+(?:\.\d+)?)\s*กรัม'),

      // กิโลกรัม: kg, kilogram, kilograms, กก, กิโลกรัม
      RegExp(r'(\d+(?:\.\d+)?)\s*kg(?:s)?(?![a-z])', caseSensitive: false),
      RegExp(r'(\d+(?:\.\d+)?)\s*กก'),
      RegExp(r'(\d+(?:\.\d+)?)\s*กิโลกรัม'),

      // มิลลิลิตร: ml, milliliter, มล, มิลลิลิตร
      RegExp(r'(\d+(?:\.\d+)?)\s*ml(?![a-z])', caseSensitive: false),
      RegExp(r'(\d+(?:\.\d+)?)\s*มล'),
      RegExp(r'(\d+(?:\.\d+)?)\s*มิลลิลิตร'),

      // ลิตร: l, liter, liters, ลิตร
      RegExp(r'(\d+(?:\.\d+)?)\s*l(?:iter)?s?(?![a-z])', caseSensitive: false),
      RegExp(r'(\d+(?:\.\d+)?)\s*ลิตร'),

      // ชิ้น/ฟอง: pieces, pcs, count, x
      RegExp(
        r'(\d+)\s*(?:pieces?|pcs?|count|x|ชิ้น|ฟอง)',
        caseSensitive: false,
      ),
    ];

    for (int i = 0; i < patterns.length; i++) {
      final match = patterns[i].firstMatch(quantityStr);
      if (match != null) {
        final value = double.tryParse(match.group(1) ?? '');
        if (value != null) {
          String unit;
          int quantity;

          if (i <= 1) {
            unit = 'กรัม';
            quantity = value.round();
          } else if (i <= 4) {
            unit = 'กิโลกรัม';
            quantity = value.round();
          } else if (i <= 7) {
            unit = 'มิลลิลิตร';
            quantity = value.round();
          } else if (i <= 9) {
            unit = 'ลิตร';
            quantity = value.round();
          } else {
            unit = 'ชิ้น';
            quantity = value.round();
          }

          return {'quantity': quantity, 'unit': unit};
        }
      }
    }

    // ถ้าไม่พบ pattern ใดๆ ให้ใช้ค่าเริ่มต้น
    return {'quantity': 1, 'unit': 'ชิ้น'};
  }

  // ดึงข้อมูลจาก Firebase
  Future<Map<String, dynamic>?> _searchProductInFirebase(String barcode) async {
    try {
      // ค้นหาในฐานข้อมูลสินค้าทั่วไป
      final productSnapshot = await _firestore
          .collection('products')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (productSnapshot.docs.isNotEmpty) {
        final data = productSnapshot.docs.first.data();
        data['fromOpenFoodFacts'] = false;
        return data;
      }

      // ค้นหาในข้อมูลของผู้ใช้
      final user = _auth.currentUser;
      if (user != null) {
        final userProductSnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('barcode', isEqualTo: barcode)
            .limit(1)
            .get();

        if (userProductSnapshot.docs.isNotEmpty) {
          final data = userProductSnapshot.docs.first.data();
          data['fromOpenFoodFacts'] = false;
          return data;
        }
      }

      return null;
    } catch (e) {
      // print('Error searching product: $e');
      return null;
    }
  }

  // แสดงผลการสแกน

  // Helper functions สำหรับประมวลผลข้อมูล OpenFoodFacts
  String _getProductName(Map<String, dynamic> product) {
    if (product['product_name_th'] != null &&
        product['product_name_th'].toString().isNotEmpty) {
      return product['product_name_th'];
    } else if (product['product_name_en'] != null &&
        product['product_name_en'].toString().isNotEmpty) {
      return product['product_name_en'];
    } else if (product['product_name'] != null &&
        product['product_name'].toString().isNotEmpty) {
      return product['product_name'];
    }
    return 'ไม่ทราบชื่อสินค้า';
  }

  String _mapToOurCategory(Map<String, dynamic> product) {
    final categories = product['categories']?.toString().toLowerCase() ?? '';
    final categoryTags = product['categories_tags'] as List? ?? [];

    if (categories.contains('meat') ||
        categories.contains('เนื้อ') ||
        categoryTags.any((tag) => tag.toString().contains('meat'))) {
      return 'เนื้อสัตว์';
    } else if (categories.contains('vegetable') ||
        categories.contains('ผัก') ||
        categoryTags.any((tag) => tag.toString().contains('vegetable'))) {
      return 'ผัก';
    } else if (categories.contains('fruit') ||
        categories.contains('ผลไม้') ||
        categoryTags.any((tag) => tag.toString().contains('fruit'))) {
      return 'ผลไม้';
    } else if (categories.contains('spice') ||
        categories.contains('เครื่องเทศ') ||
        categoryTags.any((tag) => tag.toString().contains('spice'))) {
      return 'เครื่องเทศ';
    } else if (categories.contains('dairy') ||
        categories.contains('milk') ||
        categories.contains('นม') ||
        categoryTags.any(
          (tag) =>
              tag.toString().contains('dairy') ||
              tag.toString().contains('milk'),
        )) {
      return 'ผลิตภัณฑ์จากนม';
    } else if (categories.contains('beverage') ||
        categories.contains('drink') ||
        categories.contains('เครื่องดื่ม') ||
        categoryTags.any(
          (tag) =>
              tag.toString().contains('beverage') ||
              tag.toString().contains('drink'),
        )) {
      return 'เครื่องดื่ม';
    } else if (categories.contains('oil') ||
        categories.contains('น้ำมัน') ||
        categoryTags.any((tag) => tag.toString().contains('oil'))) {
      return 'น้ำมัน';
    }
    return 'ของแห้ง';
  }

  String? _getBrand(Map<String, dynamic> product) {
    if (product['brands'] != null && product['brands'].toString().isNotEmpty) {
      return product['brands'].toString().split(',').first.trim();
    }
    return null;
  }

  String? _getDescription(Map<String, dynamic> product) {
    final descriptions = <String>[];
    if (product['generic_name'] != null &&
        product['generic_name'].toString().isNotEmpty) {
      descriptions.add(product['generic_name']);
    }
    if (product['quantity'] != null &&
        product['quantity'].toString().isNotEmpty) {
      descriptions.add('ขนาด: ${product['quantity']}');
    }
    return descriptions.isNotEmpty ? descriptions.join(' | ') : null;
  }

  String? _getImageUrl(Map<String, dynamic> product) {
    if (product['image_url'] != null &&
        product['image_url'].toString().isNotEmpty) {
      return product['image_url'];
    } else if (product['image_front_url'] != null &&
        product['image_front_url'].toString().isNotEmpty) {
      return product['image_front_url'];
    }
    return null;
  }

  String? _getIngredients(Map<String, dynamic> product) {
    if (product['ingredients_text'] != null &&
        product['ingredients_text'].toString().isNotEmpty) {
      return product['ingredients_text'];
    } else if (product['ingredients_text_en'] != null &&
        product['ingredients_text_en'].toString().isNotEmpty) {
      return product['ingredients_text_en'];
    }
    return null;
  }

  Map<String, dynamic>? _getNutritionInfo(Map<String, dynamic> product) {
    final nutriments = product['nutriments'] as Map<String, dynamic>?;
    if (nutriments == null) return null;

    final nutrition = <String, dynamic>{};
    if (nutriments['energy-kcal_100g'] != null) {
      nutrition['calories'] = nutriments['energy-kcal_100g'];
    }
    if (nutriments['proteins_100g'] != null) {
      nutrition['protein'] = nutriments['proteins_100g'];
    }
    if (nutriments['carbohydrates_100g'] != null) {
      nutrition['carbs'] = nutriments['carbohydrates_100g'];
    }
    if (nutriments['fat_100g'] != null) {
      nutrition['fat'] = nutriments['fat_100g'];
    }
    return nutrition.isNotEmpty ? nutrition : null;
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.error_outline, color: Colors.red[600]),
            ),
            const SizedBox(width: 12),
            Text('เกิดข้อผิดพลาด', style: TextStyle(color: Colors.red[700])),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'สแกนบาร์โค้ด',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey[50]!],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon และข้อความหลัก
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF5F5F5), Color(0xFFF5F5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        FontAwesomeIcons.barcode,
                        size: 80,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'สแกนบาร์โค้ดสินค้า',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ปุ่มถ่ายรูป
              Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[600],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scanFromCamera,
                  icon: const Icon(Icons.camera_alt, size: 24),
                  label: const Text(
                    'ถ่ายรูปบาร์โค้ด',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ปุ่มเลือกจากแกลลอรี่
              Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[600],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scanFromGallery,
                  icon: const Icon(Icons.photo_library, size: 24),
                  label: const Text(
                    'เลือกรูปจากแกลลอรี่',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // แสดง Loading เมื่อกำลังประมวลผล
              if (_isProcessing) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey[200]!,
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'กรุณารอสักครู่',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
