import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/preferences.dart';

/// Impostazioni dell'app (`pref_app_security.xml` e `pref_app_display.xml` di
/// Keepass2Android). Nessun valore sensibile: stanno nelle preferenze (SEC-03).
@immutable
class AppSettings {
  const AppSettings({
    this.clipboardTimeout = defaultClipboardTimeout,
    this.lockTimeout = defaultLockTimeout,
    this.lockOnScreenOff = false,
    this.secureScreen = true,
    this.openNotification = true,
    this.maskPassword = true,
    this.maskTotp = true,
    this.expireTanOnOpen = true,
    this.showUserNameInList = true,
    this.showGroupNameInSearch = true,
    this.showGroupInEntry = false,
    this.listTextSize = 20,
    this.rememberRecentFiles = true,
    this.rememberKeyFile = true,
    this.cacheRemoteFiles = true,
    this.themeMode = ThemeMode.system,
  });

  /// 30 secondi al posto dei 5 minuti di
  /// Keepass2Android.
  static const defaultClipboardTimeout = Duration(seconds: 30);

  /// Tempi ammessi per la pulizia degli appunti (decisione D5):
  /// a differenza di Keepass2Android non c'è "mai".
  static const clipboardTimeouts = [
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 180),
    Duration(seconds: 240),
  ];

  static const defaultLockTimeout = Duration(minutes: 5);

  /// Tempi ammessi per il blocco per inattività (`app_timeout_key` di
  /// Keepass2Android); `null` vuol dire "mai".
  static const lockTimeouts = <Duration?>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
    null,
  ];

  /// Pulizia degli appunti dopo una copia (`clip_timeout_key`).
  final Duration clipboardTimeout;

  /// Blocco dopo questo tempo senza interazioni; `null`: mai.
  final Duration? lockTimeout;

  /// Blocco allo spegnimento dello schermo (`LockWhenScreenOff`); su iOS al
  /// blocco del dispositivo.
  final bool lockOnScreenOff;

  /// Niente screenshot, registrazioni e anteprima tra le app recenti
  /// (`ViewDatabaseSecure`).
  final bool secureScreen;

  /// Notifica fissa con "Blocca" mentre un database è aperto, solo Android
  /// (`ShowUnlockedNotification`, attiva di default come Keepass2Android).
  final bool openNotification;

  /// Password e campi protetti nascosti all'apertura della voce (`maskpass`).
  final bool maskPassword;

  /// Codici e segreti TOTP nascosti all'apertura della voce (`masktotp`).
  final bool maskTotp;

  /// Segna le voci TAN come scadute quando vengono aperte.
  final bool expireTanOnOpen;

  /// Nome utente sotto il titolo negli elenchi (`ShowUsernameInList_key`).
  final bool showUserNameInList;

  /// Nome del gruppo nei risultati di ricerca.
  final bool showGroupNameInSearch;
  final bool showGroupInEntry;
  final int listTextSize;
  static const listTextSizes = [15, 20, 28];

  /// Elenco dei file recenti (`RememberRecentFiles_key`).
  final bool rememberRecentFiles;

  /// File chiave associato al database nei file recenti (`keyfile`).
  final bool rememberKeyFile;

  /// Copia cifrata dei database remoti per uso offline (ADR-017).
  final bool cacheRemoteFiles;

  /// Tema (`design_key`).
  final ThemeMode themeMode;

  static const _keep = Object();

  /// Copia con i valori indicati. [lockTimeout] accetta anche `null` ("mai").
  AppSettings copyWith({
    Duration? clipboardTimeout,
    Object? lockTimeout = _keep,
    bool? lockOnScreenOff,
    bool? secureScreen,
    bool? openNotification,
    bool? maskPassword,
    bool? maskTotp,
    bool? expireTanOnOpen,
    bool? showUserNameInList,
    bool? showGroupNameInSearch,
    bool? showGroupInEntry,
    int? listTextSize,
    bool? rememberRecentFiles,
    bool? rememberKeyFile,
    bool? cacheRemoteFiles,
    ThemeMode? themeMode,
  }) => AppSettings(
    clipboardTimeout: clipboardTimeout ?? this.clipboardTimeout,
    lockTimeout: identical(lockTimeout, _keep)
        ? this.lockTimeout
        : lockTimeout as Duration?,
    lockOnScreenOff: lockOnScreenOff ?? this.lockOnScreenOff,
    secureScreen: secureScreen ?? this.secureScreen,
    openNotification: openNotification ?? this.openNotification,
    maskPassword: maskPassword ?? this.maskPassword,
    maskTotp: maskTotp ?? this.maskTotp,
    expireTanOnOpen: expireTanOnOpen ?? this.expireTanOnOpen,
    showUserNameInList: showUserNameInList ?? this.showUserNameInList,
    showGroupNameInSearch: showGroupNameInSearch ?? this.showGroupNameInSearch,
    showGroupInEntry: showGroupInEntry ?? this.showGroupInEntry,
    listTextSize: listTextSize ?? this.listTextSize,
    rememberRecentFiles: rememberRecentFiles ?? this.rememberRecentFiles,
    rememberKeyFile: rememberKeyFile ?? this.rememberKeyFile,
    cacheRemoteFiles: cacheRemoteFiles ?? this.cacheRemoteFiles,
    themeMode: themeMode ?? this.themeMode,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.clipboardTimeout == clipboardTimeout &&
      other.lockTimeout == lockTimeout &&
      other.lockOnScreenOff == lockOnScreenOff &&
      other.secureScreen == secureScreen &&
      other.openNotification == openNotification &&
      other.maskPassword == maskPassword &&
      other.maskTotp == maskTotp &&
      other.expireTanOnOpen == expireTanOnOpen &&
      other.showUserNameInList == showUserNameInList &&
      other.showGroupNameInSearch == showGroupNameInSearch &&
      other.showGroupInEntry == showGroupInEntry &&
      other.listTextSize == listTextSize &&
      other.rememberRecentFiles == rememberRecentFiles &&
      other.rememberKeyFile == rememberKeyFile &&
      other.cacheRemoteFiles == cacheRemoteFiles &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(
    clipboardTimeout,
    lockTimeout,
    lockOnScreenOff,
    secureScreen,
    openNotification,
    maskPassword,
    maskTotp,
    expireTanOnOpen,
    showUserNameInList,
    showGroupNameInSearch,
    showGroupInEntry,
    listTextSize,
    rememberRecentFiles,
    rememberKeyFile,
    cacheRemoteFiles,
    themeMode,
  );
}

