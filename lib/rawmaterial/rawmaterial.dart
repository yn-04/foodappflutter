import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddRawMaterialPage extends StatefulWidget {
  const AddRawMaterialPage({Key? key}) : super(key: key);

  @override
  State<AddRawMaterialPage> createState() => _AddRawMaterialPageState();
}

class _AddRawMaterialPageState extends State<AddRawMaterialPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _quantity = 1;
  String _selectedUnit = 'หน่วย';
  String _selectedExpiry = ''; // เปลี่ยนเป็นค่าว่างเพื่อบังคับเลือก
  String? _selectedCategory;
  DateTime? _customExpiryDate;
  bool _isLoading = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<String> _units = [
    'หน่วย',
    'กรัม',
    'กิโลกรัม',
    'ลิตร',
    'มิลลิลิตร',
    'ขวด',
    'ถุง',
    'กล่อง',
    'แผ่น',
    'ชิ้น',
  ];

  final List<String> _categories = [
    'เนื้อสัตว์',
    'ผัก',
    'ผลไม้',
    'เครื่องเทศ',
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _notesController.dispose();
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
      };

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

        _showSuccessSnackBar('เพิ่มวัตถุดิบเรียบร้อยแล้ว (ID: ${docRef.id})');
        _clearForm();
        _loadRecentMaterials();
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

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _notesController.clear();
    setState(() {
      _quantity = 1;
      _selectedUnit = 'หน่วย';
      _selectedExpiry = ''; // เปลี่ยนให้เป็นค่าว่างเพื่อบังคับเลือก
      _selectedCategory = null;
      _customExpiryDate = null;
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        title: const Text(
          'เพิ่มวัตถุดิบ',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.list, color: Colors.black),
            onPressed: () async {
              final user = _auth.currentUser;
              if (user != null) {
                final snapshot = await _firestore
                    .collection('users')
                    .doc(user.uid)
                    .collection('raw_materials')
                    .get();

                print('Found ${snapshot.docs.length} raw materials');
                for (var doc in snapshot.docs) {
                  print('Material: ${doc.data()}');
                }

                _showSuccessSnackBar(
                  'พบวัตถุดิบ ${snapshot.docs.length} รายการ (ดู console)',
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    color: const Color(0xFFf9a825).withOpacity(0.1),
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

  Widget _buildQuantityControls() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                if (_quantity > 1) {
                  setState(() {
                    _quantity--;
                  });
                }
              },
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: const Color(0xFFf9a825),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.remove, size: 20, color: Colors.black),
              ),
            ),
            Text(
              '$_quantity',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _quantity++;
                });
              },
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: const Color(0xFFf9a825),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add, size: 20, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        color: isSelected ? const Color(0xFFf9a825) : Colors.white,
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
            color: Color(0xFFf9a825),
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
