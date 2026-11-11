import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../readiness/jump_test.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The 30-second readiness check: three jumps, scored against your usual.
class JumpTestScreen extends StatefulWidget {
  const JumpTestScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<JumpTestScreen> createState() => _JumpTestScreenState();
}

class _JumpTestScreenState extends State<JumpTestScreen> {
  AppController get c => widget.controller;

  @override
  void dispose() {
    // Leaving mid-check throws it away; a finished one is already saved.
    if (c.jumpRun != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.cancelJumpTest());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Readiness check'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final run = c.jumpRun;
            if (run == null) return _Intro(controller: c);
            if (!run.done) return _Running(run: run, onCancel: c.cancelJumpTest);
            return _Result(controller: c, run: run);
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sensor = controller.sensorLive;
    final n = controller.jumpConfig?.jumps ?? 3;
    Widget step(int i, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Text(
              '$i',
              style: AppText.body.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text, style: AppText.body),
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('$n jumps, 30 seconds', style: AppText.title),
        const SizedBox(height: 6),
        const Text(
          'Do it at the same time each day, before training. How high you jump compared with your usual is a '
          'simple, well-tested readiness marker.',
          style: AppText.dim,
        ),
        const SizedBox(height: 24),
        step(
          1,
          sensor ? 'Sensor on your ankle, as for training.' : 'No sensor: hold the phone firmly against your hip.',
        ),
        step(2, 'Hands on hips. Stand still for 2 seconds.'),
        step(3, 'Dip and jump as high as you can. Land on both feet and stand still again.'),
        step(4, 'Repeat until all $n jumps are counted.'),
        const SizedBox(height: 12),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: controller.startJumpTest,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Start the check'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          sensor
              ? 'Measured with ${controller.sensor!.sensor.name}.'
              : 'Measured with the phone. Checks with the phone and with the sensor are compared separately.',
          style: AppText.dim,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.run, required this.onCancel});

  final JumpTestRun run;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final n = run.cfg.jumps;
    final done = run.jumps.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          const Spacer(),
          Text(done == 0 ? 'Stand still…' : 'Jump ${done + 1} of $n', style: AppText.title),
          const SizedBox(height: 6),
          const Text('Still for 2 s, then jump as high as you can', style: AppText.dim),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < n; i++)
                Container(
                  width: 84,
                  height: 84,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i < done ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: i == done ? AppColors.brand : AppColors.outline, width: 1.5),
                  ),
                  child: i < done
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              run.jumps[i].heightCm.toStringAsFixed(0),
                              style: AppText.big.copyWith(color: AppColors.onBrand, fontSize: 30),
                            ),
                            Text('cm', style: AppText.dim.copyWith(color: AppColors.onBrand)),
                          ],
                        )
                      : Text('${i + 1}', style: AppText.big.copyWith(color: AppColors.textFaint)),
                ),
            ],
          ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (run.elapsedS / run.cfg.maxSeconds).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text('${(run.cfg.maxSeconds - run.elapsedS).clamp(0, 999).round()} s left', style: AppText.dim),
          const Spacer(),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.controller, required this.run});

  final AppController controller;
  final JumpTestRun run;

  @override
  Widget build(BuildContext context) {
    final r = run.result;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty_rounded, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 12),
            const Text('No jumps counted', style: AppText.title),
            const SizedBox(height: 6),
            const Text(
              'Stand completely still for 2 seconds before each jump, and again after landing.',
              style: AppText.dim,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: controller.startJumpTest, child: const Text('Try again')),
          ],
        ),
      );
    }
    final v = jumpVerdict(r, controller.jumpTests, run.cfg);
    final color = switch (v.state) {
      JumpReadiness.below => AppColors.warning,
      JumpReadiness.noBaseline => AppColors.accent,
      _ => AppColors.good,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Center(
          child: ArcGauge(
            value: v.pct == null ? 1 : v.pct! / 120,
            marker: v.pct == null ? null : 100 / 120,
            colors: v.state == JumpReadiness.below
                ? const [AppColors.warning, AppColors.warning]
                : const [Color(0xFF6FE3B4), AppColors.brand],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      v.pct == null ? r.scoreCm.toStringAsFixed(0) : '${v.pct!.round()}',
                      style: AppText.hero.copyWith(fontSize: 58),
                    ),
                    Text(v.pct == null ? 'cm' : '%', style: AppText.stat.copyWith(color: AppColors.textDim)),
                  ],
                ),
                Text('Readiness', style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          v.title,
          textAlign: TextAlign.center,
          style: AppText.title.copyWith(fontSize: 22, color: color),
        ),
        const SizedBox(height: 6),
        Text(v.advice, textAlign: TextAlign.center, style: AppText.body),
        const SizedBox(height: 24),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Your jumps'),
              const SizedBox(height: 10),
              for (var i = 0; i < r.heightsCm.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text('Jump ${i + 1}', style: AppText.dim.copyWith(fontSize: 14))),
                      Text('${r.heightsCm[i].toStringAsFixed(1)} cm', style: AppText.body),
                    ],
                  ),
                ),
              const Divider(color: AppColors.outline),
              Row(
                children: [
                  Expanded(child: Text('Score (best two)', style: AppText.dim.copyWith(fontSize: 14))),
                  Text('${r.scoreCm.toStringAsFixed(1)} cm', style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              if (v.usualCm != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text('Your usual', style: AppText.dim.copyWith(fontSize: 14))),
                      Text('${v.usualCm!.toStringAsFixed(1)} cm', style: AppText.body),
                    ],
                  ),
                ),
              if (run.timedOut)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Only ${r.heightsCm.length} of ${run.cfg.jumps} jumps counted before the time ran out.',
                    style: AppText.dim.copyWith(color: AppColors.warning),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            controller.cancelJumpTest(); // clears the finished run; the result is already saved
            Navigator.of(context).pop();
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
