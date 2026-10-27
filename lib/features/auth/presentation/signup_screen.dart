import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/data/remote/supabase_client_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/auth/data/auth_repository.dart';
import 'package:wavely/features/auth/presentation/auth_disabled.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';

/// E-mail + password sign-up (Stage 1.2, task B3).
///
/// Solid token-styled containers only (no GlassCard / BackdropFilter).
class SignUpScreen extends ConsumerStatefulWidget {
  /// Creates the sign-up screen.
  const SignUpScreen({super.key});

  /// Route path for the orchestrator's router wiring.
  static const String route = '/signup';

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
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

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
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
    final result = await repository.signUpWithEmail(
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
      onSuccess: (session) {
        // Null session = the project requires e-mail confirmation; the
        // account exists but is not signed in yet (see AuthRepository note).
        final message = session == null
            ? 'Check your inbox — confirm your email, then sign in.'
            : 'Welcome to Wavely!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        _popToRoot();
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
          'Create account',
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
                key: const Key('signup-email'),
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
                key: const Key('signup-password'),
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                obscureText: true,
                autofillHints: const <String>[AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: _validatePassword,
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                key: const Key('signup-confirm'),
                controller: _confirmController,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                obscureText: true,
                autofillHints: const <String>[AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                validator: _validateConfirm,
              ),
              const SizedBox(height: Spacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppConstants.touchTargetMin,
                ),
                child: FilledButton(
                  key: const Key('signup-submit'),
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting ? 'Creating account…' : 'Create account',
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
