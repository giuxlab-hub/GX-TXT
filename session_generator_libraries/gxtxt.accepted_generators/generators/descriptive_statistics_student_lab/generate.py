#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate a deterministic ready-to-run GX-TXT descriptive-statistics teaching Session."""
from __future__ import annotations
import argparse, csv, hashlib, math, shutil
from pathlib import Path

GENERATOR_VERSION = "1.0.0"
DATASET_ID = "student.descriptive.source"
DATASET_FILE = f"datasets/{DATASET_ID}.csv"
MODULE_ID = "analysis.statistics.descriptive"
ROWS = [
    (1,1.0,1000,0.10,5,-5,7,1,-1),(2,1.2,1200,0.11,5,-4,math.nan,3,0),
    (3,1.4,1400,0.12,5,-3,math.nan,math.nan,math.inf),(4,1.6,1600,0.13,5,-2,math.nan,math.nan,1),
    (5,1.8,1800,0.14,5,-1,math.nan,math.nan,-math.inf),(6,2.0,2000,0.15,5,0,math.nan,math.nan,2),
    (7,2.2,2200,0.16,5,1,math.nan,math.nan,3),(8,2.4,2400,0.17,5,2,math.nan,math.nan,4),
    (9,2.6,2600,0.18,5,3,math.nan,math.nan,5),(10,2.8,2800,0.19,5,4,math.nan,math.nan,6),
    (11,math.nan,math.nan,0.20,5,5,math.nan,math.nan,7),(12,3.2,3200,math.nan,5,6,math.nan,math.nan,8),
]
VARS = [
    ("sample","","independent"),("voltage_V","V","measured"),("voltage_mV","mV","measured"),
    ("current_A","A","measured"),("constant_V","V","measured"),("signed_V","V","measured"),
    ("single_value_V","V","measured"),("two_values_V","V","measured"),("nonfinite_V","V","measured"),
]

def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1<<20), b''): h.update(block)
    return h.hexdigest()

def write_ini(path: Path, sections):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8',newline='\n') as f:
        for j,(section,items) in enumerate(sections):
            if j: f.write('\n')
            f.write(f'[{section}]\n')
            for k,v in items: f.write(f'{k}={v}\n')

def fmt(v):
    if isinstance(v,float) and math.isnan(v): return 'NaN'
    if isinstance(v,float) and math.isinf(v): return 'Inf' if v > 0 else '-Inf'
    return format(v,'.15g') if isinstance(v,float) else str(v)

def stats(values):
    x=[float(v) for v in values if math.isfinite(float(v))]
    n=len(x); xs=sorted(x)
    mean=sum(x)/n
    def q(p):
        if n==1:return xs[0]
        pos=(n-1)*p; lo=int(math.floor(pos)); hi=int(math.ceil(pos))
        return xs[lo] if lo==hi else xs[lo]+(pos-lo)*(xs[hi]-xs[lo])
    var=sum((v-mean)**2 for v in x)/(n-1) if n>1 else math.nan
    return {'n':n,'mean':mean,'min':min(x),'max':max(x),'median':q(.5),'q1':q(.25),'q3':q(.75),'var_sample':var,'std_sample':math.sqrt(var) if n>1 else math.nan,'sem':math.sqrt(var/n) if n>1 else math.nan}

def ground_truth_text():
    lines=["GX-TXT Descriptive Statistics Student Lab - reference values", "", "Configured Selection: sample 3 through 12 inclusive.", "Configured variables: voltage_V, voltage_mV, current_A, constant_V.", "NaN / Inf policy: omit.", "Additional percentiles: 5, 10, 90, 95.", ""]
    selected=ROWS[2:12]
    for col,name in [(1,'voltage_V'),(2,'voltage_mV'),(3,'current_A'),(4,'constant_V')]:
        vals=[r[col] for r in selected]; s=stats(vals)
        lines.append(name)
        lines.append(f"  selected_count={len(vals)}")
        lines.append(f"  valid_count={s['n']}")
        lines.append(f"  excluded_count={len(vals)-s['n']}")
        for key in ['min','max','mean','median','q1','q3','var_sample','std_sample','sem']:
            lines.append(f"  {key}={s[key]:.17g}")
        lines.append("")
    lines += ["Expected automatic plot grouping:", "  Group 1: voltage_V + voltage_mV + constant_V (compatible voltage units).", "  Group 2: current_A (incompatible with voltage).", "  Expected plot variants: 4 (histogram + box/whisker for each group).", ""]
    return '\n'.join(lines)