/// Lettura e salvataggio delle impostazioni nelle preferenze. Un valore non
/// ammesso (ad esempio salvato da una versione precedente) torna al
/// predefinito.
class AppSettingsRepository {
  AppSettingsRepository(this._prefs);

  static const _clipboardTimeout = 'settings.clipboard_timeout_ms';
  static const _lockTimeout = 'settings.lock_timeout_ms';
  static const _lockOnScreenOff = 'settings.lock_on_screen_off';
  static const _secureScreen = 'settings.secure_screen';
  static const _openNotification = 'settings.open_notification';
  static const _maskPassword = 'settings.mask_password';
  static const _maskTotp = 'settings.mask_totp';
  static const _expireTanOnOpen = 'settings.expire_tan_on_open';
  static const _showUserNameInList = 'settings.show_user_name_in_list';
  static const _showGroupNameInSearch = 'settings.show_group_name_in_search';
  static const _showGroupInEntry = 'settings.show_group_in_entry';
  static const _listTextSize = 'settings.list_text_size';
  static const _rememberRecentFiles = 'settings.remember_recent_files';
  static const _rememberKeyFile = 'settings.remember_key_file';
  static const _cacheRemoteFiles = 'settings.cache_remote_files';
  static const _themeMode = 'settings.theme_mode';

  /// Impostazioni di QuickUnlock, tolto in D22: si cancellano al salvataggio.
  static const _removed = [
    'settings.quick_unlock',
    'settings.quick_unlock_length',
    'settings.quick_unlock_hide_length',
  ];

  /// Permesso per le notifiche già chiesto: non è un'impostazione.
  static const _permissionRequested = 'notifications.permission_requested';

  /// "Mai" nel blocco per inattività, come Keepass2Android.
  static const _never = -1;

  final SharedPreferences _prefs;

