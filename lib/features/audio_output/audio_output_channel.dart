import 'package:flutter/services.dart';

import 'audio_output_settings.dart';

/// Hands the decoder and output rate to the Android side, which reads them
/// when it next builds the native player.
class AudioOutputChannel {
  const AudioOutputChannel([
    this._channel = const MethodChannel('noctune/audio_output'),
  ]);

  final MethodChannel _channel;

  Future<void> configure(AudioOutputSettings settings) async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'ffmpeg': settings.decoder == AudioDecoder.ffmpeg,
        'outputRate': settings.outputRateHz,
      });
    } on MissingPluginException {
      // Only Android has these choices.
    }
  }
}
