import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'equalizer_settings.dart';

/// Holds the equaliser settings. Every change is kept for the next launch
/// and sent to the player straight away.
class EqualizerController extends Notifier<EqualizerSettings> {
  @override
  EqualizerSettings build() =>
      EqualizerSettings.load(ref.watch(sharedPreferencesProvider));

  void setEnabled(bool enabled) => _set(state.copyWith(enabled: enabled));

  void choose(EqualizerCurve curve) => _set(state.copyWith(curve: curve));

  /// Sets one of [bands] to [db] and leaves the others where the current
  /// shape puts them. The result is a setting of the user's own.
  void setBand(EqualizerBands bands, int index, double db) {
    final levels = state.curve.levelsFor(bands)..[index] = db;
    _set(
      state.copyWith(
        curve: EqualizerCurve([
          for (final (band, hz) in bands.centers.indexed)
            (hz: hz, db: levels[band]),
        ]),
      ),
    );
  }

  void setPreamp(double db) => _set(state.copyWith(preampDb: db));

  /// Keeps the current shape under [name], in place of any saved under
  /// that name before.
  void save(String name) {
    final curve = EqualizerCurve(state.curve.points, name: name);
    _set(
      state.copyWith(
        curve: curve,
        saved: [
          for (final other in state.saved)
            if (other.name != name) other,
          curve,
        ],
      ),
    );
  }

  /// Forgets the saved shape called [name]. The sound stays as it is.
  void delete(String name) => _set(
    state.copyWith(
      curve: state.curve.name == name
          ? EqualizerCurve(state.curve.points)
          : null,
      saved: [
        for (final curve in state.saved)
          if (curve.name != name) curve,
      ],
    ),
  );

  /// Back to flat with no preamp. Whether it is switched on stays.
  void reset() => _set(state.copyWith(curve: flatCurve, preampDb: 0));

  void _set(EqualizerSettings next) {
    state = next;
    next.store(ref.read(sharedPreferencesProvider));
    ref.read(audioHandlerProvider).applyEqualizer(next);
  }
}

final equalizerProvider =
    NotifierProvider<EqualizerController, EqualizerSettings>(
      EqualizerController.new,
    );

/// The bands this phone's equaliser has. Known once a first song has been
/// loaded, because that is when the phone gives the player its equaliser.
final equalizerBandsProvider = FutureProvider<EqualizerBands>(
  (ref) => ref.watch(audioHandlerProvider).equalizerBands,
);
