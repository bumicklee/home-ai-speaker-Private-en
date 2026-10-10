# AI-PA (Flutter)

The setup and control app for the family AI speaker. You build it in Chapters 10–18 of the book. The book covers Android only.

```bash
flutter pub get
flutter analyze
flutter test
../scripts/run-flutter.sh android
```

- Each feature folder has three layers: `data`, `domain`, and `presentation` (Chapter 10).
- BLE constants live in one place only: `lib/core/constants/ble_protocol.dart`. Their values must match the firmware's `firmware/components/app_config/include/app_config.h` (Chapters 8 and 12, Appendix C).
- Put UI text in the per-feature files `lib/l10n/parts/<feature>_<language>.arb` and merge them with `python3 tool/merge_arb.py && flutter gen-l10n`.
- Generate the source images for the app icon and splash with `python3 tool/gen_brand_assets.py` (Chapter 11).
