import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// What to show for a Bluetooth adapter state, or null when Bluetooth is ready (or still unknown).
String? bleStatusMessage(BleStatus status, {required bool isIOS}) => switch (status) {
      BleStatus.ready || BleStatus.unknown => null,
      BleStatus.poweredOff => isIOS
          ? 'Bluetooth is off. Turn it on in Control Center or Settings › Bluetooth.'
          : 'Bluetooth is off. Turn it on in Quick Settings.',
      BleStatus.unauthorized => isIOS
          ? 'Bluetooth permission denied. Allow it in Settings › Privacy & Security › Bluetooth › Live Training.'
          : 'Bluetooth permission denied. Allow "Nearby devices" in Settings › Apps › Live Training › Permissions.',
      BleStatus.unsupported => 'This device does not support Bluetooth Low Energy.',
      BleStatus.locationServicesDisabled =>
        'Location is off. This Android version needs Location on to scan for Bluetooth devices.',
    };

/// Whether the fix is in the system Settings app (so the UI can offer an "Open Settings" button).
bool bleStatusNeedsSettings(BleStatus status) => status == BleStatus.unauthorized;

const hrNotFoundMessage = 'No WHOOP heart-rate broadcast found.\n'
    '• In the WHOOP app, turn on Heart Rate Broadcast (device settings)\n'
    '• Wear the strap (it only broadcasts while on your wrist or body)\n'
    '• Keep the phone close, then tap Connect again';
