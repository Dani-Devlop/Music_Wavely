import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/settings/data/update_providers.dart';
import 'package:wavely/features/settings/data/update_service.dart';

/// Bytes per megabyte for the progress label (data math, not a token).
const int _bytesPerMb = 1024 * 1024;

/// Fullscreen update screen (Stage 7): shows the running version against
/// the latest GitHub release, renders the release notes and drives the
/// platform install flow with a live download progress bar.
///
/// The check fires automatically on first open; every phase of
/// [UpdateFlowState] has a dedicated presentation.
class UpdateScreen extends ConsumerStatefulWidget {
  /// Creates the update screen.
  const UpdateScreen({super.key});

  /// Router path (registered on the root navigator).
  static const String route = '/settings/update';

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-run the check exactly once per screen visit (a re-entry with a
    // preserved state — e.g. back navigation — must not restart a flow).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final UpdateFlowState state = ref.read(updateFlowControllerProvider);
      if (state is UpdateFlowIdle) {
        ref.read(updateFlowControllerProvider.notifier).check();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final UpdateFlowState state = ref.watch(updateFlowControllerProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Updates',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: switch (state) {
          UpdateFlowIdle() || UpdateFlowChecking() => const _CheckingView(),
          UpdateFlowUpToDate(:final version) => _UpToDateView(version: version),
          UpdateFlowAvailable(:final result) => _AvailableView(result: result),
          UpdateFlowDownloading(
            :final result,
            :final received,
            :final total,
          ) =>
            _DownloadingView(
              result: result,
              received: received,
              total: total,
            ),
          UpdateFlowInstalling() => const _InstallingView(),
          UpdateFlowDone(:final outcome, :final result) =>
            _DoneView(outcome: outcome, result: result),
          UpdateFlowError(:final message, :final result) => _ErrorView(
              message: message,
              hasResult: result != null,
            ),
        },
      ),
    );
  }
}

