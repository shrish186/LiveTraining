import 'package:flutter/material.dart';

/// Shows `label: value`; tapping opens a list of options.
class OptionChip extends StatelessWidget {
  const OptionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
      onPressed: enabled
          ? () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                    ListTile(title: Text(label, style: Theme.of(context).textTheme.titleMedium)),
                    for (final o in options)
                      ListTile(
                        title: Text(o),
                        trailing: o == value ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(context, o),
                      ),
                  ]),
                ),
              );
              if (picked != null) onChanged(picked);
            }
          : null,
    );
  }
}

/// A dropdown form field for Settings.
class OptionDropdown extends StatelessWidget {
  const OptionDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = options.contains(value) ? options : [value, ...options];
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [for (final o in items) DropdownMenuItem(value: o, child: Text(o))],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}
