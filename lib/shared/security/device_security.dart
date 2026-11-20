import 'package:app_security/app_security.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Eventi di schermo spento (Android), dispositivo bloccato (iOS) e presenza
/// di una biometria registrata.
final appSecurityProvider = Provider<AppSecurity>((_) => const AppSecurity());
