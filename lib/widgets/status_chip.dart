import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final Invoice invoice;
  final bool dense;

  const StatusChip({super.key, required this.invoice, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (label, color) = invoice.paid
        ? ('Pagada', c.paid)
        : invoice.isOverdue
            ? ('Vencida', c.overdue)
            : invoice.isPartiallyPaid
                ? ('Con abonos', c.partial)
                : ('Pendiente', c.pending);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: dense ? 11.5 : 13,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
