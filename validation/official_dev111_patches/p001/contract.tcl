# Focused real source contract, isolated output/profile supplied by wrapper.
lassign $argv framework output
file mkdir $output
source [file join $framework gxtxt_pipeline.tcl]
proc check {expression label} {
    if {![uplevel 1 [list expr $expression]]} {error "FAIL: $label"}
    puts "PASS: $label"
}
::GX::defaults
::GX::loadModuleCatalog
check {$::GX::version eq {0.9.8.10-dev-111}} version
::GX::configurationSet storage.session_root [file join $output sessions]
::GX::configurationSave {storage.session_root}
set a [::GX::createNewSession p001_a {} 0]
set oct analysis.octave_script
set py analysis.python_script
::GX::moduleSetEnabled $oct 1
::GX::moduleSetEnabled $py 1
::GX::moduleSetRunSelected $oct 0
::GX::moduleSetRunSelected $py 0
set enabled [::GX::moduleCardsEnabledSnapshot]
check {[::GX::moduleIsEnabled $oct] && [::GX::moduleIsEnabled $py]} {Octave/Python enabled through existing Configuration owner}
check {[::GX::moduleAnalysisIsShown $oct] && ![::GX::moduleRunIsSelected $oct]} {legacy-compatible default visibility independent of Run}
::GX::moduleSetAnalysisShown $oct 0
check {![::GX::moduleAnalysisIsShown $oct] && ![::GX::moduleRunIsSelected $oct]} {hiding does not set Run}
::GX::moduleSetRunSelected $oct 1
::GX::moduleSetRunSelected $py 1
::GX::moduleSetAnalysisShown $py 1
check {![::GX::moduleRunIsAdmitted $oct] && [::GX::moduleRunIsAdmitted $py]} {hidden true Run excluded; shown selected admitted}
check {$oct in [::GX::selectedRunModuleIds]} {hidden Run preference retained for persistence}
::GX::sessionPersistenceCommit
set manifest [file join $a metadata manifest.ini]
set d [::GX::parseIni $manifest]
check {$oct in [::GX::splitList [dict get $d module_state.run]] && $oct in [::GX::splitList [dict get $d module_state.analysis_hidden]]} {independent persisted visibility and execution}
set b [::GX::createNewSession p001_b {} 0]
check {[::GX::moduleAnalysisIsShown $oct]} {new Session resets visibility}
::GX::openSessionPath $a
check {![::GX::moduleAnalysisIsShown $oct] && [::GX::moduleRunIsSelected $oct]} {Session A visibility and Run restored}
::GX::openSessionPath $b
check {[::GX::moduleAnalysisIsShown $oct]} {Session B does not inherit A}
::GX::openSessionPath $a
check {![::GX::moduleAnalysisIsShown $oct]} {A-B-A lifecycle}
set bare [file join $output channels_only]
file mkdir [file join $bare channels]
::GX::openSessionPath $bare
check {[::GX::moduleAnalysisIsShown $oct]} {channels-only Session does not inherit visibility}
::GX::openSessionPath $a
::GX::moduleSetAnalysisShown $oct 1
check {[::GX::moduleRunIsSelected $oct]} {show restores original Run preference}
::GX::moduleSetAnalysisShown $oct 0
check {[::GX::moduleCardsEnabledSnapshot] eq $enabled} {Configuration enablement unchanged}

# Legacy manifests lack new key; use a copy of our own synthetic Session config.
set f [open $manifest];set text [read $f];close $f
regsub -line {^analysis_hidden=.*\n} $text {} text
set legacy [file join $output legacy.ini];set f [open $legacy w];puts -nonewline $f $text;close $f
::GX::loadManifest $legacy
check {[::GX::moduleAnalysisIsShown $oct]} {old manifest defaults all visible}
::GX::moduleSetAnalysisShown $py 0
::GX::loadManifest $legacy
check {[::GX::moduleAnalysisIsShown $py]} {repeated old configuration load clears stale visibility}
puts {PASS: focused persistence contract complete}
