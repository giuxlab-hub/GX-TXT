"""Bounded electrical diagram translation for the existing Scientific Execution owner.

Only raw solver observations are published. Derived scientific quantities and
analytical validation belong to the public GX-TXT Numeric APIs.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import csv
import hashlib
import re
import sys
import tkinter

from gxtxt_scientific_execution import tdict, tvalue

SCHEMA = 'gxtxt.native2d.diagram.v1'
PIN_ORDER = {'resistor':('p','n'), 'capacitor':('p','n'), 'inductor':('p','n'),
             'voltage':('p','n'), 'current':('p','n'), 'ground':('g',),
             'diode':('a','k'), 'npn':('c','b','e'),
             'nmos':('d','g','s','b'), 'pmos':('d','g','s','b'),
             'spst':('a','b'), 'spdt':('c','a','b')}
PREFIX = {'resistor':'R', 'capacitor':'C', 'inductor':'L', 'voltage':'V',
          'current':'I', 'ground':'G', 'diode':'D', 'npn':'Q',
          'nmos':'M', 'pmos':'M', 'spst':'S', 'spdt':'S'}
ATTRIBUTES = {
    'resistor':{'value':(1000,1e-15)}, 'capacitor':{'value':(1e-6,1e-18)},
    'inductor':{'value':(.001,1e-15)},
    'voltage':{'value':(1,None),'waveform':('dc',('dc','pulse','sine')),
        'ac':(1,0),'initial':(0,None),'delay':(0,0),'rise':(1e-9,1e-15),
        'width':(.01,1e-15),'period':(.02,1e-15),'frequency':(1000,1e-15)},
    'current':{'value':(.001,None),'ac':(0,0)}, 'ground':{},
    'diode':{'model':('generic',('generic','silicon'))},
    'npn':{'model':('generic',('generic','small_signal'))},
    'nmos':{'model':('educational_level1',('educational_level1',)),
            'length':(1e-5,1e-6),'width':(1e-4,1e-6)},
    'pmos':{'model':('educational_level1',('educational_level1',)),
            'length':(1e-5,1e-6),'width':(1e-4,1e-6)},
    'spst':{'position':('open',('open','closed')),'ron':(1,1e-6),'roff':(1e9,1)},
    'spdt':{'position':('a',('a','b')),'ron':(1,1e-6),'roff':(1e9,1)}}

# Original educational parameters, not a manufacturer or extracted process.
# ngspice44 manual 7.6.1/7.6.2.1/7.6.2.5 documents terminal order, SI geometry,
# enhancement threshold polarity and the long-channel LEVEL1 model limitations.
MOS_MODELS = {
    'nmos':('GXTXT_M_NMOS_EDU',
            '.model GXTXT_M_NMOS_EDU NMOS(LEVEL=1 VTO=1 KP=2e-5 GAMMA=0.4 PHI=0.6 LAMBDA=0.02 IS=1e-14 TNOM=27)'),
    'pmos':('GXTXT_M_PMOS_EDU',
            '.model GXTXT_M_PMOS_EDU PMOS(LEVEL=1 VTO=-1 KP=2e-5 GAMMA=0.4 PHI=0.6 LAMBDA=0.02 IS=1e-14 TNOM=27)')}

def number(value, minimum=None):
    value = float(value)
    if value != value or value in (float('inf'), float('-inf')):
        raise ValueError('Circuit values must be finite SI numbers')
    if minimum is not None and value < minimum:
        raise ValueError('Circuit value violates its declared minimum')
    return format(value, '.17g')

def compile_circuit(raw, override_component='', override_value=0, component_values=''):
    """Connectivity is discrete topology, never inferred from coordinates."""
    if len(raw)>1048576: raise ValueError('Circuit snapshot exceeds 1 MiB')
    payload = tdict(raw.decode('utf-8'))
    if set(payload) != {'schema','catalog','next_id','components','junctions','wires','labels'}:
        raise ValueError('Unsupported diagram payload fields')
    if payload['schema'] != SCHEMA or payload['catalog'] != 'electrical.basic':
        raise ValueError('Provider requires the public electrical.basic diagram contract')
    components = tdict(payload['components'])
    if len(component_values.encode('utf-8')) > 4096:
        raise ValueError('Component override map exceeds4KiB')
    overrides = tdict(component_values)
    if len(overrides)>8:
        raise ValueError('At most8 physical values may be overridden per solve')
    if override_component:
        if override_component in overrides:
            raise ValueError('Single and mapped physical overrides conflict')
        overrides[override_component] = override_value
    if set(overrides)-set(components):
        raise ValueError('Sweep parameter names an absent stable component')
    junctions = tdict(payload['junctions'])
    wires = tdict(payload['wires'])
    labels = tdict(payload['labels'])
    if not 1 <= len(components) <= 256 or len(junctions)>512 or len(wires)>1024 or len(labels)>256:
        raise ValueError('Circuit collection exceeds public bounds')
    parent = {}; terminals = {}; names = set(); prepared = []
    def endpoint(value):
        parts = tuple(tkinter.Tcl().splitlist(value))
        if parts not in parent: raise ValueError('Unknown explicit circuit terminal')
        return parts
    def find(item):
        while parent[item] != item:
            parent[item] = parent[parent[item]]; item = parent[item]
        return item
    def union(a,b):
        a,b = find(a),find(b)
        if a != b: parent[max(a,b)] = min(a,b)
    for ident, encoded in sorted(components.items()):
        item = tdict(encoded)
        if set(item) != {'kind','name','position','rotation','attributes'}:
            raise ValueError('Unsupported symbol fields')
        kind = item['kind']; name = item['name']
        if kind not in PIN_ORDER: raise ValueError('Unsupported circuit device')
        if not re.fullmatch(PREFIX[kind]+r'[A-Za-z0-9_]{1,31}', name, re.I):
            raise ValueError('Device name needs its SPICE prefix and 1..31 letters/digits/underscores: '+name)
        if name.lower() in names: raise ValueError('Case-insensitive duplicate SPICE device name')
        names.add(name.lower())
        attrs = tdict(item['attributes'])
        if set(attrs) != set(ATTRIBUTES[kind]): raise ValueError('Unexpected circuit device attributes')
        if ident in overrides:
            if kind not in {'resistor','capacitor','inductor','voltage','current'}:
                raise ValueError('This device has no admitted scalar sweep value')
            attrs['value'] = overrides[ident]
        values = {}
        for key, (default, constraint) in ATTRIBUTES[kind].items():
            if isinstance(constraint, tuple):
                if attrs[key] not in constraint: raise ValueError('Unsupported circuit attribute choice')
                values[key] = attrs[key]
            else: values[key] = number(attrs[key], constraint)
        if kind in MOS_MODELS and any(float(values[key])>0.001 for key in ('length','width')):
            raise ValueError('Educational MOS channel geometry requires 1e-6..0.001 metres')
        if kind in {'spst','spdt'}:
            if float(values['ron'])>1e6 or float(values['roff'])>1e12 or float(values['roff'])<=float(values['ron']):
                raise ValueError('Static contacts require Ron<=1e6 Ohm, Roff<=1e12 Ohm and Roff>Ron')
        for pin in PIN_ORDER[kind]:
            key = (ident,pin); parent[key] = key; terminals[key] = name
        prepared.append((ident,kind,name,values))
    for ident, encoded in junctions.items():
        key = (ident,); parent[key] = key
    for encoded in wires.values():
        wire = tdict(encoded)
        if set(wire) != {'start','end','route'}: raise ValueError('Unsupported wire fields')
        union(endpoint(wire['start']), endpoint(wire['end']))
    by_label = {}; terminal_labels = []
    for encoded in labels.values():
        label = tdict(encoded)
        if not {'endpoint','text'}.issubset(label) or set(label)-{'endpoint','text','offset'} or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,31}',label['text']):
            raise ValueError('Invalid circuit net label')
        if 'offset' in label:
            offset=tkinter.Tcl().splitlist(label['offset'])
            if len(offset)!=2 or any(not -1000000 <= float(number(value)) <= 1000000 for value in offset):
                raise ValueError('Invalid bounded label display offset')
        key = endpoint(label['endpoint']); text = label['text'].lower()
        if text in by_label: union(key,by_label[text])
        else: by_label[text] = key
        terminal_labels.append((key,text))
    grounds = [(ident,'g') for ident,kind,name,attrs in prepared if kind == 'ground']
    if not grounds: raise ValueError('Circuit requires an explicit ground reference')
    for key in grounds[1:]: union(grounds[0],key)
    ground = find(grounds[0]); roots = sorted({find(key) for key in parent})
    net_names = {ground:'0'}; root_labels = {}
    for key, text in terminal_labels:
        root = find(key)
        if root == ground and text not in {'gnd','ground'}:
            raise ValueError('Ground cannot carry a non-ground net label')
        root_labels.setdefault(root,[]).append(text)
    occupied = {'0'}
    for index,root in enumerate(roots):
        if root == ground: continue
        name = sorted(root_labels[root])[0] if root in root_labels else 'net_'+str(index+1)
        if name in occupied: raise ValueError('Ambiguous circuit node names')
        net_names[root] = name; occupied.add(name)
    counts = {}
    for key in terminals: counts[find(key)] = counts.get(find(key),0)+1
    for root,count in counts.items():
        if root != ground and count<2:
            raise ValueError('Open terminal: '+terminals[root] if root in terminals else 'Open circuit terminal')
    edges = {root:set() for root in roots}
    for ident,kind,name,attrs in prepared:
        nodes = [find((ident,p)) for p in PIN_ORDER[kind]]
        for a in nodes:
            for b in nodes: edges[a].add(b)
    reached = {ground}; pending = [ground]
    while pending:
        for root in edges[pending.pop()]-reached: reached.add(root); pending.append(root)
    if set(counts)-reached: raise ValueError('Circuit has a floating disconnected island')
    lines = ['GX-TXT canonical electrical diagram']; sources = []; probes = []
    component_netlist = {}; generated_names = set()
    for ident,kind,name,attrs in prepared:
        nodes = [net_names[find((ident,p))] for p in PIN_ORDER[kind]]
        component_netlist[ident] = [] if kind == 'ground' else [name]
        if kind == 'ground': continue
        lead = name+' '+' '.join(nodes)+' '
        if kind in {'resistor','capacitor','inductor'}: line = lead+attrs['value']
        elif kind == 'voltage':
            form = attrs['waveform']
            if form == 'dc': stimulus = 'DC '+attrs['value']
            elif form == 'pulse':
                if float(attrs['width']) >= float(attrs['period']): raise ValueError('Pulse width must be less than period')
                stimulus = 'PULSE('+ ' '.join(attrs[k] for k in ('initial','value','delay','rise','rise','width','period')) + ')'
            else: stimulus = 'SIN('+ ' '.join(attrs[k] for k in ('initial','value','frequency','delay')) + ')'
            line = lead+stimulus+' AC '+attrs['ac']; sources.append(name)
        elif kind == 'current': line = lead+'DC '+attrs['value']+' AC '+attrs['ac']; sources.append(name)
        elif kind == 'diode': line = lead+'GXTXT_D_'+attrs['model'].upper()
        elif kind == 'npn': line = lead+'GXTXT_Q_'+attrs['model'].upper()
        elif kind in MOS_MODELS:
            line = lead+MOS_MODELS[kind][0]+' L='+attrs['length']+' W='+attrs['width']+' TEMP=27'
        elif kind in {'spst','spdt'}:
            # State is an explicit immutable source parameter for this solve.
            # A finite resistor is a declared contact approximation, never an
            # ideal graph join, time-driven switch, relay or fuse trip model.
            branches = [('a',nodes[0],nodes[1],attrs['ron'] if attrs['position']=='closed' else attrs['roff'])] if kind=='spst' else [
                (pin,nodes[0],nodes[index],attrs['ron'] if attrs['position']==pin else attrs['roff'])
                for index,pin in enumerate(('a','b'),1)]
            component_netlist[ident] = []
            for pin,start,end,resistance in branches:
                generated = 'R_GXTXT_SW_'+name+'_'+pin
                if generated.lower() in names or generated.lower() in generated_names:
                    raise ValueError('Generated static-contact element conflicts with circuit name: '+generated)
                generated_names.add(generated.lower())
                component_netlist[ident].append(generated)
                lines.append(generated+' '+start+' '+end+' '+resistance)
            continue
        else: raise ValueError('Unsupported circuit device translation')
        lines.append(line)
    # Original, explicit generic example parameter cards, GPL-3.0-or-later.
    lines += ['.model GXTXT_D_GENERIC D(IS=1e-14 N=1)',
              '.model GXTXT_D_SILICON D(IS=1e-14 N=1.5 RS=1)',
              '.model GXTXT_Q_GENERIC NPN(IS=1e-14 BF=100 VAF=100)',
              '.model GXTXT_Q_SMALL_SIGNAL NPN(IS=1e-14 BF=200 VAF=100)']
    kinds = {kind for ident,kind,name,attrs in prepared}
    for kind in ('nmos','pmos'):
        if kind in kinds: lines.append(MOS_MODELS[kind][1])
    for node in sorted(set(net_names.values())-{'0'}):
        probes.append(dict(id='v_'+node,expression='v('+node+')',unit='V'))
    for ident,kind,name,attrs in prepared:
        if kind == 'voltage': probes.append(dict(id='i_'+name.lower(),expression='i('+name+')',unit='A'))
    if not probes: raise ValueError('Circuit has no observable quantity')
    result = dict(lines=lines,probes=probes,sources=sources,
                source_sha256=hashlib.sha256(raw).hexdigest(),
                component_values={key:number(value) for key,value in sorted(overrides.items())},
                net_mapping={tvalue(list(key)):net_names[find(key)] for key in sorted(parent)},
                model_origin='Original explicit generic educational parameter cards; GPL-3.0-or-later')
    if kinds.intersection({'nmos','pmos','spst','spdt'}):
        result['component_netlist'] = component_netlist
        if kinds.intersection(MOS_MODELS):
            result['model_origin'] += '; MOS: original educational long-channel LEVEL1, explicit body and SI L/W, TEMP/TNOM27C'
        if kinds.intersection({'spst','spdt'}):
            result['model_origin'] += '; contacts: user-selected static finite Ron/Roff, no dynamic switching or fuse physics'
    return result

def analysis_command(circuit, p):
    analysis = p['analysis']
    if analysis == 'op': command = 'op'
    elif analysis == 'tran':
        if float(p['step_seconds']) > float(p['stop_seconds']): raise ValueError('Transient step exceeds stop time')
        command = 'tran '+number(p['step_seconds'],1e-12)+' '+number(p['stop_seconds'],1e-12)
    elif analysis == 'ac':
        if float(p['start_hz']) >= float(p['stop_hz']): raise ValueError('AC frequency range must increase')
        command = 'ac '+p['ac_grid']+' '+str(p['points'])+' '+number(p['start_hz'],1e-12)+' '+number(p['stop_hz'],1e-12)
    elif analysis == 'dc':
        source = next((name for name in circuit['sources'] if name.lower()==p['source'].lower()),None)
        if source is None: raise ValueError('DC sweep needs an existing independent source name')
        if float(p['dc_step']) == 0 or ((float(p['dc_stop']) > float(p['dc_start'])) != (float(p['dc_step']) > 0)):
            raise ValueError('DC sweep step must progress toward stop')
        command = 'dc '+source+' '+number(p['dc_start'])+' '+number(p['dc_stop'])+' '+number(p['dc_step'])
    else: raise ValueError('Unsupported circuit analysis')
    return analysis, command

def observation_axis(analysis, parameters):
    """One declared independent coordinate for inspection and raw publication."""
    axis_id = dict(op='index', tran='time', ac='frequency', dc='source_value')[analysis]
    axis_unit = dict(op='', tran='s', ac='Hz', dc='A' if parameters['source'].lower().startswith('i') else 'V')[analysis]
    return dict(id=axis_id, dtype='float64', unit=axis_unit)

def inspect(raw, parameters):
    circuit = compile_circuit(raw, parameters.get('override_component',''), parameters.get('override_value',0), parameters.get('component_values',''))
    analysis, command = analysis_command(circuit,parameters)
    result = dict(analysis=analysis,analysis_command=command,source_sha256=circuit['source_sha256'],netlist='\n'.join(circuit['lines'])+'\n.end\n',
                independent_variable=observation_axis(analysis, parameters),
                probes=circuit['probes'],net_mapping=circuit['net_mapping'],component_values=circuit['component_values'],model_origin=circuit['model_origin'])
    if 'component_netlist' in circuit: result['component_netlist'] = circuit['component_netlist']
    return result

def run(context):
    if set(context.inputs) != {'circuit'}: raise ValueError('Provider requires exactly one canonical circuit snapshot')
    raw = context.inputs['circuit']; p = context.parameters
    circuit = compile_circuit(raw,p['override_component'],p['override_value'],p.get('component_values',''))
    analysis, command = analysis_command(circuit,p)
    complex_output = analysis == 'ac'
    control = ['.control','set wr_singlescale','set wr_vecnames','set numdgt=17',command,
        'wrdata observations.txt '+' '.join(probe['expression'] for probe in circuit['probes']),
        'quit','.endc','.end']
    deck = '\n'.join(circuit['lines']+control)+'\n'
    (context.scratch/'circuit.cir').write_text(deck,encoding='utf-8')
    version = context.run('spice',['--version'])
    context.run('spice',['-b','circuit.cir'])
    source = context.scratch/'observations.txt'
    if not source.is_file() or source.stat().st_size>16777216: raise ValueError('Solver produced no bounded observation table')
    columns = [observation_axis(analysis, p)]
    for probe in circuit['probes']:
        for suffix in ('_real','_imag') if complex_output else ('',):
            columns.append(dict(id=probe['id']+suffix,dtype='float64',unit=probe['unit']))
    count = 0
    with source.open() as inputs, (context.output/'waveform.csv').open('w',newline='') as output:
        next(inputs)
        writer = csv.writer(output); writer.writerow([c['id'] for c in columns])
        for line in inputs:
            values = line.split()
            if len(values) != len(columns): raise ValueError('Solver observation width differs from declared raw schema')
            values = [number(v) for v in values]
            if analysis == 'op': values[0] = str(count)
            writer.writerow(values); count += 1
            if count>200000: raise ValueError('Solver observation count exceeds bound')
    if not count: raise ValueError('Solver returned no observations')
    context.publish_output('waveform.csv','waveform','csv',columns)
    (context.output/'netlist.cir').write_text(deck,encoding='utf-8')
    context.publish_output('netlist.cir','netlist','text')
    summary = dict(validation='validated_structure',analysis=analysis,rows=count,
        circuit_sha256=circuit['source_sha256'],netlist_sha256=hashlib.sha256(deck.encode()).hexdigest(),
        solver='ngspice',solver_version=version['stdout'][:4096],model_origin=circuit['model_origin'],component_values=circuit['component_values'],
        numerical_postprocessing='none; raw solver observations only')
    if 'component_netlist' in circuit: summary['component_netlist'] = circuit['component_netlist']
    context.summary(summary)

if __name__ == '__main__':
    if sys.argv[1:] != ['--inspect']: raise SystemExit('Only bounded circuit inspection is public here')
    try:
        raw = sys.stdin.buffer.read(1114113)
        if len(raw)>1114112: raise ValueError('Circuit inspection request exceeds bound')
        request = tdict(raw.decode('utf-8'))
        if set(request) != {'payload','parameters'}: raise ValueError('Invalid circuit inspection fields')
        print(tvalue(dict(ok=True,result=inspect(request['payload'].encode('utf-8'),tdict(request['parameters'])))))
    except Exception as error:
        print(tvalue(dict(ok=False,error=str(error)))); raise SystemExit(1)
