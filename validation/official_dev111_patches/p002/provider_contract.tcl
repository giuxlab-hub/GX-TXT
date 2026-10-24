# Focused standard Module/Plugin Manager Preview presentation integration.
lassign $argv root normalizer output
if {[llength $argv]!=3 || [file exists $output]} {error {Usage FRAMEWORK NORMALIZER_TCL NEW_OUTPUT}}
file mkdir $output
foreach {key suffix} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR temp} {
    set ::env($key) [file normalize [file join $output $suffix]];file mkdir $::env($key);file attributes $::env($key) -permissions 0700
}
set argv0 __p002_provider_contract__
source [file join $root gxtxt_pipeline.tcl]
source [file join $root core tcl dataset_preview_provider_v1.tcl]
source $normalizer
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $output Sessions]
set session [::GX::createNewSession provider_contract]
# A private catalog with new real package targets. Baseline CORE reads are
# shared read-only; Plugin Manager alone installs/updates/removes targets.
set catalog [file join $output catalog];file mkdir [file join $catalog plugins modules]
foreach path [glob -directory [file join $root plugins] *] {
    if {[file tail $path] ne {modules}} {file link -symbolic [file join $catalog plugins [file tail $path]] $path}
}
foreach name {core app docs} {file link -symbolic [file join $catalog $name] [file join $root $name]}
set ::GX::scriptDir $catalog
file mkdir [file join $session datasets]
set payload [file join $session datasets values.csv]
set fd [open $payload w];puts $fd "x,y\n1,2\n2,4";close $fd
set fields [list kind curve_family.table contract curve_family.table format csv storage_provider csv path datasets/values.csv canonical_delimiter comma canonical_sha256 [::GX::sha256File $payload] var_count 2 row_count 2 variable_schema_api_version 3]
set n 0
foreach id {x y} {incr n;lappend fields var${n}_variable_id $id var${n}_enabled 1 var${n}_canonical $id var${n}_unit V var${n}_value_kind number var${n}_dtype float64 var${n}_rank 1 var${n}_shape 2 var${n}_dimension_ids row var${n}_canonical_position $n}
set ::env(GXTXT_PREVIEW_WORKER) 1
::GX::datasetRegister curves $fields;::GX::saveDatasetRegistry $session
unset ::env(GXTXT_PREVIEW_WORKER)
::GX::datasetMetadataUpdate $session curves [dict create source.provenance {Synthetic Curve Digitizer calibration} calibration.unit V]
source [file join [file dirname [info script]] provider_fixtures.tcl]

