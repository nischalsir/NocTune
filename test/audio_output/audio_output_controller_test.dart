import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/features/audio_output/audio_output_channel.dart';
import 'package:noctune/features/audio_output/audio_output_controller.dart';
import 'package:noctune/features/audio_output/audio_output_settings.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final applied = <AudioOutputSettings>[];

  @override
  Future<void> applyAudioOutput(
    AudioOutputSettings settings, {
    bool reload = true,
  }) async => applied.add(settings);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeHandler handler;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    handler = _FakeHandler();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(handler),
      ],
    );
    addTearDown(container.dispose);
  });

  test('choosing FFmpeg saves it and applies it', () async {
    await container
        .read(audioOutputProvider.notifier)
        .setDecoder(AudioDecoder.ffmpeg);

    expect(prefs.getString('audio_decoder'), 'ffmpeg');
    expect(handler.applied.single.decoder, AudioDecoder.ffmpeg);
    expect(container.read(audioOutputProvider).decoder, AudioDecoder.ffmpeg);
  });

  test('choosing a rate saves it and applies it', () async {
    await container.read(audioOutputProvider.notifier).setOutputRate(48000);

    expect(prefs.getInt('audio_output_rate'), 48000);
    expect(handler.applied.single.outputRateHz, 48000);
  });

  test('the channel sends the decoder and the rate', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('noctune/audio_output'), (
          call,
        ) async {
          calls.add(call);
          return null;
        });

    await const AudioOutputChannel().configure(
      const AudioOutputSettings(
        decoder: AudioDecoder.ffmpeg,
        outputRateHz: 48000,
      ),
    );

    expect(calls.single.method, 'configure');
    expect(calls.single.arguments, {'ffmpeg': true, 'outputRate': 48000});
  });

  test('without the Android side the channel does nothing', () async {
    // No handler registered, as on iOS.
    await const AudioOutputChannel().configure(const AudioOutputSettings());
  });
}
