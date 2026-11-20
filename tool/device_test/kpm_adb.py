# Pilotaggio del telefono con adb per le prove manuali di KeePassMobile.
# Uso, dalla root del repo:  exec(open('tool/device_test/kpm_adb.py').read())
# Variabili: KPM_SERIAL (telefono; se manca, il primo di `adb devices`), KPM_DB_KEY
# (chiave del database di prova).
# Solo build di release installate con `adb install -r`: mai `flutter test -d
# <telefono>`, che disinstalla l'app e cancella i suoi dati.
import subprocess,re,time,os,json,tempfile,xml.etree.ElementTree as ET
REPO=os.environ.get('KPM_REPO',os.getcwd())
ADB=os.path.expanduser('~/Library/Android/sdk/platform-tools/adb'); S=os.environ.get('KPM_SERIAL') or next((l.split()[0] for l in subprocess.run([ADB,'devices'],capture_output=True,text=True).stdout.splitlines()[1:] if l.strip().endswith('device')),''); PKG='io.github.al3x1n0.keepassmobile'
SHOTS=os.environ.get('KPM_SHOTS',os.path.join(tempfile.gettempdir(),'kpm_device_test')); os.makedirs(SHOTS,exist_ok=True)
DEV_DB='/sdcard/Download/KeePassMobile_adbtest.kdbx'
def sh(*a,t=60): return subprocess.run([ADB,'-s',S,'shell',*a],capture_output=True,text=True,timeout=t).stdout
def dump():
    for _ in range(4):
        sh('uiautomator','dump','/sdcard/kpm_ui.xml'); x=sh('cat','/sdcard/kpm_ui.xml'); i=x.find('<?xml')
        if i>=0:
            try: return list(ET.fromstring(x[i:]).iter('node'))
            except ET.ParseError: pass
        time.sleep(0.5)
    return []
def vals(n): return [n.get('text') or '', n.get('content-desc') or '']
def find(pat,nodes=None,mode='sub'):
    nodes=dump() if nodes is None else nodes; out=[]
    for n in nodes:
        for v in vals(n):
            if not v: continue
            first=v.split('\n')[0]
            if (mode=='sub' and pat.lower() in v.lower()) or (mode=='first' and first==pat) or (mode=='exact' and v==pat): out.append(n); break
    return out
def center(n): b=[int(v) for v in re.findall(r'\d+',n.get('bounds'))]; return (b[0]+b[2])//2,(b[1]+b[3])//2
def tap_node(n): x,y=center(n); sh('input','tap',str(x),str(y))
def wait_for(pat,timeout=20,mode='sub'):
    end=time.time()+timeout
    while time.time()<end:
        f=find(pat,mode=mode)
        if f: return f
        time.sleep(0.4)
    return []
def tap(pat,timeout=10,mode='sub',index=0,pause=0.8):
    f=wait_for(pat,timeout,mode)
    if not f: raise RuntimeError('non trovato: '+pat+' | schermo: '+str(screen_texts()[:25]))
    tap_node(f[index]); time.sleep(pause); return f[index]
def screen_texts(nodes=None):
    nodes=dump() if nodes is None else nodes
    return [ (n.get('text') or n.get('content-desc')).replace('\n',' / ') for n in nodes if (n.get('text') or n.get('content-desc'))]
def edit_texts(): return [n for n in dump() if n.get('class')=='android.widget.EditText']
def shot(name):
    p=f'{SHOTS}/{name}.png'; open(p,'wb').write(subprocess.run([ADB,'-s',S,'exec-out','screencap','-p'],capture_output=True).stdout); return p
def type_text(s): sh('input','text',s.replace(' ','%s'))
def key(*k): sh('input','keyevent',*map(str,k))
def clear_field(n=60): key('KEYCODE_MOVE_END'); sh('input','keyevent',*(['KEYCODE_DEL']*n))
L=json.load(open(os.path.join(REPO,'lib','l10n','app_'+('it' if sh('getprop','persist.sys.locale').startswith('it') else 'en')+'.arb')))
DEMO_DB=os.path.join(REPO,'tool','device_test','KeePassMobile_demo.kdbx')
def push_demo():
    # Copia il database demo come DEV_DB e lo rende visibile al selettore.
    subprocess.run([ADB,'-s',S,'push',DEMO_DB,DEV_DB],capture_output=True)
    sh('content','call','--method','scan_volume','--uri','content://media','--arg','external_primary')
def cleanup_device():
    # Toglie il database di prova e il dump della UI dal telefono.
    sh('rm','-f',DEV_DB); sh('rm','-f','/sdcard/kpm_ui.xml')
    sh('content','call','--method','scan_volume','--uri','content://media','--arg','external_primary')
    sh('svc','power','stayon','false')
def verify(extra=''):
    # Scarica DEV_DB e ne stampa la struttura (valori protetti mascherati).
    pulled=os.path.join(SHOTS,'kpm_pulled.kdbx')
    subprocess.run([ADB,'-s',S,'pull',DEV_DB,pulled],capture_output=True)
    r=subprocess.run(['fvm','dart','run','bin/verify.dart',pulled],capture_output=True,text=True,cwd=os.path.join(REPO,'tool','device_test','verify'),stdin=subprocess.DEVNULL,timeout=300)
    os.remove(pulled) if os.path.exists(pulled) else None
    out=r.stdout.strip().splitlines()
    return json.loads(out[-1]) if r.returncode==0 and out else {'error':(r.stdout+r.stderr)[-800:]}
