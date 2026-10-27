// authored, awaiting local run.
//
// Table test for lib/features/auth/data/auth_guard.dart's pure decision
// function: protected-prefix matching, the hasSupabase=false short-circuit
// (auth is a hidden feature → bounce to /settings), the unauthenticated →
// /login redirect, and public-path no-ops.
//
// NOTE: WavelyEnv.hasSupabase is a compile-time flag that cannot be flipped
// at test runtime — the guard takes `hasSupabase` as a plain parameter
// (that IS the seam), so both branches are table-tested here. The
// GoRouterState adapter (authGuardFromState) is a one-line mapping over
// state.uri.path and is covered indirectly by the location strings below.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/auth/data/auth_guard.dart';

void main() {
  group('protectedRoutePrefixes contract', () {
    test('covers exactly the documented protected routes', () {
      expect(
        protectedRoutePrefixes,
        <String>['/settings/account', '/ai-chat'],
      );
    });
  });

  group('authGuard decision table', () {
    const hasSupabase = true;

    test('public paths never redirect, whatever the auth state', () {
      const publicLocations = <String>[
        '/library',
        '/library/albums/1',
        '/settings',
        '/settings/playback',
        '/onboarding',
        '/now-playing',
        '/login',
        '/signup',
        '/',
      ];
      for (final location in publicLocations) {
        for (final authenticated in <bool>[true, false]) {
          expect(
            authGuard(
              hasSupabase: hasSupabase,
              isAuthenticated: authenticated,
              location: location,
            ),
            isNull,
            reason: 'public path $location must not redirect '
                '(authenticated=$authenticated)',
          );
        }
      }
    });

    test('protected path + supabase + unauthenticated → /login', () {
      for (final location in const <String>[
        '/settings/account',
        '/settings/account/delete',
        '/ai-chat',
        '/ai-chat/history',
      ]) {
        expect(
          authGuard(
            hasSupabase: hasSupabase,
            isAuthenticated: false,
            location: location,
          ),
          '/login',
          reason: '$location requires a session',
        );
      }
    });

    test('protected path + supabase + authenticated → no redirect', () {
      for (final location in const <String>[
        '/settings/account',
        '/settings/account/delete',
        '/ai-chat',
        '/ai-chat/history',
      ]) {
        expect(
          authGuard(
            hasSupabase: hasSupabase,
            isAuthenticated: true,
            location: location,
          ),
          isNull,
          reason: '$location allows signed-in users',
        );
      }
    });

    test('hasSupabase=false short-circuits: protected paths bounce to '
        '/settings regardless of the (irrelevant) session state', () {
      for (final location in const <String>[
        '/settings/account',
        '/settings/account/delete',
        '/ai-chat',
        '/ai-chat/history',
      ]) {
        for (final authenticated in <bool>[true, false]) {
          expect(
            authGuard(
              hasSupabase: false,
              isAuthenticated: authenticated,
              location: location,
            ),
            '/settings',
            reason: 'auth feature hidden without Supabase: $location',
          );
        }
      }
    });

    test('hasSupabase=false leaves every public path alone', () {
      for (final location in const <String>['/library', '/settings', '/']) {
        expect(
          authGuard(
            hasSupabase: false,
            isAuthenticated: false,
            location: location,
          ),
          isNull,
        );
      }
    });
  });

  group('prefix matching rules', () {
    test('a path that merely STARTS WITH the prefix text is NOT protected '
        '(segment boundaries only)', () {
      expect(
        authGuard(
          hasSupabase: true,
          isAuthenticated: false,
          location: '/settings/accounting',
        ),
        isNull, // '/settings/accounting' != '/settings/account' and has no
        // '/settings/account/' prefix.
      );
      expect(
        authGuard(
          hasSupabase: true,
          isAuthenticated: false,
          location: '/ai-chatter',
        ),
        isNull,
      );
    });

    test('query strings and fragments do not affect protection', () {
      expect(
        authGuard(
          hasSupabase: true,
          isAuthenticated: false,
          location: '/settings/account?tab=billing#top',
        ),
        '/login',
      );
      expect(
        authGuard(
          hasSupabase: false,
          isAuthenticated: false,
          location: '/ai-chat?new=1',
        ),
        '/settings',
      );
    });

    test('root and near-miss paths stay public', () {
      expect(
        authGuard(
          hasSupabase: true,
          isAuthenticated: false,
          location: '/account',
        ),
        isNull,
      );
    });
  });
}
