/// authored, awaiting local run.
///
/// Hand-rolled fakes + a memory-Drift seeding helper shared by the library
/// tab widget tests. Deliberately self-contained — `test/support` is owned
/// by another agent.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Opens a fresh in-memory [AppDatabase] (FTS5 index included via the
/// onCreate migration).
AppDatabase newMemoryDb() => AppDatabase(NativeDatabase.memory());

/// Seed row factory matching the drift [Tracks] schema requirements.
TracksCompanion seedCompanion({
  required String title,
  required String artist,
  String? album,
  String? genre,
  int durationMs = 180000,
  String sourceTrackId = 'seed',
}) {
  return TracksCompanion.insert(
    sourceId: Track.localSourceId,
    sourceTrackId: '$sourceTrackId:$title',
    title: title,
    artist: artist,
    album: Value(album),
    genre: Value(genre),
    durationMs: durationMs,
    format: 'mp3',
    addedAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}

/// Records [TrackLauncher.playTracks] calls; nothing else happens.
class FakeTrackLauncher implements TrackLauncher {
  final List<({List<Track> tracks, int startIndex})> calls =
      <({List<Track> tracks, int startIndex})>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    calls.add((tracks: List<Track>.of(tracks), startIndex: startIndex));
  }
}

/// Scripted [LibraryScanner]: pickFolders returns [picked]; scan replays
/// [events] and records every invocation.
class FakeLibraryScanner extends LibraryScanner {
  FakeLibraryScanner({
    this.picked = const <String>[],
    this.events = const <ScanEvent>[],
  });

  List<String> picked;
  List<ScanEvent> events;

  int scanCalls = 0;
  final List<List<String>> scannedFolders = <List<String>>[];

  @override
  Stream<ScanEvent> scan(List<String> folders) {
    scanCalls++;
    scannedFolders.add(List<String>.of(folders));
    return Stream<ScanEvent>.fromIterable(events);
  }

  @override
  Future<List<String>> pickFolders() async => picked;

  @override
  Future<List<String>> watchFolders() async => const <String>[];
}

/// Canonical completed-scan event list (scan ends, nothing pending).
List<ScanEvent> quietScanEvents(String root) => <ScanEvent>[
      ScanEvent.scanStarted(root: root),
      ScanEvent.completed(count: 0, errors: <String>[]),
    ];
