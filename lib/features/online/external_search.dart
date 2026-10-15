import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the app that handles it, or the browser. Returns false
/// when nothing could. Replaced with a fake in tests.
typedef LinkOpener = Future<bool> Function(Uri url);

final linkOpenerProvider = Provider<LinkOpener>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Opens Spotify's own search for [words]: in the Spotify app, or on its
/// website when the app isn't there. Nothing of Spotify's is shown in
/// NocTune. Returns false when neither opened.
Future<bool> searchOnSpotify(LinkOpener open, String words) async {
  final query = Uri.encodeComponent(words.trim());
  return await _tryOpen(open, Uri.parse('spotify:search:$query')) ||
      await _tryOpen(open, Uri.parse('https://open.spotify.com/search/$query'));
}

/// Opens YouTube Music's own search for [words], in its app when installed.
Future<bool> searchOnYouTubeMusic(LinkOpener open, String words) => _tryOpen(
  open,
  Uri.https('music.youtube.com', '/search', {'q': words.trim()}),
);

Future<bool> _tryOpen(LinkOpener open, Uri url) async {
  try {
    return await open(url);
  } on Exception {
    return false;
  }
}
