#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate a deterministic ready-to-run GX-TXT grouped-statistics teaching Session."""
from __future__ import annotations
import argparse, csv, hashlib, math, shutil
from pathlib import Path

GENERATOR_VERSION = "1.0.0"
DATASET_ID = "student.grouped.source"
DATASET_FILE = f"datasets/{DATASET_ID}.csv"
MODULE_ID = "analysis.statistics.grouped"

# sample, site, batch, voltage_V, voltage_mV, current_A, constant_V
ROWS = [
    (1,"North","B1",1.00,1000,0.100,5.0),
    (2,"South","B1",2.00,2000,0.200,5.0),
    (3,"East","B1",3.00,3000,0.300,5.0),
    (4,"North","B1",1.20,1200,0.110,5.0),
    (5,"South","B1",2.20,2200,0.210,5.0),
    (6,"East","B1",3.20,3200,0.310,5.0),
    (7,"North","B2",1.40,1400,0.120,5.0),
    (8,"","B2",9.90,9900,0.990,5.0),
    (9,"South","B2",2.40,2400,0.220,5.0),
    (10,"East","B2",3.40,3400,0.320,5.0),
    (11,"North","B2",math.nan,math.nan,0.130,5.0),
    (12,"South","B2",2.60,2600,0.230,5.0),
    (13,"East","B2",3.60,3600,0.330,5.0),
    (14,"North","B3",1.80,1800,math.inf,5.0),
    (15,"South","B3",2.80,2800,0.250,5.0),
    (16,"East","B3",3.80,3800,0.350,5.0),
    (17,"North","B3",2.00,2000,0.150,5.0),
    (18,"South","B3",3.00,3000,0.260,5.0),
]
VARS = [
    ("sample","","independent","float64","number"),
    ("site","","category","string","text"),
    ("batch","","category","string","text"),
    ("voltage_V","V","measured","float64","number"),
    ("voltage_mV","mV","measured","float64","number"),
    ("current_A","A","measured","float64","number"),
    ("constant_V","V","measured","float64","number"),
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


def quantile_type7(xs, p):
    xs=sorted(xs); n=len(xs)
    if n == 1: return xs[0]
    pos=(n-1)*p; lo=int(math.floor(pos)); hi=int(math.ceil(pos))
    return xs[lo] if lo==hi else xs[lo]+(pos-lo)*(xs[hi]-xs[lo])


def stats(values):
    x=[float(v) for v in values if math.isfinite(float(v))]
    n=len(x)
    if not n:
        return {'n':0,'min':math.nan,'max':math.nan,'mean':math.nan,'median':math.nan,'q1':math.nan,'q3':math.nan,'iqr':math.nan,'std':math.nan,'sem':math.nan}
    mean=sum(x)/n
    var=sum((v-mean)**2 for v in x)/(n-1) if n>1 else math.nan
    q1=quantile_type7(x,.25); q3=quantile_type7(x,.75)
    return {'n':n,'min':min(x),'max':max(x),'mean':mean,'median':quantile_type7(x,.5),'q1':q1,'q3':q3,'iqr':q3-q1,'std':math.sqrt(var) if n>1 else math.nan,'sem':math.sqrt(var/n) if n>1 else math.nan}


def default_selected_rows():
    return [r for r in ROWS if 3 <= r[0] <= 18]


def ground_truth_text():
    selected=default_selected_rows(); valid_group=[r for r in selected if r[1].strip()]
    lines=[
        "GX-TXT Grouped Statistics Student Lab - reference values","",
        "Configured Selection: sample 3 through 18 inclusive.",
        "Configured grouping variable: site.",
        "Configured value variables: voltage_V, voltage_mV, current_A, constant_V.",
        "NaN / Inf value policy: omit.",
        "Missing / invalid group policy: omit.",
        f"Selected rows={len(selected)}",f"Rows excluded for missing site={len(selected)-len(valid_group)}","",
        "Expected group order (first appearance inside Selection):",
        "  1 -> East","  2 -> North","  3 -> South","",
    ]
    cols=[(3,'voltage_V'),(4,'voltage_mV'),(5,'current_A'),(6,'constant_V')]
    for gi,site in enumerate(['East','North','South'],1):
        grows=[r for r in valid_group if r[1]==site]
        lines.append(f"Group {gi}: {site}")
        lines.append(f"  observation_count={len(grows)}")
        for col,name in cols:
            vals=[r[col] for r in grows]; s=stats(vals)
            lines.append(f"  {name}")
            lines.append(f"    count={s['n']}")
            lines.append(f"    excluded_count={len(vals)-s['n']}")
            for key in ['min','max','mean','median','std','sem','q1','q3','iqr']:
                val=s[key]
                lines.append(f"    {key}={'nan' if math.isnan(val) else format(val,'.17g')}")
        lines.append("")
    lines += [
        "Expected automatic plot grouping:",
        "  Unit family 1: voltage_V + voltage_mV + constant_V.",
        "  Unit family 2: current_A.",
        "  Expected persistent plot variants: 5.",
        "    2 mean/SEM variants + 2 median/IQR variants + 1 group-count variant.",
        "",
    ]
    return '\n'.join(lines)


def student_guide_text():
    return """GX-TXT GROUPED STATISTICS - STUDENT LAB
=========================================

Purpose
-------
Learn how to calculate descriptive statistics by category using
analysis.statistics.grouped, inspect the machine-readable grouped Dataset, and
read persistent plot.dataset variants.

First run
---------
1. Open this generated Session in GX-TXT.
2. Open Grouped Statistics configuration.
3. Verify Dataset = student.grouped.source.
4. Value variables are preconfigured as voltage_V, voltage_mV, current_A, and
   constant_V.
5. Grouping variable is preconfigured as site.
6. Verify Selection sel_001: sample 3 through 18 inclusive.
7. Leave NaN / Inf value policy = omit.
8. Leave Missing / invalid group policy = omit.
9. Leave Create automatic grouped plots enabled and run the module.
10. Open student.grouped.summary and grouped_statistics_report.txt.
11. Compare the group mapping and numerical results with
    metadata/ground_truth.txt.
12. Inspect the persistent plot.dataset variants. The default run should create
    five variants: mean +/- SEM and median + IQR for the voltage-compatible
    family, the same two for current_A, plus one group observation-count bar
    plot.

What to notice
--------------
- Groups are numbered in order of first appearance after Selection.
- site is a string grouping variable; its original labels remain in the result.
- voltage_V, voltage_mV, and constant_V are unit-compatible and share plots.
- current_A is dimensionally incompatible with voltage and is plotted separately.
- one selected row has an empty site and is excluded by the missing-group policy.
- North contains a NaN voltage value and an Inf current value; omission is
  counted separately for each value variable.
- the source Dataset is not modified.

Exercises
---------
A. Change the grouping variable from site to batch. Rerun and compare the new
   group order, counts, statistics, and plot variants.
B. Disable the Selection and rerun. Verify that sample 1 and 2 now contribute.
C. Change Missing / invalid group policy to error. The blank site row must
   produce an explicit error rather than disappearing silently.
D. Restore missing-group policy to omit, then change NaN / Inf value policy to
   error. The non-finite voltage/current observations must produce an explicit
   error.
E. Remove current_A from Value variables. Verify that only one compatible-unit
   family remains and the number of automatic variants decreases accordingly.
F. Add only constant_V and inspect zero spread within every group.

Reference files
---------------
metadata/ground_truth.txt contains deterministic expected values for the default
first run. This Session is synthetic teaching material, not experimental data.
"""


def generate(target: Path):
    for d in ('raw','datasets','metadata/datasets','analysis','reference'): (target/d).mkdir(parents=True,exist_ok=True)
    headers=[v[0] for v in VARS]
    raw=target/'raw/student_grouped.csv'
    with raw.open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f,lineterminator='\n');w.writerow(headers);w.writerows([[fmt(v) for v in r] for r in ROWS])
    canonical=target/DATASET_FILE;shutil.copyfile(raw,canonical);digest=sha256(canonical)
    ds=[('id',DATASET_ID),('kind','table.generic'),('contract','table.generic'),('format','csv'),('storage_kind','text'),('media_type','text/csv'),('path',DATASET_FILE),('columns',';'.join(headers)),('variables',';'.join(headers)),('units',';'.join(v[1] for v in VARS)),('semantic_roles',';'.join(v[2] for v in VARS)),('source_module','session_generator.grouped_statistics_student_lab'),('source_raw','raw/student_grouped.csv'),('source_sha256',digest),('canonical_sha256',digest),('sha256',digest),('row_count',str(len(ROWS))),('sample_count',str(len(ROWS))),('var_count',str(len(VARS))),('variable_schema_api_version','3'),('canonical_access_api_version','2'),('canonical_delimiter','comma'),('source_delimiter','comma')]
    for i,(name,unit,role,dtype,value_kind) in enumerate(VARS,1):
        p=f'var{i}_';ds += [(p+'variable_id',name),(p+'enabled','1'),(p+'source_column',str(i)),(p+'canonical_position',str(i)),(p+'original_header',name),(p+'canonical',name),(p+'unit',unit),(p+'semantic_role',role),(p+'semantic_source','generator'),(p+'semantic_reason','Declared by deterministic grouped-statistics student generator'),(p+'value_kind',value_kind),(p+'dtype',dtype),(p+'rank','1'),(p+'shape',str(len(ROWS))),(p+'dimension_ids','row'),(p+'coordinate_variable_ids','' if name in {'sample','site','batch'} else 'sample'),(p+'coordinate_role','coordinate' if name=='sample' else ('auxiliary' if name in {'site','batch'} else 'data')),(p+'axis_kind','explicit' if name=='sample' else 'none'),(p+'axis_origin',''),(p+'axis_step',''),(p+'axis_count',''),(p+'component_ids',''),(p+'group_id','student_grouped_lab')]
    write_ini(target/'metadata/datasets.ini',[('registry',[('api_version','1'),('access_api_version','2'),('inspection_api_version','1'),('session_mode','analysis_only'),('count','1')]),(f'dataset.{DATASET_ID}',ds)])
    write_ini(target/f'metadata/datasets/{DATASET_ID}.ini',[('dataset_metadata',[('api_version','1'),('dataset_id',DATASET_ID),('updated_at','2026-09-24T00:00:00+0000'),('count','5')]),('metadata',[('teaching.purpose','Grouped statistics student exercise'),('teaching.synthetic','true'),('teaching.default_group','site'),('teaching.selection','sample 3 through 18'),('teaching.expected_plot_variants','5')])])
    selection=[('api_version','1'),('id','sel_001'),('type','x_range'),('source_dataset_id',DATASET_ID),('source_role','primary'),('x_variable','sample'),('x_variable_id','sample'),('x_unit',''),('x_min','3'),('x_max','18'),('x_coordinate_space','source'),('x_display_unit',''),('x_display_min','3'),('x_display_max','18'),('x_binding_count','0'),('x_bindings',''),('y_variable',''),('y_variable_id',''),('y_unit',''),('y_min',''),('y_max',''),('producer_module',''),('producer_graph',''),('producer_variant',''),('created_at','2026-09-24T00:00:00+0000'),('updated_at','2026-09-24T00:00:00+0000')]
    write_ini(target/'metadata/dataset_selections.ini',[('dataset_selection_api',[('api_version','1'),('ids','sel_001')]),('dataset_selection.sel_001',selection)])
    manifest=[('pipeline',[('format','2'),('module_api_version','1')]),('session',[('mode','analysis_only')]),('experiment',[('name','Grouped Statistics Student Lab'),('project','GX-TXT Statistics Training'),('date','2026-09-24'),('notes','Deterministic synthetic data for teaching grouped descriptive statistics. Read STUDENT_GUIDE.txt before the first run.')]),('source_variables',[('count',str(len(VARS)))])]
    for i,(name,unit,role,_,_) in enumerate(VARS,1):manifest.append((f'source_variable.{i}',[('enabled','1'),('source_column',str(i)),('source_channel',''),('original_header',name),('canonical',name),('unit',unit),('semantic_role',role),('instrument_id',''),('instrument_channel','')]))
    manifest += [('module_state',[('enabled',MODULE_ID),('run',MODULE_ID)]),('module_config.'+MODULE_ID,[('selection','sel_001'),('nonfinite_policy','omit'),('missing_group_policy','omit'),('output_dataset_id','student.grouped.summary'),('render_graphs','1')]),('analysis_source_map_api',[('version','1')]),('module_analysis_sources.'+MODULE_ID,[('ids','primary')]),('module_analysis_source.'+MODULE_ID+'.primary',[('dataset_id',DATASET_ID)]),('repeatable_config_api',[('version','1')]),('repeatable_config.'+MODULE_ID+'.values',[('api_version','1'),('rows','row1;row2;row3;row4'),('columns','variable')])]
    selected=['voltage_V','voltage_mV','current_A','constant_V']
    for i,name in enumerate(selected,1):
        manifest.append((f'repeatable_config.{MODULE_ID}.values.row{i}',[('variable',name)]))
        manifest.append((f'repeatable_variable_id.{MODULE_ID}.values.row{i}',[('variable',f'{DATASET_ID}|{name}')]))
    manifest += [('repeatable_config.'+MODULE_ID+'.grouping',[('api_version','1'),('rows','row1'),('columns','variable')]),(f'repeatable_config.{MODULE_ID}.grouping.row1',[('variable','site')]),(f'repeatable_variable_id.{MODULE_ID}.grouping.row1',[('variable',f'{DATASET_ID}|site')]),('dataset_variable_schema_api',[('version','3')]),('dataset_selection_api',[('version','1'),('ids','sel_001')]),('dataset_selection.sel_001',selection)]
    write_ini(target/'metadata/manifest.ini',manifest)
    (target/'metadata/ground_truth.txt').write_text(ground_truth_text(),encoding='utf-8')
    (target/'STUDENT_GUIDE.txt').write_text(student_guide_text(),encoding='utf-8')


def main():
    p=argparse.ArgumentParser();p.add_argument('--target-session',required=True);p.add_argument('--library-id',required=True);p.add_argument('--generator-id',required=True);a=p.parse_args()
    if a.generator_id!='grouped_statistics_student_lab':raise SystemExit('Unexpected generator ID')
    target=Path(a.target_session).resolve();generate(target);print(f'Generated Grouped Statistics Student Lab in {target}')

if __name__=='__main__':main()
