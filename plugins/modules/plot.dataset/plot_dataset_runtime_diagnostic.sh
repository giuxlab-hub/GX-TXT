#!/usr/bin/env bash
# Inspect the actual GX-TXT/plot.dataset runtime identity and Region Selection sidecars.
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
ROOT="${GXTXT_ROOT:-$PWD}"
SESSION="${1:-}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P || printf '%s' "$ROOT")"

echo "[runtime] root=$ROOT"
if [[ -f "$ROOT/VERSION.txt" ]]; then printf '[runtime] gx_txt_version='; tr -d '\r\n' < "$ROOT/VERSION.txt"; echo; else echo "[runtime] gx_txt_version=UNKNOWN"; fi

if command -v tclsh >/dev/null 2>&1 && [[ -f "$ROOT/gxtxt_pipeline.tcl" ]]; then
  GXTXT_DIAG_ROOT="$ROOT" tclsh <<'TCL'
set root $::env(GXTXT_DIAG_ROOT)
cd $root
set argv0 __not_main__
source gxtxt_pipeline.tcl
::GX::defaults
::GX::loadModuleCatalog
set id plot.dataset
puts "\[runtime\] loaded_module_version=[::GX::moduleField $id version UNKNOWN]"
if {[info exists ::GX::moduleCatalog($id,descriptor)]} {
    puts "\[runtime\] loaded_descriptor=[file normalize $::GX::moduleCatalog($id,descriptor)]"
} else {
    puts {\[runtime\] loaded_descriptor=UNKNOWN}
}
puts "\[runtime\] binding_roles=[join [::GX::moduleBindingRoles $id] ,]"
puts "\[runtime\] config_keys=[join [::GX::moduleConfigKeys $id] ,]"
TCL
else
  echo "[runtime] tcl_catalog_probe=UNAVAILABLE"
fi

echo "[runtime] descriptor_copies_begin"
mapfile -t copies < <(find "$ROOT" -type f -path '*/plot.dataset/module.ini' -print 2>/dev/null | sort)
for f in "${copies[@]}"; do
  v="$(awk -F= '$1=="version"{print $2;exit}' "$f" | tr -d '\r')"
  echo "[runtime] descriptor_copy=$f version=${v:-UNKNOWN}"
done
echo "[runtime] descriptor_copy_count=${#copies[@]}"
echo "[runtime] descriptor_copies_end"

if [[ -z "$SESSION" ]]; then
  echo "[session] not_supplied=1"
  echo "[session] usage=$0 /absolute/session/path"
  exit 0
fi
SESSION="$(cd "$SESSION" 2>/dev/null && pwd -P || printf '%s' "$SESSION")"
echo "[session] path=$SESSION"
if [[ ! -d "$SESSION" ]]; then echo "[session] missing=1"; exit 2; fi

mf="$SESSION/metadata/manifest.ini"
if [[ -f "$mf" ]]; then
  echo "[session] legacy_state_begin"
  grep -nEi '(^|[.=])(y2|extra_series|family)([.=]|$)|bindings\.(x|y|y2|family)|analysis_source.*primary|plotspec' "$mf" || true
  echo "[session] legacy_state_end"
else
  echo "[session] manifest_missing=1"
fi

shopt -s nullglob
pngs=("$SESSION"/analysis/plot.dataset/*.png)
if ((${#pngs[@]}==0)); then echo "[region] png_count=0"; exit 0; fi
echo "[region] png_count=${#pngs[@]}"
for png in "${pngs[@]}"; do
  base="$(basename "$png" .png)"
  md="$(dirname "$png")/.gxtxt_plotmeta/$base.ini"
  echo "[region] png=$png"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$png" <<'PY'
import struct,sys
p=sys.argv[1]
try:
    with open(p,'rb') as f:
        sig=f.read(24)
    if sig[:8]==b'\x89PNG\r\n\x1a\n' and sig[12:16]==b'IHDR':
        w,h=struct.unpack('>II',sig[16:24]); print(f'[region] png_dimensions={w}x{h}')
except Exception as e:
    print(f'[region] png_dimensions_error={e}')
PY
  fi
  if [[ ! -f "$md" ]]; then echo "[region] metadata_missing=1 metadata=$md"; continue; fi
  echo "[region] metadata=$md"
  grep -E '^(selection_supported|primary_axes_count|overlay_axes_count|image_width|image_height|pixel_rect|position|xlim|xscale|tag)=' "$md" | sed 's/^/[region] /'
  ss="$(awk -F= '$1=="selection_supported"{print $2;exit}' "$md" | tr -d '\r')"
  pc="$(awk -F= '$1=="primary_axes_count"{print $2;exit}' "$md" | tr -d '\r')"
  rect="$(awk -F= '$1=="pixel_rect"{print $2;exit}' "$md" | tr -d '\r')"
  if [[ "$ss" == "0" ]]; then
    if [[ "$pc" == "1" && -z "$rect" ]]; then
      echo "[region] failure_class=RASTER_CALIBRATION_FAILED_AFTER_VALID_SINGLE_PRIMARY_TOPOLOGY"
    elif [[ -n "$pc" && "$pc" != "1" ]]; then
      echo "[region] failure_class=PRIMARY_AXES_TOPOLOGY_REJECTED"
    else
      echo "[region] failure_class=UNRESOLVED_FROM_SIDECAR"
    fi
  elif [[ "$ss" == "1" ]]; then
    echo "[region] failure_class=NONE_METADATA_SUPPORTS_SELECTION"
  else
    echo "[region] failure_class=SELECTION_SUPPORTED_FIELD_MISSING"
  fi
done
