# Live Training mobile app (Flutter)

See the top-level [README](../README.md) for setup and running on a phone.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Layout:

- `lib/sources/`: `MotionSource` interface, `PhoneMotionSource`, `WhoopHrSource` (standard BLE Heart Rate service)
- `lib/ble/heart_rate_parser.dart`: pure 0x2A37 parser
- `lib/recording/`: `SessionRecorder` (one Stopwatch, streams CSV to disk) and `csv_row.dart`
- `lib/services/`: settings, backend API, local session store
- `lib/screens/`: Home (Live), Sessions, Settings
