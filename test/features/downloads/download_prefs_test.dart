// authored, awaiting local run.
//
// Tests for lib/features/downloads/data/download_prefs.dart: defaults,
// setters, concurrency clamping and the template-constant sync with the
// domain class.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/domain/folder_template.dart';

void main() {
  late DownloadPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = DownloadPrefs(await SharedPreferences.getInstance());
  });

  test('defaults: original quality, spec template, wifi-only, 3 concurrent',
      () {
    expect(prefs.quality, 'original');
    expect(prefs.folderTemplate, 'Music/{continent}/{country}/{genre}');
    expect(prefs.wifiOnly, isTrue);
    expect(prefs.concurrency, 3);
    expect(prefs.baseDir, '');
  });

  test('the prefs default template stays in sync with the domain class',
      () {
    expect(prefs.folderTemplate, FolderTemplate.defaultTemplate);
    expect(FolderTemplateDefault, FolderTemplate.defaultTemplate);
  });

  test('quality setter persists', () async {
    await prefs.setQuality('flac');
    expect(prefs.quality, 'flac');
  });

  test('folder template setter persists', () async {
    await prefs.setFolderTemplate('Music/{artist}/{album}');
    expect(prefs.folderTemplate, 'Music/{artist}/{album}');
  });

  test('wifi-only setter persists', () async {
    await prefs.setWifiOnly(false);
    expect(prefs.wifiOnly, isFalse);
  });

  test('concurrency clamps to 1–5', () async {
    await prefs.setConcurrency(9);
    expect(prefs.concurrency, 5);
    await prefs.setConcurrency(0);
    expect(prefs.concurrency, 1);
    await prefs.setConcurrency(4);
    expect(prefs.concurrency, 4);
  });

  test('base dir setter persists', () async {
    await prefs.setBaseDir('/storage/music');
    expect(prefs.baseDir, '/storage/music');
    await prefs.setBaseDir('');
    expect(prefs.baseDir, '');
  });
}
