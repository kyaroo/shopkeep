import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Pill stock badge — three encodings (icon + color + text) per spec.
/// Non-interactive; announces status via Semantics.
class StockBadge extends StatelessWidget {
  final bool isOutOfStock;
  final bool isLowStock;

  const StockBadge({
    super.key,
    required this.isOutOfStock,
    required this.isLowStock,
  });

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<AppColors>()!;
    final (color, icon, label) = isOutOfStock
        ? (status.danger, Icons.remove_shopping_cart, 'outOfStock'.tr())
        : isLowStock
            ? (status.warning, Icons.warning_amber, 'lowStock'.tr())
            : (status.success, Icons.check_circle, 'inStock'.tr());

    final bg = color.withValues(alpha: isOutOfStock ? 0.12 : isLowStock ? 0.16 : 0.12);
    final fg = isLowStock ? status.onWarning : status.onSuccess;

    return Semantics(
      label: label,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: fg == status.onSuccess ? color : fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
