import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/online/release_screen.dart';

Track _track(String title, String? artist) => Track(
  id: title.hashCode,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: artist,
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

void main() {
  final library = [
    _track('FE!N (feat. Playboi Carti)', 'Travis Scott'),
    _track('Real Bad Man', 'Karan Aujla'),
    _track('NOKIA', 'Drake'),
    _track('Intro', 'Someone Else'),
  ];

  test('matches whatever the capitals, punctuation or featured artists', () {
    expect(
      libraryMatch(library, 'FE!N', 'Travis Scott feat. Playboi Carti')?.title,
      'FE!N (feat. Playboi Carti)',
    );
    expect(libraryMatch(library, 'nokia', 'Drake')?.title, 'NOKIA');
    expect(
      libraryMatch(library, 'Real Bad Man', 'Karan Aujla & Ikky')?.title,
      'Real Bad Man',
    );
  });

  test('needs the same song by an artist on it', () {
    expect(libraryMatch(library, 'Intro', 'Drake'), isNull);
    expect(libraryMatch(library, 'NOKIA 2', 'Drake'), isNull);
    expect(libraryMatch(library, '(Intro)', 'Someone Else'), isNull);
  });
}
