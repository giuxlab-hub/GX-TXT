# SPDX-License-Identifier: GPL-3.0-or-later
"""Read inert Tcl dictionaries from owned profile outputs, producing concise reports."""
import json
import statistics
import sys
import tkinter
from pathlib import Path

T = tkinter.Tcl()

def asdict(text):
    row = T.splitlist(text)
    if len(row) % 2:
        raise ValueError('Odd dictionary')
    return dict(zip(row[::2], row[1::2]))

def median(values):
    return statistics.median(values)

def load(directory):
    d = Path(directory).resolve()
    summary = {'evidence': str(d), 'scope': 'Automated timing; not human GUI acceptance'}
    core = d / 'measurements.tcldict'
    if core.exists():
        rows = []
        for raw in T.splitlist(core.read_text()):
            row = asdict(raw)
            us = [int(t) for t in T.splitlist(row['microseconds'])]
            rows.append({'history_steps': int(row['history_steps']), 'stage': row['stage'],
                         'median_ms': median(us) / 1000, 'min_ms': min(us) / 1000,
                         'max_ms': max(us) / 1000, 'samples_us': us})
        summary['stages'] = rows
    curve = d / 'curve_operations.tcldict'
    if not curve.exists():
        curve = d / 'curve_progress.tcldict'
    if curve.exists():
        rows = []
        for raw in T.splitlist(curve.read_text()):
            row = asdict(raw)
            stages = {name: {k: int(v) for k, v in asdict(stats).items()}
                      for name, stats in asdict(row['stages']).items()}
            rows.append({k: int(row[k]) for k in ('move', 'steps', 'record_bytes', 'acceptance_us', 'ui_latency_us')} | {'stages': stages})
        summary['curve'] = {'moves': len(rows), 'first_3_median_acceptance_ms': median([r['acceptance_us'] for r in rows[:3]])/1000,
                            'last_3_median_acceptance_ms': median([r['acceptance_us'] for r in rows[-3:]])/1000,
                            'max_acceptance_ms': max(r['acceptance_us'] for r in rows)/1000,
                            'last_3_median_ui_latency_ms': median([r['ui_latency_us'] for r in rows[-3:]])/1000,
                            'last_operation': rows[-1]}
    (d / 'performance_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    lines = ['# DEV111-P017 performance measurements', '', summary['scope'], '']
    if 'stages' in summary:
        lines += ['| Retained steps | Stage | Median ms | Min ms | Max ms |', '|---:|---|---:|---:|---:|']
        for row in summary['stages']:
            lines.append(f"| {row['history_steps']} | {row['stage']} | {row['median_ms']:.3f} | {row['min_ms']:.3f} | {row['max_ms']:.3f} |")
    if 'curve' in summary:
        c = summary['curve']; last = c['last_operation']
        lines += ['', f"True CAD translates: {c['moves']}; retained steps {last['steps']}; record {last['record_bytes']:,} bytes.",
                  f"First three median acceptance: {c['first_3_median_acceptance_ms']:.3f} ms; last three: {c['last_3_median_acceptance_ms']:.3f} ms; maximum: {c['max_acceptance_ms']:.3f} ms.",
                  f"Last three median queued UI timer latency: {c['last_3_median_ui_latency_ms']:.3f} ms.", '',
                  'Final operation inclusive stage times; nested stages overlap:', '', '| Procedure | Calls | Total ms |', '|---|---:|---:|']
        for name, row in sorted(last['stages'].items(), key=lambda i: i[1]['total_us'], reverse=True):
            lines.append(f"| `{name}` | {row['calls']} | {row['total_us']/1000:.3f} |")
    (d / 'performance_summary.md').write_text('\n'.join(lines) + '\n')
    return summary

summaries = [load(arg) for arg in sys.argv[1:]]
if len(summaries) == 2 and all('curve' in s for s in summaries):
    a, b = [s['curve'] for s in summaries]
    ratio = a['last_3_median_acceptance_ms'] / b['last_3_median_acceptance_ms']
    comparison = {'before': summaries[0]['evidence'], 'after': summaries[1]['evidence'],
                  'before_moves': a['moves'], 'after_moves': b['moves'],
                  'same_move_count': a['moves'] == b['moves'],
                  'median_final_acceptance_speedup': ratio,
                  'before_last_record_bytes': a['last_operation']['record_bytes'],
                  'after_last_record_bytes': b['last_operation']['record_bytes']}
    Path(summaries[1]['evidence'], 'comparison.json').write_text(json.dumps(comparison, indent=2)+'\n')
print(json.dumps(summaries, indent=2))
