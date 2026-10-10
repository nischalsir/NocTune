import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of bundled code and fonts that don't come from a pub
/// package, so they appear on the app's open-source licences page alongside
/// everything Flutter lists automatically.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in const [
      ('SpotiFLAC-Mobile', 'assets/licenses/SpotiFLAC-Mobile-MIT.txt'),
      ('Inter (typeface)', 'assets/licenses/Inter-OFL.txt'),
      ('Google Sans Flex (typeface)', 'assets/licenses/GoogleSansFlex-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(asset));
    }
  });
}
