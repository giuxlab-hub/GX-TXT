#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create a canonical CSV from a source table without modifying the RAW input."""
import argparse, collections, csv, re

p = argparse.ArgumentParser()
p.add_argument('--input', required=True)
p.add_argument('--output', required=True)
p.add_argument('--delimiter', required=True)
p.add_argument('--header-rows', type=int, required=True)
p.add_argument('--map', action='append', default=[], help='1-based source column=canonical_name')
p.add_argument('--encoding', default='utf-8-sig')
p.add_argument('--skip-leading', type=int, default=0)
p.add_argument('--footer-rows', type=int, default=0)
p.add_argument('--comment-prefix', default='')
p.add_argument('--whitespace', action='store_true')
p.add_argument('--decimal', choices=('dot', 'comma'), default='dot')
p.add_argument('--scale', action='append', default=[], help='canonical_name=factor')
p.add_argument('--offset', action='append', default=[], help='canonical_name=value')
a = p.parse_args()

delim = {'comma': ',', 'semicolon': ';', 'tab': '\t'}.get(a.delimiter, a.delimiter)
if len(delim) != 1 and not a.whitespace:
    raise SystemExit('delimiter must resolve to one character')
if a.header_rows < 1:
    raise SystemExit('header-rows must be >= 1')
if a.skip_leading < 0 or a.footer_rows < 0:
    raise SystemExit('skip-leading and footer-rows must be >= 0')

mapping = []
for item in a.map:
    left, sep, name = item.partition('=')
    if not sep or not left.isdigit() or int(left) < 1 or not name:
        raise SystemExit(f'invalid mapping: {item!r}')
    mapping.append((int(left)-1, name))

def numeric_rules(values, label):
    out = {}
    for item in values:
        name, sep, value = item.partition('=')
        if not sep or not name or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*', name):
            raise SystemExit(f'invalid {label}: {item!r}')
        try:
            out[name] = float(value)
        except ValueError:
            raise SystemExit(f'invalid {label} value: {item!r}')
    return out

scales = numeric_rules(a.scale, 'scale')
offsets = numeric_rules(a.offset, 'offset')

def records(handle):
    def eligible_lines():
        for line in handle:
            if a.comment_prefix and line.lstrip().startswith(a.comment_prefix):
                continue
            if not line.strip() and (a.whitespace or a.comment_prefix):
                continue
            yield line
    if a.whitespace:
        for line in eligible_lines():
            yield re.split(r'\s+', line.strip())
    else:
        yield from csv.reader(eligible_lines(), delimiter=delim)

with open(a.input, 'r', encoding=a.encoding, newline='') as fi:
    for _ in range(a.skip_leading):
        if fi.readline() == '':
            raise SystemExit('input ends inside configured leading rows')
    r = records(fi)
    header = None
    for _ in range(a.header_rows):
        try:
            header = next(r)
        except StopIteration:
            raise SystemExit('input ends inside configured header rows')
    if not mapping:
        # v0.8.2 batch mode: preserve all source columns and use the final
        # configured header row as canonical column names.  The historical
        # single-file path still passes explicit --map options and is unchanged.
        mapping = [(i, str(name).strip()) for i, name in enumerate(header or [])]
        if not mapping or any(not name for _, name in mapping):
            raise SystemExit('identity import requires a non-empty name for every source column')
    maxidx = max(i for i, _ in mapping)
    if header is None or maxidx >= len(header):
        raise SystemExit('mapping references a column outside the header')
    selected = {name for _, name in mapping}
    if (set(scales) | set(offsets)) - selected:
        raise SystemExit('numeric transformation references an unmapped canonical column')
    with open(a.output, 'w', encoding='utf-8', newline='') as fo:
        w = csv.writer(fo, delimiter=',' if a.whitespace else delim, lineterminator='\n')
        w.writerow([name for _, name in mapping])
        rows_written = 0
        column_kinds = ['number'] * len(mapping)
        buffered = collections.deque()
        for rowno, row in enumerate(r, start=a.header_rows+a.skip_leading+1):
            if not row:
                continue
            buffered.append((rowno, row))
            if len(buffered) <= a.footer_rows:
                continue
            rowno, row = buffered.popleft()
            if maxidx >= len(row):
                raise SystemExit(f'row {rowno} has only {len(row)} columns; need {maxidx+1}')
            values = []
            for position, (i, name) in enumerate(mapping):
                value = row[i]
                if a.decimal == 'comma' and re.fullmatch(r'[-+]?[0-9]+(?:,[0-9]+)?(?:[eE][-+]?[0-9]+)?', value.strip()):
                    value = value.replace(',', '.')
                if name in scales or name in offsets:
                    try:
                        number = float(value)
                    except ValueError:
                        raise SystemExit(f'row {rowno} column {name}: numeric transformation needs a number')
                    value = format(number * scales.get(name, 1.0) + offsets.get(name, 0.0), '.17g')
                probe = value.strip()
                if probe and probe.lower() not in {'na', 'n/a', 'null'}:
                    try:
                        float(probe)
                    except ValueError:
                        # Leave pure clock-form elapsed-time columns for the
                        # schema layer, which has the declared unit needed to
                        # distinguish them from ordinary text.
                        if re.fullmatch(r'[0-9]+:[0-5][0-9]:[0-5][0-9](?:[.,][0-9]+)?', probe):
                            if column_kinds[position] == 'number':
                                column_kinds[position] = 'hms'
                        else:
                            column_kinds[position] = 'text'
                    else:
                        if column_kinds[position] == 'hms':
                            column_kinds[position] = 'text'
                values.append(value)
            w.writerow(values)
            rows_written += 1

print(f'rows={rows_written}')
print('kinds=' + ';'.join(column_kinds))
