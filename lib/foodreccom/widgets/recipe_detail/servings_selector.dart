//lib/foodreccom/widgets/recipe_detail/servings_selector.dart
import 'package:flutter/material.dart';

class ServingsSelector extends StatelessWidget {
  final int selected;
  final int max;
  final ValueChanged<int> onChanged;

  const ServingsSelector({
    super.key,
    required this.selected,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('จำนวนคนที่จะทำ'),
        Row(
          children: [
            IconButton(
              onPressed: selected > 1 ? () => onChanged(selected - 1) : null,
              icon: const Icon(Icons.remove_circle),
            ),
            Text('$selected คน'),
            IconButton(
              onPressed: selected < max ? () => onChanged(selected + 1) : null,
              icon: const Icon(Icons.add_circle),
            ),
          ],
        ),
      ],
    );
  }
}
