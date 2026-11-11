import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../coach/live_coach.dart';
import '../sources/sensor_link.dart';
import '../squad/squad_controller.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

String _clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// A net session for several players on one phone: give each player a sensor, start, and watch
/// every player's efforts, impact load and fatigue live.
class SquadScreen extends StatelessWidget {
  const SquadScreen({super.key, required this.squad, this.scanner});

  final SquadController squad;
  final SensorScanner? scanner;

  Future<void> _addPlayer(BuildContext context) async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add player'),
        content: TextField(
          controller: text,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Add')),
        ],
      ),
    );
    if (name != null) squad.addPlayer(name);
  }

  Future<void> _pickSensor(BuildContext context, SquadPlayer player) async {
    if (Platform.isAndroid) {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    }
    if (!context.mounted) return;
    final scan = (scanner ?? SensorScanner()).scan();
    final picked = await showModalBottomSheet<FoundSensor>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FutureBuilder<List<FoundSensor>>(
          future: scan,
          builder: (context, snapshot) {
            final found = snapshot.data;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              children: [
                Text('SENSOR FOR ${player.name.toUpperCase()}', style: AppText.label),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  Text('Bluetooth scan failed: ${snapshot.error}', style: AppText.dim)
                else if (found == null)
                  const Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                      ),
                      SizedBox(width: 12),
                      Text('Looking for sensors nearby…', style: AppText.dim),
                    ],
                  )
                else if (found.isEmpty)
                  const Text(
                    'No sensors found. Switch the sensor on (LED blinking) and hold it near the phone.',
                    style: AppText.dim,
                  )
                else
                  for (final s in found)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sensors_rounded, color: AppColors.accent),
                      title: Text(s.name, style: AppText.body),
                      onTap: () => Navigator.pop(context, s),
                    ),
              ],
            );
          },
        ),
      ),
    );
    if (picked != null) await squad.assign(player, SensorLink(picked));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: squad,
      builder: (context, _) {
        final recording = squad.isRecording;
        final withSensor = squad.players.where((p) => p.hasSensor).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ScreenHeader(
              overline: recording
                  ? 'Recording · ${_clock(squad.elapsed)}'
                  : '${squad.players.length} player${squad.players.length == 1 ? '' : 's'} · ${squad.ready} sensor${squad.ready == 1 ? '' : 's'} live',
              title: 'Squad',
            ),
            if (squad.players.isEmpty)
              const AppCard(
                child: Column(
                  children: [
                    Icon(Icons.groups_rounded, size: 40, color: AppColors.textFaint),
                    SizedBox(height: 12),
                    Text('No players yet', style: AppText.body),
                    SizedBox(height: 4),
                    Text(
                      'Add your players, give each one a sensor, and record everyone in one session.',
                      style: AppText.dim,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final p in squad.players) ...[
              _PlayerCard(squad: squad, player: p, onPickSensor: () => _pickSensor(context, p)),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            if (!recording) ...[
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    SettingRow(
                      icon: Icons.sports_rounded,
                      label: 'Sport',
                      value: squad.sport,
                      onTap: () async {
                        final v = await showOptionSheet(
                          context,
                          title: 'Sport',
                          options: sportOptions,
                          current: squad.sport,
                        );
                        if (v != null) squad.setSetup(sport: v);
                      },
                    ),
                    SettingRow(
                      icon: Icons.accessibility_new_rounded,
                      label: 'Sensor on',
                      value: squad.placement,
                      onTap: () async {
                        final v = await showOptionSheet(
                          context,
                          title: 'Sensor on',
                          options: const ['ankle', 'shin'],
                          current: squad.placement,
                        );
                        if (v != null) squad.setSetup(placement: v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _addPlayer(context),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add player'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: withSensor == 0 ? null : squad.start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(withSensor == 0 ? 'Give a player a sensor to start' : 'Start squad session ($withSensor)'),
              ),
            ] else ...[
              HoldToConfirmButton(label: 'Hold to stop', onConfirmed: squad.stop),
              const SizedBox(height: 8),
              const Center(child: Text('Keep the app open while recording', style: AppText.dim)),
            ],
          ],
        );
      },
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.squad, required this.player, required this.onPickSensor});

  final SquadController squad;
  final SquadPlayer player;
  final VoidCallback onPickSensor;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final link = p.link;
    final recording = squad.isRecording && p.recorder != null;
    final (color, status) = switch (link?.state) {
      null => (AppColors.textFaint, 'No sensor'),
      SensorState.connecting => (AppColors.warning, '${link!.sensor.name} · connecting…'),
      SensorState.lost => (AppColors.danger, '${link!.sensor.name} · out of range'),
      SensorState.live => (
        AppColors.good,
        '${link!.sensor.name}${link.decoder.lostPct >= 1 ? ' · ${link.decoder.lostPct.round()}% lost' : ''}',
      ),
    };
    final fatigue = p.fatigueEfforts > 0;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.body.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(status, style: AppText.dim, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (recording && fatigue)
                const StatusPill(color: AppColors.warning, text: 'Fatigue')
              else if (recording)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => squad.mark(p, 'mark'),
                  child: const Text('Mark'),
                )
              else if (squad.isRecording)
                const Text('Not in this session', style: AppText.dim)
              else ...[
                TextButton(onPressed: onPickSensor, child: Text(link == null ? 'Add sensor' : 'Change')),
                IconButton(
                  tooltip: 'Remove player',
                  onPressed: () => squad.removePlayer(p),
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textFaint),
                ),
              ],
            ],
          ),
          if (recording) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: p.actions != null
                      ? _Stat(label: _capitalized(p.actionsLabel!), value: '${p.actions}')
                      : _Stat(label: 'Efforts', value: '${p.efforts}'),
                ),
                Expanded(
                  child: _Stat(label: 'Impact', value: p.impactLoad?.round().toString() ?? '—'),
                ),
                Expanded(
                  child: _Stat(label: 'Motion', value: p.motion.toStringAsFixed(1)),
                ),
              ],
            ),
            if (p.lastCall != null) ...[
              const SizedBox(height: 10),
              Text(
                p.lastCall!.title,
                style: AppText.dim.copyWith(
                  color: p.lastCall!.type == CallType.fatigue ? AppColors.warning : AppColors.textDim,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.label),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppText.stat),
        ),
      ],
    );
  }
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
