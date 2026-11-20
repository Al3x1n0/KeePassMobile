# Database KeePass di test

File copiati da [pykeepass](https://github.com/libkeepass/pykeepass/tree/master/tests)
(licenza GPLv3), usati solo nei test di compatibilità.

Contengono esclusivamente dati fittizi. Password: `password` (vuota per
`test4_blankpass.kdbx`); file chiave indicati in `test/kdbx/compat_fixtures_test.dart`.

| File | Formato | Cifrario | KDF | Chiave |
|---|---|---|---|---|
| test3.kdbx | KDBX 3.1 | AES | AES-KDF | password + test3.key (XML v1) |
| test4.kdbx | KDBX 4.0 | ChaCha20 | Argon2 | password + test4.key (binario) |
| test4_aes.kdbx | KDBX 4.0 | AES | Argon2 | password + test4.key |
| test4_aeskdf.kdbx | KDBX 4.0 | AES | AES-KDF | password + test4.key |
| test4_chacha20.kdbx | KDBX 4.0 | ChaCha20 | Argon2 | password + test4.key |
| test4_twofish.kdbx | KDBX 4.0 | Twofish | Argon2 | password + test4.key |
| test4_hex.kdbx | KDBX 4.0 | ChaCha20 | Argon2 | password + test4_hex.key (64 hex) |
| test4_aes_uncompressed.kdbx | KDBX 4.0 | AES, senza compressione | Argon2 | password |
| test4_chacha20_uncompressed.kdbx | KDBX 4.0 | ChaCha20, senza compressione | Argon2 | password |
| test4_argon2id.kdbx | KDBX 4.0 | AES | Argon2id | password |
| test4_blankpass.kdbx | KDBX 4.0 | AES | Argon2 | password vuota + test4.key |
| test4_keyx.kdbx | KDBX 4.0 | ChaCha20 | Argon2 | password + test4_keyx.keyx (XML v2) |
