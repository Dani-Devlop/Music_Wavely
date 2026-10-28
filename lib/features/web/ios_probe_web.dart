import 'dart:js_interop';

/// Real web probe over `navigator.userAgent` + `navigator.standalone`.
/// Selected by the conditional export in `ios_guidance_banner.dart`.
class IosPlatformProbe {
  const IosPlatformProbe();

  static JSObject get _navigator =>
      globalContext.getProperty('navigator'.toJS) as JSObject;

  @override
  bool get isIos {
    try {
      final String ua = (_navigator.getProperty('userAgent'.toJS) as JSString)
          .toDart
          .toLowerCase();
      return ua.contains('iphone') ||
          ua.contains('ipad') ||
          (ua.contains('macintosh') && ua.contains('mobile'));
    } on Object {
      return false;
    }
  }

  @override
  bool get isStandalone {
    try {
      // iOS Safari exposes navigator.standalone (undefined = false).
      final JSBoolean? standalone =
          _navigator.getProperty('standalone'.toJS) as JSBoolean?;
      return standalone?.toDart ?? false;
    } on Object {
      return false;
    }
  }
}
