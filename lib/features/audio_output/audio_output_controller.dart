import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'audio_output_settings.dart';

/// Holds the decoder and output rate. Every change is kept for the next
/// launch and applied to the player straight away.
class AudioOutputController extends Notifier<AudioOutputSettings> {
  @override
  AudioOutputSettings build() =>
      AudioOutputSettings.load(ref.watch(sharedPreferencesProvider));

  Future<void> setDecoder(AudioDecoder decoder) =>
      _set(state.copyWith(decoder: decoder));

  Future<void> setOutputRate(int hz) => _set(state.copyWith(outputRateHz: hz));

  Future<void> _set(AudioOutputSettings settings) async {
    state = settings;
    await settings.save(ref.read(sharedPreferencesProvider));
    await ref.read(audioHandlerProvider).applyAudioOutput(settings);
  }
}

final audioOutputProvider =
    NotifierProvider<AudioOutputController, AudioOutputSettings>(
      AudioOutputController.new,
    );