def student_guide_text():
    return """GX-TXT DESCRIPTIVE STATISTICS - STUDENT LAB
=============================================

Purpose
-------
Learn how to run analysis.statistics.descriptive on a Canonical Dataset, read
its summary Dataset/report, and inspect persistent histogram and box/whisker
plot variants.

First run
---------
1. Open this generated Session in GX-TXT.
2. Open the analysis-module configuration for Descriptive Statistics.
3. Verify that the Dataset is student.descriptive.source.
4. The Variables table is preconfigured with voltage_V, voltage_mV, current_A,
   and constant_V.
5. Verify Selection sel_001: sample 3 through 12 inclusive.
6. Leave NaN / Inf policy = omit and Create automatic distribution plots = on.
7. Run the selected analysis module.
8. Open student.descriptive.summary and descriptive_statistics_report.txt.
9. Inspect the persistent plot.dataset variants. The expected first run creates
   four variants: histogram + box/whisker for the voltage-compatible group and
   histogram + box/whisker for current_A.
10. Compare the numerical results with metadata/ground_truth.txt.

What to notice
--------------
- voltage_V and voltage_mV are dimensionally compatible and may share one plot.
- current_A is incompatible with voltage and is automatically kept separate.
- constant_V has zero spread.
- sample 11 contains NaN in voltage_V and voltage_mV; omit excludes it and the
  report records the excluded count.
- the source Dataset is not modified by the analysis.

Exercises
---------
A. Add signed_V to Variables and rerun. Inspect its negative/positive summary.
B. Add single_value_V and two_values_V. Observe which sample statistics become
   mathematically undefined for one valid observation.
C. Add nonfinite_V. With policy omit, +Inf and -Inf are excluded. Then switch
   policy to error and rerun to see the explicit scientific-configuration error.
D. Change sel_001 or disable the Selection and verify that counts/statistics and
   distribution plots follow the analyzed subset.
E. Change Histogram bins / normalization and the box/whisker IQR multiplier,
   rerun, and inspect the new persistent plot variants.

Reference files
---------------
metadata/ground_truth.txt contains deterministic expected values for the default
first run. This Session is synthetic teaching material; it is not a measurement.
"""

