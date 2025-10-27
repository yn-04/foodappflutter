// lib/foodreccom/utils/allergy_utils.dart

class AllergyExpansion {
  const AllergyExpansion({
    required this.all,
    required this.englishOnly,
  });

  final Set<String> all;
  final Set<String> englishOnly;
}

class AllergyUtils {
  static AllergyExpansion expandAllergens(Iterable<String> rawAllergies) {
    final normalizedInputs = <String>{};
    for (final raw in rawAllergies) {
      final pieces = raw
          .split(RegExp(r'[,/|;]'))
          .map(_normalize)
          .where((value) => value.isNotEmpty);
      normalizedInputs.addAll(pieces);
    }

    final expanded = <String>{};
    for (final term in normalizedInputs) {
      final synonyms = _synonymIndex[term];
      if (synonyms != null && synonyms.isNotEmpty) {
        expanded.addAll(synonyms);
      } else {
        expanded.add(term);
      }
    }

    final english = expanded.where(_looksEnglish).toSet();
    return AllergyExpansion(all: expanded, englishOnly: english);
  }

  static bool matchesAllergen(String ingredientName, Set<String> allergens) {
    if (allergens.isEmpty) return false;
    final candidate = _normalize(ingredientName);
    if (candidate.isEmpty) return false;

    for (final allergen in allergens) {
      if (allergen == 'salt' || allergen == 'เกลือ') {
        continue; // เกลือในน้ำปลาให้ตรวจจากคำสำคัญอื่นแทน เพื่อหลีกเลี่ยง false positive
      }
      if (candidate == allergen) return true;
      if (_isNonLatin(allergen)) {
        if (candidate.contains(allergen)) return true;
      } else {
        final pattern = RegExp(
          r'(^|[^a-z])' + RegExp.escape(allergen) + r'([^a-z]|$)',
        );
        if (pattern.hasMatch(candidate)) return true;
      }
    }
    return false;
  }

  static final Map<String, Set<String>> _synonymIndex = _buildSynonymIndex();