/// Centered indeterminate progress with a status label.
class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Center(
      key: const Key('update-screen-checking'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.lg),
          Text(
            'Checking GitHub Releases…',
            style: WavelyTypography.body14(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "You're on the latest release" state.
class _UpToDateView extends ConsumerWidget {
  const _UpToDateView({required this.version});

  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return Center(
      child: Column(
        key: const Key('update-screen-up-to-date'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.verified_rounded,
            color: colors.success,
            size: 64,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            "You're up to date",
            style: WavelyTypography.title20(color: colors.textPrimary),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Wavely $version is the newest published release.',
            style: WavelyTypography.body14(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
          TextButton(
            key: const Key('update-screen-open-release'),
            onPressed: () => ref
                .read(updateFlowControllerProvider.notifier)
                .openReleasePage(),
            child: const Text('View releases on GitHub'),
          ),
        ],
      ),
    );
  }
}

/// Update available: version jump, release notes and the install button.
class _AvailableView extends ConsumerWidget {
  const _AvailableView({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final bool installable = result.assetUrl != null;
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        key: const Key('update-screen-available'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Wavely ${result.currentVersion} → ${result.latestVersion}',
            key: const Key('update-screen-latest-version'),
            style: WavelyTypography.display24(color: colors.textPrimary),
          ),
          if (result.publishedAt != null) ...<Widget>[
            const SizedBox(height: Spacing.xs),
            Text(
              _dateLabel(result.publishedAt!),
              style: WavelyTypography.caption12(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          Expanded(
            child: GlassCard(
              borderRadius: AppRadii.bLg,
              padding: const EdgeInsets.all(Spacing.md),
              child: SingleChildScrollView(
                child: Column(
                  key: const Key('update-screen-release-notes'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Release notes',
                      style: WavelyTypography.body14Medium(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    MarkdownBody(
                      data: result.releaseNotes ?? 'No release notes.',
                      onTapLink: (String text, String? href, String title) {
                        if (href != null) {
                          final Uri url = Uri.parse(href);
                          if (url.scheme == 'https') {
                            ref.read(linkLauncherProvider).launchExternal(url);
                          }
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: WavelyTypography.body14(color: colors.textPrimary),
                        h1: WavelyTypography.title18(color: colors.textPrimary),
                        h2: WavelyTypography.title18(color: colors.textPrimary),
                        h3: WavelyTypography.body14Medium(
                          color: colors.textPrimary,
                        ),
                        listBullet: WavelyTypography.body14(
                          color: colors.textPrimary,
                        ),
                        code: WavelyTypography.caption12(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            key: const Key('update-screen-update-now'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accentColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(AppConstants.touchTargetMin),
            ),
            onPressed: () {
              final notifier =
                  ref.read(updateFlowControllerProvider.notifier);
              if (installable) {
                notifier.startInstall();
              } else {
                notifier.openReleasePage();
              }
            },
            icon: Icon(
              installable
                  ? Icons.download_rounded
                  : Icons.open_in_new_rounded,
            ),
            label: Text(installable ? 'Update now' : 'Download from GitHub'),
          ),
          if (!installable) ...<Widget>[
            const SizedBox(height: Spacing.sm),
            Text(
              'No installable asset was published for this platform — '
              'the release page lists every build.',
              style: WavelyTypography.caption12(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime utc) {
    final DateTime local = utc.toLocal();
    return 'Published '
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

/// Live download progress (determinate when the server sends a length).
class _DownloadingView extends StatelessWidget {
  const _DownloadingView({
    required this.result,
    required this.received,
    required this.total,
  });

  final UpdateCheckResult result;
  final int received;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final double? fraction =
        total == null || total! <= 0 ? null : received / total!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          key: const Key('update-screen-progress'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Downloading ${result.latestVersion}',
              style: WavelyTypography.title18(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              result.assetName ?? '',
              style: WavelyTypography.caption12(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Spacing.lg),
            LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                colors.accentColors.accent,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              _progressLabel(),
              key: const Key('update-screen-progress-percent'),
              style: WavelyTypography.body14Medium(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _progressLabel() {
    final String receivedMb = (received / _bytesPerMb).toStringAsFixed(1);
    if (total == null || total! <= 0) {
      return '$receivedMb MB';
    }
    final String totalMb = (total! / _bytesPerMb).toStringAsFixed(1);
    final int percent = (received * 100 / total!).clamp(0, 100).round();
    return '$receivedMb / $totalMb MB ($percent%)';
  }
}

/// Installer hand-off state (spinner while the native side takes over).
class _InstallingView extends StatelessWidget {
  const _InstallingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.lg),
          Text(
            'Handing off to the installer…',
            style: WavelyTypography.body14(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Terminal outcome of the install attempt.
class _DoneView extends ConsumerWidget {
  const _DoneView({required this.outcome, required this.result});

  final UpdateInstallOutcome outcome;
  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final (IconData icon, Color color, String title, String detail) =
        switch (outcome) {
          UpdaterUiLaunched() => (
              Icons.install_mobile_rounded,
              colors.success,
              'Installer opened',
              'Confirm the system prompt to finish installing '
                  '${result.latestVersion}.',
            ),
          AppImageReplaced() => (
              Icons.autorenew_rounded,
              colors.success,
              'Update installed',
              'Wavely ${result.latestVersion} replaced the running AppImage '
                  'and is restarting.',
            ),
          OpenedReleasePage() => (
              Icons.open_in_new_rounded,
              colors.accentColors.accent,
              'Release page opened',
              'Finish in your browser — the download links live on '
                  'GitHub.',
            ),
          InstallFailed(:final message) => (
              Icons.error_outline_rounded,
              colors.error,
              'Update did not complete',
              message,
            ),
        };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          key: const Key('update-screen-done'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 64),
            const SizedBox(height: Spacing.lg),
            Text(
              title,
              key: outcome is InstallFailed
                  ? const Key('update-screen-error')
                  : null,
              style: WavelyTypography.title20(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              detail,
              style: WavelyTypography.body14(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            if (outcome is InstallFailed) ...<Widget>[
              FilledButton.icon(
                key: const Key('update-screen-retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accentColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize:
                      const Size.fromHeight(AppConstants.touchTargetMin),
                ),
                onPressed: () => ref
                    .read(updateFlowControllerProvider.notifier)
                    .startInstall(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            TextButton(
              onPressed: () => ref
                  .read(updateFlowControllerProvider.notifier)
                  .openReleasePage(),
              child: const Text('Open release page'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Check failure with retry.
class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message, required this.hasResult});

  final String message;
  final bool hasResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          key: const Key('update-screen-error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, color: colors.error, size: 64),
            const SizedBox(height: Spacing.lg),
            Text(
              'Something went wrong',
              style: WavelyTypography.title20(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              style: WavelyTypography.body14(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            FilledButton.icon(
              key: const Key('update-screen-retry'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accentColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(AppConstants.touchTargetMin),
              ),
              onPressed: () =>
                  ref.read(updateFlowControllerProvider.notifier).check(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check again'),
            ),
            if (hasResult) ...<Widget>[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: () => ref
                    .read(updateFlowControllerProvider.notifier)
                    .openReleasePage(),
                child: const Text('Open release page'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
