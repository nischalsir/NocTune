import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel('noctune/audio_capabilities');

/// Whether this device reports a decoder for Dolby Atmos audio (Dolby
/// Digital Plus with the JOC extension).
///
/// False wherever that can't be established. On iOS the system decides how
/// such a track is rendered and doesn't tell the app, so NocTune makes no
/// claim there.
final deviceDecodesAtmosProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('decodesAtmos') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
});
