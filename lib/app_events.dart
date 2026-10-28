import 'package:flutter/foundation.dart';

import 'auto_backup.dart';
import 'notifications.dart';

/// Sinal global de "os dados mudaram" para as telas se recarregarem.
class AppEvents {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Atualiza as telas e agenda o backup automático.
  static void changed() {
    revision.value++;
    AutoBackup.schedule();
  }

  /// Após alterar dados que afetam a agenda: reagenda avisos e atualiza a UI.
  static Future<void> dataChanged() async {
    changed();
    await NotificationService.rescheduleAll();
  }
}
