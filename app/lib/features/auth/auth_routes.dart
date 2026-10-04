// Auth feature routes (features/README). Mounted on the root navigator.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import 'auth_paths.dart';
import 'http_auth_client.dart';
import 'screens/s0_2_phone_otp_screen.dart';
import 'screens/s19_1_update_required_screen.dart';

export 'auth_paths.dart';

/// S0.2 at [AuthPaths.phoneOtp]; S19.1 at [AuthPaths.updateRequired] with the
/// gate passed as `extra` (an [UpdateRequired]).
final List<RouteBase> authRoutes = [
  GoRoute(
    path: AuthPaths.phoneOtp,
    builder: (context, state) => PhoneOtpScreen(
      onDone: (_) => context.go(RkPaths.home),
      // ADR 2026-10-04b §3: *Get my books back* opens S11.6, the fork — the
      // screen's own default, shared with the F1 signup route.
    ),
  ),
  GoRoute(
    path: AuthPaths.updateRequired,
    builder: (context, state) {
      final extra = state.extra;
      return UpdateRequiredScreen(
        gate: extra is UpdateRequired
            ? extra
            : const UpdateRequired(currentVersion: '', requiredVersion: ''),
      );
    },
  ),
];
