import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/data/remote/supabase_client_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/auth/data/telegram_auth_service.dart';
import 'package:wavely/features/auth/presentation/auth_disabled.dart';

/// Telegram passwordless sign-in (Stage 1.2, task B3).
///
/// 'Open Telegram' starts [TelegramAuthService.start]; while it polls, a
/// Timer-driven (pure Dart state) determinate [ProgressRing] + elapsed-seconds
/// text show progress — deliberately static-ish, no infinite animation, so
/// tests never need pumpAndSettle.
class TelegramLoginScreen extends ConsumerStatefulWidget {
  /// Creates the Telegram login screen.
  const TelegramLoginScreen({super.key});

  /// Route path for the orchestrator's router wiring.
  static const String route = '/telegram-login';

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  /// Mirrors [TelegramAuthService.timeout] default — only used for the
  /// determinate progress fraction (cosmetic).
  static const Duration _progressBudget = Duration(minutes: 5);

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _waiting = false;
  String? _errorText;

  Future<void> _openTelegram() async {
    if (_waiting) return;
    final service = ref.read(telegramAuthServiceProvider);
    setState(() {
      _waiting = true;
      _errorText = null;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    final result = await service.start();
    if (!mounted) return;
    _ticker?.cancel();
    _ticker = null;
    setState(() => _waiting = false);
    result.fold(
      onErr: (failure) => setState(() => _errorText = failure.message),
      onSuccess: (session) {
        final email = session?.user.email ?? 'your Telegram account';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signed in as $email')),
        );
        AuthDisabledView.backToSettings(context);
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    ref.read(telegramAuthServiceProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final authEnabled = ref.watch(authEnabledProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Sign in with Telegram',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: authEnabled
          ? _buildBody(context, colors)
          : AuthDisabledView(onBack: AuthDisabledView.backToSettings),
    );
  }

  Widget _buildBody(BuildContext context, WavelySemanticColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.bLg,
          border: Border.all(color: colors.borderGlass),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(
              Icons.send_rounded,
              size: 40,
              color: colors.accentColors.accent,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'No password needed',
              style: WavelyTypography.title18(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Opens a Telegram chat with a one-tap link. Press START and '
              'Wavely signs you in automatically.',
              style: WavelyTypography.body14(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.lg),
            if (_waiting) ...<Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ProgressRing(
                    value: _elapsed.inMilliseconds /
                        _progressBudget.inMilliseconds,
                    size: 20,
                  ),
                  const SizedBox(width: Spacing.md),
                  Flexible(
                    child: Text(
                      'Waiting for START in Telegram… '
                      '${_elapsed.inSeconds}s',
                      style: WavelyTypography.body14(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (_errorText != null) ...<Widget>[
              Text(
                _errorText!,
                key: const Key('telegram-error'),
                style: WavelyTypography.body14(color: colors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.md),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppConstants.touchTargetMin,
              ),
              child: FilledButton.icon(
                key: const Key('telegram-open'),
                onPressed: _waiting ? null : _openTelegram,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  _errorText == null ? 'Open Telegram' : 'Retry',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
