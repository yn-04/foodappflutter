import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddRawMaterialPage extends StatefulWidget {
  // เพิ่ม parameters สำหรับรับข้อมูลจากบาร์โค้ด
  final String? scannedBarcode;
  final Map<String, dynamic>? scannedProductData;

  const AddRawMaterialPage({
    super.key,
    this.scannedBarcode,
    this.scannedProductData,
  });

  @override
  State<AddRawMaterialPage> createState() => _AddRawMaterialPageState();
}

class _AddRawMaterialPageState extends State<AddRawMaterialPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _barcodeController =
      TextEditingController(); // เพิ่มสำหรับบาร์โค้ด
  final TextEditingController _brandController =
      TextEditingController(); // เพิ่มสำหรับยี่ห้อ
  // 1. เพิ่มตัวแปรนี้ในส่วน class variables (หลัง _brandController):
  final TextEditingController _quantityController = TextEditingController();

  int _quantity = 1;
  String _selectedUnit = 'กรัม';
  String _selectedExpiry = ''; // เปลี่ยนเป็นค่าว่างเพื่อบังคับเลือก
  String? _selectedCategory;
  DateTime? _customExpiryDate;
  bool _isLoading = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<String> _units = [
    'กรัม',
    'ฟอง',
    'กิโลกรัม',
    'ลิตร',
    'มิลลิลิตร',
    'ขวด',
    'ชิ้น',
  ];

  final List<String> _categories = [
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

  List<String> _recentMaterials = [];

  @override
  void initState() {
    super.initState();
    _checkFirestoreConnection();
    _loadRecentMaterials();
    _initializeWithScannedData(); // เพิ่มการเติมข้อมูลจากบาร์โค้ด
    _quantityController.text = _quantity.toString(); // เพิ่มบรรทัดนี้
  }

  // เพิ่ม method สำหรับเติมข้อมูลจากบาร์โค้ด
  void _initializeWithScannedData() {
    // ถ้ามีข้อมูลจากบาร์โค้ด
    if (widget.scannedBarcode != null) {
      _barcodeController.text = widget.scannedBarcode!;
    }

    if (widget.scannedProductData != null) {
      final data = widget.scannedProductData!;

      _nameController.text = data['name'] ?? '';
      _brandController.text = data['brand'] ?? '';
      _notesController.text = data['description'] ?? '';

      if (data['category'] != null && _categories.contains(data['category'])) {
        _selectedCategory = data['category'];
      }

      if (data['unit'] != null && _units.contains(data['unit'])) {
        _selectedUnit = data['unit'];
      }

      // ถ้ามีจำนวนเริ่มต้น
      if (data['defaultQuantity'] != null) {
        _quantity = data['defaultQuantity'];
      }

      // ถ้ามีราคาเริ่มต้น
      if (data['price'] != null) {
        _priceController.text = data['price'].toString();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    _barcodeController.dispose();
    _brandController.dispose();
    _quantityController.dispose(); // เพิ่มบรรทัดนี้
    super.dispose();
  }

  Future<void> _checkFirestoreConnection() async {
    try {
      await _firestore.enableNetwork();
      print('Firestore connection: OK');

      await _firestore.collection('connection_test').doc('test').set({
        'timestamp': DateTime.now().toIso8601String(),
        'test': true,
      });
      print('Connection test write: SUCCESS');

      final user = _auth.currentUser;
      if (user != null) {
        print('User authenticated: ${user.uid}');
        print('User email: ${user.email}');
        print('User anonymous: ${user.isAnonymous}');
      } else {
        print('No user authenticated');
      }
    } catch (e) {
      print('Firestore connection error: $e');
    }
  }

  Future<void> _loadRecentMaterials() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .orderBy('created_at', descending: true)
            .limit(10)
            .get();

        setState(() {
          _recentMaterials = snapshot.docs
              .map((doc) => doc.data()['name'] as String)
              .toSet()
              .toList();
        });
      }
    } catch (e) {
      print('Error loading recent materials: $e');
    }
  }

  Future<void> _saveRawMaterial() async {
    // ตรวจสอบข้อมูลที่บังคับกรอก
    if (_nameController.text.trim().isEmpty) {
      _showErrorSnackBar('กรุณาใส่ชื่อวัตถุดิบ');
      return;
    }

    if (_selectedCategory == null) {
      _showErrorSnackBar('กรุณาเลือกหมวดหมู่');
      return;
    }

    if (_quantity <= 0) {
      _showErrorSnackBar('กรุณาระบุจำนวนที่มากกว่า 0');
      return;
    }

    if (_selectedUnit.isEmpty) {
      _showErrorSnackBar('กรุณาเลือกหน่วย');
      return;
    }

    if (_selectedExpiry.isEmpty) {
      _showErrorSnackBar('กรุณาเลือกวันหมดอายุ');
      return;
    }

    // ตรวจสอบกรณีเลือก "กำหนดเอง" แต่ไม่ได้เลือกวันที่
    if (_selectedExpiry == 'กำหนดเอง' && _customExpiryDate == null) {
      _showErrorSnackBar('กรุณาเลือกวันที่หมดอายุ');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      print('Current user: ${user?.uid}');
      print('User email: ${user?.email}');
      print('User is anonymous: ${user?.isAnonymous}');

      if (user == null) {
        _showErrorSnackBar('กรุณาเข้าสู่ระบบก่อน');
        return;
      }

      DateTime? expiryDate;
      if (_selectedExpiry == '+ 3 วัน') {
        expiryDate = DateTime.now().add(const Duration(days: 3));
      } else if (_selectedExpiry == '+ 7 วัน') {
        expiryDate = DateTime.now().add(const Duration(days: 7));
      } else if (_selectedExpiry == '+ 14 วัน') {
        expiryDate = DateTime.now().add(const Duration(days: 14));
      } else if (_selectedExpiry == 'กำหนดเอง') {
        expiryDate = _customExpiryDate;
      }
      // หมายเหตุ: ถ้าเลือก "ไม่มี" จะไม่ตั้งค่า expiryDate (จะเป็น null)

      final rawMaterialData = {
        'name': _nameController.text.trim(),
        'quantity': _quantity,
        'unit': _selectedUnit,
        'category': _selectedCategory,
        'expiry_date': expiryDate?.toIso8601String(),
        'price': _priceController.text.isNotEmpty
            ? double.tryParse(_priceController.text)
            : null,
        'notes': _notesController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'user_id': user.uid,
        'imageUrl': '', // เพิ่มสำหรับรูปภาพ (ว่างไว้ก่อน)
      };

      // เพิ่มข้อมูลจากบาร์โค้ดถ้ามี
      if (widget.scannedBarcode != null) {
        rawMaterialData['barcode'] = widget.scannedBarcode!;
      }

      if (_brandController.text.trim().isNotEmpty) {
        rawMaterialData['brand'] = _brandController.text.trim();
      }

      print('Saving data: $rawMaterialData');

      final testDocRef = _firestore.collection('raw_materials_test').doc();

      await testDocRef.set(rawMaterialData);
      print('Test data saved with ID: ${testDocRef.id}');

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .doc();

      await docRef.set(rawMaterialData);
      print('Data saved with ID: ${docRef.id}');

      // บันทึกข้อมูลสินค้าในฐานข้อมูลทั่วไป (ถ้ามีบาร์โค้ดและยังไม่มีในระบบ)
      if (widget.scannedBarcode != null && widget.scannedProductData == null) {
        await _saveProductToDatabase(rawMaterialData);
      }

      final savedDoc = await docRef.get();
      if (savedDoc.exists) {
        print('Verified: Document exists in Firestore');
        print('Document data: ${savedDoc.data()}');

        final allDocs = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .get();

        print('Total documents in raw_materials: ${allDocs.docs.length}');

        // แสดงข้อความสำเร็จ
        _showSuccessSnackBar(
          '✅ เพิ่มวัตถุดิบ "${_nameController.text.trim()}" เรียบร้อยแล้ว',
        );

        // รอ 1.5 วินาทีแล้วกลับไปหน้าหลัก
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pop(context, true); // ส่งค่า true เพื่อบอกว่าเพิ่มสำเร็จ
          }
        });
      } else {
        print('Error: Document was not saved');
        _showErrorSnackBar('ข้อมูลไม่ถูกบันทึก กรุณาลองใหม่');
      }
    } catch (e) {
      print('Save error: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาด: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // เพิ่ม method สำหรับบันทึกข้อมูลสินค้าในฐานข้อมูลทั่วไป
  Future<void> _saveProductToDatabase(Map<String, dynamic> productData) async {
    try {
      await _firestore.collection('products').doc(widget.scannedBarcode!).set({
        'barcode': widget.scannedBarcode,
        'name': productData['name'],
        'category': productData['category'],
        'brand': productData['brand'],
        'description': productData['notes'],
        'unit': productData['unit'],
        'created_at': FieldValue.serverTimestamp(),
        'created_by': _auth.currentUser?.uid,
      }, SetOptions(merge: true));
      print('Product data saved to general database');
    } catch (e) {
      print('Error saving product to database: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectCustomExpiryDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.amber,
              onPrimary: Colors.black,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customExpiryDate = picked;
        _selectedExpiry = 'กำหนดเอง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เพิ่มวัตถุดิบ',
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            // แสดงข้อมูลบาร์โค้ดถ้ามี
            if (widget.scannedBarcode != null)
              Text(
                'จากบาร์โค้ด: ${widget.scannedBarcode}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ถ้ามีข้อมูลจากบาร์โค้ด แสดง Banner
              if (widget.scannedBarcode != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.qr_code_scanner,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ข้อมูลจากบาร์โค้ด',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                            Text(
                              widget.scannedProductData != null
                                  ? 'พบข้อมูลในระบบ - กรุณาตรวจสอบความถูกต้อง'
                                  : 'ไม่พบข้อมูลในระบบ - กรุณากรอกข้อมูลใหม่',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 30),

              // Name field
              _buildNameField(),

              const SizedBox(height: 20),

              // Category selection
              _buildCategoryDropdown(),

              const SizedBox(height: 30),

              // Section title
              _buildSectionTitle('รายละเอียดวัตถุดิบ *'),

              const SizedBox(height: 20),

              // Quantity and unit row
              Row(
                children: [
                  Expanded(flex: 2, child: _buildQuantityControls()),
                  const SizedBox(width: 15),
                  Expanded(child: _buildUnitDropdown()),
                ],
              ),

              const SizedBox(height: 20),

              // Price field
              _buildPriceField(),

              const SizedBox(height: 30),

              // Expiry section
              _buildSectionTitle('วันหมดอายุ *'),

              const SizedBox(height: 20),

              // Expiry options
              _buildExpiryOptions(),

              const SizedBox(height: 20),

              // ข้อมูลเพิ่มเติม (แสดงเฉพาะเมื่อมีบาร์โค้ด)
              if (widget.scannedBarcode != null) ...[
                _buildSectionTitle('ข้อมูลเพิ่มเติม'),
                const SizedBox(height: 20),
                _buildAdditionalInfoSection(),
                const SizedBox(height: 20),
              ],

              // Notes field
              _buildNotesField(),

              const SizedBox(height: 40),

              // Add button
              _buildAddButton(),
            ],
          ),
        ),
      ),
    );
  }

  // เพิ่ม method สำหรับข้อมูลเพิ่มเติม
  Widget _buildAdditionalInfoSection() {
    return Column(
      children: [
        // บาร์โค้ด
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: _barcodeController,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            decoration: const InputDecoration(
              hintText: '📊 บาร์โค้ด',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(20),
              prefixIcon: Icon(Icons.qr_code, color: Colors.black),
            ),
            enabled: false, // ไม่ให้แก้ไขได้
          ),
        ),
        const SizedBox(height: 20),

        // ยี่ห้อ
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.black),
          ),
          child: TextField(
            controller: _brandController,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            decoration: const InputDecoration(
              hintText: '🏷️ ยี่ห้อ (ไม่บังคับ)',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(20),
              prefixIcon: Icon(Icons.business_outlined, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.black),
          ),
          child: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            decoration: InputDecoration(
              hintText: '🥘 ชื่อวัตถุดิบ *',
              hintStyle: TextStyle(color: Colors.grey[500]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
              prefixIcon: const Icon(Icons.restaurant, color: Colors.black),
            ),
          ),
        ),
        if (_recentMaterials.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentMaterials.map((material) {
              return GestureDetector(
                onTap: () {
                  _nameController.text = material;
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.yellow[600]!.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black),
                  ),
                  child: Text(
                    material,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedCategory,
            isExpanded: true,
            hint: Row(
              children: [
                const Icon(Icons.category, color: Colors.black),
                const SizedBox(width: 12),
                Text(
                  'กรุณาเลือกหมวดหมู่ *',
                  style: TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Row(
                  children: [
                    Icon(
                      _getCategoryIcon(category),
                      color: Colors.black,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      category,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedCategory = newValue;
              });
            },
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'เนื้อสัตว์':
        return Icons.set_meal;
      case 'ผัก':
        return Icons.eco;
      case 'ผลไม้':
        return Icons.apple;
      case 'เครื่องเทศ':
        return Icons.grain;
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
      default:
        return Icons.category;
    }
  }

  // แทนที่ method _buildQuantityControls() เดิมด้วยโค้ดนี้

  Widget _buildQuantityControls() {
    return Row(
      children: [
        // ปุ่มลด
        GestureDetector(
          onTap: () {
            if (_quantity > 1) {
              setState(() {
                _quantity--;
                _quantityController.text = _quantity.toString();
              });
            }
          },
          child: Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.yellow[600],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.remove, size: 20, color: Colors.black),
          ),
        ),

        const SizedBox(width: 10),

        // ช่องป้อนตัวเลข (กรอบสีดำคลุมแค่ส่วนนี้)
        Expanded(
          child: Container(
            width: 25,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.black),
            ),
            child: TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onChanged: (value) {
                final parsedValue = int.tryParse(value);
                if (parsedValue != null && parsedValue > 0) {
                  setState(() {
                    _quantity = parsedValue;
                  });
                } else if (value.isEmpty) {
                  setState(() {
                    _quantity = 1;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(width: 10),

        // ปุ่มเพิ่ม
        GestureDetector(
          onTap: () {
            setState(() {
              _quantity++;
              _quantityController.text = _quantity.toString();
            });
          },
          child: Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.yellow[600],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add, size: 20, color: Colors.black),
          ),
        ),
      ],
    );
  }

  // 4. แก้ไข _buildUnitDropdown() ให้อัพเดทค่าแนะนำเมื่อเปลี่ยนหน่วย:
  Widget _buildUnitDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedUnit,
            icon: const Icon(
              Icons.arrow_drop_down,
              color: Colors.black,
              size: 20,
            ),
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            items: _units.map((String unit) {
              return DropdownMenuItem<String>(
                value: unit,
                child: Text(
                  unit,
                  style: const TextStyle(color: Colors.black87),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedUnit = newValue!;
                // อัพเดท hint text ใน quantity field
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black),
      ),
      child: TextField(
        controller: _priceController,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.black87, fontSize: 16),
        decoration: const InputDecoration(
          hintText: '💰 ราคาต่อหน่วย (ไม่บังคับ)',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(20),
          prefixIcon: Icon(Icons.attach_money, color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildExpiryOptions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedExpiry = '+ 3 วัน';
                    _customExpiryDate = null;
                  });
                },
                child: _buildExpiryButton(
                  '+ 3 วัน',
                  _selectedExpiry == '+ 3 วัน',
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedExpiry = '+ 7 วัน';
                    _customExpiryDate = null;
                  });
                },
                child: _buildExpiryButton(
                  '+ 7 วัน',
                  _selectedExpiry == '+ 7 วัน',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedExpiry = '+ 14 วัน';
                    _customExpiryDate = null;
                  });
                },
                child: _buildExpiryButton(
                  '+ 14 วัน',
                  _selectedExpiry == '+ 14 วัน',
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: GestureDetector(
                onTap: _selectCustomExpiryDate,
                child: _buildExpiryButton(
                  _customExpiryDate != null
                      ? '${_customExpiryDate!.day}/${_customExpiryDate!.month}/${_customExpiryDate!.year}'
                      : 'กำหนดเอง',
                  _selectedExpiry == 'กำหนดเอง',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black),
      ),
      child: TextField(
        controller: _notesController,
        maxLines: 3,
        style: const TextStyle(color: Colors.black87, fontSize: 16),
        decoration: const InputDecoration(
          hintText: '📝 หมายเหตุ (ไม่บังคับ)',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _buildExpiryButton(String text, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: isSelected ? Colors.yellow[600] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: isSelected ? 2 : 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today,
            size: 16,
            color: isSelected ? Colors.black : Colors.black,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.black : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveRawMaterial,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 0,
            ).copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
            ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.yellow,
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: _isLoading
              ? const SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_shopping_cart,
                      size: 24,
                      color: Colors.black,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'เพิ่มวัตถุดิบ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
