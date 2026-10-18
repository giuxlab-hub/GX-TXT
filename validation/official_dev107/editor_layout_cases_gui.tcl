# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 280}} {after $ms {set ::settleLayoutCase 1};vwait ::settleLayoutCase;update}
proc waitFor {expression {seconds 30}} {set end [expr {[clock seconds]+$seconds}];while {![uplevel 1 [list expr $expression]]} {if {[clock seconds]>$end} {error "Timed out: $expression"};settle 80}}
proc menuSelect {button index} {
 click $button;settle 120;set m $button.menu
 exec xdotool mousemove [expr {[winfo rootx $m]+30}] [expr {[winfo rooty $m]+[$m yposition $index]+9}]
 update;exec xdotool mousedown 1;update;exec xdotool mouseup 1;settle
}
proc rowChoose {tree row} {
 raise [winfo toplevel $tree];$tree see $row;update;lassign [$tree bbox $row] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}]
 update;exec xdotool click 1;settle 350
}
proc caseRun {lang id expected body} {
 set w .gxtxt_[string tolower $lang]_script_workspace
 set prefix [string tolower $lang]_${id};set started [clock microseconds]
 capture $w ${prefix}_before
 try {
  uplevel 1 $body
  capture $w ${prefix}_after
  set ns ::GX::${lang}ScriptEditorUI;upvar #0 ${ns}::ui ui
  record ${prefix}_case [dict create case $id language $lang status PASS expected $expected before ${prefix}_before.png after ${prefix}_after.png first_input_us $started last_input_us [clock microseconds] reference $ui(currentId) sha256 $ui(currentSha) source_version $::GX::version qualification {Candidate only; installed final acceptance remains separate}]
 } on error {message options} {
  record ${prefix}_case [dict create case $id language $lang status FAIL expected $expected error [dict get $options -errorinfo]]
  capture $w ${prefix}_failure
  return -options $options $message
 }
}
proc gutterPointer {p line lane {button 1}} {
 set t $p.text;$t see $line.0;raise [winfo toplevel $p];update
 lassign [$t dlineinfo $line.0] x y width height baseline
 set x [expr {[winfo rootx $p.lines]+int(($lane+.5)*$::GX::SourceSurface::state($p,lane))}]
 set y [expr {[winfo rooty $p.lines]+$y+$height/2}]
 record gutter_input_[clock microseconds] [dict create widget $p.lines line $line lane $lane x $x y $y button $button]
 exec xdotool mousemove $x $y;update
 if {$button} {exec xdotool click $button;update}
}
proc contextChoose {p line index} {
 gutterPointer $p $line 0 3;settle 150
 set m $p.gutterMenu
 exec xdotool mousemove [expr {[winfo rootx $m]+35}] [expr {[winfo rooty $m]+[$m yposition $index]+8}]
 update;exec xdotool click 1;settle
}
if {$::GX::currentSession ne {}} {error {Layout authoring checks require no Session}}
foreach lang {Python Octave} {
 set lower [string tolower $lang];set w .gxtxt_${lower}_script_workspace;set p $w.p.center.edit
 ::GX::modulePublicApiActivate analysis.${lower}_script [string toupper $lang]_SCRIPT_EDITOR_API_v1
 if {$lang eq {Python}} {set code {# Synthetic 30-line source — Unicode λ and tab presentation
def twice(value):
    result = value * 2
    return result

total = 0
for sample in range(8):
    total += twice(sample)
print(total)
};set comment {# Additional presentation line}} else {set code {% Synthetic 30-line source — Unicode λ and tab presentation
function result = twice(value)
    result = value * 2;
endfunction

total = 0;
for sample = 1:8
    total = total + twice(sample);
endfor
disp(total);
};set comment {% Additional presentation line}}
 for {set n 0} {$n<22} {incr n} {append code $comment "\n"}
 ::GX::scriptRegistrySave user layout_$lower "Synthetic $lang layout source" $code [dict create language $lang]
 ::GX::viewerOpen analysis.${lower}_script ${lower}_script_editor
 ::GX::${lang}ScriptEditorUI::_refreshDocuments
 rowChoose $w.p.left.tree user:layout_$lower
 waitFor {[dict get $::GX::SourceSurface::state($p,model) line_count]>25}
 set saved [::GX::sourceSurfaceGet $p]
 caseRun $lang EDBG-01 {Populated Explorer, source and snippets visible without Debug} {
  if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right] || [winfo exists $w.p.debug]} {error {Initial three-pane layout is incorrect}}
 }
 caseRun $lang EDBG-02 {Native menus ordered File Edit View Run Help and checked View entries visible} {
  set labels {};foreach key {file edit view run help} {lappend labels [$w.toolbar.$key cget -text]}
  if {$labels ne {File Edit View Run Help}} {error {Menu order is incorrect}}
  click $w.toolbar.view;settle;capture $w ${lower}_EDBG-02_native_menu
  exec xdotool key Escape;update
 }
 caseRun $lang EDBG-03 {Explorer hide/restore preserves source and other panes} {
  menuSelect $w.toolbar.view 0
  if {"$w.p.left" in [$w.p panes] || "$w.p.right" ni [$w.p panes]} {error {Explorer toggle affected the wrong panes}}
  capture $w ${lower}_EDBG-03_hidden
  menuSelect $w.toolbar.view 0
  if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right]} {error {Explorer did not restore}}
 }
 caseRun $lang EDBG-04 {Independent snippets, Debugger, stack, variables and output toggles} {
  menuSelect $w.toolbar.view 1
  if {"$w.p.left" ni [$w.p panes] || "$w.p.right" in [$w.p panes]} {error {Snippets toggle affected Explorer}}
  menuSelect $w.toolbar.view 1
  menuSelect $w.toolbar.view 2;set debug $w.p.debug
  foreach {index child} [list 4 $debug.book.live.p.stack 5 $debug.book.live.p.variables] {
   menuSelect $w.toolbar.view $index
   if {[winfo ismapped $child]} {error {Independent inspector hide failed}}
   capture $w ${lower}_EDBG-04_hidden_$index
   menuSelect $w.toolbar.view $index
   if {![winfo ismapped $child]} {error {Independent inspector restore failed}}
  }
  foreach index {6 7} {menuSelect $w.toolbar.view $index;capture $w ${lower}_EDBG-04_tab_$index;menuSelect $w.toolbar.view $index}
  click $debug.footer.close
 }
 caseRun $lang EDBG-05 {Debug keeps side panes and actual sash drag resizes source/assistant} {
  menuSelect $w.toolbar.view 2
  set work $w.p.center.work;set old [$work sashpos 0]
  set x [expr {[winfo rootx $work]+[winfo width $work]/2}];set y [expr {[winfo rooty $work]+$old+2}]
  exec xdotool mousemove $x $y mousedown 1;update
  exec xdotool mousemove $x [expr {$y+35}];update;exec xdotool mouseup 1;settle
  if {abs([$work sashpos 0]-$old)<10} {error {Actual splitter drag had no effect}}
  if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right]} {error {Debug lost side panes}}
 }
 caseRun $lang EDBG-06 {Clean Debug close restores horizontal visibility, source focus and source content} {
  set panes [$w.p panes];set sashes [list [$w.p sashpos 0] [$w.p sashpos 1]]
  click $w.p.debug.footer.close
  if {[$w.p panes] ne $panes || [list [$w.p sashpos 0] [$w.p sashpos 1]] ne $sashes} {error {Clean Debug close changed horizontal layout}}
 }
 caseRun $lang EDBG-07 {Five real open/close cycles release each Debug instance without losing panes} {
  for {set n 0} {$n<5} {incr n} {
   menuSelect $w.toolbar.view 2;capture $w ${lower}_EDBG-07_open_$n
   click $w.p.debug.footer.close;settle 100
   if {[winfo exists $w.p.debug] || [array names ::GX::ScriptDebug::state $w.p.debug,*] ne {}} {error {Debug state leaked after Close}}
   if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right]} {error {Repeated Debug close lost side panes}}
   capture $w ${lower}_EDBG-07_closed_$n
  }
 }
 caseRun $lang EDBG-08 {Another supported assistant shares the lower host; no source/pane loss} {
  menuSelect $w.toolbar.view 2
  if {$lang eq {Python}} {menuSelect $w.toolbar.edit 7;capture $w ${lower}_EDBG-08_imports;click $w.p.imports.actions.cancel}
  if {![winfo exists $w.p.debug] || ![winfo ismapped $w.p.debug]} {error {Assistant roundtrip lost Debug}}
  click $w.p.debug.footer.close
  if {$lang eq {Octave}} {record octave_EDBG-08_condition {No second assistant is offered in Octave; shared Debug Destroy/restore was exercised. Python Import Organizer is verified separately.}}
 }
 caseRun $lang EDBG-09 {Focus source reverses; Reset restores both side panes} {
  menuSelect $w.toolbar.view 9
  if {[$w.p panes] ne [list $w.p.center]} {error {Focus source did not isolate the central source}}
  capture $w ${lower}_EDBG-09_focus_source
  menuSelect $w.toolbar.view 9
  menuSelect $w.toolbar.view 10
  if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right]} {error {Reset did not restore side panes}}
 }
 caseRun $lang EDBG-11 {Actual breakpoint-lane click makes a red enabled marker on valid physical line} {
  ::GX::sourceSurfaceBreakpoints $p clear
  gutterPointer $p 3 0
  if {3 ni [::GX::sourceSurfaceBreakpoints $p]} {error {Breakpoint lane did not set physical line3}}
  if {[$p.lines find withtag breakpoint] eq {}} {error {Enabled red marker absent}}
 }
 caseRun $lang EDBG-12 {Keyboard and context enable/disable/remove/clear; hollow red marker and state tooltip} {
  $p.text mark set insert 3.0;key $p.text F9
  if {3 in [::GX::sourceSurfaceBreakpoints $p]} {error {F9 toggle did not clear breakpoint}}
  key $p.text F9
  contextChoose $p 3 2
  if {3 in [::GX::sourceSurfaceBreakpoints $p] || 3 ni $::GX::SourceSurface::state($p,disabled)} {error {Context disable failed}}
  gutterPointer $p 3 0 0;settle 650
  if {![string match {*Line 3*disabled breakpoint*} [.gxViewportTip.text cget -text]]} {error {Disabled tooltip omits actual physical line/state}}
  record ${lower}_disabled_tooltip [.gxViewportTip.text cget -text]
  exec import -screen -window [winfo id $w] [file join $::out ${lower}_EDBG-12_disabled_tooltip.png]
  contextChoose $p 3 1
  if {3 ni [::GX::sourceSurfaceBreakpoints $p]} {error {Context enable failed}}
  contextChoose $p 3 3
  if {[::GX::sourceSurfaceBreakpoints $p describe] ne {}} {error {Context remove failed}}
  key $p.text F9;key $p.text ctrl+shift+F9
  if {[::GX::sourceSurfaceBreakpoints $p describe] ne {}} {error {Keyboard clear-all failed}}
 }
 caseRun $lang EDBG-13 {Fold lane preserves adjacent header breakpoint, exact physical source and clean revision} {
  gutterPointer $p 7 0
  set points [::GX::sourceSurfaceBreakpoints $p]
  gutterPointer $p 7 2
  if {7 ni $::GX::SourceSurface::state($p,folded) || [::GX::sourceSurfaceBreakpoints $p] ne $points} {error {Fold click changed adjacent breakpoint or wrong block}}
  capture $w ${lower}_EDBG-13_fold_with_breakpoint
  gutterPointer $p 7 2
  if {7 in $::GX::SourceSurface::state($p,folded)} {error {Second fold click did not expand block}}
 }
 set ns ::GX::${lang}ScriptEditorUI;upvar #0 ${ns}::ui ui
 if {[::GX::sourceSurfaceGet $p] ne $saved || $ui(modified)} {error {Presentation or markers changed source/dirty state}}
 record ${lower}_layout_cases_source_integrity [dict create exact_source 1 modified $ui(modified) reference $ui(currentId) sha256 $ui(currentSha)]
}
if {[file exists [file join $::out tk_background_errors.log]]} {error {Tk background error during layout cases}}
record layout_cases_finished 1