set checks 0
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL: $label"};incr ::checks;puts "PASS: $label"}
proc tabs {} {return [::GX::datasetPreviewProviderTabs curves [dict create kind native2d current 1 row_count 2]]}
set one {if {![dict get $context availability source] || ![dict exists $context metadata source.provenance]} {return {tabs {}}}
    set owner [dict get [::GX::datasetPrivateMetadataContext] module_id]
    return [dict create tabs [list [dict create id provenance label {Calibration provenance} kind metadata metadata [dict create provenance [dict get $context metadata source.provenance] owner $owner]] [dict create id values label {Integrated source rows} kind table variable_ids {x y} count 2]]]
}
set two {if {![dict exists $context metadata calibration.unit]} {return {tabs {}}}
    return [dict create tabs [list [dict create id provenance label {Acquisition metadata} kind metadata metadata [dict create calibration_unit [dict get $context metadata calibration.unit]]] [dict create id absent label {Absent diagnostics} kind metadata metadata {}]]]
}
::GX::pluginInstallPackage [::P002ProviderFixture::package $output preview.p002_one table.generic $one] install
::GX::pluginInstallPackage [::P002ProviderFixture::package $output preview.p002_two curve_family.table $two] install
::GX::pluginInstallPackage [::P002ProviderFixture::package $output preview.p002_other spectrum.nmr {error {Mismatched provider must never be activated}}] install
::GX::pluginInstallPackage [::P002ProviderFixture::package $output preview.p002_remove table.generic {return {tabs {}}}] install
::GX::pluginInstallPackage [::P002ProviderFixture::package $output preview.p002_bad table.generic {return [dict create tabs [list [dict create id bad label {Broken content} kind imaginary]]]}] install
check {[::GX::pluginRegistryIsManaged preview.p002_one]} {normal Plugin Manager registered Preview package}
check {![::GX::moduleAnalysisEligible preview.p002_one]} {Preview component is not an Analysis module}
check {[dict get [::GX::datasetPreviewProviderInfo preview.p002_one] profile] eq {presentation}} {ordinary descriptor selects presentation profile}
check {![dict get [::GX::datasetPreviewProviderInfo preview.p002_one] enabled]} {new Preview module defaults off}
::GX::pluginUninstall module preview.p002_remove
check {[::GX::moduleField preview.p002_remove descriptor {}] eq {}} {normal Plugin Manager removes unloaded component}
foreach id {preview.p002_one preview.p002_two preview.p002_other} {::GX::moduleSetEnabled $id 1}
set sourceBefore [::GX::datasetViewerScientificIdentity curves]
set canonicalBefore [::GX::sha256File $payload]
set registryBefore [::GX::sha256File [file join $session metadata datasets.ini]]
set metadataBefore [::GX::datasetMetadataRead $session curves]
set info [::GX::datasetPreviewProviderInfo preview.p002_one]
check {[dict get $info available] && [dict get $info verified_capabilities] eq {} && [dict get $info admission_fingerprint] eq {}} {presentation availability does not counterfeit native admission}
check {[dict get $info active_version] eq {}} {inspection does not claim callback loaded}
set beforeActivation [::GX::datasetPreviewProviderIdentity curves]
set found [tabs]
check {[llength [dict get $found tabs]]==3 && [dict get $found diagnostics] eq {}} {two compatible providers contribute together; empty content omitted}
check {$beforeActivation eq [::GX::datasetPreviewProviderIdentity curves]} {cache identity remains stable across lazy callback activation}
check {![info exists ::GX::modulePublicApiActivated(preview.p002_other,PREVIEW_COMPONENT_GUI_API_v1)]} {registered contract mismatch never activates provider}
set first [lindex [dict get $found tabs] 0]
check {[dict get $first label] eq {Calibration provenance} && [dict get $first descriptor metadata owner] eq {preview.p002_one}} {provider controls label/content and keeps ordinary module ownership}
set table [lindex [dict get $found tabs] 1]
check {[dict get $table dataset_id] eq {curves} && [dict get $table variable_ids] eq {x y}} {table requests reuse current canonical Dataset and variables}
check {[dict get [lindex [dict get $found tabs] 2] component_id] eq {preview.p002_two}} {same per-provider tab ID remains component scoped}
check {[dict get [::GX::datasetPreviewProviderInfo preview.p002_one] active_version] eq {1.0.0}} {real public API activation records loaded implementation}
check {$sourceBefore eq [::GX::datasetViewerScientificIdentity curves] && $canonicalBefore eq [::GX::sha256File $payload] && $metadataBefore eq [::GX::datasetMetadataRead $session curves]} {Preview leaves canonical content/schema/contract/scientific metadata unchanged}
set id1 [::GX::datasetPreviewProviderIdentity curves]
::GX::moduleSetEnabled preview.p002_one 0
check {[llength [dict get [tabs] tabs]]==1} {disabling one contribution retains the other}
check {$id1 ne [::GX::datasetPreviewProviderIdentity curves]} {existing cache binding reflects Module activation}
::GX::moduleSetEnabled preview.p002_two 0
check {[dict get [tabs] tabs] eq {}} {no compatible enabled contribution preserves generic fallback}
::GX::moduleSetEnabled preview.p002_one 1
file rename $payload ${payload}.held
set missing [tabs]
check {[dict get $missing tabs] eq {}} {missing actual payload suppresses unavailable content}
file rename ${payload}.held $payload
::GX::datasetMetadataUnset $session curves {source.provenance}
check {[dict get [tabs] tabs] eq {}} {structured metadata absence controls tab availability}
::GX::datasetMetadataUpdate $session curves [dict create source.provenance {Synthetic Curve Digitizer calibration}]
::GX::moduleSetEnabled preview.p002_bad 1
set result [tabs]
check {[llength [dict get $result tabs]]==2 && [llength [dict get $result diagnostics]]==1} {bad provider does not replace standard Preview or suppress good component}
check {[catch {::GX::pluginUninstall module preview.p002_one} reason] && [string match {*active*} $reason]} {normal Plugin Manager preserves loaded/active implementation refusal}
puts "PASS: $checks focused standard-module Preview checks complete"
