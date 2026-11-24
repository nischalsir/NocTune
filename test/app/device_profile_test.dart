import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/device_profile.dart';

void main() {
  DeviceTier tier({
    bool lowRam = false,
    required int totalMb,
    bool has64Bit = true,
  }) => tierFor(lowRam: lowRam, totalMb: totalMb, has64Bit: has64Bit);

  test('4 GB or less, a low-RAM flag or 32-bit only means the low tier', () {
    expect(tier(totalMb: 2048), DeviceTier.low);
    // A 4 GB phone reports a little under 4096 MB.
    expect(tier(totalMb: 3700), DeviceTier.low);
    expect(tier(totalMb: 4200), DeviceTier.low);
    expect(tier(totalMb: 8000, lowRam: true), DeviceTier.low);
    expect(tier(totalMb: 8000, has64Bit: false), DeviceTier.low);
  });

  test('mid-range memory is the standard tier', () {
    expect(tier(totalMb: 4201), DeviceTier.standard);
    expect(tier(totalMb: 5600), DeviceTier.standard);
    expect(tier(totalMb: 5999), DeviceTier.standard);
  });

  test('six gigabytes and up is the high tier', () {
    expect(tier(totalMb: 6000), DeviceTier.high);
    expect(tier(totalMb: 12000), DeviceTier.high);
  });
}
