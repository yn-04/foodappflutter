//lib/dashboard/dashboard.dart
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:my_app/dashboard/widgets/expiring_today_section.dart';
import 'package:my_app/dashboard/widgets/inventory_summary_section.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/foodreccom/utils/ingredient_utils.dart'
    as IngredientUtils;
import 'package:my_app/foodreccom/models/recipe/nutrition_info.dart';
import 'package:my_app/foodreccom/services/enhanced_ai_recommendation_service.dart';
import 'package:my_app/foodreccom/services/api_usage_service.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'package:provider/provider.dart';
import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:my_app/foodreccom/widgets/recipe_card.dart';
import 'package:my_app/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';
import 'package:my_app/foodreccom/recommendation_page.dart';
import 'package:my_app/notifications/notifications_center_screen.dart';

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
  String? _usernameLive; // อัปเดตแบบ realtime ถ้ามีการแก้ชื่อ

  // realtime listeners
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rawSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cookSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  Timer? _refreshDebounce;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _notificationsStream;

  // ===== ข้อความภาษาไทย =====
  static const _tHello = 'สวัสดี';
  static const _tWelcomeBack = 'ยินดีต้อนรับกลับ';
  static const _tWeeklyCooking = 'สรุปการทำอาหารรายสัปดาห์';
  static const _tTotalServingsPrefix = 'รวม ';
  static const _tTotalServingsSuffix = ' ที่';
  static const _tMenuIdeas = 'เมนูอาหารแนะนำ';
  static const _tAiInsight = 'Smart Insight by Gemini';
  static const _tNeedLogin = 'กรุณาเข้าสู่ระบบเพื่อดูแดชบอร์ดของคุณ';
  static const _tLoadError = 'โหลดข้อมูลไม่สำเร็จ';
  static const _tRetry = 'ลองใหม่';
  static const _tNoWeeklyData = 'ยังไม่มีข้อมูลการทำอาหารในสัปดาห์นี้';
  static const _tTopUsed = 'Top5 วัตถุดิบที่ใช้บ่อย';
  static const _tTopDiscarded = 'Top5 วัตถุดิบที่ถูกทิ้งบ่อย';
  static const _tWastedPie = 'หมดอายุโดยไม่ได้ใช้ (30 วัน)';
  static const _tMenuThisWeek = 'Top5 เมนูที่ทำบ่อยสัปดาห์นี้';
  static const _tMenuLastWeek = 'Top5 เมนูที่ทำบ่อยสัปดาห์ก่อน';
  static const _tUseBeforeExpiry = 'แนวโน้มวัตถุดิบ';
  static const _tThisMonth = 'เดือนนี้';
  static const _tLastMonth = 'เดือนก่อน';

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboardData();
    _usernameFuture = _loadUsername();
    // ขอเมนูแนะนำล่วงหน้า ถ้ายังไม่มี โหลดครั้งเดียวหลังเฟรมแรก
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<EnhancedRecommendationProvider>();
      if (!p.isLoading && p.recommendations.isEmpty) {
        p.getHybridRecommendations();
      }
    });

    _setupRealtimeListeners();
    _initNotificationStream();
  }

  void _setupRealtimeListeners() {
    final user = _auth.currentUser;
    if (user == null) return;
    final userRef = _firestore.collection('users').doc(user.uid);
    final rawCol = userRef.collection('raw_materials');
    final cookCol = userRef.collection('cooking_history');

    // Listen to inventory changes
    _rawSub?.cancel();
    _rawSub = rawCol.snapshots().listen((_) => _debouncedRefresh());

    // Listen to cooking history changes (affects several dashboard sections)
    _cookSub?.cancel();
    _cookSub = cookCol.snapshots().listen((_) => _debouncedRefresh());

    // Listen to user profile for display name updates
    _userSub?.cancel();
    _userSub = userRef.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final newName = _extractUsernameFromData(data);
      if (newName != null &&
          newName.trim().isNotEmpty &&
          newName != _usernameLive) {
        setState(() => _usernameLive = newName);
      }
    });
  }

  void _debouncedRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      final f1 = _loadDashboardData();
      setState(() {
        _dashboardFuture = f1;
      });
    });
  }

  Future<List<_DashboardInsightEntry>> _generateSmartInsights(
    String userName,
    _DashboardData data,
  ) async {
    final fallback = _localInsights(userName, data);
    final context = _buildInsightContext(userName, data);

    try {
      if (!await ApiUsageService.canUseGemini()) {
        return fallback;
      }
      if (!await ApiUsageService.allowGeminiCall()) {
        return fallback;
      }

      final ai = EnhancedAIRecommendationService();
      final prompt = [
        'คุณคือ Smart Insight ที่ช่วยสรุปแดชบอร์ดจัดการครัว พูดภาษาไทย กระชับ เป็นกันเอง และอ้างอิงข้อมูลจริงเท่านั้น',
        'ภารกิจ: วิเคราะห์แต่ละหัวข้อหลักของแดชบอร์ด แล้วให้ข้อสังเกต หรือคำแนะนำสั้น ๆ 1-2 ประโยคต่อหัวข้อ',
        'ตอบเป็น JSON รูปแบบ {"insights":[{"section":"expiring_today","title":"หัวข้อ","message":"ข้อความ"}]}',
        'เพิ่มอินไซต์สรุปรวมของแดชบอร์ดใน section "summary" เสมอ',
        'ระบุ section ให้ตรงกับคีย์ที่ให้มาเท่านั้น: summary, expiring_today, weekly_cooking, top_ingredients, use_before_expiry, top_menus, daily_nutrition, inventory_summary',
        'ห้ามแต่งข้อมูลเพิ่ม หากไม่มีข้อมูลให้สื่อสารอย่างสุภาพว่าไม่มีข้อมูล',
        'หลีกเลี่ยงการใช้ bullet หรือการฟอร์แมตพิเศษ',
        'ข้อมูล:',
        jsonEncode(context),
      ].join('\n');

      final txt = await ai.generateTextSmart(prompt);
      await ApiUsageService.countGemini();
      final parsed = _parseInsightResponse(txt);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      try {
        await ApiUsageService.setGeminiCooldown(const Duration(seconds: 20));
      } catch (_) {}
    }

    return fallback;
  }

  Map<String, dynamic> _buildInsightContext(
    String userName,
    _DashboardData data,
  ) {
    final now = DateTime.now();
    final expiringByCategory = <String, int>{};
    final expiringItems = data.expiringTodayItems
        .map((item) {
          final category = item.category.trim().isEmpty
              ? 'ไม่ระบุ'
              : item.category;
          expiringByCategory[category] =
              (expiringByCategory[category] ?? 0) + 1;
          return {
            'name': item.name,
            'category': category,
            'days_left': item.daysLeft,
            'quantity': item.quantity,
            'unit': item.unit,
          };
        })
        .toList(growable: false);

    final weeklyData = data.weeklyCooking
        .map(
          (d) => {
            'date': d.date.toIso8601String(),
            'weekday': d.date.weekday,
            'count': d.count,
          },
        )
        .toList(growable: false);

    final topWeekday = data.monthWeekdayUsage.entries.isEmpty
        ? null
        : (data.monthWeekdayUsage.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    final topCategoryUsage = data.monthCategoryUsage.entries.isEmpty
        ? null
        : (data.monthCategoryUsage.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;

    final topMenusThisWeek = data.topMenusThisWeek
        .map((m) => {'name': m.name, 'count': m.count})
        .toList(growable: false);
    final topMenusLastWeek = data.topMenusLastWeek
        .map((m) => {'name': m.name, 'count': m.count})
        .toList(growable: false);

    final dailyNutrition = data.dailyNutrition
        .map(
          (n) => {
            'date': n.date.toIso8601String(),
            'calories': n.totals.calories,
            'protein': n.totals.protein,
            'carbs': n.totals.carbs,
            'fat': n.totals.fat,
            'fiber': n.totals.fiber,
            'sodium': n.totals.sodium,
          },
        )
        .toList(growable: false);

    final nearest = data.nearestExpiryItem;
    final nearestMap = nearest == null
        ? null
        : {
            'name': nearest.name,
            'days_left': nearest.daysLeft,
            'category': nearest.category,
            'quantity': nearest.quantity,
            'unit': nearest.unit,
          };

    return {
      'user': userName,
      'month': _thaiMonthName(now),
      'generated_at': now.toIso8601String(),
      'summary': {
        'total_items': data.totalItems,
        'total_quantity': data.totalQuantity,
        'expiring_today': data.expiringTodayItems.length,
        'expiring_soon': data.expiringSoonCount,
        'expired': data.expiredCount,
        'avg_expired_per_week': data.wastedCount30 / 4.0,
        'top_usage_weekday': topWeekday == null
            ? null
            : {
                'weekday': topWeekday.key,
                'label': _weekdayThaiName(topWeekday.key),
                'count': topWeekday.value,
              },
        'top_usage_category': topCategoryUsage == null
            ? null
            : {
                'category': topCategoryUsage.key,
                'count': topCategoryUsage.value,
              },
      },
      'sections': {
        'expiring_today': {
          'items': expiringItems,
          'group_by_category': expiringByCategory,
          'nearest_expiry': nearestMap,
          'expiring_soon_count': data.expiringSoonCount,
        },
        'weekly_cooking': {
          'daily': weeklyData,
          'has_data': data.hasCookingData,
        },
        'top_ingredients': {
          'used_often': data.topUsed
              .map((e) => {'name': e.name, 'count': e.count})
              .toList(growable: false),
          'discarded_often': data.topDiscarded
              .map((e) => {'name': e.name, 'count': e.count})
              .toList(growable: false),
        },
        'use_before_expiry': {
          'pct_use_this_month': data.pctUseBeforeExpiryThisMonth,
          'pct_use_prev_month': data.pctUseBeforeExpiryPrevMonth,
          'pct_waste_this_month': data.pctWasteThisMonth,
          'pct_waste_prev_month': data.pctWastePrevMonth,
        },
        'top_menus': {
          'this_week': topMenusThisWeek,
          'last_week': topMenusLastWeek,
        },
        'daily_nutrition': {'days': dailyNutrition},
        'inventory_summary': {
          'total_items': data.totalItems,
          'category_counts': data.categoryCounts,
          'latest_added': data.categoryLatestAdded.map(
            (key, value) => MapEntry(key, value?.toIso8601String()),
          ),
          'top_category': data.topCategory,
          'wasted_by_category': data.wastedByCategory,
        },
      },
    };
  }

  List<_DashboardInsightEntry> _parseInsightResponse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <_DashboardInsightEntry>[];
    }
    final cleaned = _stripCodeFences(raw.trim());
    try {
      final decoded = jsonDecode(cleaned);
      final iterable = decoded is Map<String, dynamic>
          ? decoded['insights']
          : decoded is List
          ? decoded
          : null;
      if (iterable is! List) {
        return const <_DashboardInsightEntry>[];
      }

      final result = <_DashboardInsightEntry>[];
      for (final entry in iterable) {
        if (entry is! Map) continue;
        final section = (entry['section'] ?? 'general').toString().trim();
        final title = (entry['title'] ?? '').toString().trim();
        final message = (entry['message'] ?? entry['content'] ?? '')
            .toString()
            .trim();
        if (message.isEmpty) continue;
        result.add(
          _DashboardInsightEntry(
            section: section.isEmpty ? 'general' : section,
            title: title.isEmpty ? _defaultInsightTitle(section) : title,
            message: message,
          ),
        );
      }
      return result;
    } catch (_) {
      return const <_DashboardInsightEntry>[];
    }
  }

  String _stripCodeFences(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('```')) {
      final firstLineEnd = trimmed.indexOf('\n');
      final lastFence = trimmed.lastIndexOf('```');
      if (firstLineEnd != -1 && lastFence != -1 && lastFence > firstLineEnd) {
        return trimmed.substring(firstLineEnd + 1, lastFence).trim();
      }
    }
    return trimmed;
  }

  List<_DashboardInsightEntry> _localInsights(
    String userName,
    _DashboardData data,
  ) {
    final insights = <_DashboardInsightEntry>[];
    final now = DateTime.now();
    final monthName = _thaiMonthName(now);
    final displayName = userName.trim().isEmpty ? 'คุณ' : userName.trim();
    final expiringCount = data.expiringTodayItems.length;
    final totalServings = data.weeklyCooking.fold<int>(
      0,
      (acc, d) => acc + d.count,
    );
    final busiestDay = data.weeklyCooking.isEmpty
        ? null
        : (List<_DailyUsage>.from(
            data.weeklyCooking,
          )..sort((a, b) => b.count.compareTo(a.count))).first;
    final currentPct = (data.pctUseBeforeExpiryThisMonth * 100)
        .clamp(0, 100)
        .toDouble();
    final prevPct = (data.pctUseBeforeExpiryPrevMonth * 100)
        .clamp(0, 100)
        .toDouble();
    final diff = currentPct - prevPct;
    final trendText = diff.abs() < 0.5
        ? 'ทรงตัวจากเดือนก่อน'
        : diff >= 0
        ? 'ดีขึ้น ${diff.toStringAsFixed(0)}%'
        : 'ลดลง ${diff.abs().toStringAsFixed(0)}%';

    final summaryParts = <String>[
      '$displayName มีวัตถุดิบหมดอายุวันนี้ $expiringCount รายการ',
      'สัปดาห์นี้ทำอาหาร $totalServings ที่',
      'ใช้ก่อนหมดอายุ ${currentPct.toStringAsFixed(0)}% ($trendText)',
    ];
    if (data.dailyNutrition.isNotEmpty) {
      final latest = data.dailyNutrition.first;
      summaryParts.add(
        'รับพลังงานล่าสุด ${latest.totals.calories.toStringAsFixed(0)} kcal',
      );
    }
    insights.add(
      _DashboardInsightEntry(
        section: 'summary',
        title: 'ภาพรวมแดชบอร์ด',
        message: summaryParts.join(' • '),
      ),
    );

    // Expiring today
    if (data.expiringTodayItems.isEmpty) {
      insights.add(
        _DashboardInsightEntry(
          section: 'expiring_today',
          title: 'วัตถุดิบที่หมดอายุวันนี้',
          message:
              '$displayName วันนี้ไม่มีวัตถุดิบที่จะหมดอายุ ใช้เวลาจัดสต็อกได้เลยนะคะ',
        ),
      );
    } else {
      final grouped = <String, int>{};
      for (final item in data.expiringTodayItems) {
        final cat = item.category.trim().isEmpty ? 'ไม่ระบุ' : item.category;
        grouped[cat] = (grouped[cat] ?? 0) + 1;
      }
      final topCat = grouped.entries.isEmpty
          ? null
          : (grouped.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first;
      final nearest = data.nearestExpiryItem;
      final messageParts = <String>[
        'วันนี้มีวัตถุดิบหมดอายุ ${data.expiringTodayItems.length} รายการ',
      ];
      if (topCat != null) {
        messageParts.add(
          'หมวดที่เจอบ่อยคือ "${topCat.key}" ${topCat.value} รายการ',
        );
      }
      if (nearest != null && (nearest.daysLeft ?? 0) >= 0) {
        messageParts.add(
          'ลองใช้ ${nearest.name} ภายใน ${nearest.daysLeft} วัน เพื่อไม่ให้เสียของนะคะ',
        );
      }
      insights.add(
        _DashboardInsightEntry(
          section: 'expiring_today',
          title: 'วัตถุดิบที่หมดอายุวันนี้',
          message: '$displayName ${messageParts.join(' • ')}',
        ),
      );
    }

    // Weekly cooking
    final weeklyMsg = data.hasCookingData
        ? 'สัปดาห์นี้$displayName ทำอาหาร ${totalServings} ที่ โดย${busiestDay != null && busiestDay.count > 0 ? 'วัน${_weekdayThaiName(busiestDay.date.weekday)}ครัวคึกสุดที่ ${busiestDay.count} ที่' : 'ยังไม่มีวันที่โดดเด่น'}'
        : '$displayName ยังไม่มีการบันทึกการทำอาหารในสัปดาห์นี้ ลองเพิ่มเมนูสักอย่างเพื่อเริ่มต้นนะคะ';
    insights.add(
      _DashboardInsightEntry(
        section: 'weekly_cooking',
        title: 'สรุปการทำอาหารรายสัปดาห์',
        message: weeklyMsg,
      ),
    );

    // Top ingredients
    final topUsed = data.topUsed.isNotEmpty ? data.topUsed.first : null;
    final topDiscarded = data.topDiscarded.isNotEmpty
        ? data.topDiscarded.first
        : null;
    final ingredientMsgParts = <String>[];
    if (topUsed != null) {
      ingredientMsgParts.add(
        '$displayName ใช้ "${topUsed.name}" บ่อยที่สุด ${topUsed.count} ครั้ง',
      );
    }
    if (topDiscarded != null) {
      ingredientMsgParts.add(
        '"${topDiscarded.name}" ถูกทิ้งบ่อยที่สุด ${topDiscarded.count} ครั้ง',
      );
    }
    if (ingredientMsgParts.isEmpty) {
      ingredientMsgParts.add('ยังไม่มีข้อมูลการใช้วัตถุดิบรอบสัปดาห์');
    }
    insights.add(
      _DashboardInsightEntry(
        section: 'top_ingredients',
        title: 'Top วัตถุดิบ',
        message: ingredientMsgParts.join(' • '),
      ),
    );

    // Use before expiry
    insights.add(
      _DashboardInsightEntry(
        section: 'use_before_expiry',
        title: 'การใช้ก่อนหมดอายุ',
        message:
            '$displayName เดือน$monthName ใช้วัตถุดิบทันก่อนหมดอายุ ${currentPct.toStringAsFixed(0)}% ($trendText) ระวังของเสียให้ต่ำกว่านี้ได้นะคะ',
      ),
    );

    // Top menus
    final menuThisWeek = data.topMenusThisWeek.isNotEmpty
        ? data.topMenusThisWeek.first
        : null;
    final menuLastWeek = data.topMenusLastWeek.isNotEmpty
        ? data.topMenusLastWeek.first
        : null;
    final menusMsgParts = <String>[];
    if (menuThisWeek != null) {
      menusMsgParts.add(
        'สัปดาห์นี้ $displayName ทำ "${menuThisWeek.name}" ${menuThisWeek.count} ครั้ง',
      );
    }
    if (menuLastWeek != null) {
      menusMsgParts.add(
        'สัปดาห์ก่อนคือ "${menuLastWeek.name}" ${menuLastWeek.count} ครั้ง',
      );
    }
    if (menusMsgParts.isEmpty) {
      menusMsgParts.add('ยังไม่มีเมนูยอดนิยมที่บันทึกไว้');
    }
    insights.add(
      _DashboardInsightEntry(
        section: 'top_menus',
        title: 'เมนูยอดนิยม',
        message: menusMsgParts.join(' • '),
      ),
    );

    // Inventory summary
    final topCategory = data.topCategory ?? 'ไม่ระบุ';
    final inventoryMessage = [
      'คลังของ$displayName มีวัตถุดิบทั้งหมด ${data.totalItems} รายการ',
      if (data.expiringSoonCount > 0)
        'มี ${data.expiringSoonCount} รายการใกล้หมดอายุใน 3 วัน',
      'หมวดที่มีของมากที่สุดคือ "$topCategory"',
    ].join(' • ');
    insights.add(
      _DashboardInsightEntry(
        section: 'inventory_summary',
        title: 'ภาพรวมคลังอาหาร',
        message: inventoryMessage,
      ),
    );

    return insights;
  }

  String _defaultInsightTitle(String section) {
    switch (section) {
      case 'summary':
        return 'ภาพรวมแดชบอร์ด';
      case 'expiring_today':
        return 'หมดอายุวันนี้';
      case 'weekly_cooking':
        return 'สรุปการทำอาหาร';
      case 'top_ingredients':
        return 'Top วัตถุดิบ';
      case 'use_before_expiry':
        return 'การใช้ก่อนหมดอายุ';
      case 'top_menus':
        return 'เมนูยอดนิยม';
      case 'daily_nutrition':
        return 'โภชนาการต่อวัน';
      case 'inventory_summary':
        return 'ภาพรวมคลัง';
      default:
        return 'Smart Insight';
    }
  }

  String _thaiMonthName(DateTime date) {
    const months = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    return months[date.month];
  }

  String _formatThaiShortDate(DateTime date) {
    const months = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final m = months[date.month];
    return '${date.day} $m';
  }

  String _weekdayThaiName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'วันจันทร์';
      case DateTime.tuesday:
        return 'วันอังคาร';
      case DateTime.wednesday:
        return 'วันพุธ';
      case DateTime.thursday:
        return 'วันพฤหัสบดี';
      case DateTime.friday:
        return 'วันศุกร์';
      case DateTime.saturday:
        return 'วันเสาร์';
      default:
        return 'วันอาทิตย์';
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<String> _loadUsername() async {
    final user = _auth.currentUser;
    if (user == null) return 'ผู้ใช้';
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      String? name = (data['username'] as String?)?.trim();
      name ??= (data['firstName'] as String?)?.trim();
      name ??= (data['fullName'] as String?)?.trim();
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
      final start30 = endDate.subtract(const Duration(days: 30));
      final start90 = endDate.subtract(const Duration(days: 90));

      // สัปดาห์นี้ (เริ่มวันจันทร์) และสัปดาห์ก่อน
      final mondayThisWeek = endDate.subtract(
        Duration(days: endDate.weekday - 1),
      );
      final mondayPrevWeek = mondayThisWeek.subtract(const Duration(days: 7));
      final sundayPrevWeek = mondayThisWeek.subtract(
        const Duration(milliseconds: 1),
      );
      final sundayThisWeek = mondayThisWeek
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1));

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
      // ประวัติ 30 วันสำหรับ Top 5 ใช้บ่อย และเมนูของสัปดาห์
      final cook30Future = cookCol
          .where(
            'cooked_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start30),
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
      // ประวัติ 90 วันสำหรับวิเคราะห์ใช้ก่อนหมดอายุ
      final cook90Future = cookCol
          .where(
            'cooked_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start90),
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
      final cook30Snapshot = await cook30Future;
      await cook90Future;

      final inventoryItems = rawSnapshot.docs
          .map(
            (d) => ShoppingItem.fromMap(
              d.data(),
              d.id,
              ownerId: user.uid,
              reference: d.reference,
            ),
          )
          .toList(growable: false);
      final itemById = {for (final it in inventoryItems) it.id: it};

      DateTime? _parseDate(dynamic value) {
        if (value == null) return null;
        if (value is Timestamp) return value.toDate();
        if (value is DateTime) return value;
        if (value is String) {
          return DateTime.tryParse(value);
        }
        if (value is int) {
          try {
            return DateTime.fromMillisecondsSinceEpoch(value);
          } catch (_) {
            return null;
          }
        }
        return null;
      }

      // เก็บหมวดย่อยและเวลาที่เพิ่มไว้ใช้จับคู่วัตถุดิบกับหมวดหลัก
      final subcategoryById = <String, String>{};
      final createdAtById = <String, DateTime?>{};
      for (final doc in rawSnapshot.docs) {
        final data = doc.data();
        final sub = (data['subcategory'] ?? '').toString().trim();
        if (sub.isNotEmpty) {
          subcategoryById[doc.id] = sub;
        }
        final created =
            _parseDate(data['created_at']) ??
            _parseDate(data['created_at_local']) ??
            _parseDate(data['updated_at']);
        createdAtById[doc.id] = created;
      }

      // เฉพาะรายการที่ยังไม่หมดอายุ และมีจำนวน > 0 สำหรับสรุปคลัง (Dashboard Summary)
      final activeItems = inventoryItems
          .where((it) => !it.isExpired && it.quantity > 0)
          .toList(growable: false);

      // นับจำนวนต่อ "หมวดหลัก" ของผู้ใช้ เรียงเข้า bucket เดียวกัน
      final counts = <String, int>{};
      final latestAdded = <String, DateTime?>{};
      for (final it in activeItems) {
        final rawCategory = it.category.trim();
        final rawSubcategory = subcategoryById[it.id];

        String? primary = (rawSubcategory == null || rawSubcategory.isEmpty)
            ? null
            : Categories.categoryForSubcategory(rawSubcategory);

        if (primary == null || primary.isEmpty) {
          if (rawCategory.isNotEmpty) {
            final normalized = Categories.normalize(rawCategory);
            if (normalized.isNotEmpty && Categories.isKnown(normalized)) {
              primary = normalized;
            } else {
              final fallback = Categories.categoryForSubcategory(rawCategory);
              if (fallback != null && fallback.isNotEmpty) {
                primary = fallback;
              }
            }
          }
        }

        final key = (primary == null || primary.trim().isEmpty)
            ? 'ไม่ระบุ'
            : Categories.normalize(primary);

        counts[key] = (counts[key] ?? 0) + 1;

        final createdAt = it.createdAt ?? it.updatedAt ?? createdAtById[it.id];
        if (createdAt != null) {
          final current = latestAdded[key];
          if (current == null || createdAt.isAfter(current)) {
            latestAdded[key] = createdAt;
          }
        } else {
          latestAdded.putIfAbsent(key, () => null);
        }
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

      // ===== Top 5: Used often (ภายใน 7 วัน) + monthly aggregates =====
      final combinedUsed7 = <String, int>{};
      final canonicalNameDisplay = <String, String>{};
      final dailyNutritionTotals = <DateTime, _NutritionTotals>{};

      String _normalizeIngredientKey(String name) =>
          name.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_/()]+'), '');

      bool _namesSimilar(String a, String b) {
        final al = a.trim().toLowerCase();
        final bl = b.trim().toLowerCase();
        if (al == bl) return true;
        if (al.replaceAll(RegExp(r'\s+'), '') ==
            bl.replaceAll(RegExp(r'\s+'), '')) {
          return true;
        }
        if (al.contains(bl) || bl.contains(al)) return true;
        return IngredientUtils.ingredientsMatch(a, b) ||
            IngredientUtils.ingredientsMatch(b, a);
      }

      bool _preferDisplay(String existing, String candidate) {
        final ex = existing.trim();
        final cand = candidate.trim();
        if (ex.isEmpty) return true;
        if (cand.isEmpty) return false;
        if (cand.length < ex.length) return true;
        final exLower = ex.toLowerCase();
        final candLower = cand.toLowerCase();
        if (ex == exLower && cand != candLower) return true;
        return false;
      }

      String _canonicalFor(String name) {
        final base = _normalizeIngredientKey(name);
        if (canonicalNameDisplay.containsKey(base)) {
          return base;
        }
        for (final entry in canonicalNameDisplay.entries) {
          if (_namesSimilar(entry.value, name)) {
            return entry.key;
          }
        }
        canonicalNameDisplay[base] = name.trim();
        return base;
      }

      String? _incrementName(Map<String, int> counter, String rawName) {
        final trimmed = rawName.trim();
        if (trimmed.isEmpty) return null;
        final key = _canonicalFor(trimmed);
        final display = canonicalNameDisplay[key];
        if (display == null) {
          canonicalNameDisplay[key] = trimmed;
        } else if (_preferDisplay(display, trimmed)) {
          canonicalNameDisplay[key] = trimmed;
        }
        counter[key] = (counter[key] ?? 0) + 1;
        return key;
      }

      final monthUsageTotal = <String, Map<String, int>>{};
      final monthUsageSuccess = <String, Map<String, int>>{};
      final monthWasteTotal = <String, Map<String, int>>{};
      final monthWasteWasted = <String, Map<String, int>>{};

      String _monthKey(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

      void _incrementMonthlyUsage(
        DateTime date,
        String rawName, {
        required bool beforeExpiry,
      }) {
        final keyMonth = _monthKey(date);
        final totalMap = monthUsageTotal.putIfAbsent(
          keyMonth,
          () => <String, int>{},
        );
        final canonical = _incrementName(totalMap, rawName);
        if (beforeExpiry && canonical != null) {
          final okMap = monthUsageSuccess.putIfAbsent(
            keyMonth,
            () => <String, int>{},
          );
          okMap[canonical] = (okMap[canonical] ?? 0) + 1;
        }
      }

      void _recordWaste(DateTime date, String rawName, {required bool wasted}) {
        final keyMonth = _monthKey(date);
        final totalMap = monthWasteTotal.putIfAbsent(
          keyMonth,
          () => <String, int>{},
        );
        final canonical = _incrementName(totalMap, rawName);
        if (wasted && canonical != null) {
          final wasteMap = monthWasteWasted.putIfAbsent(
            keyMonth,
            () => <String, int>{},
          );
          wasteMap[canonical] = (wasteMap[canonical] ?? 0) + 1;
        }
      }

      final monthWeekdayUsage = <int, int>{
        1: 0,
        2: 0,
        3: 0,
        4: 0,
        5: 0,
        6: 0,
        7: 0,
      };
      final monthCategoryUsage = <String, int>{};
      for (final doc in cook30Snapshot.docs) {
        final data = doc.data();
        DateTime? cookedAt;
        final rawCooked = data['cooked_at'];
        if (rawCooked is Timestamp) cookedAt = rawCooked.toDate();
        if (rawCooked is String) cookedAt = DateTime.tryParse(rawCooked);
        final cookedDate = cookedAt == null ? null : _dateOnly(cookedAt);
        final weekday = (cookedAt ?? DateTime.now()).weekday;
        final used = (data['used_ingredients'] as List? ?? []);
        NutritionInfo? nutrition;
        final nutritionRaw = data['total_nutrition'];
        if (nutritionRaw is Map<String, dynamic>) {
          nutrition = NutritionInfo.fromMap(nutritionRaw);
        } else if (nutritionRaw is Map) {
          final normalized = <String, dynamic>{};
          nutritionRaw.forEach((key, value) {
            normalized[key.toString()] = value;
          });
          nutrition = NutritionInfo.fromMap(normalized);
        }
        for (final u in used) {
          final name = (u is Map && u['name'] != null)
              ? u['name'].toString().trim()
              : '';
          if (name.isEmpty) continue;
          if (cookedDate != null &&
              !cookedDate.isBefore(startDate) &&
              !cookedDate.isAfter(endDate)) {
            _incrementName(combinedUsed7, name);
          }
          // category aggregation
          final catRaw = (u is Map ? u['category'] : null)?.toString();
          final cat = Categories.normalize(catRaw);
          final keyCat = cat.isEmpty ? 'ไม่ระบุ' : cat;
          monthCategoryUsage[keyCat] = (monthCategoryUsage[keyCat] ?? 0) + 1;
          // weekday aggregation (by used ingredient count)
          monthWeekdayUsage[weekday] = (monthWeekdayUsage[weekday] ?? 0) + 1;
        }
        if (cookedDate != null &&
            !cookedDate.isBefore(startDate) &&
            !cookedDate.isAfter(endDate) &&
            nutrition != null) {
          final totals = dailyNutritionTotals.putIfAbsent(
            cookedDate,
            () => _NutritionTotals(),
          );
          totals.add(nutrition);
        }
      }

      // ===== % Used before expiry: MoM =====
      // ===== Refined: use usage_logs to determine used-before-expiry by quantity =====
      // เตรียมกลุ่มรายการที่ต้องตรวจสอบ (ช่วง 30 วัน, เดือนนี้, เดือนก่อน)
      bool _inRange(DateTime d, DateTime a, DateTime b) =>
          !d.isBefore(_dateOnly(a)) && !d.isAfter(_dateOnly(b));

      final cand30 = <ShoppingItem>[];
      for (final it in inventoryItems) {
        final d = it.expiryDate;
        if (d == null) continue;
        final dd = _dateOnly(d);
        if (_inRange(dd, start30, endDate)) cand30.add(it);
      }

      // โหลด usage_logs ของรายการที่เกี่ยวข้อง
      final allIds = {
        ...inventoryItems.map((e) => e.id),
        ...cand30.map((e) => e.id),
      }..removeWhere((e) => e.isEmpty);

      final usageByItem = <String, List<Map<String, dynamic>>>{};
      await Future.wait(
        allIds.map((id) async {
          try {
            final logs = await rawCol.doc(id).collection('usage_logs').get();
            usageByItem[id] = logs.docs.map((d) {
              final m = d.data();
              final qty = (m['quantity'] is num)
                  ? (m['quantity'] as num).toDouble()
                  : double.tryParse('${m['quantity']}') ?? 0.0;
              final ua = m['used_at'];
              DateTime? usedAt;
              if (ua is Timestamp) usedAt = ua.toDate();
              if (ua is String) usedAt = DateTime.tryParse(ua);
              return {'qty': qty, 'used_at': usedAt};
            }).toList();
          } catch (_) {
            usageByItem[id] = const [];
          }
        }),
      );

      for (final entry in usageByItem.entries) {
        final item = itemById[entry.key];
        if (item == null) continue;
        final name = item.name.trim();
        if (name.isEmpty) continue;
        for (final log in entry.value) {
          final usedAt = log['used_at'] as DateTime?;
          if (usedAt == null) continue;
          final usedDate = _dateOnly(usedAt);
          final beforeExpiry = item.expiryDate == null
              ? true
              : !usedDate.isAfter(_dateOnly(item.expiryDate!));
          _incrementMonthlyUsage(usedAt, name, beforeExpiry: beforeExpiry);
          if (!usedDate.isBefore(startDate) && !usedDate.isAfter(endDate)) {
            _incrementName(combinedUsed7, name);
          }
        }
      }

      final topUsedEntries = combinedUsed7.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      double _leftoverAfterExpiry(ShoppingItem it) {
        final exp = it.expiryDate;
        if (exp == null) return 0;
        final dd = _dateOnly(exp);
        final logs = usageByItem[it.id] ?? const [];
        double sumAll = 0;
        double sumBefore = 0;
        for (final e in logs) {
          final q = (e['qty'] as double?) ?? 0.0;
          final t = e['used_at'] as DateTime?;
          sumAll += q;
          if (t != null && !t.isAfter(dd)) sumBefore += q;
        }
        final initial = sumAll + it.quantity.toDouble();
        final leftoverAtExpiry = initial - sumBefore;
        return leftoverAtExpiry <= 0 ? 0 : leftoverAtExpiry;
      }

      bool _usedBeforeExpiry(ShoppingItem it) =>
          _leftoverAfterExpiry(it) <= 0.0001;

      for (final it in inventoryItems) {
        final exp = it.expiryDate;
        if (exp == null) continue;
        final expDate = _dateOnly(exp);
        if (expDate.isAfter(endDate)) continue;
        final wasted = _leftoverAfterExpiry(it) > 0.0001;
        _recordWaste(expDate, it.name, wasted: wasted);
      }

      // ===== Top 5: Discarded often (หมดอายุภายใน 7 วันและเหลือปริมาณ) =====
      final discardedCount = <String, int>{};
      final discardWindowStart = endDate.subtract(const Duration(days: 7));
      for (final it in inventoryItems) {
        final exp = it.expiryDate;
        if (exp == null) continue;
        final expDate = _dateOnly(exp);
        if (expDate.isBefore(discardWindowStart) || expDate.isAfter(endDate)) {
          continue;
        }
        if (_leftoverAfterExpiry(it) <= 0.0001) continue;
        _incrementName(discardedCount, it.name);
      }

      final topDiscarded = discardedCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDiscardedList = topDiscarded
          .take(5)
          .map(
            (e) => _NameCount(
              name: canonicalNameDisplay[e.key] ?? e.key,
              count: e.value,
            ),
          )
          .toList(growable: false);

      final topUsedList = topUsedEntries
          .take(5)
          .map(
            (e) => _NameCount(
              name: canonicalNameDisplay[e.key] ?? e.key,
              count: e.value,
            ),
          )
          .toList(growable: false);

      for (int i = 0; i < 7; i++) {
        final day = startDate.add(Duration(days: i));
        dailyNutritionTotals.putIfAbsent(day, () => _NutritionTotals());
      }

      final dailyNutrition =
          dailyNutritionTotals.entries
              .map((e) => _DailyNutrition(date: e.key, totals: e.value))
              .toList(growable: false)
            ..sort((a, b) => b.date.compareTo(a.date));
      final dailyNutritionLimited = dailyNutrition
          .take(7)
          .toList(growable: false);

      // คำนวณ wastedByCategory (30 วันล่าสุด)
      final wastedByCategory = <String, int>{};
      for (final it in cand30) {
        if (!_usedBeforeExpiry(it)) {
          final cat = (it.category.isEmpty ? 'ไม่ระบุ' : it.category);
          wastedByCategory[cat] = (wastedByCategory[cat] ?? 0) + 1;
        }
      }

      double _calcMonthPctFromMaps(String monthKey) {
        final totals = monthUsageTotal[monthKey];
        if (totals == null || totals.isEmpty) return 0;
        final totalCount = totals.values.fold<int>(0, (a, b) => a + b);
        if (totalCount == 0) return 0;
        final successes = monthUsageSuccess[monthKey] ?? const {};
        final successCount = successes.values.fold<int>(0, (a, b) => a + b);
        return successCount / totalCount;
      }

      double _calcWastePct(String monthKey) {
        final totals = monthWasteTotal[monthKey];
        if (totals == null || totals.isEmpty) return 0;
        final totalCount = totals.values.fold<int>(0, (a, b) => a + b);
        if (totalCount == 0) return 0;
        final wasted = monthWasteWasted[monthKey] ?? const {};
        final wasteCount = wasted.values.fold<int>(0, (a, b) => a + b);
        return wasteCount / totalCount;
      }

      final currentMonthKey = _monthKey(endDate);
      final prevMonthKey = _monthKey(
        DateTime(
          endDate.month == 1 ? endDate.year - 1 : endDate.year,
          endDate.month == 1 ? 12 : endDate.month - 1,
          1,
        ),
      );

      final pctThisMonth = _calcMonthPctFromMaps(currentMonthKey);
      final pctPrevMonth = _calcMonthPctFromMaps(prevMonthKey);
      final pctWasteThisMonth = _calcWastePct(currentMonthKey);
      final pctWastePrevMonth = _calcWastePct(prevMonthKey);
      final wastedCount30 = wastedByCategory.values.fold<int>(
        0,
        (a, b) => a + b,
      );

      // ===== Top Menus: this week vs last week =====
      final thisWeek = <String, _NameCountWithImage>{};
      final lastWeek = <String, _NameCountWithImage>{};
      for (final d in cook30Snapshot.docs) {
        final data = d.data();
        String name = (data['recipe_name'] ?? '').toString();
        if (name.trim().isEmpty) continue;
        DateTime? cookedAt;
        final raw = data['cooked_at'];
        if (raw is Timestamp) cookedAt = raw.toDate();
        if (raw is String) cookedAt = DateTime.tryParse(raw);
        if (cookedAt == null) continue;
        final img = (data['recipe_image'] ?? '').toString();
        final cooked = _dateOnly(cookedAt);
        if (!cooked.isBefore(_dateOnly(mondayThisWeek)) &&
            !cooked.isAfter(_dateOnly(sundayThisWeek))) {
          final cur = thisWeek[name];
          thisWeek[name] = _NameCountWithImage(
            name: name,
            count: (cur?.count ?? 0) + 1,
            imageUrl: (cur?.imageUrl?.isNotEmpty ?? false)
                ? cur!.imageUrl
                : (img.isNotEmpty ? img : null),
          );
        } else if (!cooked.isBefore(_dateOnly(mondayPrevWeek)) &&
            !cooked.isAfter(_dateOnly(sundayPrevWeek))) {
          final cur = lastWeek[name];
          lastWeek[name] = _NameCountWithImage(
            name: name,
            count: (cur?.count ?? 0) + 1,
            imageUrl: (cur?.imageUrl?.isNotEmpty ?? false)
                ? cur!.imageUrl
                : (img.isNotEmpty ? img : null),
          );
        }
      }

      List<_NameCountWithImage> _topN(Map<String, _NameCountWithImage> m) {
        final list = m.values.toList();
        list.sort((a, b) => b.count.compareTo(a.count));
        return list.take(5).toList(growable: false);
      }

      final topMenusThisWeek = _topN(thisWeek);
      final topMenusLastWeek = _topN(lastWeek);

      return _DashboardData(
        // แสดงจำนวนเฉพาะที่ยังไม่หมดอายุ
        totalItems: activeItems.length,
        totalQuantity: totalQuantity,
        expiringSoonCount: expiringSoonCount,
        expiredCount: expiredCount,
        expiringTodayItems: expiringTodayItems,
        nearestExpiryItem: nearestExpiryItem,
        weeklyCooking: weeklyUsage,
        categoryCounts: counts, // <- เพิ่ม
        categoryLatestAdded: latestAdded,
        topCategory: topCategory, // <- เพิ่ม
        topUsed: topUsedList,
        topDiscarded: topDiscardedList,
        wastedByCategory: wastedByCategory,
        pctUseBeforeExpiryThisMonth: pctThisMonth,
        pctUseBeforeExpiryPrevMonth: pctPrevMonth,
        pctWasteThisMonth: pctWasteThisMonth,
        pctWastePrevMonth: pctWastePrevMonth,
        topMenusThisWeek: topMenusThisWeek,
        topMenusLastWeek: topMenusLastWeek,
        monthWeekdayUsage: monthWeekdayUsage,
        monthCategoryUsage: monthCategoryUsage,
        wastedCount30: wastedCount30,
        dailyNutrition: dailyNutritionLimited,
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
    await _initNotificationStream();
  }

  Future<void> _initNotificationStream() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _notificationsStream = null);
      }
      return;
    }

    try {
      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      final data = userDoc.data();
      final rawFamilyId =
          (data?['familyId'] ?? data?['family_id']) as String?;
      final fid = rawFamilyId != null && rawFamilyId.trim().isNotEmpty
          ? rawFamilyId.trim()
          : null;

      CollectionReference<Map<String, dynamic>> baseCollection;
      if (fid != null) {
        baseCollection = _firestore
            .collection('notifications')
            .doc(fid)
            .collection('items');
      } else {
        baseCollection = _firestore
            .collection('user_notifications')
            .doc(user.uid)
            .collection('items');
      }

      final stream =
          baseCollection.where('type', isEqualTo: 'expiry').snapshots();
      if (!mounted) return;
      setState(() => _notificationsStream = stream);
    } catch (_) {
      final fallback = _firestore
          .collection('user_notifications')
          .doc(user.uid)
          .collection('items')
          .where('type', isEqualTo: 'expiry')
          .snapshots();
      if (!mounted) return;
      setState(() => _notificationsStream = fallback);
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _rawSub?.cancel();
    _cookSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  String? _extractUsernameFromData(Map<String, dynamic> data) {
    String? name = (data['username'] as String?)?.trim();
    name ??= (data['firstName'] as String?)?.trim();
    name ??= (data['fullName'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      final u = _auth.currentUser;
      if (u != null) {
        final display = (u.displayName ?? '').trim();
        if (display.isNotEmpty) return display;
        final email = u.email ?? '';
        if (email.contains('@')) return email.split('@').first;
      }
    }
    return name;
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
                final name = _usernameLive ?? (snap.data ?? 'ผู้ใช้');
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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _notificationsStream,
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final now = DateTime.now();
              final todayOnly = DateTime(now.year, now.month, now.day);

              int? resolveDaysLeft(Map<String, dynamic> data) {
                final raw = (data['daysLeft'] as num?)?.toInt();
                if (raw != null) return raw;
                final expiryRaw = data['expiresOn'];
                DateTime? expiry;
                if (expiryRaw is Timestamp) {
                  expiry = expiryRaw.toDate();
                } else if (expiryRaw is DateTime) {
                  expiry = expiryRaw;
                }
                if (expiry == null) return null;
                final onlyExpiry =
                    DateTime(expiry.year, expiry.month, expiry.day);
                return onlyExpiry.difference(todayOnly).inDays;
              }

              var count = 0;
              for (final doc in docs) {
                final data = doc.data();
                if ((data['type'] ?? '') != 'expiry') continue;
                final dl = resolveDaysLeft(data);
                if (dl != null && dl >= 0 && dl <= 3) {
                  count++;
                }
              }

              final badgeText = count > 99 ? '99+' : '$count';
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsCenterScreen(),
                        ),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            badgeText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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
                  child: !_aiInsightEnabled
                      ? _buildDashboardListView(
                          context,
                          data,
                          insightsEnabled: false,
                          insightsLoading: false,
                          insightsBySection:
                              const <String, List<_DashboardInsightEntry>>{},
                        )
                      : FutureBuilder<List<_DashboardInsightEntry>>(
                          future: _usernameFuture.then(
                            (name) => _generateSmartInsights(name, data),
                          ),
                          builder: (context, insightSnap) {
                            final loading =
                                insightSnap.connectionState ==
                                ConnectionState.waiting;
                            final entries =
                                insightSnap.data ??
                                const <_DashboardInsightEntry>[];
                            if (insightSnap.hasError && entries.isEmpty) {
                              debugPrint(
                                'Smart Insight error: ${insightSnap.error}',
                              );
                            }
                            final grouped = _groupInsightsBySection(entries);
                            return _buildDashboardListView(
                              context,
                              data,
                              insightsEnabled: true,
                              insightsLoading: loading,
                              insightsBySection: grouped,
                            );
                          },
                        ),
                );
              },
            ),
    );
  }

  Widget _buildDashboardListView(
    BuildContext context,
    _DashboardData data, {
    required bool insightsEnabled,
    required bool insightsLoading,
    required Map<String, List<_DashboardInsightEntry>> insightsBySection,
  }) {
    final cs = Theme.of(context).colorScheme;
    final summaryEntries =
        insightsBySection['summary'] ?? const <_DashboardInsightEntry>[];
    final expiringEntries =
        insightsBySection['expiring_today'] ?? const <_DashboardInsightEntry>[];
    final weeklyEntries =
        insightsBySection['weekly_cooking'] ?? const <_DashboardInsightEntry>[];
    final topIngredientEntries =
        insightsBySection['top_ingredients'] ??
        const <_DashboardInsightEntry>[];
    final useBeforeEntries =
        insightsBySection['use_before_expiry'] ??
        const <_DashboardInsightEntry>[];
    final topMenusEntries =
        insightsBySection['top_menus'] ?? const <_DashboardInsightEntry>[];
    final inventoryEntries =
        insightsBySection['inventory_summary'] ??
        const <_DashboardInsightEntry>[];
    final dailyNutritionEntries =
        insightsBySection['daily_nutrition'] ??
        const <_DashboardInsightEntry>[];

    final children = <Widget>[];
    if (insightsEnabled) {
      children.add(
        _buildInsightSummaryCard(cs, insightsLoading, summaryEntries),
      );
      children.add(const SizedBox(height: 16));
    }

    children.add(_buildExpiringTodayBlock(context, data, expiringEntries));
    children.add(const SizedBox(height: 24));
    children.add(
      _buildDailyNutritionSection(
        context,
        data,
        insights: dailyNutritionEntries,
      ),
    );
    children.add(const SizedBox(height: 24));
    children.add(_buildMenuIdeasSection(context));
    children.add(const SizedBox(height: 24));
    children.add(
      _buildInventorySummaryBlock(context, data, insights: inventoryEntries),
    );
    children.add(const SizedBox(height: 24));
    children.add(
      _buildTopIngredientsSection(
        context,
        data,
        insights: topIngredientEntries,
      ),
    );
    children.add(const SizedBox(height: 24));
    children.add(
      _buildUseBeforeExpiryMoM(context, data, insights: useBeforeEntries),
    );
    children.add(const SizedBox(height: 24));
    children.add(
      _buildTopMenusWeekVsWeek(context, data, insights: topMenusEntries),
    );
    children.add(const SizedBox(height: 24));
    children.add(_buildWeeklySection(context, data, insights: weeklyEntries));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Map<String, List<_DashboardInsightEntry>> _groupInsightsBySection(
    List<_DashboardInsightEntry> entries,
  ) {
    final map = <String, List<_DashboardInsightEntry>>{};
    for (final entry in entries) {
      map.putIfAbsent(entry.section, () => []).add(entry);
    }
    return map;
  }

  Widget _buildInsightSummaryCard(
    ColorScheme cs,
    bool loading,
    List<_DashboardInsightEntry> entries,
  ) {
    if (loading && entries.isEmpty) {
      return Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text(
            'กำลังวิเคราะห์ข้อมูลล่าสุด...',
            style: TextStyle(color: cs.onSurface.withAlpha(170)),
          ),
        ],
      );
    }

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInsightMessageList(
      cs,
      entries,
      background: cs.surfaceVariant.withAlpha(110),
      borderColor: cs.outline.withAlpha(80),
    );
  }

  Widget _buildInsightMessageList(
    ColorScheme cs,
    List<_DashboardInsightEntry> entries, {
    Color? background,
    Color? borderColor,
  }) {
    final bg = background ?? cs.surfaceVariant.withAlpha(110);
    final border = borderColor ?? cs.outline.withAlpha(90);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entries[i].title.isNotEmpty)
                  Text(
                    entries[i].title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                if (entries[i].title.isNotEmpty) const SizedBox(height: 6),
                Text(
                  entries[i].message,
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(210),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (i < entries.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildExpiringTodayBlock(
    BuildContext context,
    _DashboardData data,
    List<_DashboardInsightEntry> insights,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
        ExpiringTodaySection(items: data.expiringTodayItems),
      ],
    );
  }

  Widget _buildInventorySummaryBlock(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
        InventorySummarySection(
          totalItems: data.totalItems,
          counts: data.categoryCounts,
          latestAdded: data.categoryLatestAdded,
          topCategory: data.topCategory,
        ),
      ],
    );
  }

  Widget _buildTopIngredientsSection(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TopBarsCard(
                title: _tTopUsed,
                items: data.topUsed,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TopBarsCard(
                title: _tTopDiscarded,
                items: data.topDiscarded,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyNutritionSection(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    final entries = data.dailyNutrition;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (insights.isNotEmpty) ...[
            _buildInsightMessageList(
              cs,
              insights,
              background: cs.surfaceVariant.withAlpha(120),
              borderColor: cs.outline.withAlpha(90),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'โภชนาการต่อวัน (7 วันล่าสุด)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'ยังไม่มีข้อมูลโภชนาการในช่วงนี้',
              style: TextStyle(color: cs.onSurface.withAlpha(170)),
            )
          else
            SizedBox(
              height: 200,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.8),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final item = entries[index];
                  final totals = item.totals;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.outline.withAlpha(60)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(14),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatThaiShortDate(item.date),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: DefaultTextStyle(
                                style: TextStyle(color: cs.onSurface),
                                child: Table(
                                  columnWidths: const {
                                    0: FlexColumnWidth(),
                                    1: FlexColumnWidth(),
                                  },
                                  defaultVerticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  children: [
                                    TableRow(
                                      children: [
                                        _NutritionTableCell(
                                          label: 'พลังงาน',
                                          value:
                                              '${totals.calories.toStringAsFixed(0)} kcal',
                                        ),
                                        _NutritionTableCell(
                                          label: 'โปรตีน',
                                          value:
                                              '${totals.protein.toStringAsFixed(1)} g',
                                        ),
                                      ],
                                    ),
                                    TableRow(
                                      children: [
                                        _NutritionTableCell(
                                          label: 'คาร์โบไฮเดรต',
                                          value:
                                              '${totals.carbs.toStringAsFixed(1)} g',
                                        ),
                                        _NutritionTableCell(
                                          label: 'ไขมัน',
                                          value:
                                              '${totals.fat.toStringAsFixed(1)} g',
                                        ),
                                      ],
                                    ),
                                    TableRow(
                                      children: [
                                        _NutritionTableCell(
                                          label: 'ไฟเบอร์',
                                          value:
                                              '${totals.fiber.toStringAsFixed(1)} g',
                                        ),
                                        _NutritionTableCell(
                                          label: 'โซเดียม',
                                          value:
                                              '${totals.sodium.toStringAsFixed(0)} mg',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUseBeforeExpiryMoM(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    final pNow = data.pctUseBeforeExpiryThisMonth;
    final pPrev = data.pctUseBeforeExpiryPrevMonth;
    final wNow = data.pctWasteThisMonth;
    final wPrev = data.pctWastePrevMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withAlpha(76)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_tUseBeforeExpiry ($_tThisMonth vs $_tLastMonth)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _LabeledProgress(
                label: 'วัตถุดิบถูกใช้ก่อนหมดอายุ',
                percent: pNow,
                previous: pPrev,
                color: cs.primary,
                higherIsBetter: true,
              ),
              const SizedBox(height: 16),
              _LabeledProgress(
                label: 'วัตถุดิบถูกทิ้ง',
                percent: wNow,
                previous: wPrev,
                color: cs.error,
                higherIsBetter: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopMenusWeekVsWeek(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MenuBarListCard(
                title: _tMenuThisWeek,
                items: data.topMenusThisWeek,
                barColor: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MenuBarListCard(
                title: _tMenuLastWeek,
                items: data.topMenusLastWeek,
                barColor: cs.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeeklySection(
    BuildContext context,
    _DashboardData data, {
    List<_DashboardInsightEntry> insights = const <_DashboardInsightEntry>[],
  }) {
    final cs = Theme.of(context).colorScheme;
    final totalServings = data.weeklyCooking.fold<int>(
      0,
      (acc, d) => acc + d.count,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.isNotEmpty) ...[
          _buildInsightMessageList(
            cs,
            insights,
            background: cs.surfaceVariant.withAlpha(120),
            borderColor: cs.outline.withAlpha(90),
          ),
          const SizedBox(height: 12),
        ],
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
    return Consumer<EnhancedRecommendationProvider>(
      builder: (context, provider, _) {
        final recs = provider.recommendations;
        final isLoading = provider.isLoading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _tMenuIdeas,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RecommendationPage(),
                            ),
                          );
                        },
                  child: Text(
                    'ขอเมนูใหม่',
                    style: TextStyle(color: cs.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLoading && recs.isEmpty) ...[
              _buildMenuPlaceholderCard(
                context,
                title: 'กำลังหาเมนูที่เหมาะกับคุณ',
                subtitle: 'AI + API กำลังวิเคราะห์จากวัตถุดิบที่มี',
              ),
            ] else if (recs.isEmpty) ...[
              _buildMenuPlaceholderCard(
                context,
                title: 'ยังไม่มีเมนูแนะนำ',
                subtitle: 'แตะ “ขอเมนูใหม่” เพื่อเริ่มแนะนำ',
              ),
            ] else ...[
              SizedBox(
                height: 320,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recs.length.clamp(0, 10),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final r = recs[i];
                    return SizedBox(
                      width: MediaQuery.of(context).size.width * 0.78,
                      child: RecipeCard(
                        recipe: r,
                        showSourceBadge: true,
                        compact: true,
                        onTap: () => _openRecipeDetail(context, r),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _openRecipeDetail(BuildContext context, recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EnhancedRecipeDetailSheet(recipe: recipe),
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
    const maxBarHeight = 120.0;
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

class _DashboardInsightEntry {
  const _DashboardInsightEntry({
    required this.section,
    required this.title,
    required this.message,
  });

  final String section;
  final String title;
  final String message;
}

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
    required this.categoryLatestAdded,
    required this.topCategory, // <- เพิ่ม
    required this.topUsed,
    required this.topDiscarded,
    required this.wastedByCategory,
    required this.pctUseBeforeExpiryThisMonth,
    required this.pctUseBeforeExpiryPrevMonth,
    required this.pctWasteThisMonth,
    required this.pctWastePrevMonth,
    required this.topMenusThisWeek,
    required this.topMenusLastWeek,
    required this.monthWeekdayUsage,
    required this.monthCategoryUsage,
    required this.wastedCount30,
    required this.dailyNutrition,
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
      categoryLatestAdded: const {},
      topCategory: null, // <- เพิ่ม
      topUsed: const [],
      topDiscarded: const [],
      wastedByCategory: const {},
      pctUseBeforeExpiryThisMonth: 0,
      pctUseBeforeExpiryPrevMonth: 0,
      pctWasteThisMonth: 0,
      pctWastePrevMonth: 0,
      topMenusThisWeek: const [],
      topMenusLastWeek: const [],
      monthWeekdayUsage: const {},
      monthCategoryUsage: const {},
      wastedCount30: 0,
      dailyNutrition: const [],
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
  final Map<String, DateTime?> categoryLatestAdded;
  final String? topCategory; // <- เพิ่ม
  final List<_NameCount> topUsed;
  final List<_NameCount> topDiscarded;
  final Map<String, int> wastedByCategory;
  final double pctUseBeforeExpiryThisMonth;
  final double pctUseBeforeExpiryPrevMonth;
  final double pctWasteThisMonth;
  final double pctWastePrevMonth;
  final List<_NameCountWithImage> topMenusThisWeek;
  final List<_NameCountWithImage> topMenusLastWeek;
  final Map<int, int> monthWeekdayUsage; // 1..7 → count
  final Map<String, int> monthCategoryUsage; // category → usage count
  final int wastedCount30;
  final List<_DailyNutrition> dailyNutrition;

  bool get hasCookingData => weeklyCooking.any((d) => d.count > 0);
  bool get hasExpiringToday => expiringTodayItems.isNotEmpty;
}

class _DailyUsage {
  _DailyUsage({required this.date});
  final DateTime date;
  int count = 0;
}

class _DailyNutrition {
  _DailyNutrition({required this.date, required this.totals});
  final DateTime date;
  final _NutritionTotals totals;
}

class _NutritionTotals {
  double calories = 0;
  double protein = 0;
  double carbs = 0;
  double fat = 0;
  double fiber = 0;
  double sodium = 0;

  void add(NutritionInfo info) {
    calories += info.calories;
    protein += info.protein;
    carbs += info.carbs;
    fat += info.fat;
    fiber += info.fiber;
    sodium += info.sodium;
  }
}

class _NameCount {
  const _NameCount({required this.name, required this.count});
  final String name;
  final int count;
}

class _NameCountWithImage {
  const _NameCountWithImage({
    required this.name,
    required this.count,
    this.imageUrl,
  });
  final String name;
  final int count;
  final String? imageUrl;
}

class _TopBarsCard extends StatelessWidget {
  const _TopBarsCard({
    required this.title,
    required this.items,
    required this.color,
  });

  final String title;
  final List<_NameCount> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxValue = items.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(76)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'ยังไม่มีข้อมูล',
              style: TextStyle(color: cs.onSurface.withAlpha(178)),
            )
          else
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final it in items)
                    _TopBar(
                      label: it.name,
                      value: it.count,
                      maxValue: maxValue,
                      color: color,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const minBarHeight = 8.0;
    const nominalMaxBarHeight = 140.0;
    const topTextH = 16.0;
    const bottomTextH = 16.0;
    const spacingSum = 6.0 + 8.0; // between value, bar, and label
    final shortLabel = label.length <= 6 ? label : label.substring(0, 6) + '…';

    return Flexible(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : (topTextH + spacingSum + nominalMaxBarHeight + bottomTextH);
          final maxBarH = (maxH - topTextH - bottomTextH - spacingSum).clamp(
            40.0,
            nominalMaxBarHeight,
          );
          final computedBar = maxValue == 0
              ? minBarHeight
              : ((value / (maxValue == 0 ? 1 : maxValue)) *
                        (maxBarH - minBarHeight)) +
                    minBarHeight;
          final barHeight = computedBar.clamp(minBarHeight, maxBarH);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: topTextH,
                child: Center(
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withAlpha(204),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 18,
                height: barHeight,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: bottomTextH,
                child: Tooltip(
                  message: label,
                  child: Center(
                    child: Text(
                      shortLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withAlpha(178),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -------- Pie card for wasted-by-category --------
class _PieCard extends StatelessWidget {
  const _PieCard({required this.entries});
  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = entries.fold<int>(0, (acc, e) => acc + e.value);
    final colors = _palette(cs);
    final slices = <_MiniSlice>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      slices.add(
        _MiniSlice(
          label: e.key,
          value: e.value.toDouble(),
          color: colors[i % colors.length],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(painter: _MiniPiePainter(slices)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        _pct(s.value, total),
                        style: TextStyle(color: cs.onSurface.withAlpha(170)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Color> _palette(ColorScheme cs) => [
    cs.primary,
    cs.secondary,
    cs.tertiary,
    cs.primaryContainer,
    cs.secondaryContainer,
    cs.tertiaryContainer,
  ];

  String _pct(double v, int total) {
    if (total <= 0) return '0%';
    final p = (v / total * 100);
    return '${p.toStringAsFixed(p >= 10 ? 0 : 1)}%';
  }
}

class _MiniSlice {
  final String label;
  final double value;
  final Color color;
  _MiniSlice({required this.label, required this.value, required this.color});
}

class _MiniPiePainter extends CustomPainter {
  _MiniPiePainter(this.slices);
  final List<_MiniSlice> slices;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    final total = slices.fold<double>(0, (acc, s) => acc + s.value);
    if (total <= 0) return;
    double start = -3.14159 / 2;
    for (final s in slices) {
      final sweep = (s.value / total) * 6.28318;
      paint.color = s.color;
      canvas.drawArc(rect.deflate(8), start, sweep, true, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPiePainter oldDelegate) => false;
}

class _LabeledProgress extends StatelessWidget {
  const _LabeledProgress({
    required this.label,
    required this.percent,
    required this.previous,
    required this.color,
    required this.higherIsBetter,
  });
  final String label;
  final double percent; // 0..1
  final double previous; // 0..1
  final Color color;
  final bool higherIsBetter;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = percent.clamp(0.0, 1.0);
    final prev = previous.clamp(0.0, 1.0);
    final delta = (v - prev) * 100;
    final arrowIcon = delta >= 0 ? Icons.trending_up : Icons.trending_down;
    final improved = higherIsBetter ? delta >= 0 : delta <= 0;
    final arrowColor = improved ? Colors.green : Colors.redAccent;
    final deltaStr =
        (delta >= 0
            ? '+${delta.toStringAsFixed(1)}'
            : delta.toStringAsFixed(1)) +
        '%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${(v * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'เดือนก่อน ${(prev * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: cs.onSurface.withAlpha(170),
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                Icon(arrowIcon, color: arrowColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  deltaStr,
                  style: TextStyle(
                    color: arrowColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: v,
            color: color,
            backgroundColor: cs.surfaceContainerHighest.withAlpha(60),
          ),
        ),
      ],
    );
  }
}

class _NutritionTableCell extends StatelessWidget {
  const _NutritionTableCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withAlpha(210),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuBarListCard extends StatelessWidget {
  const _MenuBarListCard({
    required this.title,
    required this.items,
    required this.barColor,
  });
  final String title;
  final List<_NameCountWithImage> items;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final limited = items.length > 5 ? items.take(5).toList() : items;
    final maxV = limited.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'ยังไม่มีข้อมูล',
              style: TextStyle(color: cs.onSurface.withAlpha(170)),
            )
          else
            ...limited
                .map(
                  (e) => _MenuRow(item: e, maxValue: maxV, barColor: barColor),
                )
                .toList(),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.maxValue,
    required this.barColor,
  });
  final _NameCountWithImage item;
  final int maxValue;
  final Color barColor;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = maxValue == 0 ? 0.0 : (item.count / maxValue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage:
                (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                ? NetworkImage(item.imageUrl!)
                : null,
            child: (item.imageUrl == null || item.imageUrl!.isEmpty)
                ? const Icon(Icons.restaurant_menu, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: fraction,
                    color: barColor,
                    backgroundColor: cs.surfaceContainerHighest.withAlpha(60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.count.toString(),
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

bool get _aiInsightEnabled {
  final v = (dotenv.env['AI_INSIGHT_ENABLED'] ?? 'true').trim().toLowerCase();
  return !(v == 'false' || v == '0' || v == 'off');
}
