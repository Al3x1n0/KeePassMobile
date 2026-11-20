# flutter_secure_storage 11.2.0 — copia di KeePassMobile

Copia di [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) 11.2.0
(BSD-3-Clause, `LICENSE`), solo `lib/` e `android/`; iOS usa il pacchetto pubblicato
`flutter_secure_storage_darwin`. La copia include le correzioni necessarie per lo sblocco biometrico.

Va rimossa quando una versione pubblicata contiene entrambe le correzioni.

## Correzioni (solo Android, `FlutterSecureStorage.java` e `FlutterSecureStoragePlugin.java`)

1. **Pulsante negativo della richiesta biometrica.** Con `AndroidBiometricType.strongBiometricOnly`
   (e prima di Android 11) il pulsante negativo aveva un'azione vuota `(dialog, which) -> {}`: il
   sistema chiude la richiesta senza chiamare `onAuthenticationError`, quindi `read`/`write` non
   rispondono mai. Ora risponde con l'errore `Biometric authentication error [13]` (come
   `BIOMETRIC_ERROR_NEGATIVE_BUTTON`); un `AtomicBoolean` garantisce una sola risposta.
2. **Testi della richiesta.** `initialize` salva la configurazione solo alla prima chiamata, quindi
   titolo, sottotitolo e pulsante negativo restavano quelli della prima operazione del processo
   (anche i predefiniti inglesi, se era una `delete`). Ora il plugin passa a ogni chiamata la
   configurazione con i testi (`setPromptConfig`), usata solo per la richiesta.

## Segnalazione al progetto (da aprire su GitHub, mogol/flutter_secure_storage)

**Titolo:** Android: negative button of the biometric prompt never completes the call; prompt texts stuck to the first call

**Testo:**

> Version 11.2.0, Android 16 (Motorola moto g85), `AndroidOptions.biometric(enforceBiometrics: true,
> requireBiometricsPerOperation: true, biometricType: AndroidBiometricType.strongBiometricOnly)`.
>
> 1. In `FlutterSecureStorage.authenticateUser` the negative button listener is
>    `(dialog, which) -> {}`. Framework `BiometricPrompt` calls only that listener when the negative
>    button is tapped (no `onAuthenticationError`), so the pending `read`/`write` future never
>    completes. Expected: the call fails like `BIOMETRIC_ERROR_NEGATIVE_BUTTON`.
> 2. `initialize()` returns early once `preferences` is set, so `config` (and therefore
>    `biometricPromptTitle`/`Subtitle`/`NegativeButton`) is the one of the first call on that
>    storage instance. Texts passed in later calls are ignored; if the first call was `delete`
>    (no texts), the default English texts are shown forever.
>
> Patch used in our app: complete the callback from the negative button listener (guarded by an
> `AtomicBoolean`) and keep a per-call prompt configuration for the prompt texts.
