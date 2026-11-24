import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/device_profile.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/widgets/frosted.dart';
import 'package:noctune/core/widgets/light_effects.dart';
import 'package:noctune/core/widgets/wave_bars.dart';
import 'package:noctune/features/playback/player_glass_button.dart';
import 'package:noctune/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget page({required bool light}) => MaterialApp(
    theme: buildNocTheme(Brightness.dark, NocAccent.red),
    home: LightEffects(
      on: light,
      child: Scaffold(
        body: Column(
          children: [
            const Frosted(blurBackdrop: true, child: Text('pill')),
            PlayerGlassButton(
              icon: Icons.queue_music,
              label: 'Queue',
              frosted: true,
              onTap: () {},
            ),
            const WaveBars(playing: true, color: Colors.white),
          ],
        ),
      ),
    ),
  );

  testWidgets('full effects blur behind glass and keep the bars moving', (
    tester,
  ) async {
    await tester.pumpWidget(page(light: false));

    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('lighter effects blur nothing and hold the bars still', (
    tester,
  ) async {
    await tester.pumpWidget(page(light: true));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('pill'), findsOneWidget);
    expect(find.byTooltip('Queue'), findsOneWidget);
  });

  group('lightEffectsProvider', () {
    Future<ProviderContainer> container(
      Map<String, Object> stored, {
      DeviceTier tier = DeviceTier.high,
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceTierProvider.overrideWithBuild((ref, _) => tier),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('follows the device until the user chooses', () async {
      expect(
        (await container({}, tier: DeviceTier.low)).read(lightEffectsProvider),
        isTrue,
      );
      expect(
        (await container(
          {},
          tier: DeviceTier.standard,
        )).read(lightEffectsProvider),
        isFalse,
      );
    });

    test('the choice in Settings wins either way', () async {
      final low = await container({}, tier: DeviceTier.low);
      low.read(settingsProvider.notifier).setLightEffects(false);
      expect(low.read(lightEffectsProvider), isFalse);

      final high = await container({}, tier: DeviceTier.high);
      high.read(settingsProvider.notifier).setLightEffects(true);
      expect(high.read(lightEffectsProvider), isTrue);
    });
  });
}
