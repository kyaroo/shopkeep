import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Pill stock badge — three encodings (icon + color + text) per spec.
/// Non-interactive; announces status via Semantics.
///
/// [showLabel] is false in the dense inventory row, where the badge shares the
/// subtitle line with the price and the stock count. There it renders as a
/// 28px icon chip: the row gives the line 199px, the subtitle text alone is
/// 161px, so a text pill (85px for "En stock") cannot fit and wraps the line —
/// and by a different amount per locale. The label is not lost: it stays in
/// [Semantics] and in the long-press tooltip.
class StockBadge extends StatelessWidget {
  final bool isOutOfStock;
  final bool isLowStock;
  final bool showLabel;

  const StockBadge({
    super.key,
    required this.isOutOfStock,
    required this.isLowStock,
    this.showLabel = true,
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

    if (!showLabel) {
      return Semantics(
        label: label,
        child: Tooltip(
          message: label,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );
    }

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
