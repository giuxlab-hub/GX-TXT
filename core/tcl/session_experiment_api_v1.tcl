# SPDX-License-Identifier: GPL-3.0-or-later
# Clone preparation in an isolated interpreter. Never save/reload the source
# Session to create the clone: the live Manifest snapshot includes unsaved edits.
proc ::GX::sessionExperimentClone {name {root ""}} {
    variable currentSession;variable cfg;variable scriptDir
    set source [_sessionPortableRequireSession]
    set name [string trim $name]
    if {$name eq "" || [regexp {[\r\n]} $name]} {error {Enter a single-line Experiment name.}}
    set pid [projectCurrentId]
    if {$root eq ""} {
        if {$pid ne "" && [projectExists $pid]} {set root [projectSessionsRoot $pid]} else {set root $cfg(output_root)}
    }
    if {[string trim $root] eq ""} {error {Set a Session root before creating an Experiment.}}
    set root [file normalize $root];set target [file join $root [sanitize $name]]
    if {[_datasetDeletePathWithin $target $source]} {error {The new Experiment must be outside the source Session.}}
    if {[file exists $target]} {error "A Session already exists at: $target"}
    file mkdir $root
    set channel [file tempfile snapshot [file join $root .experiment-manifest-]]
    set eid [experimentGenerateId]
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        puts -nonewline $channel [sessionExperimentSnapshot];close $channel;set channel {}
        set cmd [list [info nameofexecutable] [file join $scriptDir core tcl session_experiment_worker.tcl] $scriptDir $source $target $snapshot $eid $name]
        # wish cannot run a headless child on every platform; tclsh is the CORE
        # host used by the existing Script Bridge and Session helpers.
        set executable [auto_execok tclsh]
        if {$executable eq {}} {error {Duplicate Experiment requires the Tcl runtime (tclsh).}}
        set cmd [lreplace $cmd 0 0 {*}$executable]
        exec {*}$cmd 2>@1
        # Registry commit is the final step. Restore its exact prior bytes and
        # in-memory membership if persistence fails after adding the new ID.
        projectEnsureRegistryLoaded
        set oldMembers [array get ::GX::projectMembership]
        set registry [projectRegistryPath];set existed [file isfile $registry]
        if {$existed} {set prior [open $registry rb];try {set bytes [read $prior]} finally {close $prior}}
        try {
            if {$pid ne "" && [projectExists $pid]} {projectAssociateExperiment $pid $eid $target $name}
        } on error {message options} {
            array unset ::GX::projectMembership *;array set ::GX::projectMembership $oldMembers
            if {$existed} {set prior [open $registry wb];try {puts -nonewline $prior $bytes} finally {close $prior}} elseif {[file exists $registry]} {file delete -- $registry}
            file delete -force -- $target
            return -options $options $message
        }
    } finally {
        if {$channel ne {}} {close $channel}
        file delete -force -- $snapshot
    }
    return [dict create session_path $target experiment_id $eid project_id $pid dataset_count 0 workspace_count 0 document_count [dict size [_interactiveDocumentRegistryRead $target]]]
}
proc ::GX::sessionExperimentSnapshot {} {
    set before {}
    try {
        # The effective editor commits on Save. A clone can capture its draft
        # without committing that draft to the source's authoritative files.
        foreach {key filename} [experimentNoteSpecs] {
            if {![llength [info commands winfo]]} break
            set tab [dict get {experiment_notes notes experiment_objective objective experiment_procedure procedure experiment_observations observations} $key]
            set parent .top.nb.exp.notes.$tab
            if {[winfo exists $parent.t] && [info exists ::GX::scientificTextState($parent,mode)] && $::GX::scientificTextState($parent,mode) eq "edit"} {
                dict set before $key $::GX::cfg($key)
                set ::GX::cfg($key) [scientificTextCurrent $parent]
            }
        }
        return [manifestString]
    } finally {dict for {key value} $before {set ::GX::cfg($key) $value}}
}
# Additive clone-policy receipt uses the existing Manifest authority. It contains
# no Workspace or viewer definitions; these are excluded experimental data.
proc ::GX::sessionExperimentPreparationRead {} {
    if {[info exists ::GX::cfg(experiment_preparation)]} {return $::GX::cfg(experiment_preparation)}
    return {}
}
rename ::GX::defaults ::GX::defaults_before_experiment077
proc ::GX::defaults {} {defaults_before_experiment077;set ::GX::cfg(experiment_preparation) {}}
rename ::GX::manifestStringV2 ::GX::manifestStringV2_before_experiment077
proc ::GX::manifestStringV2 {} {
    set out [manifestStringV2_before_experiment077]
    set preparation [sessionExperimentPreparationRead]
    if {$preparation ne {}} {append out "\n\[experiment_preparation\]\n";appendKV out api_version 1;appendKV out definitions $preparation}
    return $out
}
rename ::GX::loadManifestV2 ::GX::loadManifestV2_before_experiment077
proc ::GX::loadManifestV2 {path} {
    set data [parseIni $path]
    set preparation [datasetPublicationV2DictDefault $data experiment_preparation.definitions {}]
    if {[datasetPublicationV2DictDefault $preparation policy_api {}] eq "EXPERIMENT_DUPLICATION_POLICY_API_v1" && [datasetPublicationV2DictDefault $preparation policy_version {}] eq "1"} {
        # Legacy loaders overlay only declared config fields. Undeclared old
        # dataset aliases/private module keys must not leak on a Session switch.
        # Clear before delegation; newly saved independent settings then load
        # normally from this Session, including after subsequent fresh runs.
        foreach arrayName {moduleCfg moduleBinding moduleEnabled moduleRun moduleAnalysisSource moduleAnalysisSourceCount} {array unset ::GX::$arrayName *}
        ensureModuleConfigDefaults
        ensureModuleBindingDefaults
    }
    if {[datasetPublicationV2DictDefault $preparation graphs {}] eq "reset"} {
        # The legacy axis loader overlays records and leaves missing keys alive.
        # A duplicated Session must not inherit the previous Session's axes.
        # Clear before loading: any graphs subsequently created/saved in this
        # independent Session are then restored by the existing loader normally.
        array unset ::GX::axisOverride *
        array unset ::GX::modulePlotCfg *
        ensureModulePlotDefaults
    }
    set result [loadManifestV2_before_experiment077 $path]
    set ::GX::cfg(experiment_preparation) [datasetPublicationV2DictDefault $data experiment_preparation.definitions {}]
    return $result
}
