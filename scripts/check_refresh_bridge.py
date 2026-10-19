"""Native bridge checks against a private, synthetic Unix-socket fixture. No host plugin is installed."""
from pathlib import Path
import hashlib,json,socket,subprocess,tempfile,threading,time

root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='squat-link-fixture-',dir='/private/tmp') as temporary:
    folder=Path(temporary)
    source=(root/'plugin/SquatBridge.swift').read_text()
    old='''FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(preview ? "SquatPreviewV27/Link" : "Squat/Link",isDirectory: true)'''
    assert source.count(old)==1
    source=source.replace(old,'URL(fileURLWithPath: '+json.dumps(str(folder))+', isDirectory: true)')
    (folder/'FixtureBridge.swift').write_text(source)
    binary=folder/'fixture-bridge'
    subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(root/'.build/plugin-module-cache'),str(folder/'FixtureBridge.swift'),'-o',str(binary)],check=True)
    token='a'*64
    generation='11111111-1111-4111-8111-111111111111'
    (folder/'token').write_text(token)
    gate={'generation':generation,'expiresAt':time.monotonic()+3,'armedAt':time.monotonic()-1,'testUntil':time.monotonic()+30}
    body={'hook_event_name':'UserPromptSubmit','session_id':'synthetic-session','turn_id':'synthetic-turn','prompt':'PRIVATE_BODY_CANARY','transcript_path':'PRIVATE_PATH_CANARY'}
    results=[]
    def invoke(name,payload):
        started=time.perf_counter()
        p=subprocess.run([str(binary),'--preview'],input=json.dumps(payload).encode(),capture_output=True,timeout=1)
        duration=(time.perf_counter()-started)*1000
        assert p.returncode==0 and p.stdout==b'' and p.stderr==b'',(name,p.returncode,p.stdout,p.stderr)
        result={'case':name,'exit':p.returncode,'stdoutBytes':0,'stderrBytes':0,'elapsedMs':round(duration,2)}
        results.append(result)
    invoke('gate_absent',body)
    (folder/'gate.json').write_text(json.dumps(gate))
    invoke('receiver_absent',body)
    invoke('invalid_json_shape',None)
    invoke('missing_turn',{'hook_event_name':'UserPromptSubmit','session_id':'synthetic-session'})
    invoke('wrong_event',dict(body,hook_event_name='Stop'))
    received=[]
    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as server:
        server.bind(str(folder/'events.sock')); server.listen(1); server.settimeout(1)
        def listen():
            connection,_=server.accept()
            with connection:
                data=b''
                while not data.endswith(b'\n'):
                    part=connection.recv(2049)
                    if not part:break
                    data+=part
                received.append(data)
        listener=threading.Thread(target=listen);listener.start()
        invoke('valid_local_transfer',body)
        listener.join(timeout=2)
    assert len(received)==1 and len(received[0])<=2048
    value=json.loads(received[0])
    assert value['eventID']==hashlib.sha256(b'synthetic-session|synthetic-turn').hexdigest()
    assert value['sessionTag']==hashlib.sha256(b'synthetic-session').hexdigest()
    assert value['generation']==generation
    assert b'PRIVATE_BODY_CANARY' not in received[0] and b'PRIVATE_PATH_CANARY' not in received[0]
    for _ in range(20):invoke('warm_receiver_absent',body)
    warm=sorted(r['elapsedMs'] for r in results if r['case']=='warm_receiver_absent')
    report={'fixtureOnly':True,'hostInstalled':False,'aiRequests':0,'checks':results,'packetBytes':len(received[0]),'bodyAndPathAbsent':True,'warmMedianMs':warm[len(warm)//2],'warmP95Ms':warm[18],'measurement':'Native helper process only; not a measurement of chat delay or billed token delta.'}
    (root/'work/refresh-bridge-checks.json').write_text(json.dumps(report,indent=2))
    print(json.dumps({'cases':len(results),'bodyAndPathAbsent':True,'warmMedianMs':report['warmMedianMs'],'warmP95Ms':report['warmP95Ms'],'fixtureOnly':True}))
