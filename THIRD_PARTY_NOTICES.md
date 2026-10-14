# Third-party notices

NocTune includes the open-source software and typefaces below. Their licence
texts ship inside the app and are shown under Settings > About > Open-source
licences, together with the licences of the Flutter packages it is built
with.

## SpotiFLAC-Mobile

The floating glass navigation bar (the files in `lib/third_party/spotiflac/`
and `assets/shaders/mornye_selection_mask.frag`) is taken from
[SpotiFLAC-Mobile](https://github.com/zarzet/SpotiFLAC-Mobile) and used under
the MIT licence. Changes are limited to imports and the hooks that connect it
to this app.

```
MIT License

Copyright (c) 2026 zarzet

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Inter

`assets/fonts/InterVariable.ttf`, the typeface of the navigation bar.
Copyright (c) 2016 The Inter Project Authors. SIL Open Font License 1.1;
full text in `assets/licenses/Inter-OFL.txt`.

## Google Sans Flex

`assets/fonts/GoogleSansFlex.ttf`, the typeface of the home feed and the
lyrics view. Copyright 2015 Google LLC. SIL Open Font License 1.1; full text
in `assets/licenses/GoogleSansFlex-OFL.txt`. "Google Sans" is a trademark of
Google LLC.

## FFmpeg

On Android, the FFmpeg decoder offered under Settings > Audio > Decoder is
[FFmpeg](https://ffmpeg.org) 6.0 (branch `release/6.0`, commit
`b37bf81a7a9782438e4fe06a249329e279694494`), used under the GNU Lesser
General Public License version 2.1. It is built without any GPL or nonfree
part, with only the AAC, MP3, FLAC, ALAC, Opus and Vorbis audio decoders,
and linked statically into `libffmpegJNI.so` together with media3's JNI
wrapper. `tool/build_ffmpeg_decoder.sh` downloads that source and rebuilds
the library, so it can be rebuilt with a modified FFmpeg and put back into
`packages/just_audio/android/src/main/jniLibs/`. Configuration (arm64-v8a;
the other ABIs differ only in architecture flags):

```
--target-os=android --enable-static --disable-shared --disable-doc
--disable-programs --disable-everything --disable-avdevice
--disable-avformat --disable-swscale --disable-postproc --disable-avfilter
--disable-symver --enable-swresample --extra-ldexeflags=-pie
--disable-v4l2-m2m --disable-vulkan --enable-decoder=aac
--enable-decoder=mp3 --enable-decoder=flac --enable-decoder=alac
--enable-decoder=opus --enable-decoder=vorbis --arch=aarch64 --cpu=armv8-a
```

The licence text is in `assets/licenses/FFmpeg-LGPL-2.1.txt`.

## AndroidX Media (media3)

The FFmpeg decoder's Java classes and JNI wrapper
(`packages/just_audio/android/src/main/java/androidx/media3/decoder/ffmpeg/`)
are from [AndroidX Media](https://github.com/androidx/media) 1.4.1,
`libraries/decoder_ffmpeg`, unchanged, under the Apache License 2.0
(`assets/licenses/AndroidX-Media-Apache-2.0.txt`).

## just_audio

`packages/just_audio` is a copy of [just_audio](https://pub.dev/packages/just_audio)
0.10.6 by Ryan Heise, under the MIT licence in `packages/just_audio/LICENSE`.
NocTune changes only how its Android player is built, to offer the decoder
and output sample rate choices.
