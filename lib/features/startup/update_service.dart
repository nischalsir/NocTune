import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Address of the release manifest NocTune checks for updates, set at build
/// time with `--dart-define=NOCTUNE_UPDATE_MANIFEST=https://…`. When it is
/// empty, as it is by default, update checks are off and no request is made.
const kUpdateManifestUrl = String.fromEnvironment('NOCTUNE_UPDATE_MANIFEST');

/// An app version such as `1.4.2` with an optional build number (`1.4.2+17`).
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// Parses `1.2`, `1.2.3`, `v1.2.3` or `1.2.3+45`. Returns null for
  /// anything else, including pre-release suffixes it can't order.
  static AppVersion? tryParse(String text, {int? build}) {
    final match = RegExp(r'^v?(\d+)\.(\d+)(?:\.(\d+))?(?:\+(\d+))?$')
        .firstMatch(text.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3] ?? '0'),
      build ?? int.parse(match[4] ?? '0'),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final (mine, theirs) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      if (mine != theirs) return mine.compareTo(theirs);
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  /// The version without its build number, as shown to people.
  String get label => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => build == 0 ? label : '$label+$build';
}

/// A published release, as described by the update manifest.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.url,
    this.notes = const [],
    this.minSupported,
    this.mandatory = false,
  });

  /// Reads and validates a manifest. Throws [FormatException] when a field is
  /// missing, malformed, or points anywhere but an HTTPS address.
  ///
  /// ```json
  /// {
  ///   "version": "1.2.0",
  ///   "build": 12,
  ///   "url": "https://example.com/noctune/releases/1.2.0",
  ///   "iosUrl": "https://apps.apple.com/app/id0000000000",
  ///   "notes": ["Synchronised lyrics", "Faster scanning"],
  ///   "minSupported": "1.0.0",
  ///   "mandatory": false
  /// }
  /// ```
  factory ReleaseInfo.fromManifest(String body, {required bool isIos}) {
    final Object? json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('The manifest is not a JSON object.');
    }
    if (json.containsKey('tag_name')) return ReleaseInfo._fromGitHub(json);
    final version = switch ((json['version'], json['build'])) {
      (final String text, final int build) => AppVersion.tryParse(
        text,
        build: build,
      ),
      (final String text, null) => AppVersion.tryParse(text),
      _ => null,
    };
    if (version == null) {
      throw const FormatException('The manifest has no valid "version".');
    }

    final link = (isIos ? json['iosUrl'] : json['androidUrl']) ?? json['url'];
    final url = link is String ? Uri.tryParse(link) : null;
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('The manifest "url" must be an HTTPS link.');
    }

    final minSupported = json['minSupported'];
    final notes = json['notes'];
    return ReleaseInfo(
      version: version,
      url: url,
      // Release notes are optional and kept short for the popup.
      notes: notes is List
          ? [
              for (final note in notes.whereType<String>().take(5))
                note.length > 160 ? '${note.substring(0, 160)}…' : note,
            ]
          : const [],
      minSupported: minSupported is String
          ? AppVersion.tryParse(minSupported)
          : null,
      mandatory: json['mandatory'] == true,
    );
  }

  /// Reads GitHub's description of a release, as served by
  /// `https://api.github.com/repos/<owner>/<repo>/releases/latest`. The tag
  /// (`v1.2.0`) is the version, the release page is the link, and bulleted
  /// lines of the release text become the notes.
  factory ReleaseInfo._fromGitHub(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    final version = tag is String ? AppVersion.tryParse(tag) : null;
    if (version == null) {
      throw const FormatException('The release tag is not a version.');
    }
    final page = json['html_url'];
    final url = page is String ? Uri.tryParse(page) : null;
    if (url == null || url.scheme != 'https' || url.host != 'github.com') {
      throw const FormatException('The release has no GitHub page link.');
    }
    final text = json['body'];
    return ReleaseInfo(
      version: version,
      url: url,
      notes: [
        if (text is String)
          for (final line
              in text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.startsWith(RegExp(r'[-*] ')))
                  .take(5))
            line.length > 162
                ? '${line.substring(2, 162)}…'
                : line.substring(2),
      ],
    );
  }

  final AppVersion version;

  /// The official page to get the release from: a store listing or release
  /// page. NocTune only opens it; it never downloads or installs anything.
  final Uri url;
  final List<String> notes;

  /// Oldest version still allowed to run, if the publisher sets one.
  final AppVersion? minSupported;
  final bool mandatory;
}

/// A release worth telling the user about now.
@immutable
class UpdatePrompt {
  const UpdatePrompt({
    required this.release,
    required this.installed,
    required this.required,
  });

  final ReleaseInfo release;
  final AppVersion installed;

  /// True when the publisher marked the release mandatory, or the installed
  /// version is older than the minimum it still supports.
  final bool required;
}

/// Downloads the manifest text. Replaced with a fake in tests.
typedef ManifestFetcher = Future<String> Function(Uri url);

