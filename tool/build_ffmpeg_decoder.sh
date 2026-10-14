#!/usr/bin/env bash
# Builds media3 1.4.1's FFmpeg audio decoder for NocTune and copies the
# result into packages/just_audio:
#   android/src/main/jniLibs/<abi>/libffmpegJNI.so
#   android/src/main/java/androidx/media3/decoder/ffmpeg/*.java
#   android/ffmpeg-proguard-rules.txt
#
# FFmpeg 6.0 is configured as media3 configures it, without any GPL or
# nonfree part, so it is under the LGPL 2.1; only the audio decoders below
# are built. FFmpeg is linked statically into libffmpegJNI.so, which is
# built only from published source (FFmpeg and media3's JNI wrapper) by
# this script, so it can be rebuilt with a changed FFmpeg.
#
# Runs in MSYS2 on Windows (with the Windows NDK) or in Linux bash:
#   tool/build_ffmpeg_decoder.sh <work dir without spaces> <NDK path> [cmake bin dir]
set -euo pipefail

WORK="$1"
NDK="$2"
CMAKE_BIN="${3:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
API=24
ABIS=(arm64-v8a armeabi-v7a x86_64)
DECODERS=(aac mp3 flac alac opus vorbis)

case "$(uname -s)" in
  MSYS*|MINGW*) HOST=windows-x86_64 ;;
  *) HOST=linux-x86_64 ;;
esac
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
[[ -d "$TOOLS" ]] || { echo "No NDK toolchain at $TOOLS"; exit 1; }
if [[ -n "$CMAKE_BIN" ]]; then PATH="$CMAKE_BIN:$PATH"; fi

mkdir -p "$WORK"
cd "$WORK"
if [[ ! -d media ]]; then
  git clone --depth 1 --branch 1.4.1 --filter=blob:none --sparse \
    https://github.com/androidx/media.git
  git -C media sparse-checkout set libraries/decoder_ffmpeg
fi
MODULE="$WORK/media/libraries/decoder_ffmpeg/src/main"
FFMPEG="$MODULE/jni/ffmpeg"
if [[ ! -d "$FFMPEG" ]]; then
  git clone --depth 1 --branch release/6.0 https://github.com/FFmpeg/FFmpeg.git "$FFMPEG"
fi

# The options media3's build_ffmpeg.sh uses, with our decoders.
COMMON=(
  --target-os=android --enable-static --disable-shared --disable-doc
  --disable-programs --disable-everything --disable-avdevice
  --disable-avformat --disable-swscale --disable-postproc --disable-avfilter
  --disable-symver --enable-swresample --extra-ldexeflags=-pie
  --disable-v4l2-m2m --disable-vulkan
)
for decoder in "${DECODERS[@]}"; do COMMON+=("--enable-decoder=$decoder"); done

cd "$FFMPEG"
for abi in "${ABIS[@]}"; do
  case "$abi" in
    arm64-v8a) arch=(--arch=aarch64 --cpu=armv8-a); prefix=aarch64-linux-android$API- ;;
    armeabi-v7a) arch=(--arch=arm --cpu=armv7-a
        "--extra-cflags=-march=armv7-a -mfloat-abi=softfp"
        "--extra-ldflags=-Wl,--fix-cortex-a8")
      prefix=armv7a-linux-androideabi$API- ;;
    x86_64) arch=(--arch=x86_64 --cpu=x86-64 --disable-asm); prefix=x86_64-linux-android$API- ;;
  esac
  ./configure --libdir="android-libs/$abi" "${arch[@]}" \
    --cross-prefix="$TOOLS/$prefix" \
    --nm="$TOOLS/llvm-nm" --ar="$TOOLS/llvm-ar" \
    --ranlib="$TOOLS/llvm-ranlib" --strip="$TOOLS/llvm-strip" \
    "${COMMON[@]}"
  grep -h "FFMPEG_CONFIGURATION" config.h > "$WORK/configuration-$abi.txt"
  make -j"$(nproc)"
  make install-libs
  make clean
done

# The JNI wrapper, linked with the static FFmpeg libraries.
for abi in "${ABIS[@]}"; do
  out="$WORK/jni-$abi"
  cmake -G Ninja -S "$MODULE/jni" -B "$out" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$out"
  dest="$REPO/packages/just_audio/android/src/main/jniLibs/$abi"
  mkdir -p "$dest"
  "$TOOLS/llvm-strip" --strip-unneeded -o "$dest/libffmpegJNI.so" "$out/libffmpegJNI.so"
done

java_dest="$REPO/packages/just_audio/android/src/main/java/androidx/media3/decoder/ffmpeg"
mkdir -p "$java_dest"
cp "$MODULE/java/androidx/media3/decoder/ffmpeg/"*.java "$java_dest/"
cp "$WORK/media/libraries/decoder_ffmpeg/proguard-rules.txt" \n  "$REPO/packages/just_audio/android/ffmpeg-proguard-rules.txt"

echo "FFmpeg configuration:"
cat "$WORK/configuration-arm64-v8a.txt"
