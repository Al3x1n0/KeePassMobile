# Modifiche di KeePassMobile a kpasslib

Copia locale di [kpasslib](https://pub.dev/packages/kpasslib) 1.1.2
(licenza MIT, `LICENSE` invariato), mantenuta in questo repository.
Il progetto upstream dichiara di derivare da KdbxWeb: la relativa licenza MIT
è conservata in `KDBXWEB_LICENSE`.

| Modifica | File | Motivo |
|---|---|---|
| Verifica credenziali contro la KDF corrente (`matchesTransformedKey`) senza modificare header o cache | `lib/src/kdbx/kdbx_header.dart` | Verifica della password attuale anche dopo sblocco biometrico |
| Cifrario Twofish-CBC (`CipherId.twofish`) | `lib/src/crypto/twofish.dart`, `lib/src/kdbx/constants.dart`, `lib/src/kdbx/kdbx_database.dart` | Supportato da Keepass2Android, assente upstream |
| Cifrario sconosciuto segnalato con `UnsupportedValueError` | `lib/src/kdbx/kdbx_database.dart` | Upstream lo segnalava come password errata |
| Chiave già derivata (`KdbxTransformedKey`, `KdbxCredentials.fromTransformedKey`, `KdbxHeader.transformedKey`, `kdfFingerprint`, `TransformedKeyStaleError`) | `lib/src/kdbx/kdbx_credentials.dart`, `lib/src/kdbx/kdbx_header.dart`, `lib/src/kdbx/kdbx_error.dart` | Sblocco biometrico e autofill iOS senza ripetere la KDF. Idea ripresa da `kdbx` 2.5.0 (`TransformedKeyCredentials`) |
| Con la sola chiave derivata il salvataggio non ruota il salt della KDF | `lib/src/kdbx/kdbx_header.dart` (`generateSalts`) | Senza chiave composta non si può rifare la KDF |
| Impostazioni della KDF leggibili e scrivibili (`KdfSettings`, `AesKdfSettings`, `Argon2KdfSettings`, `KdbxHeader.kdfSettings`) | `lib/src/kdbx/kdbx_kdf_settings.dart`, `lib/src/kdbx/kdbx_header.dart`, `lib/kpasslib.dart` | Creazione di database con Argon2id 64 MiB e modifica della KDF dalle impostazioni del database di KeePassMobile senza importare `src/` |
| Ripristino di una versione della cronologia (`KdbxEntry.restoreFromHistory`) | `lib/src/kdbx/kdbx_entry.dart` | Cronologia visibile in KeePassMobile, come `PwEntry.RestoreFromBackup` |
| Importazione tra database: riallineamento allegati e icone anche nella cronologia, conservazione metadati | `lib/src/kdbx/kdbx_database.dart` | Evitare riferimenti errati o perdita di dati nell’importazione |
| Dipendenza `pointycastle` | `pubspec.yaml` | Motore Twofish |
| Esportati `Aes256`, `ChaCha20`, `Salsa20`, `Argon2`, `CryptoDart` | `lib/kpasslib.dart` | Permettere un `CryptoEngine` personalizzato (Argon2 nativo) senza importare `src/` |
| Limiti di dimensione e costo della derivazione in apertura | `lib/src/kdbx/kdbx_resource_limits.dart`, `kdbx_database.dart`, `kdbx_header.dart`, `kdbx_binaries.dart`, `lib/src/crypto/key_encryptor_kdf.dart` | Limitare la memoria e il lavoro di lettura, inclusi gli allegati compressi di KDBX 3. Richiede il limite di output GZip di archive 4.6 o successivo |
| Verifica del terminatore HMAC e della fine del flusso KDBX 4 | `lib/src/crypto/hmac_block_transform.dart` | Rifiutare i flussi senza terminatore autenticato o con dati residui |
| Azzeramento dei buffer di credenziali e valori protetti | `lib/src/crypto/protected_value.dart`, `lib/src/kdbx/kdbx_credentials.dart`, `kdbx_header.dart`, `kdbx_database.dart` | Ridurre la permanenza dei valori sensibili dopo il blocco |

Test aggiunti: `test/crypto/twofish_test.dart`,
`test/kdbx/keepassmobile_extensions_test.dart`.

Nella fixture sintetica upstream `assets/test/merge.kdbx` è stato autenticato
il terminatore KDBX 4. Il resto del file resta identico alla fixture originale.

Le modifiche sono candidate a essere proposte upstream.
