import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/audio_output/audio_output_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('defaults are System and Original', () async {
    final settings = AudioOutputSettings.load(await prefs({}));

    expect(settings.decoder, AudioDecoder.system);
    expect(settings.outputRateHz, 0);
    expect(settings.floatOutput, isFalse);
  });

  test('saves and loads both choices', () async {
    final store = await prefs({});
    await const AudioOutputSettings(
      decoder: AudioDecoder.ffmpeg,
      outputRateHz: 96000,
    ).save(store);

    final loaded = AudioOutputSettings.load(store);
    expect(loaded.decoder, AudioDecoder.ffmpeg);
    expect(loaded.outputRateHz, 96000);
    expect(store.getString('audio_decoder'), 'ffmpeg');
    expect(store.getInt('audio_output_rate'), 96000);
  });

  test('an unknown saved rate falls back to Original', () async {
    final settings = AudioOutputSettings.load(
      await prefs({'audio_output_rate': 44100, 'audio_decoder': 'magic'}),
    );

    expect(settings.outputRateHz, 0);
    expect(settings.decoder, AudioDecoder.system);
  });

  test('float output only with FFmpeg at the original rate', () {
    expect(
      const AudioOutputSettings(decoder: AudioDecoder.ffmpeg).floatOutput,
      isTrue,
    );
    expect(
      const AudioOutputSettings(
        decoder: AudioDecoder.ffmpeg,
        outputRateHz: 48000,
      ).floatOutput,
      isFalse,
    );
  });
}
