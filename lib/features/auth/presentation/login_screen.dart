import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/data/remote/supabase_client_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/auth/data/auth_repository.dart';
import 'package:wavely/features/auth/presentation/auth_disabled.dart';
import 'package:wavely/features/auth/presentation/signup_screen.dart';
import 'package:wavely/features/auth/presentation/telegram_login_screen.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';

/// E-mail + password sign-in (Stage 1.2, task B3).
///
/// Solid token-styled containers only (no GlassCard / BackdropFilter).
class LoginScreen extends ConsumerStatefulWidget {
  /// Creates the login screen.
  const LoginScreen({super.key});

  /// Route path for the orchestrator's router wiring (auth-guard target).
  static const String route = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email';
    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  void _popToRoot() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(LibraryScreen.libraryRoute);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repository = ref.read(authRepositoryProvider);
    setState(() => _submitting = true);
    final result = await repository.signInWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.fold(
      onErr: (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      },
      onSuccess: (_) => _popToRoot(),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
          'Sign in',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: authEnabled
          ? _buildForm(context, colors)
          : AuthDisabledView(onBack: AuthDisabledView.backToSettings),
    );
  }

  Widget _buildForm(BuildContext context, WavelySemanticColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Form(
        key: _formKey,
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
              TextFormField(
                key: const Key('login-email'),
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: _validateEmail,
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                key: const Key('login-password'),
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                obscureText: true,
                autofillHints: const <String>[AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                validator: _validatePassword,
              ),
              const SizedBox(height: Spacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppConstants.touchTargetMin,
                ),
                child: FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting ? 'Signing in…' : 'Sign in',
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    onPressed: () => context.push(SignUpScreen.route),
                    child: const Text('Create account'),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.push(TelegramLoginScreen.route),
                    child: const Text('Sign in with Telegram'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
