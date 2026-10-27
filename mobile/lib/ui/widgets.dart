import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Rounded dark surface every section sits on.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Caps label with an optional widget at the right end.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(text.toUpperCase(), style: AppText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        ?trailing,
      ],
    );
  }
}

/// Large screen title with an optional subtitle, used at the top of each tab.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.overline, this.trailing});

  final String title;
  final String? overline;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) Text(overline!.toUpperCase(), style: AppText.label),
                if (overline != null) const SizedBox(height: 4),
                Text(title, style: AppText.title),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Circular progress ring with rounded ends (0..1), with a child in the middle.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    required this.color,
    required this.child,
    this.size = 140,
    this.thickness = 12,
  });

  final double? value;
  final Color color;
  final Widget child;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (value ?? 0).clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(v, color, thickness),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.thickness);

  final double value;
  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(thickness / 2);
    final track = Paint()
      ..color = AppColors.surfaceHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = thickness;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// Minimal line chart of recent values; gaps (null) break the line. Auto-scales with padding.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.height = 56, this.minSpan = 4});

  final List<double?> values;
  final Color color;
  final double height;

  /// Smallest vertical range shown, so a nearly flat signal stays flat instead of jittering.
  final double minSpan;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color, minSpan)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.minSpan);

  final List<double?> values;
  final Color color;
  final double minSpan;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>();
    if (values.length < 2 || present.isEmpty) {
      final dash = Paint()
        ..color = AppColors.outline
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), dash);
      return;
    }
    var lo = present.reduce(math.min);
    var hi = present.reduce(math.max);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    final dx = size.width / (values.length - 1);
    double y(double v) => size.height - 3 - (v - lo) / (hi - lo) * (size.height - 6);

    final line = Path();
    final fill = Path();
    var drawing = false;
    double? lastX;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final x = i * dx;
      if (v == null) {
        if (drawing && lastX != null) fill.lineTo(lastX, size.height);
        drawing = false;
        continue;
      }
      if (!drawing) {
        line.moveTo(x, y(v));
        fill
          ..moveTo(x, size.height)
          ..lineTo(x, y(v));
        drawing = true;
      } else {
        line.lineTo(x, y(v));
        fill.lineTo(x, y(v));
      }
      lastX = x;
    }
    if (drawing && lastX != null) fill.lineTo(lastX, size.height);

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

/// Small rounded status chip: coloured dot + text.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.color, required this.text, this.onTap});

  final Color color;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                text,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Caps label over a number with a unit, for stat grids.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.color});

  final String label;
  final String value;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppText.label),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppText.stat.copyWith(color: color),
                ),
                if (unit != null) TextSpan(text: ' $unit', style: AppText.unit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable "label …… value ›" row.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.icon, required this.label, required this.value, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textDim),
            const SizedBox(width: 12),
            Text(label, style: AppText.body.copyWith(color: AppColors.textDim)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                prettySlug(value),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppColors.text : AppColors.textFaint,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: enabled ? AppColors.textDim : AppColors.outline),
          ],
        ),
      ),
    );
  }
}

/// `phone_armband` -> `Phone armband`.
String prettySlug(String slug) {
  final s = slug.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Bottom sheet list of options; returns the picked one.
Future<String?> showOptionSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title.toUpperCase(), style: AppText.label),
          ),
          for (final o in options)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(prettySlug(o), style: AppText.body),
              trailing: o == current ? const Icon(Icons.check_rounded, color: AppColors.accent) : null,
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
    ),
  );
}

/// Press and hold for [holdFor] to trigger. The fill shows progress; letting go early cancels.
/// Used for Stop, so a pocket or armband touch can't end a session.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = AppColors.danger,
    this.holdFor = const Duration(milliseconds: 900),
  });

  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final Duration holdFor;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.holdFor)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onConfirmed();
        _c.value = 0;
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(shape: const StadiumBorder(), color: widget.color.withValues(alpha: 0.18)),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: _c.value,
                child: Container(color: widget.color),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_rounded, color: _c.value > 0.5 ? AppColors.background : widget.color),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _c.value > 0.5 ? AppColors.background : widget.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
