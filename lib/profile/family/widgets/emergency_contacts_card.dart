// screens/family/widgets/emergency_contacts_card.dart
import 'package:flutter/material.dart';

class EmergencyContactsCard extends StatelessWidget {
  final VoidCallback onAddContact;
  final Function(String) onCallContact;

  const EmergencyContactsCard({
    super.key,
    required this.onAddContact,
    required this.onCallContact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.emergency,
                        color: Colors.red[600],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ผู้ติดต่อฉุกเฉิน',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: onAddContact,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่ม'),
                ),
              ],
            ),
          ),

          // Default emergency contacts
          EmergencyContactTile(
            name: 'โรงพยาบาลใกล้บ้าน',
            phone: '02-123-4567',
            type: 'โรงพยาบาล',
            icon: Icons.local_hospital,
            color: Colors.red,
            onCall: () => onCallContact('02-123-4567'),
            onEdit: () => _showEditContactDialog(context, 'โรงพยาบาลใกล้บ้าน'),
            onDelete: () =>
                _showDeleteContactDialog(context, 'โรงพยาบาลใกล้บ้าน'),
          ),
          _buildDivider(),
          EmergencyContactTile(
            name: 'แพทย์ประจำครอบครัว',
            phone: '089-123-4567',
            type: 'แพทย์',
            icon: Icons.medical_services,
            color: Colors.blue,
            onCall: () => onCallContact('089-123-4567'),
            onEdit: () => _showEditContactDialog(context, 'แพทย์ประจำครอบครัว'),
            onDelete: () =>
                _showDeleteContactDialog(context, 'แพทย์ประจำครอบครัว'),
          ),
          _buildDivider(),
          EmergencyContactTile(
            name: 'ศูนย์การแพทย์ฉุกเฉิน',
            phone: '1669',
            type: 'ฉุกเฉิน',
            icon: Icons.emergency_outlined,
            color: Colors.orange,
            isEmergencyNumber: true,
            onCall: () => onCallContact('1669'),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: Colors.grey[200],
    );
  }

  void _showEditContactDialog(BuildContext context, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('แก้ไข $contactName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'ชื่อ',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: contactName),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'เบอร์โทรศัพท์',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
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
                const SnackBar(
                  content: Text('แก้ไขผู้ติดต่อฉุกเฉินสำเร็จ'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _showDeleteContactDialog(BuildContext context, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบผู้ติดต่อฉุกเฉิน'),
        content: Text('คุณต้องการลบ "$contactName" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ลบผู้ติดต่อฉุกเฉินสำเร็จ'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }
}

class EmergencyContactTile extends StatelessWidget {
  final String name;
  final String phone;
  final String type;
  final IconData icon;
  final Color color;
  final VoidCallback onCall;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isEmergencyNumber;

  const EmergencyContactTile({
    super.key,
    required this.name,
    required this.phone,
    required this.type,
    required this.icon,
    required this.color,
    required this.onCall,
    this.onEdit,
    this.onDelete,
    this.isEmergencyNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isEmergencyNumber)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'ฉุกเฉิน',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Call button
              Container(
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: onCall,
                  icon: Icon(Icons.phone, color: Colors.green[600], size: 20),
                  tooltip: 'โทร',
                ),
              ),

              // Edit/Delete menu for non-emergency numbers
              if (!isEmergencyNumber && (onEdit != null || onDelete != null))
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit?.call();
                        break;
                      case 'delete':
                        onDelete?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('แก้ไข'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('ลบ', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.more_vert,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
