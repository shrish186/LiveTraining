import 'package:flutter/material.dart';

import '../coach/advice.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// A list of advice lines: coloured dot, title, detail. Optional trailing action (e.g. "Ask the coach").
class AdviceCard extends StatelessWidget {
  const AdviceCard({super.key, required this.advice, this.title = 'Advice', this.action});

  final List<Advice> advice;
  final String title;
  final Widget? action;

  static Color colorOf(AdviceLevel l) => switch (l) {
    AdviceLevel.good => AppColors.good,
    AdviceLevel.info => AppColors.accent,
    AdviceLevel.warn => AppColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title, trailing: const Icon(Icons.tips_and_updates_rounded, size: 16, color: AppColors.accent)),
          for (final a in advice) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: colorOf(a.level), shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(a.detail, style: AppText.dim),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}
