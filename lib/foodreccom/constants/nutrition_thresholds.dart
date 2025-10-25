enum NutrientLevel { low, medium, high }

enum ConsumptionFrequency { daily, oncePerDay, weekly, occasional }

class NutrientThreshold {
  final double lowMax;
  final double mediumMax;

  const NutrientThreshold({
    required this.lowMax,
    required this.mediumMax,
  });

  NutrientLevel classify(double value) {
    if (value <= lowMax) return NutrientLevel.low;
    if (value <= mediumMax) return NutrientLevel.medium;
    return NutrientLevel.high;
  }
}

class NutritionThresholds {
  static const Map<String, NutrientThreshold> thresholds = {
    'fat': NutrientThreshold(lowMax: 3, mediumMax: 17.5),
    'saturates': NutrientThreshold(lowMax: 1.5, mediumMax: 5),
    'sugar': NutrientThreshold(lowMax: 5, mediumMax: 22.5),
    'salt': NutrientThreshold(lowMax: 0.3, mediumMax: 1.5),
  };

  static const Map<String, String> _nutrientLabels = {
    'fat': 'fat',
    'saturates': 'saturated fat',
    'sugar': 'sugar',
    'salt': 'salt',
  };

  static ConsumptionFrequency? frequencyFromValues({
    double? fat,
    double? saturates,
    double? sugar,
    double? salt,
  }) {
    final entries = <String, double>{
      if (fat != null) 'fat': fat,
      if (saturates != null) 'saturates': saturates,
      if (sugar != null) 'sugar': sugar,
      if (salt != null) 'salt': salt,
    };
    if (entries.isEmpty) return null;

    final levels = entries.map((key, value) {
      final threshold = thresholds[key];
      if (threshold == null) return MapEntry(key, NutrientLevel.low);
      return MapEntry(key, threshold.classify(value));
    });
    return frequencyFromLevels(levels.values.toList());
  }

  static ConsumptionFrequency frequencyFromLevels(List<NutrientLevel> levels) {
    if (levels.isEmpty) return ConsumptionFrequency.daily;
    final highCount = levels.where((l) => l == NutrientLevel.high).length;
    if (highCount >= 1) return ConsumptionFrequency.occasional;

    final mediumCount = levels.where((l) => l == NutrientLevel.medium).length;
    if (mediumCount >= 3) return ConsumptionFrequency.weekly;
    if (mediumCount == 2) return ConsumptionFrequency.oncePerDay;
    return ConsumptionFrequency.daily;
  }

  static String? reasonFromValues({
    double? fat,
    double? saturates,
    double? sugar,
    double? salt,
  }) {
    final entries = <String, double>{
      if (fat != null) 'fat': fat,
      if (saturates != null) 'saturates': saturates,
      if (sugar != null) 'sugar': sugar,
      if (salt != null) 'salt': salt,
    };
    if (entries.isEmpty) return null;

    final evaluated = entries.map((key, value) {
      final threshold = thresholds[key];
      final level =
          threshold == null ? NutrientLevel.low : threshold.classify(value);
      return MapEntry(key, level);
    });

    final highKeys =
        evaluated.entries.where((e) => e.value == NutrientLevel.high).map((e) => e.key).toList();
    if (highKeys.isNotEmpty) {
      return 'High ${_formatLabels(highKeys)} - enjoy occasionally.';
    }

    final mediumKeys =
        evaluated.entries.where((e) => e.value == NutrientLevel.medium).map((e) => e.key).toList();
    if (mediumKeys.length >= 3) {
      return 'Several nutrients at medium levels (${_formatLabels(mediumKeys)}) - limit to weekly consumption.';
    }
    if (mediumKeys.length == 2) {
      return 'Moderate ${_formatLabels(mediumKeys)} - keep to once per day.';
    }
    if (mediumKeys.length == 1) {
      return 'Slightly elevated ${_formatLabels(mediumKeys)} - suitable for daily use.';
    }
    return 'All tracked nutrients are low - safe for daily consumption.';
  }

  static String _formatLabels(List<String> keys) {
    final labels = keys.map((k) => _nutrientLabels[k] ?? k).toList();
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    final head = labels.sublist(0, labels.length - 1).join(', ');
    final tail = labels.last;
    return '$head and $tail';
  }
}
