import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/startup/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = 'https://example.com/noctune/update.json';

String _manifest({
  String version = '1.2.0',
  int? build,
  String url = 'https://example.com/noctune/releases/1.2.0',
  String? minSupported,
  bool mandatory = false,
  List<String> notes = const ['Synchronised lyrics'],
}) =>
    '{"version": "$version", ${build == null ? '' : '"build": $build, '}'
    '"url": "$url", "mandatory": $mandatory, '
    '${minSupported == null ? '' : '"minSupported": "$minSupported", '}'
    '"notes": [${notes.map((n) => '"$n"').join(', ')}]}';

/// One release as GitHub's release list describes it.
String _gitHubRelease(String tag, {bool prerelease = false}) =>
    '{"tag_name": "$tag", "prerelease": $prerelease, "draft": false, '
    '"html_url": "https://github.com/nischalsir/NocTune/releases/tag/$tag", '
    '"body": "- Notes for $tag"}';

String _gitHubList(List<String> releases) => '[${releases.join(', ')}]';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late int fetches;
  Uri? fetched;
  String? served;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 10, 12);
    fetches = 0;
    served = _manifest();
  });

  UpdateService service({
    String manifestUrl = _url,
    AppVersion installed = const AppVersion(1, 0, 0, 1),
  }) => UpdateService(
    manifestUrl: manifestUrl,
    installed: installed,
    preferences: prefs,
    isIos: false,
    now: () => now,
    fetch: (url) async {
      fetches++;
      fetched = url;
      final body = served;
      if (body == null) throw const SocketException('offline');
      return body;
    },
  );

  group('AppVersion', () {
    test('parses common forms', () {
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('v2.0'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3, 45));
      expect(
        AppVersion.tryParse('1.2.3', build: 9),
        const AppVersion(1, 2, 3, 9),
      );
    });

    test('rejects text that is not a version', () {
      for (final text in ['', 'latest', '1', '1.2.3-beta', '1.x.0']) {
        expect(AppVersion.tryParse(text), isNull, reason: text);
      }
    });

    test('orders numerically, then by build', () {
      expect(const AppVersion(1, 9, 0) < const AppVersion(1, 10, 0), isTrue);
      expect(const AppVersion(2, 0, 0) < const AppVersion(1, 99, 99), isFalse);
      expect(
        const AppVersion(1, 0, 0, 3) < const AppVersion(1, 0, 0, 4),
        isTrue,
      );
      expect(const AppVersion(1, 0, 0) < const AppVersion(1, 0, 0), isFalse);
    });
  });

  group('manifest', () {
    test('reads version, link, notes and policy', () {
      final release = ReleaseInfo.fromManifest(
        _manifest(build: 12, minSupported: '1.1.0', mandatory: true),
        isIos: false,
      );

      expect(release.version, const AppVersion(1, 2, 0, 12));
      expect(release.url.host, 'example.com');
      expect(release.notes, ['Synchronised lyrics']);
      expect(release.minSupported, const AppVersion(1, 1, 0));
      expect(release.mandatory, isTrue);
    });

    test('uses the platform link when one is given', () {
      const body =
          '{"version": "1.2.0", "url": "https://example.com/a", '
          '"iosUrl": "https://apps.apple.com/app/id1"}';

      expect(
        ReleaseInfo.fromManifest(body, isIos: true).url.host,
        'apps.apple.com',
      );
      expect(
        ReleaseInfo.fromManifest(body, isIos: false).url.host,
        'example.com',
      );
    });

    test('rejects malformed or unsafe manifests', () {
      for (final body in [
        'not json',
        '[]',
        '{"url": "https://example.com/a"}',
        '{"version": "newest", "url": "https://example.com/a"}',
        '{"version": "1.2.0"}',
        '{"version": "1.2.0", "url": "http://example.com/a"}',
        '{"version": "1.2.0", "url": "file:///sdcard/app.apk"}',
      ]) {
        expect(
          () => ReleaseInfo.fromManifest(body, isIos: false),
          throwsFormatException,
          reason: body,
        );
      }
    });

    group('GitHub release', () {
      const release =
          '{"tag_name": "v1.2.0", '
          '"html_url": "https://github.com/nischalsir/NocTune/releases/tag/v1.2.0", '
          r'"body": "## What is new\n- Synchronised lyrics\n* Lossless badge\n\nThanks!"}';

      test('reads the tag, page link and bulleted notes', () {
        final info = ReleaseInfo.fromManifest(release, isIos: false);

        expect(info.version, const AppVersion(1, 2, 0));
        expect(info.url.path, '/nischalsir/NocTune/releases/tag/v1.2.0');
        expect(info.notes, ['Synchronised lyrics', 'Lossless badge']);
        expect(info.mandatory, isFalse);
      });

      test('rejects a tag that is not a version or a foreign link', () {
        for (final body in [
          '{"tag_name": "nightly", "html_url": "https://github.com/a/b"}',
          '{"tag_name": "v1.2.0"}',
          '{"tag_name": "v1.2.0", "html_url": "https://evil.example/a"}',
        ]) {
          expect(
            () => ReleaseInfo.fromManifest(body, isIos: false),
            throwsFormatException,
            reason: body,
          );
        }
      });

      test('the build that made a release is not offered that release', () {
        // Installed 1.2.0+7; the tag carries no build number.
        final info = ReleaseInfo.fromManifest(release, isIos: false);

        expect(const AppVersion(1, 2, 0, 7) < info.version, isFalse);
        expect(const AppVersion(1, 1, 9, 7) < info.version, isTrue);
      });
    });

    group('GitHub release list', () {
      test('reads the newest stable release and lists the published ones', () {
        final info = ReleaseInfo.fromManifest(
          _gitHubList([
            _gitHubRelease('v1.4.0', prerelease: true),
            _gitHubRelease('v1.3.0'),
            _gitHubRelease('v1.2.0'),
          ]),
          isIos: false,
        );

        expect(info.version, const AppVersion(1, 3, 0));
        expect(info.notes, ['Notes for v1.3.0']);
        expect(info.published, const [
          AppVersion(1, 3, 0),
          AppVersion(1, 2, 0),
        ]);
      });

      test('rejects a list with no stable release', () {
        expect(
          () => ReleaseInfo.fromManifest(
            _gitHubList([_gitHubRelease('v1.4.0', prerelease: true)]),
            isIos: false,
          ),
          throwsFormatException,
        );
      });
    });

    test('keeps release notes short', () {
      final release = ReleaseInfo.fromManifest(
        _manifest(notes: [for (var i = 0; i < 9; i++) 'Note $i', 'x' * 400]),
        isIos: false,
      );

      expect(release.notes, hasLength(5));
    });
  });

  group('checking', () {
    test('does nothing at all when no update address is set', () async {
      final updates = service(manifestUrl: '');

      expect(updates.isConfigured, isFalse);
      expect(await updates.check(), isNull);
      expect(fetches, 0);
    });

    test('refuses a plain-HTTP update address', () async {
      expect(
        await service(manifestUrl: 'http://example.com/u.json').check(),
        isNull,
      );
      expect(fetches, 0);
    });

    test('announces a newer release as optional', () async {
      final prompt = await service().check();

      expect(prompt!.release.version.label, '1.2.0');
      expect(prompt.installed.label, '1.0.0');
      expect(prompt.required, isFalse);
    });

    test('stays quiet when the app is current or ahead', () async {
      expect(
        await service(installed: const AppVersion(1, 2, 0)).check(),
        isNull,
      );
      expect(
        await service(installed: const AppVersion(2, 0, 0)).check(),
        isNull,
      );
    });

    test('a newer build of the same version counts as an update', () async {
      served = _manifest(version: '1.0.0', build: 5);

      expect(await service().check(), isNotNull);
    });

    test('requires the update when the release says so', () async {
      served = _manifest(mandatory: true);

      expect((await service().check())!.required, isTrue);
    });

    test('requires the update below the minimum supported version', () async {
      served = _manifest(minSupported: '1.1.0');

      expect((await service().check())!.required, isTrue);
      expect(
        (await service(installed: const AppVersion(1, 1, 0)).check())!.required,
        isFalse,
      );
    });

    group('three releases behind', () {
      const latest =
          'https://api.github.com/repos/nischalsir/NocTune/releases/latest';

      setUp(() {
        served = _gitHubList([
          _gitHubRelease('v1.3.0'),
          _gitHubRelease('v1.2.0'),
          _gitHubRelease('v1.1.0'),
          _gitHubRelease('v1.0.0'),
        ]);
      });

      test('a GitHub address asks for the recent releases', () async {
        await service(manifestUrl: latest).check();

        expect(
          fetched.toString(),
          'https://api.github.com/repos/nischalsir/NocTune/releases?per_page=5',
        );
      });

      test('three or more releases behind must update', () async {
        final prompt = await service(
          manifestUrl: latest,
          installed: const AppVersion(1, 0, 0, 1),
        ).check();

        expect(prompt!.release.version, const AppVersion(1, 3, 0));
        expect(prompt.required, isTrue);
      });

      test('one or two releases behind stays optional', () async {
        for (final installed in const [
          AppVersion(1, 1, 0),
          AppVersion(1, 2, 0),
        ]) {
          final prompt = await service(
            manifestUrl: latest,
            installed: installed,
          ).checkNow();
          expect(prompt.update!.required, isFalse, reason: '$installed');
        }
      });

      test('checking by hand applies the same rule', () async {
        final result = await service(
          manifestUrl: latest,
          installed: const AppVersion(1, 0, 0),
        ).checkNow();

        expect(result.update!.required, isTrue);
      });
    });

    test('stays quiet offline with nothing cached', () async {
      served = null;

      expect(await service().check(), isNull);
    });

    test('ignores a malformed manifest and keeps the last good one', () async {
      await service().check();
      now = now.add(const Duration(days: 1));
      served = '{"version": "oops"}';

      final prompt = await service().check();

      expect(prompt!.release.version.label, '1.2.0');
    });

    test('reuses a recent result instead of downloading again', () async {
      await service().check();
      now = now.add(const Duration(hours: 1));
      await service().check();
      expect(fetches, 1);

      now = now.add(const Duration(hours: 12));
      await service().check();
      expect(fetches, 2);
    });

    test('falls back to the cached release when offline later', () async {
      await service().check();
      now = now.add(const Duration(days: 2));
      served = null;

      expect(await service().check(), isNotNull);
    });

    test('simultaneous checks share one request', () async {
      final updates = service();

      final results = await Future.wait([updates.check(), updates.check()]);

      expect(fetches, 1);
      expect(results.every((prompt) => prompt != null), isTrue);
    });
  });

  group('reminders', () {
    test('"Later" silences the version for three days', () async {
      final updates = service();
      await updates.remindLater((await updates.check())!.release);

      now = now.add(const Duration(days: 2));
      expect(await service().check(), isNull);

      now = now.add(const Duration(days: 2));
      expect(await service().check(), isNotNull);
    });

    test('"Don\'t remind me" silences that version for good', () async {
      final updates = service();
      await updates.skip((await updates.check())!.release);

      now = now.add(const Duration(days: 90));
      expect(await service().check(), isNull);
    });

    test('a newer release is announced despite an earlier skip', () async {
      final updates = service();
      await updates.skip((await updates.check())!.release);

      now = now.add(const Duration(days: 1));
      served = _manifest(version: '1.3.0');

      expect((await service().check())!.release.version.label, '1.3.0');
    });

    test('a required update ignores "Later" and skips', () async {
      final updates = service();
      final release = (await updates.check())!.release;
      await updates.remindLater(release);
      await updates.skip(release);

      now = now.add(const Duration(days: 1));
      served = _manifest(mandatory: true);

      expect((await service().check())!.required, isTrue);
    });
  });
}
