import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/data_type.dart';

class TypeTabRow extends StatelessWidget {
  final DataType selected;
  final ValueChanged<DataType> onChanged;

  const TypeTabRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DataType.values.map((dt) {
          final isActive = dt == selected;
          return GestureDetector(
            onTap: () => onChanged(dt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? context.themeAccent.withValues(alpha: 0.12)
                    : context.themeCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? context.themeAccent : context.themeBorder,
                  width: isActive ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dt.icon,
                    size: 16,
                    color: isActive
                        ? context.themeAccent
                        : context.themeTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dt.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? context.themeAccent
                          : context.themeTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
