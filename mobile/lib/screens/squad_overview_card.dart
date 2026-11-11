import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_controller.dart';
import '../coach/advice.dart';
import '../squad/squad_overview.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'advice_card.dart';
import 'trends_screen.dart';

/// The coach's dashboard: every player's week at a glance, who needs a look first.
class SquadOverviewCard extends StatelessWidget {
  const SquadOverviewCard({super.key, required this.controller});

  final AppController controller;

  List<PlayerOverview> get _overview => squadOverview([
    for (final s in controller.sessions)
      if (s.player != null && s.anyEntry != null) (s.player!, s.anyEntry!),
  ], DateTime.now());

  /// The week as a CSV the coach can send on (WhatsApp, email, a spreadsheet).
  static String weekCsv(List<PlayerOverview> players) {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final label = players.map((p) => p.trends.actionsLabel).whereType<String>().firstOrNull ?? 'actions';
    final rows = [
      'player,sessions_7d,${label}_7d,usual_${label}_week,load_7d,usual_load_week,last_landing_held_pct,flags',
      for (final p in players)
        [
          q(p.name),
          p.thisWeek.sessions,
          p.thisWeek.actions,
          p.usualWeeklyActions?.round() ?? '',
          p.thisWeek.load.toStringAsFixed(1),
          p.usualWeeklyLoad?.toStringAsFixed(1) ?? '',
          p.lastHeldPct?.round() ?? '',
          q(p.flags.map((f) => f.text).join('; ')),
        ].join(','),
    ];
    return '${rows.join('\n')}\n';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final players = _overview;
        if (players.isEmpty) return const SizedBox.shrink();
        final needLook = players.where((p) => p.status == AdviceLevel.warn).length;
        return AppCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SectionLabel(
                  'This week',
                  trailing: Text(
                    needLook == 0 ? 'All on track' : '$needLook need${needLook == 1 ? 's' : ''} a look',
                    style: AppText.dim.copyWith(color: needLook == 0 ? AppColors.good : AppColors.warning),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              for (final p in players) _PlayerRow(player: p),
              Align(
                alignment: Alignment.centerRight,
                child: Builder(
                  builder: (context) => TextButton.icon(
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      SharePlus.instance.share(
                        ShareParams(
                          text: weekCsv(players),
                          subject: 'Squad week',
                          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                        ),
                      );
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share the week'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final PlayerOverview player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final color = AdviceCard.colorOf(p.status);
    final usual = p.usualWeeklyActions;
    final label = p.trends.actionsLabel;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrendsScreen(trends: p.trends, title: p.name),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Text(
                p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                style: AppText.body.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    p.flags.first.text,
                    style: AppText.dim.copyWith(color: p.status == AdviceLevel.good ? AppColors.textDim : color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  label != null ? '${p.thisWeek.actions}' : p.thisWeek.load.toStringAsFixed(0),
                  style: AppText.stat.copyWith(fontSize: 20),
                ),
                Text(
                  label != null
                      ? (usual == null ? label : 'of ~${usual.round()}')
                      : (p.usualWeeklyLoad == null ? 'load' : 'of ~${p.usualWeeklyLoad!.round()}'),
                  style: AppText.dim.copyWith(fontSize: 12),
                ),
              ],
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
