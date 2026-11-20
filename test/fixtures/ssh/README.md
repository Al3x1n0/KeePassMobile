# Chiave SSH sintetica

`client_ed25519.pem` è una chiave Ed25519 OpenSSH generata esclusivamente per i
test, cifrata con la passphrase pubblica `synthetic-passphrase`. Non autorizza
l'accesso a sistemi esterni e non va usata con dati reali.

Serve per verificare decifratura, passphrase errata e separazione delle callback
non trasferibili fra isolate. Generata con `ssh-keygen`, commento
`kpm-synthetic-client`; non contiene nomi o percorsi personali.