  AppSettings load() {
    const defaults = AppSettings();
    bool flag(String key, bool fallback) => _prefs.getBool(key) ?? fallback;
    return AppSettings(
      clipboardTimeout:
          _allowed(
            _prefs.getInt(_clipboardTimeout),
            AppSettings.clipboardTimeouts,
          ) ??
          defaults.clipboardTimeout,
      lockTimeout: switch (_prefs.getInt(_lockTimeout)) {
        null => defaults.lockTimeout,
        _never => null,
        final ms =>
          _allowed(ms, AppSettings.lockTimeouts) ?? defaults.lockTimeout,
      },
      lockOnScreenOff: flag(_lockOnScreenOff, defaults.lockOnScreenOff),
      secureScreen: flag(_secureScreen, defaults.secureScreen),
      openNotification: flag(_openNotification, defaults.openNotification),
      maskPassword: flag(_maskPassword, defaults.maskPassword),
      maskTotp: flag(_maskTotp, defaults.maskTotp),
      expireTanOnOpen: flag(_expireTanOnOpen, defaults.expireTanOnOpen),
      showUserNameInList: flag(
        _showUserNameInList,
        defaults.showUserNameInList,
      ),
      showGroupNameInSearch: flag(
        _showGroupNameInSearch,
        defaults.showGroupNameInSearch,
      ),
      showGroupInEntry: flag(_showGroupInEntry, defaults.showGroupInEntry),
      listTextSize:
          AppSettings.listTextSizes.contains(_prefs.getInt(_listTextSize))
          ? _prefs.getInt(_listTextSize)!
          : defaults.listTextSize,
      rememberRecentFiles: flag(
        _rememberRecentFiles,
        defaults.rememberRecentFiles,
      ),
      rememberKeyFile: flag(_rememberKeyFile, defaults.rememberKeyFile),
      cacheRemoteFiles: flag(_cacheRemoteFiles, defaults.cacheRemoteFiles),
      themeMode:
          ThemeMode.values.asNameMap()[_prefs.getString(_themeMode)] ??
          defaults.themeMode,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setInt(
      _clipboardTimeout,
      settings.clipboardTimeout.inMilliseconds,
    );
    await _prefs.setInt(
      _lockTimeout,
      settings.lockTimeout?.inMilliseconds ?? _never,
    );
    await _prefs.setBool(_lockOnScreenOff, settings.lockOnScreenOff);
    await _prefs.setBool(_secureScreen, settings.secureScreen);
    await _prefs.setBool(_openNotification, settings.openNotification);
    await _prefs.setBool(_maskPassword, settings.maskPassword);
    await _prefs.setBool(_maskTotp, settings.maskTotp);
    await _prefs.setBool(_expireTanOnOpen, settings.expireTanOnOpen);
    await _prefs.setBool(_showUserNameInList, settings.showUserNameInList);
    await _prefs.setBool(
      _showGroupNameInSearch,
      settings.showGroupNameInSearch,
    );
    await _prefs.setBool(_showGroupInEntry, settings.showGroupInEntry);
    await _prefs.setInt(_listTextSize, settings.listTextSize);
    await _prefs.setBool(_rememberRecentFiles, settings.rememberRecentFiles);
    await _prefs.setBool(_rememberKeyFile, settings.rememberKeyFile);
    await _prefs.setBool(_cacheRemoteFiles, settings.cacheRemoteFiles);
    await _prefs.setString(_themeMode, settings.themeMode.name);
    for (final key in _removed) {
      await _prefs.remove(key);
    }
  }

  /// `true` se il permesso per le notifiche è già stato chiesto (alla prima
  /// apertura di un database, decisione D19).
  bool get notificationPermissionRequested =>
      _prefs.getBool(_permissionRequested) ?? false;

  Future<void> markNotificationPermissionRequested() =>
      _prefs.setBool(_permissionRequested, true);

  static Duration? _allowed(int? ms, List<Duration?> allowed) {
    for (final duration in allowed) {
      if (duration != null && duration.inMilliseconds == ms) return duration;
    }
    return null;
  }
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// Impostazioni correnti, per tutta l'app.
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(appSettingsRepositoryProvider).load();

  /// Applica subito [settings] e li salva.
  Future<void> update(AppSettings settings) async {
    state = settings;
    await ref.read(appSettingsRepositoryProvider).save(settings);
  }
}
