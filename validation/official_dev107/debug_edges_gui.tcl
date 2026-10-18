# SPDX-License-Identifier: GPL-3.0-or-later
proc waitFor {expression {seconds 60}} {
 set deadline [expr {[clock seconds]+$seconds}]
 while {![uplevel 1 [list expr $expression]]} {if {[clock seconds]>$deadline} {error "Timed out: $expression"};settle 80}
}
proc nextStop {p previous} {
 waitFor {[info exists ::GX::ScriptDebug::state($p,observation)] && [dict get $::GX::ScriptDebug::state($p,observation) sequence]>$previous && $::GX::ScriptDebug::state($p,phase) in {PAUSED COMPLETED FAILED CANCELLED INTERRUPTED}}
 return $::GX::ScriptDebug::state($p,observation)
}
set ::edgeFailures {}
set ::GX::cfg(output_root) [file join $::out Sessions]
::GX::createNewSession dev107_pause_synthetic
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
foreach lang {Python Octave} {
 set lower [string tolower $lang];set w .gxtxt_${lower}_script_workspace;set p $w.p.debug
 try {
  if {$lang eq {Python}} {
   set code {# Synthetic bounded loop for native Pause control
def adjust(value):
    return value + 1
import time
total = 0
for sample in range(2000):
    total += sample
    time.sleep(0.01)
print('PAUSE_RESULT', total)
}
   set header 2
  } else {
   set code {% Synthetic bounded loop for native Pause control
1;
function result = adjust(value)
    result = value + 1;
endfunction
total = 0;
for sample = 0:1999
    total = total + sample;
    pause(0.01);
endfor
fprintf('PAUSE_RESULT %d\n', total);
}
   set header 3
  }
  ::GX::modulePublicApiActivate analysis.${lower}_script [string toupper $lang]_SCRIPT_EDITOR_API_v1
  ::GX::viewerOpen analysis.${lower}_script ${lower}_script_editor
  ::GX::scriptRegistrySave session ${lower}_pause "Synthetic $lang Pause" $code [dict create language $lang]
  ::GX::${lang}ScriptEditorUI::_refreshDocuments
  ::GX::${lang}ScriptEditorUI::_loadDocument session:${lower}_pause
  waitFor {[::GX::sourceSurfaceReady $w.p.center.edit] && [dict get $::GX::SourceSurface::state($w.p.center.edit,model) line_count]>8}
  ::GX::sourceSurfaceBreakpoints $w.p.center.edit clear
  menuSelect $w.toolbar.view 2
  click $p.controls.start
  waitFor {[info exists ::GX::ScriptDebug::state($p,observation)] && $::GX::ScriptDebug::state($p,phase) eq {PAUSED}}
  set initial $::GX::ScriptDebug::state($p,observation)
  capture $w ${lower}_pause_initial
  click $p.controls.continue
  waitFor {$::GX::ScriptDebug::state($p,phase) eq {RUNNING}}
  settle 200
  capture $w ${lower}_running_before_pause
  set capabilities [::GX::scriptJobDebugCapabilities $lang]
  set supportsPause [dict get $capabilities pause_supported]
  if {$supportsPause} {
   if {![$p.controls.pause instate !disabled]} {error {Actual running native Pause is incorrectly disabled}}
   click $p.controls.pause
   set paused [nextStop $p [dict get $initial sequence]]
   if {[dict get $paused state] ne {PAUSED} || [dict get $paused line]<=0} {error {Pause did not produce an actual native stopped source frame}}
  } else {
   if {![$p.controls.pause instate disabled]} {error {Unsupported native Pause is incorrectly enabled}}
   click $p.controls.pause
   if {![catch {::GX::scriptJobDebugControl $::GX::ScriptDebug::state($p,job) pause [dict get $initial source_sha256]} refusal]} {error {Unsupported native Pause was accepted through the public API}}
   settle 400
   if {$::GX::ScriptDebug::state($p,phase) ne {RUNNING}} {error {Unsupported Pause changed genuine native execution}}
   record ${lower}_unsupported_pause [dict create status {UNSUPPORTED, safely refused} capabilities $capabilities public_api_refusal $refusal job_id $::GX::ScriptDebug::state($p,job)]
   capture $w ${lower}_unsupported_pause_running_unchanged
   click $p.controls.stop
   waitFor {$::GX::ScriptDebug::state($p,phase) in {CANCELLED COMPLETED FAILED INTERRUPTED}}
   click $p.footer.close
   # The remaining paused-layout checks use a genuine native breakpoint,
   # not a simulated Pause or an interrupt that changes program semantics.
   ::GX::sourceSurfaceBreakpoints $w.p.center.edit toggle 8
   menuSelect $w.toolbar.view 2
   click $p.controls.start
   waitFor {[info exists ::GX::ScriptDebug::state($p,observation)] && $::GX::ScriptDebug::state($p,phase) eq {PAUSED}}
   set paused $::GX::ScriptDebug::state($p,observation)
   if {[dict get $paused line]!=8} {error {Native Octave breakpoint did not stop at the admitted physical line}}
  }
  record ${lower}_pause_native $paused
  capture $w ${lower}_paused_after_running
  set before [::GX::sourceSurfaceGet $w.p.center.edit]
  # Fold the unrelated helper using its true gutter hit target while paused.
  set t $w.p.center.edit.text;$t see $header.0;update
  lassign [$t dlineinfo $header.0] x y width height baseline
  set gutter $w.p.center.edit.lines
  exec xdotool mousemove [expr {[winfo rootx $gutter]+int(2.5*$::GX::SourceSurface::state($w.p.center.edit,lane))}] [expr {[winfo rooty $gutter]+$y+$height/2}]
  update;exec xdotool click 1;update;settle 800
  if {$header ni $::GX::SourceSurface::state($w.p.center.edit,folded)} {error {Native polling reopened an unrelated folded function}}
  capture $w ${lower}_paused_unrelated_fold_preserved
  if {[font actual TkDefaultFont -size]>=12 && $::GX::WorkspaceAssist::state($w,properties)} {
   menuSelect $w.toolbar.view 12
   record ${lower}_large_font_explicit_compact_properties 1
  }
  foreach size {850x550 900x560 1180x760 1650x900} {
   wm geometry $w $size;settle 350
   if {[::GX::sourceSurfaceGet $w.p.center.edit] ne $before} {error {Paused resize changed source}}
   if {$::GX::SourceSurface::state($w.p.center.edit,line)!=[dict get $paused line]} {error {Paused resize detached physical source arrow}}
   capture $w ${lower}_paused_$size
  }
  ::GX::sourceSurfaceConfigure $w.p.center.edit {theme {High Contrast Dark}}
  settle 350;capture $w ${lower}_paused_high_contrast
  ::GX::sourceSurfaceConfigure $w.p.center.edit {theme {Readable Light}}
  key $t ctrl+End
  exec xdotool type --clearmodifiers -- x
  update;settle 300
  if {[$p.controls.into instate !disabled] || [$p.controls.continue instate !disabled]} {error {Dirty paused source allows stepping a mismatched revision}}
  if {$::GX::SourceSurface::state($w.p.center.edit,line)!=0} {error {Dirty paused buffer retained an untruthful arrow}}
  capture $w ${lower}_paused_dirty_guard
  key $t ctrl+z;settle 400
  if {[::GX::sourceSurfaceGet $w.p.center.edit] ne $before || ![$p.controls.continue instate !disabled]} {error {Exact Undo did not restore paused source readiness}}
  # Deliberate client-observation failure, followed by the genuine next poll.
  ::GX::scriptDebugPolled $p {ok 0 error {Injected missing observation: native transport receipt unavailable}}
  capture $w ${lower}_missing_callback_feedback
  settle 900
  if {$::GX::ScriptDebug::state($p,phase) ne {PAUSED}} {error {Missing-client callback failed to recover the native Job}}
  if {$supportsPause} {
   click $p.controls.continue
   waitFor {$::GX::ScriptDebug::state($p,phase) eq {RUNNING}}
   capture $w ${lower}_resumed_after_pause
  }
  click $p.controls.stop
  waitFor {$::GX::ScriptDebug::state($p,phase) in {CANCELLED COMPLETED FAILED INTERRUPTED}}
  record ${lower}_pause_terminal [::GX::scriptJobDescribe $::GX::ScriptDebug::state($p,job)]
  click $p.footer.close
  after 120 [list ::GX::scriptDebugPolled $p {ok 0 error {Injected late callback after assistant Destroy}}]
  settle 400
  if {[$w.p panes] ne [list $w.p.left $w.p.center $w.p.right]} {error {Late callback/Destroy lost editor panes}}
  capture $w ${lower}_late_callback_destroy_restored
  record ${lower}_edge_cycle [dict create pause_job [dict get $paused job_id] source_sha256 [dict get $paused source_sha256] native_paused_line [dict get $paused line] exact_source [expr {[::GX::sourceSurfaceGet $w.p.center.edit] eq $before}] source_unchanged_by_view 1]
 } on error {message options} {
  lappend ::edgeFailures $lang
  record ${lower}_edge_error [dict get $options -errorinfo]
 } finally {
  if {[info exists ::GX::ScriptDebug::state($p,job)] && $::GX::ScriptDebug::state($p,job) ne {}} {
   catch {::GX::scriptJobCancel $::GX::ScriptDebug::state($p,job)}
   catch {::GX::scriptJobWait $::GX::ScriptDebug::state($p,job) 30}
   catch {destroy $p}
  }
 }
}
if {[llength $::edgeFailures]} {error "Native edge walkthrough failed: $::edgeFailures"}
record edge_review_finished 1
