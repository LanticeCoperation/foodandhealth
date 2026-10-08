import 'package:flutter/material.dart';

/// 去掉多餘的小數：2.0 → "2"、1.5 → "1.5"；null → ""。
String fmtNum(double? v, {int maxDecimals = 1}) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(maxDecimals)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double? parseNum(String s) => double.tryParse(s.trim());

String? validateOptionalNumber(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final v = parseNum(s);
  return v == null || v < 0 ? '請輸入數字' : null;
}

String? validateServings(String? s) {
  final v = parseNum(s ?? '');
  return v == null || v <= 0 ? '>0' : null;
}

const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

/// 每份熱量 / 蛋白質 / 碳水 / 脂肪的四個輸入欄（都可留空）。
class NutritionControllers {
  NutritionControllers({
    double? kcal,
    double? protein,
    double? carbs,
    double? fat,
  }) : kcal = TextEditingController(text: fmtNum(kcal, maxDecimals: 2)),
       protein = TextEditingController(text: fmtNum(protein, maxDecimals: 2)),
       carbs = TextEditingController(text: fmtNum(carbs, maxDecimals: 2)),
       fat = TextEditingController(text: fmtNum(fat, maxDecimals: 2));

  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  double? get kcalValue => parseNum(kcal.text);
  double? get proteinValue => parseNum(protein.text);
  double? get carbsValue => parseNum(carbs.text);
  double? get fatValue => parseNum(fat.text);

  void dispose() {
    for (final c in [kcal, protein, carbs, fat]) {
      c.dispose();
    }
  }
}

class NutritionFields extends StatelessWidget {
  const NutritionFields({super.key, required this.controllers});

  final NutritionControllers controllers;

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, String unit) =>
        Expanded(
          child: TextFormField(
            controller: c,
            keyboardType: numberKeyboard,
            decoration: InputDecoration(labelText: label, suffixText: unit),
            validator: validateOptionalNumber,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每份營養（可留空）', style: Theme.of(context).textTheme.labelMedium),
        Row(
          children: [
            field(controllers.kcal, '熱量', 'kcal'),
            const SizedBox(width: 12),
            field(controllers.protein, '蛋白質', 'g'),
          ],
        ),
        Row(
          children: [
            field(controllers.carbs, '碳水', 'g'),
            const SizedBox(width: 12),
            field(controllers.fat, '脂肪', 'g'),
          ],
        ),
      ],
    );
  }
}
