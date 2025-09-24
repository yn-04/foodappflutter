// lib/rawmaterial/barcode_scanner.dart — สแกนบาร์โค้ดด้วย ML Kit + Image Picker
// หน้าที่: เลือกรูป/ถ่ายรูป -> อ่านบาร์โค้ด -> ดึงข้อมูลสินค้า/เติมฟอร์ม
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(50),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'กำลังค้นหาข้อมูลสินค้า...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'กรุณารอสักครู่',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
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
      print('Error fetching from OpenFoodFacts: $e');
      return null;
    }
  }

  // แปลงหน่วยและปริมาณจากข้อมูล OpenFoodFacts
  Map<String, dynamic> _parseQuantityAndUnit(Map<String, dynamic> product) {
    String quantityStr = product['quantity']?.toString().toLowerCase() ?? '';

    // ลบช่องว่างและจัดรูปแบบ
    quantityStr = quantityStr.replaceAll(' ', '');

    print('Original quantity: $quantityStr');

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

    // ลองจับแต่ละ pattern
    for (int i = 0; i < patterns.length; i++) {
      final match = patterns[i].firstMatch(quantityStr);
      if (match != null) {
        final value = double.tryParse(match.group(1) ?? '');
        if (value != null) {
          print('Matched pattern $i: ${match.group(0)} -> value: $value');

          // กำหนดหน่วยตามลำดับ pattern
          String unit;
          int quantity;

          if (i <= 1) {
            // กรัม patterns
            unit = 'กรัม';
            quantity = value.round();
          } else if (i <= 4) {
            // กิโลกรัม patterns
            unit = 'กิโลกรัม';
            quantity = value.round();
          } else if (i <= 7) {
            // มิลลิลิตร patterns
            unit = 'มิลลิลิตร';
            quantity = value.round();
          } else if (i <= 9) {
            // ลิตร patterns
            unit = 'ลิตร';
            quantity = value.round();
          } else {
            // ชิ้น/ฟอง patterns
            unit = 'ชิ้น';
            quantity = value.round();
          }

          print('Converted to: $quantity $unit');
          return {'quantity': quantity, 'unit': unit};
        }
      }
    }

    // ถ้าไม่พบ pattern ใดๆ ให้ใช้ค่าเริ่มต้น
    print('No pattern matched, using default');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green[400]!, Colors.green[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'พบบาร์โค้ด',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            barcode,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Container(
                padding: EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (productData != null) ...[
                        // แสดงแหล่งข้อมูล
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: productData['fromOpenFoodFacts'] == true
                                ? LinearGradient(
                                    colors: [
                                      Colors.green[100]!,
                                      Colors.green[50]!,
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.blue[100]!,
                                      Colors.blue[50]!,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: productData['fromOpenFoodFacts'] == true
                                  ? Colors.green[300]!
                                  : Colors.blue[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                productData['fromOpenFoodFacts'] == true
                                    ? Icons.public
                                    : Icons.cloud,
                                size: 16,
                                color: productData['fromOpenFoodFacts'] == true
                                    ? Colors.green[700]
                                    : Colors.blue[700],
                              ),
                              SizedBox(width: 6),
                              Text(
                                productData['fromOpenFoodFacts'] == true
                                    ? 'OpenFoodFacts'
                                    : 'Firebase',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      productData['fromOpenFoodFacts'] == true
                                      ? Colors.green[800]
                                      : Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        // รูปภาพสินค้า
                        if (productData['imageUrl'] != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              productData['imageUrl'],
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 150,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.image_not_supported,
                                        size: 40,
                                        color: Colors.grey[400],
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'ไม่สามารถโหลดรูปภาพได้',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(height: 16),
                        ],

                        // ข้อมูลสินค้า
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow(
                                '📦',
                                'ชื่อสินค้า',
                                productData['name'],
                              ),
                              SizedBox(height: 8),
                              _buildInfoRow(
                                '🏷️',
                                'หมวดหมู่',
                                productData['category'],
                              ),
                              if (productData['brand'] != null) ...[
                                SizedBox(height: 8),
                                _buildInfoRow(
                                  '🏢',
                                  'ยี่ห้อ',
                                  productData['brand'],
                                ),
                              ],
                              if (productData['defaultQuantity'] != null &&
                                  productData['unit'] != null) ...[
                                SizedBox(height: 8),
                                _buildInfoRow(
                                  '⚖️',
                                  'ปริมาณแนะนำ',
                                  '${productData['defaultQuantity']} ${productData['unit']}',
                                ),
                              ],
                              if (productData['originalQuantity'] != null) ...[
                                SizedBox(height: 8),
                                _buildInfoRow(
                                  '📏',
                                  'ขนาดจากบรรจุภัณฑ์',
                                  productData['originalQuantity'],
                                ),
                              ],
                              if (productData['description'] != null) ...[
                                SizedBox(height: 8),
                                _buildInfoRow(
                                  '📝',
                                  'รายละเอียด',
                                  productData['description'],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange[50]!, Colors.orange[25]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Icon(
                                  Icons.info_outline,
                                  color: Colors.orange[700],
                                  size: 32,
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'ไม่พบข้อมูลสินค้า',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.orange[800],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'คุณสามารถเพิ่มข้อมูลสินค้าใหม่ได้\nระบบจะบันทึกข้อมูลสำหรับการใช้งานครั้งต่อไป',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ปิด', style: TextStyle(color: Colors.grey[600])),
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
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_shopping_cart, size: 18),
                SizedBox(width: 8),
                Text(
                  productData != null ? 'เพิ่มสินค้า' : 'เพิ่มข้อมูลใหม่',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: TextStyle(fontSize: 16)),
        SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: Colors.black87, fontSize: 14),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(Icons.error_outline, color: Colors.red[600]),
              ),
              SizedBox(width: 12),
              Text('เกิดข้อผิดพลาด', style: TextStyle(color: Colors.red[700])),
            ],
          ),
          content: Text(message, style: TextStyle(fontSize: 16)),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
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
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon และข้อความหลัก
              Container(
                padding: EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 245, 245, 245),
                      const Color.fromARGB(255, 245, 245, 245),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(20),
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
                    SizedBox(height: 20),
                    Text(
                      'สแกนบาร์โค้ดสินค้า',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              ),

              SizedBox(height: 40),

              // ปุ่มถ่ายรูป
              Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[600],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scanFromCamera,
                  icon: Icon(Icons.camera_alt, size: 24),
                  label: Text(
                    'ถ่ายรูปบาร์โค้ด',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                    padding: EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),

              SizedBox(height: 16),

              // ปุ่มเลือกจากแกลลอรี่
              Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[600],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scanFromGallery,
                  icon: Icon(Icons.photo_library, size: 24),
                  label: Text(
                    'เลือกรูปจากแกลลอรี่',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                    padding: EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),

              SizedBox(height: 32),

              // แสดง Loading เมื่อกำลังประมวลผล
              if (_isProcessing) ...[
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey[200]!,
                        blurRadius: 15,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
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
                      SizedBox(height: 16),
                      Text(
                        'กำลังประมวลผลรูปภาพ...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'กรุณารอสักครู่',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
