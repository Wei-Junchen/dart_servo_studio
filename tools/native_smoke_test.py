#!/usr/bin/env python3
"""Linux Release UI smoke test on a separate Xvfb display with a FAKE Commander.

Never opens USB/J-Link. Uses only stdlib, Xvfb, ImageMagick, libX11 and libXtst.
Run after building: python3 tools/native_smoke_test.py
"""
from pathlib import Path
import ctypes as C
import json
import os
import subprocess
import sys
import tempfile
import time
import socket

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'build/linux/x64/release/bundle/dart_servo_studio'
MOCK = r'''#!/usr/bin/env python3
import socket,threading,sys,json,os
from pathlib import Path
port=int(sys.argv[sys.argv.index('-RTTTelnetPort')+1])
server=socket.socket();server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
server.bind(('127.0.0.1',port));server.listen(1)
root=Path(os.environ['SMOKE_ROOT']);manual=False;offsets=[-28,-5,-18,-28];angles=[0,0,0,0];mapping=[3,1,2,4]
saved_offsets=None;saved_mapping=None
print('FAKE Commander: no USB access. Cortex-M4 identified.',flush=True)
def serve():
 global manual,offsets,angles,mapping,saved_offsets,saved_mapping
 client,_=server.accept();data=b''
 with client:
  while True:
   chunk=client.recv(4096)
   if not chunk:break
   data+=chunk
   if data.startswith(b'$$'):
    end=data.find(b'$$',2)
    if end<0:continue
    data=data[end+2:]
   while b'\n' in data:
    line,data=data.split(b'\n',1);rid,cmd=line.decode().split(' ',1)
    with (root/'commands.jsonl').open('a') as out:out.write(json.dumps(cmd)+'\n')
    if cmd=='ping':msg='OK PONG protocol=v4'
    elif cmd=='status':msg=f'OK STATUS state=0 idle=1 profile=9 flash_busy=0 save_pending=0 manual={int(manual)} lease_ms=1500'
    elif cmd=='servo get':msg='OK SERVO offset_deg='+','.join(map(str,offsets))
    elif cmd=='servo angles get':msg='OK SERVO_ANGLES angle_deg='+','.join(map(str,angles))+' pwm_index='+','.join(map(str,mapping))
    elif cmd=='servo saved':msg='ERR NO_SAVED_SERVO' if saved_offsets is None else 'OK SERVO_SAVED offset_deg='+','.join(map(str,saved_offsets))
    elif cmd=='servo map saved':msg='ERR NO_SAVED_MAPPING' if saved_mapping is None else 'OK SERVO_MAP pwm_index='+','.join(map(str,saved_mapping))
    elif cmd=='servo manual start':manual=True;angles=[0]*4;msg='OK MANUAL active=1 lease_ms=1500'
    elif cmd=='servo manual keepalive':msg='OK MANUAL active=1 lease_ms=1500'
    elif cmd=='servo manual stop':manual=False;angles=[0]*4;msg='OK MANUAL active=0 lease_ms=1500'
    elif cmd.startswith('servo angles set '):angles=list(map(float,cmd.split()[3:]));msg='OK SERVO_ANGLES angle_deg='+','.join(map(str,angles))
    elif cmd.startswith('servo map set '):mapping=list(map(int,cmd.split()[3:]));msg='OK SERVO_MAP pwm_index='+','.join(map(str,mapping))
    elif cmd.startswith('servo setall '):offsets=list(map(float,cmd.split()[2:]));msg='OK SERVO offset_deg='+','.join(map(str,offsets))
    elif cmd=='servo save':saved_offsets=offsets[:];saved_mapping=mapping[:];msg='OK FLASH_PENDING'
    else:msg='ERR UNKNOWN_COMMAND'
    client.sendall(f'[DART] {rid[1:]} {msg}\n'.encode())
    if cmd=='servo save':client.sendall(f'[DART] {rid[1:]} DONE FLASH status=OK\n'.encode())
threading.Thread(target=serve,daemon=True).start()
for line in sys.stdin:
 if line.strip()=='exit':
  (root/'commander-exited').touch();break
server.close()
'''

if '--inside' not in sys.argv:
    sys.exit(subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1480x1000x24',
                             sys.executable, __file__, '--inside'], cwd=ROOT).returncode)
