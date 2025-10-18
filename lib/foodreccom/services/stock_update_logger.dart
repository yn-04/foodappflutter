import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/smart_unit_converter.dart';

class StockUpdateLogger {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  /// 🔸 บันทึก log การลดสต็อกหลังการทำอาหาร
  Future<void> logConversionAndStockUpdate({
    required String ingredientName,
    required String recipeId,
    required double requiredAmount,
    required String recipeUnit,
    required double deductedAmount,
    required String stockUnit,
    required double beforeQuantity,
    required double afterQuantity,
  }) async {
    if (_user == null) return;
    final uid = _user!.uid;

    final requiredCanonical = SmartUnitConverter.toCanonicalQuantity(
      requiredAmount,
      recipeUnit,
      ingredientName,
    );
    final deductedCanonical = SmartUnitConverter.toCanonicalQuantity(
      deductedAmount,
      stockUnit,
      ingredientName,
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('raw_materials_history')
        .add({
          'ingredient_name': ingredientName,
          'recipe_id': recipeId,
          'timestamp': FieldValue.serverTimestamp(),
          'required_amount': requiredAmount,
          'required_unit': recipeUnit,
          'required_canonical': {
            'amount': requiredCanonical.amount,
            'unit': requiredCanonical.unit,
          },
          'deducted_amount': deductedAmount,
          'deducted_unit': stockUnit,
          'deducted_canonical': {
            'amount': deductedCanonical.amount,
            'unit': deductedCanonical.unit,
          },
          'before_quantity': beforeQuantity,
          'after_quantity': afterQuantity,
          'difference': beforeQuantity - afterQuantity,
          'conversion_note':
              'Converted ${requiredAmount.toStringAsFixed(2)} $recipeUnit → ${deductedCanonical.amount.toStringAsFixed(2)} ${deductedCanonical.unit}',
        });
  }
}
