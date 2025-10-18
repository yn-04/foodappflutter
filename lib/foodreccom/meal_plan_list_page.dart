import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/meal_plan_provider.dart';
import 'providers/enhanced_recommendation_provider.dart';
import 'meal_plan_page.dart';

class MealPlanListPage extends StatefulWidget {
  const MealPlanListPage({super.key});

  @override
  State<MealPlanListPage> createState() => _MealPlanListPageState();
}

class _MealPlanListPageState extends State<MealPlanListPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _weekFilter = 'all'; // all | this | last

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('โปรดเข้าสู่ระบบเพื่อดูแผนอาหาร')),
      );
    }
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plans')
        .orderBy('created_at', descending: true);
    return Scaffold(
      appBar: AppBar(
        title: const Text('📚 แผนมื้ออาหารทั้งหมด'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                filled: true,
                hintText: 'ค้นหา (ID/วันที่/ชื่อเมนูแรก) ...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีแผนที่บันทึก'));
          }
          // Filter by search
          var filtered = snap.data!.docs.where((d) {
            final data = d.data();
            final id = d.id.toLowerCase();
            final gen = (data['generated_at'] as String?)?.toLowerCase() ?? '';
            final names = <String>[];
            try {
              final plan = (data['plan'] as Map<String, dynamic>?);
              final days = (plan?['days'] as List?) ?? [];
              for (final day in days) {
                final meals = (day as Map<String, dynamic>)['meals'] as List? ?? [];
                for (final m in meals) {
                  final recipe = (m as Map<String, dynamic>)['recipe'] as Map<String, dynamic>?;
                  final name = (recipe?['name'] as String?)?.toLowerCase() ?? '';
                  if (name.isNotEmpty) names.add(name);
                }
              }
            } catch (_) {}
            if (_query.isEmpty) return true;
            return id.contains(_query) || gen.contains(_query) || names.any((n) => n.contains(_query));
          }).toList();

          // Filter by week
          if (_weekFilter != 'all') {
            final now = DateTime.now();
            final thisStart = now.subtract(Duration(days: now.weekday - 1));
            final thisEnd = thisStart.add(const Duration(days: 6));
            final lastStart = thisStart.subtract(const Duration(days: 7));
            final lastEnd = thisEnd.subtract(const Duration(days: 7));

            bool inRange(DateTime d, DateTime s, DateTime e) => !d.isBefore(s) && !d.isAfter(e);

            filtered = filtered.where((doc) {
              final ts = (doc.data()['created_at'] as Timestamp?);
              final dt = ts?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
              if (_weekFilter == 'this') return inRange(dt, thisStart, thisEnd);
              if (_weekFilter == 'last') return inRange(dt, lastStart, lastEnd);
              return true;
            }).toList();
          }

          // Group by ISO week (YYYY-Www) based on created_at
          final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final d in filtered) {
            final created = (d.data()['created_at'] as Timestamp?);
            final dt = (created?.toDate() ?? DateTime.now());
            final key = _isoWeekKey(dt);
            (grouped[key] ??= []).add(d);
          }

          final sections = grouped.entries.toList()
            ..sort((a, b) => _parseDateRange(b.key).compareTo(_parseDateRange(a.key)));

          return Column(
            children: [
              // Week filter chips
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ทั้งหมด'),
                      selected: _weekFilter == 'all',
                      onSelected: (_) => setState(() => _weekFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('สัปดาห์นี้'),
                      selected: _weekFilter == 'this',
                      onSelected: (_) => setState(() => _weekFilter = 'this'),
                    ),
                    ChoiceChip(
                      label: const Text('สัปดาห์ก่อน'),
                      selected: _weekFilter == 'last',
                      onSelected: (_) => setState(() => _weekFilter = 'last'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: sections.length,
                  itemBuilder: (ctx, idx) {
                    final sec = sections[idx];
                    final list = sec.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          color: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(sec.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        ...list.map((d) => _planTile(context, user.uid, d)).toList(),
                        const Divider(height: 1),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planTile(BuildContext context, String uid, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final gen = (data['generated_at'] as String?) ?? '';
    final created = (data['created_at'] as Timestamp?);
    final createdStr = created != null ? created.toDate().toString() : '';
    // compute meals count summary
    int mealsCount = 0;
    try {
      final plan = (data['plan'] as Map<String, dynamic>?);
      final days = (plan?['days'] as List?) ?? [];
      for (final day in days) {
        final meals = (day as Map<String, dynamic>)['meals'] as List? ?? [];
        mealsCount += meals.length;
      }
    } catch (_) {}
    // Estimate total cost using current inventory
    double? estimateCost;
    try {
      final planJson = (data['plan'] as Map<String, dynamic>);
      final inv = context.read<EnhancedRecommendationProvider>().ingredients;
      estimateCost = context.read<MealPlanProvider>().estimateTotalCostForPlanJson(planJson, inv);
    } catch (_) {}

    return ListTile(
      leading: const Icon(Icons.calendar_month),
      title: Text('แผน #${d.id.substring(0, 6)} • $gen'),
      subtitle: Text('บันทึกเมื่อ: $createdStr • รวม ${mealsCount} มื้อ${estimateCost != null ? ' • ≈ ฿${estimateCost.toStringAsFixed(0)}' : ''}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'ทำสำเนา',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final copied = {...data};
              copied['created_at'] = FieldValue.serverTimestamp();
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('meal_plans')
                  .add(copied);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ทำสำเนาแผนแล้ว')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'ลบ',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('ยืนยันการลบ'),
                      content: Text('ลบแผน #${d.id.substring(0, 6)} นี้หรือไม่?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ')),
                      ],
                    ),
                  ) ??
                  false;
              if (!ok) return;
              await d.reference.delete();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ลบแผนแล้ว')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'เปิด',
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              await context.read<MealPlanProvider>().loadPlanById(d.id);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MealPlanPage()),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  DateTime _parseDateRange(String key) {
    // key: 2025-W40 -> return first day of that ISO week
    try {
      final parts = key.split('-W');
      final year = int.parse(parts[0]);
      final week = int.parse(parts[1]);
      return _firstDateOfIsoWeek(week, year);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _isoWeekKey(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays) / 7).floor();
    final year = thursday.year;
    return '$year-W${week.toString().padLeft(2, '0')}';
  }

  DateTime _firstDateOfIsoWeek(int week, int year) {
    final fourthJan = DateTime(year, 1, 4);
    final firstThursday = fourthJan.add(Duration(days: 3 - ((fourthJan.weekday + 6) % 7)));
    final weekStart = firstThursday.add(Duration(days: (week - 1) * 7 - 3));
    return weekStart;
  }
}
