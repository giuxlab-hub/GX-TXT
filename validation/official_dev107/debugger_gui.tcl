# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 250}} {after $ms {set ::settleTick 1};vwait ::settleTick;update}
proc waitFor {expression {seconds 60}} {
 set deadline [expr {[clock seconds]+$seconds}]
 while {![uplevel 1 [list expr $expression]]} {if {[clock seconds]>$deadline} {error "Timed out: $expression"};settle 80}
}
proc menuSelect {button index} {
 click $button;settle 150;set m $button.menu
 exec xdotool mousemove [expr {[winfo rootx $m]+30}] [expr {[winfo rooty $m]+[$m yposition $index]+9}]
 update;exec xdotool mousedown 1;update;exec xdotool mouseup 1;settle
}
foreach lang {Python Octave} {
 set lower [string tolower $lang];set w .gxtxt_${lower}_script_workspace
 ::GX::modulePublicApiActivate analysis.${lower}_script [string toupper $lang]_SCRIPT_EDITOR_API_v1
 ::GX::viewerOpen analysis.${lower}_script ${lower}_script_editor
 settle 600;menuSelect $w.toolbar.view 2
 set p $w.p.debug
 if {[$p.controls.start instate !disabled]} {error {No-Session Debug Start must be disabled}}
 capture $w ${lower}_no_session_debug
 click $p.footer.close
}
set ::GX::cfg(output_root) [file join $::out Sessions]
::GX::createNewSession dev107_debug_synthetic
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
foreach lang {Python Octave} {
 set lower [string tolower $lang];set w .gxtxt_${lower}_script_workspace
 if {$lang eq {Python}} {
  set code {# Synthetic native debugger exercise
def twice(value):
    result = value * 2
    return result

total = 0
for sample in range(8):
    total += twice(sample)
print('DEBUG_RESULT', total)
}
  set breakpoint 8
 } else {
  set code {% Synthetic native debugger exercise
total = 0;
for sample = 1:8
    doubled = sample * 2;
    total = total + doubled;
endfor
fprintf('DEBUG_RESULT %d\n', total);
}
  set breakpoint 4
 }
 append code [string repeat "\n" 2]
 for {set i 0} {$i<22} {incr i} {append code [expr {$lang eq {Python} ? {# Presentation fixture} : {% Presentation fixture}}] "\n"}
 ::GX::scriptRegistrySave session debug_$lower "Synthetic $lang debugging" $code [dict create language $lang]
 ::GX::${lang}ScriptEditorUI::_refreshDocuments
 ::GX::${lang}ScriptEditorUI::_loadDocument session:debug_$lower
 waitFor {[dict get $::GX::SourceSurface::state($w.p.center.edit,model) line_count]>25}
 ::GX::sourceSurfaceBreakpoints $w.p.center.edit toggle $breakpoint
 menuSelect $w.toolbar.view 2;set p $w.p.debug
 capture $w ${lower}_before_start
 click $p.controls.start
 waitFor {[info exists ::GX::ScriptDebug::state($p,observation)] && [dict get $::GX::ScriptDebug::state($p,observation) state] eq {PAUSED}}
 record ${lower}_first_stop $::GX::ScriptDebug::state($p,observation)
 capture $w ${lower}_first_stop
 set sequence [dict get $::GX::ScriptDebug::state($p,observation) sequence]
 click $p.controls.continue
 waitFor {[dict get $::GX::ScriptDebug::state($p,observation) state] eq {PAUSED} && [dict get $::GX::ScriptDebug::state($p,observation) sequence]>$sequence}
 record ${lower}_breakpoint_stop $::GX::ScriptDebug::state($p,observation)
 capture $w ${lower}_breakpoint_stop
 click $p.controls.stop
 waitFor {$::GX::ScriptDebug::state($p,phase) in {CANCELLED COMPLETED FAILED INTERRUPTED}}
 record ${lower}_stopped_job [::GX::scriptJobDescribe $::GX::ScriptDebug::state($p,job)]
 click $p.footer.close
 capture $w ${lower}_restored
}
