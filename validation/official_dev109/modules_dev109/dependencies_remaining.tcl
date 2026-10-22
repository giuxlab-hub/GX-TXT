# Resume only the unexecuted disable Cancel/Accept cases after preserved native
# timer-too-early failure. Initial snapshot is the unchanged prepared fixture.
if {$::env(DISPLAY) ne {:126} || ![::GX::moduleIsEnabled gxtxt.ir_waveform] || ![::GX::moduleIsEnabled gxtxt.ir_identify] || ![llength [glob -nocomplain [file join $::out spool_error_*]]]} {error {Wrong preserved continuation state}}
set provider gxtxt.ir_waveform;set consumer gxtxt.ir_identify
set fd [open [file join $::out dependency_initial.tcldict] r]
try {set initial [string trim [read $fd]]} finally {close $fd}
proc dependencyDialog {choice name {remaining 100}} {
    set modal .__tk__messagebox
    if {![winfo exists $modal] || ![winfo ismapped $modal]} {
        if {$remaining>0} {after 50 [list dependencyDialog $choice $name [expr {$remaining-1}]];return}
        set ::dialogFailure {Expected mapped dependency confirmation};return
    }
    record ${name}_dialog [dict create title [wm title $modal] widgets [widgets $modal] states [::GX::moduleCardsEnabledSnapshot]]
    capture $modal ${name}_dialog
    exec xdotool windowfocus --sync [winfo id $modal]
    exec xdotool key --clearmodifiers [expr {$choice eq {cancel}?{Escape}:{alt+o}}]
    set ::dialogObserved 1
}
foreach {id choice expected name} [list $provider cancel 1 disable_cancel $provider ok 0 disable_accept] {
    set row [winfo parent [dict get $::GX::ui(moduleStateWidgets) $id]]
    moduleSee $row.toggle
    set ::dialogObserved 0;set ::dialogFailure {}
    after 300 [list dependencyDialog $choice $name]
    click $row.toggle
    modulePause 250
    if {$::dialogFailure ne {} || !$::dialogObserved} {error "Confirmation not observed: $::dialogFailure"}
    record $name [dict create flags [::GX::moduleCardsEnabledSnapshot] provider [::GX::moduleOperationalInfo $provider] consumer [::GX::moduleOperationalInfo $consumer] feedback $::GX::ui(moduleFeedback) switch_provider $::GX::ui(moduleQuick,$provider) switch_consumer $::GX::ui(moduleQuick,$consumer)]
    capture . $name
    if {[::GX::moduleIsEnabled $provider]!=$expected || [::GX::moduleIsEnabled $consumer]!=$expected} {error {Dependency activation/cancel mismatch}}
    if {$choice eq {cancel} && ![string match {Cancelled.*} $::GX::ui(moduleFeedback)]} {error {Cancellation not explained}}
    if {$choice eq {ok} && ![string match {*Related changes:*} $::GX::ui(moduleFeedback)]} {error {Dependency changes not explained}}
}
set final [::GX::moduleCardsEnabledSnapshot]
record dependency_restoration [dict create initial $initial final $final]
if {$initial ne $final} {error {Canonical flags differ from original prepared fixture}}
return {Native dependency accept/cancel and full canonical flag restoration passed}
