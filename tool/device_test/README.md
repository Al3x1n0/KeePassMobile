# Prove sul telefono

Strumenti per le prove manuali di KeePassMobile su un telefono Android collegato
con adb. Contengono solo dati finti.

| File | Uso |
|---|---|
| `kpm_adb.py` | funzioni adb: `dump`, `find`, `tap`, `wait_for`, `screen_texts`, `edit_texts`, `type_text`, `key`, `shot`, `push_demo`, `cleanup_device`, `verify`; `L` contiene le stringhe ARB nella lingua del telefono |
| `kpm_settings_reader.py` | `read_clipboard_in_settings(tag)`: legge gli appunti incollandoli nella ricerca delle Impostazioni |
| `verify/` | programma Dart che apre un database con kpasslib e ne stampa la struttura (valori protetti mascherati) |
| `kpm_webdav.py` | server WebDAV HTTPS di prova (Basic, certificato autofirmato): `python3 kpm_webdav.py <cartella> <porta> <utente> <password>`, poi `adb reverse tcp:<porta> tcp:<porta>` e `https://localhost:<porta>/` dal telefono |
| `kpm_sftp.py` | server SFTP locale con paramiko, autenticazione sintetica demo/sftp-demo; `--root`, `--host-key`, porta predefinita 18445; usare `adb reverse tcp:18445 tcp:18445` |
| `kpm_sftp_smoke_test.dart` | prova client contro OpenSSH locale; cartella temporanea e chiavi sintetiche passate con `KPM_SFTP_TEST_ROOT` |
| `KeePassMobile_demo.kdbx` | database demo con dati finti, chiave `demo1234`, Argon2 64 MiB / 2 iterazioni / 2 thread |

## Regole

- Build installate solo con `adb install -r` (mai `flutter run` o `flutter test` sul telefono).
- **Release:** `fvm flutter build apk --release --target-platform android-arm64` e
  `adb install -r build/app/outputs/flutter-apk/app-release.apk`. La release fa i
  controlli di integrità del dispositivo (D9, D10): con opzioni sviluppatore o debug USB attivi
  mostra la schermata di blocco.
- **Release di prova sul telefono:** aggiungere `--dart-define=KPM_DEVICE_TEST=true`, che salta
  solo i controlli delle opzioni sviluppatore e del debugger (D10, D15); tutti gli altri
  controlli restano attivi.
- **Profile** (`--profile`, file `app-profile.apk`): nessun controllo del dispositivo e nessuno
  schermo protetto; solo per prove di funzioni non legate alla sicurezza.

## Esempio

```python
exec(open('tool/device_test/kpm_adb.py').read())
push_demo()
sh('monkey', '-p', PKG, '-c', 'android.intent.category.LAUNCHER', '1')
tap(L['fileSelectOpenFile'])
# ... selettore di sistema, sblocco con 'demo1234', azioni ...
print(verify())
cleanup_device()
```

Prima del primo `verify()`: `fvm dart pub get` in `verify/`.

Gli output di `kpm_adb.py` restano nella directory temporanea `kpm_device_test`
(o in `KPM_SHOTS` se impostata), esterna al repository.

Per il server SFTP preparare un ambiente Python temporaneo con `paramiko`,
usare una cartella contenente solo copie dei dati demo e una chiave host
sintetica esterna al repository. L'impronta viene stampata all'avvio e va
confrontata con quella mostrata nell'app. La porta è esposta soltanto su loopback.
