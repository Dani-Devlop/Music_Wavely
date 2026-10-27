/// User-facing sync status model shared by [SyncService] and the settings
/// badge (`sync_status_view.dart`).
///
/// Kept free of Flutter/Riverpod imports so the data layer (and its tests)
/// stay UI-independent.
/// Sync lifecycle of the engine.
enum SyncStatus {
  /// No backend configured (Supabase keys absent) — the service idles.
  disabled,

  /// Backend present, nothing in flight.
  idle,

  /// A push or pull round is running.
  syncing,

  /// The last push or pull failed ([SyncStatusView.lastError] says why).
  error,
}

/// Immutable snapshot of the sync engine state surfaced to the UI.
class SyncStatusView {
  /// Creates a status snapshot.
  const SyncStatusView({
    required this.status,
    this.pending = 0,
    this.lastError,
  });

  /// Current lifecycle state.
  final SyncStatus status;

  /// Rows still waiting in the sync outbox (including parked failures).
  final int pending;

  /// Message of the last failed push/pull; null after a success.
  final String? lastError;

  /// Returns a copy with the given fields replaced.
  SyncStatusView copyWith({SyncStatus? status, int? pending}) =>
      SyncStatusView(
        status: status ?? this.status,
        pending: pending ?? this.pending,
        lastError: lastError,
      );

  @override
  String toString() =>
      'SyncStatusView(${status.name}, pending: $pending, '
      'lastError: $lastError)';
}
