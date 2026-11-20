# Legge gli appunti del telefono incollandoli nel campo di ricerca delle
# Impostazioni (un'app in background non può leggerli da Android 10).
# Uso: dopo kpm_adb.py,  exec(open('tool/device_test/kpm_settings_reader.py').read())
def _fields(): return [n for n in dump() if n.get('class') in ('android.widget.EditText','android.widget.AutoCompleteTextView')]
def read_clipboard_in_settings(tag):
    sh('am','start','-a','android.settings.SETTINGS'); time.sleep(2.5)
    f=_fields()
    if not f:
        s=wait_for('Cerca',6)
        if s: tap_node(s[0]); time.sleep(2)
        f=_fields()
    if not f: return 'campo di ricerca non trovato: '+str(screen_texts()[:10])
    tap_node(f[0]); time.sleep(0.8)
    key(279); time.sleep(1.2)          # KEYCODE_PASTE, gestito da TextView
    t=_fields()[0].get('text') or ''
    shot(tag)
    res=repr('' if t=='Cerca…' else t)
    clear_field(40); key('KEYCODE_BACK'); time.sleep(0.5); key('KEYCODE_HOME'); time.sleep(1)
    return res
