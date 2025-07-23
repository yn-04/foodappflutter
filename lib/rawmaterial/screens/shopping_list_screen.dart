// lib/screens/shopping_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/rawmaterial/addraw.dart';
import 'package:my_app/rawmaterial/barcode_scanner.dart';
import '../models/shopping_item.dart';
import '../widgets/shopping_item_card.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ShoppingListScreen extends StatefulWidget {
  @override
  _ShoppingListScreenState createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customDaysController = TextEditingController();

  String selectedCategory = 'ทั้งหมด';
  String searchQuery = '';
  String selectedExpiryFilter = 'ทั้งหมด';
  int? customDays;
  List<String> availableCategories = ['ทั้งหมด'];

  final List<String> expiryFilterOptions = [
    'ทั้งหมด',
    '1 วัน',
    '2 วัน',
    '3 วัน',
    '7 วัน',
    '14 วัน',
    'กำหนดเอง',
  ];

  User? get currentUser => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadAvailableCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  // ดึงหมวดหมู่ที่มีจริงใน Firebase
  void _loadAvailableCategories() async {
    if (currentUser == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('raw_materials')
          .get();

      Set<String> categories = {'ทั้งหมด'};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['category'] != null &&
            data['category'].toString().isNotEmpty) {
          categories.add(data['category'].toString());
        }
      }

      setState(() {
        availableCategories = categories.toList();
        if (!availableCategories.contains(selectedCategory)) {
          selectedCategory = 'ทั้งหมด';
        }
      });
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  // กรองข้อมูลตามคำค้นหา
  List<ShoppingItem> _filterItemsBySearch(List<ShoppingItem> items) {
    if (searchQuery.isEmpty) return items;
    return items.where((item) {
      return item.name.toLowerCase().contains(searchQuery);
    }).toList();
  }

  // กรองข้อมูลตามวันหมดอายุ
  List<ShoppingItem> _filterItemsByExpiry(List<ShoppingItem> items) {
    if (selectedExpiryFilter == 'ทั้งหมด') return items;

    final now = DateTime.now();
    int daysToCheck = 0;

    switch (selectedExpiryFilter) {
      case '1 วัน':
        daysToCheck = 1;
        break;
      case '2 วัน':
        daysToCheck = 2;
        break;
      case '3 วัน':
        daysToCheck = 3;
        break;
      case '7 วัน':
        daysToCheck = 7;
        break;
      case '14 วัน':
        daysToCheck = 14;
        break;
      case 'กำหนดเอง':
        daysToCheck = customDays ?? 0;
        break;
    }

    return items.where((item) {
      if (item.expiryDate == null) return false;

      final daysUntilExpiry = item.expiryDate!.difference(now).inDays;

      if (selectedExpiryFilter == '1 วัน') {
        return daysUntilExpiry == 0 || daysUntilExpiry == 1;
      } else if (selectedExpiryFilter == '2 วัน') {
        return daysUntilExpiry == 0 ||
            daysUntilExpiry == 1 ||
            daysUntilExpiry == 2;
      } else if (selectedExpiryFilter == '3 วัน') {
        return daysUntilExpiry == 0 ||
            daysUntilExpiry == 1 ||
            daysUntilExpiry == 2 ||
            daysUntilExpiry == 3;
      } else if (selectedExpiryFilter == '7 วัน') {
        return daysUntilExpiry >= 4 && daysUntilExpiry <= 7;
      } else if (selectedExpiryFilter == '14 วัน') {
        return daysUntilExpiry >= 8 && daysUntilExpiry <= 14;
      } else if (selectedExpiryFilter == 'กำหนดเอง') {
        return daysUntilExpiry == daysToCheck;
      } else {
        return daysUntilExpiry <= daysToCheck && daysUntilExpiry >= 0;
      }
    }).toList();
  }

  // แสดง Bottom Sheet สำหรับตัวกรองวันหมดอายุ
  void _showExpiryFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.yellow[300]!.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.schedule_rounded,
                        color: Colors.yellow[700],
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'กรองตามวันหมดอายุ',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            'เลือกช่วงเวลาที่ต้องการดู',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

              // Drag Handle
              Container(
                margin: EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Options List
              Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: expiryFilterOptions.map((option) {
                    final isSelected = selectedExpiryFilter == option;
                    final isCustom = option == 'กำหนดเอง';

                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (isCustom) {
                              Navigator.pop(context);
                              _showCustomDaysDialog();
                            } else {
                              setState(() {
                                selectedExpiryFilter = option;
                              });
                              Navigator.pop(context);
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.yellow[300]!.withOpacity(0.3)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.yellow[600]!
                                    : Colors.grey[200]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.yellow[300]
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.yellow[600]!
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Icon(
                                    option == 'ทั้งหมด'
                                        ? Icons.all_inclusive_rounded
                                        : isCustom
                                        ? Icons.edit_calendar_rounded
                                        : Icons.schedule_rounded,
                                    size: 20,
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.grey[600],
                                  ),
                                ),
                                SizedBox(width: 16),

                                // Text
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isCustom &&
                                                customDays != null &&
                                                isSelected
                                            ? 'กำหนดเอง ($customDays วัน)'
                                            : option,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.grey[800],
                                          fontSize: 16,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      if (option != 'ทั้งหมด' && !isCustom)
                                        Text(
                                          'วัตถุดิบที่หมดอายุใน${option}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      if (isCustom)
                                        Text(
                                          'กำหนดจำนวนวันเอง',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Selection Indicator
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.yellow[600]
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.yellow[600]!
                                          : Colors.grey[400]!,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.black,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Reset Button
              if (selectedExpiryFilter != 'ทั้งหมด')
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          selectedExpiryFilter = 'ทั้งหมด';
                          customDays = null;
                        });
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.clear_rounded, color: Colors.grey[600]),
                          SizedBox(width: 8),
                          Text(
                            'ล้างตัวกรอง',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // แสดง Dialog สำหรับกำหนดวันเอง
  void _showCustomDaysDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.yellow[300]!.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.edit_calendar_rounded,
                        color: Colors.yellow[700],
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'กำหนดจำนวนวัน',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            'ระบุจำนวนวันที่ต้องการ',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),

                // Input Field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: _customDaysController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 24,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      suffixIcon: Padding(
                        padding: EdgeInsets.only(right: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'วัน',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    autofocus: true,
                  ),
                ),
                SizedBox(height: 24),

                // Quick Select Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [1, 3, 7, 14, 30].map((days) {
                    return InkWell(
                      onTap: () {
                        _customDaysController.text = days.toString();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.yellow[300]!.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.yellow[400]!),
                        ),
                        child: Text(
                          '$days วัน',
                          style: TextStyle(
                            color: Colors.yellow[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'ยกเลิก',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final days = int.tryParse(_customDaysController.text);
                          if (days != null && days > 0) {
                            setState(() {
                              customDays = days;
                              selectedExpiryFilter = 'กำหนดเอง';
                            });
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text('กรองวัตถุดิบที่หมดอายุใน $days วัน'),
                                  ],
                                ),
                                backgroundColor: Colors.green[600],
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: EdgeInsets.all(16),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.error, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('กรุณาใส่จำนวนวันที่ถูกต้อง'),
                                  ],
                                ),
                                backgroundColor: Colors.red[600],
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: EdgeInsets.all(16),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow[300],
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded),
                            SizedBox(width: 8),
                            Text(
                              'ยืนยัน',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // เพิ่ม method สำหรับไปหน้า barcode scanner
  void _navigateToBarcodeScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WorkingBarcodeScanner()),
    );

    // ถ้าได้ผลลัพธ์จากการสแกน
    if (result != null && result is Map<String, dynamic>) {
      String barcode = result['barcode'] ?? '';
      Map<String, dynamic>? productData = result['productData'];

      // ไปหน้าเพิ่มสินค้าพร้อมข้อมูลที่สแกนได้
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddRawMaterialPage(
            scannedBarcode: barcode,
            scannedProductData: productData,
          ),
        ),
      ).then((_) {
        _loadAvailableCategories();
        setState(() {});
      });
    }
  }

  // แก้ไข method _navigateToAddRawMaterial
  void _navigateToAddRawMaterial() {
    if (currentUser == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddRawMaterialPage()),
    ).then((_) {
      _loadAvailableCategories();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'วัตถุดิบ',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getUserRawMaterials(),
                builder: (context, snapshot) {
                  int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return Text(
                    '$count ชิ้น',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'ค้นหาวัตถุดิบ',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[400]),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                // เพิ่ม debounce เพื่อลดการ rebuild
                Future.delayed(Duration(milliseconds: 300), () {
                  if (_searchController.text == value) {
                    setState(() {
                      searchQuery = value.toLowerCase();
                    });
                  }
                });
              },
            ),
          ),

          // Category Filter - ใช้หมวดหมู่ที่ดึงจาก Firebase
          Container(
            height: 60,
            padding: EdgeInsets.symmetric(horizontal: 16),
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: availableCategories.length,
              itemBuilder: (context, index) {
                final category = availableCategories[index];
                final isSelected = selectedCategory == category;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedCategory = category;
                    });
                  },
                  child: Container(
                    margin: EdgeInsets.only(right: 12, top: 8, bottom: 8),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.yellow[600] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[600],
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Items List Header with Filter Menu
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Status Icon
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selectedExpiryFilter != 'ทั้งหมด'
                              ? Colors.yellow[300]!.withOpacity(0.2)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedExpiryFilter != 'ทั้งหมด'
                                ? Colors.yellow[600]!
                                : Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          selectedExpiryFilter != 'ทั้งหมด'
                              ? Icons.schedule_rounded
                              : Icons.inventory_2_rounded,
                          size: 20,
                          color: selectedExpiryFilter != 'ทั้งหมด'
                              ? Colors.yellow[700]
                              : Colors.grey[600],
                        ),
                      ),
                      SizedBox(width: 12),

                      // Filter Text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              searchQuery.isNotEmpty
                                  ? 'ผลการค้นหา'
                                  : selectedExpiryFilter != 'ทั้งหมด'
                                  ? 'วัตถุดิบใกล้หมดอายุ'
                                  : 'วัตถุดิบทั้งหมด',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              searchQuery.isNotEmpty
                                  ? '"$searchQuery"'
                                  : selectedExpiryFilter != 'ทั้งหมด'
                                  ? selectedExpiryFilter == 'กำหนดเอง'
                                        ? 'หมดอายุใน $customDays วัน'
                                        : 'หมดอายุใน${selectedExpiryFilter}'
                                  : 'เรียงตามวันหมดอายุ',
                              style: TextStyle(
                                color: selectedExpiryFilter != 'ทั้งหมด'
                                    ? Colors.yellow[700]
                                    : Colors.grey[600],
                                fontSize: 13,
                                fontWeight: selectedExpiryFilter != 'ทั้งหมด'
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Filter Button
                GestureDetector(
                  onTap: () => _showExpiryFilterBottomSheet(),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedExpiryFilter != 'ทั้งหมด'
                          ? Colors.yellow[300]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: selectedExpiryFilter != 'ทั้งหมด'
                            ? Colors.yellow[600]!
                            : Colors.grey[300]!,
                        width: 1.5,
                      ),
                      boxShadow: selectedExpiryFilter != 'ทั้งหมด'
                          ? [
                              BoxShadow(
                                color: Colors.yellow[300]!.withOpacity(0.3),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: selectedExpiryFilter != 'ทั้งหมด'
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                        SizedBox(width: 6),
                        Text(
                          'กรอง',
                          style: TextStyle(
                            color: selectedExpiryFilter != 'ทั้งหมด'
                                ? Colors.black
                                : Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (selectedExpiryFilter != 'ทั้งหมด') ...[
                          SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
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

          // Shopping Items List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getFilteredItems(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  print('Error in stream: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 60, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          'เกิดข้อผิดพลาด: ${snapshot.error}',
                          style: TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          selectedCategory == 'ทั้งหมด'
                              ? 'ไม่มีรายการวัตถุดิบ'
                              : 'ไม่มีวัตถุดิบในหมวดหมู่ "$selectedCategory"',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final items = snapshot.data!.docs.map((doc) {
                  return ShoppingItem.fromMap(
                    doc.data() as Map<String, dynamic>,
                    doc.id,
                  );
                }).toList();

                // กรองตามคำค้นหา
                var filteredItems = _filterItemsBySearch(items);

                // กรองตามวันหมดอายุ
                filteredItems = _filterItemsByExpiry(filteredItems);

                // ถ้าไม่มีผลการค้นหาหรือกรอง
                if (filteredItems.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selectedExpiryFilter != 'ทั้งหมด'
                              ? Icons.schedule
                              : Icons.search_off,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          selectedExpiryFilter != 'ทั้งหมด'
                              ? 'ไม่มีวัตถุดิบที่หมดอายุใน${selectedExpiryFilter == 'กำหนดเอง' ? '$customDays วัน' : selectedExpiryFilter}'
                              : searchQuery.isNotEmpty
                              ? 'ไม่พบรายการที่ค้นหา'
                              : 'ไม่มีรายการ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        if (searchQuery.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'คำค้นหา: "$searchQuery"',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                // เรียงตามวันหมดอายุ (ที่ใกล้หมดอายุที่สุดมาก่อน)
                filteredItems.sort((a, b) {
                  if (a.expiryDate == null && b.expiryDate == null) return 0;
                  if (a.expiryDate == null) return 1;
                  if (b.expiryDate == null) return -1;
                  return a.expiryDate!.compareTo(b.expiryDate!);
                });

                return ListView.builder(
                  itemCount:
                      filteredItems.length + 1, // บวก 1 เพื่อใส่ SizedBox
                  itemBuilder: (context, index) {
                    if (index == filteredItems.length) {
                      return SizedBox(height: 120); // เว้นช่องให้ FAB
                    }

                    final item = filteredItems[index];
                    return ShoppingItemCard(
                      item: item,
                      onQuantityChanged: (newQuantity) {
                        _updateItemQuantity(item.id, newQuantity);
                      },
                      onDelete: () {
                        _deleteItem(item.id);
                      },
                      searchQuery: searchQuery,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // Floating Action Button - แก้ไขให้มีแค่ Write และ Scan
      floatingActionButton: Container(
        decoration: BoxDecoration(
          color: Colors.yellow[700], // สีพื้นหลังของก้อนปุ่ม
          borderRadius: BorderRadius.circular(30), // ขอบมนทั้งกล่อง
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), // ขอบด้านใน
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ปุ่ม Write
            TextButton.icon(
              onPressed: _navigateToAddRawMaterial,
              icon: Icon(Icons.edit, color: Colors.black),
              label: Text(
                'Write',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            SizedBox(width: 8), // ระยะห่างระหว่างปุ่ม
            // ปุ่ม Scan
            TextButton.icon(
              onPressed: _navigateToBarcodeScanner,
              icon: Icon(
                FontAwesomeIcons.barcode,
                size: 20,
                color: const Color.fromARGB(255, 0, 0, 0),
              ),
              label: Text(
                'Scan',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getFilteredItems() {
    if (currentUser == null) return Stream.empty();

    CollectionReference userRawMaterials = _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('raw_materials');

    if (selectedCategory == 'ทั้งหมด') {
      return userRawMaterials
          .orderBy('created_at', descending: true)
          .snapshots();
    } else {
      return userRawMaterials
          .where('category', isEqualTo: selectedCategory)
          .snapshots();
    }
  }

  Stream<QuerySnapshot> _getUserRawMaterials() {
    if (currentUser == null) return Stream.empty();

    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('raw_materials')
        .snapshots();
  }

  void _updateItemQuantity(String itemId, int newQuantity) async {
    if (currentUser == null) return;

    try {
      if (newQuantity <= 0) {
        await _deleteItem(itemId);
        return;
      }

      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('raw_materials')
          .doc(itemId)
          .update({
            'quantity': newQuantity,
            'updated_at': FieldValue.serverTimestamp(),
          });

      print('Updated quantity for $itemId to $newQuantity');
    } catch (e) {
      print('Error updating quantity: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการอัปเดตจำนวน'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteItem(String itemId) async {
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('raw_materials')
          .doc(itemId)
          .delete();

      _loadAvailableCategories();
      print('Deleted item: $itemId');
    } catch (e) {
      print('Error deleting item: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการลบรายการ'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
