lassign $argv root
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc check {e m} {if {![uplevel 1 [list expr $e]]} {error "FAIL: $m"};puts "PASS: $m"}
set registry [array get ::GX::moduleCatalog]
set enabled [::GX::moduleCardsEnabledSnapshot]
set hidden $::GX::cfg(analysis_hidden_modules)
foreach id {viewer.html acq.generic_csv export.session_html core.scientific_execution} {
    ::GX::moduleSetAnalysisShown $id 0
    check {![::GX::moduleAnalysisEligible $id] && ![::GX::moduleAnalysisIsShown $id]} "ineligible $id cannot enter Analysis selection"
}
check {$hidden eq $::GX::cfg(analysis_hidden_modules)} {ineligible changes do not mutate canonical visibility}
set id analysis.statistics.descriptive
check {![::GX::moduleIsEnabled $id]} {disabled Analysis fixture}
::GX::moduleSetAnalysisShown $id 0
check {[::GX::moduleAnalysisIsShown $id]} {disabled Analysis visibility cannot be changed by Modules}
::GX::moduleSetEnabled $id 1
set caps [::GX::moduleAnalysisCapabilities $id]
::GX::moduleSetAnalysisShown $id 0
check {$caps eq [::GX::moduleAnalysisCapabilities $id] && [dict get $caps available]} {hidden module targeted API capability unchanged}
check {[array get ::GX::moduleCatalog] eq $registry} {descriptors and API registry unchanged}
check {![::GX::moduleRunIsAdmitted $id] && [::GX::moduleRunIsSelected $id]} {hidden module does not erase legitimate Run preference}
check {[llength [::GX::selectedRunModuleIds 1]]==0} {Run-now presentation excludes hidden preferences}
puts {PASS: focused negative checks complete}
