/// Conditional export for the platform update installer (Stage 7): the
/// real download/install flows on IO platforms, the browser fallback on
/// web. Both variants expose `createPlatformInstaller()` with an
/// identical signature.
library;

export 'package:wavely/features/settings/data/update_installer_stub.dart'
    if (dart.library.io)
        'package:wavely/features/settings/data/update_installer_io.dart';
