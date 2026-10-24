# SPDX-License-Identifier: GPL-3.0-or-later
# Focused public CORE auxiliary presentation contract; no Viewer source changes.
if {[llength $argv]!=2} {error {usage: auxiliary.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_AUXILIARY_CONTRACT__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk;wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_PUBLIC_AUXILIARY
namespace eval ::TA {variable checks {};variable trace {};variable errors {};variable background {};variable commits 0;variable auxCaptures 0;variable auxRestores 0;variable canonical [dict create camera {scale 1 center {0 0}} selected_ids {}];variable state [dict create value 0 retained {inert café {x} [y]}];variable aux $canonical;variable modal {}
}
proc ::TA::emit {name value} {set f [open [file join $::out $name.tcldict] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}}
proc ::TA::check {condition message} {if {![uplevel 1 [list expr $condition]]} {error "FAIL: $message"};lappend ::TA::checks $message;emit checks $::TA::checks;puts "PASS: $message";flush stdout}
proc ::TA::capture {} {return $::TA::state}
proc ::TA::guard {} {return [winfo exists .fixture]}
proc ::TA::captureAux {} {incr ::TA::auxCaptures;return $::TA::aux}
proc ::TA::restoreAux {value} {set ::TA::aux $value;incr ::TA::auxRestores;lappend ::TA::trace [list aux_restore [dict get $::TA::state value]]}
proc ::TA::restore {value} {
    set ::TA::state $value
    set mode [dict get [::GX::scientificHistoryViewerRestoreContext .fixture] mode]
    lappend ::TA::trace [list restore $mode [dict get $value value]]
    # This domain derives a camera after scientific navigation, while a browse
    # only renders scientific rows and deliberately leaves presentation alone.
    if {$mode in {undo redo branch seek clear}} {dict set ::TA::aux camera center [list [dict get $value value] $mode]}
}
proc ::TA::commit {record} {incr ::TA::commits;::GX::interactiveDocumentUpdate $::document [dict create state [::GX::scientificHistoryState $record] scientific_history $record auxiliary $::TA::aux]}
proc ::TA::failure {receipt} {lappend ::TA::errors $receipt}
proc ::TA::validate {record} {return [dict exists $record base value]}
proc ::TA::attach {record {initial @canonical}} {
    if {$initial eq {@canonical}} {set initial $::TA::canonical}
    set cb [dict create capture ::TA::capture restore ::TA::restore guard ::TA::guard commit ::TA::commit error ::TA::failure auxiliary $initial capture_aux ::TA::captureAux restore_aux ::TA::restoreAux document_id $::document recovery_choice recover]
    ::GX::scientificHistoryViewerAttach .fixture fixture.auxiliary $cb $record
}
proc ::TA::append {value} {dict set ::TA::state value $value;dict set ::TA::aux camera center [list $value append];return [::GX::scientificHistoryViewerRecordOperation .fixture "Set integer to $value"]}
proc ::TA::answer {label {remaining 80}} {
    foreach w [::TA::descendants .] {
        if {[winfo class $w] in {Button TButton} && ![catch {$w cget -text} text] && [string equal -nocase [string trim $text] $label]} {lappend ::TA::modal [list $w $label];$w invoke;return}
    }
    if {$remaining<=0} {error "Actual modal button not found: $label"}
    after 25 [list ::TA::answer $label [expr {$remaining-1}]]
}
proc ::TA::descendants {w} {set all {};foreach c [winfo children $w] {lappend all $c {*}[descendants $c]};return $all}
proc bgerror {message} {lappend ::TA::background [list $message $::errorInfo]}
::GX::scientificRecipeHostRegister fixture.auxiliary [dict create capture ::TA::capture validate ::TA::validate replay ::GX::scientificHistoryState]
toplevel .fixture;wm geometry .fixture 640x320;wm title .fixture {Private CORE auxiliary contract}
label .fixture.science -textvariable ::TA::state;label .fixture.presentation -textvariable ::TA::aux -wraplength 610
pack .fixture.science .fixture.presentation -fill x -padx 12 -pady 12
after 75000 {::TA::emit WATCHDOG $::TA::trace;exit 2}
set pins {};foreach p {core/history/libgxtxt_history.so core/tcl/scientific_history_native.tcl core/tcl/scientific_recipe_history.tcl core/tcl/interactive_document_resource_api_v1.tcl} {dict set pins $p [::GX::sha256File [file join $framework $p]]};::TA::emit source_pins $pins
try {
    set d [::GX::interactiveDocumentCreate fixture.auxiliary fixture_aux gxtxt.aux.fixture.v1 1 [dict create state $::TA::state auxiliary $::TA::canonical]];set document [dict get $d id]
    set initial [::GX::scientificHistoryCreate fixture.auxiliary $::TA::state]
    ::TA::attach $initial;update
    ::TA::check {[winfo ismapped .fixture] && [::GX::scientificHistoryViewerAuxiliary .fixture] eq $::TA::canonical} {A real owning Tk window starts with canonical auxiliary state}
    set original [::GX::scientificHistoryViewerRecord .fixture];set before [::GX::scientificHistoryViewerStatus .fixture]
    set ::TA::aux [dict create camera {scale 2 center {8 9}} selected_ids {curve1 curve2}]
    set accepted [::GX::scientificHistoryViewerAuxiliary .fixture $::TA::aux]
    ::TA::check {[dict get $accepted accepted] && [dict get $accepted revision]>[dict get $before revision] && [dict get $accepted count]==0 && [dict get $accepted cursor]==0} {Auxiliary-only acceptance advances revision without scientific entries or cursor change}
    ::TA::check {[::GX::scientificHistoryViewerRecord .fixture] eq $original && $::TA::commits==0} {Auxiliary-only edits preserve exact legacy scientific record and avoid Document projection}
    set unchanged [::GX::scientificHistoryViewerAuxiliary .fixture $::TA::aux]
    ::TA::check {[dict get $unchanged revision]==[dict get $accepted revision]} {Identical auxiliary assignment is idempotent}
    set durable [::GX::scientificHistoryViewerFlush .fixture 30000 0]
    ::TA::check {[dict get $durable durable_revision]==[dict get $accepted revision] && $::TA::commits==0} {Nonprojecting flush reports auxiliary durability without a hidden Save}
    ::TA::append 1;::TA::append 2
    ::TA::check {[::GX::scientificHistoryViewerAuxiliary .fixture] eq $::TA::aux && [dict get [::GX::scientificHistoryViewerStatus .fixture] count]==2 && $::TA::auxCaptures==2} {Scientific appends synchronize presentation through CORE-owned capture hooks}
    ::GX::scientificHistoryViewerNavigate .fixture undo
    ::TA::check {[dict get $::TA::state value]==1 && [dict get [::GX::scientificHistoryViewerAuxiliary .fixture] camera center] eq {1 undo}} {Undo applies scientific state and synchronizes derived auxiliary state}
    set undone [::GX::scientificHistoryViewerStatus .fixture];set preservedAux $::TA::aux;set captures $::TA::auxCaptures
    ::TA::check {[dict get [::GX::scientificHistoryViewerStateAt .fixture 2] value]==2 && [dict get [::GX::scientificHistoryViewerOperation .fixture 2] description] eq {Set integer to 2} && [catch {::GX::scientificHistoryViewerOperation .fixture 0}]} {Future StateAt is readable and Operation uses one-based scientific row indexes}
    ::GX::scientificHistoryViewerBrowse .fixture 2 index
    ::TA::check {[dict get $::TA::state value]==2 && ![::GX::scientificHistoryViewerEditable .fixture] && [dict get [::GX::scientificHistoryViewerStatus .fixture] cursor]==1} {Numeric final-row browsing after Undo inspects the future without changing editable cursor}
    ::TA::check {$::TA::aux eq $preservedAux && [::GX::scientificHistoryViewerAuxiliary .fixture] eq $preservedAux && $::TA::auxCaptures==$captures} {Browsing leaves RAM auxiliary state and capture scheduling untouched}
    ::TA::check {[catch {::GX::scientificHistoryViewerFlush .fixture 30000 1}] && $::TA::commits==0} {Projecting Save rejects read-only browsing without Document changes}
    set drained [::GX::scientificHistoryViewerFlush .fixture 30000 0]
    ::TA::check {[dict get $drained durable_revision]==[dict get $drained accepted_revision] && $::TA::commits==0} {Browsing can drain pending journal bytes with project zero}
    set ::TA::aux [dict create camera {scale 9 center {999 999}} selected_ids transient]
    ::GX::scientificHistoryViewerBrowse .fixture 2 latest
    ::TA::check {[dict get $::TA::state value]==1 && [::GX::scientificHistoryViewerEditable .fixture] && $::TA::aux eq $preservedAux} {Explicit latest returns to the editable Undo cursor and overlays authoritative auxiliary state}
    ::GX::scientificHistoryViewerNavigate .fixture redo
    ::TA::check {[dict get $::TA::state value]==2 && [dict get [::GX::scientificHistoryViewerAuxiliary .fixture] camera center] eq {2 redo}} {Redo preserves its scientific row and synchronizes presentation}
    ::GX::scientificHistoryViewerSeek .fixture 1
    ::TA::check {[dict get $::TA::state value]==1 && [dict get [::GX::scientificHistoryViewerAuxiliary .fixture] camera center] eq {1 seek}} {Explicit scientific Seek synchronizes presentation on the owning thread}
    ::GX::scientificHistoryViewerBrowse .fixture 1 index
    after 25 {::TA::answer OK}
    ::GX::scientificHistoryViewerNavigate .fixture branch
    ::TA::check {[dict get [::GX::scientificHistoryViewerStatus .fixture] count]==1 && [dict get [::GX::scientificHistoryViewerAuxiliary .fixture] camera center] eq {1 branch} && [llength $::TA::modal]==1} {Confirmed branch removes future scientific rows and synchronizes auxiliary state}
    ::TA::append 3
    set scienceBefore [::GX::scientificHistoryViewerRecord .fixture];set auxBefore $::TA::aux
    set ::TA::aux [dict create selected_ids [string repeat x 8388609]]
    set rejected [::GX::scientificHistoryViewerAuxiliary .fixture $::TA::aux]
    ::TA::check {![dict get $rejected accepted] && [dict get $rejected scientific_state_retained] && [dict get $rejected auxiliary_failed] && $::TA::aux eq $auxBefore && [::GX::scientificHistoryViewerRecord .fixture] eq $scienceBefore && [dict get $::TA::state value]==3} {Oversized auxiliary rejection restores only presentation and retains accepted scientific state}
    set ::TA::aux [dict create camera {scale 2 center {3 4}} selected_ids [string repeat {curve17 } 12000]]
    set largeAux $::TA::aux;set large [::GX::scientificHistoryViewerAuxiliary .fixture $largeAux]
    ::TA::check {[dict get $large accepted] && [string bytelength $largeAux]>65536 && [::GX::scientificHistoryViewerRecord .fixture] eq $scienceBefore && ![dict exists [::GX::scientificHistoryViewerStatus .fixture] auxiliary_failed]} {A valid auxiliary selection larger than 64 KiB is accepted without scientific record mutation}
    set resource [::GX::managedResourceWrite $document [dict create format application/octet-stream purpose auxiliary_fixture] AUXILIARY_OWNED_BLOB]
    dict set ::TA::aux resource $resource
    ::GX::scientificHistoryViewerAuxiliary .fixture $::TA::aux
    set collected [::GX::interactiveDocumentResourceCollect $document]
    ::TA::check {[::GX::interactiveDocumentResourceReadChunk $resource 0 [dict get $resource size_bytes]] eq {AUXILIARY_OWNED_BLOB}} {Active auxiliary-only managed resource references survive public collection}
    set finalRecord [::GX::scientificHistoryViewerRecord .fixture];set finalAux $::TA::aux;set closing [::GX::scientificHistoryViewerStatus .fixture]
    set path [dict get $::GX::ScientificHistory::viewers .fixture path];set identity [::GX::_historyIdentity fixture.auxiliary $document]
    ::GX::scientificHistoryViewerDetach .fixture 0
    set recovered [::GX::historyNative recover $path $identity]
    ::TA::check {[dict get $recovered record] eq $finalRecord && [dict get $recovered auxiliary] eq $finalAux && [dict get $recovered durable_revision]==[dict get $closing accepted_revision] && $::TA::commits==0} {Nonprojecting Close drains accepted scientific and auxiliary revisions for explicit verified recovery}
    set ::TA::state [dict get $initial base];set ::TA::aux [dict create camera {scale 99 center resized} selected_ids live_resize]
    ::TA::attach $initial $::TA::canonical
    ::TA::check {[dict get $::TA::state value]==3 && $::TA::aux eq $finalAux && [::GX::scientificHistoryViewerRecord .fixture] eq $finalRecord} {Journal recovery compares canonical initial auxiliary and overlays recovered presentation onto fresh live geometry}
    ::GX::scientificHistoryViewerDetach .fixture 0
    ::GX::interactiveDocumentResourceCollect $document
    ::TA::check {[::GX::interactiveDocumentResourceReadChunk $resource 0 [dict get $resource size_bytes]] eq {AUXILIARY_OWNED_BLOB}} {Inactive verified auxiliary journal references also survive public collection}
    set ::TA::state [::GX::scientificHistoryState $finalRecord];set ::TA::aux $finalAux
    ::TA::attach $finalRecord $finalAux
    set captureBeforeClear $::TA::auxCaptures
    dict set ::TA::aux camera center {3 clear}
    after 25 {::TA::answer No}
    ::GX::scientificHistoryViewerClear .fixture $document
    ::TA::check {[dict get [::GX::scientificHistoryViewerStatus .fixture] count]==0 && [dict get $::TA::state value]==3 && [::GX::scientificHistoryViewerAuxiliary .fixture] eq $::TA::aux && $::TA::auxCaptures==$captureBeforeClear+1 && [dict get [::GX::scientificHistoryViewerAuxiliary .fixture] camera center] eq {3 clear} && $::TA::commits==1 && [llength $::TA::modal]==2} {Confirmed Clear preserves scientific current state and synchronizes auxiliary state before explicit projection}
    ::GX::scientificHistoryViewerDetach .fixture 0;destroy .fixture;update
    ::TA::check {$::TA::background eq {}} {Owning-thread hook and modal lifecycle finishes without Tcl/Tk background failures}
    ::TA::emit receipt [dict create status PASS_PUBLIC_AUXILIARY framework $framework checks $::TA::checks pins $pins commits $::TA::commits auxiliary_captures $::TA::auxCaptures auxiliary_restores $::TA::auxRestores rejected $rejected pending_before_close [dict get $closing pending] accepted_before_close [dict get $closing accepted_revision] durable_after_close [dict get $recovered durable_revision] modal_buttons $::TA::modal trace $::TA::trace]
    puts {PASS PUBLIC CORE AUXILIARY}
} on error {message options} {::TA::emit FIRST_FAILURE [dict create message $message options $options checks $::TA::checks state $::TA::state auxiliary $::TA::aux trace $::TA::trace errors $::TA::errors background $::TA::background];puts stderr [dict get $options -errorinfo];exit 1}
exit 0
