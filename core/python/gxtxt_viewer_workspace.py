# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit inert additive-upgrade review in the existing Development owner.

This checks supplied saved declarations only. Session/Workspace authority,
History transformation, canonical duplication and apply guards belong to the
trusted Tcl host. No author-supplied state is applied by this helper.
"""
import copy
from pathlib import Path
import re
import tempfile
import tkinter


def review(project, request):
    from gxtxt_viewer_development import (DevelopmentError, core, dictionary,
        validate, workspace_callback_contract, workspace_callback_semantics)
    def deny(message):raise DevelopmentError(message,'WORKSPACE_UPGRADE_DENIED')
    if not isinstance(request,dict) or set(request)!={'saved_design','saved_snapshot','callback_contract'}:
        deny('Review requires exactly the saved inert design, snapshot and callback contract')
    if not all(isinstance(value,str) and '\0' not in value for value in request.values()):
        deny('Saved review fields must be inert bounded text')
    if len(request['saved_design'].encode())>4194304:deny('Saved design exceeds4MiB')
    snapshot=dictionary(request['saved_snapshot']);contract=request['callback_contract']
    if set(snapshot)!={'source_sha256','design_sha256','project_sha256'} or not all(re.fullmatch(r'[0-9a-f]{64}',x) for x in snapshot.values()) or not re.fullmatch(r'[0-9a-f]{64}',contract):
        deny('Saved source identity or callback contract is missing or malformed')
    meta,report,new,requested=validate(project)
    if report['status']!='PASS':deny('Current project source is not admitted')
    if report['source_sha256']!=snapshot['source_sha256']:deny('C++ source changed; automatic state migration is unavailable')
    with tempfile.NamedTemporaryFile(dir=project/'derived/tmp',suffix='.gxtxt-viewer',delete=False) as f:
        f.write(request['saved_design'].encode());path=Path(f.name)
    try:old=dictionary(core(project,'validate_design',path))
    finally:path.unlink()
    if old['module_id']!=new['module_id'] or old['provider_id']!=new['provider_id']:
        deny('Saved Workspace belongs to another module or provider')
    # The prior digest proves the complete old metadata/profile/grants using
    # NEW admitted metadata and the exact SAVED declaration. No old project
    # file or author-supplied grant manifest is trusted or read here.
    if workspace_callback_contract(meta,old,report['source_sha256'])!=contract:
        deny('Saved contract cannot prove unchanged profile, grants and original callback semantics')
    before=workspace_callback_semantics(old);after=workspace_callback_semantics(new)
    old_components=before.pop('components');new_components=after.pop('components')
    old_handlers=dictionary(before.pop('handlers'));new_handlers=dictionary(after.pop('handlers'))
    if before!=after:deny('Existing root, requirement or initial-action contracts changed')
    if len(new_components)<len(old_components):deny('Existing components were removed')
    t=tkinter.Tcl()
    old_by_id={c['id']:c for c in old_components};new_by_id={c['id']:c for c in new_components}
    def trusted_bindings(components):
        result={}
        for c in components:
            p=c['properties']
            for action,target in dictionary(p.get('visibility_commands','')).items():result[action]=('visibility',target)
            if c['type']=='action' and 'component_visibility' in p:result[p['action']]=('visibility',p['component_visibility'])
            if 'scientific_netlist_action' in p:result[p['scientific_netlist_action']]=('netlist',c['id'])
            for action,operation in dictionary(p.get('plot_series_commands','')).items():result[action]=('series',c['id'],operation)
        return result
    old_trusted=trusted_bindings(old_components);new_trusted=trusted_bindings(new_components)
    for action,binding in new_trusted.items():
        if action in old_handlers and old_trusted.get(action)!=binding:deny('New presentation binding would intercept an original callback: '+action)
    reserved={'fit','zoom_in','zoom_out'}|set(new_trusted)
    for name,value in old_handlers.items():
        if new_handlers.get(name)!=value:deny('Existing handler contract changed: '+name)
    for name,value in new_handlers.items():
        if name in old_handlers:continue
        h=dictionary(value)
        if name not in reserved or h.get('arguments')!='window action' or h.get('effect')!='presentation' or set(h)-{'arguments','effect','label','default'}:
            deny('New handler is not an inert trusted presentation contract: '+name)
    additions=[];modes=set();probe_refs=[]
    changes=[];new_visibility={};new_netlist_forms=[]
    for index,old_component in enumerate(old_components):
        current=copy.deepcopy(new_components[index]);prior=copy.deepcopy(old_component)
        if current['id']!=prior['id']:deny('Existing declaration ordinals changed')
        p=current['properties'];op=prior['properties']
        # Tooltip text is presentation only; defaults/event values remain strict.
        p.pop('tooltip',None);op.pop('tooltip',None)
        if current['parent']!=prior['parent']:
            parent=new_by_id.get(current['parent'])
            if current['parent'] in old_by_id or not parent or parent['type'] not in {'panel','section','tab','splitter'}:
                deny('Reparenting requires a newly appended inert layout container')
            changes.append('presentation_parent:'+current['id']);current['parent']=prior['parent']
        if current['type'] in {'label','status','log','panel','section','tab','tabs','splitter','action','menu'}:
            for key in {'label','text','title','wraplength'}:
                p.pop(key,None);op.pop(key,None)
        keys={'scientific_probe_diagram','scientific_probe_plot','scientific_probe_mode'}
        added=keys.intersection(p)-keys.intersection(op)
        if added:
            if added!=keys or current['type']!='section' or op.get('scientific_provider')!='core.ngspice.circuit':
                deny('Only a complete new probe trio on an existing Scientific section is admissible')
            refs={key:p.pop(key) for key in keys}
            diagram=old_by_id.get(refs['scientific_probe_diagram']);plot=old_by_id.get(refs['scientific_probe_plot'])
            if not diagram or diagram['type']!='native2d' or diagram['properties'].get('diagram_catalog')!='electrical.basic' or not plot or plot['type']!='plot' or not plot['properties'].get('plot_form'):
                deny('Probe references must use the original electrical diagram and canonical Plot')
            if refs['scientific_probe_mode'] in old_by_id:deny('Probe mode must be a new inert explicit choice')
            modes.add(refs['scientific_probe_mode']);probe_refs.append(refs)
            changes.append('scientific_probe:'+current['id'])
        netlist_keys={'scientific_netlist','scientific_netlist_diagram','scientific_netlist_action'}
        added=netlist_keys.intersection(p)-netlist_keys.intersection(op)
        if added:
            if added!=netlist_keys or current['type']!='section' or op.get('scientific_provider')!='core.ngspice.circuit':deny('Netlist requires a complete additive binding on the original Scientific form')
            refs={key:p.pop(key) for key in netlist_keys}
            if refs['scientific_netlist'] in old_by_id or refs['scientific_netlist_diagram'] not in old_by_id:deny('Netlist requires a new separate log and the original source diagram')
            new_netlist_forms.append(current['id'])
            changes.append('scientific_netlist:'+current['id'])
        series_keys={'plot_series','plot_series_label','plot_series_axis','plot_series_enabled','plot_panel','plot_panel_title','plot_series_target','plot_series_commands'}
        added=series_keys.intersection(p)-series_keys.intersection(op)
        if added:
            if added!=series_keys or current['type']!='section' or 'plot_dataset' not in op:deny('Series editor requires a complete additive profile on the original Plot form')
            refs={key:p.pop(key) for key in series_keys}
            if refs['plot_series_target'] not in old_by_id:deny('Series editing requires the original canonical Plot')
            for key in series_keys-{'plot_series_target','plot_series_commands'}:
                if refs[key] in old_by_id:deny('Series editing requires new distinct inert controls')
            if 'plot_series_status' in p:
                if p['plot_series_status'] in old_by_id:deny('Series summary requires a new separate read-only control')
                p.pop('plot_series_status')
            changes.append('plot_series:'+current['id'])
        if current['type']=='menu':
            old_actions=t.splitlist(op.get('actions',''));new_actions=t.splitlist(p.get('actions',''))
            if new_actions!=old_actions:
                if new_actions[:len(old_actions)]!=old_actions or any(x not in reserved|{'-'} for x in new_actions[len(old_actions):]):deny('Existing menu commands may only append trusted presentation actions')
                p['actions']=op.get('actions','');changes.append('presentation_menu:'+current['id'])
            if 'visibility_commands' in p and 'visibility_commands' not in op:
                bindings=dictionary(p.pop('visibility_commands'))
                if not bindings or any(x not in reserved for x in bindings):deny('Only declared checked presentation commands may be appended')
                for target in bindings.values():new_visibility[target]=1
                changes.append('visibility_menu:'+current['id'])
        if current!=prior:deny('Existing component semantic contract changed: '+prior['id'])
    defaults={};plain={'label','status','log','panel','section','tab','tabs','splitter','action','menu','toggle','checkbutton','choice','combobox','entry','field','dataset_selector'}
    common={'label','text','title','tooltip','width','height','wraplength','padding'}
    for component in new_components[len(old_components):]:
        ident=component['id'];kind=component['type'];p=component['properties']
        if ident in old_by_id:deny('Appended identity collides with an original component')
        if kind=='choice' and ident in modes:
            if set(p)-{'label','tooltip','choices','default','width'} or t.splitlist(p.get('choices',''))!=('voltage','current') or p.get('default')!='voltage':
                deny('New probe mode must be an inert voltage/current choice with voltage default')
            defaults[ident]='voltage'
        elif kind in plain:
            allowed=common|({'action','component_visibility'} if kind=='action' else {'actions','visibility_commands'} if kind=='menu' else {'default','component_visibility'} if kind in {'toggle','checkbutton'} else {'default','choices'} if kind in {'choice','combobox'} else {'default','datatype','min','max'} if kind in {'field','entry'} else {'orientation'} if kind=='splitter' else set())
            if set(p)-allowed:deny('Appended component has a non-inert property: '+ident)
            if kind=='action' and p.get('action') not in reserved:deny('Appended action is not trusted presentation')
            if kind=='menu' and (not t.splitlist(p.get('actions','')) or any(x not in reserved|{'-'} for x in t.splitlist(p['actions']))):
                deny('Appended menu contains an author callback')
            if kind in {'toggle','checkbutton','choice','combobox','entry','field'}:defaults[ident]=p.get('default','0' if kind in {'toggle','checkbutton'} else '')
            if 'component_visibility' in p:new_visibility[p['component_visibility']]=1
            for target in dictionary(p.get('visibility_commands','')).values():new_visibility[target]=1
        else:deny('Appended component type is outside reviewed inert upgrade: '+ident)
        additions.append(ident)
    if not modes.issubset(set(additions)):deny('Missing appended probe-mode control')
    for c in new_components:
        p=c['properties']
        if c['type'] in {'toggle','checkbutton'} and 'component_visibility' in p and p['component_visibility'] in new_visibility:new_visibility[p['component_visibility']]=str(int(t.getboolean(p['default'])))
    if not changes and not additions:deny('No supported explicit additive presentation upgrade was found')
    return dict(status='REVIEWED_INERT_ADDITIVE_UPGRADE',source_sha256=report['source_sha256'],
        prior_callback_contract=contract,new_callback_contract=report['workspace_callback_contract_sha256'],
        preserved_component_count=len(old_components),appended_components=additions,new_defaults=defaults,new_visibility_defaults=new_visibility,new_netlist_forms=new_netlist_forms,approved_presentation_changes=changes,
        approved_probe_references=probe_refs,source_snapshot={key:report[key] for key in ('source_sha256','design_sha256','project_sha256')},
        policy='Explicit canonical duplicate only; original Workspace/source/Jobs/Datasets unchanged. Host must recheck Session/source/Workspace stamps, transform every retained History state and copy resources through existing owners. This report is not an applied migration.')