assert BINARY.exists(), 'Build Linux Release first'
xlib = C.CDLL('libX11.so.6')
xtst = C.CDLL('libXtst.so.6')
xlib.XOpenDisplay.argtypes=[C.c_char_p];xlib.XOpenDisplay.restype=C.c_void_p
xlib.XDefaultRootWindow.argtypes=[C.c_void_p];xlib.XDefaultRootWindow.restype=C.c_ulong
xlib.XFlush.argtypes=[C.c_void_p]
xlib.XInternAtom.argtypes=[C.c_void_p,C.c_char_p,C.c_int];xlib.XInternAtom.restype=C.c_ulong
xlib.XQueryTree.argtypes=[C.c_void_p,C.c_ulong,C.POINTER(C.c_ulong),C.POINTER(C.c_ulong),C.POINTER(C.POINTER(C.c_ulong)),C.POINTER(C.c_uint)]
xlib.XFetchName.argtypes=[C.c_void_p,C.c_ulong,C.POINTER(C.c_char_p)]
xlib.XFree.argtypes=[C.c_void_p]
xlib.XSendEvent.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_long,C.c_void_p]
xtst.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong]
xtst.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
xlib.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];xlib.XKeysymToKeycode.restype=C.c_uint
xtst.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
display=xlib.XOpenDisplay(None)
assert display

def click(x,y):
    xtst.XTestFakeMotionEvent(display,-1,x,y,0);xlib.XFlush(display);time.sleep(.12)
    xtst.XTestFakeButtonEvent(display,1,1,0);xlib.XFlush(display);time.sleep(.12)
    xtst.XTestFakeButtonEvent(display,1,0,0);xlib.XFlush(display)

def key(keysym):
    code=xlib.XKeysymToKeycode(display,keysym)
    assert code, hex(keysym)
    xtst.XTestFakeKeyEvent(display,code,1,0);xlib.XFlush(display);time.sleep(.08)
    xtst.XTestFakeKeyEvent(display,code,0,0);xlib.XFlush(display);time.sleep(.12)

def hold_key(keysym,seconds):
    code=xlib.XKeysymToKeycode(display,keysym)
    assert code,hex(keysym)
    xtst.XTestFakeKeyEvent(display,code,1,0);xlib.XFlush(display);time.sleep(seconds)
    xtst.XTestFakeKeyEvent(display,code,0,0);xlib.XFlush(display);time.sleep(.12)

def close_window():
    root=xlib.XDefaultRootWindow(display);rr=C.c_ulong();parent=C.c_ulong();children=C.POINTER(C.c_ulong)();count=C.c_uint()
    xlib.XQueryTree(display,root,C.byref(rr),C.byref(parent),C.byref(children),C.byref(count))
    target=None
    for i in range(count.value):
        name=C.c_char_p();xlib.XFetchName(display,children[i],C.byref(name))
        if name.value and b'Dart Servo Studio' in name.value:target=children[i]
        if name:xlib.XFree(name)
    xlib.XFree(children);assert target is not None,'window not found'
    class Message(C.Structure):
        _fields_=[('type',C.c_int),('serial',C.c_ulong),('send_event',C.c_int),('display',C.c_void_p),('window',C.c_ulong),('message_type',C.c_ulong),('format',C.c_int),('data',C.c_long*5)]
    class Event(C.Union):_fields_=[('message',Message),('padding',C.c_long*24)]
    event=Event();event.message.type=33;event.message.send_event=1;event.message.display=display;event.message.window=target
    event.message.message_type=xlib.XInternAtom(display,b'WM_PROTOCOLS',0);event.message.format=32
    event.message.data[0]=xlib.XInternAtom(display,b'WM_DELETE_WINDOW',0)
    xlib.XSendEvent(display,target,0,0,C.byref(event));xlib.XFlush(display)

