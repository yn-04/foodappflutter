import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/foodreccom/models/recipe/recipe.dart';
import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/widgets/recipe_card.dart';
import 'package:my_app/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';
import 'package:my_app/foodreccom/extensions/ui_extensions.dart';
import 'package:my_app/foodreccom/widgets/status_card.dart';
import 'package:my_app/foodreccom/widgets/add_user_recipe_sheet.dart';
import 'package:my_app/foodreccom/pages/cooking_history_page.dart';

class RecommendationPage extends StatefulWidget {
  const RecommendationPage({super.key});

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  static const List<Map<String, dynamic>> _ingredientPresets = [
    {
      'label': 'พื้นฐานครบ 3 มื้อ',
      'items': [
        'อกไก่',
        'หมูสับ',
        'ไข่ไก่',
        'ผักกาดขาว',
        'แครอท',
        'เห็ดฟาง',
        'คะน้า',
        'ข้าวหอมมะลิ',
        'เส้นหมี่',
        'น้ำปลา',
        'ซีอิ๊วขาว',
        'กระเทียม'
      ],
    },
    {
      'label': 'รักสุขภาพ/คุมแคล',
      'items': [
        'ปลาแซลมอน',
        'อกไก่งวง',
        'เต้าหู้แข็ง',
        'ไข่ขาว',
        'บร็อคโคลี',
        'มะเขือเทศเชอร์รี',
        'ผักโขม',
        'ฟักทอง',
        'ควินัว',
        'ข้าวกล้อง',
        'มันหวาน',
        'โยเกิร์ตไขมันต่ำ',
        'น้ำมันมะกอก'
      ],
    },
    {
      'label': 'อาหารไทยพร้อมทำ',
      'items': [
        'สะโพกไก่',
        'กุ้ง',
        'ปลาดอลลี่',
        'หมูสามชั้น',
        'ถั่วฝักยาว',
        'พริกชี้ฟ้า',
        'ใบมะกรูด',
        'มะเขือพวง',
        'โหระพา',
        'ข้าวเสาไห้',
        'เส้นใหญ่',
        'น้ำปลา',
        'น้ำตาลปี๊บ',
        'กะทิ',
        'น้ำพริกแกงเขียวหวาน'
      ],
    },
  ];