/// Fetches a small text document over HTTPS, giving up after a few seconds.
Future<String> fetchManifestOverHttps(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Unexpected status ${response.statusCode}', uri: url);
    }
    // A manifest is a few hundred bytes; refuse anything implausibly large.
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
      if (bytes.length > 64 * 1024) {
        throw HttpException('The manifest is too large', uri: url);
      }
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}

/// Decides whether there is a newer release the user should hear about,
/// and remembers their answers so the same optional update doesn't nag.
class UpdateService {
  UpdateService({
    required this.manifestUrl,
    required this.installed,
    required SharedPreferences preferences,
    required this.isIos,
    this.fetch = fetchManifestOverHttps,
    this._now = DateTime.now,
  }) : _prefs = preferences;

  static const _manifestKey = 'update_manifest';
  static const _checkedAtKey = 'update_checked_at';
  static const _skippedKey = 'update_skipped_version';
  static const _laterVersionKey = 'update_later_version';
  static const _laterUntilKey = 'update_later_until';

  /// How long a downloaded manifest is trusted before asking again.
  static const checkInterval = Duration(hours: 12);

  /// How long "Later" silences an optional update.
  static const remindAfter = Duration(days: 3);

  final String manifestUrl;
  final AppVersion installed;
  final bool isIos;
  final ManifestFetcher fetch;
  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Future<UpdatePrompt?>? _inFlight;

  /// Whether this build was given somewhere to look for updates.
  bool get isConfigured => Uri.tryParse(manifestUrl)?.scheme == 'https';

  /// Returns the update to show now, or null: when checks are off, the app is
  /// current, the user has put this version off, or the release information
  /// can't be fetched or trusted. Never throws; being offline is normal.
  ///
  /// Calls made while a check is running share its result, so two triggers
  /// can't produce two prompts.
  Future<UpdatePrompt?> check() =>
      _inFlight ??= _check().whenComplete(() => _inFlight = null);

  Future<UpdatePrompt?> _check() async {
    if (!isConfigured) return null;
    final release = await _latestRelease();
    if (release == null || !(installed < release.version)) return null;

    final minSupported = release.minSupported;
    final required =
        release.mandatory || (minSupported != null && installed < minSupported);
    if (!required) {
      final version = release.version.toString();
      if (_prefs.getString(_skippedKey) == version) return null;
      final laterUntil = _prefs.getInt(_laterUntilKey) ?? 0;
      if (_prefs.getString(_laterVersionKey) == version &&
          _now().millisecondsSinceEpoch < laterUntil) {
        return null;
      }
    }
    return UpdatePrompt(
      release: release,
      installed: installed,
      required: required,
    );
  }

  /// A check the user asked for. It always asks the server and ignores
  /// "Later" and "Don't remind me". [checked] is false when the server
  /// couldn't be reached or its answer couldn't be read, so "up to date" is
  /// only ever said when it is known.
  Future<({UpdatePrompt? update, bool checked})> checkNow() async {
    if (!isConfigured) return (update: null, checked: false);
    final ReleaseInfo release;
    try {
      final fresh = await fetch(Uri.parse(manifestUrl));
      release = ReleaseInfo.fromManifest(fresh, isIos: isIos);
      await _prefs.setString(_manifestKey, fresh);
      await _prefs.setInt(_checkedAtKey, _now().millisecondsSinceEpoch);
    } on Exception {
      return (update: null, checked: false);
    }
    if (!(installed < release.version)) return (update: null, checked: true);
    final minSupported = release.minSupported;
    return (
      update: UpdatePrompt(
        release: release,
        installed: installed,
        required:
            release.mandatory ||
            (minSupported != null && installed < minSupported),
      ),
      checked: true,
    );
  }

  /// The newest release known: freshly downloaded when the cached copy is
  /// stale, otherwise (or if the download fails) the cached copy.
  Future<ReleaseInfo?> _latestRelease() async {
    final checkedAt = _prefs.getInt(_checkedAtKey) ?? 0;
    final age = _now().millisecondsSinceEpoch - checkedAt;
    var body = _prefs.getString(_manifestKey);
    if (body == null || age < 0 || age > checkInterval.inMilliseconds) {
      try {
        final fresh = await fetch(Uri.parse(manifestUrl));
        // Validate before caching, so a bad response can't stick.
        ReleaseInfo.fromManifest(fresh, isIos: isIos);
        body = fresh;
        await _prefs.setString(_manifestKey, fresh);
        await _prefs.setInt(_checkedAtKey, _now().millisecondsSinceEpoch);
      } on Exception {
        // Offline, timed out or malformed: fall back to what is cached.
      }
    }
    if (body == null) return null;
    try {
      return ReleaseInfo.fromManifest(body, isIos: isIos);
    } on FormatException {
      return null;
    }
  }

  /// "Later": stay quiet about this version for [remindAfter].
  Future<void> remindLater(ReleaseInfo release) async {
    await _prefs.setString(_laterVersionKey, release.version.toString());
    await _prefs.setInt(
      _laterUntilKey,
      _now().add(remindAfter).millisecondsSinceEpoch,
    );
  }

  /// "Don't remind me": never prompt for this version again. A newer release
  /// will still be announced.
  Future<void> skip(ReleaseInfo release) =>
      _prefs.setString(_skippedKey, release.version.toString());
}
