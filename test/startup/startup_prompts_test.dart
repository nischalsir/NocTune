import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/startup/startup_prompts.dart';
import 'package:noctune/features/startup/update_dialog.dart';
import 'package:noctune/features/startup/update_service.dart';
import 'package:noctune/features/startup/welcome_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdatePrompt _prompt({bool required = false}) => UpdatePrompt(
  release: ReleaseInfo(
    version: const AppVersion(1, 2, 0),
    url: Uri.parse('https://example.com/release'),
  ),
  installed: const AppVersion(1, 0, 0),
  required: required,
);

void main() {
  late SharedPreferences prefs;
  late List<String> events;
  late bool mainScreenInFront;
  UpdatePrompt? available;
  Completer<void>? welcomeOpen;

  Future<void> start({bool welcomeSeen = false}) async {
    SharedPreferences.setMockInitialValues({
      if (welcomeSeen) 'welcome_seen': true,
    });
    prefs = await SharedPreferences.getInstance();
    events = [];
    mainScreenInFront = true;
    available = null;
    welcomeOpen = null;
  }

  StartupPrompts prompts() => StartupPrompts(
    welcome: WelcomeStore(prefs),
    checkForUpdate: () async {
      events.add('check');
      return available;
    },
    showWelcome: () async {
      events.add('welcome shown');
      await welcomeOpen?.future;
      events.add('welcome closed');
    },
    showUpdate: (prompt) async {
      events.add('update shown');
      return UpdateChoice.later;
    },
    canInterrupt: () => mainScreenInFront,
    onUpdateChoice: (prompt, choice) async => events.add('chose $choice'),
  );

  test('a new installation sees the welcome once', () async {
    await start();

    await prompts().run();
    expect(events, contains('welcome shown'));
    expect(WelcomeStore(prefs).isPending, isFalse);

    events.clear();
    await prompts().run();
    expect(events, isNot(contains('welcome shown')));
  });

  test('an ordinary restart does not show the welcome', () async {
    await start(welcomeSeen: true);

    await prompts().run();

    expect(events, ['check']);
  });

  test('a welcome cut short by closing the app is not repeated', () async {
    await start();
    welcomeOpen = Completer<void>();

    unawaited(prompts().run());
    await pumpEventQueue();
    // The process dies here with the welcome still open.

    expect(WelcomeStore(prefs).isPending, isFalse);
  });

  test('the update waits until the welcome has been closed', () async {
    await start();
    available = _prompt();
    welcomeOpen = Completer<void>();

    final running = prompts().run();
    await pumpEventQueue();
    expect(events, ['welcome shown']);

    welcomeOpen!.complete();
    await running;
    expect(events, [
      'welcome shown',
      'welcome closed',
      'check',
      'update shown',
      'chose UpdateChoice.later',
    ]);
  });

  test('no update popup when the app is up to date', () async {
    await start(welcomeSeen: true);

    await prompts().run();

    expect(events, isNot(contains('update shown')));
  });

  test('an optional update does not cover something in front', () async {
    await start(welcomeSeen: true);
    available = _prompt();
    mainScreenInFront = false;

    await prompts().run();

    expect(events, ['check']);
  });

  test('a required update is shown even then', () async {
    await start(welcomeSeen: true);
    available = _prompt(required: true);
    mainScreenInFront = false;

    await prompts().run();

    expect(events, contains('update shown'));
  });

  test('running again, as on resume, shows nothing twice', () async {
    await start(welcomeSeen: true);
    available = _prompt();
    final startup = prompts();

    await Future.wait([startup.run(), startup.run()]);
    await startup.run();

    expect(events.where((event) => event == 'update shown'), hasLength(1));
  });
}
