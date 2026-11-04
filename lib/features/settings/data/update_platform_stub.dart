/// Web/stub variants of the platform seams: there is no installable
/// desktop asset on web, no device ABI and no test-environment flag.
/// Selected by the conditional export in `update_platform.dart`.
String defaultAssetSuffix() => '';

Future<String?> deviceAbi() async => null;

bool get runningInFlutterTest => false;
