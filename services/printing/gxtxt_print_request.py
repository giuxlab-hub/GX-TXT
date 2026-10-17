#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Printing OS adapter. CORE owns request lifetime; CUPS owns accepted jobs."""
from pathlib import Path
import hashlib, json, os, re, shutil, signal, sys, tkinter
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'core/python'))
from gxtxt_job_supervisor import auxiliary_request_run, AuxiliaryRequestError, request_process_group, tcl_result

request_process_group()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
interpreter = tkinter.Tcl()
def dictionary(value):
    words = interpreter.splitlist(value)
    if len(words) % 2: raise ValueError('Invalid inert printing dictionary')
    return dict(zip(words[::2], words[1::2]))

class PrintError(RuntimeError):
    def __init__(self, category, message): super().__init__(message); self.category = category

def queue_name(value):
    if not value or len(value)>200 or not value.isprintable() or any(character.isspace() or character in '/#' for character in value):
        raise ValueError('Choose an actual CUPS destination name')
    return value

def command(name, args, timeout, *, optional=False):
    tool = shutil.which(name)
    if not tool: raise PrintError('unavailable', f'{name} is unavailable on this host')
    result = auxiliary_request_run([tool, *args], timeout_seconds=timeout,
        max_bytes=1048576, environment={**os.environ, 'LC_ALL':'C', 'LANG':'C'})
    if result['returncode'] and not optional:
        text = result['output'].strip()
        category = 'authorization' if re.search(r'not authorized|forbidden|permission denied|authentication', text, re.I) else ('offline' if re.search(r'not running|failed to connect|unable to connect|connection refused|host is down|service-unavailable',text,re.I) else 'unavailable')
        raise PrintError(category, f'{name}: {text[:4000] or "CUPS command failed"}')
    return result

def discover(timeout):
    result = command('lpstat', ['-e'], timeout)
    printers = sorted({queue_name(line.strip()) for line in result['output'].splitlines() if line.strip()})
    default_result = command('lpstat', ['-d'], timeout, optional=True)
    match = re.search(r':\s*(\S+)\s*$', default_result['output'])
    default = match.group(1) if match and match.group(1) in printers else ''
    return dict(status='available' if printers else 'no_printers', printers=printers,
        default=default, diagnostics=result['output']+default_result['output'])

def capabilities(printer, timeout):
    printer = queue_name(printer)
    status = command('lpstat', ['-p', printer, '-l'], timeout)
    result = command('lpoptions', ['-p', printer, '-l'], timeout)
    options = {}
    for line in result['output'].splitlines():
        match = re.fullmatch(r'([^/\s]+)/([^:]+):\s*(.*)', line)
        if not match: continue
        key, label, raw = match.groups(); choices=[]; default=''
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', key): continue
        for word in raw.split():
            if word.startswith('*'): default=word[1:]
            choices.append(word.lstrip('*'))
        options[key] = dict(label=label, choices=choices, default=default)
    fingerprint=hashlib.sha256(json.dumps(options,sort_keys=True).encode()).hexdigest()
    duplex=['auto']
    for key in ('Duplex','sides'):
        for choice in options.get(key,{}).get('choices',[]):
            value={'none':'simplex','simplex':'simplex','one-sided':'simplex',
                   'duplexnotumble':'long','two-sided-long-edge':'long',
                   'duplextumble':'short','two-sided-short-edge':'short'}.get(choice.lower())
            if value and value not in duplex: duplex.append(value)
    groups={}
    for group, keys in dict(media=('PageSize','media'), color=('ColorModel','print-color-mode'),
                            resolution=('Resolution','printer-resolution'), tray=('InputSlot','media-source')).items():
        groups[group]=next((dict(key=key,**options[key]) for key in keys if key in options),{})
    return dict(status='verified', printer=printer, options=options, groups=groups,
                duplex=duplex, fingerprint=fingerprint, diagnostics=status['output']+'\n'+result['output'])

