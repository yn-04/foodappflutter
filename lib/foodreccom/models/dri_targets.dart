class DriTargets {
  final double energyKcal;
  final double carbMinG;
  final double carbMaxG;
  final double fatMinG;
  final double fatMaxG;
  final double proteinG;
  final double sodiumMaxMg;

  const DriTargets({
    required this.energyKcal,
    required this.carbMinG,
    required this.carbMaxG,
    required this.fatMinG,
    required this.fatMaxG,
    required this.proteinG,
    required this.sodiumMaxMg,
  });

  factory DriTargets.fromMap(Map<String, dynamic> map) {
    double _asDouble(String key) {
      final v = map[key];
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return DriTargets(
      energyKcal: _asDouble('energy_kcal'),
      carbMinG: _asDouble('carb_min_g'),
      carbMaxG: _asDouble('carb_max_g'),
      fatMinG: _asDouble('fat_min_g'),
      fatMaxG: _asDouble('fat_max_g'),
      proteinG: _asDouble('protein_g'),
      sodiumMaxMg: _asDouble('sodium_max_mg'),
    );
  }

  bool get hasMacros =>
      energyKcal > 0 &&
      carbMinG > 0 &&
      carbMaxG > 0 &&
      fatMinG > 0 &&
      fatMaxG > 0 &&
      proteinG > 0;

  Map<String, double> perMealTargets(int mealsPerDay, List<double>? energyRatios) {
    if (mealsPerDay <= 0) {
      return {
        'energy': energyKcal,
        'carb_min': carbMinG,
        'carb_max': carbMaxG,
        'fat_min': fatMinG,
        'fat_max': fatMaxG,
        'protein_min': proteinG,
        'sodium_max': sodiumMaxMg,
      };
    }
    final ratios = _normalizedRatios(mealsPerDay, energyRatios);
    final base = <String, double>{};
    for (var i = 0; i < mealsPerDay; i++) {
      final ratio = ratios[i];
      base['energy_$i'] = energyKcal * ratio;
      base['carb_min_$i'] = carbMinG * ratio;
      base['carb_max_$i'] = carbMaxG * ratio;
      base['fat_min_$i'] = fatMinG * ratio;
      base['fat_max_$i'] = fatMaxG * ratio;
      base['protein_min_$i'] = proteinG * ratio;
      base['sodium_max_$i'] = sodiumMaxMg * ratio;
    }
    return base;
  }

  static List<double> _normalizedRatios(
    int mealsPerDay,
    List<double>? ratios,
  ) {
    if (ratios != null && ratios.length == mealsPerDay) {
      final sum = ratios.fold<double>(0, (prev, v) => prev + v);
      if (sum > 0) {
        return ratios.map((v) => v / sum).toList(growable: false);
      }
    }
    return List<double>.filled(mealsPerDay, 1 / mealsPerDay);
  }
}
