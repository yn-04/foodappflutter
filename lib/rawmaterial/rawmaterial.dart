// Raw Material Tab
import 'package:flutter/material.dart';
import 'package:my_app/welcomeapp/barcode.dart';

class RawMaterialTab extends StatelessWidget {
  const RawMaterialTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw Material'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _navigateToBarcodeScannerPage(context),
            tooltip: 'สแกนบาร์โค้ด',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2, size: 80, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Raw Material Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'จัดการวัตถุดิบและสต็อก',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),

            // Menu buttons
            _buildMenuButton(
              context,
              icon: Icons.qr_code_scanner,
              title: 'สแกนบาร์โค้ด',
              subtitle: 'สแกนบาร์โค้ดเพื่อเพิ่มวัตถุดิบ',
              onTap: () => _navigateToBarcodeScannerPage(context),
            ),
            const SizedBox(height: 16),
            _buildMenuButton(
              context,
              icon: Icons.add_circle_outline,
              title: 'เพิ่มวัตถุดิบ',
              subtitle: 'เพิ่มวัตถุดิบใหม่ด้วยตนเอง',
              onTap: () => _showAddMaterialDialog(context),
            ),
            const SizedBox(height: 16),
            _buildMenuButton(
              context,
              icon: Icons.list_alt,
              title: 'รายการวัตถุดิบ',
              subtitle: 'ดูรายการวัตถุดิบทั้งหมด',
              onTap: () => _showMaterialList(context),
            ),
            const SizedBox(height: 16),
            _buildMenuButton(
              context,
              icon: Icons.analytics,
              title: 'รายงานสต็อก',
              subtitle: 'ดูรายงานและสถิติสต็อก',
              onTap: () => _showStockReport(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, size: 40, color: Colors.blue),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }

  Future<void> _navigateToBarcodeScannerPage(BuildContext context) async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerPage()),
      );

      if (result != null && context.mounted) {
        // แสดงผลลัพธ์ที่ได้จากการสแกน
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('สแกนได้: $result'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'เพิ่มวัตถุดิบ',
              onPressed: () => _addMaterialFromBarcode(context, result),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addMaterialFromBarcode(BuildContext context, String barcode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มวัตถุดิบ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('บาร์โค้ด: $barcode'),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'ชื่อวัตถุดิบ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'จำนวน',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('เพิ่มวัตถุดิบสำเร็จ')),
              );
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
  }

  void _showAddMaterialDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มวัตถุดิบ'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'ชื่อวัตถุดิบ',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'จำนวน',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'หน่วย',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('เพิ่มวัตถุดิบสำเร็จ')),
              );
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
  }

  void _showMaterialList(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รายการวัตถุดิบ'),
        content: const SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.inventory),
                title: Text('แป้งสาลี'),
                subtitle: Text('จำนวน: 50 กิโลกรัม'),
              ),
              ListTile(
                leading: Icon(Icons.inventory),
                title: Text('น้ำตาล'),
                subtitle: Text('จำนวน: 25 กิโลกรัม'),
              ),
              ListTile(
                leading: Icon(Icons.inventory),
                title: Text('เกลือ'),
                subtitle: Text('จำนวน: 10 กิโลกรัม'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  void _showStockReport(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รายงานสต็อก'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 สรุปสต็อกวัตถุดิบ'),
            SizedBox(height: 16),
            Text('• วัตถุดิบทั้งหมด: 12 รายการ'),
            Text('• วัตถุดิบที่เหลือน้อย: 3 รายการ'),
            Text('• วัตถุดิบที่หมด: 1 รายการ'),
            SizedBox(height: 16),
            Text('⚠️ แจ้งเตือน:'),
            Text(
              '• แป้งสาลีเหลือน้อย (< 10 กก.)',
              style: TextStyle(color: Colors.orange),
            ),
            Text('• น้ำมันหมด', style: TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}
