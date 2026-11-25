import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/database/database_session.dart';
import 'password_audit.dart';

final passwordCheckReportProvider = Provider.autoDispose<PasswordCheckReport?>((
  ref,
) {
  final session = ref.watch(databaseSessionProvider);
  return session == null ? null : auditPasswords(session.database);
});
