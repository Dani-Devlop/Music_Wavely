import 'package:wavely/app/bootstrap.dart';

/// Owner spec wrote `void main() => bootstrap();`; the returned Future is
/// kept so very_good_analysis' unawaited_futures stays clean — one-line,
/// logged deviation from the owner snippet (errors are still handled inside
/// the guarded zone + FlutterError/PlatformDispatcher hooks).
Future<void> main() => bootstrap();
