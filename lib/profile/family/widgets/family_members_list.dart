// screens/family/widgets/family_members_list.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'family_member_tile.dart';

class FamilyMembersList extends StatelessWidget {
  final List<Map<String, dynamic>> familyMembers;
  final User? currentUser;
  final VoidCallback onAddMember;
  final Function(Map<String, dynamic>) onEditMember;
  final Function(String, String) onRemoveMember;
  final Function(Map<String, dynamic>) onViewHealth;

  const FamilyMembersList({
    super.key,
    required this.familyMembers,
    required this.currentUser,
    required this.onAddMember,
    required this.onEditMember,
    required this.onRemoveMember,
    required this.onViewHealth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'สมาชิกในครอบครัว',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: onAddMember,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่ม'),
                ),
              ],
            ),
          ),

          // Current User (Owner)
          FamilyMemberTile(
            name: currentUser?.displayName ?? 'ผู้ใช้',
            email: currentUser?.email ?? '',
            role: 'เจ้าของบัญชี',
            relationship: 'ตัวเอง',
            isOwner: true,
            isOnline: true,
            avatarUrl: currentUser?.photoURL,
            healthStatus: 'ดี',
            onEdit: null,
            onRemove: null,
            onViewHealth: () => _showOwnerHealthDialog(context),
          ),

          // Family Members
          if (familyMembers.isEmpty)
            _buildEmptyState()
          else
            ...List.generate(familyMembers.length, (index) {
              final member = familyMembers[index];
              return Column(
                children: [
                  FamilyMemberTile(
                    name: member['name'] ?? 'ไม่ระบุ',
                    email: member['email'] ?? '',
                    role: member['role'] ?? 'สมาชิก',
                    relationship: member['relationship'] ?? 'สมาชิก',
                    isOwner: false,
                    isOnline: member['isOnline'] ?? false,
                    avatarUrl: member['avatarUrl'],
                    healthStatus: member['healthStatus'] ?? 'ไม่ทราบ',
                    joinedDate: member['addedAt'],
                    onEdit: () => onEditMember(member),
                    onRemove: () =>
                        onRemoveMember(member['id'], member['name']),
                    onViewHealth: () => onViewHealth(member),
                  ),
                  if (index < familyMembers.length - 1) _buildDivider(),
                ],
              );
            }),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.family_restroom, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'ยังไม่มีสมาชิกในครอบครัว',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'เชิญสมาชิกเข้าร่วมครอบครัวของคุณ',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAddMember,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มสมาชิกแรก'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
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

  void _showOwnerHealthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ข้อมูลสุขภาพของคุณ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHealthInfoRow('สถานะสุขภาพ', 'ดี'),
            _buildHealthInfoRow('BMI', '22.5'),
            _buildHealthInfoRow('ความดันโลหิต', 'ปกติ'),
            _buildHealthInfoRow('การออกกำลังกาย', 'สม่ำเสมอ'),
            const SizedBox(height: 16),
            Text(
              'ข้อมูลนี้มาจากโปรไฟล์สุขภาพของคุณ',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to health profile
            },
            child: const Text('แก้ไขข้อมูล'),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
