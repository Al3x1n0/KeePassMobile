# Modifiche di KeePassMobile a kpasslib

Copia locale di [kpasslib](https://pub.dev/packages/kpasslib) 1.1.2
(licenza MIT, `LICENSE` invariato), mantenuta in questo repository.
Il progetto upstream dichiara di derivare da KdbxWeb: la relativa licenza MIT
è conservata in `KDBXWEB_LICENSE`.

| Modifica | File | Motivo |
|---|---|---|
| Cifrario Twofish-CBC (`CipherId.twofish`) | `lib/src/crypto/twofish.dart`, `lib/src/kdbx/constants.dart`, `lib/src/kdbx/kdbx_database.dart` | Supportato da Keepass2Android, assente upstream |
| Cifrario sconosciuto segnalato con `UnsupportedValueError` | `lib/src/kdbx/kdbx_database.dart` | Upstream lo segnalava come password errata |
| Chiave già derivata (`KdbxTransformedKey`, `KdbxCredentials.fromTransformedKey`, `KdbxHeader.transformedKey`, `kdfFingerprint`, `TransformedKeyStaleError`) | `lib/src/kdbx/kdbx_credentials.dart`, `lib/src/kdbx/kdbx_header.dart`, `lib/src/kdbx/kdbx_error.dart` | Sblocco biometrico e autofill iOS senza ripetere la KDF. Idea ripresa da `kdbx` 2.5.0 (`TransformedKeyCredentials`) |
| Con la sola chiave derivata il salvataggio non ruota il salt della KDF | `lib/src/kdbx/kdbx_header.dart` (`generateSalts`) | Senza chiave composta non si può rifare la KDF |
| Impostazioni della KDF leggibili e scrivibili (`KdfSettings`, `AesKdfSettings`, `Argon2KdfSettings`, `KdbxHeader.kdfSettings`) | `lib/src/kdbx/kdbx_kdf_settings.dart`, `lib/src/kdbx/kdbx_header.dart`, `lib/kpasslib.dart` | Creazione di database con Argon2id 64 MiB e modifica della KDF dalle impostazioni del database di KeePassMobile senza importare `src/` |
| Ripristino di una versione della cronologia (`KdbxEntry.restoreFromHistory`) | `lib/src/kdbx/kdbx_entry.dart` | Cronologia visibile in KeePassMobile, come `PwEntry.RestoreFromBackup` |
| Importazione tra database: riallineamento allegati e icone anche nella cronologia, conservazione metadati | `lib/src/kdbx/kdbx_database.dart` | Evitare riferimenti errati o perdita di dati nell’importazione |
| Dipendenza `pointycastle` | `pubspec.yaml` | Motore Twofish |
| Esportati `Aes256`, `ChaCha20`, `Salsa20`, `Argon2`, `CryptoDart` | `lib/kpasslib.dart` | Permettere un `CryptoEngine` personalizzato (Argon2 nativo) senza importare `src/` |

Test aggiunti: `test/crypto/twofish_test.dart`,
`test/kdbx/keepassmobile_extensions_test.dart`.

Le modifiche sono candidate a essere proposte upstream.
