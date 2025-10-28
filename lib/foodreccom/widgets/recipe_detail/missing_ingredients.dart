//lib/foodreccom/widgets/recipe_detail/missing_ingredients.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import 'package:my_app/foodreccom/models/purchase_item.dart';
import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/utils/purchase_item_utils.dart';
import '../../models/recipe/recipe.dart';

class MissingIngredientsSection extends StatefulWidget {
  final RecipeModel recipe;
  final int? servings;
  final VoidCallback? onAddToShoppingList;
  final Map<String, double>? manualRequiredAmounts;
  final List<ManualCustomIngredient>? manualCustomIngredients;
  const MissingIngredientsSection({
    super.key,
    required this.recipe,
    this.servings,
    this.onAddToShoppingList,
    this.manualRequiredAmounts,
    this.manualCustomIngredients,
  });

  @override
  State<MissingIngredientsSection> createState() =>
      _MissingIngredientsSectionState();
}

class _MissingIngredientsSectionState extends State<MissingIngredientsSection> {
  String _storeType =
      'ซูเปอร์มาร์เก็ต'; // 'ตลาดสด' | 'ซูเปอร์มาร์เก็ต' | 'โชห่วย'

  @override
  Widget build(BuildContext context) {
    final provider = context.read<EnhancedRecommendationProvider>();
    final inv = provider.ingredients;
    final computed = computePurchaseItems(
      widget.recipe,
      inv,
      servings: widget.servings,
      manualRequiredAmounts: widget.manualRequiredAmounts,
      manualCustomIngredients: widget.manualCustomIngredients,
    );
    final displayItems = computed
        .where((item) => item.missingAmount > 0.01)
        .toList(growable: false);
    if (displayItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart, color: Colors.orange[700], size: 18),
              const SizedBox(width: 6),
              Text(
                'วัตถุดิบที่ต้องซื้อ (${displayItems.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _storeSelector(),
          const SizedBox(height: 8),
          ...displayItems.map((item) => _ingredientRow(context, item)),
          const SizedBox(height: 8),
          _overallCostSummary(displayItems),
          if (widget.onAddToShoppingList != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  try {
                    final added = await provider.addPurchaseItemsToShoppingList(
                      displayItems,
                      recipe: widget.recipe,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('เพิ่มเข้ารายการซื้อของ $added รายการ'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('เพิ่มไม่สำเร็จ: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('เพิ่มเข้ารายการซื้อของ'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _storeSelector() {
    final chips = [
      ('ตลาดสด', Icons.storefront),
      ('ซูเปอร์มาร์เก็ต', Icons.local_mall_outlined),
      ('โชห่วย', Icons.local_convenience_store_outlined),
    ];
    return Wrap(
      spacing: 8,
      children: chips
          .map(
            (e) => ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(e.$2, size: 16),
                  const SizedBox(width: 6),
                  Text(e.$1),
                ],
              ),
              selected: _storeType == e.$1,
              onSelected: (_) => setState(() => _storeType = e.$1),
            ),
          )
          .toList(),
    );
  }

  Widget _ingredientRow(BuildContext context, PurchaseItem item) {
    final qtyText = formatQuantityNumber(
      item.quantity,
      unit: item.unit,
      ingredientName: item.name,
    );
    final unitText = item.unit.trim().isEmpty
        ? qtyText
        : '$qtyText ${item.unit}';
    final priceText = '฿${_estimateItemCost(item).toStringAsFixed(0)}';
    final category = item.category ?? guessCategory(item.name);
    final store = _selectedStoreForCategory(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 16,
                color: Colors.orange[600],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(color: Colors.orange[800]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unitText,
                style: TextStyle(
                  color: Colors.orange[900],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                priceText,
                style: TextStyle(
                  color: Colors.orange[900],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (item.consumptionFrequency != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FrequencyBadge(frequency: item.consumptionFrequency!),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.frequencyReason?.trim().isNotEmpty == true
                          ? item.frequencyReason!.trim()
                          : 'ยังไม่มีเหตุผลประกอบสำหรับวัตถุดิบนี้',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => _openMap(context, store.$2),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: Text('เปิดแผนที่ร้าน ${store.$1}'),
          ),
        ],
      ),
    );
  }

  // ---- Cost estimation helpers ----
  double _estimateItemCost(PurchaseItem it) {
    final cat = it.category ?? guessCategory(it.name);
    final canon = toCanonicalQuantity(it.quantity.toDouble(), it.unit, it.name);
    final price = _pricePerUnit(cat, canon.unit);
    final m = _storeMultiplier(cat);
    return canon.amount * price * m;
  }

  double _groupCost(List<PurchaseItem> items) =>
      items.fold(0.0, (sum, it) => sum + _estimateItemCost(it));

  Widget _overallCostSummary(List<PurchaseItem> items) {
    final grouped = <String, List<PurchaseItem>>{};
    for (final item in items) {
      final cat = item.category ?? guessCategory(item.name);
      grouped.putIfAbsent(cat, () => []).add(item);
    }
    final total = grouped.values.fold<double>(
      0.0,
      (s, list) => s + _groupCost(list),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.blueGrey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ประมาณการค่าใช้จ่ายรวม',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey[800],
                  ),
                ),
              ),
              Text(
                '฿${total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openMultiStopRoute(grouped),
              icon: const Icon(Icons.alt_route),
              label: const Text('วางแผนเส้นทางซื้อของ'),
            ),
          ),
        ],
      ),
    );
  }

  double _pricePerUnit(String category, String canonUnit) {
    // canonUnit: 'gram'|'milliliter'|'piece'
    if (category == 'เนื้อสัตว์') return canonUnit == 'gram' ? 0.6 : 15;
    if (category == 'ผัก') return canonUnit == 'gram' ? 0.08 : 10;
    if (category == 'ผลไม้') return canonUnit == 'gram' ? 0.1 : 12;
    if (category == 'ผลิตภัณฑ์จากนม')
      return canonUnit == 'milliliter' ? 0.04 : 20;
    if (category == 'ข้าว' || category == 'แป้ง')
      return canonUnit == 'gram' ? 0.03 : 15;
    if (category == 'เครื่องเทศ') return canonUnit == 'gram' ? 0.2 : 20;
    if (category == 'เครื่องปรุง') return canonUnit == 'milliliter' ? 0.02 : 15;
    if (category == 'น้ำมัน') return canonUnit == 'milliliter' ? 0.05 : 25;
    if (category == 'เครื่องดื่ม') return 25; // per piece
    if (category == 'ของแช่แข็ง') return 50; // per piece
    return canonUnit == 'gram' ? 0.03 : 15; // default
  }

  double _storeMultiplier(String category) {
    // Adjust prices based on selected store
    switch (_storeType) {
      case 'ตลาดสด':
        if (category == 'ผัก') return 0.8;
        if (category == 'ผลไม้') return 0.85;
        if (category == 'เนื้อสัตว์') return 0.9;
        return 0.95;
      case 'โชห่วย':
        if (category == 'เนื้อสัตว์') return 1.1;
        if (category == 'ผัก' || category == 'ผลไม้') return 1.15;
        return 1.2;
      default: // ซูเปอร์มาร์เก็ต
        return 1.0;
    }
  }

  (String, String) _storeForCategory(String category) {
    switch (category) {
      case 'ผัก':
      case 'ผลไม้':
        return ('ตลาดสด', 'ตลาดสด ใกล้ฉัน');
      case 'เนื้อสัตว์':
        return ('ร้านขายเนื้อ', 'ร้านขายเนื้อ ใกล้ฉัน');
      case 'ผลิตภัณฑ์จากนม':
      case 'เครื่องปรุง':
      case 'แป้ง':
      case 'ข้าว':
      case 'น้ำมัน':
      case 'ของแช่แข็ง':
      case 'เครื่องดื่ม':
        return ('ซูเปอร์มาร์เก็ต', 'ซูเปอร์มาร์เก็ต ใกล้ฉัน');
      default:
        return ('มินิมาร์ท', 'มินิมาร์ท ใกล้ฉัน');
    }
  }

  (String, String) _selectedStoreForCategory(String category) {
    // If user selects a store type explicitly, use it for maps
    if (_storeType == 'ตลาดสด') return ('ตลาดสด', 'ตลาดสด ใกล้ฉัน');
    if (_storeType == 'ซูเปอร์มาร์เก็ต')
      return ('ซูเปอร์มาร์เก็ต', 'ซูเปอร์มาร์เก็ต ใกล้ฉัน');
    if (_storeType == 'โชห่วย') return ('มินิมาร์ท', 'มินิมาร์ท ใกล้ฉัน');
    return _storeForCategory(category);
  }

  Future<void> _openMap(BuildContext context, String query) async {
    final candidates = <String>[
      // Try Maps app schemes first
      'geo:0,0?q=$query',
      'google.navigation:q=$query',
      // Fallback to HTTPS search
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    ];
    for (final u in candidates) {
      final uri = Uri.parse(u);
      if (await _openFlexible(uri)) return;
    }
    // Last resort: show a hint
    _showSnack(
      context,
      'ไม่พบแอปสำหรับเปิดแผนที่ กรุณาติดตั้ง Google Maps หรือเบราว์เซอร์',
    );
  }

  Future<void> _openMultiStopRoute(
    Map<String, List<PurchaseItem>> grouped,
  ) async {
    final cats = grouped.keys.toSet();
    final queue = <String>[];
    void addIfHas(String c) {
      if (cats.contains(c)) queue.add(_storeForCategory(c).$2);
    }

    addIfHas('ผัก');
    addIfHas('ผลไม้');
    addIfHas('เนื้อสัตว์');
    const superCats = [
      'ผลิตภัณฑ์จากนม',
      'เครื่องปรุง',
      'แป้ง',
      'ข้าว',
      'น้ำมัน',
      'ของแช่แข็ง',
      'เครื่องดื่ม',
    ];
    if (cats.any(superCats.contains)) {
      queue.add(_storeForCategory('ซูเปอร์มาร์เก็ต').$2);
    }
    for (final c in cats) {
      if (!['ผัก', 'ผลไม้', 'เนื้อสัตว์', ...superCats].contains(c)) {
        queue.add(_storeForCategory(c).$2);
      }
    }
    // dedup
    final seen = <String>{};
    final stops = <String>[];
    for (final q in queue) {
      if (seen.add(q)) stops.add(q);
    }
    if (stops.isEmpty) return;
    final dest = stops.first;
    final way = stops.skip(1).toList();
    final base = StringBuffer('https://www.google.com/maps/dir/?api=1');
    base.write('&destination=${Uri.encodeComponent(dest)}');
    if (way.isNotEmpty) {
      base.write('&waypoints=${Uri.encodeComponent(way.join('|'))}');
    }
    base.write('&travelmode=driving');
    final uri = Uri.parse(base.toString());
    if (await _openFlexible(uri)) return;
    // Fallback: เปิดจุดแรกในโหมดค้นหาแทน
    if (stops.isNotEmpty) {
      await _openMap(context, stops.first);
    } else {
      _showSnack(context, 'ไม่สามารถเปิดเส้นทางได้');
    }
  }

  Future<bool> _openFlexible(Uri uri) async {
    // Try external app/browser
    try {
      if (await canLaunchUrl(uri)) {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication))
          return true;
      }
    } catch (_) {}
    // Try platform default
    try {
      if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return true;
    } catch (_) {}
    // Try in-app browser view
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
    } catch (_) {}
    return false;
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _FrequencyBadge extends StatelessWidget {
  final ConsumptionFrequency frequency;

  const _FrequencyBadge({required this.frequency});

  @override
  Widget build(BuildContext context) {
    final color = _colorForFrequency(frequency);
    final label = _labelForFrequency(frequency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  MaterialColor _colorForFrequency(ConsumptionFrequency frequency) {
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

  String _labelForFrequency(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return 'ทานได้ทุกวัน';
      case ConsumptionFrequency.oncePerDay:
        return 'วันละครั้ง';
      case ConsumptionFrequency.weekly:
        return 'สัปดาห์ละครั้ง';
      case ConsumptionFrequency.occasional:
        return 'ทานนานๆ ครั้ง';
    }
  }
}
