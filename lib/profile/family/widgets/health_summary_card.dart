// screens/family/widgets/health_summary_card.dart
import 'package:flutter/material.dart';

class HealthSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? familyStats;

  const HealthSummaryCard({super.key, required this.familyStats});

  @override
  Widget build(BuildContext context) {
    if (familyStats == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics,
                  color: Colors.green[600],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'สรุปสุขภาพครอบครัว',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => _showDetailedStats(context),
                child: const Text('ดูทั้งหมด'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...familyStats!.entries.map(
            (entry) => _buildHealthSummaryRow(entry.key, entry.value),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthSummaryRow(String key, dynamic value) {
    final statInfo = _getStatInfo(key, value);
    if (statInfo == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statInfo['color'].withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statInfo['icon'], size: 20, color: statInfo['color']),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statInfo['label'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (statInfo['percentage'] != null)
                  Text(
                    statInfo['percentage'],
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          Text(
            statInfo['value'],
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: statInfo['color'],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _getStatInfo(String key, dynamic value) {
    final totalMembers = familyStats!['totalMembers'] ?? 1;

    switch (key) {
      case 'weightControl':
        return {
          'label': 'สมาชิกที่ควบคุมน้ำหนัก',
          'value': '$value คน',
          'percentage': '${((value / totalMembers) * 100).round()}%',
          'icon': Icons.trending_down,
          'color': Colors.blue,
        };
      case 'exercise':
        return {
          'label': 'สมาชิกที่ออกกำลังกายสม่ำเสมอ',
          'value': '$value คน',
          'percentage': '${((value / totalMembers) * 100).round()}%',
          'icon': Icons.fitness_center,
          'color': Colors.green,
        };
      case 'allergies':
        return {
          'label': 'สมาชิกที่มีภูมิแพ้',
          'value': '$value คน',
          'percentage': null,
          'icon': Icons.warning_amber,
          'color': Colors.orange,
        };
      case 'averageAge':
        return {
          'label': 'อายุเฉลี่ยของครอบครัว',
          'value': '$value ปี',
          'percentage': null,
          'icon': Icons.cake,
          'color': Colors.purple,
        };
      default:
        return null;
    }
  }

  void _showDetailedStats(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('สถิติสุขภาพครอบครัวแบบละเอียด'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailedStatItem(
                'จำนวนสมาชิกทั้งหมด',
                '${familyStats!['totalMembers'] ?? 0}',
                Icons.people,
                Colors.blue,
              ),
              _buildDetailedStatItem(
                'สมาชิกที่มีสุขภาพดี',
                '${_calculateHealthyMembers()}',
                Icons.health_and_safety,
                Colors.green,
              ),
              _buildDetailedStatItem(
                'อัตราการออกกำลังกาย',
                '${_calculateExerciseRate()}%',
                Icons.fitness_center,
                Colors.orange,
              ),
              _buildDetailedStatItem(
                'BMI เฉลี่ย',
                '${_calculateAverageBMI()}',
                Icons.monitor_weight,
                Colors.purple,
              ),
              _buildDetailedStatItem(
                'สมาชิกใหม่เดือนนี้',
                '${_calculateNewMembers()}',
                Icons.person_add,
                Colors.teal,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _exportHealthReport(context);
            },
            child: const Text('ส่งออกรายงาน'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  int _calculateHealthyMembers() {
    // Mock calculation - in real app, calculate from actual data
    final totalMembers = familyStats!['totalMembers'] ?? 0;
    return (totalMembers * 0.8).round(); // 80% are healthy
  }

  int _calculateExerciseRate() {
    final exerciseMembers = familyStats!['exercise'] ?? 0;
    final totalMembers = familyStats!['totalMembers'] ?? 1;
    return ((exerciseMembers / totalMembers) * 100).round();
  }

  String _calculateAverageBMI() {
    // Mock calculation - in real app, calculate from actual BMI data
    return '22.5';
  }

  int _calculateNewMembers() {
    // Mock calculation - in real app, calculate from join dates
    return 1;
  }

  void _exportHealthReport(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('กำลังสร้างรายงาน...'),
          ],
        ),
      ),
    );

    // Simulate export process
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งออกรายงานสุขภาพครอบครัวสำเร็จ'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }
}
