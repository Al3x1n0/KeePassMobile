/// Percorsi del router, in un unico punto.
abstract final class AppRoutes {
  static const fileSelect = '/';
  static const unlock = '/unlock';
  static const createDatabase = '/create';

  /// "Apri da server" (WebDAV).
  static const remoteOpen = '/remote';
  static const database = '/db';
  static const search = '$database/search';
  static const additionalDatabase = '$database/open';
  static const additionalUnlock = '$additionalDatabase/unlock';
  static const additionalRemote = '$additionalDatabase/remote';
  static const generator = '$database/generator';

  /// Impostazioni dell'app a database chiuso e aperto.
  static const appSettings = '/settings';
  static const appSettingsInDatabase = '$database/settings';

  /// Impostazioni e chiave principale del database aperto.
  static const databaseSettings = '$database/database-settings';
  static const changeMasterKey = '$database/change-key';

  static String group(String groupId) => '$database/group/$groupId';
  static String newEntry(String groupId) => '${group(groupId)}/new';
  static String entry(String entryId) => '$database/entry/$entryId';
  static String entryEdit(String entryId) => '${entry(entryId)}/edit';
  static String entryHistory(String entryId, int index) =>
      '${entry(entryId)}/history/$index';
}
