import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which decoder turns a file into sound.
enum AudioDecoder {
  /// Android's own decoders: what NocTune has always used.
  system,

  /// FFmpeg inside NocTune, decoding with headroom so loud files are not
  /// clipped.
  ffmpeg,
}

/// How NocTune decodes audio and at what sample rate it hands it to Android.
/// The defaults leave both as Android would have them.
@immutable
class AudioOutputSettings {
  const AudioOutputSettings({
    this.decoder = AudioDecoder.system,
    this.outputRateHz = 0,
  });

  static const _decoderKey = 'audio_decoder';
  static const _rateKey = 'audio_output_rate';

  /// The output rates offered, in Hz; 0 keeps each file's own.
  static const List<int> rates = [0, 48000, 96000, 192000];

  /// Reads what [save] wrote. Anything missing or not offered falls back to
  /// the default.
  factory AudioOutputSettings.load(SharedPreferences preferences) {
    final rate = preferences.getInt(_rateKey) ?? 0;
    return AudioOutputSettings(
      decoder:
          AudioDecoder.values.asNameMap()[preferences.getString(_decoderKey)] ??
          AudioDecoder.system,
      outputRateHz: rates.contains(rate) ? rate : 0,
    );
  }

  final AudioDecoder decoder;

  /// The sample rate to resample to, in Hz, or 0 for each file's own.
  final int outputRateHz;

  /// Whether decoded audio stays in floating point. Only FFmpeg decodes to
  /// it, and resampling works on 16-bit audio only, so it needs the
  /// original rate.
  bool get floatOutput => decoder == AudioDecoder.ffmpeg && outputRateHz == 0;

  Future<void> save(SharedPreferences preferences) async {
    await preferences.setString(_decoderKey, decoder.name);
    await preferences.setInt(_rateKey, outputRateHz);
  }

  AudioOutputSettings copyWith({AudioDecoder? decoder, int? outputRateHz}) =>
      AudioOutputSettings(
        decoder: decoder ?? this.decoder,
        outputRateHz: outputRateHz ?? this.outputRateHz,
      );
}