def submit(data, timeout):
    printer=queue_name(data['printer']); caps=capabilities(printer,timeout)
    if caps['fingerprint'] != data['capability_sha256']:
        raise PrintError('stale_capabilities','Printer capabilities changed; refresh and review the selected options')
    path=Path(data['pdf'])
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise ValueError('Select a regular, absolute validated PDF path')
    with path.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
    if digest != data['pdf_sha256']: raise PrintError('stale_document','PDF changed before CUPS submission')
    if data.get('source_manifest'):
        from gxtxt_print_document_request import verify_sources
        try:verify_sources(data['source_manifest'])
        except Exception as exc:raise PrintError('stale_document',str(exc)) from exc
    copies=int(data['copies'])
    if not 1 <= copies <= 99: raise ValueError('Copies must be from 1 to 99')
    duplex=data.get('duplex','auto')
    if duplex not in caps['duplex']: raise ValueError('Selected duplex mode is not verified for this printer')
    args=['-d',printer,'-n',str(copies)]
    if duplex != 'auto': args += ['-o','sides='+{'simplex':'one-sided','long':'two-sided-long-edge','short':'two-sided-short-edge'}[duplex]]
    options=dictionary(data.get('options',''))
    for key, value in options.items():
        if key not in caps['options'] or value not in caps['options'][key]['choices']:
            raise ValueError(f'Option {key}={value} is not supported by this verified printer')
        args += ['-o',f'{key}={value}']
    pages=data.get('pages','').strip()
    if pages:
        if not re.fullmatch(r'[1-9][0-9]*(?:-[1-9][0-9]*)?(?:,[1-9][0-9]*(?:-[1-9][0-9]*)?)*', pages): raise ValueError('Use a positive CUPS page range such as 1-3,5')
        args += ['-P', pages]
    result=command('lp',[*args,'--',str(path)],timeout)
    match=re.search(r'request id is (\S+)',result['output'])
    return dict(status='accepted' if match else 'submitted_unidentified', printer=printer,
                job_id=match.group(1) if match else '', diagnostics=result['output'],
                physical_completion='unknown', pdf_sha256=digest)

def run(data):
    operation=data['operation']; timeout=int(data.get('timeout_ms','3000'))/1000
    if not .25 <= timeout <= 30: raise ValueError('CUPS operation timeout must be 250–30000 ms')
    if operation=='discover': return discover(timeout)
    if operation=='capabilities': return capabilities(data['printer'],timeout)
    if operation=='submit': return submit(data,timeout)
    if operation in ('job_status','cancel_job'):
        job=data['job_id']
        parts=job.rsplit('-',1)
        if len(parts)!=2 or not parts[1].isdigit(): raise ValueError('Invalid CUPS job identity')
        queue_name(parts[0])
        if operation=='cancel_job':
            result=command('cancel',[job],timeout)
            return dict(status='cancel_requested',job_id=job,diagnostics=result['output'])
        printer=queue_name(data['printer'])
        lines=[]; state='not_listed'
        for which in ('not-completed','completed'):
            result=command('lpstat',['-W',which,'-o',printer],timeout)
            matching=[line for line in result['output'].splitlines() if line.split() and line.split()[0]==job]
            if matching: lines.extend(matching);state='queued' if which=='not-completed' else 'completed_reported_by_cups'
        return dict(status=state,job_id=job,physical_completion='unknown',diagnostics='\n'.join(lines))
    raise ValueError('Unknown printing adapter operation')

if __name__=='__main__':
    try:
        raw=sys.stdin.read(2097153)
        if len(raw.encode())>2097152: raise ValueError('Printing request exceeds 2 MiB')
        print(tcl_result(dict(ok=True,result=run(dictionary(raw)))),flush=True)
    except (AuxiliaryRequestError, PrintError) as error:
        print(tcl_result(dict(ok=False,error=str(error),error_type=error.category)),flush=True)
    except Exception as error:
        print(tcl_result(dict(ok=False,error=str(error),error_type='invalid_request')),flush=True)
