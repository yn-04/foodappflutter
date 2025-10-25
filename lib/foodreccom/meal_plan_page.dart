import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/common/thai_number_format.dart' as fmt;
import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import 'models/meal_plan.dart';
import 'models/recipe/recipe.dart';
import 'models/recipe/nutrition_info.dart';
import 'providers/enhanced_recommendation_provider.dart';
import 'providers/meal_plan_provider.dart';
import 'meal_plan_list_page.dart';
import 'services/cooking_service.dart';
import 'widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';

class MealPlanPage extends StatefulWidget {
  const MealPlanPage({super.key});
  @override
  State<MealPlanPage> createState() => _MealPlanPageState();
}

class _MealPlanPageState extends State<MealPlanPage> {
  bool _loading = true;
  String? _error;
  final CookingService _cookingService = CookingService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = context.read<EnhancedRecommendationProvider>();
      final mp = context.read<MealPlanProvider>();
      await mp.generateWeeklyPlan(p);
    } catch (e) { setState(() => _error = e.toString()); }
    finally { setState(() => _loading = false); }
  }

  String _frequencySummaryText(Map<ConsumptionFrequency, int> counts) {
    final order = [
      ConsumptionFrequency.daily,
      ConsumptionFrequency.oncePerDay,
      ConsumptionFrequency.weekly,
      ConsumptionFrequency.occasional,
    ];
    final labels = {
      ConsumptionFrequency.daily: 'ทุกวัน',
      ConsumptionFrequency.oncePerDay: 'วันละครั้ง',
      ConsumptionFrequency.weekly: 'สัปดาห์ละครั้ง',
      ConsumptionFrequency.occasional: 'นานๆ ครั้ง',
    };
    final parts = <String>[];
    for (final freq in order) {
      final count = counts[freq] ?? 0;
      if (count <= 0) continue;
      parts.add('${labels[freq]} ${count} เมนู');
    }
    return parts.isEmpty ? 'ยังไม่มีข้อมูลความถี่' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final recProvider = context.watch<EnhancedRecommendationProvider>();
    final mealPlanProvider = context.watch<MealPlanProvider>();
    final plan = mealPlanProvider.plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('📅 Meal Plan (7 วัน)'),
        actions: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : plan == null
                  ? const Center(child: Text('No plan'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: plan.days.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                        final summary =
                            mealPlanProvider.frequencySummary(recProvider.ingredients);
                        return _MealPlanSummaryCard(summary: summary);
                      }
                      final dayIndex = i - 1;
                      final d = plan.days[dayIndex];
                      final dayCounts = mealPlanProvider.dayFrequencyCounts(
                        d,
                        recProvider.ingredients,
                      );
                        final daySummary = mealPlanProvider.summaryFor(d.date);
                        final dayInsight = mealPlanProvider.insightFor(d.date);
                        final highRisk = (dayCounts[ConsumptionFrequency.weekly] ?? 0) +
                                (dayCounts[ConsumptionFrequency.occasional] ?? 0) >
                            1;
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'วันที่ ${_formatDate(d.date)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (highRisk)
                                        Row(
                                          children: [
                                            const Icon(Icons.warning_amber_rounded,
                                                color: Colors.deepOrange, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              'มื้อเสี่ยง ${dayCounts[ConsumptionFrequency.weekly] ?? 0 + (dayCounts[ConsumptionFrequency.occasional] ?? 0)}',
                                              style: const TextStyle(
                                                color: Colors.deepOrange,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                if (daySummary != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'โภชนาการรวมทั้งวัน',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.blueGrey[800],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        _DailyNutritionRow(summary: daySummary),
                                        const SizedBox(height: 6),
                                        Text(
                                          _frequencySummaryText(dayCounts),
                                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                        ),
                                        if (mealPlanProvider.isGeneratingInsights && dayInsight == null)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 6),
                                            child: SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        else if (dayInsight != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              dayInsight,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.teal[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                const Divider(height: 1),
                                ...List.generate(d.meals.length, (idx) {
                                  final e = d.meals[idx];
                                  final freqInfo = mealPlanProvider.mealFrequencyInfo(
                                    e,
                                    recProvider.ingredients,
                                  );
                                  final nearCount = _nearExpiryCount(context, e.recipe);
                                  final statusText = e.done ? 'ทำแล้ว' : 'ยังไม่ได้ทำ';
                                  final statusColor = e.done ? Colors.green : Colors.red;
                                  return ListTile(
                                    onTap: () => _openRecipeDetail(context, e.recipe),
                                    leading: Stack(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.blue[50],
                                          child: Text(
                                            _mealEmoji(idx),
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                        if (nearCount > 0)
                                          Positioned(
                                            right: -2,
                                            top: -2,
                                            child: CircleAvatar(
                                              radius: 8,
                                              backgroundColor: Colors.red,
                                              child: Text('$nearCount', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                            ),
                                          ),
                                      ],
                                    ),
                                    title: Text(e.recipe.name),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('มื้อ: ${_mealLabel(idx)}'),
                                        Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
                                        if (freqInfo.frequency != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _FrequencyChip(frequency: freqInfo.frequency!),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    freqInfo.reason ?? '',
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: 'ขอเมนูทางเลือก',
                                          icon: const Icon(Icons.sync_alt, color: Colors.blueGrey),
                                          onPressed: () => _swapMeal(context, d.date, idx),
                                        ),
                                        IconButton(
                                          tooltip: e.done ? 'ทำแล้ว' : 'ทำแล้ว',
                                          icon: Icon(
                                            Icons.check_circle,
                                            color: e.done ? Colors.green : Colors.redAccent,
                                          ),
                                          onPressed: e.done
                                              ? null
                                              : () => _markDone(context, d.date, idx, e),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading ? null : () => context.read<MealPlanProvider>().regenerateUnlocked(context.read<EnhancedRecommendationProvider>()),
                icon: const Icon(Icons.refresh),
                label: const Text('จัดแผนใหม่'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showShoppingList(context),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('รวมรายการซื้อสัปดาห์นี้'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  String _mealLabel(int idx) {
    switch (idx) {
      case 0:
        return 'เช้า';
      case 1:
        return 'กลางวัน';
      case 2:
        return 'เย็น';
      default:
        return 'มื้อ${idx + 1}';
    }
  }

  String _mealEmoji(int idx) {
    switch (idx) {
      case 0:
        return '☀️';
      case 1:
        return '🌤️';
      case 2:
        return '🌙';
      default:
        return '🍽️';
    }
  }

  // (ตั้งค่าถูกถอดออกแล้ว)

  void _showShoppingList(BuildContext context) {
    final mp = context.read<MealPlanProvider>();
    final rec = context.read<EnhancedRecommendationProvider>();
    final items = mp.consolidatedShoppingList(rec.ingredients);
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('รวมรายการซื้อของสัปดาห์นี้', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...items.map((it) => ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: Text('${it.name}'),
                trailing: Text('${it.quantity} ${it.unit}'),
              )),
        ],
      ),
    );
  }

  void _openRecipeDetail(BuildContext context, RecipeModel recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EnhancedRecipeDetailSheet(recipe: recipe),
    );
  }

  int _nearExpiryCount(BuildContext context, RecipeModel recipe) {
    final p = context.read<EnhancedRecommendationProvider>();
    final near = p.nearExpiryIngredients.map((i) => i.name.trim().toLowerCase()).toSet();
    int cnt = 0;
    for (final ing in recipe.ingredients) {
      final n = ing.name.trim().toLowerCase();
      if (near.contains(n)) cnt++;
    }
    return cnt;
  }

  Future<void> _markDone(BuildContext context, DateTime date, int mealIndex, MealPlanEntry entry) async {
    try {
      final rec = context.read<EnhancedRecommendationProvider>();
      final mp = context.read<MealPlanProvider>();
      final result = await _cookingService.startCooking(
        entry.recipe,
        entry.servings,
        allowPartial: true,
      );
      if (!result.success) {
        if (!mounted) return;
        final message = result.shortages.isNotEmpty
            ? 'วัตถุดิบไม่พอสำหรับเมนูนี้ (${result.shortages.first.name})'
            : 'ไม่สามารถอัปเดตสต็อกได้';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        return;
      }

      await rec.loadIngredients();
      mp.markEntryDoneAt(date, mealIndex);
      if (!mounted) return;
      final text = result.partial
          ? 'ทำเสร็จแบบบางส่วน อัปเดตสต็อกแล้ว'
          : 'อัปเดตสต็อกเรียบร้อย! พร้อมเสิร์ฟได้เลย';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')),
      );
    }
  }

}

Future<void> _swapMeal(
  BuildContext context,
  DateTime date,
  int mealIndex,
) async {
  final mp = context.read<MealPlanProvider>();
  final rec = context.read<EnhancedRecommendationProvider>();
  final success = await mp.swapMeal(date, mealIndex, rec);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        success ? 'ได้เมนูใหม่สำหรับมื้อนี้แล้ว' : 'ไม่พบเมนูทางเลือกที่เหมาะสม',
      ),
    ),
  );
}

class _WeeklyNutritionRow extends StatelessWidget {
  final NutritionInfo totals;
  final int dayCount;
  const _WeeklyNutritionRow({required this.totals, required this.dayCount});

  @override
  Widget build(BuildContext context) {
    final days = dayCount <= 0 ? 1 : dayCount;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _chip(
          '🔥',
          '${fmt.nf0.format(totals.calories)} kcal',
          '${fmt.nf0.format(totals.calories / days)} kcal/วัน',
        ),
        _chip(
          '🥩',
          '${fmt.nf1.format(totals.protein)} g โปรตีน',
          '${fmt.nf1.format(totals.protein / days)} g/วัน',
        ),
        _chip(
          '🍞',
          '${fmt.nf1.format(totals.carbs)} g คาร์บ',
          '${fmt.nf1.format(totals.carbs / days)} g/วัน',
        ),
        _chip(
          '🧈',
          '${fmt.nf1.format(totals.fat)} g ไขมัน',
          '${fmt.nf1.format(totals.fat / days)} g/วัน',
        ),
        _chip(
          '🌾',
          '${fmt.nf1.format(totals.fiber)} g ไฟเบอร์',
          '${fmt.nf1.format(totals.fiber / days)} g/วัน',
        ),
        _chip(
          '🧂',
          '${fmt.nf0.format(totals.sodium)} mg โซเดียม',
          '${fmt.nf0.format(totals.sodium / days)} mg/วัน',
        ),
      ],
    );
  }

  Widget _chip(String emoji, String total, String average) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$emoji $total',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'เฉลี่ย $average',
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}

class _MealPlanSummaryCard extends StatelessWidget {
  final MealPlanFrequencySummary summary;
  const _MealPlanSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MealPlanProvider>();
    final weeklyTotals = provider.weeklyTotals;
    final weeklyInsight = provider.weeklyInsight;
    final weeklyLoading = provider.isWeeklyInsightGenerating;
    final dayCount = summary.dayCount == 0 ? 1 : summary.dayCount;
    final colors = {
      ConsumptionFrequency.daily: Colors.green,
      ConsumptionFrequency.oncePerDay: Colors.amber,
      ConsumptionFrequency.weekly: Colors.deepOrange,
      ConsumptionFrequency.occasional: Colors.red,
    };
    final labels = {
      ConsumptionFrequency.daily: 'ทานได้ทุกวัน',
      ConsumptionFrequency.oncePerDay: 'วันละครั้ง',
      ConsumptionFrequency.weekly: 'สัปดาห์ละครั้ง',
      ConsumptionFrequency.occasional: 'ทานนานๆ ครั้ง',
    };
    final warningWeekly = (summary.counts[ConsumptionFrequency.weekly] ?? 0) > 4;
    final warningOccasional = (summary.counts[ConsumptionFrequency.occasional] ?? 0) > 2;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ภาพรวมโภชนาการประจำสัปดาห์',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (weeklyTotals != null) ...[
              const SizedBox(height: 12),
              _WeeklyNutritionRow(totals: weeklyTotals, dayCount: dayCount),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'ยังไม่มีข้อมูลโภชนาการรวมทั้งสัปดาห์',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            if (weeklyLoading && weeklyInsight == null) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ] else if (weeklyInsight != null) ...[
              const SizedBox(height: 12),
              Text(
                'Smart Insight รายสัปดาห์',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.teal[800],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                weeklyInsight!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.teal[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ConsumptionFrequency.values.map((freq) {
                final count = summary.counts[freq] ?? 0;
                final color = colors[freq]!;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[freq]!,
                        style: TextStyle(
                          color: color.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count มื้อ',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              weeklyTotals != null
                  ? 'พลังงานรวม ~ ${fmt.nf0.format(weeklyTotals.calories)} kcal | เฉลี่ยวันละ ${fmt.nf0.format(weeklyTotals.calories / dayCount)} kcal'
                  : 'พลังงานรวม ~ ${summary.totalCalories.toStringAsFixed(0)} kcal | เฉลี่ยวันละ ${summary.averageCaloriesPerDay.toStringAsFixed(0)} kcal',
              style: TextStyle(color: Colors.grey[800]),
            ),
            if (warningWeekly || warningOccasional) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.deepOrange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (warningWeekly)
                            'มีมื้อประเภท "สัปดาห์ละครั้ง" มากกว่า 4 มื้อ ลองพิจารณาสลับเมนูที่เบากว่านี้',
                          if (warningOccasional)
                            'มื้อ "ทานนานๆ ครั้ง" เกิน 2 มื้อ/สัปดาห์ ควรลดของทอดหรือของหวาน',
                        ].join('\n'),
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}


class _FrequencyChip extends StatelessWidget {
  final ConsumptionFrequency frequency;
  const _FrequencyChip({required this.frequency});

  @override
  Widget build(BuildContext context) {
    final color = _frequencyColor(frequency);
    final label = _frequencyLabel(frequency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  MaterialColor _frequencyColor(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return Colors.green;
      case ConsumptionFrequency.oncePerDay:
        return Colors.amber;
      case ConsumptionFrequency.weekly:
        return Colors.deepOrange;
      case ConsumptionFrequency.occasional:
        return Colors.red;
    }
  }

  String _frequencyLabel(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return 'ทุกวัน';
      case ConsumptionFrequency.oncePerDay:
        return 'วันละครั้ง';
      case ConsumptionFrequency.weekly:
        return 'สัปดาห์ละครั้ง';
      case ConsumptionFrequency.occasional:
        return 'นานๆ ครั้ง';
    }
  }
}

class _DailyNutritionRow extends StatelessWidget {
  final DailyNutritionSummary summary;
  const _DailyNutritionRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final totals = summary.totals;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _chip('🔥', '${fmt.nf0.format(totals.calories)} kcal'),
        _chip('🥩', '${fmt.nf1.format(totals.protein)} g โปรตีน'),
        _chip('🍞', '${fmt.nf1.format(totals.carbs)} g คาร์บ'),
        _chip('🧈', '${fmt.nf1.format(totals.fat)} g ไขมัน'),
        _chip('🌾', '${fmt.nf1.format(totals.fiber)} g ไฟเบอร์'),
        _chip('🧂', '${fmt.nf0.format(totals.sodium)} mg โซเดียม'),
      ],
    );
  }

  Widget _chip(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$emoji $text',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