with tempfile.TemporaryDirectory(prefix='native-servo-',dir=ROOT/'build') as raw:
    directory=Path(raw);mock=directory/'fake-commander';mock.write_text(MOCK);mock.chmod(0o755)
    reserve=socket.socket();reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1];reserve.close()
    config=directory/'config/dart_servo_studio';config.mkdir(parents=True)
    (config/'settings.json').write_text(json.dumps({'connection':{'commander':str(mock),'port':port,'elf':'','rttAddress':'0x20004404','launchCommander':True},'angleDirection':1}))
    env=dict(os.environ,XDG_CONFIG_HOME=str(directory/'config'),SMOKE_ROOT=raw,LIBGL_ALWAYS_SOFTWARE='1',GDK_BACKEND='x11')
    with (directory/'app.log').open('w') as output:
        app=subprocess.Popen([str(BINARY)],cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT)
        def commands():
            log=directory/'commands.jsonl'
            return [json.loads(row) for row in log.read_text().splitlines()] if log.exists() else []
        def until(predicate,timeout=8):
            deadline=time.monotonic()+timeout
            while time.monotonic()<deadline:
                if predicate():return
                assert app.poll() is None, (directory/'app.log').read_text()
                time.sleep(.1)
            raise AssertionError(f'timed out; commands={commands()}; log={(directory/"app.log").read_text()}')
        try:
            time.sleep(3)
            click(125,205) # One-click J-Link connection. Default window is 1480x1000.
            until(lambda:'servo map saved' in commands())
            assert all(c in ['ping','status','servo get','servo saved','servo angles get','servo map saved'] for c in commands())
            subprocess.run(['import','-window','root',str(ROOT/'build/native-connected.png')],check=True)
            time.sleep(.5)
            click(1260,184) # Position 1 OFFSET slider, no unlock/confirmation step.
            until(lambda:any(c.startswith('servo setall ') for c in commands()))
            until(lambda:'servo manual start' in commands())
            assert not any(c.startswith('servo angles set ') for c in commands()), 'Offset slider changed servo_angle'
            offsets=[c for c in commands() if c.startswith('servo setall ')][-1].split()[2:]
            assert float(offsets[0]) != -28 and list(map(float,offsets[1:])) == [-5,-18,-28]
            subprocess.run(['import','-window','root',str(ROOT/'build/native-offset.png')],check=True)
            click(1434,187) # Position 1 +0.1 offset button.
            until(lambda:len([c for c in commands() if c.startswith('servo setall ')])>=2)
            stepped=float([c for c in commands() if c.startswith('servo setall ')][-1].split()[2])
            assert abs(stepped - float(offsets[0]) - 0.1)<1e-6, (stepped,offsets)
            click(900,670) # Fixed-positive GUI common test-angle slider.
            until(lambda:any(c.startswith('servo angles set ') for c in commands()))
            angle_cmd=[c for c in commands() if c.startswith('servo angles set ')][-1]
            angles=list(map(float,angle_cmd.split()[3:]))
            assert len(angles)==4 and len(set(angles))==1 and angles[0] > 0, angle_cmd # Positive GUI angle is positive RTT angle.
            assert len([c for c in commands() if c.startswith('servo setall ')])==2, 'Common angle changed offsets'
            assert 'servo save' not in commands(), 'RAM editing wrote Flash'
            until(lambda:'servo manual keepalive' in commands())
            time.sleep(.35) # Let discrete-slider thumb animation settle before capture.
            subprocess.run(['import','-window','root',str(ROOT/'build/native-unified.png')],check=True)
            assert 'servo manual keepalive' in commands()
            key(0xff54) # Down selects position 2 from position 1.
            key(0x3d) # '=' nudges selected offset +0.1.
            until(lambda:len([c for c in commands() if c.startswith('servo setall ')])>=3)
            keyboard_offsets=list(map(float,[c for c in commands() if c.startswith('servo setall ')][-1].split()[2:]))
            assert abs(keyboard_offsets[1]-(-5.0)-0.1)<1e-6 and keyboard_offsets[0]==stepped, keyboard_offsets
            key(0x2d) # '-' restores the selected offset.
            until(lambda:len([c for c in commands() if c.startswith('servo setall ')])>=4)
            assert float([c for c in commands() if c.startswith('servo setall ')][-1].split()[3])==-5.0
            hold_key(0xff53,.85) # Right held: continuous position-2 offset adjustment.
            until(lambda:float([c for c in commands() if c.startswith('servo setall ')][-1].split()[3])>-4.5)
            count_after_release=len([c for c in commands() if c.startswith('servo setall ')])
            time.sleep(.25)
            assert len([c for c in commands() if c.startswith('servo setall ')])==count_after_release, 'Offset continued after key release'
            key(0xff51) # Left decrements the same position once.
            until(lambda:len([c for c in commands() if c.startswith('servo setall ')])>count_after_release)
            click(1368,926) # No saved Flash record: report, leave RAM alone.
            until(lambda:commands().count('servo saved')>=2)
            assert float([c for c in commands() if c.startswith('servo setall ')][-1].split()[2])==stepped
            click(1210,926) # Clear all offsets in RAM only.
            until(lambda:any(c.startswith('servo setall ') and all(float(v)==0 for v in c.split()[2:]) for c in commands()))
            assert 'servo save' not in commands()
            assert 'angleDirection' not in json.loads((config/'settings.json').read_text()), 'Legacy direction preference survived'
            close_window();app.wait(timeout=10)
            assert 'servo manual stop' in commands(), 'Close did not neutralize before shutdown'
            assert (directory/'commander-exited').exists(), 'Owned Commander was not released'
            assert app.returncode==0
            print('Native Linux GUI: one-click read → offset slider/+0.1 and keyboard ↑/↓/←/→/-/= with hold-to-repeat → equal positive RTT angles → Flash read/clear RAM → heartbeat/close cleanup: OK (FAKE target, no USB)')
        finally:
            if app.poll() is None:app.terminate();app.wait(timeout=10)
