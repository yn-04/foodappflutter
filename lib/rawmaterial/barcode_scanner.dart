// ไฟล์ lib/rawmaterial/working_barcode_scanner.dart
// วิธีแก้ที่แน่นอน - ใช้ image_picker แทน camera stream
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

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
          print('Barcode found: $barcode');
          await _handleBarcodeFound(barcode);
        } else {
          _showError('ไม่พบบาร์โค้ดในรูปภาพ');
        }
      } else {
        _showError('ไม่พบบาร์โค้ดในรูปภาพ');
      }
    } catch (e) {
      print('Process image error: $e');
      _showError('ไม่สามารถประมวลผลรูปภาพได้');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // จัดการเมื่อพบบาร์โค้ด
  Future<void> _handleBarcodeFound(String barcode) async {
    // แสดง Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('กำลังค้นหาข้อมูลสินค้า...'),
          ],
        ),
      ),
    );

    // ค้นหาข้อมูลจาก OpenFoodFacts
    Map<String, dynamic>? productData = await _getProductFromOpenFoodFacts(
      barcode,
    );

    // ถ้าไม่พบใน OpenFoodFacts ค้นหาใน Firebase
    if (productData == null) {
      productData = await _searchProductInFirebase(barcode);
    }

    // ปิด Loading dialog
    if (mounted) {
      Navigator.of(context).pop();
    }

    // แสดงผลการค้นหา
    if (mounted) {
      await _showBarcodeResult(barcode, productData);
    }
  }

  // ดึงข้อมูลจาก OpenFoodFacts API
  Future<Map<String, dynamic>?> _getProductFromOpenFoodFacts(
    String barcode,
  ) async {
    try {
      print('Fetching product data from OpenFoodFacts for barcode: $barcode');

      final url =
          'https://world.openfoodfacts.org/api/v0/product/$barcode.json';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'RawMaterialApp/1.0 (your.email@example.com)',
            },
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          return {
            'name': _getProductName(product),
            'category': _mapToOurCategory(product),
            'brand': _getBrand(product),
            'description': _getDescription(product),
            'imageUrl': _getImageUrl(product),
            'ingredients': _getIngredients(product),
            'nutrition': _getNutritionInfo(product),
            'fromOpenFoodFacts': true,
          };
        }
      }
      return null;
    } catch (e) {
      print('Error fetching from OpenFoodFacts: $e');
      return null;
    }
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
        return productSnapshot.docs.first.data();
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
          return userProductSnapshot.docs.first.data();
        }
      }

      return null;
    } catch (e) {
      print('Error searching product: $e');
      return null;
    }
  }

  // แสดงผลการสแกน
  Future<void> _showBarcodeResult(
    String barcode,
    Map<String, dynamic>? productData,
  ) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('พบบาร์โค้ด')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // แสดงบาร์โค้ด
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.qr_code, color: Colors.grey[600]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        barcode,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),

              if (productData != null) ...[
                // แสดงแหล่งข้อมูล
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: productData['fromOpenFoodFacts'] == true
                        ? Colors.green[100]
                        : Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    productData['fromOpenFoodFacts'] == true
                        ? '📊 OpenFoodFacts'
                        : '🔥 Firebase',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: productData['fromOpenFoodFacts'] == true
                          ? Colors.green[800]
                          : Colors.blue[800],
                    ),
                  ),
                ),
                SizedBox(height: 12),

                Text(
                  'พบข้อมูลสินค้า:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),

                // รูปภาพสินค้า
                if (productData['imageUrl'] != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      productData['imageUrl'],
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 120,
                          color: Colors.grey[200],
                          child: Icon(Icons.image_not_supported),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 8),
                ],

                // ข้อมูลสินค้า
                Text('ชื่อ: ${productData['name']}'),
                Text('หมวดหมู่: ${productData['category']}'),
                if (productData['brand'] != null)
                  Text('ยี่ห้อ: ${productData['brand']}'),
                if (productData['description'] != null)
                  Text('คำอธิบาย: ${productData['description']}'),
              ] else ...[
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ไม่พบข้อมูลสินค้า\nคุณสามารถเพิ่มข้อมูลใหม่ได้',
                          style: TextStyle(color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).pop({'barcode': barcode, 'productData': productData});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(
              productData != null ? 'เพิ่มสินค้า' : 'เพิ่มข้อมูลใหม่',
            ),
          ),
        ],
      ),
    );
  }

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
    List<String> descriptions = [];
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

    Map<String, dynamic> nutrition = {};
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
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('เกิดข้อผิดพลาด'),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('ตกลง'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('สแกนบาร์โค้ด'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.qr_code_scanner, size: 120, color: Colors.green),
            SizedBox(height: 30),

            Text(
              'เลือกวิธีสแกนบาร์โค้ด',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),

            Text(
              'ระบบจะค้นหาข้อมูลจาก OpenFoodFacts อัตโนมัติ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),

            // ปุ่มถ่ายรูป
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _scanFromCamera,
              icon: Icon(Icons.camera_alt, size: 24),
              label: Text('ถ่ายรูปบาร์โค้ด', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            SizedBox(height: 20),

            // ปุ่มเลือกจากแกลลอรี่
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _scanFromGallery,
              icon: Icon(Icons.photo_library, size: 24),
              label: Text(
                'เลือกรูปจากแกลลอรี่',
                style: TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            SizedBox(height: 30),

            if (_isProcessing) ...[
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('กำลังประมวลผลรูปภาพ...'),
                  ],
                ),
              ),
            ],

            Spacer(),

            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600]),
                  SizedBox(height: 8),
                  Text(
                    'ทิปส์: ตรวจสอบให้แน่ใจว่าบาร์โค้ดในรูปภาพชัดเจนและมีแสงเพียงพอ',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
