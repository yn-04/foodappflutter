import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:my_app/dashboard/widgets/expiring_today_section.dart';
import 'package:my_app/dashboard/widgets/inventory_summary_section.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with AutomaticKeepAliveClientMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late Future<_DashboardData> _dashboardFuture;

  // โหลด username จาก Firestore (ใช้บนหัว)
  late Future<String> _usernameFuture;

  // ===== ข้อความภาษาไทย =====
  static const _tHello = 'สวัสดี';
  static const _tWelcomeBack = 'ยินดีต้อนรับกลับ';
  static const _tWeeklyCooking = 'สรุปการทำอาหารรายสัปดาห์';
  static const _tTotalServingsPrefix = 'รวม ';
  static const _tTotalServingsSuffix = ' ที่';
  static const _tMenuIdeas = 'เมนูแนะนำ';
  static const _tNeedLogin = 'กรุณาเข้าสู่ระบบเพื่อดูแดชบอร์ดของคุณ';
  static const _tLoadError = 'โหลดข้อมูลไม่สำเร็จ';
  static const _tRetry = 'ลองใหม่';
  static const _tNoWeeklyData = 'ยังไม่มีข้อมูลการทำอาหารในสัปดาห์นี้';

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboardData();
    _usernameFuture = _loadUsername();
  }

  @override
  bool get wantKeepAlive => true;

  Future<String> _loadUsername() async {
    final user = _auth.currentUser;
    if (user == null) return 'ผู้ใช้';
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      String? name = (data['displayName'] as String?)?.trim();
      name ??= (data['username'] as String?)?.trim();
      name ??= (user.displayName ?? '').trim();
      if (name.isEmpty) {
        final email = user.email ?? '';
        if (email.contains('@')) name = email.split('@').first;
      }
      return (name.isEmpty) ? 'ผู้ใช้' : name;
    } catch (_) {
      // ถ้าอ่านไม่ได้ ให้ fallback ไปที่ displayName/email
      final email = user.email ?? '';
      if ((user.displayName ?? '').trim().isNotEmpty) return user.displayName!;
      if (email.contains('@')) return email.split('@').first;
      return 'ผู้ใช้';
    }
  }

  Future<_DashboardData> _loadDashboardData() async {
    final user = _auth.currentUser;
    if (user == null) return _DashboardData.empty();

    try {
      final today = DateTime.now();
      final endDate = _dateOnly(today);
      final startDate = endDate.subtract(const Duration(days: 6));

      final userRef = _firestore.collection('users').doc(user.uid);
      final rawCol = userRef.collection('raw_materials');
      final cookCol = userRef.collection('cooking_history');

      // สร้าง bin รายวัน 7 วันล่าสุด
      final weeklyUsage = List.generate(
        7,
        (i) => _DailyUsage(date: startDate.add(Duration(days: i))),
      );

      // โหลดขนาน
      final rawFuture = rawCol.get();
      final cookFuture = cookCol
          .where(
            'cooked_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            'cooked_at',
            isLessThanOrEqualTo: Timestamp.fromDate(
              endDate
                  .add(const Duration(days: 1))
                  .subtract(const Duration(milliseconds: 1)),
            ),
          )
          .get();

      final rawSnapshot = await rawFuture;
      final cookSnapshot = await cookFuture;

      final inventoryItems = rawSnapshot.docs
          .map((d) => ShoppingItem.fromMap(d.data(), d.id))
          .toList(growable: false);

      // นับจำนวนต่อหมวดหมู่ (ใช้ Categories.normalize)
      final counts = <String, int>{};
      for (final it in inventoryItems) {
        final key0 = Categories.normalize(it.category);
        final key = key0.isEmpty ? 'ไม่ระบุ' : key0;
        counts[key] = (counts[key] ?? 0) + 1;
      }

      // หา top category
      String? topCategory;
      int topCount = 0;
      counts.forEach((k, v) {
        if (v > topCount) {
          topCount = v;
          topCategory = k;
        }
      });

      final totalQuantity = inventoryItems.fold<int>(
        0,
        (acc, it) => acc + it.quantity,
      );
      final expiredCount = inventoryItems.where((it) => it.isExpired).length;
      final expiringSoonCount = inventoryItems.where((it) {
        final dl = it.daysLeft;
        return dl != null && dl >= 0 && dl <= 3;
      }).length;

      var expiringTodayItems = inventoryItems
          .where((it) => (it.daysLeft ?? -1) == 0)
          .toList(growable: false);
      if (expiringTodayItems.length > 10) {
        expiringTodayItems = expiringTodayItems.take(10).toList();
      }

      final nearestExpiryItem = inventoryItems
          .where((it) => it.daysLeft != null && it.daysLeft! >= 0)
          .fold<ShoppingItem?>(null, (cur, next) {
            if (cur == null) return next;
            return next.daysLeft! < cur.daysLeft! ? next : cur;
          });

      for (final doc in cookSnapshot.docs) {
        final data = doc.data();
        final raw = data['cooked_at'];
        DateTime? cookedAt;
        if (raw is Timestamp) {
          cookedAt = raw.toDate();
        } else if (raw is String) {
          cookedAt = DateTime.tryParse(raw);
        }
        if (cookedAt == null) continue;

        final cookedDate = _dateOnly(cookedAt);
        if (cookedDate.isBefore(startDate) || cookedDate.isAfter(endDate)) {
          continue;
        }
        final idx = cookedDate.difference(startDate).inDays;
        if (idx < 0 || idx >= weeklyUsage.length) continue;

        final servings = (data['servings_made'] as num?)?.toInt() ?? 1;
        weeklyUsage[idx].count += servings > 0 ? servings : 1;
      }

      return _DashboardData(
        totalItems: inventoryItems.length,
        totalQuantity: totalQuantity,
        expiringSoonCount: expiringSoonCount,
        expiredCount: expiredCount,
        expiringTodayItems: expiringTodayItems,
        nearestExpiryItem: nearestExpiryItem,
        weeklyCooking: weeklyUsage,
        categoryCounts: counts, // <- เพิ่ม
        topCategory: topCategory, // <- เพิ่ม
      );
    } catch (e, st) {
      debugPrint('Load dashboard failed: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final f1 = _loadDashboardData();
    final f2 = _loadUsername();
    setState(() {
      _dashboardFuture = f1;
      _usernameFuture = f2;
    });
    await Future.wait([f1, f2]);
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = _auth.currentUser;

    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final surface = cs.surface;
    final onSurface = cs.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: onSurface,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: primary.withAlpha(38),
              backgroundImage: user?.photoURL != null
                  ? NetworkImage(user!.photoURL!)
                  : null,
              child: user?.photoURL == null
                  ? Icon(Icons.person, color: primary)
                  : null,
            ),
            const SizedBox(width: 12),
            FutureBuilder<String>(
              future: _usernameFuture,
              builder: (context, snap) {
                final name = snap.data ?? 'ผู้ใช้';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_tHello $name! 👋',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tWelcomeBack,
                      style: TextStyle(
                        fontSize: 13,
                        color: onSurface.withAlpha(178),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: user == null
          ? _buildLoginPlaceholder(context)
          : FutureBuilder<_DashboardData>(
              future: _dashboardFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorState(context);
                }
                final data = snapshot.data ?? _DashboardData.empty();
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      ExpiringTodaySection(items: data.expiringTodayItems),
                      const SizedBox(height: 24),
                      _buildWeeklySection(context, data),
                      const SizedBox(height: 24),
                      _buildMenuIdeasSection(context),
                      const SizedBox(height: 24),
                      InventorySummarySection(
                        totalItems: data.totalItems,
                        counts: data.categoryCounts,
                        topCategory: data.topCategory,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildWeeklySection(BuildContext context, _DashboardData data) {
    final cs = Theme.of(context).colorScheme;
    final totalServings = data.weeklyCooking.fold<int>(
      0,
      (acc, d) => acc + d.count,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _tWeeklyCooking,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            if (data.hasCookingData)
              Text(
                '$_tTotalServingsPrefix$totalServings$_tTotalServingsSuffix',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withAlpha(166),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _buildWeeklyChart(context, data.weeklyCooking),
      ],
    );
  }

  Widget _buildMenuIdeasSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tMenuIdeas,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMenuPlaceholderCard(
                context,
                title: 'เมนูจากของใกล้หมดอายุ',
                subtitle: 'กำลังดึงเมนูจากโมดูลแนะนำอาหาร',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuPlaceholderCard(
                context,
                title: 'เมนูยอดนิยม',
                subtitle: 'กำลังดึงเมนูที่ผู้ใช้ทำบ่อย',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuPlaceholderCard(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.04).round()),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 110,
              width: double.infinity,
              color: cs.primary.withAlpha((255 * 0.12).round()),
              child: Icon(Icons.image_outlined, color: cs.primary, size: 40),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(153)),
          ),
        ],
      ),
    );
  }

  // ===== Widgets ทั่วไป =====
  Widget _buildLoginPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 64, color: cs.primary.withAlpha(102)),
          const SizedBox(height: 12),
          Text(
            _tNeedLogin,
            style: TextStyle(color: cs.onSurface.withAlpha(178)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: cs.error.withAlpha(204)),
          const SizedBox(height: 12),
          Text(_tLoadError, style: TextStyle(color: cs.onSurface)),
          const SizedBox(height: 8),
          TextButton(onPressed: _refresh, child: const Text(_tRetry)),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context, List<_DailyUsage> usage) {
    final cs = Theme.of(context).colorScheme;
    final maxValue = usage.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final hasData = maxValue > 0;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: cs.outline.withAlpha(76)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in usage)
                  _buildChartBar(
                    context,
                    day,
                    maxValue,
                    _isSameDay(day.date, today)
                        ? cs.primary
                        : cs.primary.withAlpha(191),
                  ),
              ],
            ),
          ),
          if (!hasData) ...[
            const SizedBox(height: 12),
            Text(
              _tNoWeeklyData,
              style: TextStyle(color: cs.onSurface.withAlpha(178)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartBar(
    BuildContext context,
    _DailyUsage usage,
    int maxValue,
    Color color,
  ) {
    final cs = Theme.of(context).colorScheme;
    const minBarHeight = 6.0;
    const maxBarHeight = 150.0;
    final height = maxValue == 0
        ? minBarHeight
        : ((usage.count / maxValue) * (maxBarHeight - minBarHeight)) +
              minBarHeight;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          usage.count.toString(),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withAlpha(204),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 14,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _dayLabel(usage.date),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withAlpha(178),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ===== Helpers =====
  static String _dayLabel(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'จ.';
      case DateTime.tuesday:
        return 'อ.';
      case DateTime.wednesday:
        return 'พ.';
      case DateTime.thursday:
        return 'พฤ.';
      case DateTime.friday:
        return 'ศ.';
      case DateTime.saturday:
        return 'ส.';
      default:
        return 'อา.';
    }
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ===== Models (dashboard) =====
class _DashboardData {
  const _DashboardData({
    required this.totalItems,
    required this.totalQuantity,
    required this.expiringSoonCount,
    required this.expiredCount,
    required this.expiringTodayItems,
    required this.nearestExpiryItem,
    required this.weeklyCooking,
    required this.categoryCounts, // <- เพิ่ม
    required this.topCategory, // <- เพิ่ม
  });

  factory _DashboardData.empty() {
    final today = _DashboardTabState._dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 6));
    return _DashboardData(
      totalItems: 0,
      totalQuantity: 0,
      expiringSoonCount: 0,
      expiredCount: 0,
      expiringTodayItems: const [],
      nearestExpiryItem: null,
      weeklyCooking: List.generate(
        7,
        (i) => _DailyUsage(date: start.add(Duration(days: i))),
      ),
      categoryCounts: const {}, // <- เพิ่ม
      topCategory: null, // <- เพิ่ม
    );
  }

  final int totalItems;
  final int totalQuantity;
  final int expiringSoonCount;
  final int expiredCount;
  final List<ShoppingItem> expiringTodayItems;
  final ShoppingItem? nearestExpiryItem;
  final List<_DailyUsage> weeklyCooking;

  final Map<String, int> categoryCounts; // <- เพิ่ม
  final String? topCategory; // <- เพิ่ม

  bool get hasCookingData => weeklyCooking.any((d) => d.count > 0);
  bool get hasExpiringToday => expiringTodayItems.isNotEmpty;
}

class _DailyUsage {
  _DailyUsage({required this.date});
  final DateTime date;
  int count = 0;
}
