import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';

/// Pictures the user has chosen as covers, kept as copies in the app's own
/// storage so they outlive both the originals and the artwork cache.
class CoverStore {
  const CoverStore(this._directory);

  final String _directory;

  /// Lets the user pick a picture and keeps a copy of it. Returns the copy's
  /// path, or null if they backed out.
  Future<String?> pick() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final source = picked?.path;
    if (source == null) return null;
    final directory = Directory(_directory)..createSync(recursive: true);
    // Named by the moment it was chosen: a new cover never takes the path of
    // the one it replaces, so the old picture is not shown from memory.
    final copy = await File(source).copy(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
      ),
    );
    await FilePicker.clearTemporaryFiles();
    return copy.path;
  }

  /// Deletes a cover that is no longer used. Only ever a file of this store.
  Future<void> discard(String? path) async {
    if (path == null || !p.isWithin(_directory, path)) return;
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

final coverStoreProvider = Provider<CoverStore>(
  (ref) => CoverStore(ref.watch(appPathsProvider).coverDir),
);

/// The picture the user chose for the Favourites page, if they have.
class FavouritesCover extends Notifier<String?> {
  static const _key = 'favourites_cover';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  void set(String? path) {
    final preferences = ref.read(sharedPreferencesProvider);
    if (path == null) {
      preferences.remove(_key);
    } else {
      preferences.setString(_key, path);
    }
    state = path;
  }
}

final favouritesCoverProvider = NotifierProvider<FavouritesCover, String?>(
  FavouritesCover.new,
);
