import 'package:flutter/material.dart';

import '../sources/sensor_link.dart';
import '../ui/theme.dart';

/// Bottom sheet that scans for our leg sensors and returns the one tapped (null if dismissed).
/// [scan] runs once when the sheet opens and again on "Scan again".
Future<FoundSensor?> showSensorPicker(
  BuildContext context, {
  required String title,
  required Future<List<FoundSensor>> Function() scan,
}) {
  return showModalBottomSheet<FoundSensor>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: _Picker(title: title, scan: scan),
    ),
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.title, required this.scan});

  final String title;
  final Future<List<FoundSensor>> Function() scan;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late Future<List<FoundSensor>> _found = widget.scan();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FoundSensor>>(
      future: _found,
      builder: (context, snapshot) {
        final found = snapshot.data;
        final scanning = snapshot.connectionState != ConnectionState.done;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          children: [
            Text(widget.title.toUpperCase(), style: AppText.label),
            const SizedBox(height: 12),
            if (scanning)
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
            else if (snapshot.hasError)
              Text('Bluetooth scan failed: ${snapshot.error}', style: AppText.dim)
            else if (found == null || found.isEmpty)
              const Text(
                'No sensors found. Switch the sensor on (LED blinking blue), hold it next to the phone, and check '
                'that Bluetooth is on.',
                style: AppText.dim,
              )
            else
              for (final s in found)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sensors_rounded, color: AppColors.accent),
                  title: Text(s.name, style: AppText.body),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
                  onTap: () => Navigator.pop(context, s),
                ),
            if (!scanning) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _found = widget.scan()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan again'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