  static Map<String, Set<String>> _buildSynonymIndex() {
    final index = <String, Set<String>>{};
    final baseGroups = <String, Set<String>>{};

    void addGroup(String key, Iterable<String> values) {
      final normalized = values.map(_normalize).where((v) => v.isNotEmpty).toSet();
      if (normalized.isEmpty) return;
      baseGroups[key] = normalized;
      for (final term in normalized) {
        index.putIfAbsent(term, () => <String>{}).addAll(normalized);
      }
    }

    addGroup('fish', const {
      'fish',
      'ปลา',
      'ปลาทะเล',
      'ปลาน้ำจืด',
      'ปลาดิบ',
      'ปลานิล',
      'ปลาดอรี่',
      'ปลากะพง',
      'ปลาทูน่า',
      'ทูน่า',
      'tuna',
      'salmon',
      'แซลมอน',
      'mackerel',
      'ซาบะ',
      'ปลากะตัก',
      'anchovy',
      'ปลาซาร์ดีน',
      'sardine',
      'ปลาคอด',
      'cod',
      'snapper',
      'ปลาดุก',
      'catfish',
      'ปลาช่อน',
      'snakehead fish',
      'ปลาเค็ม',
      'ปลาร้า',
      'fermented fish',
      'น้ำปลา',
      'fish sauce',
      'anchovy paste',
      'ปลาป่น',
      'garum',
      'nam pla',
      'nuoc mam',
      'patis',
    });

    addGroup('crustacean', const {
      'กุ้ง',
      'shrimp',
      'prawn',
      'กุ้งแห้ง',
      'dried shrimp',
      'river prawn',
      'กุ้งก้ามกราม',
      'กั้ง',
      'mantis shrimp',
      'กุ้งล็อบสเตอร์',
      'lobster',
      'ปู',
      'crab',
      'ปูทะเล',
      'ปูม้า',
      'blue crab',
      'mud crab',
      'กะปิ',
      'shrimp paste',
      'xo sauce',
      'น้ำปลา',
      'fish sauce',
      'fermented shrimp',
      'shrimp sauce',
    });

    addGroup('shellfish', const {
      'หอย',
      'shellfish',
      'oyster',
      'หอยนางรม',
      'clam',
      'หอยลาย',
      'mussel',
      'หอยแมลงภู่',
      'scallop',
      'หอยเชลล์',
      'cockle',
      'หอยแครง',
      'mollusk',
      'mollusc',
      'oyster sauce',
      'clam juice',
      'หอยดอง',
      'น้ำปลา',
      'fish sauce',
    });

    addGroup('cephalopod', const {
      'ปลาหมึก',
      'หมึก',
      'squid',
      'calamari',
      'octopus',
      'ปลาหมึกยักษ์',
      'cuttlefish',
      'squid ink',
      'หมึกดำ',
    });

    addGroup('dairy', const {
      'นม',
      'milk',
      'dairy',
      'นมวัว',
      'cow milk',
      'นมผง',
      'milk powder',
      'cream',
      'ครีม',
      'เนย',
      'butter',
      'ชีส',
      'cheese',
      'โยเกิร์ต',
      'yogurt',
      'kefir',
      'คีเฟอร์',
      'นมข้นหวาน',
      'condensed milk',
      'นมข้นจืด',
      'evaporated milk',
      'เคซีน',
      'casein',
      'เวย์',
      'whey',
      'แลคโตส',
      'lactose',
      'ice cream',
      'เจลาโต',
      'gelato',
      'sour cream',
      'buttermilk',
      'ครีมชีส',
      'cream cheese',
      'ricotta',
      'mascarpone',
      'ghee',
      'ไขมันนม',
      'milk fat',
      'milk chocolate',
      'white chocolate',
    });

    addGroup('egg', const {
      'ไข่',
      'egg',
      'ไข่ไก่',
      'chicken egg',
      'ไข่เป็ด',
      'duck egg',
      'ไข่แดง',
      'egg yolk',
      'ไข่ขาว',
      'egg white',
      'albumen',
      'mayonnaise',
      'มายองเนส',
      'mayo',
      'aioli',
      'custard',
      'คัสตาร์ด',
      'meringue',
      'ซอสฮอลแลนด์',
      'hollandaise',
      'egg wash',
    });

    addGroup('peanut', const {
      'ถั่วลิสง',
      'peanut',
      'groundnut',
      'ถั่วปี',
      'เนยถั่ว',
      'peanut butter',
      'peanut oil (unrefined)',
      'satay sauce',
      'ซอสสะเต๊ะ',
      'น้ำจิ้มถั่วลิสง',
    });

    addGroup('tree_nut', const {
      'ถั่ว',
      'nut',
      'อัลมอนด์',
      'almond',
      'วอลนัท',
      'walnut',
      'เฮเซลนัท',
      'hazelnut',
      'พิสตาชิโอ',
      'pistachio',
      'pecan',
      'pekan',
      'แมคคาเดเมีย',
      'macadamia',
      'เม็ดมะม่วงหิมพานต์',
      'cashew',
      'บราซิลนัท',
      'brazil nut',
      'เกาลัด',
      'chestnut',
      'pine nut',
      'pinenut',
      'ถั่วพิสต้า',
      'nut butter',
      'nut milk',
      'almond milk',
      'almond butter',
      'hazelnut spread',
      'nut flour',
      'pesto',
      'น้ำมันถั่ว',
    });

    addGroup('soy', const {
      'ถั่วเหลือง',
      'soy',
      'soybean',
      'ถั่วแขก',
      'edamame',
      'นมถั่วเหลือง',
      'soy milk',
      'ซอสถั่วเหลือง',
      'soy sauce',
      'tamari',
      'โชยุ',
      'shoyu',
      'เต้าหู้',
      'tofu',
      'มิโซะ',
      'miso',
      'เทมเป้',
      'tempeh',
      'นัตโตะ',
      'natto',
      'yuba',
      'tofu skin',
      'soy protein',
      'soy protein isolate',
      'hydrolyzed soy protein',
      'textured vegetable protein',
      'tvp',
      'soy lecithin',
      'edamame paste',
      'fermented soybeans',
    });

    addGroup('chili', const {
      'พริก',
      'พริกขี้หนู',
      'พริกแห้ง',
      'พริกคั่ว',
      'พริกป่น',
      'พริกไทยสด',
      'chili',
      'chilli',
      'chile',
      '辣椒',
      'chili pepper',
      'hot pepper',
      'hot chili',
      'red chili',
      'green chili',
      'bird eye chili',
      'thai chili',
      'jalapeno',
      'jalapeño',
      'serrano',
      'cayenne',
      'habanero',
      'ghost pepper',
      'pepper flakes',
      'chili flakes',
      'chili powder',
      'cayenne powder',
      'paprika (hot)',
      'sambal',
      'sambal oelek',
      'nam prik',
      'น้ำพริก',
      'น้ำพริกเผา',
      'chili paste',
      'chili jam',
      'chili oil',
      '辣椒油',
      'ซอสพริก',
      'sriracha',
      'hot sauce',
      'buffalo sauce',
      'gochujang',
      'โคชูจัง',
      'kimchi',
      'คิมชี',
      'kimchi paste',
      'peri-peri',
      'piri piri',
      'harissa',
      'adobo sauce',
      'chipotle',
      'chipotle in adobo',
      '辣椒醬',
    });

    addGroup('wheat', const {
      'แป้งสาลี',
      'wheat',
      'gluten',
      'กลูเตน',
      'ข้าวสาลี',
      'wheat flour',
      'all-purpose flour',
      'self-rising flour',
      'bread flour',
      'cake flour',
      'แป้งเอนกประสงค์',
      'แป้งเค้ก',
      'แป้งขนมปัง',
      'แป้งทำขนม',
      'barley',
      'บาร์เลย์',
      'rye',
      'ข้าวไรย์',
      'malt',
      'มอลต์',
      'durum',
      'semolina',
      'เซโมลินา',
      'couscous',
      'คูสคูส',
      'breadcrumbs',
      'เกล็ดขนมปัง',
      'bread',
      'ขนมปัง',
      'biscuit',
      'cookie',
      'cracker',
      'croissant',
      'เค้ก',
      'พายแป้ง',
      'พาสต้า',
      'pasta',
      'spaghetti',
      'สปาเก็ตตี้',
      'macaroni',
      'มักกะโรนี',
      'ราเม็ง',
      'ramen',
      'อุด้ง',
      'udon',
      'โซบะ',
      'soba',
      'เทมปุระ',
      'tempura batter',
      'ซีอิ๊ว',
      'ซีอิ๊วขาว',
      'ซีอิ๊วดำ',
      'ซีอิ๊วดำหวาน',
      'ซอสถั่วเหลือง',
      'soy sauce',
      'shoyu',
      'ponzu',
      'ซอสพอนสึ',
      'worcestershire sauce',
      'ซอสปรุงรส',
      'teriyaki sauce',
      'ซอสเทอริยากิ',
      'hoisin sauce',
      'ซอสฮอยซิน',
      'malt vinegar',
      'beer',
      'เบียร์',
      'lager',
      'ale',
      'seitan',
      'vital wheat gluten',
      'farro',
      'emmer',
      'einkorn',
      'triticale',
      'kamut',
      'bulgur',
      'freekeh',
      'graham flour',
      'flour',
      'แป้ง',
      'แป้งมัน',
      'แป้งมันฝรั่ง',
      'แป้งข้าวโพด',
      'corn flour',
      'cornstarch',
      'starch',
      'แป้งเท้ายายม่อม',
      'แป้งกวนไส้',
      'wheat starch',
      'wheat bran',
      'bran',
      'orzo',
      'cereal containing wheat',
      '麵',
      '面',
      'noodle',
      'noodles',
      'เส้น',
      'egg noodle',
      'เส้นไข่',
      'instant noodle',
      'instant noodles',
      'บะหมี่กึ่งสำเร็จรูป',
      'มาม่า',
      'ไวไว',
      'ยำยำ',
      'ควิก',
      'ซื่อสัตย์',
      'mamee',
      'ramen noodles',
      'udon noodles',
      'soba noodles',
      'dumpling',
      'เกี๊ยว',
      'เกี๊ยวซ่า',
      'เกี๊ยวทอด',
      'wonton',
      'gnocchi',
      'pancake',
      'waffle',
      'crepe',
      'doughnut',
      'donut',
      'pretzel',
      'scone',
      'bagel',
      'pizza',
      'pizza crust',
      'พิซซ่า',
      'พิซซ่าโดว์',
      'puff pastry',
      'phyllo',
      'filo',
      'spring roll wrapper',
      'แผ่นปอเปี๊ยะ',
      'แผ่นเกี๊ยว',
      'wrap',
      'tortilla',
      'flour tortilla',
      'breaded',
      'battered',
      'roux',
      'graham cracker',
      'cracker crumbs',
      'sausage',
      'sausages',
      'ไส้กรอก',
      'ลูกชิ้น',
      'meatball',
      'meatballs',
    });

    addGroup('sesame', const {
      'งา',
      'sesame',
      'เมล็ดงา',
      'sesame seed',
      'น้ำมันงา',
      'sesame oil',
      'tahini',
      'ซอสงา',
      'gomasio',
    });

    addGroup('honey', const {
      'น้ำผึ้ง',
      'honey',
    });

    addGroup('yeast', const {
      'ยีสต์',
      'yeast',
      'baker\'s yeast',
      'brewer\'s yeast',
      'active dry yeast',
      'instant yeast',
      'rapid-rise yeast',
      'fresh yeast',
      'sourdough starter',
      'levain',
      'yeast extract',
      'autolyzed yeast extract',
      'marmite',
      'vegemite',
      'นูทริชันนัลยีสต์',
      'nutritional yeast',
      'torula yeast',
      'wine yeast',
      'champagne yeast',
      'beer yeast',
      'kombucha scoby',
      'scoby',
      'barm',
      'fermented dough',
      'แป้งหมัก',
      'หัวเชื้อ',
      'หัวเชื้อขนมปัง',
      'หัวเชื้อซาวโดว์',
      'ขนมปัง',
      'bread',
      'bagel',
      'เบเกิล',
      'ขนมปังโฮลวีต',
      'whole wheat bread',
      'brioche',
      'ครัวซองต์',
      'croissant',
      'เบเกอรี่หมัก',
      'pizza dough',
      'โดว์พิซซ่า',
      'พิซซ่า',
      'pizza',
      'buns',
      'ขนมปังเบอร์เกอร์',
      'burger bun',
      'bao',
      'ซาลาเปา',
      'mantou',
      'ขนมจีบทอด',
      'ขนมปังกระเทียม',
      'garlic bread',
      'โยเกิร์ต',
      'yogurt',
      'kefir',
      'คีเฟอร์',
      'ชีส',
      'cheese',
      'blue cheese',
      'camembert',
      'gouda',
      'ไวน์',
      'wine',
      'red wine',
      'white wine',
      'สปาร์กลิงไวน์',
      'sparkling wine',
      'แชมเปญ',
      'champagne',
      'เบียร์',
      'beer',
      'ale',
      'lager',
      'stout',
      'ไซเดอร์',
      'cider',
      'คอมบูชะ',
      'kombucha',
      'มิริน',
      'mirin',
      'มิโซะ',
      'miso',
      'ซอสถั่วเหลืองหมัก',
      'fermented soy sauce',
      'tempeh',
      'เต้าหู้หมัก',
      'นัตโตะ',
      'natto',
      'vinegar with mother',
      'apple cider vinegar',
      'balsamic vinegar',
    });

    void extendWithSelfAndGroups(Iterable<String> rawTerms, Iterable<String> groups) {
      final normalizedTerms =
          rawTerms.map(_normalize).where((t) => t.isNotEmpty).toSet();
      if (normalizedTerms.isEmpty) return;
      final union = <String>{...normalizedTerms};
      for (final key in groups) {
        union.addAll(baseGroups[key] ?? const <String>{});
      }
      for (final term in normalizedTerms) {
        index.putIfAbsent(term, () => <String>{}).addAll(union);
      }
    }

    extendWithSelfAndGroups(
      const {'seafood', 'sea food', 'อาหารทะเล', 'ซีฟู้ด'},
      const {'fish', 'crustacean', 'shellfish', 'cephalopod'},
    );

    extendWithSelfAndGroups(
      const {'shellfish', 'mollusk', 'mollusc', 'สัตว์เปลือกแข็ง'},
      const {'crustacean', 'shellfish'},
    );

    return index;
  }

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static bool _looksEnglish(String value) {
    return RegExp(r'[a-z]').hasMatch(value) &&
        !RegExp(r'[^\x00-\x7F]').hasMatch(value);
  }

  static bool _isNonLatin(String value) {
    return RegExp(r'[^\x00-\x7F]').hasMatch(value);
  }
}

String describeAllergyCoverage(Iterable<String> rawAllergies) {
  final seen = <String>{};
  final lines = <String>[];
  for (final raw in rawAllergies) {
    final tokens = raw
        .split(RegExp(r'[,/|;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    for (final token in tokens) {
      final normalized = token.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      if (!seen.add(normalized)) continue;
      final expansion = AllergyUtils.expandAllergens([token]);
      final synonyms = expansion.all.toList()..sort();
      if (synonyms.isEmpty) continue;
      lines.add('- $token → หลีกเลี่ยงทั้งหมด: ${synonyms.join(', ')}');
    }
  }
  if (lines.isEmpty) {
    return '- ไม่มีข้อมูลภูมิแพ้จากผู้ใช้';
  }
  return lines.join('\n');
}
