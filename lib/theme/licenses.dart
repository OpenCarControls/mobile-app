import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the licenses of the bundled theme assets, so they show on the
/// licenses page next to the package licenses.
void registerThemeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope font',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
}