  int? _parseNumericInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              width: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.filter_list, color: Colors.black),
                onPressed: () => _showFilterSheet(context),
                tooltip: 'ตัวกรองเมนูอาหาร',
              ),
            ),
            const SizedBox(width: 8),
            '🍳 แนะนำเมนูอาหาร'.asText(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            onPressed: () async {
              final provider =
                  context.read<EnhancedRecommendationProvider>();
              if (provider.cookingHistory.isEmpty) {
                await provider.loadCookingHistory();
              }
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CookingHistoryPage(),
                ),
              );
            },
            tooltip: 'เมนูที่ทำไปแล้ว',
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks, color: Colors.black),
            tooltip: 'เมนูที่ฉันเพิ่มเอง',
            onPressed: _showUserRecipesMenu,
          ),
        ],
      ),
      body: Consumer<EnhancedRecommendationProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: provider.getHybridRecommendations,
            color: Colors.yellow[600],
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRecommendations(provider),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: Consumer<EnhancedRecommendationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) return const SizedBox();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'add_user_recipe',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AddUserRecipeSheet(),
                ),
                backgroundColor: Colors.green[400],
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'refresh_recs',
                onPressed: () {
                  provider.getHybridRecommendations();
                  context.showSnack(
                    '🤖 กำลังขอคำแนะนำใหม่ และแปลเป็นภาษาไทย...',
                    color: Colors.yellow[700]!,
                  );
                },
                backgroundColor: Colors.yellow[600],
                child: const Icon(Icons.refresh, color: Colors.black),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUserRecipesMenu() {
    final provider = context.read<EnhancedRecommendationProvider>();
    final recipes = provider.userRecommendations;
    if (recipes.isEmpty) {
      context.showSnack(
        'ยังไม่มีเมนูที่เพิ่มเอง',
        color: Colors.orangeAccent,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final maxHeight = MediaQuery.of(sheetCtx).size.height * 0.7;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    'เมนูที่ฉันเพิ่มเอง'.asText(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: recipes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final recipe = recipes[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.bookmark_added,
                          color: Colors.deepPurple,
                        ),
                        title: Text(recipe.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (!mounted) return;
                            _showRecipeDetail(recipe);
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendations(EnhancedRecommendationProvider provider) {
    if (provider.isLoading) {
      return const StatusCard.loading(
        title: '🤖 AI + API กำลังคิดเมนู...',
        subtitle: 'และกำลังแปลเป็นภาษาไทย 🇹🇭',
        color: Colors.yellow,
      );
    }

    final hasError = provider.error != null;
    final hybridRecipes = provider.hybridRecommendations;
    final hasUserRecipes = provider.userRecommendations.isNotEmpty;

    if (hasError && hybridRecipes.isEmpty) {
      return StatusCard.error(
        message: provider.error!,
        onRetry: () => provider.getHybridRecommendations(),
      );
    }

    if (hybridRecipes.isEmpty) {
      return StatusCard(
        icon: Icons.restaurant_menu,
        title: 'ยังไม่มีเมนูแนะนำจากระบบ',
        subtitle: hasUserRecipes
            ? 'คุณยังสามารถเปิดเมนูที่เพิ่มเองจากปุ่มมุมขวาบน'
            : 'ลองปรับตัวกรองหรือเพิ่มวัตถุดิบเพื่อรับคำแนะนำใหม่',
        color: Colors.green,
        action: hasUserRecipes
            ? ElevatedButton(
                onPressed: _showUserRecipesMenu,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('ดูเมนูที่ฉันเพิ่มเอง'),
              )
            : ElevatedButton(
                onPressed: () => provider.getHybridRecommendations(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow[600],
                  foregroundColor: Colors.black,
                ),
                child: const Text('ขอคำแนะนำใหม่'),
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.restaurant_menu,
              color: Colors.green,
            ).withPadding(const EdgeInsets.all(8)),
            'เมนูแนะนำ (Hybrid)'.asText(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hybridRecipes.length,
          itemBuilder: (context, index) {
            final recipe = hybridRecipes[index];
            return RecipeCard(
              recipe: recipe,
              showSourceBadge: true,
              compact: true,
              onTap: () => _showRecipeDetail(recipe),
            );
          },
        ),
      ],
    );
  }

  void _showRecipeDetail(RecipeModel recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EnhancedRecipeDetailSheet(recipe: recipe),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    final provider = context.read<EnhancedRecommendationProvider>();
    if (provider.ingredients.isEmpty) {
      await provider.loadIngredients();
    }
    final cuisines = const [
      {'th': 'ไทย', 'en': 'thai'},
      {'th': 'จีน', 'en': 'chinese'},
      {'th': 'ญี่ปุ่น', 'en': 'japanese'},
      {'th': 'เกาหลี', 'en': 'korean'},
      {'th': 'เวียดนาม', 'en': 'vietnamese'},
      {'th': 'อินเดีย', 'en': 'indian'},
      {'th': 'อเมริกา', 'en': 'american'},
      {'th': 'อังกฤษ', 'en': 'british'},
      {'th': 'ฝรั่งเศส', 'en': 'french'},
      {'th': 'เยอรมัน', 'en': 'german'},
      {'th': 'อิตาเลียน', 'en': 'italian'},
      {'th': 'เม็กซิกัน', 'en': 'mexican'},
      {'th': 'สเปน', 'en': 'spanish'},
    ];
    final dietKeys = const [
      'Vegan',
      'Vegetarian',
      'Lacto-Vegetarian',
      'Ovo-Vegetarian',
      'Ketogenic',
      'Paleo',
      'Gluten-Free',
      'Dairy-Free',
      'Low-Fat',
      'High-Protein',
      'Low-Carb',
    ];

    final current = provider.filters;
    final selectedCuisine = current.cuisineEn.toSet();
    final selectedDiet = current.dietGoals
        .map((e) => e[0].toUpperCase() + e.substring(1))
        .toSet();
    final minCalController =
        TextEditingController(text: current.minCalories?.toString() ?? '');
    final maxCalController =
        TextEditingController(text: current.maxCalories?.toString() ?? '');
    final minProteinController =
        TextEditingController(text: current.minProtein?.toString() ?? '');
    final maxCarbsController =
        TextEditingController(text: current.maxCarbs?.toString() ?? '');
    final maxFatController =
        TextEditingController(text: current.maxFat?.toString() ?? '');
    final controllers = <TextEditingController>[
      minCalController,
      maxCalController,
      minProteinController,
      maxCarbsController,
      maxFatController,
    ];
    final manualNames = (current.manualIngredientNames ?? []).toSet();
    String? activePreset = _activePresetFor(manualNames);
    final shownWarningCombos = <String>{};
    final shownPraiseCombos = <String>{};

    final sheetFuture = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {

        return StatefulBuilder(builder: (context, setState) {
          const conflictMap = <String, Set<String>>{
            'Vegan': {
              'Vegetarian',
              'Lacto-Vegetarian',
              'Ovo-Vegetarian',
              'Ketogenic',
              'Paleo',
              'High-Protein',
            },
            'Vegetarian': {'Vegan', 'Paleo', 'Dairy-Free'},
            'Lacto-Vegetarian': {'Vegan', 'Ovo-Vegetarian', 'Dairy-Free'},
            'Ovo-Vegetarian': {'Vegan', 'Lacto-Vegetarian'},
            'Ketogenic': {'Vegan', 'Low-Fat'},
            'Paleo': {'Vegan', 'Vegetarian', 'Low-Fat', 'Gluten-Free'},
            'High-Protein': {'Vegan'},
            'Low-Fat': {'Ketogenic', 'Paleo'},
            'Gluten-Free': {'Paleo'},
            'Dairy-Free': {'Lacto-Vegetarian', 'Vegetarian'},
          };
          const conflictReasons = <String, String>{
            'Vegan|Vegetarian':
                'เลือก Vegan แล้วจะครอบคลุมข้อจำกัดของ Vegetarian อัตโนมัติ',
            'Vegan|Lacto-Vegetarian':
                'Vegan ห้ามทุกผลิตภัณฑ์สัตว์ จึงไม่ควรเลือกแบบ Lacto เพิ่ม',
            'Vegan|Ovo-Vegetarian':
                'Vegan งดไข่ด้วยอยู่แล้ว เลือก Ovo-Vegetarian จะซ้ำซ้อน',
            'Vegan|Ketogenic':
                'Vegan เน้นพืช ส่วน Ketogenic ต้องคาร์บต่ำและไขมันสูงจากสัตว์ ซึ่งขัดกัน',
            'Vegan|Paleo':
                'Paleo เน้นเนื้อสัตว์และผลิตภัณฑ์จากสัตว์ ซึ่งไม่สอดคล้องกับ Vegan',
            'Vegan|High-Protein':
                'High-Protein ในที่นี้เน้นโปรตีนจากสัตว์ จึงไม่เข้ากับ Vegan',
            'Vegetarian|Vegan':
                'เลือก Vegetarian อยู่แล้ว หากต้องการงดผลิตภัณฑ์สัตว์ทั้งหมดให้เลือก Vegan แทน',
            'Vegetarian|Paleo':
                'Paleo เน้นเนื้อสัตว์เป็นหลัก จึงไม่เข้ากับ Vegetarian',
            'Vegetarian|Dairy-Free':
                'Vegetarian มักใช้ผลิตภัณฑ์นมทดแทนโปรตีน หากงดนมทั้งหมดให้เลือกแผน Vegan แทน',
            'Lacto-Vegetarian|Vegan':
                'Lacto-Vegetarian ยังทานนมได้ ส่วน Vegan งดนม จึงต้องเลือกอย่างใดอย่างหนึ่ง',
            'Lacto-Vegetarian|Ovo-Vegetarian':
                'Lacto- และ Ovo-Vegetarian เป็นตัวเลือกเฉพาะทาง ควรเลือกแบบใดแบบหนึ่ง',
            'Lacto-Vegetarian|Dairy-Free':
                'สูตร Lacto-Vegetarian เน้นผลิตภัณฑ์นม การเลือก Dairy-Free พร้อมกันจึงขัดกัน',
            'Ovo-Vegetarian|Vegan':
                'Ovo-Vegetarian ยังทานไข่ได้ แต่ Vegan งดไข่ เลือกพร้อมกันไม่ได้',
            'Ovo-Vegetarian|Lacto-Vegetarian':
                'Ovo และ Lacto เป็นแนวทางต่างกัน ควรเลือกอย่างใดอย่างหนึ่ง',
            'Ketogenic|Vegan':
                'Ketogenic ต้องใช้ไขมันสูงจากสัตว์ ซึ่งขัดกับ Vegan',
            'Ketogenic|Low-Fat':
                'Ketogenic ต้องทานไขมันสูง แต่ Low-Fat กำหนดไขมันต่ำ ซึ่งตรงข้ามกัน',
            'Paleo|Vegan':
                'Paleo ให้ความสำคัญกับเนื้อสัตว์และไขมัน จึงขัดกับ Vegan',
            'Paleo|Vegetarian':
                'Paleo งดธัญพืชและพืชหลายชนิดจึงไม่เข้ากับ Vegetarian',
            'Paleo|Low-Fat':
                'Paleo ใช้ไขมันจากสัตว์เป็นหลัก ซึ่งไม่ตรงกับ Low-Fat',
            'Paleo|Gluten-Free':
                'Paleo กำจัดธัญพืชกลูเตนอยู่แล้ว ระบบจะคัดให้ตาม Paleo โดยไม่ต้องเลือก Gluten-Free เพิ่ม',
            'High-Protein|Vegan':
                'High-Protein ในระบบนี้ออกแบบมาสำหรับโปรตีนจากสัตว์ จึงไม่เข้ากับ Vegan',
            'Low-Fat|Ketogenic':
                'Low-Fat และ Ketogenic กำหนดสัดส่วนไขมันตรงข้ามกัน',
            'Low-Fat|Paleo':
                'Paleo อิงไขมันจากสัตว์หลายชนิด จึงไม่สอดคล้องกับ Low-Fat',
          };
          String comboKey(String a, String b) {
            final items = [a, b]..sort();
            return items.join('|');
          }
          final cautionCombos = <String, String>{
            comboKey('Vegetarian', 'Low-Carb'):
                'เมนูมังสวิรัติที่คาร์บต่ำมีไม่มาก ระบบอาจแนะนำเมนูซ้ำหรือใช้วัตถุดิบคล้ายเดิมบ่อยขึ้น',
            comboKey('Vegan', 'Low-Fat'):
                'การกินแบบ Vegan พร้อมลดไขมันอาจทำให้ได้รับไขมันดีไม่เพียงพอ ระบบจะเน้นเมนูที่ยังมีไขมันจากพืชที่จำเป็นให้',
            comboKey('High-Protein', 'Low-Fat'):
                'การเพิ่มโปรตีนพร้อมควบคุมไขมันจะจำกัดแหล่งโปรตีน ระบบจะเลือกเมนูที่สมดุลระหว่างโปรตีนสูงและไขมันต่ำให้มากที่สุด',
            comboKey('Vegan', 'Gluten-Free'):
                'การกินแบบ Vegan และปราศจากกลูเตนพร้อมกันทำให้ตัวเลือกวัตถุดิบแคบมาก ระบบจะแนะนำเมนูที่ยังคงครบหมู่และหาวัตถุดิบได้จริง',
            comboKey('Vegetarian', 'Gluten-Free'):
                'มังสวิรัติที่ไม่ใช้กลูเตนต้องระวังธัญพืชทดแทน ระบบจะช่วยคัดเมนูที่ใช้แหล่งคาร์บปลอดกลูเตนแต่ยังครบสารอาหาร',
            comboKey('Vegan', 'Dairy-Free'):
                'Vegan งดผลิตภัณฑ์สัตว์อยู่แล้ว การเลือก Dairy-Free เพิ่มหมายถึงต้องเสริมแคลเซียมและโปรตีนจากพืชให้พอ ระบบจะแนะนำเมนูที่ตอบโจทย์นี้',
            comboKey('Vegetarian', 'Dairy-Free'):
                'มังสวิรัติที่งดนมอาจขาดโปรตีนและแคลเซียม ระบบจะเลือกเมนูที่ใช้ถั่วและผลิตภัณฑ์เสริมให้แทน',
          };
          final praiseCombos = <String, String>{
            comboKey('Low-Fat', 'Low-Carb'):
                'ควบคุมทั้งไขมันและคาร์บ เหมาะสำหรับการดูแลน้ำหนักและสมดุลพลังงานอย่างยั่งยืน',
            comboKey('Vegetarian', 'Low-Fat'):
                'มังสวิรัติแบบไขมันต่ำช่วยลดความเสี่ยงโรคหัวใจและสนับสนุนระบบหลอดเลือด',
            comboKey('Ketogenic', 'High-Protein'):
                'คีโตที่เสริมโปรตีนช่วยรักษามวลกล้ามเนื้อ เหมาะกับผู้ที่ออกกำลังกายสม่ำเสมอ',
            comboKey('Gluten-Free', 'Dairy-Free'):
                'เมนูที่ปลอดทั้งกลูเตนและนมเหมาะกับผู้ที่แพ้สองกลุ่มนี้ ระบบจะยังคัดเมนูที่สมดุลสารอาหารให้ครบถ้วน',
          };

          List<String> applyDietConflicts(String diet) {
            final conflicts = conflictMap[diet] ?? const {};
            final removed = <String>[];
            for (final c in conflicts) {
              if (selectedDiet.remove(c)) {
                removed.add(c);
              }
            }
            return removed;
          }

          Future<void> showConflictDialog(String diet, List<String> removed) async {
            if (removed.isEmpty) return;
            final detail = removed
                .map((item) =>
                    '• $item: ${conflictReasons['$diet|$item'] ?? conflictReasons['$item|$diet'] ?? 'ข้อจำกัดซ้ำซ้อน'}')
                .join('\n');
            final message = 'ไม่สามารถเลือกพร้อมกับ $diet ได้:\n$detail';
            return showDialog<void>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('ตัวเลือกขัดกัน'),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('ตกลง'),
                  ),
                ],
              ),
            );
          }

          Future<void> evaluateComboAlerts() async {
            Future<void> runAlerts(
              Map<String, String> combos,
              Set<String> tracker,
              String title,
            ) async {
              for (final entry in combos.entries) {
                final parts = entry.key.split('|');
                final active = selectedDiet.contains(parts[0]) &&
                    selectedDiet.contains(parts[1]);
                if (active) {
                  if (!tracker.contains(entry.key)) {
                    tracker.add(entry.key);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: Text(title),
                        content: Text(entry.value),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('ตกลง'),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  tracker.remove(entry.key);
                }
              }
            }

            await runAlerts(
              cautionCombos,
              shownWarningCombos,
              'โปรดระวัง',
            );
            await runAlerts(
              praiseCombos,
              shownPraiseCombos,
              'เลือกได้ดีมาก',
            );
          }

          Future.microtask(() => evaluateComboAlerts());

          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return FractionallySizedBox(
            heightFactor: 0.98,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Material(
                color: Colors.white,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Center(
                                child: 'ตัวกรองเมนูอาหาร'.asText(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            bottomInset > 16 ? bottomInset : 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              'วัตถุดิบที่ต้องการใช้ (ไม่บังคับ)'.asText(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              if (_ingredientPresets.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'เลือกชุดวัตถุดิบล่วงหน้า (แตะอีกครั้งเพื่อยกเลิก)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _ingredientPresets.map((preset) {
                                    final label = preset['label'] as String;
                                    final items =
                                        List<String>.from(preset['items'] as List);
                                    final selected = activePreset == label;
                                    return ChoiceChip(
                                      label: Text(label),
                                      selected: selected,
                                      onSelected: (_) {
                                        setState(() {
                                          if (selected) {
                                            manualNames.clear();
                                            activePreset = null;
                                          } else {
                                            manualNames
                                              ..clear()
                                              ..addAll(items);
                                            activePreset = label;
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Consumer<EnhancedRecommendationProvider>(
                                builder: (_, provider, __) {
                                  final ingredientNames =
                                      provider.availableIngredientNames;
                                  if (ingredientNames.isEmpty) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'ยังไม่มีวัตถุดิบพร้อมใช้งาน',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    );
                                  }
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: ingredientNames.map((name) {
                                      final checked = manualNames.contains(name);
                                      return FilterChip(
                                        label: Text(name),
                                        selected: checked,
                                        onSelected: (v) {
                                          setState(() {
                                            if (v) {
                                              manualNames.add(name);
                                            } else {
                                              manualNames.remove(name);
                                            }
                                            activePreset = null;
                                          });
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                              if (manualNames.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                'รายการที่เลือกไว้'.asText(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: (manualNames.toList()..sort())
                                      .map(
                                        (name) => InputChip(
                                          label: Text(name),
                                          onDeleted: () {
                                            setState(() {
                                              manualNames.remove(name);
                                              activePreset = null;
                                            });
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              const SizedBox(height: 16),
                              'ประเภทอาหาร (ไม่บังคับ)'.asText(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              ...cuisines.map((c) {
                                final en = c['en']!;
                                final th = c['th']!;
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: selectedCuisine.contains(en),
                                  title: Text(th),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        selectedCuisine.add(en);
                                      } else {
                                        selectedCuisine.remove(en);
                                      }
                                    });
                                  },
                                );
                              }),
                              const SizedBox(height: 8),
                              'ข้อจำกัดด้านอาหาร (ไม่บังคับ)'.asText(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              ...dietKeys.map((k) {
                                final key = k.toLowerCase();
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: selectedDiet.contains(k),
                                  title: Text(k),
                                  onChanged: (v) async {
                                    if (v == true) {
                                      var removed = <String>[];
                                      setState(() {
                                        removed = applyDietConflicts(k);
                                        selectedDiet.add(k);
                                      });
                                      await showConflictDialog(k, removed);
                                      await evaluateComboAlerts();
                                    } else {
                                      setState(() {
                                        selectedDiet.remove(k);
                                      });
                                      await evaluateComboAlerts();
                                    }
                                  },
                                );
                              }).toList(),
                              const SizedBox(height: 8),
                              'แคลอรี่ต่อเมนู (ไม่บังคับ)'.asText(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      keyboardType: TextInputType.number,
                                      controller: minCalController,
                                      decoration: const InputDecoration(
                                        labelText: 'ขั้นต่ำ (kcal)',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      keyboardType: TextInputType.number,
                                      controller: maxCalController,
                                      decoration: const InputDecoration(
                                        labelText: 'ขั้นสูง (kcal)',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedDiet.contains('High-Protein') ||
                                  selectedDiet.contains('Low-Carb') ||
                                  selectedDiet.contains('Low-Fat')) ...[
                                const SizedBox(height: 12),
                                'ข้อจำกัดที่เลือก (ต่อหนึ่งเสิร์ฟ)'.asText(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ],
                              if (selectedDiet.contains('High-Protein'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextFormField(
                                    keyboardType: TextInputType.number,
                                    controller: minProteinController,
                                    decoration: const InputDecoration(
                                      labelText: 'High-Protein: โปรตีนขั้นต่ำ',
                                      hintText: 'เช่น 20',
                                      suffixText: 'g',
                                    ),
                                  ),
                                ),
                              if (selectedDiet.contains('Low-Carb'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextFormField(
                                    keyboardType: TextInputType.number,
                                    controller: maxCarbsController,
                                    decoration: const InputDecoration(
                                      labelText: 'Low-Carb: คาร์บสูงสุด',
                                      hintText: 'เช่น 25',
                                      suffixText: 'g',
                                    ),
                                  ),
                                ),
                              if (selectedDiet.contains('Low-Fat'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextFormField(
                                    keyboardType: TextInputType.number,
                                    controller: maxFatController,
                                    decoration: const InputDecoration(
                                      labelText: 'Low-Fat: ไขมันสูงสุด',
                                      hintText: 'เช่น 15',
                                      suffixText: 'g',
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: const Text('ยกเลิก'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      final appliedMinCal =
                                          _parseNumericInput(
                                            minCalController.text,
                                          );
                                      final appliedMaxCal =
                                          _parseNumericInput(
                                            maxCalController.text,
                                          );
                                      final appliedMinProtein =
                                          _parseNumericInput(
                                            minProteinController.text,
                                          );
                                      final appliedMaxCarbs =
                                          _parseNumericInput(
                                            maxCarbsController.text,
                                          );
                                      final appliedMaxFat =
                                          _parseNumericInput(
                                            maxFatController.text,
                                          );

                                      provider.setCuisineFilters(
                                        selectedCuisine.toList(),
                                      );
                                      provider.setDietGoals(
                                        selectedDiet
                                            .map((e) => e.toLowerCase())
                                            .toSet(),
                                      );
                                      provider.setCalorieRange(
                                        min: appliedMinCal,
                                        max: appliedMaxCal,
                                      );
                                      final sd = selectedDiet.toSet();
                                      provider.setMacroThresholds(
                                        minProtein: sd.contains('High-Protein')
                                            ? appliedMinProtein
                                            : null,
                                        maxCarbs: sd.contains('Low-Carb')
                                            ? appliedMaxCarbs
                                            : null,
                                        maxFat: sd.contains('Low-Fat')
                                            ? appliedMaxFat
                                            : null,
                                      );
                                      provider.setManualIngredientNames(
                                        manualNames.isEmpty
                                            ? null
                                            : manualNames.toList(),
                                      );
                                      Navigator.pop(context);
                                      provider.getHybridRecommendations();
                                    },
                                    child: const Text('ตกลง'),
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
            ),
          );

        });
      },
    );
    sheetFuture.whenComplete(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  String? _activePresetFor(Set<String> manualNames) {
    for (final preset in _ingredientPresets) {
      final items = List<String>.from(preset['items'] as List);
      if (manualNames.length == items.length &&
          items.every(manualNames.contains)) {
        return preset['label'] as String;
      }
    }
    return null;
  }
}
