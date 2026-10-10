import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import 'update_dialog.dart';
import 'update_service.dart';
import 'welcome_dialog.dart';

/// Shows the popups that can appear at launch, strictly one at a time: the
/// first-run welcome, then an update notice if there is one. It runs after
/// the app is usable, and has no connection to the audio engine, so playback
/// carries on whatever it shows.
class StartupPrompts {
  StartupPrompts({
    required this.welcome,
    required this.checkForUpdate,
    required this.showWelcome,
    required this.showUpdate,
    required this.canInterrupt,
    required this.onUpdateChoice,
  });

  final WelcomeStore welcome;

  /// Resolves to the update to announce, or null.
  final Future<UpdatePrompt?> Function() checkForUpdate;
  final Future<void> Function() showWelcome;
  final Future<UpdateChoice?> Function(UpdatePrompt prompt) showUpdate;

  /// Whether a popup may appear right now: the main screen is in front, with
  /// no player, sheet or other dialog over it.
  final bool Function() canInterrupt;
  final Future<void> Function(UpdatePrompt prompt, UpdateChoice? choice)
  onUpdateChoice;

  bool _started = false;

  /// Runs the sequence once. Later calls, for example from the app being
  /// resumed, do nothing, so a popup can never be stacked on itself.
  Future<void> run() async {
    if (_started) return;
    _started = true;

    if (welcome.isPending) {
      // Recorded before showing: a welcome interrupted by the app being
      // closed is not shown a second time.
      await welcome.markSeen();
      if (canInterrupt()) await showWelcome();
    }

    final prompt = await checkForUpdate();
    if (prompt == null) return;
    // A required update is shown regardless; an optional one waits for a
    // launch where it wouldn't cover something the user is doing.
    if (!prompt.required && !canInterrupt()) return;
    await onUpdateChoice(prompt, await showUpdate(prompt));
  }
}

/// The installed app version, read from the platform package.
final installedVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion.tryParse(
        info.version,
        build: int.tryParse(info.buildNumber) ?? 0,
      ) ??
      const AppVersion(0, 0, 0);
});

final updateServiceProvider = FutureProvider<UpdateService>(
  (ref) async => UpdateService(
    manifestUrl: kUpdateManifestUrl,
    installed: await ref.watch(installedVersionProvider.future),
    preferences: ref.watch(sharedPreferencesProvider),
    isIos: Platform.isIOS,
  ),
);

/// Carries out what the user chose in the update popup.
Future<void> applyUpdateChoice(
  UpdateService service,
  UpdatePrompt prompt,
  UpdateChoice? choice,
) async {
  switch (choice) {
    case UpdateChoice.updateNow:
      // Hands the official page to the browser or store app. NocTune itself
      // downloads and installs nothing.
      await launchUrl(prompt.release.url, mode: LaunchMode.externalApplication);
    case UpdateChoice.dontRemind:
      await service.skip(prompt.release);
    // Dismissing an optional update by tapping outside counts as "Later".
    case UpdateChoice.later || null:
      if (!prompt.required) await service.remindLater(prompt.release);
  }
}
