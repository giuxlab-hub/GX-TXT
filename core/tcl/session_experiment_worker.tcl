# SPDX-License-Identifier: GPL-3.0-or-later
# Private isolated worker for sessionExperimentClone. No source Session writes.
set ::experimentCloneArguments $argv
set argv0 __experiment_clone__;source [file join [lindex $::experimentCloneArguments 0] gxtxt_pipeline.tcl]
lassign $::experimentCloneArguments framework source target snapshot eid name
::GX::defaults;::GX::loadModuleCatalog
namespace eval ::GX::ExperimentClone {variable omitted {};variable paths {};variable ids {};variable source {};variable target {};variable diagnostics {};variable allowedFiles {};variable resources {}}
source [file join $framework core tcl session_experiment_ownership.tcl]
proc ::GX::ExperimentClone::iniWrite {path data} {
    file mkdir [file dirname $path];set ch [open $path w];fconfigure $ch -encoding utf-8 -translation lf
    try {
        set last {}
        dict for {full value} $data {
            if {![regexp {^(.+)\.([^.]+)$} $full -> section key]} {error "Invalid INI key: $full"}
            if {$section ne $last} {puts $ch "\n\[$section\]";set last $section}
            ::GX::putKV $ch $key $value
        }
    } finally {close $ch}
}
proc ::GX::ExperimentClone::cleanValue {value} {
    variable source;variable paths;variable ids
    if {$value in $ids || [string first "$source/" $value]>=0} {return {}}
    foreach path $paths {if {$value eq $path} {return {}}}
    return $value
}
proc ::GX::ExperimentClone::cleanIni {data} {
    # Positive CORE authorities replace a growing blacklist of plugin fields.
    # Free author notes/instrument text are never substring-rewritten.
    set out {}
    dict for {full value} $data {
        if {[regexp {^(pipeline|runtime|session|experiment|instrument_modules|instrument_module_instance\.[0-9]+|instrument_library_link\.[0-9]+|source_variables|source_variable\.[0-9]+|core_parameters|project_link|graphics|graphics_3d|print)\.} $full]} {
            if {[regexp {^(runtime|print)\.} $full]} {set value [cleanValue $value]}
            dict set out $full $value
        }
    }
    if {[dict exists $out core_parameters.state]} {
        set state [dict get $out core_parameters.state]
        set independent [::GX::datasetPublicationV2DictDefault $state session {}]
        dict set out core_parameters.state [dict create session $independent]
        foreach scope [dict keys $state module.*] {report reset [string range $scope 7 end] parameters $scope {unverifiable module-scoped parameter overrides}}
    }
    foreach key {module_id session_root session_name} {dict set out acquisition.$key [::GX::datasetPublicationV2DictDefault $data acquisition.$key {}]}
    set acquisition [dict get $out acquisition.module_id]
    if {$acquisition ni $::GX::moduleOrder} {dict set out acquisition.module_id $::GX::cfg(acquisition_module);report reset $acquisition descriptor acquisition {uninstalled acquisition; use normal importer}}
    dict set out acquisition.input_csv {}
    dict set out module_state.enabled {};dict set out module_state.run {}
    foreach module $::GX::moduleOrder {
        set policy [::GX::experimentDuplicationPolicyModule $module]
        report reset $module {} configuration "[dict get $policy status]: [dict get $policy errors]; defaults, empty Run selection; configure fresh inputs"
        foreach key [::GX::moduleConfigKeys $module] {
            set value [::GX::moduleConfigField $module $key default {}]
            # Dataset/path defaults may themselves be legacy selectors. Start
            # these empty; descriptor UI can rebind them after fresh acquisition.
            if {[regexp -nocase {(dataset|workspace|selection|graph)} $key] || [string tolower [::GX::moduleConfigField $module $key type {}]] in {dataset variable selection temporal_set table model analysis_definition file path}} {set value {}}
            set field module_config.$module.$key
            if {[dict get $policy valid] && [dict exists $policy configs $key] && [dict exists $data $field]} {
                set proposed [dict get $data $field];set action [dict get $policy configs $key]
                if {![catch {
                    dependencies $proposed [dict create id configuration module_id $module provider_id descriptor format config] 0
                    if {$action eq "COPY_PREPARATION" && [::GX::moduleConfigField $module $key type {}] in {file path}} {
                        set path [file normalize [file join $::GX::ExperimentClone::source $proposed]]
                        if {$path ni $::GX::ExperimentClone::allowedFiles} {error unproved_preparation_path}
                    }
                    if {$action eq "PRESERVE_VALID_EXTERNAL_REFERENCE" && (![file isfile $proposed] || [file pathtype $proposed] ne "absolute" || [file type $proposed] eq "link")} {error invalid_external_file}
                } reason]} {
                    set value $proposed;report copied $module descriptor $key $action
                } else {report skipped $module descriptor $key $reason}
            }
            dict set out $field $value
        }
        if {[::GX::moduleSupportsAnalysisSources $module]} {
            set sources [::GX::moduleAnalysisSourceDeclaredIds $module]
            dict set out module_analysis_sources.$module.ids [join $sources {;}]
            foreach id $sources {dict set out module_analysis_source.$module.$id.dataset_id {}}
        }
        foreach role [::GX::moduleBindingRoles $module] {dict set out module_binding.$module.$role {}}
    }
    return $out
}
proc ::GX::ExperimentClone::omit {relative} {
    variable omitted;lappend omitted $relative
}
proc ::GX::ExperimentClone::copyTree {from to {rel {}}} {
    variable paths;variable allowedFiles
    file mkdir $to
    foreach path [lsort -unique [concat [glob -nocomplain -directory $from *] [glob -nocomplain -directory $from .*]]] {
        set tail [file tail $path];if {$tail in {. ..}} continue
        set relative [expr {$rel eq {} ? $tail : "$rel/$tail"}]
        # Only CORE author preparation roots or exact declared file owners
        # may transport bytes. Unknown analysis/private state is omitted whole.
        if {![string match managed/* $relative]} {
            set core [expr {$relative eq "metadata" || $relative eq "metadata/manifest.ini" || [regexp {^(notes|scripts)(/|$)} $relative]}]
            set declared 0
            foreach safe $allowedFiles {if {$path eq $safe || [string first "$path/" $safe]==0} {set declared 1;break}}
            if {!$core && !$declared} {omit $relative;continue}
        }
        # Managed registries are copied separately by their active owners. Graph
        # authorities and canonical scientific storage never become preparation.
        if {[regexp {^(metadata/(workbench_recovery(/|$)|plot.dataset(/|$)|graph_annotations(/|$)|graphs(/|$)|datasets(/|$)|dataset_selections\.ini|datasets\.ini|interactive_documents(/|$|\.ini$)|interactive_document_resources(/|$)|scientific_profiles(/|$)|dataset_profiles(/|$))|notes/(datasets|graphs)(/|$)|analysis/core.plot_clones(/|$)|cache/dataset_materializations(/|$)|datasets(/|$))} $relative]} {omit $relative;continue}
        if {[regexp {^analysis/([^/]+)/variants(/|$)} $relative -> owner] && $owner in $::GX::moduleOrder} {omit $relative;continue}
        if {[regexp {^notes/workspaces/(idoc_[0-9]+)\.md$} $relative -> owner] && $owner in $::GX::ExperimentClone::removedDocuments} {omit $relative;continue}
        if {$path in $paths} {omit $relative;continue}
        file lstat $path st
        if {$st(type) eq "directory"} {copyTree $path [file join $to $tail] $relative;continue}
        if {$st(type) eq "link"} {
            if {![file isfile $path]} {error "Cannot safely clone directory/broken link: $relative"}
            set resolved $path;set remaining 64
            while {[file type $resolved] eq "link"} {
                if {[incr remaining -1]<0} {error "Symlink cycle: $relative"}
                set resolved [file normalize [file join [file dirname $resolved] [file readlink $resolved]]]
            }
            if {$resolved in $paths} {omit $relative;continue}
        } elseif {$st(type) ne "file"} {error "Cannot clone special file: $relative"}
        set ext [string tolower [file extension $tail]]
        if {([string match managed/* $relative] && [string match .pending-* $tail]) || [string match metadata/manifest.ini.tmp.* $relative]} {omit $relative;continue}
        set dest [file join $to $tail]
        if {$st(type) eq "link"} {set fd [open $path rb];set out [open $dest wb];try {fcopy $fd $out} finally {close $fd;close $out}} else {file copy -- $path $dest}
        # Only the authoritative Manifest is rebound below. Ordinary preparation
        # files, script metadata and managed document attachments stay verbatim;
        # similarly named INI fields are not permission to truncate author data.
    }
}
proc runClone {} {
    global framework source target snapshot eid name
    set ::GX::ExperimentClone::source $source;set ::GX::ExperimentClone::target $target
    ::GX::loadDatasetRegistry $source
    set ::GX::ExperimentClone::ids [::GX::datasetRegistryIds]
    set paths {}
    foreach id [::GX::datasetRegistryIds] {
        foreach field {path raw_path raw_file source_raw source_path user_notes_file structured_metadata_file} {
            set p [::GX::datasetField $id $field {}]
            if {$p eq {}} continue
            if {[file pathtype $p] ne "absolute"} {set p [file join $source $p]}
            set p [file normalize $p];lappend paths $p
        }
    }
    set ::GX::ExperimentClone::paths [lsort -unique $paths];set ::GX::ExperimentClone::allowedFiles {}
    set manifest [dict merge [::GX::parseIni [file join $source metadata manifest.ini]] [::GX::parseIni $snapshot]]
    ::GX::ExperimentClone::ownedOutputs $manifest
    ::GX::ExperimentClone::documentsPlan
    while 1 {
        set prior [list [dict keys $::GX::ExperimentClone::documents] [lsort -unique $::GX::ExperimentClone::paths]]
        set viewers [::GX::ExperimentClone::viewersClean $manifest]
        ::GX::ExperimentClone::documentsValidate
        set ::GX::ExperimentClone::paths [lsort -unique $::GX::ExperimentClone::paths]
        if {$prior eq [list [dict keys $::GX::ExperimentClone::documents] $::GX::ExperimentClone::paths]} break
    }
    ::GX::ExperimentClone::filesPlan
    set cleaned [::GX::ExperimentClone::cleanIni $manifest]
    dict for {key value} $viewers {if {[regexp {^viewer_(scene|scenes|layer|layers|attribute|attributes)\.} $key]} {dict set cleaned $key $value}}
    set manifest [::GX::ExperimentClone::graphsReset $cleaned]
    set ::GX::ExperimentClone::diagnostics [lsort -unique $::GX::ExperimentClone::diagnostics]
    dict set manifest experiment.observations {}
    dict set manifest experiment_preparation.api_version 1
    dict set manifest experiment_preparation.definitions [dict create clone_policy duplicate_preparation dataset_count 0 workspace_count 0 document_count [dict size $::GX::ExperimentClone::documents] observations empty graphs reset policy_api EXPERIMENT_DUPLICATION_POLICY_API_v1 policy_version 1 summary $::GX::ExperimentClone::diagnostics]
    set sourceExperimentId [::GX::datasetPublicationV2DictDefault $manifest project_link.experiment_id {}]
    dict set manifest project_link.experiment_id $eid
    dict set manifest acquisition.session_name [file tail $target]
    dict set manifest acquisition.session_root [file dirname $target]
    dict set manifest origin.api_version 1
    dict set manifest origin.definition [::GX::_originCreate duplicate [dict create object_kind session_experiment experiment_id $sourceExperimentId creator_installation [dict get [::GX::sessionOriginRead $source] creator_installation] origin_snapshot [::GX::sessionOriginRead $source]]]
    dict set manifest experiment.name $name
    dict set manifest pipeline.application_version $::GX::version
    file mkdir [file dirname $target]
    set creation [::GX::_sessionCreationReserve [file dirname $target] [file tail $target]]
    set stage [dict get $creation stage]
    try {
        file mkdir $stage
        set creation [::GX::_sessionCreationClaim $creation $stage]
        ::GX::ExperimentClone::copyTree $source $stage
        ::GX::_sessionStorageProfilesPrepareClone $source $stage
        ::GX::ExperimentClone::documentsCopy $stage
        foreach d {raw metadata channels datasets analysis report logs notes/experiment} {file mkdir [file join $stage $d]}
        ::GX::ExperimentClone::iniWrite [file join $stage metadata manifest.ini] $manifest
        # Zero Datasets also means zero namespaces containing source measurements;
        # empty namespace definitions in the Manifest remain reusable organization.
        ::GX::ExperimentClone::iniWrite [file join $stage metadata datasets.ini] {registry.api_version 1 registry.session_mode native registry.count 0}
        set ::GX::currentSession $stage
        ::GX::loadManifest [file join $stage metadata manifest.ini]
        ::GX::loadDatasetRegistry $stage
        if {[llength [::GX::datasetRegistryIds]]} {error {Clone still contains Datasets}}
        # Notes are captured from the live snapshot (including unsaved source
        # edits) instead of blindly preferring possibly older Markdown files.
        foreach {key filename} [::GX::experimentNoteSpecs] {
            ::GX::noteWriteUtf8 [file join $stage notes experiment $filename] $::GX::cfg($key)
        }
        if {[llength [::GX::sessionWorkspaceList]]} {error {Clone still contains Workspaces}}
        foreach item [::GX::interactiveDocumentList] {::GX::interactiveDocumentRead [dict get $item id]}
        dict for {id receipts} $::GX::ExperimentClone::resources {foreach receipt $receipts {::GX::interactiveDocumentResourceInfo $receipt}}
        set report "Duplicate Experiment: zero Datasets/Workspaces, empty observations, graphs reset.\nSelectable modules start disabled; all Run selections are empty. Configure fresh inputs before running.\n"
        foreach entry $::GX::ExperimentClone::diagnostics {append report "[dict get $entry action] | [dict get $entry module_id]/[dict get $entry provider_id] | [dict get $entry object] | [dict get $entry reason]\n"}
        append report "Excluded unowned/scientific filesystem entries:\n[join $::GX::ExperimentClone::omitted \n]\n"
        ::GX::noteWriteUtf8 [file join $stage metadata experiment_preparation.txt] $report
        set creation [::GX::_sessionCreationPromote $creation]
    } on error {message options} {
        if {[catch {set cleanup [::GX::_sessionCreationAbort $creation]} issue]} {
            append message "\nCreation paths preserved: $stage / $target\n$issue"
        } elseif {[dict get $cleanup state] in {aborted_retained promoted_retained}} {
            append message "\nPreserved Session output: $stage / $target"
        }
        return -options $options $message
    }
}
if {[catch {runClone} message options]} {puts stderr $message;puts stderr [dict get $options -errorinfo];exit 1}
puts EXPERIMENT_PREPARATION_CLONED