def generate(target: Path):
    for d in ('raw','datasets','metadata/datasets','analysis','reference'): (target/d).mkdir(parents=True,exist_ok=True)
    headers=[v[0] for v in VARS]
    raw=target/'raw/student_descriptive.csv'
    with raw.open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f,lineterminator='\n'); w.writerow(headers); w.writerows([[fmt(v) for v in r] for r in ROWS])
    canonical=target/DATASET_FILE; shutil.copyfile(raw,canonical)
    digest=sha256(canonical)
    ds_items=[('id',DATASET_ID),('kind','table.generic'),('contract','table.generic'),('format','csv'),('storage_kind','text'),('media_type','text/csv'),('path',DATASET_FILE),('columns',';'.join(headers)),('variables',';'.join(headers)),('units',';'.join(v[1] for v in VARS)),('semantic_roles',';'.join(v[2] for v in VARS)),('source_module','session_generator.descriptive_statistics_student_lab'),('source_raw','raw/student_descriptive.csv'),('source_sha256',digest),('canonical_sha256',digest),('sha256',digest),('row_count',str(len(ROWS))),('sample_count',str(len(ROWS))),('var_count',str(len(VARS))),('variable_schema_api_version','3'),('canonical_access_api_version','2'),('canonical_delimiter','comma'),('source_delimiter','comma')]
    for i,(name,unit,role) in enumerate(VARS,1):
        p=f'var{i}_'; ds_items += [(p+'variable_id',name),(p+'enabled','1'),(p+'source_column',str(i)),(p+'canonical_position',str(i)),(p+'original_header',name),(p+'canonical',name),(p+'unit',unit),(p+'semantic_role',role),(p+'semantic_source','generator'),(p+'semantic_reason','Declared by the deterministic descriptive-statistics student generator'),(p+'value_kind','number'),(p+'dtype','float64'),(p+'rank','1'),(p+'shape',str(len(ROWS))),(p+'dimension_ids','row'),(p+'coordinate_variable_ids','' if name=='sample' else 'sample'),(p+'coordinate_role','coordinate' if name=='sample' else 'data'),(p+'axis_kind','explicit' if name=='sample' else 'none'),(p+'axis_origin',''),(p+'axis_step',''),(p+'axis_count',''),(p+'component_ids',''),(p+'group_id','student_lab')]
    write_ini(target/'metadata/datasets.ini',[('registry',[('api_version','1'),('access_api_version','2'),('inspection_api_version','1'),('session_mode','analysis_only'),('count','1')]),(f'dataset.{DATASET_ID}',ds_items)])
    write_ini(target/f'metadata/datasets/{DATASET_ID}.ini',[('dataset_metadata',[('api_version','1'),('dataset_id',DATASET_ID),('updated_at','2026-09-24T00:00:00+0000'),('count','4')]),('metadata',[('teaching.purpose','Descriptive statistics student exercise'),('teaching.synthetic','true'),('teaching.selection','sample 3 through 12'),('teaching.expected_plot_variants','4')])])
    selection=[('api_version','1'),('id','sel_001'),('type','x_range'),('source_dataset_id',DATASET_ID),('source_role','primary'),('x_variable','sample'),('x_variable_id','sample'),('x_unit',''),('x_min','3'),('x_max','12'),('x_coordinate_space','source'),('x_display_unit',''),('x_display_min','3'),('x_display_max','12'),('x_binding_count','0'),('x_bindings',''),('y_variable',''),('y_variable_id',''),('y_unit',''),('y_min',''),('y_max',''),('producer_module',''),('producer_graph',''),('producer_variant',''),('created_at','2026-09-24T00:00:00+0000'),('updated_at','2026-09-24T00:00:00+0000')]
    write_ini(target/'metadata/dataset_selections.ini',[('dataset_selection_api',[('api_version','1'),('ids','sel_001')]),('dataset_selection.sel_001',selection)])
    manifest=[('pipeline',[('format','2'),('module_api_version','1')]),('session',[('mode','analysis_only')]),('experiment',[('name','Descriptive Statistics Student Lab'),('project','GX-TXT Statistics Training'),('date','2026-09-24'),('notes','Deterministic synthetic data for teaching descriptive statistics and plot variants. Read STUDENT_GUIDE.txt before the first run.')]),('source_variables',[('count',str(len(VARS)))])]
    for i,(name,unit,role) in enumerate(VARS,1): manifest.append((f'source_variable.{i}',[('enabled','1'),('source_column',str(i)),('source_channel',''),('original_header',name),('canonical',name),('unit',unit),('semantic_role',role),('instrument_id',''),('instrument_channel','')]))
    manifest += [('module_state',[('enabled',MODULE_ID),('run',MODULE_ID)]),('module_config.'+MODULE_ID,[('selection','sel_001'),('nonfinite_policy','omit'),('percentiles','5;10;90;95'),('output_dataset_id','student.descriptive.summary'),('render_graphs','1'),('histogram_bins','auto'),('histogram_normalization','count'),('box_whisker_iqr','1.5'),('box_show_outliers','1')]),('analysis_source_map_api',[('version','1')]),('module_analysis_sources.'+MODULE_ID,[('ids','primary')]),('module_analysis_source.'+MODULE_ID+'.primary',[('dataset_id',DATASET_ID)]),('repeatable_config_api',[('version','1')]),('repeatable_config.'+MODULE_ID+'.variables',[('api_version','1'),('rows','row1;row2;row3;row4'),('columns','variable')])]
    selected=['voltage_V','voltage_mV','current_A','constant_V']
    for i,name in enumerate(selected,1):
        manifest.append((f'repeatable_config.{MODULE_ID}.variables.row{i}',[('variable',name)]))
        manifest.append((f'repeatable_variable_id.{MODULE_ID}.variables.row{i}',[('variable',f'{DATASET_ID}|{name}')]))
    manifest += [('dataset_variable_schema_api',[('version','3')]),('dataset_selection_api',[('version','1'),('ids','sel_001')]),('dataset_selection.sel_001',selection)]
    write_ini(target/'metadata/manifest.ini',manifest)
    (target/'metadata/ground_truth.txt').write_text(ground_truth_text(),encoding='utf-8')
    (target/'STUDENT_GUIDE.txt').write_text(student_guide_text(),encoding='utf-8')

def main():
    p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id',required=True); p.add_argument('--generator-id',required=True); a=p.parse_args()
    if a.generator_id!='descriptive_statistics_student_lab': raise SystemExit('Unexpected generator ID')
    target=Path(a.target_session).resolve(); generate(target)
    print(f'Generated Descriptive Statistics Student Lab in {target}')
if __name__=='__main__': main()
