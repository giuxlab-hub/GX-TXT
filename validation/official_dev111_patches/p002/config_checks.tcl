lassign $argv root output
if {[file exists $output]} {error {Output must be new}}
file mkdir $output
set log [open [file join $output observations.txt] w];fconfigure $log -buffering line
proc record {value} {puts $::log $value;puts $value}
proc check {expression label} {
    if {![uplevel 1 [list expr $expression]]} {error "FAIL: $label"}
    record "PASS: $label"
}
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
package require Tk
proc bgerror {message} {puts stderr "BGERROR: $message\n$::errorInfo";exit 2}
wm geometry . 1180x760+0+0
foreach f {.top .top.nb .top.nb.configuration .top.nb.configuration.sections .top.nb.configuration.sections.modules} {ttk::frame $f;pack $f -fill both -expand 1}
set base .top.nb.configuration.sections.modules
::GX::configurationModulesBuild $base 0
update
set tabs [$base.kinds tabs]
check {$tabs eq [list $base.kinds.services $base.kinds.exports $base.kinds.viewers $base.kinds.acquisition $base.kinds.preview]} {existing tab order preserved; new categories appended}
check {[$base.kinds index $base.kinds.exports]==1 && [$base.kinds tab $base.kinds.exports -text] eq {Export}} {Export exact position and label preserved}
check {[$base.kinds index $base.kinds.viewers]==2} {Viewers exact position preserved}
check {[$base.kinds tab $base.kinds.services -text] eq {Analysis & Services}} {Analysis and Services label excludes Acquisition}
check {[$base.kinds tab $base.kinds.acquisition -text] eq {Acquisition}} {Acquisition has dedicated tab}
check {[$base.kinds tab $base.kinds.preview -text] eq {Preview Components}} {Preview Components has dedicated tab}
check {[dict size $::GX::ConfigurationModules::acquisitionRecords]>0} {Acquisition browser lists real installed importers}
check {[dict size $::GX::ConfigurationModules::exportRecords]>0} {Export browser retains real installed exporters}
dict for {iid record} $::GX::ConfigurationModules::acquisitionRecords {
    check {[::GX::moduleField [dict get $record id] kind] eq {acquisition}} "Acquisition row owns importer [dict get $record id]"
}
dict for {iid record} $::GX::ConfigurationModules::records {
    set kind [expr {[dict get $record type] eq {module} ? [::GX::moduleField [dict get $record id] kind] : {}}]
    check {$kind ni {acquisition viewer export preview}} "Services retains only its category [dict get $record id]"
}
dict for {iid record} $::GX::ConfigurationModules::exportRecords {
    check {[::GX::moduleField [dict get $record id] kind] eq {export}} "Export filter unchanged [dict get $record id]"
}
set exportBefore $::GX::ConfigurationModules::exportRecords
set exportSelectedBefore $::GX::ConfigurationModules::exportSelected
set servicesBefore $::GX::ConfigurationModules::records
set ::GX::ConfigurationModules::acquisitionQuery acq.generic_csv
::GX::configurationModulesRefresh acquisition
update
check {[dict size $::GX::ConfigurationModules::acquisitionRecords]==1 && $::GX::ConfigurationModules::acquisitionSelected eq {module:acq.generic_csv}} {Acquisition independent search and selection}
check {$::GX::ConfigurationModules::exportRecords eq $exportBefore && $::GX::ConfigurationModules::exportSelected eq $exportSelectedBefore} {Acquisition search does not mutate Export state}
check {$::GX::ConfigurationModules::records eq $servicesBefore} {Acquisition search does not mutate Services state}
set aq $base.kinds.acquisition.browser
check {[$aq.search.query cget -textvariable] eq {::GX::ConfigurationModules::acquisitionQuery}} {Acquisition search has separate presentation draft}
foreach category {services exports acquisition} {
    set browser $base.kinds.$category.browser
    check {[$browser.actions.manage cget -command] eq {::GX::pluginManagerDialog}} "existing Plugin Manager action retained for $category"
    check {[$browser.actions.docs cget -command] eq [list ::GX::configurationModulesDocumentation $category]} "existing Documentation action retained for $category"
}
set editor $aq.split.detail.viewport.content.editor
check {[winfo exists $editor] && [dict get $::GX::ConfigurationEditor::contexts $editor module] eq {acq.generic_csv}} {Acquisition uses existing typed Configuration editor}
# Existing importer schemas are Session-scoped; don't invent user fields or
# upgrade their allowed scopes merely to test central Save.
check {[::GX::configurationModulesPending] eq {}} {central user Save has no fabricated Acquisition edits}
check {[string first {services exports acquisition} [info body ::GX::configurationModulesPending]]>=0 && [string first {services exports acquisition} [info body ::GX::configurationModulesSaved]]>=0} {existing central draft owners include Acquisition without changing scope rules}
set preview [::GX::configurationPreviewComponentsBuild $base.kinds.preview]
check {[winfo exists $preview.actions.manage] && [$preview.actions.manage cget -command] eq {::GX::pluginManagerDialog}} {existing Preview management factory and Plugin Manager entry point wired}
set viewsBefore [dict keys $::GX::ConfigurationPreviewComponents::views]
::GX::configurationModulesReload
check {[dict keys $::GX::ConfigurationPreviewComponents::views] eq $viewsBefore && [dict get [::GX::configurationPreviewComponentsRefresh $base.kinds.preview] refreshed]==1} {reload refreshes existing Preview tab without duplicate UI}
$base.kinds select $base.kinds.acquisition
update
exec import -window root [file join $output configuration-acquisition.png]
$base.kinds select $base.kinds.preview
update
exec import -window root [file join $output configuration-preview.png]
record {PASS: Configuration-only focused checks complete}
close $log
destroy .
exit 0
