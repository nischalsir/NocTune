import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../third_party/spotiflac/runtime_profile_provider.dart';
import '../features/settings/settings_controller.dart';
import 'providers.dart';

const _channel = MethodChannel('noctune/device_profile');
// v2: the low tier now reaches 4 GB phones, so every device measures again.
const _tierKey = 'device_tier_v2';

/// How much visual effect this device is given.
enum DeviceTier { low, standard, high }

/// The tier for a device: low when it is 32-bit only or has 4 GB of memory
/// or less (a 4 GB phone reports a little under 4096 MB), high from 6 GB
/// up, standard in between.
DeviceTier tierFor({
  required bool lowRam,
  required int totalMb,
  required bool has64Bit,
}) {
  if (!has64Bit || lowRam || totalMb <= 4200) return DeviceTier.low;
  return totalMb >= 6000 ? DeviceTier.high : DeviceTier.standard;
}

/// This device's tier. It is worked out once and remembered; until the
/// first answer arrives the device is treated as standard.
class DeviceTierController extends Notifier<DeviceTier> {
  @override
  DeviceTier build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final known = DeviceTier.values.asNameMap()[prefs.getString(_tierKey)];
    if (known != null) return known;
    if (Platform.isAndroid) _measure();
    return DeviceTier.standard;
  }

  Future<void> _measure() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('memory');
      if (info == null || !ref.mounted) return;
      final tier = tierFor(
        lowRam: info['lowRam'] as bool? ?? false,
        totalMb: info['totalMb'] as int? ?? 0,
        has64Bit: info['has64Bit'] as bool? ?? true,
      );
      await ref.read(sharedPreferencesProvider).setString(_tierKey, tier.name);
      if (ref.mounted) state = tier;
    } on PlatformException {
      // Stays standard; asked again at the next launch.
    } on MissingPluginException {
      // As above.
    }
  }
}

final deviceTierProvider = NotifierProvider<DeviceTierController, DeviceTier>(
  DeviceTierController.new,
);

/// Whether the app draws with lighter effects (see `LightEffects`): as the
/// user chose in Settings, or else on low-tier devices.
final lightEffectsProvider = Provider<bool>((ref) {
  final chosen = ref.watch(settingsProvider.select((s) => s.lightEffects));
  return chosen ?? ref.watch(deviceTierProvider) == DeviceTier.low;
});

/// Hands the navigation bar's glass the tier of this device, by the rule its
/// source app uses: flat surfaces on low-tier devices, frosted on standard
/// Android devices, and the full refracting glass on high-tier Android
/// devices and everywhere else.
final deviceProfileOverrides = [
  lowEndDeviceProvider.overrideWith((ref) => ref.watch(lightEffectsProvider)),
  deviceSupportsBackdropBlurProvider.overrideWith(
    (ref) =>
        !ref.watch(lightEffectsProvider) &&
        ref.watch(deviceTierProvider) == DeviceTier.high,
  ),
  deviceSupportsLiquidGlassProvider.overrideWith(
    (ref) =>
        !ref.watch(lightEffectsProvider) &&
        (!Platform.isAndroid ||
            ref.watch(deviceTierProvider) == DeviceTier.high),
  ),
];
