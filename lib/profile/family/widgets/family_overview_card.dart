// screens/family/widgets/family_overview_card.dart
import 'package:flutter/material.dart';

class FamilyOverviewCard extends StatelessWidget {
  final int totalMembers;
  final Map<String, dynamic>? familyStats;
  final List<Map<String, dynamic>> familyMembers;

  const FamilyOverviewCard({
    super.key,
    required this.totalMembers,
    required this.familyStats,
    required this.familyMembers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ครอบครัวของฉัน',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalMembers สมาชิก',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'เจ้าของ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'สมาชิกใหม่',
                '${_getNewMembersThisMonth()}',
                Icons.person_add,
              ),
              _buildStatItem(
                'สุขภาพดี',
                '${_getHealthyMembers()}',
                Icons.health_and_safety,
              ),
              _buildStatItem(
                'ออนไลน์',
                '${_getOnlineMembers()}',
                Icons.circle,
                Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, [
    Color? iconColor,
  ]) {
    return Column(
      children: [
        Icon(icon, color: iconColor ?? Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  int _getNewMembersThisMonth() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return familyMembers.where((member) {
      final addedAt = member['addedAt']?.toDate();
      return addedAt != null && addedAt.isAfter(startOfMonth);
    }).length;
  }

  int _getHealthyMembers() {
    return familyMembers
            .where(
              (member) =>
                  member['healthStatus'] == 'ดี' ||
                  member['healthStatus'] == 'ปกติ',
            )
            .length +
        1; // +1 for owner
  }

  int _getOnlineMembers() {
    return familyMembers.where((member) => member['isOnline'] == true).length +
        1; // +1 for owner (always online)
  }
}
