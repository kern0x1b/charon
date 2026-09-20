import json,os,struct,subprocess,sys

tool, metallib, out = sys.argv[1:4]
data = open(metallib, 'rb').read()
os.makedirs(out, exist_ok=True)
functions = []
offset = 0
index = 0
while True:
    offset = data.find(b'\xde\xc0\x17\x0b', offset)
    if offset < 0:
        break
    _, _, start, size, _ = struct.unpack_from('<5I', data, offset)
    module = os.path.join(out, 'module%d.bc' % index)
    open(module, 'wb').write(data[offset + start:offset + start + size])
    prefix = os.path.join(out, 'module%d' % index)
    result = subprocess.run([tool, module, prefix], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    os.remove(module)
    if result.returncode == 0:
        reflection = json.load(open(prefix + '.json'))
        source = os.path.basename(prefix) + ('.vert' if reflection['stage'] == 'vertex' else '.frag')
        functions.append({'name': reflection['entry'], 'stage': reflection['stage'], 'source': source, 'reflection': os.path.basename(prefix) + '.json'})
    index += 1
    offset += 4
json.dump({'functions': functions}, open(os.path.join(out, 'library.json'), 'w'), indent=1)
