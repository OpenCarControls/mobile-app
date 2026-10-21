import 'package:flutter/foundation.dart';

/// Registers the licenses of the E-GMP assets bundled in the app, so they show
/// on the licenses page next to the package licenses.
void registerEgmpLicenses() {
  LicenseRegistry.addLicense(() async* {
    // CC BY 4.0 requires the title, author, source, license and any changes.
    yield const LicenseEntryWithLineBreaks(
      ['2022 Kia EV6 3D model'],
      '"2022 Kia EV6" by tonielpro520\n'
      'https://sketchfab.com/3d-models/2022-kia-ev6-44d11e83ef40492bb4bc3d9fbc41e5e0\n'
      '\n'
      'Licensed under the Creative Commons Attribution 4.0 International '
      'license (CC BY 4.0): https://creativecommons.org/licenses/by/4.0/\n'
      '\n'
      'Changed for this app: parts of the mesh simplified to reduce the '
      'polygon count, parts separated so they can be animated, the paint '
      'recolored, emissive lights added, a plane added under the hood, and '
      'the mesh compressed.',
    );
  });
}
