# GX-TXT Standard Module API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# This layer deliberately wraps the proven v0.4.8 application. Legacy scientific
# algorithms remain unchanged and are exposed as adapters; new modules are
# descriptor-driven and use declared dataset contracts and standard runners.

namespace eval ::GX {
    variable moduleApiVersion 1
    variable moduleCfg
    variable moduleEnabled
    variable moduleRun
    variable modelCatalog
    variable modelOrder {}
    variable datasetRegistry
}

# Extend v0.4.8 defaults without changing its historical settings.
proc ::GX::defaults_v052_api {} {
    variable cfg
    variable moduleCfg
    variable moduleEnabled
    variable moduleRun
    ::GX::defaults_v048
    set cfg(acquisition_module) "acq.rigol_csv"
    set cfg(session_mode) "measurement"
    array unset moduleCfg *
    array unset moduleEnabled *
    array unset moduleRun *
}

proc ::GX::descriptorValue {d section key {default ""}} {
    set k "$section.$key"
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $default
}

# Replace the old monolithic catalog loader with discovery of independent module.ini files.
proc ::GX::loadModuleCatalog_v052_api {} {
    variable moduleCatalog
    variable moduleOrder
    variable modelCatalog
    variable modelOrder
    variable scriptDir
    array unset moduleCatalog *
    array unset modelCatalog *
    set moduleOrder {}
    set modelOrder {}

    set root [file join $scriptDir plugins modules]
    set paths [lsort [glob -nocomplain -types f [file join $root * module.ini]]]
    if {[llength $paths] == 0} { error "No Standard Module API descriptors found under $root" }
    set sortable {}
    foreach path $paths {
        set d [parseIni $path]
        set api [descriptorValue $d meta api_version ""]
        if {$api ne "1"} { error "Unsupported module API version '$api' in $path" }
        set id [string trim [descriptorValue $d meta id ""]]
        if {$id eq ""} { error "Missing meta.id in $path" }
        if {[info exists moduleCatalog($id,descriptor)]} { error "Duplicate module id: $id" }
        foreach {field def} {
            kind analysis group General name "" version "" selectable 1 default_enabled 0 core 0
            enabled_key "" run_key "" runner "" order 1000 depends "" description "" config_hint "" ui_surface_id "" ui_replaced_by_core 0
        } {
            set moduleCatalog($id,$field) [descriptorValue $d meta $field $def]
        }
        set moduleCatalog($id,inputs) [descriptorValue $d inputs contracts ""]
        set moduleCatalog($id,outputs) [descriptorValue $d outputs files ""]
        set moduleCatalog($id,output_datasets) [descriptorValue $d outputs datasets ""]
        set moduleCatalog($id,graphs) [descriptorValue $d graphs ids ""]
        set moduleCatalog($id,rerender) [descriptorValue $d graphs rerender ""]
        set moduleCatalog($id,config_fields) [descriptorValue $d config fields ""]
        set moduleCatalog($id,runner_script) [descriptorValue $d runner script ""]
        set moduleCatalog($id,rerender_script) [descriptorValue $d runner rerender_script ""]
        set moduleCatalog($id,default_dataset) [descriptorValue $d inputs default_dataset ""]
        # Optional Render Cache API v1 declaration.  Legacy modules that omit
        # this section keep their historical module-owned render_cache.mat.
        set moduleCatalog($id,render_cache_api_version) [descriptorValue $d render_cache api_version ""]
        set moduleCatalog($id,render_cache_rerender) [descriptorValue $d render_cache rerender_from_cache ""]
        set moduleCatalog($id,descriptor) $path
        set moduleCatalog($id,dict) $d
        if {$moduleCatalog($id,name) eq ""} { set moduleCatalog($id,name) $id }
        set ord $moduleCatalog($id,order)
        if {![string is integer -strict $ord]} { set ord 1000 }
        lappend sortable [list $ord $id]
    }
    foreach pair [lsort -integer -index 0 $sortable] { lappend moduleOrder [lindex $pair 1] }

    set mroot [file join $scriptDir plugins models]
    set mpaths [lsort [glob -nocomplain -types f [file join $mroot * model.ini]]]
    foreach path $mpaths {
        set d [parseIni $path]
        if {[descriptorValue $d meta api_version ""] ne "1"} { error "Unsupported model API version in $path" }
        set id [string trim [descriptorValue $d meta id ""]]
        if {$id eq ""} { error "Missing model meta.id in $path" }
        if {[info exists modelCatalog($id,descriptor)]} {error "Duplicate mathematical model id: $id"}
        foreach {field def} {
            kind "" name "" version "" function "" script "" x_column "" family_column "" y_column "" y_unit "" description ""
        } {
            set modelCatalog($id,$field) [descriptorValue $d meta $field $def]
        }
        foreach field {names initial lower upper units} {
            set modelCatalog($id,param_$field) [descriptorValue $d parameters $field ""]
        }
        set modelCatalog($id,descriptor) $path
        lappend modelOrder $id
    }
    ensureModuleConfigDefaults
}

proc ::GX::moduleField {id field {default ""}} {
    variable moduleCatalog
    if {[info exists moduleCatalog($id,$field)]} { return $moduleCatalog($id,$field) }
    return $default
}

# CORE is a distribution/protection class, independent from runtime enablement.
# A CORE module may remain selectable and default_enabled=0.
proc ::GX::moduleIsCore {id} {
    set raw [string tolower [string trim [moduleField $id core 0]]]
    return [expr {$raw in {1 true yes on}}]
}

proc ::GX::moduleConfigField {id key field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return $default }
    set d $moduleCatalog($id,dict)
    return [descriptorValue $d "config.$key" $field $default]
}

proc ::GX::splitList {s} {
    set s [string map [list ";" ","] $s]
    set out {}
    foreach x [split $s ","] {
        set x [string trim $x]
        if {$x ne ""} { lappend out $x }
    }
    return $out
}

proc ::GX::moduleConfigKeys {id} {
    set raw [moduleField $id config_fields ""]
    set keys [splitList $raw]
    if {[info commands ::GX::configurationModuleFields] ne {}} {
        dict for {field descriptor} [configurationModuleFields $id] {
            set key [dict get $descriptor module_key]
            if {$key ni $keys} {lappend keys $key}
        }
    }
    return $keys
}

proc ::GX::ensureModuleConfigDefaults {} {
    variable moduleOrder
    variable moduleCfg
    variable moduleEnabled
    variable moduleRun
    foreach id $moduleOrder {
        if {![info exists moduleEnabled($id)]} {
            set moduleEnabled($id) [expr {[moduleField $id default_enabled 0] ? 1 : 0}]
        }
        if {![info exists moduleRun($id)]} { set moduleRun($id) 0 }
        configurationModuleDiscover $id
        sessionWorkspaceProviderDiscover $id
    }
}

# Activation is independent of distribution ownership. Importers are invocation
# providers, so persisted Analysis enable flags must never gate Acquisition.
proc ::GX::moduleIsAlwaysAvailable {id} {
    expr {[moduleField $id kind ""] eq "acquisition" || ![moduleField $id selectable 1]}
}
proc ::GX::moduleOperationalClass {id} {
    if {[moduleField $id kind {}] eq {}} {error "Unknown module '$id'"}
    if {[moduleIsAlwaysAvailable $id]} {return ALWAYS}
    if {[moduleField $id kind] eq "analysis"} {
        if {[moduleIsCore $id]} {return CORE_ANALYSIS}
        return ANALYSIS
    }
    return SELECTABLE_PROVIDER
}
proc ::GX::moduleAnalysisEligible {id} {
    expr {[moduleOperationalClass $id] in {CORE_ANALYSIS ANALYSIS}}
}
proc ::GX::moduleOperationalState {id} {
    switch -- [moduleOperationalClass $id] {
        ALWAYS {return ALWAYS}
        CORE_ANALYSIS {return [expr {[moduleIsEnabled $id] ? "CORE / ON" : "CORE / OFF"}]}
        default {return [expr {[moduleIsEnabled $id] ? "ON" : "OFF"}]}
    }
}
proc ::GX::moduleOperationalInfo {id} {
    return [dict create module_id $id kind [moduleField $id kind] \
        operational_class [moduleOperationalClass $id] state [moduleOperationalState $id] \
        core_protected [moduleIsCore $id] always_available [moduleIsAlwaysAvailable $id] \
        analysis_enableable [moduleAnalysisEligible $id] run_eligible [moduleAnalysisEligible $id] \
        enabled [moduleIsEnabled $id]]
}
proc ::GX::moduleIsEnabled {id} {
    variable cfg
    variable moduleEnabled
    set selectable [moduleField $id selectable 1]
    if {[moduleIsAlwaysAvailable $id]} { return 1 }
    set key [moduleField $id enabled_key ""]
    if {$key ne ""} {
        if {![info exists cfg($key)]} { return 0 }
        return [expr {$cfg($key) ? 1 : 0}]
    }
    if {[info exists moduleEnabled($id)]} { return [expr {$moduleEnabled($id) ? 1 : 0}] }
    return [expr {[moduleField $id default_enabled 0] ? 1 : 0}]
}

proc ::GX::moduleRunIsSelected {id} {
    if {![moduleAnalysisEligible $id]} {return 0}
    variable cfg
    variable moduleRun
    set key [moduleField $id run_key ""]
    if {$key ne ""} {
        return [expr {[info exists cfg($key)] && $cfg($key) ? 1 : 0}]
    }
    return [expr {[info exists moduleRun($id)] && $moduleRun($id) ? 1 : 0}]
}

proc ::GX::moduleSetRunSelected {id state} {
    variable cfg
    variable moduleRun
    set v [expr {[moduleAnalysisEligible $id]&&$state ? 1 : 0}]
    set key [moduleField $id run_key ""]
    if {$key ne ""} { set cfg($key) $v } else { set moduleRun($id) $v }
}

proc ::GX::selectedRunModuleIds {} {
    variable moduleOrder
    set out {}
    foreach id $moduleOrder {
        if {![moduleAnalysisEligible $id]} continue
        if {[moduleIsEnabled $id] && [moduleRunIsSelected $id]} { lappend out $id }
    }
    return $out
}

proc ::GX::selectedModuleIds {} {
    variable moduleOrder
    set out {}
    foreach id $moduleOrder {
        if {[moduleIsAlwaysAvailable $id]} continue
        if {[moduleIsEnabled $id]} { lappend out $id }
    }
    return $out
}

proc ::GX::moduleSetEnabled_v081_before_contract_registry {id state {cascade 1}} {
    variable cfg
    variable moduleEnabled
    variable moduleOrder
    if {[moduleIsAlwaysAvailable $id]} { return }
    set v [expr {$state ? 1 : 0}]
    set key [moduleField $id enabled_key ""]
    if {$key ne ""} { set cfg($key) $v } else { set moduleEnabled($id) $v }
    moduleSetRunSelected $id $v
    if {$v} {
        foreach dep [splitList [moduleField $id depends ""]] {
            moduleSetEnabled $dep 1 0
        }
    } elseif {$cascade} {
        foreach other $moduleOrder {
            if {[lsearch -exact [splitList [moduleField $other depends ""]] $id] >= 0 && [moduleIsEnabled $other]} {
                # The current module is already OFF, so enabled-consumer
                # traversal also terminates for cycles and shared dependants.
                moduleSetEnabled $other 0 1
            }
        }
    }
}

proc ::GX::applyModuleSelection_v078_workspace {raw} {
    variable moduleOrder
    foreach id $moduleOrder {
        if {[moduleField $id selectable 1]} { moduleSetEnabled $id 0 0 }
    }
    foreach id [splitList $raw] {
        if {[lsearch -exact $moduleOrder $id] >= 0} { moduleSetEnabled $id 1 0 }
    }
    foreach id $moduleOrder {
        # Always-available UI/service providers are not a saved scientific
        # activation. Their optional consumers must not resurrect modules that
        # the user explicitly left OFF. Selected modules still resolve their
        # declared dependencies through moduleSetEnabled above.
        if {![moduleIsAlwaysAvailable $id] && [moduleIsEnabled $id]} {
            foreach dep [splitList [moduleField $id depends ""]] { moduleSetEnabled $dep 1 0 }
        }
    }
}

# Manifest extension: v0.4.8 fields remain intact, then API-v1 state/config is appended.
proc ::GX::manifestString_v052_native {} {
    variable cfg
    variable moduleOrder
    variable moduleCfg
    variable moduleApiVersion
    set out [::GX::manifestString_v048]
    append out "\n\[module_api\]\n"
    appendKV out version $moduleApiVersion
    appendKV out descriptor_layout "plugins/modules/<module-id>/module.ini"
    append out "\n\[session\]\n"
    appendKV out mode $cfg(session_mode)
    append out "\n\[acquisition_api\]\n"
    appendKV out module_id $cfg(acquisition_module)
    append out "\n\[module_state\]\n"
    appendKV out enabled [join [selectedModuleIds] ","]
    appendKV out run [join [selectedRunModuleIds] ","]
    foreach id $moduleOrder {
        set keys [moduleConfigKeys $id]
        if {[llength $keys] == 0} continue
        append out "\n\[module_config.$id\]\n"
        foreach key $keys {
            set v [expr {[info exists moduleCfg($id,$key)] ? $moduleCfg($id,$key) : ""}]
            if {[configurationModuleShouldPersist $id $key]} {appendKV out $key $v}
        }
    }
    return $out
}

proc ::GX::loadManifest_v052_native {path} {
    variable cfg
    variable moduleOrder
    variable moduleCfg
    ::GX::loadManifest_v048 $path
    ensureModuleConfigDefaults
    set d [parseIni $path]
    if {[dict exists $d "session.mode"]} { set cfg(session_mode) [dict get $d "session.mode"] }
    if {[dict exists $d "acquisition_api.module_id"]} { set cfg(acquisition_module) [dict get $d "acquisition_api.module_id"] }
    if {[dict exists $d "module_state.enabled"]} { applyModuleSelection [dict get $d "module_state.enabled"] }
    if {[dict exists $d "module_state.run"]} {
        foreach id $moduleOrder { if {[moduleField $id kind ""] eq "analysis"} { moduleSetRunSelected $id 0 } }
        foreach id [splitList [dict get $d "module_state.run"]] {
            if {[lsearch -exact $moduleOrder $id] >= 0} { moduleSetRunSelected $id 1 }
        }
    }
    foreach id $moduleOrder {
        foreach key [moduleConfigKeys $id] {
            set dk "module_config.$id.$key"
            if {[dict exists $d $dk]} { set moduleCfg($id,$key) [dict get $d $dk] }
        }
    }
}

proc ::GX::sha256File {path} {
    if {[auto_execok sha256sum] ne ""} {
        set line [exec sha256sum -- $path]
        return [lindex $line 0]
    }
    if {[llength [info commands ::GX::runtimeToolResolve]] && [runtimeToolResolve python] ne ""} {
        set code {import hashlib,sys; h=hashlib.sha256(); f=open(sys.argv[1],'rb'); [h.update(b) for b in iter(lambda:f.read(1048576),b'')]; print(h.hexdigest())}
        return [string trim [exec [runtimeToolRequired python] -c $code $path]]
    }
    error "SHA-256 requires sha256sum or a configured Python runtime"
}

proc ::GX::datasetRegistryClear {} {
    variable datasetRegistry
    array unset datasetRegistry *
}

proc ::GX::datasetRegistryIds {} {
    variable datasetRegistry
    set ids {}
    foreach k [array names datasetRegistry "*,id"] {
        set id [string range $k 0 end-3]
        if {[lsearch -exact $ids $id] < 0} { lappend ids $id }
    }
    return [lsort $ids]
}

proc ::GX::datasetRegister {id fields} {
    variable datasetRegistry
    foreach {k v} $fields { set datasetRegistry($id,$k) $v }
    set datasetRegistry($id,id) $id
}

proc ::GX::datasetField {id field {default ""}} {
    variable datasetRegistry
    if {[info exists datasetRegistry($id,$field)]} { return $datasetRegistry($id,$field) }
    return $default
}

proc ::GX::datasetRegistryPath {session} { return [file join $session metadata datasets.ini] }

proc ::GX::saveDatasetRegistry_v085_before_dataset_inspection {session} {
    variable cfg
    set path [datasetRegistryPath $session]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Canonical Dataset API registry"
    puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
    puts $fd "\[registry\]"
    putKV $fd api_version 1
    putKV $fd session_mode $cfg(session_mode)
    set ids [datasetRegistryIds]
    putKV $fd count [llength $ids]
    foreach id $ids {
        puts $fd "\n\[dataset.$id\]"
        foreach field {id kind format path columns source_module source_raw source_sha256 canonical_sha256 created_at immutable notes user_notes_markup user_notes_format user_notes_updated_at} {
            putKV $fd $field [datasetField $id $field ""]
        }
    }
    close $fd
    return $path
}

proc ::GX::loadDatasetRegistry_v1_before_schema {session} {
    variable datasetRegistry
    datasetRegistryClear
    set path [datasetRegistryPath $session]
    if {![file isfile $path]} { return {} }
    # A flattened INI key cannot distinguish a dotted Dataset ID from a
    # dotted metadata field. Keep the section boundary while loading records.
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set sectionId ""
    set records [dict create]
    try {
        while {[gets $fd line] >= 0} {
            set line [string trim $line]
            if {$line eq "" || [string match ";*" $line] || [string match "#*" $line]} continue
            if {[regexp {^\[(.+)\]$} $line -> section]} {
                set sectionId ""
                if {[string match "dataset.*" $section]} {
                    set sectionId [string range $section [string length "dataset."] end]
                }
                continue
            }
            if {$sectionId ne "" && [regexp {^([^=]+)=(.*)$} $line -> field value]} {
                dict set records $sectionId [string trim $field] [iniUnescape $value]
            }
        }
    } finally {
        close $fd
    }
    set ids {}
    dict for {id fields} $records {
        if {![dict exists $fields id]} continue
        if {[dict get $fields id] ne $id} {
            error "Dataset registry section 'dataset.$id' has mismatched ID '[dict get $fields id]'."
        }
        dict for {field value} $fields { set datasetRegistry($id,$field) $value }
        lappend ids $id
    }
    return [lsort $ids]
}

proc ::GX::loadDatasetRegistry {session} {
    return [::GX::loadDatasetRegistry_v1_before_schema $session]
}

proc ::GX::datasetResolvePath {session id} {
    set p [datasetField $id path ""]
    if {$p eq ""} { return "" }
    if {[file pathtype $p] eq "absolute"} { return $p }
    return [file normalize [file join $session $p]]
}

proc ::GX::_datasetDeletePathWithin {path root} {
    if {$path eq "" || $root eq ""} { return 0 }
    if {[catch {set path [file normalize $path]}] || [catch {set root [file normalize $root]}]} { return 0 }
    # Tcl normalizes Windows paths with '/' even though [file separator] is '\'.
    if {[file separator] eq "\\"} {
        set path [string tolower [string map {\\ /} $path]]
        set root [string tolower [string map {\\ /} $root]]
    }
    set prefix "$root/"
    return [expr {$path ne $root && [string first $prefix $path] == 0}]
}

proc ::GX::_datasetDeleteStorageShared {session datasetId path} {
    if {[catch {set wanted [file normalize $path]}]} { return 1 }
    foreach other [datasetRegistryIds] {
        if {$other eq $datasetId} continue
        set candidate [datasetResolvePath $session $other]
        if {$candidate ne "" && ![catch {set candidate [file normalize $candidate]}] && $candidate eq $wanted} {
            return 1
        }
    }
    return 0
}

proc ::GX::_datasetDeleteNoteShared {session datasetId path} {
    if {[catch {set wanted [file normalize $path]}]} { return 1 }
    foreach other [datasetRegistryIds] {
        if {$other eq $datasetId} continue
        set rel [datasetField $other user_notes_file ""]
        if {$rel eq ""} continue
        set candidate [expr {[file pathtype $rel] eq "absolute" ? $rel : [file join $session $rel]}]
        if {![catch {set candidate [file normalize $candidate]}] && $candidate eq $wanted} { return 1 }
    }
    return 0
}

proc ::GX::_datasetDeleteMetadataShared {session datasetId path} {
    if {[catch {set wanted [file normalize $path]}]} { return 1 }
    foreach other [datasetRegistryIds] {
        if {$other eq $datasetId} continue
        set rel [datasetField $other structured_metadata_file ""]
        if {$rel eq "" && [llength [info commands ::GX::_datasetMetadataRelativePath]]} {
            set rel [_datasetMetadataRelativePath $other]
        }
        if {$rel eq ""} continue
        set candidate [expr {[file pathtype $rel] eq "absolute" ? $rel : [file join $session $rel]}]
        if {![catch {set candidate [file normalize $candidate]}] && $candidate eq $wanted} { return 1 }
    }
    return 0
}

# Canonical Dataset API v1 lifecycle operation. It removes one logical
# dataset from the current session registry and deletes only storage that CORE
# can prove is owned by that dataset inside the session datasets/ directory.
# RAW/source paths and analysis resources are deliberately outside its scope.
proc ::GX::datasetDelete_before_temporal_set_v1 {session datasetId} {
    variable datasetRegistry
    if {$session eq "" || ![file isdirectory $session]} { error "Dataset deletion requires an existing session." }
    set session [file normalize $session]
    set datasetId [string trim $datasetId]
    if {$datasetId eq ""} { error "Dataset deletion requires a Dataset ID." }
    loadDatasetRegistry $session
    if {[datasetField $datasetId id ""] eq ""} { error "Dataset '$datasetId' is not registered in this session." }

    set owned {}
    set canonical [datasetResolvePath $session $datasetId]
    if {$canonical ne "" && [file isfile $canonical] &&
        [_datasetDeletePathWithin $canonical [file join $session datasets]] &&
        ![_datasetDeleteStorageShared $session $datasetId $canonical]} {
        lappend owned [list canonical $canonical]
    }

    set noteRel [datasetField $datasetId user_notes_file ""]
    if {$noteRel eq "" && [llength [info commands ::GX::datasetNoteRelativePath]]} {
        set noteRel [datasetNoteRelativePath $datasetId]
    }
    if {$noteRel ne ""} {
        set notePath [expr {[file pathtype $noteRel] eq "absolute" ? $noteRel : [file join $session $noteRel]}]
        if {[file isfile $notePath] &&
            [_datasetDeletePathWithin $notePath [file join $session notes datasets]] &&
            ![_datasetDeleteNoteShared $session $datasetId $notePath]} {
            lappend owned [list note $notePath]
        }
    }

    set metadataRel [datasetField $datasetId structured_metadata_file ""]
    if {$metadataRel eq "" && [llength [info commands ::GX::_datasetMetadataRelativePath]]} {
        set metadataRel [_datasetMetadataRelativePath $datasetId]
    }
    if {$metadataRel ne ""} {
        set metadataPath [expr {[file pathtype $metadataRel] eq "absolute" ? $metadataRel : [file join $session $metadataRel]}]
        if {[file isfile $metadataPath] &&
            [_datasetDeletePathWithin $metadataPath [file join $session metadata datasets]] &&
            ![_datasetDeleteMetadataShared $session $datasetId $metadataPath]} {
            lappend owned [list metadata $metadataPath]
        }
    }

    set record {}
    foreach name [array names datasetRegistry] {
        if {[string first "$datasetId," $name] == 0} {
            lappend record $name $datasetRegistry($name)
        }
    }

    foreach item $owned {datasetAuthorityEnlist [lindex $item 1]}
    set staged {}
    if {[catch {
        set serial 0
        foreach item $owned {
            lassign $item kind path
            set temporary [format "%s.gxtxt-delete-%s-%s-%s" $path [pid] [clock clicks] [incr serial]]
            file rename -- $path $temporary
            lappend staged [list $kind $path $temporary]
        }
    } err options]} {
        foreach item [lreverse $staged] {
            lassign $item kind path temporary
            catch {file rename -- $temporary $path}
        }
        return -options $options $err
    }

    foreach name [array names datasetRegistry] {
        if {[string first "$datasetId," $name] == 0} { unset datasetRegistry($name) }
    }
    if {[catch {saveDatasetRegistry $session} err options]} {
        foreach {name value} $record { set datasetRegistry($name) $value }
        foreach item [lreverse $staged] {
            lassign $item kind path temporary
            catch {file rename -- $temporary $path}
        }
        catch {saveDatasetRegistry $session}
        return -options $options $err
    }

    # Graph Series may legally outlive their source dataset in persisted session
    # state. Prune those references immediately so deleting a dataset cannot
    # poison plot editors or later renders; provider sidecars reconcile lazily.
    set prunedGraphSeries {}
    if {[llength [info commands ::GX::graphSeriesPruneDatasetReferences]]} {
        catch {set prunedGraphSeries [::GX::graphSeriesPruneDatasetReferences $datasetId]}
    }
    # plot.dataset exposed a generic lifecycle gap: if deletion removes the last
    # Graph Series in one graph/variant scope, remove that declared plot artifact
    # immediately so Results does not keep showing a dead graph.
    set affectedScopes [dict create]
    foreach key $prunedGraphSeries {
        set parts [split $key ,]
        if {[llength $parts] == 3} {
            lassign $parts moduleId graphId seriesId
            set variantId ""
        } elseif {[llength $parts] == 4} {
            lassign $parts moduleId graphId variantId seriesId
        } else {
            continue
        }
        dict set affectedScopes "$moduleId,$graphId,$variantId" [list $moduleId $graphId $variantId]
    }
    dict for {scope tuple} $affectedScopes {
        lassign $tuple moduleId graphId variantId
        if {[llength [graphSeriesIds $moduleId $graphId $variantId]]} continue
        set declared [string trim [moduleGraphField $moduleId $graphId file ""]]
        if {$declared eq ""} continue
        if {$variantId eq ""} {
            set deadArtifact [file join $session analysis $moduleId $declared]
        } elseif {[llength [info commands ::GX::plotVariantExists]] && [plotVariantExists $moduleId $graphId $variantId]} {
            set deadArtifact [plotVariantArtifact $moduleId $graphId $variantId]
        } else {
            set deadArtifact ""
        }
        if {$deadArtifact ne ""} {catch {file delete -force -- $deadArtifact}}
    }

    set deleted {}
    set cleanupErrors {}
    foreach item $staged {
        lassign $item kind path temporary
        if {[catch {file delete -force -- $temporary} cleanupError]} {
            lappend cleanupErrors "$kind: $cleanupError"
        } else {
            lappend deleted $kind
        }
    }
    return [dict create dataset_id $datasetId registry_removed 1 canonical_storage_deleted [expr {[lsearch -exact $deleted canonical] >= 0}] note_deleted [expr {[lsearch -exact $deleted note] >= 0}] metadata_deleted [expr {[lsearch -exact $deleted metadata] >= 0}] cleanup_errors $cleanupErrors]
}

proc ::GX::csvDelimiter {path setting} {
    if {$setting eq "," || $setting eq "comma"} { return "," }
    if {$setting eq "semicolon" || $setting eq ";"} { return ";" }
    if {$setting eq "tab"} { return "\t" }
    set fd [open $path r]; fconfigure $fd -encoding utf-8; gets $fd line; close $fd
    set best ","; set nbest -1
    foreach c [list "," ";" "\t"] {
        set n [llength [split $line $c]]
        if {$n > $nbest} { set best $c; set nbest $n }
    }
    return $best
}

proc ::GX::genericCsvValidate_v081_single {} {
    variable cfg
    variable moduleCfg
    if {$cfg(input_csv) eq "" || ![file isfile $cfg(input_csv)]} { error "Select an existing CSV file." }
    if {$cfg(output_root) eq ""} { error "Specify the session root folder." }
    set id [string trim $moduleCfg(acq.generic_csv,dataset_id)]
    if {$id eq ""} { error "Generic CSV import requires a canonical dataset ID." }
    if {![regexp {^[A-Za-z0-9_.-]+$} $id]} { error "Dataset ID may contain only letters, digits, '.', '_' and '-'." }
    set hr $moduleCfg(acq.generic_csv,header_rows)
    if {![string is integer -strict $hr] || $hr < 1} { error "Generic CSV header_rows must be an integer >= 1." }
}

proc ::GX::validate_v052_native {} {
    variable cfg
    if {$cfg(acquisition_module) eq "acq.generic_csv"} { genericCsvValidate; return }
    ::GX::validate_v048
}
proc ::GX::validate {} {
    return [::GX::validate_v052_native]
}

proc ::GX::genericCsvImportSync_v052_native {} {
    variable cfg
    variable moduleCfg
    variable currentSession
    genericCsvValidate
    set cfg(session_mode) "analysis_only"
    set session [makeSession]
    file mkdir [file join $session datasets]
    set src [file normalize $cfg(input_csv)]
    set rawRel [file join raw [file tail $src]]
    set rawDst [file join $session $rawRel]
    file copy -force -- $src $rawDst
    set srcHash [sha256File $rawDst]

    set id [string trim $moduleCfg(acq.generic_csv,dataset_id)]
    set dataRel [file join datasets "${id}.csv"]
    set dataDst [file join $session $dataRel]
    set headerRows $moduleCfg(acq.generic_csv,header_rows)
    if {$headerRows == 1} {
        file copy -force -- $rawDst $dataDst
        set canonicalNote "Canonical table copied byte-for-byte from RAW source"
    } else {
        set inf [open $rawDst r]
        fconfigure $inf -encoding utf-8 -translation auto
        set lastHeader ""
        for {set hi 0} {$hi < $headerRows} {incr hi} {
            if {[gets $inf line] < 0} { close $inf; error "The file ends within the configured generic CSV header rows." }
            set lastHeader $line
        }
        set outf [open $dataDst w]
        fconfigure $outf -encoding utf-8 -translation lf
        puts $outf $lastHeader
        while {[gets $inf line] >= 0} { puts $outf $line }
        close $inf
        close $outf
        set canonicalNote "Canonical table normalized from RAW: final configured header row retained as the column-name row"
    }
    set canonHash [sha256File $dataDst]

    set delim [csvDelimiter $dataDst $moduleCfg(acq.generic_csv,delimiter)]
    set fd [open $dataDst r]; fconfigure $fd -encoding utf-8; gets $fd header; close $fd
    set cols {}
    foreach c [split $header $delim] { lappend cols [string trim $c " \t\r\n\""] }
    if {[llength $cols] < 2} { error "Generic CSV import found fewer than two columns in the header." }

    datasetRegistryClear
    datasetRegister $id [list \
        kind $moduleCfg(acq.generic_csv,dataset_kind) \
        format csv \
        path $dataRel \
        columns [join $cols ","] \
        source_module acq.generic_csv \
        source_raw $rawRel \
        source_sha256 $srcHash \
        canonical_sha256 $canonHash \
        created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] \
        immutable 0 \
        notes $canonicalNote]
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
    set log [open [file join $session logs pipeline.log] w]
    fconfigure $log -encoding utf-8 -translation lf
    puts $log "Standard Module API v1"
    puts $log "Acquisition module: acq.generic_csv"
    puts $log "Session mode: analysis_only"
    puts $log "Dataset: $id"
    puts $log "Columns: [join $cols ,]"
    puts $log "RAW SHA-256: $srcHash"
    puts $log "Canonical SHA-256: $canonHash"
    close $log
    set currentSession $session
    return $session
}

proc ::GX::runSync {manifestPath} {
    variable cfg
    variable cliMode
    set cliMode 1
    loadManifest $manifestPath
    if {$cfg(output_root) eq ""} { set cfg(output_root) [file join [pwd] GXTXT_sessions] }
    if {$cfg(acquisition_module) eq "acq.generic_csv"} {
        set session [genericCsvImportSync]
        puts "Session: $session"
        puts "Acquisition module: acq.generic_csv"
        puts "Dataset registry: [datasetRegistryPath $session]"
        return $session
    }
    return [::GX::runSync_v048 $manifestPath]
}

proc ::GX::modelField {id field {default ""}} {
    variable modelCatalog
    if {[info exists modelCatalog($id,$field)]} { return $modelCatalog($id,$field) }
    return $default
}

# Historical v0.4.8 runtime writer remains callable for compatibility.
proc ::GX::writeStandardRuntimeConfig_v052_native {id} {
    variable currentSession
    variable moduleCfg
    variable scriptDir
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "$id: open a valid session first." }
    loadDatasetRegistry $currentSession
    set datasetId $moduleCfg($id,dataset_id)
    if {[datasetField $datasetId id ""] eq ""} { error "$id: dataset '$datasetId' is not registered in metadata/datasets.ini." }
    set expected [moduleField $id inputs ""]
    set actual [datasetField $datasetId kind ""]
    if {$expected ne "" && $actual ne "" && ![contractSatisfiesAny $actual $expected]} {
        error "$id: dataset '$datasetId' has contract '$actual', expected '$expected'."
    }
    set modelId $moduleCfg($id,model_id)
    if {[modelField $modelId descriptor ""] eq ""} { error "$id: unknown mathematical model '$modelId'." }
    set dataPath [datasetResolvePath $currentSession $datasetId]
    if {![file isfile $dataPath]} { error "$id: canonical dataset file is missing: $dataPath" }
    set outDir [file join $currentSession analysis [sanitize $id]]
    # Script preparation can request a unique run-local runtime snapshot.
    # All existing module callers retain their established output location.
    if {[info exists ::GX::scriptRuntimeOutputOverride] && [dict get $::GX::scriptRuntimeOutputOverride module] eq $id} {
        set outDir [dict get $::GX::scriptRuntimeOutputOverride path]
    }
    file mkdir $outDir
    set path [file join $outDir runtime.ini]
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Standard Module API runtime configuration"
    puts $fd "\[runtime\]"; putKV $fd api_version 1; putKV $fd module_id $id; putKV $fd session $currentSession; putKV $fd output_dir $outDir
    puts $fd "\n\[dataset\]"; putKV $fd id $datasetId; putKV $fd path $dataPath; putKV $fd kind [datasetField $datasetId kind]; putKV $fd columns [datasetField $datasetId columns]
    puts $fd "\n\[model\]"; putKV $fd id $modelId; putKV $fd function [modelField $modelId function]; putKV $fd script [file join $scriptDir [modelField $modelId script]]
    foreach f {x_column family_column y_column y_unit param_names param_initial param_lower param_upper param_units} { putKV $fd $f [modelField $modelId $f ""] }
    puts $fd "\n\[config\]"
    foreach key [moduleConfigKeys $id] { putKV $fd $key $moduleCfg($id,$key) }
    close $fd
    return $path
}

proc ::GX::buildStandardAnalysisQueue_v060_unchecked {} {
    variable moduleOrder
    variable moduleCfg
    variable cfg
    variable scriptDir
    set q {}
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        if {![moduleIsEnabled $id] || ![moduleRunIsSelected $id]} continue
        set runtime [writeStandardRuntimeConfig $id]
        set rel [moduleField $id runner_script ""]
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} { error "$id: standard runner script missing: $script" }
        set ncpu $cfg(cpu_count)
        set cmd [concat [list env OMP_NUM_THREADS=$ncpu OPENBLAS_NUM_THREADS=$ncpu MKL_NUM_THREADS=$ncpu NUMEXPR_NUM_THREADS=$ncpu] [graphicsEnv] [plotEnv $id] [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime]]
        lappend q [list "Analysis - [moduleField $id name $id]" $cmd]
    }
    return $q
}

proc ::GX::buildAnalysisQueue_v052_native {} {
    variable moduleOrder
    set q {}
    set needLegacy 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] eq "analysis" && [moduleField $id runner ""] eq "legacy_adapter" && [moduleIsEnabled $id] && [moduleRunIsSelected $id]} {
            set needLegacy 1; break
        }
    }
    if {$needLegacy} { set q [::GX::buildAnalysisQueue_v048] }
    set q [concat $q [buildStandardAnalysisQueue]]
    if {[llength $q] == 0} { error "No module selected for this run." }
    return $q
}

proc ::GX::buildStandardRerenderQueue_v060_unchecked {paths} {
    variable moduleOrder
    variable cfg
    variable currentSession
    variable scriptDir
    set q {}
    foreach id $moduleOrder {
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        set outDir [file join $currentSession analysis [sanitize $id]]
    # Script preparation can request a unique run-local runtime snapshot.
    # All existing module callers retain their established output location.
    if {[info exists ::GX::scriptRuntimeOutputOverride] && [dict get $::GX::scriptRuntimeOutputOverride module] eq $id} {
        set outDir [dict get $::GX::scriptRuntimeOutputOverride path]
    }
        set hit 0
        foreach p $paths {
            set pn [file normalize $p]
            set dn [file normalize $outDir]
            if {[string first "$dn/" "$pn/"] == 0 || [file dirname $pn] eq $dn} { set hit 1; break }
        }
        if {!$hit} continue
        set cache [file join $outDir render_cache.mat]
        if {![file isfile $cache]} continue
        set runtime [file join $outDir runtime.ini]
        if {![file isfile $runtime]} { set runtime [writeStandardRuntimeConfig $id] }
        set rel [moduleField $id rerender_script ""]
        if {$rel eq ""} continue
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} continue
        set cmd [concat [list env] [graphicsEnv] [plotEnv $id] [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime --cache $cache]]
        lappend q [list "Rerender - [moduleField $id name $id]" $cmd]
    }
    return $q
}

proc ::GX::buildRerenderQueue_v052_native {paths {allConfigured 0}} {
    set q {}
    if {![catch {set legacy [::GX::buildRerenderQueue_v048 $paths $allConfigured]}]} { set q $legacy }
    set q [concat $q [buildStandardRerenderQueue $paths]]
    if {[llength $q] == 0} { error "The selected plots do not belong to a module that supports rerendering." }
    return $q
}

proc ::GX::standardConfigWidget_v060 {parent id key row} {
    variable moduleCfg
    variable modelOrder
    variable currentSession
    set label [moduleConfigField $id $key label $key]
    set type [moduleConfigField $id $key type string]
    ttk::label $parent.l$row -text $label
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    if {$type eq "choice"} {
        set vals [splitList [moduleConfigField $id $key values ""]]
        ttk::combobox $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -values $vals -state readonly -width 30
    } elseif {$type eq "model"} {
        # This historical selector supplies an executable family-model callback.
        # Scalar expression descriptors are discoverable in the same registry
        # but are consumed through the public Numeric composition API.
        set callableModels [lmap model $modelOrder {if {[modelField $model function ""] eq ""} continue;set model}]
        ttk::combobox $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -values $callableModels -state readonly -width 30
    } elseif {$type eq "dataset" && $currentSession ne "" && [file isdirectory $currentSession]} {
        catch {loadDatasetRegistry $currentSession}
        set vals [datasetRegistryIds]
        ttk::combobox $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -values $vals -width 30
    } else {
        ttk::entry $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -width 32
    }
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}

# One owner is selected for each descriptor field. The named historical
# implementations below retain their direct-call delegation contracts, while
# ordinary GUI construction takes exactly one explicit dispatch path.
proc ::GX::standardConfigWidget {parent id key row} {
    if {$id in {analysis.octave_script analysis.python_script} && $key eq "registered_script"} {
        return [::GX::scriptAnalysisSelectorWidget $parent $id $key $row]
    }
    if {$id eq "acq.generic_csv" && $key eq "dataset_kind"} {
        return [::GX::standardConfigWidget_v083_before_analysis_parameters $parent $id $key $row]
    }
    set type [string tolower [moduleConfigField $id $key type string]]
    switch -- $type {
        temporal_set              {set handler ::GX::standardConfigWidgetTemporalSet}
        unit                      {set handler ::GX::standardConfigWidget_before_temporal_set_v1}
        numeric_operation_browser {set handler ::GX::standardConfigWidget_v0933_before_unit_selector}
        table - model             {set handler ::GX::standardConfigWidget_before_numeric_expression_browser}
        selection                 {set handler ::GX::standardConfigWidget_v092_before_repeatable_config}
        analysis_definition       {set handler ::GX::standardConfigWidget_v091_before_dataset_selection}
        file - path               {set handler ::GX::standardConfigWidget_v079_before_scientific_analysis}
        boolean                   {set handler ::GX::standardConfigWidget_v077}
        default                   {set handler ::GX::standardConfigWidget_v060}
    }
    return [$handler $parent $id $key $row]
}

proc ::GX::buildStandardConfigFrame {parent id} {
    grid columnconfigure $parent 1 -weight 1
    set row 0
    foreach key [moduleConfigKeys $id] {
        standardConfigWidget $parent $id $key $row
        incr row
    }
    return $row
}

proc ::GX::augmentStandardGui_v050 {} {
    variable cfg
    variable moduleOrder
    variable moduleRun
    variable ui

    # The importer is an architectural choice, not a parser option.  Put it at
    # the TOP of Acquisition so users cannot mistake the legacy
    # "generic_sequence" parser for the Standard API generic-table importer.
    set f .top.nb.acq
    foreach child [winfo children $f] {
        if {[catch {set gi [grid info $child]}] || [llength $gi] == 0} continue
        if {![dict exists $gi -row]} continue
        set row [dict get $gi -row]
        grid configure $child -row [expr {$row + 1}]
    }
    ttk::labelframe $f.api -text "Acquisition / Import Module (Standard Module API v1)"
    grid $f.api -row 0 -column 0 -columnspan 4 -sticky ew -padx 5 -pady {0 8}
    grid columnconfigure $f.api 1 -weight 1
    ttk::label $f.api.l0 -text "Import module"
    ttk::combobox $f.api.module -textvariable ::GX::cfg(acquisition_module) -values {acq.rigol_csv acq.generic_csv} -state readonly -width 34
    grid $f.api.l0 -row 0 -column 0 -sticky e -padx 4 -pady 3
    grid $f.api.module -row 0 -column 1 -sticky w -padx 4 -pady 3
    ttk::label $f.api.hint -text "Use acq.generic_csv for ordinary tables such as X_V,Vg_V,Y_mA. The 'generic_sequence' parser below belongs to the legacy oscilloscope importer." -wraplength 760 -justify left -foreground #444444
    grid $f.api.hint -row 1 -column 0 -columnspan 3 -sticky ew -padx 4 -pady {0 4}
    ttk::labelframe $f.api.generic -text "acq.generic_csv configuration (descriptor generated)"
    grid $f.api.generic -row 2 -column 0 -columnspan 3 -sticky ew -padx 4 -pady 4
    buildStandardConfigFrame $f.api.generic acq.generic_csv

    # Make the legacy nature of the old parser controls explicit.
    if {[winfo exists $f.l3]} { $f.l3 configure -text "Legacy acquisition parser" }
    if {[winfo exists $f.sessionHelp]} {
        $f.sessionHelp configure -text "PHASE 1 creates a NEW session folder under Session root. Choose the Import module above first. Parser/channel/instrument controls below apply only to acq.rigol_csv."
    }

    # New analysis modules: both Run selector and configuration are generated from descriptors.
    set a .top.nb.analysis.sub.params
    ttk::labelframe $a.standard -text "Standard Module API v1"
    grid $a.standard -row 40 -column 0 -columnspan 3 -sticky ew -padx 6 -pady 8
    grid columnconfigure $a.standard 0 -weight 1
    set r 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis" || [moduleField $id runner ""] ne "standard_octave"} continue
        ttk::labelframe $a.standard.m$r -text "[moduleField $id name $id]  ($id)"
        grid $a.standard.m$r -row $r -column 0 -sticky ew -padx 4 -pady 4
        grid columnconfigure $a.standard.m$r 0 -weight 1
        ttk::checkbutton $a.standard.m$r.run -text "Run / recalculate this module" -variable ::GX::moduleRun($id) -command ::GX::refreshManifestPreview
        grid $a.standard.m$r.run -row 0 -column 0 -sticky w -padx 4 -pady 3
        ttk::frame $a.standard.m$r.cfg
        grid $a.standard.m$r.cfg -row 1 -column 0 -sticky ew -padx 4 -pady 2
        buildStandardConfigFrame $a.standard.m$r.cfg $id
        incr r
    }
}

# The original Tk constructor is retained and augmented after it creates the widgets.
proc ::GX::launchGui_v087_before_workspace_profiles {} {
    ::GX::launchGui_v048
    ::GX::augmentStandardGui
    catch {::GX::refreshModuleCatalog}
    catch {::GX::refreshManifestPreview}
}

# v0.5.1 patch: acquisition-aware CSV preview and module-aware GUI state.
# Generic canonical datasets must never be presented through the legacy Rigol
# channel mapping, and disabled analysis modules must not expose active controls.

proc ::GX::refreshCsvPreview_v052_native2 {} {
    variable cfg
    variable ui
    if {[info exists cfg(acquisition_module)] && $cfg(acquisition_module) eq "acq.generic_csv"} {
        return [refreshGenericCsvPreview]
    }
    ::GX::refreshCsvPreview_v050
    # If a Standard API analysis is selected while the legacy importer is
    # active, say so in the preview. Do not silently switch importers: import
    # and analysis are intentionally independent architectural modules.
    if {[moduleIsEnabled curvefit.family_global] && [info exists ui(preview)] && [winfo exists $ui(preview)]} {
        set w $ui(preview)
        $w configure -state normal
        $w insert 1.0 "*** IMPORT MODE WARNING ***\nCurve Family Fitting is enabled, but the active import module is acq.rigol_csv.\nThe parser 'generic_sequence' is a LEGACY oscilloscope/sequence parser and still uses CH1/CH2/... node mapping.\nFor a table such as X_V,Vg_V,Y_mA select Import module = acq.generic_csv at the TOP of the Acquisition tab.\nImport and fitting are not switched automatically because they are independent modules.\n\n"
        $w configure -state disabled
    }
    return
}

proc ::GX::refreshGenericCsvPreview_v085_before_dataset_inspection {} {
    variable cfg
    variable moduleCfg
    variable ui
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} return
    set w $ui(preview)
    $w configure -state normal
    $w delete 1.0 end
    set p [string trim $cfg(input_csv)]
    if {$p eq "" || ![file isfile $p]} {
        $w insert end "Select a valid CSV file.\n"
        $w configure -state disabled
        return
    }

    set setting [expr {[info exists moduleCfg(acq.generic_csv,delimiter)] ? $moduleCfg(acq.generic_csv,delimiter) : "auto"}]
    if {[catch {set delim [csvDelimiter $p $setting]} err]} {
        $w insert end "CSV delimiter detection error: $err\n"
        $w configure -state disabled
        return
    }
    set dlabel [expr {$delim eq "\t" ? "TAB" : $delim}]
    set nhead [expr {[info exists moduleCfg(acq.generic_csv,header_rows)] ? $moduleCfg(acq.generic_csv,header_rows) : 1}]
    if {![string is integer -strict $nhead] || $nhead < 1} { set nhead 1 }
    set nsamp $cfg(preview_lines)
    if {![string is integer -strict $nsamp] || $nsamp < 1} { set nsamp 8 }

    if {[catch {
        set fd [open $p r]
        fconfigure $fd -encoding utf-8 -translation auto
        set lines {}
        set max [expr {$nhead + $nsamp}]
        for {set i 1} {$i <= $max && [gets $fd line] >= 0} {incr i} { lappend lines $line }
        close $fd
    } err]} {
        $w insert end "Read error: $err\n"
        $w configure -state disabled
        return
    }

    $w insert end "FILE: $p\n"
    $w insert end "Size: [file size $p] bytes\n"
    $w insert end "Acquisition module: acq.generic_csv\n"
    $w insert end "Delimiter: $dlabel"
    if {$setting eq "auto"} { $w insert end " (AUTO)" }
    $w insert end "\nHeader rows: $nhead\n\n"

    $w insert end "=== RAW ROWS ===\n"
    set i 0
    foreach line $lines {
        incr i
        set tag [expr {$i <= $nhead ? "HEADER" : "DATA"}]
        $w insert end [format "%s %d: %s\n" $tag $i $line]
    }

    if {[llength $lines] < $nhead} {
        $w insert end "\nERROR: the file ends inside the configured header.\n"
        $w configure -state disabled
        return
    }

    set header [lindex $lines [expr {$nhead - 1}]]
    set cols {}
    foreach c [split $header $delim] { lappend cols [string trim $c " \t\r\n\""] }
    $w insert end "\n=== CANONICAL DATASET COLUMNS ===\n"
    $w insert end "Columns detected from the final header row: [llength $cols]\n"
    set ci 0
    foreach name $cols {
        incr ci
        $w insert end [format "CSV C%-2d -> %s\n" $ci [expr {$name eq "" ? "<unnamed>" : $name}]]
    }

    set expectedCount [llength $cols]
    set badRows 0
    foreach line [lrange $lines $nhead end] {
        if {[string trim $line] eq ""} continue
        if {[llength [split $line $delim]] != $expectedCount} { incr badRows }
    }
    if {$badRows > 0} {
        $w insert end "WARNING: $badRows preview data row(s) have a different field count.\n"
    }

    if {[moduleIsEnabled curvefit.family_global]} {
        set modelId $moduleCfg(curvefit.family_global,model_id)
        $w insert end "\n=== ACTIVE MODEL COLUMN BINDING ===\n"
        $w insert end "Module: curvefit.family_global\n"
        $w insert end "Model: $modelId\n"
        set canonicalNames [sourceVariableNames]
        foreach {roleText roleKey} {"Independent X" x "Family variable" family "Measured Y" y} {
            set name [resolveModuleBinding curvefit.family_global $roleKey $modelId]
            set ok [expr {$name ne "" && [lsearch -exact $canonicalNames $name] >= 0}]
            $w insert end [format "%-16s -> %-20s %s\n" $roleText $name [expr {$ok ? "OK" : "MISSING"}]]
        }
    } else {
        $w insert end "\nCurve Family Fitting is disabled; no model-column binding is applied.\n"
    }

    $w insert end "\n=== DATA EXTRACT ===\n"
    set heads {}
    for {set c 1} {$c <= [llength $cols]} {incr c} { lappend heads [format "C%-2d" $c] }
    set tab "\t"
    $w insert end "[join $heads $tab]\n"
    foreach line [lrange $lines $nhead end] {
        $w insert end "[join [split $line $delim] $tab]\n"
    }
    $w insert end "\nNOTE: canonical variables inherit CSV header names by default, but may be aliased in Variables. Legacy GX-TXT node mappings are not used.\n"
    $w configure -state disabled
}

proc ::GX::applyDetectedCsvLayout {} {
    variable cfg
    if {[info exists cfg(acquisition_module)] && $cfg(acquisition_module) eq "acq.generic_csv"} {
        refreshCsvPreview
        refreshManifestPreview
        return
    }
    return [::GX::applyDetectedCsvLayout_v050]
}

proc ::GX::setWidgetTreeState {w enabled} {
    if {![winfo exists $w]} return
    foreach c [winfo children $w] {
        catch {$c state [expr {$enabled ? "!disabled" : "disabled"}]}
        setWidgetTreeState $c $enabled
    }
}

proc ::GX::refreshAcquisitionControls {} {
    variable cfg
    if {![winfo exists .top.nb]} return
    set generic [expr {$cfg(acquisition_module) eq "acq.generic_csv"}]

    # Legacy importer-only widgets. CPU count, Octave command and preview row count
    # remain available because PHASE 2 standard modules can still use them.
    foreach w {
        .top.nb.acq.e3 .top.nb.acq.e4 .top.nb.acq.e6 .top.nb.acq.e7
        .top.nb.acq.e8 .top.nb.acq.e9 .top.nb.acq.e10
        .top.nb.acq.c10 .top.nb.acq.c11 .top.nb.acq.c12 .top.nb.acq.c13
        .top.nb.acq.workere .top.nb.acq.workerb .top.nb.acq.e18
        .top.nb.acq.e22 .top.nb.acq.e24 .top.nb.acq.e25 .top.nb.acq.c25
    } {
        if {[winfo exists $w]} { catch {$w state [expr {$generic ? "disabled" : "!disabled"}]} }
    }

    if {[winfo exists .top.nb.acq.api.generic]} {
        setWidgetTreeState .top.nb.acq.api.generic $generic
    }
    if {[winfo exists .top.nb.preview.buttons.apply]} {
        catch {.top.nb.preview.buttons.apply state [expr {$generic ? "disabled" : "!disabled"}]}
    }
    # The current Dataset and Instrumentation browsers serve every importer,
    # including generic CSV and its pending-row Variables action.
    catch {.top.nb tab .top.nb.channels -state normal}
    catch {.top.nb tab .top.nb.instr -state normal}
    if {[winfo exists .top.nb.acq.l3]} {
        .top.nb.acq.l3 configure -foreground [expr {$generic ? "#888888" : "#000000"}]
    }
}

proc ::GX::refreshStandardModuleControls {} {
    variable moduleOrder
    variable moduleRun
    set r 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis" || [moduleField $id runner ""] ne "standard_octave"} continue
        set base .top.nb.analysis.sub.params.standard.m$r
        if {[winfo exists $base]} {
            set active [moduleIsEnabled $id]
            if {!$active} { set moduleRun($id) 0 }
            if {[winfo exists $base.run]} { catch {$base.run state [expr {$active ? "!disabled" : "disabled"}]} }
            if {[winfo exists $base.cfg]} { setWidgetTreeState $base.cfg $active }
        }
        incr r
    }
}

proc ::GX::refreshLegacyParameterControls {} {
    if {![winfo exists .top.nb.analysis.sub.params]} return
    set ir [moduleIsEnabled gxtxt.ir_waveform]
    set hold [moduleIsEnabled gxtxt.hold_led]
    set anyLegacy [expr {$ir || [moduleIsEnabled gxtxt.ir_identify] || [moduleIsEnabled gxtxt.compare_stages] || $hold}]
    foreach w {.top.nb.analysis.sub.params.e2 .top.nb.analysis.sub.params.e5 .top.nb.analysis.sub.params.e6 .top.nb.analysis.sub.params.e7 .top.nb.analysis.sub.params.v} {
        if {[winfo exists $w]} { catch {$w state [expr {$ir ? "!disabled" : "disabled"}]} }
    }
    foreach w {.top.nb.analysis.sub.params.e3 .top.nb.analysis.sub.params.e4 .top.nb.analysis.sub.params.e9 .top.nb.analysis.sub.params.e10 .top.nb.analysis.sub.params.e11 .top.nb.analysis.sub.params.e12 .top.nb.analysis.sub.params.e13 .top.nb.analysis.sub.params.e14} {
        if {[winfo exists $w]} { catch {$w state [expr {$hold ? "!disabled" : "disabled"}]} }
    }
    if {[winfo exists .top.nb.analysis.sub.params.e8]} {
        catch {.top.nb.analysis.sub.params.e8 state [expr {$anyLegacy ? "!disabled" : "disabled"}]}
    }
}

proc ::GX::onAcquisitionModuleChanged_v088_before_acquisition_handler_batch {} {
    refreshAcquisitionControls
    catch {refreshCsvPreview}
    catch {refreshManifestPreview}
}

proc ::GX::onAcquisitionModuleChanged {} {
    tailcall ::GX::onAcquisitionModuleChanged_v088_before_acquisition_handler_batch
}

proc ::GX::augmentStandardGui_v052_native {} {
    ::GX::augmentStandardGui_v050
    if {[winfo exists .top.nb.acq.api.module]} {
        bind .top.nb.acq.api.module <<ComboboxSelected>> {::GX::onAcquisitionModuleChanged}
    }
    refreshAcquisitionControls
    refreshStandardModuleControls
    refreshLegacyParameterControls
}

proc ::GX::refreshAnalysisStatus_v052_native2 {} {
    variable cfg
    variable ui
    variable currentSession
    refreshStandardModuleControls
    refreshLegacyParameterControls
    if {![info exists cfg(acquisition_module)] || $cfg(acquisition_module) ne "acq.generic_csv"} {
        return [::GX::refreshAnalysisStatus_v050]
    }
    if {![info exists ui(analysisStatus)] || ![winfo exists $ui(analysisStatus)]} return
    set w $ui(analysisStatus)
    $w configure -state normal
    $w delete 1.0 end
    if {$currentSession eq ""} {
        $w insert end "No current session. Run the generic CSV import or open an existing analysis-only session.\n"
    } else {
        $w insert end "SESSION: $currentSession\n"
        $w insert end "Acquisition: acq.generic_csv (canonical dataset mode)\n\n"
        catch {loadDatasetRegistry $currentSession}
        set ids [datasetRegistryIds]
        $w insert end "Registered datasets: [expr {[llength $ids] ? [join $ids {, }] : "none"}]\n"
        foreach id $ids {
            $w insert end "  $id: kind=[datasetField $id kind] columns=[datasetField $id columns]\n"
        }
        $w insert end "\nEnabled analysis modules: [join [selectedModuleIds] {, }]\n"
        $w insert end "Run now: [join [selectedRunModuleIds] {, }]\n"
        $w insert end "\nLegacy GX-TXT node/LED compatibility checks are not applicable to a generic canonical dataset.\n"
    }
    $w configure -state disabled
}

proc ::GX::refreshAnalysisStatus {} { ::GX::refreshAnalysisStatus_v052_native2 }

# GUI PHASE 1 routing fix: the v0.5.0 batch path already used genericCsvImportSync,
# but the Tk Start button still entered the legacy asynchronous Rigol worker.
proc ::GX::startAsync_v052_native2 {} {
    variable cfg
    variable pipe
    variable currentSession
    variable ui
    variable runAllPending
    if {$cfg(acquisition_module) ne "acq.generic_csv"} {
        return [::GX::startAsync_v050]
    }
    if {$pipe ne ""} return
    if {[catch {
        setStatus "Importing canonical CSV..." 5
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state disabled }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state disabled }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state disabled }
        set session [genericCsvImportSync]
        guiLog "Session: $session"
        guiLog "Acquisition module: acq.generic_csv"
        guiLog "Canonical dataset registry: [datasetRegistryPath $session]"
        updateSessionUi
        refreshResults
        refreshAnalysisStatus
        refreshGraphs
        setStatus "Generic CSV import completed" 100
    } err opts]} {
        set runAllPending 0
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
        setStatus "Error" 0
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
    if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
    if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
    if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
    if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
    if {$runAllPending} {
        set runAllPending 0
        guiLog "RUN ALL: generic import completed, starting PHASE 2."
        after 100 ::GX::startAnalysis
    } else {
        tk_messageBox -icon info -title "GX-TXT" -message "Generic CSV import completed.\n\n$currentSession"
    }
}

# Saving a generic configuration must not validate the legacy channel mapper.
proc ::GX::saveManifestDialog_v087_before_workspace_profiles {} {
    variable cfg
    if {$cfg(acquisition_module) ne "acq.generic_csv"} {
        return [::GX::saveManifestDialog_v050]
    }
    if {[catch {genericCsvValidate} err]} {
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
    set p [tk_getSaveFile -title "Export configuration manifest" -defaultextension .ini -filetypes {{{Manifest INI} {.ini}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {writeManifest $p} err]} { tk_messageBox -icon error -message $err }
}

proc ::GX::saveManifestDialog {} { ::GX::saveManifestDialog_v087_before_workspace_profiles }

# -----------------------------------------------------------------------------
# v0.6.1 native-only profile
# Manifest format 2, dynamic instruments, canonical variables and module bindings.
# Legacy GX-TXT analysis modules are intentionally not discoverable.
# -----------------------------------------------------------------------------

namespace eval ::GX {
    variable manifestFormatVersion 2
    variable instruments
    variable instrumentCount 0
    variable sourceVar
    variable sourceVarCount 0
    variable moduleBinding
}

# Reset API-native state after the historical defaults have initialized the
# compatibility internals. No instrument or measurement variable is preloaded.
proc ::GX::defaults_v061_base {} {
    variable cfg
    variable instruments
    variable instrumentCount
    variable sourceVar
    variable sourceVarCount
    variable moduleBinding
    ::GX::defaults_v052_api
    set cfg(acquisition_module) "acq.generic_csv"
    set cfg(session_mode) "analysis_only"
    set cfg(experiment_name) ""
    set cfg(experiment_project) ""
    set cfg(experiment_date) [clock format [clock seconds] -format "%Y-%m-%d"]
    set cfg(experiment_notes) ""
    array unset instruments *
    set instrumentCount 0
    array unset sourceVar *
    set sourceVarCount 0
    array unset moduleBinding *
}

proc ::GX::moduleBindingRoles {id} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return {} }
    return [splitList [descriptorValue $moduleCatalog($id,dict) bindings roles ""]]
}

proc ::GX::moduleBindingField {id role field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($id,dict) "binding.$role" $field $default]
}

proc ::GX::ensureModuleBindingDefaults {} {
    variable moduleOrder
    variable moduleBinding
    foreach id $moduleOrder {
        foreach role [moduleBindingRoles $id] {
            if {![info exists moduleBinding($id,$role)]} { set moduleBinding($id,$role) "auto" }
        }
    }
}

proc ::GX::loadModuleCatalog_v061_base {} {
    ::GX::loadModuleCatalog_v052_api
    ensureModuleBindingDefaults
}

proc ::GX::clearInstruments {} {
    variable instruments
    variable instrumentCount
    array unset instruments *
    set instrumentCount 0
}

proc ::GX::addInstrument_v061_fixed {{id ""}} {
    variable instruments
    variable instrumentCount
    incr instrumentCount
    set n $instrumentCount
    if {$id eq ""} { set id "instrument$n" }
    foreach {k v} {enabled 1 id "" type "" role "" manufacturer "" model "" serial "" firmware "" notes ""} {
        set instruments($n,$k) $v
    }
    set instruments($n,id) $id
    return $n
}

proc ::GX::removeLastInstrument {} {
    variable instruments
    variable instrumentCount
    if {$instrumentCount <= 0} return
    foreach k [array names instruments "$instrumentCount,*"] { unset instruments($k) }
    incr instrumentCount -1
    refreshNativeInstrumentationGui
    refreshNativeVariablesGui
}

proc ::GX::instrumentIds {} {
    variable instruments
    variable instrumentCount
    set out {}
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        if {![info exists instruments($i,enabled)] || !$instruments($i,enabled)} continue
        set id [string trim $instruments($i,id)]
        if {$id ne ""} { lappend out $id }
    }
    return $out
}

proc ::GX::clearSourceVariables {} {
    variable sourceVar
    variable sourceVarCount
    array unset sourceVar *
    set sourceVarCount 0
}

proc ::GX::setSourceVariablesFromHeaders {headers} {
    variable sourceVar
    variable sourceVarCount
    clearSourceVariables
    set idx 0
    foreach h $headers {
        incr idx
        set sourceVarCount $idx
        set name [string trim $h]
        if {$name eq ""} { set name "C$idx" }
        foreach {k v} [list enabled 1 source_column $idx source_channel "" original_header $name canonical $name unit "" semantic_role "" instrument_id "" instrument_channel ""] {
            set sourceVar($idx,$k) $v
        }
    }
}

proc ::GX::sourceVariableNames {} {
    variable sourceVar
    variable sourceVarCount
    set out {}
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        set n [string trim $sourceVar($i,canonical)]
        if {$n ne ""} { lappend out $n }
    }
    return $out
}

proc ::GX::headersFromCsv {path delimiter headerRows} {
    set d [csvDelimiter $path $delimiter]
    set f [open $path r]
    fconfigure $f -encoding utf-8 -translation auto
    set header ""
    for {set i 0} {$i < $headerRows} {incr i} {
        if {[gets $f header] < 0} { close $f; error "CSV ends inside configured header rows." }
    }
    close $f
    set cols {}
    foreach c [split $header $d] { lappend cols [string trim $c " \t\r\n\""] }
    return $cols
}

proc ::GX::ensureVariablesForCurrentInput_v088_before_acquisition_handler_api {} {
    variable cfg
    variable moduleCfg
    variable sourceVarCount
    if {$cfg(input_csv) eq "" || ![file isfile $cfg(input_csv)]} return
    if {$cfg(acquisition_module) eq "acq.generic_csv"} {
        set headers [headersFromCsv $cfg(input_csv) $moduleCfg(acq.generic_csv,delimiter) $moduleCfg(acq.generic_csv,header_rows)]
    } else {
        # Rigol files may not expose semantic headers. Initialize from the final
        # configured header when useful; otherwise preserve an existing map.
        set hr $moduleCfg(acq.rigol_csv,header_rows)
        if {$hr < 1} { set hr 1 }
        set headers [headersFromCsv $cfg(input_csv) $moduleCfg(acq.rigol_csv,delimiter) $hr]
    }
    if {$sourceVarCount == 0} { setSourceVariablesFromHeaders $headers }
}

proc ::GX::ensureVariablesForCurrentInput {} {
    tailcall ::GX::ensureVariablesForCurrentInput_v088_before_acquisition_handler_api
}

proc ::GX::resolveModuleBinding_v084_single_source {id role {modelId ""}} {
    variable moduleBinding
    variable sourceVar
    variable sourceVarCount
    set explicit [expr {[info exists moduleBinding($id,$role)] ? [string trim $moduleBinding($id,$role)] : "auto"}]
    if {$explicit ne "" && $explicit ne "auto"} { return $explicit }

    set pref ""
    set mf [moduleBindingField $id $role preferred_model_field ""]
    if {$modelId ne "" && $mf ne ""} { set pref [modelField $modelId $mf ""] }
    if {$pref ne "" && [lsearch -exact [sourceVariableNames] $pref] >= 0} { return $pref }

    set wanted [moduleBindingField $id $role semantic_role ""]
    if {$wanted ne ""} {
        for {set i 1} {$i <= $sourceVarCount} {incr i} {
            if {[info exists sourceVar($i,enabled)] && $sourceVar($i,enabled) && [string equal -nocase [string trim $sourceVar($i,semantic_role)] $wanted]} {
                return [string trim $sourceVar($i,canonical)]
            }
        }
    }
    return ""
}

proc ::GX::validateNativeVariables {} {
    variable sourceVar
    variable sourceVarCount
    if {$sourceVarCount <= 0} { error "No CSV variables are defined. Preview the CSV or define variables first." }
    set seen {}
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        set c [string trim $sourceVar($i,source_column)]
        set n [string trim $sourceVar($i,canonical)]
        if {![string is integer -strict $c] || $c < 1} { error "Variable row $i: source column must be an integer >= 1." }
        if {$n eq ""} { error "Variable row $i: canonical variable name is required." }
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $n]} { error "Variable '$n': use letters/digits/underscore/dot/hyphen and start with a letter or underscore." }
        if {[lsearch -exact $seen $n] >= 0} { error "Duplicate canonical variable name '$n'." }
        lappend seen $n
    }
    if {[llength $seen] == 0} { error "Enable at least one CSV variable." }
}

proc ::GX::syncRigolConfigToLegacy {} {
    variable cfg
    variable moduleCfg
    foreach {mk ck} {
        parser parser delimiter delimiter header_rows header_lines sequence_col sequence_col time_col time_col
        tstart manual_tstart dt manual_dt make_rigol_split make_rigol_split make_canonical_split make_canonical_split
        chunk_rows chunk_rows raw_fields raw_fields drop_trailing_fields drop_trailing_fields strict_sequence strict_sequence
    } {
        set v $moduleCfg(acq.rigol_csv,$mk)
        if {$mk eq "delimiter" && $v eq "comma"} { set v "," }
        set cfg($ck) $v
    }
}

proc ::GX::syncVariablesToLegacyChannels {} {
    variable sourceVar
    variable sourceVarCount
    variable ch
    for {set i 1} {$i <= 8} {incr i} { set ch($i,enabled) 0 }
    set out 0
    for {set i 1} {$i <= $sourceVarCount && $out < 8} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        incr out
        set ch($out,enabled) 1
        set ch($out,column) $sourceVar($i,source_column)
        set sc [string trim $sourceVar($i,source_channel)]
        if {$sc eq ""} { set sc "CH$out" }
        set ch($out,scope) $sc
        set ch($out,name) [string trim $sourceVar($i,canonical)]
        set ch($out,plot_label) $ch($out,name)
    }
    if {$out == 0} { error "Rigol import requires at least one enabled variable." }
}

# Native acquisition validation: no GX-TXT IR/HOLD/LED parameters are consulted.
proc ::GX::validate {} {
    variable cfg
    variable moduleCfg
    if {$cfg(input_csv) eq "" || ![file isfile $cfg(input_csv)]} { error "Select an existing acquisition CSV." }
    if {$cfg(output_root) eq ""} { error "Specify the session root folder." }
    ensureVariablesForCurrentInput
    validateNativeVariables
    if {$cfg(acquisition_module) eq "acq.generic_csv"} {
        genericCsvValidate
        return
    }
    if {$cfg(acquisition_module) ne "acq.rigol_csv"} { error "Unknown acquisition module '$cfg(acquisition_module)'." }
    syncRigolConfigToLegacy
    syncVariablesToLegacyChannels
    if {$cfg(worker_file) eq "" || ![file isfile $cfg(worker_file)]} { error "Octave CSV worker not found: $cfg(worker_file)" }
    if {$cfg(octave_cmd) eq ""} { error "Specify octave-cli/octave." }
    if {[auto_execok $cfg(octave_cmd)] eq "" && ![file executable $cfg(octave_cmd)]} { error "Octave command not found: $cfg(octave_cmd)" }
    if {![string is integer -strict $cfg(header_lines)] || $cfg(header_lines) < 0} { error "Header rows must be >= 0." }
    if {![string is integer -strict $cfg(chunk_rows)] || $cfg(chunk_rows) < 1000} { error "Rows per block must be >= 1000." }
    if {$cfg(parser) eq "generic_sequence" && ($cfg(manual_tstart) eq "" || $cfg(manual_dt) eq "")} { error "generic_sequence requires manual tStart and dt." }
}

proc ::GX::buildWorkerCommand {session} {
    variable cfg
    if {$cfg(acquisition_module) ne "acq.rigol_csv"} { error "buildWorkerCommand is only valid for acq.rigol_csv." }
    syncRigolConfigToLegacy
    syncVariablesToLegacyChannels
    return [::GX::buildWorkerCommand_v052_native $session]
}

# Save variables as dataset metadata after a generic import. The CSV content is
# left intact when names are inherited; aliases and semantic metadata live in
# the registry and are resolved by module bindings.
proc ::GX::genericCsvImportSync_v060_precanon {} {
    variable sourceVar
    variable sourceVarCount
    set session [::GX::genericCsvImportSync_v052_native]
    loadDatasetRegistry $session
    variable moduleCfg
    set id $moduleCfg(acq.generic_csv,dataset_id)
    set vars {}
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        lappend vars [string trim $sourceVar($i,canonical)]
        foreach f {source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} {
            set datasetRegistry($id,var${i}_$f) $sourceVar($i,$f)
        }
    }
    set datasetRegistry($id,variables) [join $vars ,]
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
    return $session
}

proc ::GX::registerRigolDatasets {session} {
    variable sourceVar
    variable sourceVarCount
    datasetRegistryClear
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        set name [string trim $sourceVar($i,canonical)]
        set candidates [glob -nocomplain -types f [file join $session channels "*${name}*canonical.csv"]]
        if {[llength $candidates] == 0} { set candidates [glob -nocomplain -types f [file join $session channels "*${name}*rigol.csv"]] }
        if {[llength $candidates] == 0} continue
        set p [lindex $candidates 0]
        set rel [file join channels [file tail $p]]
        set id "rigol.$name"
        datasetRegister $id [list kind timeseries.table format csv path $rel columns "time_s,$name" source_module acq.rigol_csv canonical_sha256 [sha256File $p] immutable 0]
        foreach f {source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} {
            set datasetRegistry($id,$f) $sourceVar($i,$f)
        }
    }
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
}

# Module runtime uses explicit/semantic/model-preferred bindings rather than
# assuming fixed CSV column names.
proc ::GX::writeStandardRuntimeConfig_v061_base {id} {
    variable currentSession
    variable moduleCfg
    variable scriptDir
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "$id: open a valid session first." }
    loadDatasetRegistry $currentSession
    set datasetId $moduleCfg($id,dataset_id)
    set optionalEmpty [expr {$datasetId eq "" && [moduleSupportsAnalysisSources $id] && ![analysisSourceIsRequired $id primary]}]
    if {!$optionalEmpty && [datasetField $datasetId id ""] eq ""} { error "$id: dataset '$datasetId' is not registered." }
    set expected [moduleField $id inputs ""]
    set actual [datasetField $datasetId kind ""]
    if {$expected ne "" && $actual ne "" && ![contractSatisfiesAny $actual $expected]} { error "$id: dataset contract '$actual' does not satisfy '$expected'." }
    set modelId [expr {[info exists moduleCfg($id,model_id)] ? $moduleCfg($id,model_id) : ""}]
    if {$modelId ne "" && [modelField $modelId descriptor ""] eq ""} { error "$id: unknown model '$modelId'." }
    # Resolve every binding before opening runtime.ini. A stale dataset-scoped
    # identity must fail without leaving a partially rewritten runtime file.
    set resolvedBindings [dict create]
    foreach role [moduleBindingRoles $id] {
        dict set resolvedBindings $role [resolveModuleBinding $id $role $modelId]
    }
    set dataPath ""
    if {!$optionalEmpty} {
        set dataPath [datasetResolvePath $currentSession $datasetId]
        if {![file isfile $dataPath]} { error "$id: canonical dataset file is missing: $dataPath" }
    }
    set outDir [file join $currentSession analysis [sanitize $id]]
    # Script preparation can request a unique run-local runtime snapshot.
    # All existing module callers retain their established output location.
    if {[info exists ::GX::scriptRuntimeOutputOverride] && [dict get $::GX::scriptRuntimeOutputOverride module] eq $id} {
        set outDir [dict get $::GX::scriptRuntimeOutputOverride path]
    }
    file mkdir $outDir
    set configuredSpice ""
    if {$id eq "model.spice_build_validate" && $::tcl_platform(platform) eq "unix" && [llength [info commands ::GX::runtimeToolResolve]]} {
        set configuredSpice [::GX::runtimeToolResolve spice]
    }
    set path [file join $outDir runtime.ini]
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; Standard Module API runtime configuration"
    puts $fd "\[runtime\]"; putKV $fd api_version 1; putKV $fd module_id $id; putKV $fd session $currentSession; putKV $fd output_dir $outDir
    if {$id eq "model.spice_build_validate" && $::tcl_platform(platform) eq "unix"} {
        # The module's default executable follows the configured Linux runtime.
        # Its explicit per-module override remains available in [config].
        putKV $fd spice_cmd $configuredSpice
    }
    puts $fd "\n\[dataset\]"; putKV $fd id $datasetId; putKV $fd path $dataPath; putKV $fd kind [datasetField $datasetId kind]; putKV $fd columns [datasetField $datasetId columns]
    if {$modelId ne ""} {
        puts $fd "\n\[model\]"; putKV $fd id $modelId; putKV $fd function [modelField $modelId function]; putKV $fd script [file join $scriptDir [modelField $modelId script]]
        foreach f {y_unit param_names param_initial param_lower param_upper param_units} { putKV $fd $f [modelField $modelId $f ""] }
        foreach {role mf} {x x_column family family_column y y_column} {
            set resolved [expr {[dict exists $resolvedBindings $role] ? [dict get $resolvedBindings $role] : [resolveModuleBinding $id $role $modelId]}]
            if {$resolved eq "" && [moduleBindingField $id $role required 0]} { close $fd; error "$id: input binding '$role' cannot be resolved." }
            putKV $fd $mf $resolved
        }
    }
    puts $fd "\n\[bindings\]"
    foreach role [moduleBindingRoles $id] { putKV $fd $role [dict get $resolvedBindings $role] }
    puts $fd "\n\[config\]"
    foreach key [moduleConfigKeys $id] { putKV $fd $key $moduleCfg($id,$key) }
    close $fd
    return $path
}

# Native-only queue and rerender: no call into the old hard-coded analysis tree.
proc ::GX::buildAnalysisQueue {} {
    set q [buildStandardAnalysisQueue]
    if {[llength $q] == 0} { error "No enabled Standard Module API analysis is selected for this run." }
    return $q
}
proc ::GX::buildRerenderQueue {paths {allConfigured 0}} {
    set q [buildStandardRerenderQueue $paths]
    if {[llength $q] == 0} { error "The selected plots do not belong to an enabled standard module with rerender support." }
    return $q
}

# ----------------------------- Manifest format 2 ------------------------------
proc ::GX::manifestStringV2_v061_base {} {
    variable cfg
    variable moduleOrder
    variable moduleCfg
    variable moduleBinding
    variable instruments
    variable instrumentCount
    variable sourceVar
    variable sourceVarCount
    set out "; GX-TXT Pipeline manifest format 2\n; SPDX-License-Identifier: GPL-3.0-or-later\n"
    append out "\n\[pipeline\]\n"; appendKV out format 2; appendKV out application_version $::GX::version; appendKV out module_api_version 1
    append out "\n\[runtime\]\n"; appendKV out octave_cmd $cfg(octave_cmd); appendKV out cpu_count $cfg(cpu_count); appendKV out worker_file $cfg(worker_file)
    append out "\n\[acquisition\]\n"; appendKV out module_id $cfg(acquisition_module); appendKV out input_csv $cfg(input_csv); appendKV out session_root $cfg(output_root); appendKV out session_name $cfg(session_name)
    append out "\n\[session\]\n"; appendKV out mode $cfg(session_mode)
    append out "\n\[experiment\]\n"; appendKV out name $cfg(experiment_name); appendKV out project $cfg(experiment_project); appendKV out date $cfg(experiment_date); appendKV out notes $cfg(experiment_notes)
    append out "\n\[instruments\]\n"; appendKV out count $instrumentCount
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        append out "\n\[instrument.$i\]\n"
        foreach k {enabled id type role manufacturer model serial firmware notes} { appendKV out $k $instruments($i,$k) }
    }
    append out "\n\[source_variables\]\n"; appendKV out count $sourceVarCount
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        append out "\n\[source_variable.$i\]\n"
        foreach k {enabled source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} { appendKV out $k $sourceVar($i,$k) }
    }
    append out "\n\[module_state\]\n"; appendKV out enabled [join [selectedModuleIds] ,]; appendKV out run [join [selectedRunModuleIds] ,]
    foreach id $moduleOrder {
        set keys [moduleConfigKeys $id]
        if {[llength $keys]} {
            append out "\n\[module_config.$id\]\n"
            foreach key $keys {if {[configurationModuleShouldPersist $id $key]} {appendKV out $key $moduleCfg($id,$key)}}
        }
        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            append out "\n\[module_binding.$id\]\n"
            foreach role $roles { appendKV out $role $moduleBinding($id,$role) }
        }
    }
    append out "\n\[graphics\]\n"
    foreach key {graphics_mode graphics_toolkit graphics_display graphics_visible plot_width_px plot_height_px plot_font_unit plot_font_size plot_axis_label_font_size plot_title_font_size plot_line_width plot_grid plot_grid_mode plot_grid_color plot_background plot_legend_mode plot_legend_location plot_legend_layout plot_legend_alignment plot_legend_columns plot_legend_font_unit plot_legend_font_size plot_legend_background plot_legend_border plot_legend_external_border plot_legend_border_color plot_legend_external_margin_px plot_legend_manual_x plot_legend_manual_y analysis_png_dpi} {
        if {[info exists cfg($key)]} { appendKV out $key $cfg($key) }
    }
    append out "\n\[print\]\n"
    foreach key {print_page print_orientation print_rows print_cols print_margin_mm print_gap_mm print_captions print_title print_output_pdf print_printer print_copies print_duplex export_dir} {
        if {[info exists cfg($key)]} { appendKV out $key $cfg($key) }
    }
    return $out
}

proc ::GX::manifestString {} { return [manifestStringV2] }

proc ::GX::loadManifestV2_v061_base {path} {
    variable cfg
    variable moduleOrder
    variable moduleCfg
    variable moduleBinding
    variable instruments
    variable instrumentCount
    variable sourceVar
    variable sourceVarCount
    set d [parseIni $path]
    foreach {dk ck} {
        acquisition.module_id acquisition_module acquisition.input_csv input_csv acquisition.session_root output_root acquisition.session_name session_name
        session.mode session_mode runtime.octave_cmd octave_cmd runtime.cpu_count cpu_count runtime.worker_file worker_file
        experiment.name experiment_name experiment.project experiment_project experiment.date experiment_date experiment.notes experiment_notes
    } { if {[dict exists $d $dk]} { set cfg($ck) [dict get $d $dk] } }
    clearInstruments
    set instrumentCount [expr {[dict exists $d instruments.count] ? [dict get $d instruments.count] : 0}]
    if {![string is integer -strict $instrumentCount] || $instrumentCount < 0} { set instrumentCount 0 }
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        foreach {k def} {enabled 1 id "" type "" role "" manufacturer "" model "" serial "" firmware "" notes ""} {
            set key "instrument.$i.$k"; set instruments($i,$k) [expr {[dict exists $d $key] ? [dict get $d $key] : $def}]
        }
    }
    clearSourceVariables
    set sourceVarCount [expr {[dict exists $d source_variables.count] ? [dict get $d source_variables.count] : 0}]
    if {![string is integer -strict $sourceVarCount] || $sourceVarCount < 0} { set sourceVarCount 0 }
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        foreach {k def} {enabled 1 source_column "" source_channel "" original_header "" canonical "" unit "" semantic_role "" instrument_id "" instrument_channel ""} {
            set key "source_variable.$i.$k"; set sourceVar($i,$k) [expr {[dict exists $d $key] ? [dict get $d $key] : $def}]
        }
    }
    if {[dict exists $d module_state.enabled]} { applyModuleSelection [dict get $d module_state.enabled] }
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] eq "analysis"} { moduleSetRunSelected $id 0 }
        foreach key [moduleConfigKeys $id] { set dk "module_config.$id.$key"; if {[dict exists $d $dk]} { set moduleCfg($id,$key) [dict get $d $dk] } }
        foreach role [moduleBindingRoles $id] { set dk "module_binding.$id.$role"; if {[dict exists $d $dk]} { set moduleBinding($id,$role) [dict get $d $dk] } }
    }
    if {[dict exists $d module_state.run]} { foreach id [splitList [dict get $d module_state.run]] { if {[lsearch -exact $moduleOrder $id] >= 0} { moduleSetRunSelected $id 1 } } }
    foreach key {graphics_mode graphics_toolkit graphics_display graphics_visible plot_width_px plot_height_px plot_font_unit plot_font_size plot_axis_label_font_size plot_title_font_size plot_line_width plot_grid plot_grid_mode plot_grid_color plot_background plot_legend_mode plot_legend_location plot_legend_layout plot_legend_alignment plot_legend_columns plot_legend_font_unit plot_legend_font_size plot_legend_background plot_legend_border plot_legend_external_border plot_legend_border_color plot_legend_external_margin_px plot_legend_manual_x plot_legend_manual_y analysis_png_dpi} {
        set dk "graphics.$key"; if {[dict exists $d $dk]} { set cfg($key) [dict get $d $dk] }
    }
    foreach key {print_page print_orientation print_rows print_cols print_margin_mm print_gap_mm print_captions print_title print_output_pdf print_printer print_copies print_duplex export_dir} {
        set dk "print.$key"; if {[dict exists $d $dk]} { set cfg($key) [dict get $d $dk] }
    }
}

proc ::GX::loadManifest {path} {
    # Session instrument projections must not flush old text into new owners.
    set priorLoading [expr {[info exists ::GX::sessionInstrumentLoading] ? $::GX::sessionInstrumentLoading : {}}]
    set ::GX::sessionInstrumentLoading 1
    try {
        set d [parseIni $path]
        if {[dict exists $d pipeline.format] && [dict get $d pipeline.format] eq "2"} {
            loadManifestV2 $path
        } else {
            # Read-only compatibility for old manifests. Legacy modules cannot re-enter
            # discovery because their descriptors are absent.
            ::GX::loadManifest_v052_native $path
            ensureModuleBindingDefaults
        }
        # Existing registered-script fields advertise this configuration contract;
        # preserve legacy external-file values without branching on plugin IDs.
        foreach id $::GX::moduleOrder {
            if {[moduleConfigField $id registered_script type {}] ne "registered_script"} continue
            if {"external_file" in [splitList [moduleConfigField $id source_mode values {}]] &&
                [moduleConfigField $id script_file type {}] eq "file" &&
                ![dict exists $d module_config.$id.source_mode] &&
                [dict exists $d module_config.$id.script_file] &&
                [string trim [dict get $d module_config.$id.script_file]] ne ""} {
                set ::GX::moduleCfg($id,source_mode) external_file
            }
            if {[llength [info commands ::GX::scriptAnalysisSyncRequiredApis]]} {
                ::GX::scriptAnalysisSyncRequiredApis $id
            }
        }
        configurationSessionLoad $path
    } finally {
        if {$priorLoading eq {}} {unset ::GX::sessionInstrumentLoading} else {set ::GX::sessionInstrumentLoading $priorLoading}
    }
}

# ----------------------------- Native GUI ------------------------------------
proc ::GX::destroyChildren {w} { if {[winfo exists $w]} { foreach c [winfo children $w] { destroy $c } } }

proc ::GX::refreshNativeInstrumentationGui {} {
    variable instruments
    variable instrumentCount
    set f .top.nb.instr
    if {![winfo exists $f]} return
    destroyChildren $f
    grid columnconfigure $f 0 -weight 1
    ttk::frame $f.bar
    ttk::button $f.bar.add -text "Add instrument" -command {::GX::addInstrument; ::GX::refreshNativeInstrumentationGui; ::GX::refreshNativeVariablesGui; ::GX::refreshManifestPreview}
    ttk::button $f.bar.remove -text "Remove last" -command {::GX::removeLastInstrument; ::GX::refreshManifestPreview}
    ttk::label $f.bar.note -text "No instrument is predefined. Add only the equipment actually used in this experiment."
    pack $f.bar.add $f.bar.remove $f.bar.note -side left -padx 4
    grid $f.bar -row 0 -column 0 -sticky ew -padx 5 -pady 5
    ttk::frame $f.tbl
    grid $f.tbl -row 1 -column 0 -sticky nsew -padx 5 -pady 5
    foreach {c txt} {0 Use 1 {Stable ID} 2 Type 3 Role 4 Manufacturer 5 Model 6 Serial 7 Firmware 8 Notes} { ttk::label $f.tbl.h$c -text $txt; grid $f.tbl.h$c -row 0 -column $c -sticky w -padx 2 }
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        ttk::checkbutton $f.tbl.e$i -variable ::GX::instruments($i,enabled)
        grid $f.tbl.e$i -row $i -column 0 -padx 2
        set c 1
        foreach k {id type role manufacturer model serial firmware notes} {
            ttk::entry $f.tbl.${k}$i -textvariable ::GX::instruments($i,$k) -width [expr {$k eq "notes" ? 22 : 14}]
            grid $f.tbl.${k}$i -row $i -column $c -sticky ew -padx 2 -pady 2
            incr c
        }
    }
}

proc ::GX::refreshNativeVariablesGui_v085_before_dataset_inspection {} {
    variable sourceVar
    variable sourceVarCount
    set f .top.nb.channels
    if {![winfo exists $f]} return
    destroyChildren $f
    grid columnconfigure $f 0 -weight 1
    ttk::frame $f.bar
    ttk::button $f.bar.detect -text "Read variables from CSV" -command {::GX::clearSourceVariables; ::GX::ensureVariablesForCurrentInput; ::GX::refreshNativeVariablesGui; ::GX::refreshCsvPreview; ::GX::refreshManifestPreview}
    ttk::label $f.bar.note -text "Canonical name inherits the CSV header by default. Change it only when you need an alias."
    pack $f.bar.detect $f.bar.note -side left -padx 4
    grid $f.bar -row 0 -column 0 -sticky ew -padx 5 -pady 5
    ttk::frame $f.tbl
    grid $f.tbl -row 1 -column 0 -sticky nsew -padx 5 -pady 5
    foreach {c txt} {0 Use 1 {CSV column} 2 {Source channel} 3 {Original header} 4 {Canonical variable} 5 Unit 6 {Semantic role} 7 Instrument 8 {Instrument channel}} { ttk::label $f.tbl.h$c -text $txt; grid $f.tbl.h$c -row 0 -column $c -sticky w -padx 2 }
    set inst [linsert [instrumentIds] 0 ""]
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        ttk::checkbutton $f.tbl.e$i -variable ::GX::sourceVar($i,enabled)
        grid $f.tbl.e$i -row $i -column 0
        ttk::entry $f.tbl.c$i -textvariable ::GX::sourceVar($i,source_column) -width 8; grid $f.tbl.c$i -row $i -column 1 -padx 2
        ttk::entry $f.tbl.sc$i -textvariable ::GX::sourceVar($i,source_channel) -width 10; grid $f.tbl.sc$i -row $i -column 2 -padx 2
        ttk::entry $f.tbl.oh$i -textvariable ::GX::sourceVar($i,original_header) -width 16 -state readonly; grid $f.tbl.oh$i -row $i -column 3 -padx 2
        ttk::entry $f.tbl.n$i -textvariable ::GX::sourceVar($i,canonical) -width 18; grid $f.tbl.n$i -row $i -column 4 -padx 2
        ttk::entry $f.tbl.u$i -textvariable ::GX::sourceVar($i,unit) -width 8; grid $f.tbl.u$i -row $i -column 5 -padx 2
        ttk::entry $f.tbl.r$i -textvariable ::GX::sourceVar($i,semantic_role) -width 14; grid $f.tbl.r$i -row $i -column 6 -padx 2
        ttk::combobox $f.tbl.i$i -textvariable ::GX::sourceVar($i,instrument_id) -values $inst -width 14; grid $f.tbl.i$i -row $i -column 7 -padx 2
        ttk::entry $f.tbl.ic$i -textvariable ::GX::sourceVar($i,instrument_channel) -width 12; grid $f.tbl.ic$i -row $i -column 8 -padx 2
    }
}

proc ::GX::rebuildNativeExperimentGui {} {
    variable cfg
    set f .top.nb.exp
    destroyChildren $f
    grid columnconfigure $f 1 -weight 1
    addLabeledEntry $f 0 "Experiment name" ::GX::cfg(experiment_name)
    addLabeledEntry $f 1 "Project" ::GX::cfg(experiment_project)
    addLabeledEntry $f 2 "Date" ::GX::cfg(experiment_date)
    addLabeledEntry $f 3 "Notes" ::GX::cfg(experiment_notes)
    ttk::label $f.note -text "Instrument-specific metadata belongs in Instrumentation; measured quantities and CSV associations belong in Variables." -wraplength 900 -justify left
    grid $f.note -row 4 -column 0 -columnspan 3 -sticky ew -padx 6 -pady 10
}

proc ::GX::rebuildNativeAcquisitionGui {} {
    variable cfg
    variable moduleOrder
    set f .top.nb.acq
    destroyChildren $f
    # Keep the established config/queue widget identities and provider dispatch.
    # The browser is a projection of module metadata, not another catalog.
    foreach column {0 1 2 3} {grid columnconfigure $f $column -weight 0 -minsize 0}
    grid columnconfigure $f 0 -weight 1
    grid columnconfigure $f 1 -minsize 310
    grid rowconfigure $f 2 -weight 1
    ttk::frame $f.heading
    ttk::label $f.heading.name -textvariable ::GX::ui(acquisitionName) -font TkHeadingFont
    ttk::label $f.heading.description -textvariable ::GX::ui(acquisitionDescription) -wraplength 550 -justify left
    ttk::label $f.heading.steps -text {Choose an importer → set options → add files → review Preview / Variables → import. Changing importer clears pending files.} -wraplength 550 -justify left
    pack $f.heading.name $f.heading.description $f.heading.steps -anchor w -fill x -pady 3
    grid $f.heading -row 0 -column 0 -sticky ew -padx 8 -pady 5
    bind $f.heading <Configure> [list ::GX::acquisitionHeadingLayout %w]
    ttk::frame $f.cfg; grid $f.cfg -row 1 -column 0 -sticky ew -padx 5 -pady 4; grid columnconfigure $f.cfg 0 -weight 1
    acquisitionBrowserBuild
    refreshNativeAcquisitionConfig
}

proc ::GX::refreshNativeAcquisitionConfig_v081_before_v082_batch {} {
    variable cfg
    set f .top.nb.acq.cfg
    if {![winfo exists $f]} return
    destroyChildren $f
    ttk::labelframe $f.box -text "$cfg(acquisition_module) configuration"
    grid $f.box -row 0 -column 0 -sticky ew
    grid columnconfigure $f.box 1 -weight 1
    buildStandardConfigFrame $f.box $cfg(acquisition_module)
}

proc ::GX::moduleIsRunnableAnalysis {id} {
    if {[moduleField $id kind ""] ne "analysis" || [moduleField $id runner ""] in {"" service provider internal}} {
        return 0
    }
    if {[moduleField $id ui_replaced_by_core 0]} { return 0 }
    set surface [moduleField $id ui_surface_id ""]
    if {$surface ne "" && [llength [info commands ::GX::coreUiSurfaceVisible]] && ![coreUiSurfaceVisible $surface]} {
        return 0
    }
    return 1
}

proc ::GX::rebuildNativeAnalysisGui {} {
    variable moduleOrder
    variable moduleRun
    variable moduleBinding
    set f .top.nb.analysis
    destroyChildren $f
    grid columnconfigure $f 0 -weight 1
    set row 0
    foreach id $moduleOrder {
        if {![moduleIsRunnableAnalysis $id]} continue
        ttk::labelframe $f.m$row -text "[moduleField $id name $id]  ($id)"
        grid $f.m$row -row $row -column 0 -sticky ew -padx 6 -pady 6
        grid columnconfigure $f.m$row 1 -weight 1
        ttk::checkbutton $f.m$row.enabled -text "Enabled in experiment" -variable ::GX::moduleEnabled($id) -command [list ::GX::nativeModuleToggle $id]
        ttk::checkbutton $f.m$row.run -text "Run / recalculate now" -variable ::GX::moduleRun($id) -command ::GX::refreshManifestPreview
        grid $f.m$row.enabled -row 0 -column 0 -sticky w -padx 4 -pady 3; grid $f.m$row.run -row 0 -column 1 -sticky w -padx 4 -pady 3
        ttk::labelframe $f.m$row.cfg -text "Configuration"; grid $f.m$row.cfg -row 1 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4; buildStandardConfigFrame $f.m$row.cfg $id
        set br 2
        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            ttk::labelframe $f.m$row.bind -text "Input variable bindings"; grid $f.m$row.bind -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4; grid columnconfigure $f.m$row.bind 1 -weight 1
            set vals [linsert [sourceVariableNames] 0 auto]
            set rr 0
            foreach role $roles {
                ttk::label $f.m$row.bind.l$rr -text [moduleBindingField $id $role label $role]
                ttk::combobox $f.m$row.bind.w$rr -textvariable ::GX::moduleBinding($id,$role) -values $vals -state readonly -width 30
                grid $f.m$row.bind.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2; grid $f.m$row.bind.w$rr -row $rr -column 1 -sticky w -padx 4 -pady 2
                incr rr
            }
        }
        incr row
    }
    if {$row == 0} { ttk::label $f.none -text "No Standard Module API analysis modules are installed."; grid $f.none -row 0 -column 0 -padx 8 -pady 8 }
    refreshNativeAnalysisState
}

proc ::GX::nativeModuleToggle {id} {
    variable moduleEnabled
    moduleSetEnabled $id $moduleEnabled($id)
    refreshNativeAnalysisState
    refreshManifestPreview
}

proc ::GX::refreshNativeAnalysisState_v061_base {} {
    variable moduleOrder
    set row 0
    foreach id $moduleOrder {
        if {![moduleIsRunnableAnalysis $id]} continue
        set base .top.nb.analysis.m$row
        if {[winfo exists $base]} {
            set on [moduleIsEnabled $id]
            if {!$on} { moduleSetRunSelected $id 0 }
            catch {$base.run state [expr {$on ? "!disabled" : "disabled"}]}
            if {[winfo exists $base.cfg]} { setWidgetTreeState $base.cfg $on }
            if {[winfo exists $base.bind]} { setWidgetTreeState $base.bind $on }
        }
        incr row
    }
}

# Replace the old mixed GUI after it is constructed. This leaves the proven
# session/results/plot/print infrastructure untouched while removing all visible
# legacy GX-TXT acquisition/analysis controls.
proc ::GX::augmentStandardGui_v061_base {} {
    ::GX::augmentStandardGui_v052_native
    catch {.top.nb tab .top.nb.channels -text "Variables" -state normal}
    catch {.top.nb tab .top.nb.instr -state normal}
    rebuildNativeAcquisitionGui
    refreshNativeInstrumentationGui
    rebuildNativeExperimentGui
    refreshNativeVariablesGui
    rebuildNativeAnalysisGui
    catch {refreshModuleCatalog}
}

# Preview also seeds the variable registry when it is still empty.
proc ::GX::refreshCsvPreview_v088_before_acquisition_handler_api {} {
    catch {ensureVariablesForCurrentInput}
    set r [::GX::refreshCsvPreview_v052_native2]
    catch {refreshNativeVariablesGui}
    catch {rebuildNativeAnalysisGui}
    return $r
}

# Native Rigol import: sync descriptor/variable state before entering the proven
# asynchronous worker. Generic CSV keeps the synchronous Standard API path.
proc ::GX::startAsync_v060_predispatch {} {
    variable cfg
    if {$cfg(acquisition_module) eq "acq.rigol_csv"} {
        validate
        syncRigolConfigToLegacy
        syncVariablesToLegacyChannels
    }
    return [::GX::startAsync_v052_native2]
}

# After the old Rigol worker closes successfully, expose its outputs through the
# Canonical Dataset API. Failure leaves no fabricated registry entries.
proc ::GX::onPipeReadable {p} {
    variable pipe
    variable cfg
    variable currentSession
    set before $pipe
    set mode $cfg(acquisition_module)
    set session $currentSession
    set r [::GX::onPipeReadable_v052_native $p]
    if {$mode eq "acq.rigol_csv" && $before ne "" && $pipe eq "" && $session ne "" && [file isdirectory [file join $session channels]]} {
        if {![catch {registerRigolDatasets $session} err]} {
            catch {guiLog "Canonical Dataset API registry updated for Rigol outputs."}
        } else {
            catch {guiLog "Rigol dataset registry warning: $err"}
        }
    }
    return $r
}

# Retain the older status text-widget entry for programmatic and historical GUI callers.
# Run status for v0.6.1: standard modules only.
proc ::GX::refreshAnalysisStatus {} {
    variable ui
    variable currentSession
    if {![info exists ui(analysisStatus)] || ![winfo exists $ui(analysisStatus)]} return
    set w $ui(analysisStatus)
    $w configure -state normal; $w delete 1.0 end
    if {$currentSession eq ""} {
        $w insert end "No current session. Run PHASE 1 or open an existing session.\n"
    } else {
        catch {loadDatasetRegistry $currentSession}
        $w insert end "SESSION: $currentSession\n"
        $w insert end "Datasets: [join [datasetRegistryIds] {, }]\n"
        $w insert end "Enabled standard analysis modules: [join [selectedModuleIds] {, }]\n"
        $w insert end "Run now: [join [selectedRunModuleIds] {, }]\n"
    }
    $w configure -state disabled
}

# v0.6.1 native CSV canonicalization and widget refinements.
proc ::GX::genericCsvImportSync_v081_single {} {
    variable cfg
    variable moduleCfg
    variable sourceVar
    variable sourceVarCount
    variable currentSession
    variable scriptDir
    genericCsvValidate
    ensureVariablesForCurrentInput
    validateNativeVariables
    set cfg(session_mode) "analysis_only"
    set session [makeSession]
    file mkdir [file join $session datasets]
    set src [file normalize $cfg(input_csv)]
    set rawRel [file join raw [file tail $src]]
    set rawDst [file join $session $rawRel]
    file copy -force -- $src $rawDst
    set srcHash [sha256File $rawDst]

    set id [string trim $moduleCfg(acq.generic_csv,dataset_id)]
    set dataRel [file join datasets "${id}.csv"]
    set dataDst [file join $session $dataRel]
    set setting $moduleCfg(acq.generic_csv,delimiter)
    set delim [csvDelimiter $rawDst $setting]
    set token [expr {$delim eq "," ? "comma" : ($delim eq ";" ? "semicolon" : "tab")}]
    set helper [file join $scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
    set cmd [list [runtimeToolRequired python] $helper --input $rawDst --output $dataDst --delimiter $token --header-rows $moduleCfg(acq.generic_csv,header_rows)]
    set vars {}
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        set name [string trim $sourceVar($i,canonical)]
        lappend vars $name
        lappend cmd --map "$sourceVar($i,source_column)=$name"
    }
    if {[catch {exec {*}$cmd 2>@1} out opts]} { error "Canonical CSV conversion failed: $out" }
    set canonHash [sha256File $dataDst]

    datasetRegistryClear
    datasetRegister $id [list kind $moduleCfg(acq.generic_csv,dataset_kind) format csv path $dataRel columns [join $vars ,] variables [join $vars ,] var_count $sourceVarCount source_header_rows $moduleCfg(acq.generic_csv,header_rows) source_delimiter $token canonical_delimiter $token source_module acq.generic_csv source_raw $rawRel source_sha256 $srcHash canonical_sha256 $canonHash created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 notes "Canonical CSV generated from RAW using the source-variable map"]
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        foreach f {enabled source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} { set datasetRegistry($id,var${i}_$f) $sourceVar($i,$f) }
    }
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
    set log [open [file join $session logs pipeline.log] w]; fconfigure $log -encoding utf-8 -translation lf
    puts $log "Standard Module API v1 / Manifest format 2"
    puts $log "Acquisition module: acq.generic_csv"
    puts $log "Dataset: $id"
    puts $log "Variables: [join $vars ,]"
    puts $log "RAW SHA-256: $srcHash"
    puts $log "Canonical SHA-256: $canonHash"
    close $log
    set currentSession $session
    return $session
}

proc ::GX::standardConfigWidget_v077 {parent id key row} {
    variable moduleCfg
    set type [moduleConfigField $id $key type string]
    if {$type ne "boolean"} { return [::GX::standardConfigWidget_v060 $parent $id $key $row] }
    set label [moduleConfigField $id $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::checkbutton $parent.w$row -variable ::GX::moduleCfg($id,$key)
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky w -padx 4 -pady 2
}

proc ::GX::moduleRunnerHandler {id} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return "" }
    return [descriptorValue $moduleCatalog($id,dict) runner handler ""]
}

# Final acquisition dispatch is descriptor-driven. standard_tcl identifies the
# runner family; [runner].handler chooses the native implementation.
proc ::GX::startAsync_v088_before_acquisition_handler_dispatch {} {
    variable cfg
    set id $cfg(acquisition_module)
    if {[moduleField $id kind ""] ne "acquisition" || [moduleField $id runner ""] ne "standard_tcl"} {
        error "Acquisition module '$id' is not a native standard_tcl module."
    }
    switch -- [moduleRunnerHandler $id] {
        generic_csv { return [::GX::startAsync_v060_predispatch] }
        rigol_csv   { return [::GX::startAsync_v060_predispatch] }
        default { error "$id: missing or unsupported native acquisition handler." }
    }
}

# -----------------------------------------------------------------------------
# v0.6.1 hardening: native-only plot environment, checked Octave runner, and
# native Results view.  These overrides intentionally keep the Module API v1
# and Manifest format 2 contracts unchanged.
# -----------------------------------------------------------------------------

# The old plotEnv carried IR / HOLD-LED / stage-comparison variables into every
# Octave process.  In the native-only profile only generic graphics settings are
# exported.  Module-specific settings belong to the module runtime/config.
proc ::GX::plotEnv_v062_native_legend_base {} {
    variable cfg
    return [list \
        GXTXT_PLOT_WIDTH_PX=$cfg(plot_width_px) \
        GXTXT_PLOT_HEIGHT_PX=$cfg(plot_height_px) \
        GXTXT_PNG_DPI=$cfg(analysis_png_dpi) \
        GXTXT_PLOT_FONT_UNIT=$cfg(plot_font_unit) \
        GXTXT_PLOT_FONT_SIZE=$cfg(plot_font_size) \
        GXTXT_PLOT_AXIS_LABEL_FONT_SIZE=$cfg(plot_axis_label_font_size) \
        GXTXT_PLOT_TITLE_FONT_SIZE=$cfg(plot_title_font_size) \
        GXTXT_PLOT_LINE_WIDTH=$cfg(plot_line_width) \
        GXTXT_PLOT_GRID=$cfg(plot_grid) \
        GXTXT_PLOT_GRID_MODE=$cfg(plot_grid_mode) \
        GXTXT_PLOT_GRID_COLOR=$cfg(plot_grid_color) \
        GXTXT_PLOT_TIME_UNIT=$cfg(plot_time_unit) \
        GXTXT_PLOT_STACKED_SHARED_X=$cfg(plot_stacked_shared_x) \
        GXTXT_PLOT_STACKED_BOTTOM_XTICKS_ONLY=$cfg(plot_stacked_bottom_xticks_only) \
        GXTXT_PLOT_STACKED_GRID_MODE=$cfg(plot_stacked_grid_mode) \
        GXTXT_PLOT_STACKED_MARGIN_LEFT_PCT=$cfg(plot_stacked_margin_left_pct) \
        GXTXT_PLOT_STACKED_MARGIN_RIGHT_PCT=$cfg(plot_stacked_margin_right_pct) \
        GXTXT_PLOT_STACKED_MARGIN_TOP_PCT=$cfg(plot_stacked_margin_top_pct) \
        GXTXT_PLOT_STACKED_MARGIN_BOTTOM_PCT=$cfg(plot_stacked_margin_bottom_pct) \
        GXTXT_PLOT_STACKED_GAP_PCT=$cfg(plot_stacked_gap_pct) \
        GXTXT_PLOT_STACKED_ALIGN_YLABELS=$cfg(plot_stacked_align_ylabels) \
        GXTXT_PLOT_STACKED_YLABEL_X=$cfg(plot_stacked_ylabel_x) \
        GXTXT_PLOT_LEGEND_MODE=$cfg(plot_legend_mode) \
        GXTXT_PLOT_LEGEND_LOCATION=$cfg(plot_legend_location) \
        GXTXT_PLOT_LEGEND_FONT_UNIT=$cfg(plot_legend_font_unit) \
        GXTXT_PLOT_LEGEND_FONT_SIZE=$cfg(plot_legend_font_size) \
        GXTXT_PLOT_LEGEND_ORIENTATION=$cfg(plot_legend_orientation) \
        GXTXT_PLOT_LEGEND_LAYOUT=$cfg(plot_legend_layout) \
        GXTXT_PLOT_LEGEND_ALIGNMENT=$cfg(plot_legend_alignment) \
        GXTXT_PLOT_LEGEND_COLUMNS=$cfg(plot_legend_columns) \
        GXTXT_PLOT_LEGEND_BACKGROUND=$cfg(plot_legend_background) \
        GXTXT_PLOT_LEGEND_BORDER=$cfg(plot_legend_border) \
        GXTXT_PLOT_LEGEND_EXTERNAL_BORDER=$cfg(plot_legend_external_border) \
        GXTXT_PLOT_LEGEND_BORDER_COLOR=$cfg(plot_legend_border_color) \
        GXTXT_PLOT_LEGEND_EXTERNAL_MARGIN_PX=$cfg(plot_legend_external_margin_px) \
        GXTXT_PLOT_LEGEND_MANUAL_X=$cfg(plot_legend_manual_x) \
        GXTXT_PLOT_LEGEND_MANUAL_Y=$cfg(plot_legend_manual_y) \
        GXTXT_PLOT_BACKGROUND=$cfg(plot_background)]
}

# Standard Octave modules are executed through a small streaming wrapper which
# propagates the real child exit status and validates the descriptor-declared
# output contract.  A module cannot be reported as completed when only
# runtime.ini exists.
proc ::GX::buildStandardAnalysisQueue_v077 {} {
    variable moduleOrder
    variable cfg
    variable scriptDir
    set q {}
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        if {[moduleField $id ui_replaced_by_core 0] && (![info exists ::GX::cliMode] || !$::GX::cliMode)} continue
        if {![moduleIsEnabled $id] || ![moduleRunIsSelected $id]} continue
        set runtime [writeStandardRuntimeConfig $id]
        set rel [moduleField $id runner_script ""]
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} { error "$id: standard runner script missing: $script" }
        set outDir [file dirname $runtime]
        set expected [moduleExpectedOutputs $id]
        set wrapper [file join $scriptDir core tcl standard_octave_exec.tcl]
        if {![file isfile $wrapper]} { error "$id: standard Octave wrapper missing: $wrapper" }
        set ncpu $cfg(cpu_count)
        set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime]
        set cmd [concat \
            [list env OMP_NUM_THREADS=$ncpu OPENBLAS_NUM_THREADS=$ncpu MKL_NUM_THREADS=$ncpu NUMEXPR_NUM_THREADS=$ncpu] \
            [graphicsEnv] [plotEnv $id] \
            [list tclsh $wrapper --output-dir $outDir --expected $expected --] \
            $child]
        lappend q [list "Analysis - [moduleField $id name $id]" $cmd]
    }
    return $q
}

# Rerender uses the same checked process wrapper.  The child exit status is
# always enforced; the declared output contract is also revalidated.
proc ::GX::buildStandardRerenderQueue_v063_runtime_base {paths} {
    variable moduleOrder
    variable cfg
    variable currentSession
    variable scriptDir
    set q {}
    foreach id $moduleOrder {
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        set outDir [file join $currentSession analysis [sanitize $id]]
    # Script preparation can request a unique run-local runtime snapshot.
    # All existing module callers retain their established output location.
    if {[info exists ::GX::scriptRuntimeOutputOverride] && [dict get $::GX::scriptRuntimeOutputOverride module] eq $id} {
        set outDir [dict get $::GX::scriptRuntimeOutputOverride path]
    }
        set hit 0
        foreach p $paths {
            set pn [file normalize $p]
            set dn [file normalize $outDir]
            if {[string first "$dn/" "$pn/"] == 0 || [file dirname $pn] eq $dn} { set hit 1; break }
        }
        if {!$hit} continue
        set cache [file join $outDir render_cache.mat]
        if {![file isfile $cache]} continue
        set runtime [file join $outDir runtime.ini]
        if {![file isfile $runtime]} { set runtime [writeStandardRuntimeConfig $id] }
        set rel [moduleField $id rerender_script ""]
        if {$rel eq ""} continue
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} continue
        set wrapper [file join $scriptDir core tcl standard_octave_exec.tcl]
        set expected [moduleExpectedOutputs $id]
        set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime --cache $cache]
        set cmd [concat [list env] [graphicsEnv] [plotEnv $id] \
            [list tclsh $wrapper --output-dir $outDir --expected $expected --] $child]
        lappend q [list "Rerender - [moduleField $id name $id]" $cmd]
    }
    return $q
}

# Results in the native profile show Canonical Dataset API information instead
# of asking every acquisition module for legacy Rigol import_result.ini and
# summary.tsv files.
proc ::GX::refreshResults_v091_before_dataset_notes {} {
    variable ui
    variable currentSession
    if {![info exists ui(results)] || ![winfo exists $ui(results)]} return
    set w $ui(results)
    $w configure -state normal
    $w delete 1.0 end
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        $w insert end "No current session. Run PHASE 1 or open an existing session.\n"
        $w configure -state disabled
        return
    }

    $w insert end "SESSION: $currentSession\n\n"
    $w insert end "=== CANONICAL DATASETS ===\n"
    if {[catch {loadDatasetRegistry $currentSession} derr]} {
        $w insert end "Dataset registry unavailable: $derr\n"
    } else {
        set ids [datasetRegistryIds]
        if {[llength $ids] == 0} {
            $w insert end "No canonical datasets registered.\n"
        } else {
            foreach id $ids {
                set rel [datasetField $id path ""]
                set abs [expr {$rel eq "" ? "" : [file join $currentSession $rel]}]
                set size [expr {$abs ne "" && [file isfile $abs] ? [file size $abs] : -1}]
                $w insert end "Dataset: $id\n"
                $w insert end "  kind:    [datasetField $id kind ""]\n"
                $w insert end "  columns: [datasetField $id columns ""]\n"
                $w insert end "  path:    $rel\n"
                if {$size >= 0} { $w insert end "  size:    $size byte\n" }
                set sha [datasetField $id canonical_sha256 ""]
                if {$sha ne ""} { $w insert end "  SHA-256: $sha\n" }
            }
        }
    }

    set cdir [file join $currentSession channels]
    if {[file isdirectory $cdir]} {
        set cfiles [lsort [glob -nocomplain -types f -directory $cdir *]]
        if {[llength $cfiles]} {
            $w insert end "\n=== ACQUISITION OUTPUT FILES ===\n"
            foreach f $cfiles { $w insert end [format "%-52s %12d byte\n" [file tail $f] [file size $f]] }
        }
    }

    set adir [file join $currentSession analysis]
    $w insert end "\n=== ANALYSIS OUTPUT ===\n"
    set any 0
    if {[file isdirectory $adir]} {
        foreach f [walkFiles $adir] {
            set any 1
            $w insert end [format "%-70s %12d byte\n" [string range $f [expr {[string length $adir]+1}] end] [file size $f]]
        }
    }
    if {!$any} { $w insert end "No analysis output is available.\n" }
    $w configure -state disabled
}

proc ::GX::refreshResults {} { ::GX::refreshResults_v091_before_dataset_notes }

# -----------------------------------------------------------------------------
# v0.6.2 UI/API refinement
# - descriptor-driven per-module plot configuration
# - rich experiment notebook fields
# - Instrument Module API v1 (instrument definitions are loaded as modules)
# -----------------------------------------------------------------------------

namespace eval ::GX {
    variable instrumentApiVersion 1
    variable instrumentCatalog
    variable instrumentOrder {}
    variable instrumentModuleChoice ""
    variable modulePlotCfg
}

proc ::GX::instrumentDescriptorValue {id section key {default ""}} {
    variable instrumentCatalog
    if {![info exists instrumentCatalog($id,dict)]} { return $default }
    return [descriptorValue $instrumentCatalog($id,dict) $section $key $default]
}

proc ::GX::loadInstrumentCatalog {} {
    variable instrumentCatalog
    variable instrumentOrder
    variable instrumentModuleChoice
    variable scriptDir
    array unset instrumentCatalog *
    set instrumentOrder {}
    set root [file join $scriptDir plugins instruments]
    foreach path [lsort [glob -nocomplain -types f [file join $root * instrument.ini]]] {
        set d [parseIni $path]
        if {[descriptorValue $d meta api_version ""] ne "1"} { error "Unsupported Instrument Module API version in $path" }
        set id [string trim [descriptorValue $d meta id ""]]
        if {$id eq ""} { error "Missing instrument meta.id in $path" }
        if {[info exists instrumentCatalog($id,dict)]} { error "Duplicate instrument module id: $id" }
        set instrumentCatalog($id,dict) $d
        foreach {k def} {name "" version "" group "Laboratory instruments" description ""} {
            set instrumentCatalog($id,$k) [descriptorValue $d meta $k $def]
        }
        set instrumentCatalog($id,fields) [descriptorValue $d fields ids ""]
        set instrumentCatalog($id,descriptor) $path
        lappend instrumentOrder $id
    }
    if {$instrumentModuleChoice eq "" || [lsearch -exact $instrumentOrder $instrumentModuleChoice] < 0} {
        set instrumentModuleChoice [expr {[llength $instrumentOrder] ? [lindex $instrumentOrder 0] : ""}]
    }
}

proc ::GX::instrumentModuleFieldKeys {moduleId} {
    variable instrumentCatalog
    if {![info exists instrumentCatalog($moduleId,fields)]} { return {} }
    return [splitList $instrumentCatalog($moduleId,fields)]
}

proc ::GX::instrumentModuleField {moduleId key field {default ""}} {
    return [instrumentDescriptorValue $moduleId "field.$key" $field $default]
}

proc ::GX::instrumentModuleName {moduleId} {
    variable instrumentCatalog
    if {[info exists instrumentCatalog($moduleId,name)] && $instrumentCatalog($moduleId,name) ne ""} { return $instrumentCatalog($moduleId,name) }
    return $moduleId
}

proc ::GX::moduleGraphIds {id} { return [splitList [moduleField $id graphs ""]] }
proc ::GX::moduleGraphField {id graph field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($id,dict) "graph.$graph" $field $default]
}
proc ::GX::moduleGraphConfigKeys {id graph} { return [splitList [moduleGraphField $id $graph config_fields ""]] }
proc ::GX::moduleGraphConfigField {id graph key field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($id,dict) "graph.$graph.config.$key" $field $default]
}
proc ::GX::ensureModulePlotDefaults {} {
    variable moduleOrder
    variable modulePlotCfg
    foreach id $moduleOrder {
        foreach graph [moduleGraphIds $id] {
            foreach key [moduleGraphConfigKeys $id $graph] {
                if {![info exists modulePlotCfg($id,$graph,$key)]} {
                    set modulePlotCfg($id,$graph,$key) [moduleGraphConfigField $id $graph $key default ""]
                }
            }
        }
    }
}

# Catalog discovery now includes instrument modules and plot defaults.
proc ::GX::loadModuleCatalog_v070_graph_provider_base {} {
    ::GX::loadModuleCatalog_v061_base
    loadInstrumentCatalog
    ensureModulePlotDefaults
}

# Native defaults: no instrument instance is created automatically.
proc ::GX::defaults_v070_graph_provider_base {} {
    variable cfg
    variable modulePlotCfg
    variable instrumentModuleChoice
    ::GX::defaults_v061_base
    foreach {k v} {
        experiment_operator ""
        experiment_tags ""
        experiment_objective ""
        experiment_procedure ""
        experiment_observations ""
    } { set cfg($k) $v }
    array unset modulePlotCfg *
    set instrumentModuleChoice ""
}

proc ::GX::addInstrumentFromModule {{moduleId ""}} {
    variable instrumentModuleChoice
    variable instrumentCatalog
    variable instruments
    variable instrumentCount
    if {$moduleId eq ""} { set moduleId $instrumentModuleChoice }
    if {$moduleId eq "" || ![info exists instrumentCatalog($moduleId,dict)]} { error "Choose an installed instrument module first." }
    incr instrumentCount
    set n $instrumentCount
    foreach {k v} {enabled 1 module_id "" id "" display_name "" type "" role "" manufacturer "" model "" serial "" firmware "" notes ""} { set instruments($n,$k) $v }
    set instruments($n,module_id) $moduleId
    set instruments($n,id) "instrument$n"
    set instruments($n,display_name) [instrumentModuleName $moduleId]
    foreach key [instrumentModuleFieldKeys $moduleId] {
        set instruments($n,field,$key) [instrumentModuleField $moduleId $key default ""]
    }
    return $n
}

# Compatibility helper: programmatic addInstrument now creates a generic
# instrument-module instance, but nothing is preloaded at startup.
proc ::GX::addInstrument {{id ""}} {
    set n [addInstrumentFromModule instrument.generic]
    if {$id ne ""} { set ::GX::instruments($n,id) $id }
    return $n
}

proc ::GX::removeInstrument {idx} {
    variable instruments
    variable instrumentCount
    if {![string is integer -strict $idx] || $idx < 1 || $idx > $instrumentCount} return
    for {set i $idx} {$i < $instrumentCount} {incr i} {
        foreach k [array names instruments "$i,*"] { unset instruments($k) }
        foreach k [array names instruments "[expr {$i+1}],*"] {
            set tail [string range $k [expr {[string first , $k]+1}] end]
            set instruments($i,$tail) $instruments($k)
        }
    }
    foreach k [array names instruments "$instrumentCount,*"] { unset instruments($k) }
    incr instrumentCount -1
}

proc ::GX::instrumentTextWidget {parent idx key row label} {
    variable instruments
    ttk::label $parent.l$row -text $label
    text $parent.w$row -height 4 -wrap word -undo 1
    $parent.w$row insert 1.0 $instruments($idx,field,$key)
    bind $parent.w$row <<Modified>> [list ::GX::instrumentTextChanged $parent.w$row $idx $key]
    $parent.w$row edit modified 0
    ttk::scrollbar $parent.s$row -orient vertical -command [list $parent.w$row yview]
    $parent.w$row configure -yscrollcommand [list $parent.s$row set]
    grid $parent.l$row -row $row -column 0 -sticky ne -padx 4 -pady 3
    grid $parent.w$row -row $row -column 1 -sticky nsew -padx {4 0} -pady 3
    grid $parent.s$row -row $row -column 2 -sticky ns -pady 3
}
proc ::GX::instrumentTextChanged {w idx key} {
    variable instruments
    if {![winfo exists $w] || ![$w edit modified]} return
    set instruments($idx,field,$key) [string trimright [$w get 1.0 end] "\n"]
    $w edit modified 0
}

proc ::GX::refreshNativeInstrumentationGui_before_scientific_notes_v1 {} {
    variable instruments
    variable instrumentCount
    variable instrumentOrder
    variable instrumentModuleChoice
    set f .top.nb.instr
    if {![winfo exists $f]} return
    destroyChildren $f
    for {set r 0} {$r < 50} {incr r} { catch {grid rowconfigure $f $r -weight 0} }
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    ttk::frame $f.bar
    ttk::label $f.bar.ml -text "Instrument module"
    ttk::combobox $f.bar.module -textvariable ::GX::instrumentModuleChoice -values $instrumentOrder -state readonly -width 32
    ttk::button $f.bar.add -text "Load / add instrument module" -command {::GX::addInstrumentFromModule; ::GX::refreshNativeInstrumentationGui; ::GX::refreshNativeVariablesGui; ::GX::refreshManifestPreview}
    ttk::label $f.bar.note -text "Installed modules are templates; no instrument instance is created until you add one."
    pack $f.bar.ml $f.bar.module $f.bar.add $f.bar.note -side left -padx 4
    grid $f.bar -row 0 -column 0 -sticky ew -padx 5 -pady 5

    canvas $f.c -highlightthickness 0
    ttk::scrollbar $f.sy -orient vertical -command [list $f.c yview]
    ttk::frame $f.body
    $f.c create window 0 0 -window $f.body -anchor nw -tags body
    $f.c configure -yscrollcommand [list $f.sy set]
    bind $f.body <Configure> [list $f.c configure -scrollregion [list 0 0 2000 2000]]
    bind $f.c <Configure> {catch {.top.nb.instr.c itemconfigure body -width %w}; catch {.top.nb.instr.c configure -scrollregion [.top.nb.instr.c bbox all]}}
    grid $f.c -row 1 -column 0 -sticky nsew -padx {5 0} -pady 5
    grid $f.sy -row 1 -column 1 -sticky ns -pady 5
    grid columnconfigure $f.body 0 -weight 1

    if {$instrumentCount == 0} {
        ttk::label $f.body.none -text "No instruments in this experiment. Choose an Instrument module above and load an instance when needed." -wraplength 1000 -justify left
        grid $f.body.none -row 0 -column 0 -sticky w -padx 8 -pady 12
        return
    }
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        if {![info exists instruments($i,module_id)]} { set instruments($i,module_id) instrument.generic }
        set mid $instruments($i,module_id)
        ttk::labelframe $f.body.i$i -text "[instrumentModuleName $mid]  — instance $i"
        grid $f.body.i$i -row [expr {$i-1}] -column 0 -sticky ew -padx 5 -pady 5
        grid columnconfigure $f.body.i$i 1 -weight 1
        ttk::checkbutton $f.body.i$i.enabled -text "Use in experiment" -variable ::GX::instruments($i,enabled)
        ttk::button $f.body.i$i.remove -text "Remove" -command [list ::GX::removeInstrumentAndRefresh $i]
        grid $f.body.i$i.enabled -row 0 -column 0 -sticky w -padx 4 -pady 3
        grid $f.body.i$i.remove -row 0 -column 2 -sticky e -padx 4 -pady 3
        ttk::label $f.body.i$i.idl -text "Stable ID"; ttk::entry $f.body.i$i.id -textvariable ::GX::instruments($i,id)
        ttk::label $f.body.i$i.dnl -text "Display name"; ttk::entry $f.body.i$i.dn -textvariable ::GX::instruments($i,display_name)
        grid $f.body.i$i.idl -row 1 -column 0 -sticky e -padx 4 -pady 2; grid $f.body.i$i.id -row 1 -column 1 -columnspan 2 -sticky ew -padx 4 -pady 2
        grid $f.body.i$i.dnl -row 2 -column 0 -sticky e -padx 4 -pady 2; grid $f.body.i$i.dn -row 2 -column 1 -columnspan 2 -sticky ew -padx 4 -pady 2
        set rr 3
        foreach key [instrumentModuleFieldKeys $mid] {
            set label [instrumentModuleField $mid $key label $key]
            set type [instrumentModuleField $mid $key type string]
            if {![info exists instruments($i,field,$key)]} { set instruments($i,field,$key) [instrumentModuleField $mid $key default ""] }
            if {$type eq "multiline"} {
                instrumentTextWidget $f.body.i$i $i $key $rr $label
            } else {
                ttk::label $f.body.i$i.l$rr -text $label
                if {$type eq "choice"} {
                    ttk::combobox $f.body.i$i.w$rr -textvariable ::GX::instruments($i,field,$key) -values [splitList [instrumentModuleField $mid $key values ""]] -width 36
                } else {
                    ttk::entry $f.body.i$i.w$rr -textvariable ::GX::instruments($i,field,$key)
                }
                grid $f.body.i$i.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2
                grid $f.body.i$i.w$rr -row $rr -column 1 -columnspan 2 -sticky ew -padx 4 -pady 2
            }
            incr rr
        }
    }
}
proc ::GX::refreshNativeInstrumentationGui {} {
    tailcall ::GX::refreshNativeInstrumentationGui_before_scientific_notes_v1
}
proc ::GX::removeInstrumentAndRefresh {idx} {
    removeInstrument $idx
    refreshNativeInstrumentationGui
    refreshNativeVariablesGui
    refreshManifestPreview
}

# Rich experiment notebook. Text widgets synchronize directly to cfg values.
proc ::GX::experimentTextChanged {w key} {
    variable cfg
    if {![winfo exists $w] || ![$w edit modified]} return
    set cfg($key) [string trimright [$w get 1.0 end] "\n"]
    $w edit modified 0
}
proc ::GX::addExperimentTextTab {nb name label key} {
    variable cfg
    ttk::frame $nb.$name
    $nb add $nb.$name -text $label
    grid columnconfigure $nb.$name 0 -weight 1; grid rowconfigure $nb.$name 0 -weight 1
    text $nb.$name.t -wrap word -undo 1 -font TkTextFont
    ttk::scrollbar $nb.$name.sy -orient vertical -command [list $nb.$name.t yview]
    $nb.$name.t configure -yscrollcommand [list $nb.$name.sy set]
    $nb.$name.t insert 1.0 $cfg($key); $nb.$name.t edit modified 0
    bind $nb.$name.t <<Modified>> [list ::GX::experimentTextChanged $nb.$name.t $key]
    grid $nb.$name.t -row 0 -column 0 -sticky nsew -padx {4 0} -pady 4
    grid $nb.$name.sy -row 0 -column 1 -sticky ns -pady 4
}
proc ::GX::rebuildNativeExperimentGui_before_project_api_v1 {} {
    variable cfg
    set f .top.nb.exp
    destroyChildren $f
    for {set r 0} {$r < 30} {incr r} { catch {grid rowconfigure $f $r -weight 0} }
    grid columnconfigure $f 1 -weight 1
    grid rowconfigure $f 6 -weight 1
    addLabeledEntry $f 0 "Experiment name" ::GX::cfg(experiment_name)
    addLabeledEntry $f 1 "Project" ::GX::cfg(experiment_project)
    addLabeledEntry $f 2 "Date" ::GX::cfg(experiment_date)
    addLabeledEntry $f 3 "Operator / author" ::GX::cfg(experiment_operator)
    addLabeledEntry $f 4 "Tags / keywords" ::GX::cfg(experiment_tags)
    ttk::label $f.hint -text "Use the notebook below as a simple laboratory record. Instrument-specific metadata belongs in Instrumentation; measured variables and CSV associations belong in Variables." -wraplength 1200 -justify left
    grid $f.hint -row 5 -column 0 -columnspan 3 -sticky ew -padx 6 -pady {5 2}
    ttk::notebook $f.notes
    grid $f.notes -row 6 -column 0 -columnspan 3 -sticky nsew -padx 6 -pady 6
    addExperimentTextTab $f.notes notes "Notes" experiment_notes
    addExperimentTextTab $f.notes objective "Objective" experiment_objective
    addExperimentTextTab $f.notes procedure "Procedure / setup" experiment_procedure
    addExperimentTextTab $f.notes observations "Observations" experiment_observations
}

proc ::GX::modulePlotConfigWidget_v077 {parent id graph key row} {
    variable modulePlotCfg
    set label [moduleGraphConfigField $id $graph $key label $key]
    set type [moduleGraphConfigField $id $graph $key type string]
    ttk::label $parent.l$row -text $label
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    if {$type eq "boolean"} {
        ttk::checkbutton $parent.w$row -variable ::GX::modulePlotCfg($id,$graph,$key)
    } elseif {$type eq "choice"} {
        ttk::combobox $parent.w$row -textvariable ::GX::modulePlotCfg($id,$graph,$key) -values [splitList [moduleGraphConfigField $id $graph $key values ""]] -state readonly -width 34
    } else {
        ttk::entry $parent.w$row -textvariable ::GX::modulePlotCfg($id,$graph,$key) -width 38
    }
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}
proc ::GX::buildModulePlotConfigFrame {parent id} {
    set outerRow 0
    foreach graph [moduleGraphIds $id] {
        ttk::labelframe $parent.g$outerRow -text "[moduleGraphField $id $graph name $graph]  ($graph)"
        grid $parent.g$outerRow -row $outerRow -column 0 -sticky ew -padx 3 -pady 3
        grid columnconfigure $parent.g$outerRow 1 -weight 1
        set rr 0
        foreach key [moduleGraphConfigKeys $id $graph] {
            modulePlotConfigWidget $parent.g$outerRow $id $graph $key $rr
            incr rr
        }
        incr outerRow
    }
    return $outerRow
}

# Rebuild Analysis with no inherited legacy row weights and with descriptor-
# generated plot controls. This also fixes the large blank area seen in v0.6.1.
proc ::GX::rebuildNativeAnalysisGui_v071_graphs_last {} {
    variable moduleOrder
    variable moduleRun
    variable moduleBinding
    set f .top.nb.analysis
    destroyChildren $f
    for {set r 0} {$r < 50} {incr r} { catch {grid rowconfigure $f $r -weight 0} }
    grid columnconfigure $f 0 -weight 1
    set row 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        ttk::labelframe $f.m$row -text "[moduleField $id name $id]  ($id)"
        grid $f.m$row -row $row -column 0 -sticky new -padx 6 -pady 6
        grid columnconfigure $f.m$row 1 -weight 1
        ttk::checkbutton $f.m$row.enabled -text "Enabled in experiment" -variable ::GX::moduleEnabled($id) -command [list ::GX::nativeModuleToggle $id]
        ttk::checkbutton $f.m$row.run -text "Run / recalculate now" -variable ::GX::moduleRun($id) -command ::GX::refreshManifestPreview
        grid $f.m$row.enabled -row 0 -column 0 -sticky w -padx 4 -pady 3
        grid $f.m$row.run -row 0 -column 1 -sticky w -padx 4 -pady 3
        ttk::labelframe $f.m$row.cfg -text "Calculation configuration"
        grid $f.m$row.cfg -row 1 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
        buildStandardConfigFrame $f.m$row.cfg $id
        set br 2
        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            ttk::labelframe $f.m$row.bind -text "Input variable bindings"
            grid $f.m$row.bind -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $f.m$row.bind 1 -weight 1
            set vals [linsert [sourceVariableNames] 0 auto]
            set rr 0
            foreach role $roles {
                ttk::label $f.m$row.bind.l$rr -text [moduleBindingField $id $role label $role]
                ttk::combobox $f.m$row.bind.w$rr -textvariable ::GX::moduleBinding($id,$role) -values $vals -state readonly -width 30
                grid $f.m$row.bind.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2
                grid $f.m$row.bind.w$rr -row $rr -column 1 -sticky w -padx 4 -pady 2
                incr rr
            }
            incr br
        }
        if {[llength [moduleGraphIds $id]]} {
            ttk::labelframe $f.m$row.plots -text "Graphs offered by module (Graph Provider API v1)"
            grid $f.m$row.plots -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $f.m$row.plots 0 -weight 1
            buildModulePlotConfigFrame $f.m$row.plots $id
        }
        incr row
    }
    if {$row == 0} { ttk::label $f.none -text "No Standard Module API analysis modules are installed."; grid $f.none -row 0 -column 0 -padx 8 -pady 8 }
    grid rowconfigure $f $row -weight 1
    refreshNativeAnalysisState
}

proc ::GX::refreshNativeAnalysisState_v078_rows {} {
    ::GX::refreshNativeAnalysisState_v061_base
    variable moduleOrder
    set row 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        set base .top.nb.analysis.m$row
        if {[winfo exists $base.plots]} { setWidgetTreeState $base.plots [moduleIsEnabled $id] }
        incr row
    }
}

# Manifest format 2 extension: richer experiment text, instrument module
# instances, and per-module plot configuration are configuration state.
proc ::GX::manifestStringV2_v062_legend_base {} {
    variable cfg
    variable moduleOrder
    variable moduleCfg
    variable moduleBinding
    variable modulePlotCfg
    variable instruments
    variable instrumentCount
    variable sourceVar
    variable sourceVarCount
    set out "; GX-TXT Pipeline manifest format 2\n; SPDX-License-Identifier: GPL-3.0-or-later\n"
    append out "\n\[pipeline\]\n"; appendKV out format 2; appendKV out application_version $::GX::version; appendKV out module_api_version 1; appendKV out instrument_api_version 1
    append out "\n\[runtime\]\n"; appendKV out octave_cmd $cfg(octave_cmd); appendKV out cpu_count $cfg(cpu_count); appendKV out worker_file $cfg(worker_file)
    append out "\n\[acquisition\]\n"; appendKV out module_id $cfg(acquisition_module); appendKV out input_csv $cfg(input_csv); appendKV out session_root $cfg(output_root); appendKV out session_name $cfg(session_name)
    append out "\n\[session\]\n"; appendKV out mode $cfg(session_mode)
    append out "\n\[experiment\]\n"
    foreach {key cfgkey} {name experiment_name project experiment_project date experiment_date operator experiment_operator tags experiment_tags notes experiment_notes objective experiment_objective procedure experiment_procedure observations experiment_observations} { appendKV out $key $cfg($cfgkey) }
    append out "\n\[instrument_modules\]\n"; appendKV out api_version 1; appendKV out count $instrumentCount
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        append out "\n\[instrument_module_instance.$i\]\n"
        foreach k {enabled module_id id display_name} { appendKV out $k $instruments($i,$k) }
        set mid $instruments($i,module_id)
        foreach key [instrumentModuleFieldKeys $mid] { appendKV out "field.$key" $instruments($i,field,$key) }
    }
    append out "\n\[source_variables\]\n"; appendKV out count $sourceVarCount
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        append out "\n\[source_variable.$i\]\n"
        foreach k {enabled source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} { appendKV out $k $sourceVar($i,$k) }
    }
    append out "\n\[module_state\]\n"; appendKV out enabled [join [selectedModuleIds] ,]; appendKV out run [join [selectedRunModuleIds] ,]
    foreach id $moduleOrder {
        set keys [moduleConfigKeys $id]
        if {[llength $keys]} {
            append out "\n\[module_config.$id\]\n"
            foreach key $keys {if {[configurationModuleShouldPersist $id $key]} {appendKV out $key $moduleCfg($id,$key)}}
        }
        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            append out "\n\[module_binding.$id\]\n"
            foreach role $roles { appendKV out $role $moduleBinding($id,$role) }
        }
        foreach graph [moduleGraphIds $id] {
            if {![llength [moduleGraphConfigKeys $id $graph]]} continue
            append out "\n\[module_plot.$id.$graph\]\n"
            foreach key [moduleGraphConfigKeys $id $graph] { appendKV out $key $modulePlotCfg($id,$graph,$key) }
        }
    }
    append out "\n\[graphics\]\n"
    foreach key {graphics_mode graphics_toolkit graphics_display graphics_visible plot_width_px plot_height_px plot_font_unit plot_font_size plot_axis_label_font_size plot_title_font_size plot_line_width plot_grid plot_grid_mode plot_grid_color plot_background plot_legend_mode plot_legend_location plot_legend_layout plot_legend_alignment plot_legend_columns plot_legend_font_unit plot_legend_font_size plot_legend_background plot_legend_border plot_legend_external_border plot_legend_border_color plot_legend_external_margin_px plot_legend_manual_x plot_legend_manual_y analysis_png_dpi} { if {[info exists cfg($key)]} { appendKV out $key $cfg($key) } }
    append out "\n\[print\]\n"
    foreach key {print_page print_orientation print_rows print_cols print_margin_mm print_gap_mm print_captions print_title print_output_pdf print_printer print_copies print_duplex export_dir} { if {[info exists cfg($key)]} { appendKV out $key $cfg($key) } }
    return $out
}

# Keep the public manifestString mapped to the extended generator.
proc ::GX::manifestString {} { return [manifestStringV2] }

proc ::GX::loadManifestV2_v062_legend_base {path} {
    variable cfg
    variable instruments
    variable instrumentCount
    variable moduleOrder
    variable modulePlotCfg
    ::GX::loadManifestV2_v061_base $path
    set d [parseIni $path]
    foreach {dk ck} {experiment.operator experiment_operator experiment.tags experiment_tags experiment.objective experiment_objective experiment.procedure experiment_procedure experiment.observations experiment_observations} {
        if {[dict exists $d $dk]} { set cfg($ck) [dict get $d $dk] }
    }
    # Prefer Instrument Module API instances when present.
    if {[dict exists $d instrument_modules.count]} {
        clearInstruments
        set instrumentCount [dict get $d instrument_modules.count]
        if {![string is integer -strict $instrumentCount] || $instrumentCount < 0} { set instrumentCount 0 }
        for {set i 1} {$i <= $instrumentCount} {incr i} {
            set pre "instrument_module_instance.$i"
            foreach {k def} {enabled 1 module_id instrument.generic id "" display_name ""} {
                set dk "$pre.$k"; set instruments($i,$k) [expr {[dict exists $d $dk] ? [dict get $d $dk] : $def}]
            }
            foreach {ck cv} {type "" role "" manufacturer "" model "" serial "" firmware "" notes ""} { if {![info exists instruments($i,$ck)]} { set instruments($i,$ck) $cv } }
            set mid $instruments($i,module_id)
            foreach key [instrumentModuleFieldKeys $mid] {
                set dk "$pre.field.$key"
                set instruments($i,field,$key) [expr {[dict exists $d $dk] ? [dict get $d $dk] : [instrumentModuleField $mid $key default ""]}]
            }
        }
    }
    if {![dict exists $d instrument_modules.count] && $instrumentCount > 0} {
        # Read-only migration of v0.6.0/v0.6.1 fixed instrument rows into
        # generic Instrument Module API instances.
        for {set i 1} {$i <= $instrumentCount} {incr i} {
            set instruments($i,module_id) instrument.generic
            if {![info exists instruments($i,display_name)] || $instruments($i,display_name) eq ""} { set instruments($i,display_name) $instruments($i,id) }
            foreach key [instrumentModuleFieldKeys instrument.generic] {
                if {[info exists instruments($i,$key)]} { set instruments($i,field,$key) $instruments($i,$key) } else { set instruments($i,field,$key) [instrumentModuleField instrument.generic $key default ""] }
            }
        }
    }
    foreach id $moduleOrder {
        foreach graph [moduleGraphIds $id] {
            foreach key [moduleGraphConfigKeys $id $graph] {
                set dk "module_plot.$id.$graph.$key"
                if {[dict exists $d $dk]} { set modulePlotCfg($id,$graph,$key) [dict get $d $dk] }
            }
        }
    }
    catch {refreshNativeInstrumentationGui}
    catch {rebuildNativeExperimentGui}
    catch {rebuildNativeAnalysisGui}
}

# Runtime receives module-specific plot configuration as declared by the module.
proc ::GX::writeStandardRuntimeConfig_v063_legend_runtime_base {id} {
    variable modulePlotCfg
    set path [::GX::writeStandardRuntimeConfig_v061_base $id]
    if {![llength [moduleGraphIds $id]]} { return $path }
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    foreach graph [moduleGraphIds $id] {
        puts $fd "\n\[plot.$graph\]"
        foreach key [moduleGraphConfigKeys $id $graph] { putKV $fd $key $modulePlotCfg($id,$graph,$key) }
    }
    close $fd
    return $path
}

# Ensure the native GUI uses all v0.6.2 builders after the historical GUI exists.
proc ::GX::augmentStandardGui_annotation_base {} {
    ::GX::augmentStandardGui_v061_base
    refreshNativeInstrumentationGui
    rebuildNativeExperimentGui
    rebuildNativeAnalysisGui
}


# -----------------------------------------------------------------------------
# v0.6.3 generic legend-editor integration for descriptor-defined plots
# -----------------------------------------------------------------------------

# Native plot paths are resolved from the module descriptor instead of requiring
# a core hard-coded filename switch. Legacy graph keys remain available through
# the historical resolver for older sessions/tools outside the native-only set.
proc ::GX::nativeGraphInfoForPath_before_plot_variant {path} {
    variable currentSession
    variable moduleOrder
    if {$currentSession eq ""} { return {} }
    set session [file normalize $currentSession]
    set p [file normalize $path]
    set analysisRoot [file normalize [file join $session analysis]]
    if {[string first "$analysisRoot/" "$p/"] != 0} { return {} }
    set rel [string range $p [expr {[string length $analysisRoot] + 1}] end]
    set parts [file split $rel]
    if {[llength $parts] < 2} { return {} }
    set moduleId [lindex $parts 0]
    if {[lsearch -exact $moduleOrder $moduleId] < 0} { return {} }
    set base [file tail $p]
    foreach graph [moduleGraphIds $moduleId] {
        set declared [string trim [moduleGraphField $moduleId $graph file ""]]
        if {$declared ne "" && $base eq [file tail $declared]} {
            return [list $moduleId $graph]
        }
    }
    return {}
}
proc ::GX::graphKeyForPath_before_plot_variant {path} {
    set native [nativeGraphInfoForPath $path]
    if {[llength $native] == 2} { return [lindex $native 1] }
    return [::GX::graphKeyForPath_v062_legacy $path]
}

proc ::GX::graphKeyForPath {path} {
    return [::GX::graphKeyForPath_before_plot_variant $path]
}

proc ::GX::graphSupportsLegend {path} {
    set native [nativeGraphInfoForPath $path]
    if {[llength $native] == 2} {
        lassign $native moduleId graph
        set enabled [string tolower [string trim [moduleGraphField $moduleId $graph supports_legend "0"]]]
        set editor [string tolower [string trim [moduleGraphField $moduleId $graph legend_editor "none"]]]
        return [expr {$enabled in {1 true yes on} && $editor ne "none"}]
    }
    return [::GX::graphSupportsLegend_v062_legacy $path]
}

# The native-only plot environment deliberately excludes all legacy IR/HOLD/
# compare variables, but it must still carry the common plot-editor resources.
# In particular, legend overrides are written to a session-local TSV and passed
# to both calculation rendering and rerendering.
proc ::GX::plotEnv_v072_global_graphics {} {
    set out [::GX::plotEnv_v062_native_legend_base]
    set lof [writeLegendOverrideFile]
    if {$lof ne ""} { lappend out "GXTXT_PLOT_LEGEND_OVERRIDE_FILE=$lof" }
    return $out
}

# Manifest Format 2 now persists the same per-plot legend overrides used by the
# Plots-tab legend editor. They are presentation state, independent of the
# module's semantic legend-content choice (for example family_only).
proc ::GX::manifestStringV2_annotation_base {} {
    variable legendOverride
    set out [::GX::manifestStringV2_v062_legend_base]
    set keys {}
    foreach k [array names legendOverride "*,enabled"] {
        set gk [string range $k 0 end-8]
        if {[lsearch -exact $keys $gk] < 0} { lappend keys $gk }
    }
    append out "\n\[plot.legend.overrides\]\n"
    appendKV out keys [join [lsort $keys] ","]
    foreach gk [lsort $keys] {
        append out "\n\[plot.legend.$gk\]\n"
        foreach field {enabled mode placement location alignment orientation layout columns background border border_color font_unit font_size external_margin_px manual_x manual_y} {
            set v [expr {[info exists legendOverride($gk,$field)] ? $legendOverride($gk,$field) : ""}]
            appendKV out $field $v
        }
    }
    return $out
}

proc ::GX::loadManifestV2_annotation_base {path} {
    variable legendOverride
    ::GX::loadManifestV2_v062_legend_base $path
    set d [parseIni $path]
    array unset legendOverride *
    if {[dict exists $d "plot.legend.overrides.keys"]} {
        foreach gk [split [dict get $d "plot.legend.overrides.keys"] ","] {
            set gk [string trim $gk]
            if {$gk eq ""} continue
            foreach {field def} {enabled 1 mode "" placement "" location "" alignment "" orientation "" layout "" columns "" background "" border "" border_color "" font_unit "" font_size "" external_margin_px "" manual_x "" manual_y ""} {
                set dk "plot.legend.$gk.$field"
                set legendOverride($gk,$field) [expr {[dict exists $d $dk] ? [dict get $d $dk] : $def}]
            }
        }
    }
    catch {writeLegendOverrideFile}
}

# -----------------------------------------------------------------------------
# v0.6.4 native presentation-state hardening
# -----------------------------------------------------------------------------
# Every native rerender must receive the *current* GUI state.  Reusing an old
# runtime.ini made module-specific plot settings and legend state potentially
# stale.  Legend overrides are now also serialized into runtime.ini, so native
# renderers do not rely solely on process-environment propagation.
proc ::GX::writeStandardRuntimeConfig_v070_graph_provider_base {id} {
    variable legendOverride
    set path [::GX::writeStandardRuntimeConfig_v063_legend_runtime_base $id]
    if {![llength [moduleGraphIds $id]]} { return $path }
    set fd [open $path a]
    fconfigure $fd -encoding utf-8 -translation lf
    foreach graph [moduleGraphIds $id] {
        puts $fd "\n\[legend.$graph\]"
        set has [info exists legendOverride($graph,enabled)]
        putKV $fd enabled [expr {$has ? $legendOverride($graph,enabled) : 0}]
        foreach field {mode placement location alignment orientation layout columns background border border_color font_unit font_size external_margin_px manual_x manual_y} {
            set v [expr {[info exists legendOverride($graph,$field)] ? $legendOverride($graph,$field) : ""}]
            putKV $fd $field $v
        }
    }
    close $fd
    return $path
}

# Refresh runtime.ini before *every* native rerender.  The underlying queue
# builder can then use the file as usual, but it is guaranteed to represent the
# current module/plot/legend GUI state rather than the state of the last fit.
proc ::GX::buildStandardRerenderQueue_v077 {paths} {
    variable moduleOrder
    variable currentSession
    if {$currentSession ne ""} {
        foreach id $moduleOrder {
            if {[moduleField $id runner ""] ne "standard_octave"} continue
            set outDir [file normalize [file join $currentSession analysis [sanitize $id]]]
            set hit 0
            foreach p $paths {
                set pn [file normalize $p]
                if {[string first "$outDir/" "$pn/"] == 0 || [file dirname $pn] eq $outDir} {
                    set hit 1
                    break
                }
            }
            if {!$hit} continue
            if {![file isfile [file join $outDir render_cache.mat]]} continue
            # Let the normal error path report configuration/dataset problems.
            writeStandardRuntimeConfig $id
        }
    }
    return [::GX::buildStandardRerenderQueue_v063_runtime_base $paths]
}

# Plot Annotation API v1 is a presentation-layer extension. It is loaded last so
# it can wrap the final manifest/GUI/preview/print functions without altering the
# acquisition or analysis contracts.
source [file join $::GX::scriptDir services annotations annotation_api_v1.tcl]


# -----------------------------------------------------------------------------
# v0.7.1 Graph Provider API v1
# -----------------------------------------------------------------------------
# A module descriptor declares every plot type it can offer under [graphs] /
# [graph.<id>].  The experiment selects which offered plots are generated.
# This keeps plot discovery in the module and plot selection/persistence in the
# framework. Graph IDs are fixed plot types. Opt-in Plot Module variants add
# persistent configurations without inventing dynamic provider IDs.

namespace eval ::GX {
    variable graphProviderApiVersion 1
    variable moduleGraphEnabled
}

proc ::GX::moduleGraphDefaultEnabled {id graph} {
    set raw [string tolower [string trim [moduleGraphField $id $graph default_enabled ""]]]
    if {$raw ne ""} { return [expr {$raw in {1 true yes on}}] }
    set defaults [splitList [moduleField $id graph_defaults ""]]
    if {[llength $defaults]} { return [expr {[lsearch -exact $defaults $graph] >= 0}] }
    return 1
}

proc ::GX::ensureModuleGraphDefaults {} {
    variable moduleOrder
    variable moduleGraphEnabled
    foreach id $moduleOrder {
        foreach graph [moduleGraphIds $id] {
            if {![info exists moduleGraphEnabled($id,$graph)]} {
                set moduleGraphEnabled($id,$graph) [moduleGraphDefaultEnabled $id $graph]
            }
        }
    }
}

proc ::GX::loadModuleCatalog_v077 {} {
    ::GX::loadModuleCatalog_v070_graph_provider_base
    variable moduleOrder
    variable moduleCatalog
    foreach id $moduleOrder {
        # Optional Graph Provider metadata.  Existing descriptors remain valid.
        if {[info exists moduleCatalog($id,dict)]} {
            set moduleCatalog($id,graph_provider_api) [descriptorValue $moduleCatalog($id,dict) graphs provider_api_version ""]
            set moduleCatalog($id,graph_defaults) [descriptorValue $moduleCatalog($id,dict) graphs default_ids ""]
        }
    }
    ensureModuleGraphDefaults
}

proc ::GX::defaults_v072_module_graphics_base {} {
    variable moduleGraphEnabled
    ::GX::defaults_v070_graph_provider_base
    array unset moduleGraphEnabled *
}

proc ::GX::moduleGraphIsEnabled {id graph} {
    variable moduleGraphEnabled
    if {[info exists moduleGraphEnabled($id,$graph)]} { return [expr {$moduleGraphEnabled($id,$graph) ? 1 : 0}] }
    return [moduleGraphDefaultEnabled $id $graph]
}

proc ::GX::activeModuleGraphIds {id} {
    set out {}
    foreach graph [moduleGraphIds $id] {
        if {[moduleGraphIsEnabled $id $graph]} { lappend out $graph }
    }
    return $out
}

proc ::GX::moduleExpectedOutputs_before_graph_workflow {id} {
    set out [splitList [moduleField $id outputs ""]]
    foreach graph [activeModuleGraphIds $id] {
        set f [string trim [moduleGraphField $id $graph file ""]]
        if {$f ne "" && [lsearch -exact $out $f] < 0} { lappend out $f }
    }
    return [join $out ";"]
}
proc ::GX::moduleExpectedOutputs {id} {
    tailcall ::GX::moduleExpectedOutputs_before_graph_workflow $id
}

proc ::GX::moduleGraphToggle {id graph} {
    variable moduleGraphEnabled
    set moduleGraphEnabled($id,$graph) [expr {$moduleGraphEnabled($id,$graph) ? 0 : 1}]
    refreshManifestPreview
}

# Replace the plot-config frame with a provider-aware view.  Every descriptor
# graph is an offering from the module; the user explicitly includes/excludes
# it from the experiment.  Plot-specific controls remain descriptor-generated.
proc ::GX::buildModulePlotConfigFrame_v071_expanded {parent id} {
    variable moduleGraphEnabled
    set outerRow 0
    foreach graph [moduleGraphIds $id] {
        ttk::labelframe $parent.g$outerRow -text "[moduleGraphField $id $graph name $graph]  ($graph)"
        grid $parent.g$outerRow -row $outerRow -column 0 -sticky ew -padx 3 -pady 3
        grid columnconfigure $parent.g$outerRow 1 -weight 1
        ttk::checkbutton $parent.g$outerRow.enable -text "Add / generate this plot" \
            -variable ::GX::moduleGraphEnabled($id,$graph) -command ::GX::refreshManifestPreview
        grid $parent.g$outerRow.enable -row 0 -column 0 -columnspan 2 -sticky w -padx 4 -pady 3
        set rr 1
        foreach key [moduleGraphConfigKeys $id $graph] {
            modulePlotConfigWidget $parent.g$outerRow $id $graph $key $rr
            incr rr
        }
        incr outerRow
    }
    return $outerRow
}

# Persist selected graph offerings after every other Manifest Format 2 extension
# (including annotations) has added its own sections.
proc ::GX::manifestStringV2_v072_module_graphics_base {} {
    variable moduleOrder
    variable graphProviderApiVersion
    set out [::GX::manifestStringV2_v070_graph_provider_base]
    append out "\n\[graph_provider_api\]\n"
    appendKV out version $graphProviderApiVersion
    appendKV out model "module-declared graph types; optional persistent plot variants"
    foreach id $moduleOrder {
        set offered [moduleGraphIds $id]
        if {![llength $offered]} continue
        append out "\n\[module_graphs.$id\]\n"
        appendKV out offered [join $offered ","]
        appendKV out enabled [join [activeModuleGraphIds $id] ","]
    }
    return $out
}

proc ::GX::loadManifestV2_v072_module_graphics_base {path} {
    variable moduleOrder
    variable moduleGraphEnabled
    ::GX::loadManifestV2_v070_graph_provider_base $path
    set d [parseIni $path]
    foreach id $moduleOrder {
        set offered [moduleGraphIds $id]
        if {![llength $offered]} continue
        set k "module_graphs.$id.enabled"
        if {[dict exists $d $k]} {
            set enabled [splitList [dict get $d $k]]
            foreach graph $offered { set moduleGraphEnabled($id,$graph) [expr {[lsearch -exact $enabled $graph] >= 0}] }
        }
    }
    catch {rebuildNativeAnalysisGui}
}

# The runtime tells the module exactly which of its declared graph offerings
# must be rendered.  A renderer never guesses from filenames or GUI state.
proc ::GX::writeStandardRuntimeConfig_v072_module_graphics_base {id} {
    variable graphProviderApiVersion
    set path [::GX::writeStandardRuntimeConfig_v070_graph_provider_base $id]
    if {![llength [moduleGraphIds $id]]} { return $path }
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[graph_provider\]"
    putKV $fd api_version $graphProviderApiVersion
    putKV $fd offered [join [moduleGraphIds $id] ";"]
    putKV $fd enabled [join [activeModuleGraphIds $id] ";"]
    close $fd
    return $path
}

# -----------------------------------------------------------------------------
# v0.7.2 Graph Provider GUI hardening
# -----------------------------------------------------------------------------
# v0.7.1 correctly propagated graph selections through manifest/runtime, but
# expanded every graph's complete configuration directly in Analysis.  On a
# normal desktop this pushed graph offerings below the visible area because the
# Analysis page itself is not scrollable.  v0.7.2 keeps provider selection
# compact: one row per offered graph plus a Configure... dialog.

proc ::GX::moduleGraphConfigDialog_before_graph_workflow {id graph} {
    set w .modulegraphcfg
    catch {destroy $w}
    toplevel $w
    wm title $w "Graph configuration - [moduleGraphField $id $graph name $graph]"
    wm transient $w .
    grid columnconfigure $w 0 -weight 1
    ttk::label $w.title -text "[moduleGraphField $id $graph name $graph]  ($graph)" -font TkHeadingFont
    grid $w.title -row 0 -column 0 -sticky w -padx 8 -pady {8 4}
    ttk::label $w.file -text "Output: [moduleGraphField $id $graph file \"\"]" -foreground #555555
    grid $w.file -row 1 -column 0 -sticky w -padx 8 -pady {0 6}
    ttk::frame $w.body
    grid $w.body -row 2 -column 0 -sticky nsew -padx 8 -pady 4
    grid columnconfigure $w.body 1 -weight 1
    set rr 0
    foreach key [moduleGraphConfigKeys $id $graph] {
        modulePlotConfigWidget $w.body $id $graph $key $rr
        incr rr
    }
    if {$rr == 0} {
        ttk::label $w.body.none -text "This graph has no module-specific parameters."
        grid $w.body.none -row 0 -column 0 -columnspan 2 -sticky w -pady 8
    }
    ttk::frame $w.buttons
    grid $w.buttons -row 3 -column 0 -sticky e -padx 8 -pady 8
    ttk::button $w.buttons.close -text "Close" -command [list destroy $w]
    grid $w.buttons.close -row 0 -column 0 -padx 4
    bind $w <Escape> [list destroy $w]
    catch {wm minsize $w 520 200}
    return $w
}
proc ::GX::moduleGraphConfigDialog {id graph} {
    tailcall ::GX::moduleGraphConfigDialog_before_graph_workflow $id $graph
}

proc ::GX::moduleGraphSetAll {id value} {
    variable moduleGraphEnabled
    foreach graph [moduleGraphIds $id] { set moduleGraphEnabled($id,$graph) [expr {$value ? 1 : 0}] }
    refreshManifestPreview
}

proc ::GX::buildModulePlotConfigFrame_v072_common_graphics_base {parent id} {
    variable moduleGraphEnabled
    set offered [moduleGraphIds $id]
    if {![llength $offered]} { return 0 }

    ttk::label $parent.hint -text "Select the plots this module will generate. Configure... edits only that plot; selection is saved in Manifest Format 2 and passed to the module runtime." -wraplength 1050 -justify left
    grid $parent.hint -row 0 -column 0 -columnspan 4 -sticky ew -padx 4 -pady {3 6}
    grid columnconfigure $parent 1 -weight 1
    set row 1
    foreach graph $offered {
        ttk::checkbutton $parent.e$row -variable ::GX::moduleGraphEnabled($id,$graph) -command ::GX::refreshManifestPreview
        ttk::label $parent.n$row -text [moduleGraphField $id $graph name $graph]
        ttk::label $parent.f$row -text [moduleGraphField $id $graph file ""] -foreground #666666
        ttk::button $parent.c$row -text "Configure..." -command [list ::GX::moduleGraphConfigDialog $id $graph]
        grid $parent.e$row -row $row -column 0 -sticky w -padx {5 2} -pady 2
        grid $parent.n$row -row $row -column 1 -sticky w -padx 2 -pady 2
        grid $parent.f$row -row $row -column 2 -sticky w -padx 8 -pady 2
        grid $parent.c$row -row $row -column 3 -sticky e -padx 4 -pady 2
        incr row
    }
    ttk::frame $parent.actions
    ttk::button $parent.actions.all -text "Enable all" -command [list ::GX::moduleGraphSetAll $id 1]
    ttk::button $parent.actions.none -text "Disable all" -command [list ::GX::moduleGraphSetAll $id 0]
    grid $parent.actions.all -row 0 -column 0 -padx 3
    grid $parent.actions.none -row 0 -column 1 -padx 3
    grid $parent.actions -row $row -column 0 -columnspan 4 -sticky w -padx 4 -pady {5 4}
    return [expr {$row+1}]
}

# Keep graph selection visible before the longer calculation/binding sections.
# This is a presentation-only reorder; the descriptor/runtime contracts are unchanged.
proc ::GX::rebuildNativeAnalysisGui_v078_all_modules {} {
    ::GX::rebuildNativeAnalysisGui_v071_graphs_last
    variable moduleOrder
    set row 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        set base .top.nb.analysis.m$row
        if {[winfo exists $base.plots]} { grid configure $base.plots -row 1 }
        if {[winfo exists $base.cfg]}   { grid configure $base.cfg   -row 2 }
        if {[winfo exists $base.bind]}  { grid configure $base.bind  -row 3 }
        incr row
    }
}


# -----------------------------------------------------------------------------
# v0.7.4 common graphics inheritance: global -> module -> plot-specific
# -----------------------------------------------------------------------------
# Global [graphics] is authoritative by default.  A module may opt into a
# presentation override without redefining scientific plot semantics.  The
# effective environment is resolved per module before Octave starts.  Existing
# per-plot legend overrides remain the final layer for legend-only settings.
namespace eval ::GX {
    variable moduleGraphicsOverride
    variable moduleGraphicsApiVersion 1
}

proc ::GX::defaults_v081_before_v082_state {} {
    variable moduleGraphicsOverride
    ::GX::defaults_v072_module_graphics_base
    array unset moduleGraphicsOverride *
}

proc ::GX::moduleGraphicsFields_v0933_before_3d {} {
    return {width_px height_px dpi font_unit font_size axis_label_font_size title_font_size line_width grid_mode grid_color background legend_placement legend_inside_preset legend_layout legend_alignment legend_columns legend_font_unit legend_font_size legend_background legend_border legend_border_color legend_margin_px}
}
proc ::GX::moduleGraphicsFields {} { ::GX::moduleGraphicsFields_v0933_before_3d }
proc ::GX::moduleGraphicsEnsure {id} {
    variable moduleGraphicsOverride
    if {![info exists moduleGraphicsOverride($id,enabled)]} { set moduleGraphicsOverride($id,enabled) 0 }
    foreach f [moduleGraphicsFields] { if {![info exists moduleGraphicsOverride($id,$f)]} { set moduleGraphicsOverride($id,$f) "" } }
}
proc ::GX::moduleGraphicsParentLegendUnitForGraph {graphId globalUnit} {
    variable moduleOrder
    variable moduleGraphicsOverride
    foreach id $moduleOrder {
        if {[lsearch -exact [moduleGraphIds $id] $graphId] < 0} continue
        moduleGraphicsEnsure $id
        if {!$moduleGraphicsOverride($id,enabled)} { return $globalUnit }
        set lfu [string tolower [string trim $moduleGraphicsOverride($id,legend_font_unit)]]
        if {$lfu in {px pt}} { return $lfu }
        set fu [string tolower [string trim $moduleGraphicsOverride($id,font_unit)]]
        if {$fu in {px pt}} { return $fu }
        return $globalUnit
    }
    return $globalUnit
}

proc ::GX::moduleGraphicsEnvMap_v0933_before_3d {} {
    return [dict create \
        width_px GXTXT_PLOT_WIDTH_PX height_px GXTXT_PLOT_HEIGHT_PX dpi GXTXT_PNG_DPI \
        font_unit GXTXT_PLOT_FONT_UNIT font_size GXTXT_PLOT_FONT_SIZE \
        axis_label_font_size GXTXT_PLOT_AXIS_LABEL_FONT_SIZE title_font_size GXTXT_PLOT_TITLE_FONT_SIZE \
        line_width GXTXT_PLOT_LINE_WIDTH grid_mode GXTXT_PLOT_GRID_MODE grid_color GXTXT_PLOT_GRID_COLOR \
        background GXTXT_PLOT_BACKGROUND legend_placement GXTXT_PLOT_LEGEND_MODE \
        legend_inside_preset GXTXT_PLOT_LEGEND_LOCATION legend_layout GXTXT_PLOT_LEGEND_LAYOUT \
        legend_alignment GXTXT_PLOT_LEGEND_ALIGNMENT legend_columns GXTXT_PLOT_LEGEND_COLUMNS \
        legend_font_unit GXTXT_PLOT_LEGEND_FONT_UNIT legend_font_size GXTXT_PLOT_LEGEND_FONT_SIZE \
        legend_background GXTXT_PLOT_LEGEND_BACKGROUND legend_border GXTXT_PLOT_LEGEND_BORDER \
        legend_border_color GXTXT_PLOT_LEGEND_BORDER_COLOR legend_margin_px GXTXT_PLOT_LEGEND_EXTERNAL_MARGIN_PX]
}
proc ::GX::moduleGraphicsEnvMap {} { ::GX::moduleGraphicsEnvMap_v0933_before_3d }
proc ::GX::envListReplace {lst name value} {
    set out {}; set done 0
    foreach item $lst {
        if {[string match "$name=*" $item]} { lappend out "$name=$value"; set done 1 } else { lappend out $item }
    }
    if {!$done} { lappend out "$name=$value" }
    return $out
}
proc ::GX::plotEnv_v079_before_axis_override_fix {{moduleId ""}} {
    variable moduleGraphicsOverride
    set out [::GX::plotEnv_v072_global_graphics]
    if {$moduleId eq ""} { return $out }
    moduleGraphicsEnsure $moduleId
    if {!$moduleGraphicsOverride($moduleId,enabled)} { return $out }
    set map [moduleGraphicsEnvMap]
    foreach f [moduleGraphicsFields] {
        set v [string trim $moduleGraphicsOverride($moduleId,$f)]
        if {$v eq "" || $v eq "inherit"} continue
        if {[dict exists $map $f]} { set out [envListReplace $out [dict get $map $f] $v] }
    }
    return $out
}

proc ::GX::moduleGraphicsDialog_v0933_before_3d {id} {
    variable moduleGraphicsOverride
    moduleGraphicsEnsure $id
    set w .modulegfx
    catch {destroy $w}
    toplevel $w
    wm title $w "Module graphics override - [moduleField $id name $id]"
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::checkbutton $w.en -text "Override global graphics for this module" -variable ::GX::moduleGraphicsOverride($id,enabled)
    grid $w.en -row 0 -column 0 -columnspan 3 -sticky w -padx 8 -pady {8 5}
    ttk::label $w.note -text "Blank or inherit = use Global graphics. These values affect every graph generated by this module. Plot-specific legend settings remain the final override." -wraplength 720 -justify left
    grid $w.note -row 1 -column 0 -columnspan 3 -sticky ew -padx 8 -pady {0 6}
    set r 2
    foreach spec {
        {"Output width [px]" width_px entry}
        {"Output height [px]" height_px entry}
        {"Output DPI" dpi entry}
        {"Default font unit" font_unit {inherit px pt}}
        {"Axis tick font size" font_size entry}
        {"Axis-label font size" axis_label_font_size entry}
        {"Title font size" title_font_size entry}
        {"Line width" line_width entry}
        {"Grid mode" grid_mode {inherit both vertical horizontal none}}
        {"Grid color" grid_color entry}
        {"Background" background entry}
        {"Legend placement" legend_placement {inherit none inside below above right left manual}}
        {"Legend inside preset" legend_inside_preset {inherit north northeast east southeast south southwest west northwest}}
        {"Legend layout" legend_layout {inherit auto row stacked wrapped}}
        {"Legend alignment" legend_alignment {inherit start center end}}
        {"Legend columns" legend_columns entry}
        {"Legend font unit" legend_font_unit {inherit px pt}}
        {"Legend font size" legend_font_size entry}
        {"Legend background" legend_background entry}
        {"Legend border" legend_border {inherit 0 1}}
        {"Legend border color" legend_border_color entry}
        {"Legend/plot distance [px]" legend_margin_px entry}
    } {
        lassign $spec label field kind
        ttk::label $w.l$r -text $label
        if {$kind eq "entry"} {
            ttk::entry $w.e$r -textvariable ::GX::moduleGraphicsOverride($id,$field) -width 18
        } else {
            ttk::combobox $w.e$r -textvariable ::GX::moduleGraphicsOverride($id,$field) -values $kind -state readonly -width 18
        }
        ttk::label $w.h$r -text "inherit global" -foreground #666666
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 2
        grid $w.e$r -row $r -column 1 -sticky w -padx 5 -pady 2
        grid $w.h$r -row $r -column 2 -sticky w -padx 5 -pady 2
        incr r
    }
    ttk::frame $w.b
    ttk::button $w.b.save -text "Save" -command [list ::GX::moduleGraphicsSave $w $id]
    ttk::button $w.b.cancel -text "Cancel" -command [list destroy $w]
    pack $w.b.save $w.b.cancel -side left -padx 4
    grid $w.b -row $r -column 0 -columnspan 3 -pady 8
    bind $w <Escape> [list destroy $w]
    catch {wm minsize $w 640 620}
}
proc ::GX::moduleGraphicsDialog {id} { ::GX::moduleGraphicsDialog_v0933_before_3d $id }
proc ::GX::moduleGraphicsSave_v0933_before_3d {w id} {
    variable moduleGraphicsOverride
    foreach f {width_px height_px dpi font_size axis_label_font_size title_font_size line_width legend_columns legend_font_size legend_margin_px} {
        set v [string trim $moduleGraphicsOverride($id,$f)]
        if {$v eq "" || $v eq "inherit"} continue
        if {![string is double -strict $v] || $v <= 0} { tk_messageBox -parent $w -icon error -message "$f must be a positive number or inherit/blank."; return }
    }
    destroy $w
    refreshManifestPreview
}
proc ::GX::moduleGraphicsSave {w id} {
    tailcall ::GX::moduleGraphicsSave_v0933_before_3d $w $id
}

# Put module-wide style beside Graph Provider selection.  Graphs remain fully
# module-declared; this button changes only common presentation inheritance.
proc ::GX::buildModulePlotConfigFrame_before_plot_variant {parent id} {
    set rows [::GX::buildModulePlotConfigFrame_v072_common_graphics_base $parent $id]
    if {$rows <= 0} { return $rows }
    if {[winfo exists $parent.actions]} {
        ttk::button $parent.actions.gfx -text "Module graphics..." -command [list ::GX::moduleGraphicsDialog $id]
        grid $parent.actions.gfx -row 0 -column 2 -padx 10
    }
    return $rows
}

# During the remaining CORE sources, keep the pre-variant entry available.
# plot_module_variants.tcl replaces it with the final variant-aware builder.
proc ::GX::buildModulePlotConfigFrame {parent id} {
    return [::GX::buildModulePlotConfigFrame_before_plot_variant $parent $id]
}

# Manifest Format 2: module overrides are separate from plot semantics.
proc ::GX::manifestStringV2_v079_before_scientific_analysis {} {
    variable moduleOrder
    variable moduleGraphicsOverride
    set out [::GX::manifestStringV2_v072_module_graphics_base]
    append out "\n\[module_graphics_api\]\n"; appendKV out version 1
    foreach id $moduleOrder {
        if {![llength [moduleGraphIds $id]]} continue
        moduleGraphicsEnsure $id
        append out "\n\[module_graphics.$id\]\n"
        appendKV out enabled $moduleGraphicsOverride($id,enabled)
        foreach f [moduleGraphicsFields] { appendKV out $f $moduleGraphicsOverride($id,$f) }
    }
    return $out
}
proc ::GX::loadManifestV2_v081_before_csv_batch {path} {
    variable moduleOrder
    variable moduleGraphicsOverride
    ::GX::loadManifestV2_v072_module_graphics_base $path
    array unset moduleGraphicsOverride *
    set d [parseIni $path]
    foreach id $moduleOrder {
        if {![llength [moduleGraphIds $id]]} continue
        moduleGraphicsEnsure $id
        set ek "module_graphics.$id.enabled"
        if {[dict exists $d $ek]} { set moduleGraphicsOverride($id,enabled) [dict get $d $ek] }
        foreach f [moduleGraphicsFields] {
            set k "module_graphics.$id.$f"
            if {[dict exists $d $k]} { set moduleGraphicsOverride($id,$f) [dict get $d $k] }
        }
    }
}

# Record the module override and the resolved environment in runtime.ini for
# provenance/debugging.  The child receives the same resolved values via env.
proc ::GX::writeStandardRuntimeConfig_v077 {id} {
    variable moduleGraphicsOverride
    set path [::GX::writeStandardRuntimeConfig_v072_module_graphics_base $id]
    if {![llength [moduleGraphIds $id]]} { return $path }
    moduleGraphicsEnsure $id
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[module_graphics\]"; putKV $fd api_version 1; putKV $fd enabled $moduleGraphicsOverride($id,enabled)
    foreach f [moduleGraphicsFields] { putKV $fd $f $moduleGraphicsOverride($id,$f) }
    puts $fd "\n\[graphics_effective\]"
    foreach item [plotEnv $id] {
        set pos [string first = $item]; if {$pos < 1} continue
        putKV $fd [string range $item 0 [expr {$pos-1}]] [string range $item [expr {$pos+1}] end]
    }
    close $fd
    return $path
}

# -----------------------------------------------------------------------------
# v0.7.8 framework capability consolidation
# - complete mathematical-model plugin location in runtime.ini
# - generic descriptor-driven file/path fields with Browse
# - public Plugin Progress API v1 integration for standard_octave jobs
# -----------------------------------------------------------------------------

source [file join $::GX::scriptDir core tcl progress_api_v1.tcl]

# Mathematical model discovery already retained the descriptor path.  Publish
# the plugin directory as a first-class catalog field without interpreting any
# optional model-specific descriptor sections.
proc ::GX::loadModuleCatalog_v079_before_scientific_analysis {} {
    variable modelCatalog
    variable modelOrder
    ::GX::loadModuleCatalog_v077
    foreach id $modelOrder {
        if {[info exists modelCatalog($id,descriptor)] && $modelCatalog($id,descriptor) ne ""} {
            set modelCatalog($id,plugin_dir) [file dirname [file normalize $modelCatalog($id,descriptor)]]
        }
    }
}

proc ::GX::fieldFiletypes {extensions} {
    set pats {}
    foreach e [splitList $extensions] {
        set e [string trim $e]
        if {$e eq ""} continue
        if {[string match {*[*?]*} $e]} {
            lappend pats $e
        } elseif {[string index $e 0] eq "."} {
            lappend pats "*$e"
        } else {
            lappend pats "*.$e"
        }
    }
    if {[llength $pats] == 0} { return [list [list "All files" "*"]] }
    return [list [list "Allowed files" $pats] [list "All files" "*"]]
}

proc ::GX::browseModuleConfigField {id key} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    set kind [string tolower [moduleConfigField $id $key path_kind file]]
    set title [moduleConfigField $id $key dialog_title [moduleConfigField $id $key label $key]]
    set must [expr {[moduleConfigField $id $key must_exist 1] ? 1 : 0}]
    set current [expr {[info exists moduleCfg($id,$key)] ? $moduleCfg($id,$key) : ""}]
    set workspaceRole [string trim [moduleConfigField $id $key workspace_role ""]]
    if {$workspaceRole ne ""} { workspaceValidateRole $workspaceRole }
    set initialDir ""
    if {$current ne ""} {
        if {[file isdirectory $current]} { set initialDir $current } else { set initialDir [file dirname $current] }
        if {![file isdirectory $initialDir]} { set initialDir "" }
    }
    if {$kind in {directory dir folder}} {
        set args [list -title $title]
        if {$initialDir ne ""} { lappend args -initialdir $initialDir }
        if {$workspaceRole ne ""} { set chosen [workspaceChooseDirectory $workspaceRole {*}$args] } else { set chosen [tk_chooseDirectory {*}$args] }
    } else {
        set args [list -title $title -filetypes [fieldFiletypes [moduleConfigField $id $key extensions ""]]]
        if {$initialDir ne ""} { lappend args -initialdir $initialDir }
        if {$must} {
            if {$workspaceRole ne ""} { set chosen [workspaceOpenFile $workspaceRole {*}$args] } else { set chosen [tk_getOpenFile {*}$args] }
        } else {
            if {$workspaceRole ne ""} { set chosen [workspaceSaveFile $workspaceRole {*}$args] } else { set chosen [tk_getSaveFile {*}$args] }
        }
    }
    if {$chosen ne ""} { set moduleCfg($id,$key) $chosen; catch {refreshManifestPreview} }
}

proc ::GX::browseModuleGraphConfigField {id graph key} {
    variable modulePlotCfg
    set type [string tolower [moduleGraphConfigField $id $graph $key type string]]
    set kind [string tolower [moduleGraphConfigField $id $graph $key path_kind file]]
    set title [moduleGraphConfigField $id $graph $key dialog_title [moduleGraphConfigField $id $graph $key label $key]]
    set must [expr {[moduleGraphConfigField $id $graph $key must_exist 1] ? 1 : 0}]
    set current [expr {[info exists modulePlotCfg($id,$graph,$key)] ? $modulePlotCfg($id,$graph,$key) : ""}]
    set workspaceRole [string trim [moduleGraphConfigField $id $graph $key workspace_role ""]]
    if {$workspaceRole ne ""} { workspaceValidateRole $workspaceRole }
    set initialDir ""
    if {$current ne ""} {
        if {[file isdirectory $current]} { set initialDir $current } else { set initialDir [file dirname $current] }
        if {![file isdirectory $initialDir]} { set initialDir "" }
    }
    if {$kind in {directory dir folder}} {
        set args [list -title $title]
        if {$initialDir ne ""} { lappend args -initialdir $initialDir }
        if {$workspaceRole ne ""} { set chosen [workspaceChooseDirectory $workspaceRole {*}$args] } else { set chosen [tk_chooseDirectory {*}$args] }
    } else {
        set args [list -title $title -filetypes [fieldFiletypes [moduleGraphConfigField $id $graph $key extensions ""]]]
        if {$initialDir ne ""} { lappend args -initialdir $initialDir }
        if {$must} {
            if {$workspaceRole ne ""} { set chosen [workspaceOpenFile $workspaceRole {*}$args] } else { set chosen [tk_getOpenFile {*}$args] }
        } else {
            if {$workspaceRole ne ""} { set chosen [workspaceSaveFile $workspaceRole {*}$args] } else { set chosen [tk_getSaveFile {*}$args] }
        }
    }
    if {$chosen ne ""} { set modulePlotCfg($id,$graph,$key) $chosen; catch {refreshManifestPreview} }
}

proc ::GX::standardConfigWidget_v079_before_scientific_analysis {parent id key row} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ni {file path}} { return [::GX::standardConfigWidget_v077 $parent $id $key $row] }
    set label [moduleConfigField $id $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::frame $parent.w$row
    ttk::entry $parent.w$row.entry -textvariable ::GX::moduleCfg($id,$key) -width 42
    ttk::button $parent.w$row.browse -text "Browse..." -command [list ::GX::browseModuleConfigField $id $key]
    pack $parent.w$row.entry -side left -fill x -expand 1
    pack $parent.w$row.browse -side left -padx {5 0}
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}

proc ::GX::modulePlotConfigWidget {parent id graph key row} {
    variable modulePlotCfg
    set type [string tolower [moduleGraphConfigField $id $graph $key type string]]
    if {$type ni {file path}} { return [::GX::modulePlotConfigWidget_v077 $parent $id $graph $key $row] }
    set label [moduleGraphConfigField $id $graph $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::frame $parent.w$row
    ttk::entry $parent.w$row.entry -textvariable ::GX::modulePlotCfg($id,$graph,$key) -width 42
    ttk::button $parent.w$row.browse -text "Browse..." -command [list ::GX::browseModuleGraphConfigField $id $graph $key]
    pack $parent.w$row.entry -side left -fill x -expand 1
    pack $parent.w$row.browse -side left -padx {5 0}
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}

proc ::GX::validateModulePathFields {id} {
    variable moduleCfg
    foreach key [moduleConfigKeys $id] {
        set type [string tolower [moduleConfigField $id $key type string]]
        if {$type ni {file path}} continue
        set value [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : ""}]
        set required [expr {[moduleConfigField $id $key required 0] ? 1 : 0}]
        set must [expr {[moduleConfigField $id $key must_exist 1] ? 1 : 0}]
        set kind [string tolower [moduleConfigField $id $key path_kind file]]
        if {$value eq ""} {
            if {$required} { error "$id: configuration '$key' requires a path." }
            continue
        }
        if {!$must} continue
        if {$kind in {directory dir folder}} {
            if {![file isdirectory $value]} { error "$id: directory does not exist for '$key': $value" }
        } else {
            if {![file isfile $value]} { error "$id: file does not exist for '$key': $value" }
        }
    }
}

proc ::GX::validateModuleGraphPathFields {id} {
    variable modulePlotCfg
    foreach graph [moduleGraphIds $id] {
        foreach key [moduleGraphConfigKeys $id $graph] {
            set type [string tolower [moduleGraphConfigField $id $graph $key type string]]
            if {$type ni {file path}} continue
            set value [expr {[info exists modulePlotCfg($id,$graph,$key)] ? [string trim $modulePlotCfg($id,$graph,$key)] : ""}]
            set required [expr {[moduleGraphConfigField $id $graph $key required 0] ? 1 : 0}]
            set must [expr {[moduleGraphConfigField $id $graph $key must_exist 1] ? 1 : 0}]
            set kind [string tolower [moduleGraphConfigField $id $graph $key path_kind file]]
            if {$value eq ""} {
                if {$required} { error "$id/$graph: plot configuration '$key' requires a path." }
                continue
            }
            if {!$must} continue
            if {$kind in {directory dir folder}} {
                if {![file isdirectory $value]} { error "$id/$graph: directory does not exist for '$key': $value" }
            } else {
                if {![file isfile $value]} { error "$id/$graph: file does not exist for '$key': $value" }
            }
        }
    }
}

# Add model plugin location and the public progress transport declaration to the
# final runtime.ini without changing Module API v1 or existing keys.
proc ::GX::writeStandardRuntimeConfig_v079_before_scientific_analysis {id} {
    variable moduleCfg
    validateModulePathFields $id
    validateModuleGraphPathFields $id
    set path [::GX::writeStandardRuntimeConfig_v077 $id]
    set modelId [expr {[info exists moduleCfg($id,model_id)] ? $moduleCfg($id,model_id) : ""}]
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    if {$modelId ne "" && [modelField $modelId descriptor ""] ne ""} {
        set descriptor [file normalize [modelField $modelId descriptor ""]]
        puts $fd "\n\[model\]"
        putKV $fd descriptor_path $descriptor
        putKV $fd plugin_dir [file dirname $descriptor]
    }
    puts $fd "\n\[progress\]"
    putKV $fd api_version 1
    putKV $fd transport structured_stdout_prefix
    putKV $fd prefix $::GX::progressProtocolPrefix
    close $fd
    return $path
}

proc ::GX::appendProgressRuntimeJob {runtime moduleId runId operation} {
    set fd [open $runtime a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[job\]"
    putKV $fd module_id $moduleId
    putKV $fd run_id $runId
    putKV $fd operation $operation
    close $fd
}

# Rebuild the two standard_octave queues with injected framework-owned job
# identity.  Existing two-element queue items remain accepted by runNextAnalysis.
proc ::GX::buildStandardAnalysisQueue_before_plot_variant {{target ""}} {
    variable moduleOrder
    variable cfg
    variable scriptDir
    set q {}
    # A targeted invocation prepares only its owner. Building the global queue
    # and filtering it afterwards would already have rewritten other runtimes.
    set owners [expr {$target eq "" ? $moduleOrder : [list $target]}]
    foreach id $owners {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {[moduleField $id runner ""] eq "script_module"} {
            if {$target eq "" && (![moduleIsEnabled $id] || ![moduleRunIsSelected $id])} continue
            lappend q [scriptModuleBuildQueueItem $id]
            continue
        }
        if {$id eq "analysis.python_script" && [moduleField $id runner ""] eq "script_execution"} {
            if {$target eq "" && (![moduleIsEnabled $id] || ![moduleRunIsSelected $id])} continue
            lappend q [scriptAnalysisBuildQueueItem $id]
            continue
        }
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        if {$target eq "" && (![moduleIsEnabled $id] || ![moduleRunIsSelected $id])} continue
        if {[moduleField $id ui_replaced_by_core 0] && (![info exists ::GX::cliMode] || !$::GX::cliMode)} continue
        if {$id eq "analysis.octave_script" && $::GX::moduleCfg($id,source_mode) eq "registered_script"} {
            lappend q [scriptAnalysisBuildQueueItem $id]
            continue
        }
        if {$id eq "analysis.octave_script" && $::GX::moduleCfg($id,source_mode) eq "external_file"} {
            set outDir [file join $::GX::currentSession analysis analysis.octave_script]
            foreach stale {execution.ini octave.log .registered_queue_status} {
                if {[file exists [file join $outDir $stale]]} { file delete -- [file join $outDir $stale] }
            }
        }
        set runtime [writeStandardRuntimeConfig $id]
        set runId [progressNewRunId $id analysis]
        appendProgressRuntimeJob $runtime $id $runId analysis
        set rel [moduleField $id runner_script ""]
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} { error "$id: standard runner script missing: $script" }
        set outDir [file dirname $runtime]
        set expected [moduleExpectedOutputs $id]
        set wrapper [file join $scriptDir core tcl standard_octave_exec.tcl]
        if {![file isfile $wrapper]} { error "$id: standard Octave wrapper missing: $wrapper" }
        set ncpu $cfg(cpu_count)
        set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime]
        set cmd [concat \
            [list env OMP_NUM_THREADS=$ncpu OPENBLAS_NUM_THREADS=$ncpu MKL_NUM_THREADS=$ncpu NUMEXPR_NUM_THREADS=$ncpu \
                GXTXT_PROGRESS_ENABLED=1 GXTXT_PROGRESS_MODULE_ID=$id GXTXT_PROGRESS_RUN_ID=$runId GXTXT_PROGRESS_OPERATION=analysis] \
            [graphicsEnv] [plotEnv $id] \
            [list tclsh $wrapper --output-dir $outDir --expected $expected --] \
            $child]
        lappend q [list "Analysis - [moduleField $id name $id]" $cmd $id $runId]
    }
    return $q
}

proc ::GX::buildStandardRerenderQueue_before_plot_variant {paths} {
    variable moduleOrder
    variable cfg
    variable currentSession
    variable scriptDir
    set q {}
    foreach id $moduleOrder {
        if {[moduleField $id runner ""] ne "standard_octave"} continue
        set outDir [file join $currentSession analysis [sanitize $id]]
    # Script preparation can request a unique run-local runtime snapshot.
    # All existing module callers retain their established output location.
    if {[info exists ::GX::scriptRuntimeOutputOverride] && [dict get $::GX::scriptRuntimeOutputOverride module] eq $id} {
        set outDir [dict get $::GX::scriptRuntimeOutputOverride path]
    }
        set hit 0
        foreach p $paths {
            set pn [file normalize $p]; set dn [file normalize $outDir]
            if {[string first "$dn/" "$pn/"] == 0 || [file dirname $pn] eq $dn} { set hit 1; break }
        }
        if {!$hit} continue
        set cache [file join $outDir render_cache.mat]
        if {![file isfile $cache]} {
            if {$id ne "plot.dataset"} continue
            # plot.dataset runtime/cache is disposable. A user can therefore
            # recover a damaged or reset module through the normal Rerender
            # action while persistent Graph Series, PlotSpec and variants stay.
            set runtime [writeStandardRuntimeConfig $id]
            set script [file join $scriptDir [moduleField $id runner_script ""]]
            if {![file isfile $script]} continue
            set wrapper [file join $scriptDir core tcl standard_octave_exec.tcl]
            set expected [moduleExpectedOutputs $id]
            set runId [progressNewRunId $id recovery]
            appendProgressRuntimeJob $runtime $id $runId recovery
            set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime]
            set cmd [concat [list env GXTXT_PROGRESS_ENABLED=1 GXTXT_PROGRESS_MODULE_ID=$id GXTXT_PROGRESS_RUN_ID=$runId GXTXT_PROGRESS_OPERATION=recovery]                 [graphicsEnv] [plotEnv $id]                 [list tclsh $wrapper --output-dir $outDir --expected $expected --] $child]
            lappend q [list "Rerender - [moduleField $id name $id]" $cmd $id $runId]
            continue
        }
        # Always refresh runtime from current GUI/configuration state.
        set runtime [writeStandardRuntimeConfig $id]
        set rel [moduleField $id rerender_script ""]
        if {$rel eq ""} continue
        set script [file join $scriptDir $rel]
        if {![file isfile $script]} continue
        set wrapper [file join $scriptDir core tcl standard_octave_exec.tcl]
        set expected [moduleExpectedOutputs $id]
        set runId [progressNewRunId $id rerender]
        appendProgressRuntimeJob $runtime $id $runId rerender
        set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime --cache $cache]
        set cmd [concat [list env GXTXT_PROGRESS_ENABLED=1 GXTXT_PROGRESS_MODULE_ID=$id GXTXT_PROGRESS_RUN_ID=$runId GXTXT_PROGRESS_OPERATION=rerender] \
            [graphicsEnv] [plotEnv $id] \
            [list tclsh $wrapper --output-dir $outDir --expected $expected --] $child]
        lappend q [list "Rerender - [moduleField $id name $id]" $cmd $id $runId]
    }
    return $q
}

# Progress-aware analysis lifecycle.  The subprocess remains non-blocking and
# fileevent-driven; progress records are consumed separately from normal logs.
proc ::GX::runNextAnalysis_before_parallel_octave_binding_v1 {} {
    variable analysisPipe
    variable analysisQueue
    variable analysisDone
    variable analysisTotal
    variable analysisPids
    variable ui
    if {[llength $analysisQueue] == 0} {
        set analysisPipe ""
        if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {close $ui(analysisLogFile)}; set ui(analysisLogFile) "" }
        if {[info exists ui(startButton)]} {$ui(startButton) configure -state normal}
        if {[info exists ui(analysisStart)]} {$ui(analysisStart) configure -state normal}
        if {[info exists ui(runAllButton)]} {$ui(runAllButton) configure -state normal}
        if {[info exists ui(stopButton)]} {$ui(stopButton) configure -state disabled}
        variable analysisOperation
        analysisLog "$analysisOperation completed."
        progressUiStopAnimation
        setStatus "$analysisOperation completed" 100
        if {$analysisOperation eq "Plot rerendering"} {
            catch {unset ui(graphPreviewLoadSig)}; catch {unset ui(graphPreviewFitW)}; catch {unset ui(graphPreviewFitH)}
        }
        catch {refreshResults}; catch {refreshGraphs}; catch {refreshOpenGraphWindow}; catch {refreshAnalysisStatus}
        if {$analysisOperation eq "Targeted analysis"} {
            moduleAnalysisFinish COMPLETED {}
        } elseif {[llength [info commands tk_messageBox]]} { tk_messageBox -icon info -title "GX-TXT" -message "$analysisOperation completed." }
        return
    }
    set item [lindex $analysisQueue 0]; set analysisQueue [lrange $analysisQueue 1 end]
    set label [lindex $item 0]; set cmd [lindex $item 1]
    set moduleId [expr {[llength $item] >= 3 ? [lindex $item 2] : ""}]
    set runId [expr {[llength $item] >= 4 ? [lindex $item 3] : ""}]
    set ui(analysisCurrentLabel) $label; set ui(analysisCurrentModuleId) $moduleId; set ui(analysisCurrentRunId) $runId
    set ui(analysisRecentOutput) ""
    analysisLog "=== $label ==="; analysisLog "Server command: $cmd"
    if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { puts $ui(analysisLogFile) "=== $label ===\n$cmd" }
    set pipeline [concat | $cmd [list 2>@1]]
    set ::GX::analysisOwnedGroup 0
    if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {} && $::tcl_platform(platform) eq "unix"} {
        # One owned process group lets the existing Cancel terminate the runner
        # and its Octave descendants together, including computation without IO.
        set setsid [auto_execok setsid]
        if {$setsid eq {}} {moduleAnalysisFinish FAILED {Owned process-group cancellation is unavailable};error {setsid is required for targeted Analysis cancellation}}
        set pipeline [concat | [list {*}$setsid --wait] $cmd [list 2>@1]]
        set ::GX::analysisOwnedGroup 1
    }
    if {[catch {
        set analysisPipe [open $pipeline r]; set analysisPids [pid $analysisPipe]
        fconfigure $analysisPipe -blocking 0 -buffering line -encoding utf-8
        fileevent $analysisPipe readable [list ::GX::onAnalysisReadable $analysisPipe]
        progressUiFallbackStart $label $moduleId
    } err]} {
        analysisLog "START ERROR: $err"
        if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {}} {moduleAnalysisFinish FAILED $err}
        stopAnalysis 0
    }
}

proc ::GX::onAnalysisReadable_before_parallel_octave_binding_v1 {p} {
    variable analysisPipe
    variable analysisDone
    variable analysisTotal
    variable ui
    if {$p ne $analysisPipe} return
    if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {} && ![moduleAnalysisScopeValid 0]} {
        moduleAnalysisFinish FAILED {Session or source identity changed during the invocation}
        stopAnalysis 0
        return
    }
    while {[gets $p line] >= 0} {
        set ev [progressParseLine $line]
        if {[dict size $ev] > 0} {
            if {(![dict exists $ev module_id] || [dict get $ev module_id] eq "") && [info exists ui(analysisCurrentModuleId)]} { dict set ev module_id $ui(analysisCurrentModuleId) }
            if {(![dict exists $ev run_id] || [dict get $ev run_id] eq "") && [info exists ui(analysisCurrentRunId)]} { dict set ev run_id $ui(analysisCurrentRunId) }
            progressPublish $ev
            continue
        }
        analysisLog $line
        if {[info exists ui(analysisCurrentModuleId)] &&
            ($ui(analysisCurrentModuleId) in {analysis.octave_script analysis.python_script} ||
             [moduleField $ui(analysisCurrentModuleId) runner ""] eq "script_module")} {
            append ui(analysisRecentOutput) "$line\n"
            if {[string length $ui(analysisRecentOutput)] > 4000} {
                set ui(analysisRecentOutput) [string range $ui(analysisRecentOutput) end-3999 end]
            }
        }
        if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { puts $ui(analysisLogFile) $line }
    }
    if {[eof $p]} {
        if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {} && ![moduleAnalysisScopeValid]} {
            moduleAnalysisFinish FAILED {Scientific source identity changed during invocation}
            stopAnalysis 0
            return
        }
        fileevent $p readable {}
        set ok 1; set errtxt ""
        # EOF is already observed. Collect the actual child exit status; Tcl
        # otherwise discards CHILDSTATUS when closing a nonblocking pipeline.
        fconfigure $p -blocking 1
        if {[catch {close $p} err]} { set ok 0; set errtxt $err }
        if {[info exists ui(analysisCurrentModuleId)] &&
            ([moduleField $ui(analysisCurrentModuleId) runner ""] eq "script_module" ||
             ($ui(analysisCurrentModuleId) in {analysis.octave_script analysis.python_script} &&
              [info exists ::GX::moduleCfg($ui(analysisCurrentModuleId),source_mode)] &&
              $::GX::moduleCfg($ui(analysisCurrentModuleId),source_mode) eq "registered_script"))} {
            set statusPath [file join $::GX::currentSession analysis $ui(analysisCurrentModuleId) .registered_queue_status]
            set status ""
            if {[file isfile $statusPath]} {
                set sf [open $statusPath r]
                try { set status [string trim [read $sf]] } finally { close $sf }
            }
            if {$status ne "PASS"} {
                set ok 0
                if {$errtxt eq ""} { set errtxt "Registered script execution failed ($status)." }
            }
        }
        set analysisPipe ""
        if {!$ok} {
            if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {}} {moduleAnalysisFinish FAILED $errtxt}
            set ev [dict create state failed mode indeterminate stage process message "Module process failed" \
                module_id [expr {[info exists ui(analysisCurrentModuleId)] ? $ui(analysisCurrentModuleId) : ""}] \
                run_id [expr {[info exists ui(analysisCurrentRunId)] ? $ui(analysisCurrentRunId) : ""}]]
            progressPublish $ev
            analysisLog "ERROR: $errtxt"
            if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {close $ui(analysisLogFile)}; set ui(analysisLogFile) "" }
            if {[info exists ui(startButton)]} {$ui(startButton) configure -state normal}
            if {[info exists ui(analysisStart)]} {$ui(analysisStart) configure -state normal}
            if {[info exists ui(runAllButton)]} {$ui(runAllButton) configure -state normal}
            if {[info exists ui(stopButton)]} {$ui(stopButton) configure -state disabled}
            variable analysisOperation
            if {[info exists ui(analysisCurrentModuleId)] &&
                ($ui(analysisCurrentModuleId) in {analysis.octave_script analysis.python_script} ||
                 [moduleField $ui(analysisCurrentModuleId) runner ""] eq "script_module") &&
                [info exists ui(analysisRecentOutput)] && $ui(analysisRecentOutput) ne ""} {
                append errtxt "\n\n" $ui(analysisRecentOutput)
            }
            if {[llength [info commands ::tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message "$analysisOperation: module finished with an error.\n\n$errtxt" }
            return
        }
        variable analysisOperation
        if {$analysisOperation in {"Selective analysis" "Targeted analysis"} && [info exists ui(analysisCurrentModuleId)] && $ui(analysisCurrentModuleId) ne ""} {
            if {[catch {set pubs [datasetPublicationProcessModule $ui(analysisCurrentModuleId)]} perr]} {
                if {$analysisOperation eq "Targeted analysis"} {moduleAnalysisFinish FAILED $perr}
                analysisLog "DATASET PUBLICATION ERROR: $perr"
                if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {puts $ui(analysisLogFile) "DATASET PUBLICATION ERROR: $perr"} }
                if {[info exists ui(startButton)]} {$ui(startButton) configure -state normal}
                if {[info exists ui(analysisStart)]} {$ui(analysisStart) configure -state normal}
                if {[info exists ui(runAllButton)]} {$ui(runAllButton) configure -state normal}
                if {[info exists ui(stopButton)]} {$ui(stopButton) configure -state disabled}
                if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message "Analysis completed but Dataset Publication API registration failed.\n\n$perr" }
                return
            } elseif {[llength $pubs]} {
                analysisLog "Published dataset(s): [join $pubs {, }]"
            }
        }
        incr analysisDone
        progressUiStopAnimation
        setStatus "$analysisOperation: $analysisDone / $analysisTotal" [expr {100.0*$analysisDone/max(1,$analysisTotal)}]
        runNextAnalysis
    }
}

proc ::GX::stopAnalysis_before_parallel_octave_binding_v1 {{message 1}} {
    if {[info exists ::GX::targetedAnalysisActive] && $::GX::targetedAnalysisActive ne {}} {moduleAnalysisFinish CANCELLED {Invocation cancelled}}
    set r [::GX::stopAnalysis_v077 $message]
    progressUiStopAnimation
    if {$message} { progressUiReset "Analysis interrupted" }
    return $r
}


# -----------------------------------------------------------------------------
# v0.7.9 Analysis workspace scalability
# -----------------------------------------------------------------------------
# The Modules tab is the catalog/selection surface.  Analysis is a workspace:
# it must contain only analysis modules explicitly enabled in the experiment.
# The workspace is hosted in a vertically scrollable canvas so any number of
# active modules remains fully reachable on ordinary desktop displays.

proc ::GX::analysisScrollableHost {} {
    variable ui
    set f .top.nb.analysis
    if {![llength [info commands winfo]] || ![winfo exists $f]} { return "" }
    destroyChildren $f
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1

    canvas $f.canvas -highlightthickness 0 -borderwidth 0 -takefocus 0
    set bg [ttk::style lookup TFrame -background]
    if {$bg ne ""} { catch {$f.canvas configure -background $bg} }
    ttk::scrollbar $f.ys -orient vertical -command [list $f.canvas yview]
    $f.canvas configure -yscrollcommand [list $f.ys set]
    grid $f.canvas -row 0 -column 0 -sticky nsew
    grid $f.ys -row 0 -column 1 -sticky ns

    ttk::frame $f.canvas.inner
    set win [$f.canvas create window 0 0 -anchor nw -window $f.canvas.inner]
    set ui(analysisCanvas) $f.canvas
    set ui(analysisInner) $f.canvas.inner
    set ui(analysisCanvasWindow) $win

    bind $f.canvas.inner <Configure> [list ::GX::analysisScrollRefresh]
    bind $f.canvas <Configure> [list ::GX::analysisCanvasResize %w]
    bind $f.canvas <MouseWheel> [list ::GX::analysisMouseWheel %D]
    bind $f.canvas.inner <MouseWheel> [list ::GX::analysisMouseWheel %D]
    bind $f.canvas <Button-4> {::GX::analysisScrollUnits -3}
    bind $f.canvas <Button-5> {::GX::analysisScrollUnits 3}
    bind $f.canvas.inner <Button-4> {::GX::analysisScrollUnits -3}
    bind $f.canvas.inner <Button-5> {::GX::analysisScrollUnits 3}
    return $f.canvas.inner
}

proc ::GX::analysisScrollRefresh {} {
    variable ui
    if {![info exists ui(analysisCanvas)] || ![winfo exists $ui(analysisCanvas)]} { return }
    set c $ui(analysisCanvas)
    set bbox [$c bbox all]
    if {[llength $bbox] == 4} { $c configure -scrollregion $bbox }
}

proc ::GX::analysisCanvasResize {width} {
    variable ui
    if {![info exists ui(analysisCanvas)] || ![info exists ui(analysisCanvasWindow)]} { return }
    set c $ui(analysisCanvas)
    if {![winfo exists $c]} { return }
    # Keep the workspace exactly as wide as the viewport.  Only vertical
    # scrolling is required and long module forms therefore expand naturally.
    set w [expr {max(1, $width)}]
    catch {$c itemconfigure $ui(analysisCanvasWindow) -width $w}
    analysisScrollRefresh
}

proc ::GX::analysisScrollUnits {units} {
    variable ui
    if {[info exists ui(analysisCanvas)] && [winfo exists $ui(analysisCanvas)]} {
        $ui(analysisCanvas) yview scroll $units units
    }
}

proc ::GX::analysisMouseWheel {delta} {
    if {$delta == 0} { return }
    # Windows reports multiples of 120; other Tk builds may report smaller
    # deltas.  Preserve direction and guarantee at least one scroll unit.
    set n [expr {int(-$delta / 120)}]
    if {$n == 0} { set n [expr {$delta > 0 ? -1 : 1}] }
    analysisScrollUnits [expr {$n * 3}]
}

# Final Analysis builder for the native Standard Module API profile.
# Installed-but-disabled modules are intentionally absent here; they remain
# discoverable and selectable in the Modules catalog.
proc ::GX::rebuildNativeAnalysisGui_v084_single_source {} {
    variable moduleOrder
    variable moduleRun
    variable moduleBinding
    variable ui

    set host [analysisScrollableHost]
    if {$host eq ""} { return }
    foreach k [array names ui "analysisModuleFrame,*"] { unset ui($k) }
    grid columnconfigure $host 0 -weight 1

    set row 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {![moduleIsEnabled $id]} continue

        set base $host.m$row
        set ui(analysisModuleFrame,$id) $base
        ttk::labelframe $base -text "[moduleField $id name $id]  ($id)"
        grid $base -row $row -column 0 -sticky new -padx 6 -pady 6
        grid columnconfigure $base 0 -weight 1
        grid columnconfigure $base 1 -weight 1

        # Experiment membership belongs exclusively to Modules.  Analysis only
        # decides whether an already-active module should run/recalculate now.
        ttk::checkbutton $base.run -text "Run / recalculate now" \
            -variable ::GX::moduleRun($id) -command ::GX::refreshManifestPreview
        grid $base.run -row 0 -column 0 -columnspan 2 -sticky w -padx 4 -pady 3

        set br 1
        if {[llength [moduleGraphIds $id]]} {
            ttk::labelframe $base.plots -text "Graphs offered by module (Graph Provider API v1)"
            grid $base.plots -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $base.plots 0 -weight 1
            buildModulePlotConfigFrame $base.plots $id
            incr br
        }

        ttk::labelframe $base.cfg -text "Calculation configuration"
        grid $base.cfg -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
        buildStandardConfigFrame $base.cfg $id
        incr br

        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            ttk::labelframe $base.bind -text "Input variable bindings"
            grid $base.bind -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $base.bind 1 -weight 1
            set vals [linsert [sourceVariableNames] 0 auto]
            set rr 0
            foreach role $roles {
                ttk::label $base.bind.l$rr -text [moduleBindingField $id $role label $role]
                ttk::combobox $base.bind.w$rr -textvariable ::GX::moduleBinding($id,$role) \
                    -values $vals -state readonly -width 30
                grid $base.bind.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2
                grid $base.bind.w$rr -row $rr -column 1 -sticky ew -padx 4 -pady 2
                incr rr
            }
        }
        incr row
    }

    if {$row == 0} {
        ttk::frame $host.empty
        ttk::label $host.empty.title -text "No analysis modules are active in this experiment." -font TkHeadingFont
        ttk::label $host.empty.help -text "Open the Modules tab and activate the analysis modules you want to use. Only active modules are shown here." -wraplength 800 -justify left
        grid $host.empty.title -row 0 -column 0 -sticky w -pady {0 5}
        grid $host.empty.help -row 1 -column 0 -sticky w
        grid $host.empty -row 0 -column 0 -sticky nw -padx 12 -pady 12
    }

    refreshNativeAnalysisState
    update idletasks
    analysisScrollRefresh
    if {[info exists ui(analysisCanvas)] && [winfo exists $ui(analysisCanvas)]} { $ui(analysisCanvas) yview moveto 0 }
}

# With inactive modules absent from Analysis, state refresh is deliberately
# simple and keyed by stable module ID rather than display-row numbering.
proc ::GX::refreshNativeAnalysisState_v084_sources_base {} {
    variable moduleOrder
    variable ui
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {![info exists ui(analysisModuleFrame,$id)]} continue
        set base $ui(analysisModuleFrame,$id)
        if {![winfo exists $base]} continue
        if {[winfo exists $base.run]} { catch {$base.run state !disabled} }
        if {[winfo exists $base.cfg]} { setWidgetTreeState $base.cfg 1 }
        if {[winfo exists $base.bind]} { setWidgetTreeState $base.bind 1 }
        if {[winfo exists $base.plots]} { setWidgetTreeState $base.plots 1 }
    }
    catch {analysisScrollRefresh}
}

# Selection happens in Modules.  Rebuild the workspace immediately after a
# user activation/deactivation so Analysis never shows stale plugin panels.
proc ::GX::setSelectedModuleState {state} {
    ::GX::setSelectedModuleState_v078_workspace $state
    catch {rebuildNativeAnalysisGui}
}

proc ::GX::toggleSelectedModule {} {
    ::GX::toggleSelectedModule_v078_workspace
    catch {rebuildNativeAnalysisGui}
}

# Manifest/session selection can also change module membership.  This wrapper
# is harmless in headless mode because the GUI rebuild is guarded by catch.
proc ::GX::applyModuleSelection {raw} {
    ::GX::applyModuleSelection_v078_workspace $raw
    catch {rebuildNativeAnalysisGui}
}

# -----------------------------------------------------------------------------
# v0.8.1 Scientific Analysis Definition API v1 + plot-axis override hardening
# -----------------------------------------------------------------------------
# Analysis definitions are trusted, declarative plugin resources.  They describe
# a scientific data-flow assembled from framework operations.  Mathematical
# Model API v1 remains independent and backward compatible.
namespace eval ::GX {
    variable scientificAnalysisApiVersion 1
    variable renderCacheApiVersion 1
    variable analysisDefinitionCatalog
    variable analysisDefinitionOrder {}
}

proc ::GX::analysisDefinitionField {id field {default ""}} {
    variable analysisDefinitionCatalog
    if {[info exists analysisDefinitionCatalog($id,$field)]} { return $analysisDefinitionCatalog($id,$field) }
    return $default
}

proc ::GX::registerAnalysisDefinition {path scope ownerModule} {
    variable analysisDefinitionCatalog
    variable analysisDefinitionOrder
    set d [parseIni $path]
    set api [descriptorValue $d meta api_version ""]
    if {$api ne "1"} { error "Unsupported Scientific Analysis Definition API version '$api' in $path" }
    set id [string trim [descriptorValue $d meta id ""]]
    if {$id eq ""} { error "Missing analysis-definition meta.id in $path" }
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id]} { error "Invalid analysis-definition id '$id' in $path" }
    if {[info exists analysisDefinitionCatalog($id,descriptor)]} { error "Duplicate analysis-definition id: $id" }
    foreach {field def} {name "" version "" kind generic description "" capabilities ""} {
        set analysisDefinitionCatalog($id,$field) [descriptorValue $d meta $field $def]
    }
    if {$analysisDefinitionCatalog($id,name) eq ""} { set analysisDefinitionCatalog($id,name) $id }
    set analysisDefinitionCatalog($id,descriptor) [file normalize $path]
    set analysisDefinitionCatalog($id,plugin_dir) [file dirname [file normalize $path]]
    set analysisDefinitionCatalog($id,scope) $scope
    set analysisDefinitionCatalog($id,owner_module) $ownerModule
    set analysisDefinitionCatalog($id,dict) $d
    lappend analysisDefinitionOrder $id
}

proc ::GX::loadScientificAnalysisDefinitions {} {
    variable analysisDefinitionCatalog
    variable analysisDefinitionOrder
    variable moduleOrder
    variable scriptDir
    array unset analysisDefinitionCatalog *
    set analysisDefinitionOrder {}

    # Global definitions are reusable by every module.
    set root [file join $scriptDir plugins analysis_definitions]
    foreach path [lsort [glob -nocomplain -types f [file join $root * analysis.ini]]] {
        registerAnalysisDefinition $path global ""
    }

    # Module-local definitions are visible only to their owning module.  This
    # provides a private namespace without forcing specialised definitions into
    # the global catalog.
    foreach moduleId $moduleOrder {
        set descriptor [moduleField $moduleId descriptor ""]
        if {$descriptor eq ""} continue
        set mroot [file join [file dirname $descriptor] analysis_definitions]
        foreach path [lsort [glob -nocomplain -types f [file join $mroot * analysis.ini]]] {
            registerAnalysisDefinition $path local $moduleId
        }
    }
    set analysisDefinitionOrder [lsort -dictionary $analysisDefinitionOrder]
}

proc ::GX::loadModuleCatalog_v081_before_contract_registry {} {
    ::GX::loadModuleCatalog_v079_before_scientific_analysis
    loadScientificAnalysisDefinitions
}

proc ::GX::analysisDefinitionIdsForConfig {moduleId key} {
    variable analysisDefinitionOrder
    set scope [string tolower [string trim [moduleConfigField $moduleId $key scope all]]]
    if {$scope ni {all global local}} { set scope all }
    set requiredKind [string trim [moduleConfigField $moduleId $key kind ""]]
    set requiredCaps [splitList [moduleConfigField $moduleId $key capabilities ""]]
    set out {}
    foreach id $analysisDefinitionOrder {
        set ds [analysisDefinitionField $id scope global]
        set owner [analysisDefinitionField $id owner_module ""]
        if {$ds eq "local" && $owner ne $moduleId} continue
        if {$scope eq "global" && $ds ne "global"} continue
        if {$scope eq "local" && !($ds eq "local" && $owner eq $moduleId)} continue
        if {$requiredKind ne "" && ![string equal -nocase $requiredKind [analysisDefinitionField $id kind ""]]} continue
        set caps {}
        foreach cap [splitList [analysisDefinitionField $id capabilities ""]] { lappend caps [string tolower $cap] }
        set ok 1
        foreach cap $requiredCaps { if {[lsearch -exact $caps [string tolower $cap]] < 0} { set ok 0; break } }
        if {$ok} { lappend out $id }
    }
    return $out
}

# Descriptor-generated selector for analysis definitions.  Existing config
# field types are unchanged.
proc ::GX::standardConfigWidget_v081_before_contract_registry {parent id key row} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ne "analysis_definition"} { return [::GX::standardConfigWidget_v079_before_scientific_analysis $parent $id $key $row] }
    set label [moduleConfigField $id $key label $key]
    set vals [analysisDefinitionIdsForConfig $id $key]
    ttk::label $parent.l$row -text $label
    ttk::combobox $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -values $vals -state readonly -width 42
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}

proc ::GX::appendAxisRuntimeSections_v0933_before_3d {fd id} {
    variable axisOverride
    foreach graph [moduleGraphIds $id] {
        # The layout controls live in the same per-graph store but must not
        # switch plot-specific Axes configuration on by themselves.
        if {![info exists axisOverride($graph,enabled)] && ![info exists axisOverride($graph,layout_auto)]} continue
        puts $fd "\n\[axis.$graph\]"
        foreach {field def} {enabled 0 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" layout_auto 1 layout_margin_left "" layout_margin_right "" layout_margin_top "" layout_margin_bottom "" layout_gap "" layout_ylabel_dist "" layout_ylabel_allow_negative 0} {
            set v [expr {[info exists axisOverride($graph,$field)] ? $axisOverride($graph,$field) : $def}]
            putKV $fd $field $v
        }
        set panels [expr {[info exists axisOverride($graph,panels)] ? $axisOverride($graph,panels) : {}}]
        putKV $fd panel_count [llength $panels]
        set pi 0
        foreach pn $panels {
            incr pi
            putKV $fd "panel${pi}_name" $pn
            foreach {field def} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
                set ak "$graph,$pn,$field"
                set v [expr {[info exists axisOverride($ak)] ? $axisOverride($ak) : $def}]
                putKV $fd "panel${pi}_$field" $v
            }
        }
    }
}
proc ::GX::appendAxisRuntimeSections {fd id} {
    tailcall ::GX::appendAxisRuntimeSections_v0933_before_3d $fd $id
}

# Runtime publishes selected definition locations and the current plot-axis
# override state.  The latter makes rerender configuration reproducible while
# keeping the historical TSV transport as a compatibility fallback.
proc ::GX::writeStandardRuntimeConfig_v083_before_analysis_parameters {id} {
    variable moduleCfg
    set path [::GX::writeStandardRuntimeConfig_v079_before_scientific_analysis $id]
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[scientific_analysis_api\]"
    putKV $fd api_version $::GX::scientificAnalysisApiVersion
    foreach key [moduleConfigKeys $id] {
        if {[string tolower [moduleConfigField $id $key type string]] ne "analysis_definition"} continue
        set defId [string trim $moduleCfg($id,$key)]
        set required [expr {[moduleConfigField $id $key required 0] ? 1 : 0}]
        if {$defId eq ""} {
            if {$required} { close $fd; error "$id: configuration '$key' requires an analysis definition." }
            continue
        }
        if {[analysisDefinitionField $defId descriptor ""] eq ""} { close $fd; error "$id: unknown analysis definition '$defId'." }
        if {[lsearch -exact [analysisDefinitionIdsForConfig $id $key] $defId] < 0} { close $fd; error "$id: analysis definition '$defId' is incompatible with configuration '$key'." }
        puts $fd "\n\[analysis_definition.$key\]"
        putKV $fd id $defId
        putKV $fd api_version 1
        putKV $fd kind [analysisDefinitionField $defId kind ""]
        putKV $fd capabilities [analysisDefinitionField $defId capabilities ""]
        putKV $fd scope [analysisDefinitionField $defId scope global]
        putKV $fd owner_module [analysisDefinitionField $defId owner_module ""]
        putKV $fd descriptor_path [analysisDefinitionField $defId descriptor ""]
        putKV $fd plugin_dir [analysisDefinitionField $defId plugin_dir ""]
    }
    set rcApi [string trim [moduleField $id render_cache_api_version ""]]
    if {$rcApi ne ""} {
        if {$rcApi ne "1"} { close $fd; error "$id: unsupported Render Cache API version '$rcApi'." }
        variable currentSession
        puts $fd "\n\[render_cache_api\]"
        putKV $fd api_version 1
        putKV $fd path [file join $currentSession analysis [sanitize $id] render_cache.mat]
        putKV $fd rerender_from_cache [moduleField $id render_cache_rerender 0]
    }
    appendAxisRuntimeSections $fd $id
    close $fd
    return $path
}

# v0.6.1's native plot environment intentionally removed legacy scientific
# variables, but it also dropped the common axis-override transport. Restore
# that framework resource for every native module; no module-specific grid code
# is involved.

# v0.8.1: publish a framework-owned mapping between declared graph outputs and
# Graph Provider IDs.  Renderers keep using the existing graphics API; the
# common PNG finalizer uses this map to apply the current per-plot Axes/grid
# override immediately before export.  No plugin-specific grid code is needed.
proc ::GX::writeGraphOutputMapFile {{moduleId ""}} {
    variable currentSession
    variable moduleOrder
    variable axisOverride
    if {$currentSession eq ""} { return "" }
    set ids [expr {$moduleId ne "" ? [list $moduleId] : $moduleOrder}]
    set d [file join $currentSession analysis]
    file mkdir $d
    set path [file join $d .plot_graph_map.tsv]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "path\tkey\tpanels"
    foreach id $ids {
        if {[lsearch -exact $moduleOrder $id] < 0} continue
        foreach graph [moduleGraphIds $id] {
            set declared [string trim [moduleGraphField $id $graph file ""]]
            if {$declared eq ""} continue
            set target [file normalize [file join $currentSession analysis $id $declared]]
            set panels [expr {[info exists axisOverride($graph,panels)] ? $axisOverride($graph,panels) : {}}]
            set safeTarget [string map [list "\t" " " "\n" " " "\r" " "] $target]
            set safeGraph  [string map [list "\t" " " "\n" " " "\r" " "] $graph]
            set safePanels [string map [list "\t" " " "\n" " " "\r" " "] [join $panels ";"]]
            puts $fd "$safeTarget\t$safeGraph\t$safePanels"
        }
    }
    close $fd
    return $path
}

proc ::GX::plotEnv_v0933_before_plot3d {{moduleId ""}} {
    set out [::GX::plotEnv_v079_before_axis_override_fix $moduleId]
    set aof [writeAxisOverrideFile]
    if {$aof ne ""} { set out [envListReplace $out GXTXT_PLOT_AXIS_OVERRIDE_FILE $aof] }
    set gmf [writeGraphOutputMapFile $moduleId]
    if {$gmf ne ""} { set out [envListReplace $out GXTXT_PLOT_GRAPH_MAP_FILE $gmf] }
    return $out
}

proc ::GX::manifestStringV2_v081_before_csv_batch {} {
    set out [::GX::manifestStringV2_v079_before_scientific_analysis]
    append out "\n\[scientific_analysis_api\]\n"
    appendKV out version $::GX::scientificAnalysisApiVersion
    append out "\n\[render_cache_api\]\n"
    appendKV out version $::GX::renderCacheApiVersion
    return $out
}

# -----------------------------------------------------------------------------
# v0.8.2 Contract Registry API v1 + generic CSV batch import
# -----------------------------------------------------------------------------
# This release is additive. Existing Module API v1, Graph Provider API,
# Scientific Analysis Definition API v1 and legacy single-CSV import remain
# available.  The Contract Registry is descriptor-derived and exposes an
# explicit Other... escape hatch so sessions never depend on a closed enum.
namespace eval ::GX {
    variable contractRegistryApiVersion 1
    variable contractRegistry
    variable contractOrder {}
    variable genericCsvBatch
    variable genericCsvBatchCount 0
    variable genericCsvBatchEnabled 0
    variable genericContractChoice
    variable genericContractCustom
}

proc ::GX::contractCoreDescription {id} {
    switch -- $id {
        raw.csv { return "Raw CSV acquisition source." }
        table.generic { return "Generic canonical tabular dataset." }
        timeseries.table { return "Canonical time-series table." }
        curve_family.table { return "Canonical family-of-curves table." }
        spectrum.table { return "Canonical frequency-domain spectrum table (independent variable: frequency)." }
        spectrum.scientific { return "Generic one-dimensional scientific spectrum with arbitrary X and Y quantities/units." }
        default { return "Plugin-declared dataset contract." }
    }
}

proc ::GX::contractRegistryEnsure {cid} {
    variable contractRegistry
    set cid [string trim $cid]
    if {$cid eq ""} { return "" }
    if {![info exists contractRegistry($cid,id)]} {
        set contractRegistry($cid,id) $cid
        set contractRegistry($cid,description) [contractCoreDescription $cid]
        set contractRegistry($cid,parents) {}
        set contractRegistry($cid,providers) {}
        set contractRegistry($cid,producers) {}
        set contractRegistry($cid,consumers) {}
    }
    return $cid
}

proc ::GX::contractRegistryAddRole {cid field moduleId} {
    variable contractRegistry
    set cid [contractRegistryEnsure $cid]
    if {$cid eq ""} { return }
    set cur $contractRegistry($cid,$field)
    if {$moduleId ne "" && [lsearch -exact $cur $moduleId] < 0} { lappend cur $moduleId }
    set contractRegistry($cid,$field) $cur
}

proc ::GX::contractRegistrySetParents {cid parents} {
    variable contractRegistry
    set cid [contractRegistryEnsure $cid]
    if {$cid eq ""} { return }
    set clean {}
    foreach parent [splitList $parents] {
        set parent [string trim $parent]
        if {$parent eq "" || $parent eq $cid} continue
        contractRegistryEnsure $parent
        if {[lsearch -exact $clean $parent] < 0} { lappend clean $parent }
    }
    set contractRegistry($cid,parents) $clean
}

# v0.9.4 additive contract-specialization matching. Unknown/custom contracts
# retain historical exact-match semantics unless a provider declares parents.
proc ::GX::contractSatisfies {actual expected} {
    variable contractRegistry
    set actual [string trim $actual]
    set expected [string trim $expected]
    if {$actual eq "" || $expected eq ""} { return 0 }
    if {$actual eq $expected} { return 1 }
    if {![info exists contractRegistry($actual,id)]} { return 0 }
    set todo [contractRegistryField $actual parents {}]
    set seen [list $actual]
    while {[llength $todo]} {
        set cur [lindex $todo 0]
        set todo [lrange $todo 1 end]
        if {$cur eq $expected} { return 1 }
        if {[lsearch -exact $seen $cur] >= 0} continue
        lappend seen $cur
        if {[info exists contractRegistry($cur,id)]} {
            foreach parent [contractRegistryField $cur parents {}] {
                if {[lsearch -exact $seen $parent] < 0} { lappend todo $parent }
            }
        }
    }
    return 0
}

proc ::GX::contractSatisfiesAny {actual expectedList} {
    # Callers historically pass both descriptor strings (a;b,c) and already
    # split Tcl lists. Preserve both forms.
    if {![regexp {[;,]} $expectedList] && [llength $expectedList] > 1} {
        set expectedItems $expectedList
    } else {
        set expectedItems [splitList $expectedList]
    }
    foreach expected $expectedItems {
        if {[contractSatisfies $actual $expected]} { return 1 }
    }
    return 0
}

proc ::GX::refreshContractRegistry {} {
    variable contractRegistry
    variable contractOrder
    variable moduleOrder
    variable moduleCatalog
    array unset contractRegistry *
    set contractOrder {}

    # Stable framework contracts remain available even when no current plugin
    # happens to consume them. Plugin descriptors extend this registry.
    foreach cid {raw.csv table.generic timeseries.table curve_family.table spectrum.table spectrum.scientific spectrum.family} {
        contractRegistryAddRole $cid providers "GX-TXT core"
    }
    contractRegistrySetParents timeseries.table {table.generic}
    contractRegistrySetParents curve_family.table {table.generic}
    contractRegistrySetParents spectrum.table {table.generic}
    contractRegistrySetParents spectrum.scientific {table.generic}
    contractRegistrySetParents spectrum.family {curve_family.table}

    foreach mid $moduleOrder {
        foreach cid [splitList [moduleField $mid inputs ""]] {
            contractRegistryAddRole $cid consumers $mid
        }
        foreach cid [splitList [moduleField $mid output_datasets ""]] {
            contractRegistryAddRole $cid producers $mid
        }
        # Optional forward-compatible declaration for plugins that explicitly
        # provide additional contracts.
        if {[info exists moduleCatalog($mid,dict)]} {
            set d $moduleCatalog($mid,dict)
            foreach cid [splitList [descriptorValue $d contracts provided ""]] {
                contractRegistryAddRole $cid providers $mid
                set desc [descriptorValue $d "contract.$cid" description ""]
                if {$desc ne ""} { set contractRegistry($cid,description) $desc }
                set parents [descriptorValue $d "contract.$cid" parents [descriptorValue $d "contract.$cid" parent ""]]
                if {[string trim $parents] ne ""} { contractRegistrySetParents $cid $parents }
            }
        }
    }
    set ids {}
    foreach k [array names contractRegistry "*,id"] {
        lappend ids [string range $k 0 end-3]
    }
    set contractOrder [lsort -dictionary -unique $ids]
    catch {refreshGenericCsvContractWidgets}
    return $contractOrder
}

proc ::GX::contractRegistryIds {} {
    variable contractOrder
    if {![llength $contractOrder]} { refreshContractRegistry }
    return $contractOrder
}

proc ::GX::contractRegistryKnown {cid} {
    variable contractRegistry
    return [info exists contractRegistry($cid,id)]
}

proc ::GX::contractRegistryField {cid field {default ""}} {
    variable contractRegistry
    if {[info exists contractRegistry($cid,$field)]} { return $contractRegistry($cid,$field) }
    return $default
}

proc ::GX::contractRegistryChoices {} {
    return [concat [contractRegistryIds] [list "Other..."]]
}

proc ::GX::contractModulesWithState {mods} {
    set out {}
    foreach mid $mods {
        if {$mid eq "GX-TXT core"} { lappend out $mid; continue }
        set state [expr {[catch {moduleIsEnabled $mid} active] || !$active ? "installed" : "active"}]
        lappend out "$mid ($state)"
    }
    return $out
}

proc ::GX::contractRegistryDialog {} {
    variable contractOrder
    set w .contractRegistry
    catch {destroy $w}
    toplevel $w
    wm title $w "Dataset contract registry"
    wm transient $w .
    wm geometry $w 900x560
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    ttk::label $w.info -text "Contracts are discovered from installed plugin descriptors. 'Other...' remains available for undeclared/custom contracts. Active/installed status updates when module selection changes." -wraplength 860 -justify left
    grid $w.info -row 0 -column 0 -sticky ew -padx 10 -pady 8
    text $w.txt -wrap word -font TkFixedFont
    ttk::scrollbar $w.sy -orient vertical -command [list $w.txt yview]
    $w.txt configure -yscrollcommand [list $w.sy set]
    grid $w.txt -row 1 -column 0 -sticky nsew -padx {10 0} -pady 4
    grid $w.sy -row 1 -column 1 -sticky ns -padx {0 10} -pady 4
    foreach cid [contractRegistryIds] {
        $w.txt insert end "$cid\n"
        $w.txt insert end "  [contractRegistryField $cid description]\n"
        set parents [contractRegistryField $cid parents {}]
        $w.txt insert end "  Parent contracts: [expr {[llength $parents] ? [join $parents {, }] : {-}}]\n"
        set p [contractRegistryField $cid providers {}]
        set o [contractRegistryField $cid producers {}]
        set c [contractRegistryField $cid consumers {}]
        $w.txt insert end "  Declared/provided by: [expr {[llength $p] ? [join [contractModulesWithState $p] {, }] : {-}}]\n"
        $w.txt insert end "  Produced by: [expr {[llength $o] ? [join [contractModulesWithState $o] {, }] : {-}}]\n"
        $w.txt insert end "  Accepted by: [expr {[llength $c] ? [join [contractModulesWithState $c] {, }] : {-}}]\n\n"
    }
    $w.txt configure -state disabled
    ttk::button $w.close -text "Close" -command [list destroy $w]
    grid $w.close -row 2 -column 0 -columnspan 2 -sticky e -padx 10 -pady 8
}

# Build registry after every catalog load without changing discovery semantics.
proc ::GX::loadModuleCatalog_v083_before_documentation_api {} {
    ::GX::loadModuleCatalog_v081_before_contract_registry
    refreshContractRegistry
}

# Keep contract status/details synchronized with module activation while never
# deleting unknown values already stored in a session.
proc ::GX::moduleSetEnabled {id state {cascade 1}} {
    set r [::GX::moduleSetEnabled_v081_before_contract_registry $id $state $cascade]
    catch {refreshContractRegistry}
    return $r
}

proc ::GX::genericCsvSetContractUi {slot value} {
    variable genericContractChoice
    variable genericContractCustom
    set value [string trim $value]
    if {[contractRegistryKnown $value]} {
        set genericContractChoice($slot) $value
        set genericContractCustom($slot) ""
    } else {
        set genericContractChoice($slot) "Other..."
        set genericContractCustom($slot) $value
    }
}

proc ::GX::genericCsvSingleContractChanged {} {
    variable moduleCfg
    variable genericContractChoice
    variable genericContractCustom
    if {![info exists genericContractChoice(single)]} { return }
    if {$genericContractChoice(single) eq "Other..."} {
        set moduleCfg(acq.generic_csv,dataset_kind) [string trim $genericContractCustom(single)]
    } else {
        set moduleCfg(acq.generic_csv,dataset_kind) $genericContractChoice(single)
    }
    catch {refreshManifestPreview}
}

proc ::GX::genericCsvBatchResolvedContract {i} {
    variable genericCsvBatch
    if {![info exists genericCsvBatch($i,contract_choice)]} { return "" }
    if {$genericCsvBatch($i,contract_choice) eq "Other..."} {
        return [string trim $genericCsvBatch($i,custom_contract)]
    }
    return [string trim $genericCsvBatch($i,contract_choice)]
}

proc ::GX::genericCsvBatchSetContract {i value} {
    variable genericCsvBatch
    set value [string trim $value]
    if {[contractRegistryKnown $value]} {
        set genericCsvBatch($i,contract_choice) $value
        set genericCsvBatch($i,custom_contract) ""
    } else {
        set genericCsvBatch($i,contract_choice) "Other..."
        set genericCsvBatch($i,custom_contract) $value
    }
}

proc ::GX::genericCsvBatchContractChanged {i} {
    variable genericCsvBatch
    if {![info exists genericCsvBatch($i,contract_choice)]} { return }
    catch {refreshManifestPreview}
}

proc ::GX::refreshGenericCsvContractWidgets {} {
    variable ui
    variable moduleCfg
    variable genericCsvBatchCount
    set vals [contractRegistryChoices]
    if {[info exists ui(genericContractCombo,single)] && [winfo exists $ui(genericContractCombo,single)]} {
        $ui(genericContractCombo,single) configure -values $vals
        if {[info exists moduleCfg(acq.generic_csv,dataset_kind)]} { genericCsvSetContractUi single $moduleCfg(acq.generic_csv,dataset_kind) }
    }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {[info exists ui(genericContractCombo,$i)] && [winfo exists $ui(genericContractCombo,$i)]} {
            $ui(genericContractCombo,$i) configure -values $vals
        }
    }
}

# Replace only the dataset_kind editor with a registry-backed combobox plus the
# explicit Other... field. All other descriptor-generated widgets remain on
# the existing Standard Module API path.
proc ::GX::standardConfigWidget_v083_before_analysis_parameters {parent id key row} {
    variable moduleCfg
    variable ui
    variable genericContractChoice
    variable genericContractCustom
    if {$id ne "acq.generic_csv" || $key ne "dataset_kind"} {
        return [::GX::standardConfigWidget_v081_before_contract_registry $parent $id $key $row]
    }
    set label [moduleConfigField $id $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::frame $parent.w$row
    genericCsvSetContractUi single $moduleCfg($id,$key)
    ttk::combobox $parent.w$row.choice -textvariable ::GX::genericContractChoice(single) -values [contractRegistryChoices] -state readonly -width 24
    ttk::label $parent.w$row.ol -text "Other:"
    ttk::entry $parent.w$row.other -textvariable ::GX::genericContractCustom(single) -width 26
    set ui(genericContractCombo,single) $parent.w$row.choice
    bind $parent.w$row.choice <<ComboboxSelected>> {::GX::genericCsvSingleContractChanged}
    bind $parent.w$row.other <KeyRelease> {::GX::genericCsvSingleContractChanged}
    pack $parent.w$row.choice $parent.w$row.ol $parent.w$row.other -side left -padx {0 5}
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
}

proc ::GX::genericCsvAutoDatasetId {path} {
    set id [string tolower [file rootname [file tail $path]]]
    regsub -all {[^a-z0-9_.-]+} $id {_} id
    set id [string trim $id "._-"]
    if {$id eq ""} { set id "dataset" }
    return $id
}

proc ::GX::genericCsvBatchAdd_v088_before_acquisition_handler_batch {{path ""}} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    variable genericCsvBatchEnabled
    variable moduleCfg
    variable cfg
    incr genericCsvBatchCount
    set i $genericCsvBatchCount
    set genericCsvBatch($i,enabled) 1
    if {$path eq "" && $genericCsvBatchCount == 1 && [info exists cfg(input_csv)]} { set path $cfg(input_csv) }
    set genericCsvBatch($i,path) $path
    set genericCsvBatch($i,dataset_id) [expr {$path ne "" ? [genericCsvAutoDatasetId $path] : "dataset.$i"}]
    set value [expr {[info exists moduleCfg(acq.generic_csv,dataset_kind)] ? $moduleCfg(acq.generic_csv,dataset_kind) : "table.generic"}]
    genericCsvBatchSetContract $i $value
    set genericCsvBatch($i,delimiter) [expr {[info exists moduleCfg(acq.generic_csv,delimiter)] ? $moduleCfg(acq.generic_csv,delimiter) : "auto"}]
    set genericCsvBatch($i,header_rows) [expr {[info exists moduleCfg(acq.generic_csv,header_rows)] ? $moduleCfg(acq.generic_csv,header_rows) : 1}]
    set genericCsvBatchEnabled 1
    catch {genericCsvBatchRender}
    catch {refreshManifestPreview}
    return $i
}
proc ::GX::genericCsvBatchAdd {{path ""}} {
    return [::GX::genericCsvBatchAdd_v088_before_acquisition_handler_batch $path]
}

proc ::GX::genericCsvBatchAddMultiple_v087_before_workspace_profiles {} {
    set paths [tk_getOpenFile -multiple 1 -filetypes {{{CSV / text tables} {.csv .txt .tsv}} {{All files} *}}]
    if {![llength $paths]} { return }
    foreach p $paths { genericCsvBatchAdd $p }
}
proc ::GX::genericCsvBatchAddMultiple {} {
    return [::GX::genericCsvBatchAddMultiple_v087_before_workspace_profiles]
}

proc ::GX::genericCsvBatchBrowse_v085_before_dataset_inspection {i} {
    variable genericCsvBatch
    set p [tk_getOpenFile -filetypes {{{CSV / text tables} {.csv .txt .tsv}} {{All files} *}}]
    if {$p eq ""} { return }
    set genericCsvBatch($i,path) $p
    if {![info exists genericCsvBatch($i,dataset_id)] || [string trim $genericCsvBatch($i,dataset_id)] eq "" || [string match "dataset.*" $genericCsvBatch($i,dataset_id)]} {
        set genericCsvBatch($i,dataset_id) [genericCsvAutoDatasetId $p]
    }
    catch {refreshManifestPreview}
}
proc ::GX::genericCsvBatchBrowse {i} {
    return [::GX::genericCsvBatchBrowse_v085_before_dataset_inspection $i]
}

proc ::GX::genericCsvBatchRemove_v085_before_dataset_inspection {idx} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    if {$idx < 1 || $idx > $genericCsvBatchCount} { return }
    set fields {enabled path dataset_id contract_choice custom_contract delimiter header_rows}
    for {set i $idx} {$i < $genericCsvBatchCount} {incr i} {
        foreach f $fields {
            set genericCsvBatch($i,$f) [expr {[info exists genericCsvBatch([expr {$i+1}],$f)] ? $genericCsvBatch([expr {$i+1}],$f) : ""}]
        }
    }
    foreach f $fields { catch {unset genericCsvBatch($genericCsvBatchCount,$f)} }
    incr genericCsvBatchCount -1
    catch {genericCsvBatchRender}
    catch {refreshManifestPreview}
}
proc ::GX::genericCsvBatchRemove {idx} {
    return [::GX::genericCsvBatchRemove_v085_before_dataset_inspection $idx]
}

proc ::GX::genericCsvBatchClear_v085_before_dataset_inspection {} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    variable genericCsvBatchEnabled
    array unset genericCsvBatch *
    set genericCsvBatchCount 0
    set genericCsvBatchEnabled 0
    catch {genericCsvBatchRender}
    catch {refreshManifestPreview}
}
proc ::GX::genericCsvBatchClear {} {
    return [::GX::genericCsvBatchClear_v085_before_dataset_inspection]
}

proc ::GX::genericCsvBatchScrollRefresh {} {
    variable ui
    if {![info exists ui(genericBatchCanvas)] || ![winfo exists $ui(genericBatchCanvas)]} { return }
    set c $ui(genericBatchCanvas)
    if {[info exists ::GX::interactiveImportQueue] && $::GX::interactiveImportQueue && [info exists ui(genericBatchWindow)]} {
        set width [expr {max([winfo width $c],[winfo reqwidth $ui(genericBatchInner)])}]
        if {[$c itemcget $ui(genericBatchWindow) -width] != $width} {$c itemconfigure $ui(genericBatchWindow) -width $width}
    }
    set bb [$c bbox all]
    if {[llength $bb] == 4} { $c configure -scrollregion $bb }
}

proc ::GX::genericCsvBatchRender_v085_before_dataset_inspection {} {
    variable ui
    variable genericCsvBatch
    variable genericCsvBatchCount
    if {![info exists ui(genericBatchInner)] || ![winfo exists $ui(genericBatchInner)]} { return }
    set p $ui(genericBatchInner)
    foreach child [winfo children $p] { destroy $child }
    foreach {col txt} {0 Use 1 {CSV file} 2 {} 3 {Dataset ID} 4 Contract 5 {Other / custom contract} 6 Delimiter 7 Header 8 {}} {
        if {$txt ne ""} { ttk::label $p.h$col -text $txt; grid $p.h$col -row 0 -column $col -sticky w -padx 3 -pady 2 }
    }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set r $i
        ttk::checkbutton $p.use$i -variable ::GX::genericCsvBatch($i,enabled)
        ttk::entry $p.path$i -textvariable ::GX::genericCsvBatch($i,path) -width 48
        ttk::button $p.browse$i -text "..." -width 3 -command [list ::GX::genericCsvBatchBrowse $i]
        ttk::entry $p.id$i -textvariable ::GX::genericCsvBatch($i,dataset_id) -width 22
        ttk::combobox $p.kind$i -textvariable ::GX::genericCsvBatch($i,contract_choice) -values [contractRegistryChoices] -state readonly -width 22
        ttk::entry $p.other$i -textvariable ::GX::genericCsvBatch($i,custom_contract) -width 24
        ttk::combobox $p.delim$i -textvariable ::GX::genericCsvBatch($i,delimiter) -values {auto comma semicolon tab} -state readonly -width 10
        ttk::spinbox $p.head$i -from 1 -to 999 -textvariable ::GX::genericCsvBatch($i,header_rows) -width 6
        ttk::button $p.rm$i -text "Remove" -command [list ::GX::genericCsvBatchRemove $i]
        set ui(genericContractCombo,$i) $p.kind$i
        bind $p.kind$i <<ComboboxSelected>> [list ::GX::genericCsvBatchContractChanged $i]
        bind $p.other$i <KeyRelease> [list ::GX::refreshManifestPreview]
        grid $p.use$i -row $r -column 0 -padx 3 -pady 2
        grid $p.path$i -row $r -column 1 -sticky ew -padx 3 -pady 2
        grid $p.browse$i -row $r -column 2 -padx 1 -pady 2
        grid $p.id$i -row $r -column 3 -padx 3 -pady 2
        grid $p.kind$i -row $r -column 4 -padx 3 -pady 2
        grid $p.other$i -row $r -column 5 -padx 3 -pady 2
        grid $p.delim$i -row $r -column 6 -padx 3 -pady 2
        grid $p.head$i -row $r -column 7 -padx 3 -pady 2
        grid $p.rm$i -row $r -column 8 -padx 3 -pady 2
    }
    update idletasks
    genericCsvBatchScrollRefresh
}
proc ::GX::genericCsvBatchRender {} {
    return [::GX::genericCsvBatchRender_v085_before_dataset_inspection]
}

proc ::GX::buildGenericCsvBatchGui_v082_base {} {
    variable ui
    variable genericCsvBatchEnabled
    set host .top.nb.acq
    if {![winfo exists $host]} { return }
    if {[winfo exists $host.cfg.box]} { $host.cfg.box configure -text "$::GX::cfg(acquisition_module) import options" }
    catch {destroy $host.batch}
    ttk::labelframe $host.batch -text "Pending imports"
    grid $host.batch -row 2 -column 0 -sticky nsew -padx 5 -pady {2 6}
    grid columnconfigure $host.batch 0 -weight 1
    grid rowconfigure $host.batch 2 -weight 1
    ttk::frame $host.batch.bar
    ttk::button $host.batch.bar.add -text "+ Add file" -command ::GX::genericCsvBatchChooseOne
    ttk::button $host.batch.bar.multi -text "Add multiple..." -command ::GX::genericCsvBatchAddMultiple
    ttk::button $host.batch.bar.clear -text "Clear" -command ::GX::genericCsvBatchClear
    ttk::button $host.batch.bar.contracts -text "Contract registry..." -command ::GX::contractRegistryDialog
    pack $host.batch.bar.add $host.batch.bar.multi $host.batch.bar.clear $host.batch.bar.contracts -side left -padx 3
    grid $host.batch.bar -row 0 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 3
    ttk::label $host.batch.note -text "Select files for the current Session. Imported rows leave this temporary queue; failed rows remain for correction and retry." -wraplength 480 -justify left
    bind $host.batch.note <Configure> {%W configure -wraplength [expr {max(180,%w-4)}]}
    grid $host.batch.note -row 1 -column 0 -columnspan 2 -sticky ew -padx 4 -pady {0 4}
    canvas $host.batch.c -height 190 -highlightthickness 0
    ttk::scrollbar $host.batch.sy -orient vertical -command [list $host.batch.c yview]
    ttk::scrollbar $host.batch.sx -orient horizontal -command [list $host.batch.c xview]
    $host.batch.c configure -yscrollcommand [list $host.batch.sy set] -xscrollcommand [list $host.batch.sx set]
    ttk::frame $host.batch.c.inner
    set win [$host.batch.c create window 0 0 -anchor nw -window $host.batch.c.inner]
    set ui(genericBatchCanvas) $host.batch.c
    set ui(genericBatchInner) $host.batch.c.inner
    set ui(genericBatchWindow) $win
    bind $host.batch.c.inner <Configure> {::GX::genericCsvBatchScrollRefresh}
    bind $host.batch.c <Configure> {::GX::genericCsvBatchScrollRefresh}
    grid $host.batch.c -row 2 -column 0 -sticky nsew -padx {4 0} -pady {0 0}
    grid $host.batch.sy -row 2 -column 1 -sticky ns -padx {0 4}
    grid $host.batch.sx -row 3 -column 0 -sticky ew -padx {4 0} -pady {0 4}
    genericCsvBatchRender
}

# Add the batch workspace after the established GUI has been built. Existing
# acquisition widgets and APIs are retained.
proc ::GX::augmentStandardGui_v083_before_documentation_api {} {
    ::GX::augmentStandardGui_v081_before_csv_batch
    buildGenericCsvBatchGui
    refreshGenericCsvContractWidgets
}

proc ::GX::genericCsvBatchEnabledRows {} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    set out {}
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {[info exists genericCsvBatch($i,enabled)] && $genericCsvBatch($i,enabled)} { lappend out $i }
    }
    return $out
}

proc ::GX::genericCsvBatchValidate_v085_before_dataset_inspection {} {
    variable cfg
    variable genericCsvBatch
    variable genericCsvBatchEnabled
    if {!$genericCsvBatchEnabled} { return }
    if {$cfg(output_root) eq ""} { error "Specify the session root folder." }
    set rows [genericCsvBatchEnabledRows]
    if {![llength $rows]} { error "Multi-CSV batch import is enabled but no rows are enabled." }
    set ids {}
    foreach i $rows {
        set path [string trim $genericCsvBatch($i,path)]
        if {$path eq "" || ![file isfile $path]} { error "Batch row $i: select an existing CSV file." }
        set id [string trim $genericCsvBatch($i,dataset_id)]
        if {$id eq "" || ![regexp {^[A-Za-z0-9_.-]+$} $id]} { error "Batch row $i: Dataset ID may contain only letters, digits, '.', '_' and '-'." }
        if {[lsearch -exact $ids $id] >= 0} { error "Batch row $i: duplicate Dataset ID '$id'." }
        lappend ids $id
        set kind [genericCsvBatchResolvedContract $i]
        if {$kind eq ""} { error "Batch row $i: choose a dataset contract or enter Other/custom contract." }
        if {[regexp {[\r\n]} $kind]} { error "Batch row $i: dataset contract must be a single line." }
        set hr $genericCsvBatch($i,header_rows)
        if {![string is integer -strict $hr] || $hr < 1} { error "Batch row $i: Header rows must be an integer >= 1." }
        if {$genericCsvBatch($i,delimiter) ni {auto comma semicolon tab , ;}} { error "Batch row $i: unsupported delimiter '$genericCsvBatch($i,delimiter)'." }
    }
}

proc ::GX::genericCsvBatchValidate {} {
    return [::GX::genericCsvBatchValidate_v085_before_dataset_inspection]
}

# Preserve the historical single-file validator exactly when batch mode is off.
proc ::GX::genericCsvValidate {} {
    variable genericCsvBatchEnabled
    if {$genericCsvBatchEnabled} { return [genericCsvBatchValidate] }
    return [::GX::genericCsvValidate_v081_single]
}

proc ::GX::genericCsvReadHeaderColumns {path delimiter} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8 -translation auto
    if {[gets $fd line] < 0} { close $fd; return {} }
    close $fd
    set cols {}
    foreach c [split $line $delimiter] { lappend cols [string trim $c " \t\r\n\""] }
    return $cols
}

proc ::GX::genericCsvBatchImportSync_v085_before_dataset_inspection {} {
    variable cfg
    variable genericCsvBatch
    variable currentSession
    variable scriptDir
    genericCsvBatchValidate
    set cfg(session_mode) "analysis_only"
    set rows [genericCsvBatchEnabledRows]
    # Keep the historical acquisition.input_csv field meaningful for old tools.
    if {[llength $rows]} { set cfg(input_csv) $genericCsvBatch([lindex $rows 0],path) }
    set session [makeSession]
    file mkdir [file join $session datasets]
    datasetRegistryClear
    set logLines {}
    foreach i $rows {
        set src [file normalize $genericCsvBatch($i,path)]
        set id [string trim $genericCsvBatch($i,dataset_id)]
        set kind [genericCsvBatchResolvedContract $i]
        set rawRel [file join raw $id [file tail $src]]
        set rawDst [file join $session $rawRel]
        file mkdir [file dirname $rawDst]
        file copy -force -- $src $rawDst
        set srcHash [sha256File $rawDst]

        set dataRel [file join datasets "${id}.csv"]
        set dataDst [file join $session $dataRel]
        set setting $genericCsvBatch($i,delimiter)
        set delim [csvDelimiter $rawDst $setting]
        set token [expr {$delim eq "," ? "comma" : ($delim eq ";" ? "semicolon" : "tab")}]
        set helper [file join $scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
        set cmd [list [runtimeToolRequired python] $helper --input $rawDst --output $dataDst --delimiter $token --header-rows $genericCsvBatch($i,header_rows)]
        if {[catch {exec {*}$cmd 2>@1} out opts]} { error "Batch row $i ($id): canonical CSV conversion failed: $out" }
        set canonHash [sha256File $dataDst]
        set cols [genericCsvReadHeaderColumns $dataDst $delim]
        if {![llength $cols]} { error "Batch row $i ($id): canonical CSV has no header columns." }
        datasetRegister $id [list kind $kind format csv path $dataRel columns [join $cols ,] variables [join $cols ,] source_module acq.generic_csv source_raw $rawRel source_sha256 $srcHash canonical_sha256 $canonHash created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 notes "Canonical CSV generated by GX-TXT v0.8.2 multi-CSV identity import"]
        lappend logLines "Dataset: $id | contract: $kind | source: $src | variables: [join $cols ,] | RAW SHA-256: $srcHash | Canonical SHA-256: $canonHash"
    }
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
    set log [open [file join $session logs pipeline.log] w]
    fconfigure $log -encoding utf-8 -translation lf
    puts $log "Standard Module API v1 / Manifest format 2"
    puts $log "Acquisition module: acq.generic_csv"
    puts $log "Mode: multi_csv_batch"
    puts $log "Dataset count: [llength $rows]"
    foreach line $logLines { puts $log $line }
    close $log
    set currentSession $session
    return $session
}

proc ::GX::genericCsvBatchImportSync {} {
    return [::GX::genericCsvBatchImportSync_v085_before_dataset_inspection]
}

# Batch mode is an additive path; the established single-file import and its
# source-variable mapping are left untouched when batch mode is disabled.
proc ::GX::genericCsvImportSync {} {
    variable genericCsvBatchEnabled
    if {$genericCsvBatchEnabled} { return [genericCsvBatchImportSync] }
    return [::GX::genericCsvImportSync_v081_single]
}

# Manifest Format 2 persistence for the batch table. Unknown/custom contracts
# are stored literally so disabling/removing a plugin never destroys a session.
proc ::GX::manifestStringV2_v083_before_documentation_api {} {
    variable genericCsvBatchEnabled
    variable genericCsvBatchCount
    variable genericCsvBatch
    set out [::GX::manifestStringV2_v081_before_csv_batch]
    append out "\n\[contract_registry_api\]\n"
    appendKV out version $::GX::contractRegistryApiVersion
    append out "\n\[generic_csv_batch\]\n"
    appendKV out api_version 1
    appendKV out enabled $genericCsvBatchEnabled
    appendKV out count $genericCsvBatchCount
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        append out "\n\[generic_csv_batch.$i\]\n"
        foreach f {enabled path dataset_id delimiter header_rows} {
            appendKV out $f [expr {[info exists genericCsvBatch($i,$f)] ? $genericCsvBatch($i,$f) : ""}]
        }
        appendKV out contract [genericCsvBatchResolvedContract $i]
    }
    return $out
}

proc ::GX::loadManifestV2_v083_before_analysis_parameters {path} {
    variable genericCsvBatchEnabled
    variable genericCsvBatchCount
    variable genericCsvBatch
    ::GX::loadManifestV2_v081_before_csv_batch $path
    set d [parseIni $path]
    array unset genericCsvBatch *
    set genericCsvBatchEnabled [expr {[dict exists $d generic_csv_batch.enabled] ? [dict get $d generic_csv_batch.enabled] : 0}]
    set genericCsvBatchCount [expr {[dict exists $d generic_csv_batch.count] ? [dict get $d generic_csv_batch.count] : 0}]
    if {![string is integer -strict $genericCsvBatchCount] || $genericCsvBatchCount < 0} { set genericCsvBatchCount 0 }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set pre "generic_csv_batch.$i"
        foreach {f def} {enabled 1 path "" dataset_id "" delimiter auto header_rows 1} {
            set k "$pre.$f"
            set genericCsvBatch($i,$f) [expr {[dict exists $d $k] ? [dict get $d $k] : $def}]
        }
        set k "$pre.contract"
        set val [expr {[dict exists $d $k] ? [dict get $d $k] : "table.generic"}]
        genericCsvBatchSetContract $i $val
    }
    catch {genericCsvBatchRender}
    catch {refreshGenericCsvContractWidgets}
}

# v0.8.2 final GUI/state hooks -------------------------------------------------
proc ::GX::defaults_v083_before_analysis_parameters {} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    variable genericCsvBatchEnabled
    variable genericContractChoice
    variable genericContractCustom
    ::GX::defaults_v081_before_v082_state
    array unset genericCsvBatch *
    array unset genericContractChoice *
    array unset genericContractCustom *
    set genericCsvBatchCount 0
    set genericCsvBatchEnabled 0
}

proc ::GX::refreshGenericCsvBatchVisibility_before_import_queue {} {
    variable cfg
    set w .top.nb.acq.batch
    if {![llength [info commands winfo]] || ![winfo exists $w]} { return }
    if {[info exists cfg(acquisition_module)] && $cfg(acquisition_module) eq "acq.generic_csv"} {
        grid $w
    } else {
        grid remove $w
    }
}

proc ::GX::refreshGenericCsvBatchVisibility {} {
    tailcall ::GX::refreshGenericCsvBatchVisibility_before_import_queue
}

proc ::GX::refreshNativeAcquisitionConfig_v089_before_acq_native_gui {} {
    ::GX::refreshNativeAcquisitionConfig_v081_before_v082_batch
    catch {refreshGenericCsvContractWidgets}
    catch {refreshGenericCsvBatchVisibility}
}

# The batch frame is built after the native Acquisition tab has been rebuilt.
# Keep it visible only for acq.generic_csv; other acquisition modules are
# untouched.
proc ::GX::buildGenericCsvBatchGui {} {
    ::GX::buildGenericCsvBatchGui_v082_base
    refreshGenericCsvBatchVisibility
}


# -----------------------------------------------------------------------------
# v0.8.4 Documentation API v1
# -----------------------------------------------------------------------------
# Documentation is a public plugin contract.  v0.8.4 keeps legacy descriptors
# loadable for backward compatibility, but plugin authors MUST declare this API.
# Future releases may silently stop exposing/running plugins that omit it.
namespace eval ::GX {
    variable documentationApiVersion 1
    variable documentationRegistry
    variable documentationOrder {}
}

proc ::GX::documentationDescriptorInfo {kind id} {
    variable moduleCatalog
    variable modelCatalog
    variable analysisDefinitionCatalog
    variable instrumentCatalog
    switch -- $kind {
        module {
            if {![info exists moduleCatalog($id,descriptor)]} { return {} }
            return [list $moduleCatalog($id,descriptor) $moduleCatalog($id,dict) [moduleField $id name $id]]
        }
        model {
            if {![info exists modelCatalog($id,descriptor)]} { return {} }
            set path $modelCatalog($id,descriptor)
            return [list $path [parseIni $path] [modelField $id name $id]]
        }
        analysis_definition {
            if {![info exists analysisDefinitionCatalog($id,descriptor)]} { return {} }
            return [list $analysisDefinitionCatalog($id,descriptor) $analysisDefinitionCatalog($id,dict) [analysisDefinitionField $id name $id]]
        }
        instrument {
            if {![info exists instrumentCatalog($id,descriptor)]} { return {} }
            set path $instrumentCatalog($id,descriptor)
            return [list $path $instrumentCatalog($id,dict) [instrumentModuleName $id]]
        }
    }
    return {}
}

proc ::GX::documentationResolvePluginPath {descriptor rel} {
    set rel [string trim $rel]
    if {$rel eq ""} { return "" }
    if {[file pathtype $rel] ne "relative"} { return [file normalize $rel] }
    return [file normalize [file join [file dirname $descriptor] $rel]]
}

proc ::GX::documentationResolveApiRef {ref} {
    variable scriptDir
    set ref [string trim $ref]
    if {$ref eq ""} { return "" }
    if {[file pathtype $ref] ne "relative"} { return [file normalize $ref] }
    if {[string match */* $ref]} { return [file normalize [file join $scriptDir $ref]] }
    set api [file rootname $ref]
    set filename [expr {[file extension $ref] eq {}?"$ref.md":$ref}]
    set common [file normalize [file join $scriptDir docs api $filename]]
    if {[file isfile $common]} {return $common}
    # Installed providers own their API manuals. Resolve descriptor declarations
    # without activating scientific code; conflicting documents stay unavailable.
    set paths {}
    foreach module $::GX::moduleOrder {
        set info [documentationDescriptorInfo module $module]
        if {$info eq {}} continue
        lassign $info descriptor d name
        if {$api ni [splitList [descriptorValue $d public_apis ids {}]]} continue
        set relative [descriptorValue $d public_api.$api documentation {}]
        if {$relative eq {}||[file pathtype $relative] ne {relative}||{..} in [file split $relative]} continue
        set ownerRoot [file normalize [file dirname $descriptor]]
        set path [file normalize [file join $ownerRoot $relative]]
        if {[string first "$ownerRoot/" "$path/"]!=0||![file isfile $path]||[file type $path] eq {link}} continue
        lappend paths $path
    }
    set paths [lsort -unique $paths]
    if {[llength $paths]==1} {return [lindex $paths 0]}
    if {[llength $paths]>1} {return {}}
    return $common
}

proc ::GX::documentationValidateOne {kind id} {
    set info [documentationDescriptorInfo $kind $id]
    if {![llength $info]} { return [dict create status missing errors [list descriptor_missing] warnings {}] }
    lassign $info descriptor d name
    set api [string trim [descriptorValue $d documentation api_version ""]]
    set errors {}; set warnings {}
    if {$api eq ""} {
        # Backward-compatible in v0.8.4 only.  Normative policy is still MUST.
        lappend warnings documentation_api_missing
        return [dict create status legacy_missing errors $errors warnings $warnings]
    }
    if {$api ne "1"} { lappend errors unsupported_documentation_api }
    set guide [string trim [descriptorValue $d documentation guide ""]]
    if {$guide eq ""} {
        lappend errors guide_missing
    } else {
        set gp [documentationResolvePluginPath $descriptor $guide]
        if {![file isfile $gp]} { lappend errors guide_not_found }
    }
    foreach rel [splitList [descriptorValue $d documentation examples ""]] {
        if {![file isfile [documentationResolvePluginPath $descriptor $rel]]} { lappend errors "example_not_found:$rel" }
    }
    set ch [string trim [descriptorValue $d documentation changelog ""]]
    if {$ch ne "" && ![file isfile [documentationResolvePluginPath $descriptor $ch]]} { lappend errors changelog_not_found }
    set notices [string trim [descriptorValue $d documentation third_party_notices ""]]
    if {$notices ne "" && ![file isfile [documentationResolvePluginPath $descriptor $notices]]} {
        lappend errors third_party_notices_not_found
    }
    foreach ref [splitList [descriptorValue $d documentation api_refs ""]] {
        if {![file isfile [documentationResolveApiRef $ref]]} { lappend errors "api_ref_not_found:$ref" }
    }
    set status [expr {[llength $errors] ? "invalid" : "valid"}]
    return [dict create status $status errors $errors warnings $warnings]
}

proc ::GX::refreshDocumentationRegistry {} {
    variable documentationRegistry
    variable documentationOrder
    variable moduleOrder
    variable modelOrder
    variable analysisDefinitionOrder
    variable instrumentOrder
    array unset documentationRegistry *
    set documentationOrder {}
    foreach spec [list [list module $moduleOrder] [list model $modelOrder] [list analysis_definition $analysisDefinitionOrder] [list instrument $instrumentOrder]] {
        lassign $spec kind ids
        foreach id $ids {
            set info [documentationDescriptorInfo $kind $id]
            if {![llength $info]} continue
            lassign $info descriptor d name
            set key "$kind:$id"
            set rep [documentationValidateOne $kind $id]
            set documentationRegistry($key,kind) $kind
            set documentationRegistry($key,id) $id
            set documentationRegistry($key,name) $name
            set documentationRegistry($key,descriptor) $descriptor
            set documentationRegistry($key,status) [dict get $rep status]
            set documentationRegistry($key,errors) [dict get $rep errors]
            set documentationRegistry($key,warnings) [dict get $rep warnings]
            set documentationRegistry($key,guide) [descriptorValue $d documentation guide ""]
            set documentationRegistry($key,api_refs) [descriptorValue $d documentation api_refs ""]
            set documentationRegistry($key,examples) [descriptorValue $d documentation examples ""]
            set documentationRegistry($key,changelog) [descriptorValue $d documentation changelog ""]
            lappend documentationOrder $key
        }
    }
    set documentationOrder [lsort -dictionary $documentationOrder]
    return $documentationOrder
}

proc ::GX::documentationField {key field {default ""}} {
    variable documentationRegistry
    if {[info exists documentationRegistry($key,$field)]} { return $documentationRegistry($key,$field) }
    return $default
}

proc ::GX::documentationSummaryFor {kind id} {
    set key "$kind:$id"
    set status [documentationField $key status legacy_missing]
    set out "Documentation API v1: $status"
    set guide [documentationField $key guide ""]
    if {$guide ne ""} { append out "\nGuide: $guide" }
    set refs [documentationField $key api_refs ""]
    if {$refs ne ""} { append out "\nAPI references: $refs" }
    set examples [documentationField $key examples ""]
    if {$examples ne ""} { append out "\nExamples: $examples" }
    set errs [documentationField $key errors {}]
    if {[llength $errs]} { append out "\nErrors: [join $errs {, }]" }
    if {$status eq "legacy_missing"} {
        append out "\nWARNING: backward-compatible legacy plugin. Documentation API v1 is mandatory for plugin authors; future GX-TXT releases may silently enforce it."
    }
    return $out
}

proc ::GX::documentationRegistryDialog {} {
    variable documentationOrder
    if {![llength $documentationOrder]} { refreshDocumentationRegistry }
    set w .documentationRegistry
    catch {destroy $w}
    toplevel $w
    wm title $w "GX-TXT Documentation Registry"
    wm geometry $w 980x650
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    ttk::label $w.note -text "Documentation API v1 is mandatory for plugin authors. v0.8.5 keeps undocumented legacy plugins loadable for compatibility; future releases may silently enforce the requirement." -wraplength 940 -justify left
    grid $w.note -row 0 -column 0 -sticky ew -padx 8 -pady 8
    text $w.txt -wrap word -font TkFixedFont
    ttk::scrollbar $w.sy -orient vertical -command [list $w.txt yview]
    $w.txt configure -yscrollcommand [list $w.sy set]
    grid $w.txt -row 1 -column 0 -sticky nsew -padx {8 0} -pady {0 8}
    grid $w.sy -row 1 -column 1 -sticky ns -pady {0 8}
    foreach key $documentationOrder {
        $w.txt insert end "[documentationField $key kind]  [documentationField $key id]  ([documentationField $key status])\n"
        $w.txt insert end "  [documentationField $key name]\n"
        set guide [documentationField $key guide ""]
        if {$guide ne ""} { $w.txt insert end "  guide: $guide\n" }
        set refs [documentationField $key api_refs ""]
        if {$refs ne ""} { $w.txt insert end "  api_refs: $refs\n" }
        set ex [documentationField $key examples ""]
        if {$ex ne ""} { $w.txt insert end "  examples: $ex\n" }
        set er [documentationField $key errors {}]
        if {[llength $er]} { $w.txt insert end "  errors: [join $er {, }]\n" }
        $w.txt insert end "\n"
    }
    $w.txt configure -state disabled
}

proc ::GX::generateInstalledReference {{path ""}} {
    variable scriptDir
    variable documentationOrder
    variable contractOrder
    variable moduleOrder
    variable analysisDefinitionOrder
    variable modelOrder
    variable instrumentOrder
    if {$path eq ""} { set path [file join $scriptDir docs reference INSTALLED_PLUGIN_REFERENCE.md] }
    file mkdir [file dirname $path]
    refreshDocumentationRegistry
    refreshContractRegistry
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "# GX-TXT installed plugin/API reference"
    puts $fd ""
    puts $fd "Generated from installed descriptors. Normative contracts remain the Markdown files under `docs/api/`."
    puts $fd ""
    puts $fd "## Dataset contracts"
    foreach cid [contractRegistryIds] {
        puts $fd "- `$cid` - [contractRegistryField $cid description]"
        puts $fd "  - providers: [join [contractRegistryField $cid providers {}] {, }]"
        puts $fd "  - producers: [join [contractRegistryField $cid producers {}] {, }]"
        puts $fd "  - consumers: [join [contractRegistryField $cid consumers {}] {, }]"
    }
    puts $fd "\n## Modules"
    foreach id $moduleOrder {
        puts $fd "- `$id` - [moduleField $id name $id]"
        puts $fd "  - inputs: [moduleField $id inputs]"
        puts $fd "  - outputs: [moduleField $id output_datasets] [moduleField $id outputs]"
        puts $fd "  - bindings: [join [moduleBindingRoles $id] {, }]"
        if {[llength [info commands moduleSupportsAnalysisSources]] && [moduleSupportsAnalysisSources $id]} {
            puts $fd "  - analysis source map API: 1"
            puts $fd "  - default source IDs: [join [moduleAnalysisSourceDeclaredIds $id] {, }]"
        }
        puts $fd "  - documentation: [documentationField module:$id status legacy_missing] / [documentationField module:$id guide]"
        set rc [moduleField $id render_cache_api_version ""]
        if {$rc ne ""} { puts $fd "  - render cache API: $rc" }
    }
    puts $fd "\n## Scientific Analysis Definitions"
    foreach id $analysisDefinitionOrder {
        puts $fd "- `$id` - [analysisDefinitionField $id name $id]"
        puts $fd "  - kind: [analysisDefinitionField $id kind]"
        puts $fd "  - capabilities: [analysisDefinitionField $id capabilities]"
        puts $fd "  - documentation: [documentationField analysis_definition:$id status legacy_missing] / [documentationField analysis_definition:$id guide]"
    }
    puts $fd "\n## Mathematical Models"
    foreach id $modelOrder {
        puts $fd "- `$id` - [modelField $id name $id]"
        puts $fd "  - kind: [modelField $id kind]"
        puts $fd "  - documentation: [documentationField model:$id status legacy_missing] / [documentationField model:$id guide]"
    }
    puts $fd "\n## Instruments"
    foreach id $instrumentOrder {
        puts $fd "- `$id` - [instrumentModuleName $id]"
        puts $fd "  - documentation: [documentationField instrument:$id status legacy_missing] / [documentationField instrument:$id guide]"
    }
    puts $fd "\n## Documentation Registry"
    foreach key $documentationOrder {
        puts $fd "- `$key`: [documentationField $key status] - [documentationField $key guide]"
    }
    close $fd
    return $path
}

proc ::GX::loadModuleCatalog_v084_before_analysis_sources {} {
    ::GX::loadModuleCatalog_v083_before_documentation_api
    refreshDocumentationRegistry
}

# Extend the existing help text without changing the established content.
proc ::GX::moduleHelpText_v084_before_analysis_sources {id} {
    set out [::GX::moduleHelpText_v083_before_documentation_api $id]
    append out "\n\nDOCUMENTATION\n[documentationSummaryFor module $id]\n"
    return $out
}

proc ::GX::moduleHelpText {id} {
    return [::GX::moduleHelpText_v084_before_analysis_sources $id]
}

# Add a registry button to the existing Help tab if Tk is active.
proc ::GX::augmentStandardGui_v085_before_dataset_inspection {} {
    ::GX::augmentStandardGui_v083_before_documentation_api
    if {[llength [info commands winfo]] && [winfo exists .top.nb.help.buttons] && ![winfo exists .top.nb.help.buttons.docs]} {
        ttk::button .top.nb.help.buttons.docs -text "Documentation registry..." -command ::GX::documentationRegistryDialog
        pack .top.nb.help.buttons.docs -side left -padx 4
    }
}

proc ::GX::manifestStringV2_v083_before_analysis_parameters {} {
    set out [::GX::manifestStringV2_v083_before_documentation_api]
    append out "\n\[documentation_api\]\n"
    appendKV out version $::GX::documentationApiVersion
    appendKV out policy required_for_plugins
    appendKV out enforcement v084_backward_compatible_warning
    return $out
}

# -----------------------------------------------------------------------------
# v0.8.4 Scientific Analysis parameter GUI + structural preflight
# -----------------------------------------------------------------------------
# These controls are generated entirely from Analysis Definition API v1
# descriptors.  Modules do not create private Tcl panels for scientific
# parameters or binding validation.
namespace eval ::GX {
    variable analysisParamValue
    variable analysisParamDefinition
}

proc ::GX::analysisDefinitionDict {defId} {
    variable analysisDefinitionCatalog
    if {![info exists analysisDefinitionCatalog($defId,dict)]} { return {} }
    return $analysisDefinitionCatalog($defId,dict)
}

proc ::GX::analysisDefinitionParameterIds {defId} {
    set d [analysisDefinitionDict $defId]
    if {$d eq {}} { return {} }
    return [splitList [descriptorValue $d parameters ids ""]]
}

proc ::GX::analysisDefinitionParameterField {defId pid field {default ""}} {
    set d [analysisDefinitionDict $defId]
    if {$d eq {}} { return $default }
    return [descriptorValue $d "parameter.$pid" $field $default]
}

proc ::GX::analysisParametersEnsure {moduleId configKey {reset 0}} {
    variable moduleCfg
    variable analysisParamValue
    variable analysisParamDefinition
    if {![info exists moduleCfg($moduleId,$configKey)]} { return }
    set defId [string trim $moduleCfg($moduleId,$configKey)]
    if {$defId eq "" || [analysisDefinitionField $defId descriptor ""] eq ""} { return }
    set owner "$moduleId,$configKey"
    set changed [expr {![info exists analysisParamDefinition($owner)] || $analysisParamDefinition($owner) ne $defId}]
    if {$reset || $changed} {
        # Definition selection changed: stale parameter IDs from the old
        # definition must not leak into the new runtime/manifest.
        foreach k [array names analysisParamValue "$moduleId,$configKey,*"] { unset analysisParamValue($k) }
        set analysisParamDefinition($owner) $defId
    }
    foreach pid [analysisDefinitionParameterIds $defId] {
        set k "$moduleId,$configKey,$pid"
        if {![info exists analysisParamValue($k)]} {
            set analysisParamValue($k) [analysisDefinitionParameterField $defId $pid default ""]
        }
    }
}

proc ::GX::analysisDefinitionSelectionChanged {moduleId configKey} {
    analysisParametersEnsure $moduleId $configKey 1
    catch {refreshManifestPreview}
}

proc ::GX::analysisParameterValidateOne {defId pid raw} {
    set typ [string tolower [string trim [analysisDefinitionParameterField $defId $pid type numeric]]]
    set required [expr {[analysisDefinitionParameterField $defId $pid required 0] ? 1 : 0}]
    set raw [string trim $raw]
    if {$raw eq ""} {
        if {$required} { error "Analysis parameter '$pid' is required." }
        return
    }
    switch -- $typ {
        numeric - number - double {
            if {![string is double -strict $raw]} { error "Analysis parameter '$pid' must be numeric." }
            set lo [string trim [analysisDefinitionParameterField $defId $pid min ""]]
            set hi [string trim [analysisDefinitionParameterField $defId $pid max ""]]
            if {$lo ne "" && [string is double -strict $lo] && $raw < $lo} { error "Analysis parameter '$pid' must be >= $lo." }
            if {$hi ne "" && [string is double -strict $hi] && $raw > $hi} { error "Analysis parameter '$pid' must be <= $hi." }
        }
        bool - boolean - logical {
            if {[string tolower $raw] ni {0 1 false true no yes off on}} { error "Analysis parameter '$pid' must be boolean." }
        }
        choice {
            set choices [splitList [analysisDefinitionParameterField $defId $pid choices ""]]
            if {![llength $choices]} { error "Analysis parameter '$pid' is type=choice but declares no choices." }
            if {[lsearch -exact $choices $raw] < 0} { error "Analysis parameter '$pid' must be one of: [join $choices {, }]." }
        }
        string - text { }
        default { error "Unsupported Analysis Definition parameter type '$typ' for '$pid'." }
    }
}

proc ::GX::analysisParametersValidate {moduleId configKey} {
    variable moduleCfg
    variable analysisParamValue
    analysisParametersEnsure $moduleId $configKey
    set defId [string trim $moduleCfg($moduleId,$configKey)]
    foreach pid [analysisDefinitionParameterIds $defId] {
        set k "$moduleId,$configKey,$pid"
        set raw [expr {[info exists analysisParamValue($k)] ? $analysisParamValue($k) : ""}]
        analysisParameterValidateOne $defId $pid $raw
    }
}

proc ::GX::analysisParametersResetDefaults {moduleId configKey} {
    analysisParametersEnsure $moduleId $configKey 1
    catch {analysisParameterDialogRender $moduleId $configKey}
    catch {refreshManifestPreview}
}

proc ::GX::analysisParameterDialogRender {moduleId configKey} {
    variable moduleCfg
    variable analysisParamValue
    set w .analysisParameters
    if {![winfo exists $w]} { return }
    set p $w.body.c.inner
    foreach child [winfo children $p] { destroy $child }
    analysisParametersEnsure $moduleId $configKey
    set defId [string trim $moduleCfg($moduleId,$configKey)]
    set ids [analysisDefinitionParameterIds $defId]
    if {![llength $ids]} {
        ttk::label $p.none -text "This Analysis Definition declares no configurable parameters."
        grid $p.none -row 0 -column 0 -columnspan 3 -sticky w -padx 6 -pady 8
    }
    set row 0
    foreach pid $ids {
        set typ [string tolower [string trim [analysisDefinitionParameterField $defId $pid type numeric]]]
        set label [analysisDefinitionParameterField $defId $pid label $pid]
        set unit [analysisDefinitionParameterField $defId $pid unit ""]
        ttk::label $p.l$row -text $label
        set var ::GX::analysisParamValue($moduleId,$configKey,$pid)
        switch -- $typ {
            bool - boolean - logical {
                ttk::checkbutton $p.w$row -variable $var
            }
            choice {
                ttk::combobox $p.w$row -textvariable $var -values [splitList [analysisDefinitionParameterField $defId $pid choices ""]] -state readonly -width 28
            }
            default {
                ttk::entry $p.w$row -textvariable $var -width 31
            }
        }
        set help "type=$typ"
        set lo [analysisDefinitionParameterField $defId $pid min ""]
        set hi [analysisDefinitionParameterField $defId $pid max ""]
        if {$lo ne "" || $hi ne ""} { append help "  range=$lo .. $hi" }
        if {$unit ne ""} { append help "  unit=$unit" }
        ttk::label $p.h$row -text $help -foreground #666666
        grid $p.l$row -row $row -column 0 -sticky e -padx 4 -pady 3
        grid $p.w$row -row $row -column 1 -sticky ew -padx 4 -pady 3
        grid $p.h$row -row $row -column 2 -sticky w -padx 4 -pady 3
        incr row
    }
    grid columnconfigure $p 1 -weight 1
    update idletasks
    set bb [$w.body.c bbox all]
    if {[llength $bb] == 4} { $w.body.c configure -scrollregion $bb }
}

proc ::GX::analysisParameterDialog {moduleId configKey} {
    variable moduleCfg
    if {![info exists moduleCfg($moduleId,$configKey)] || [string trim $moduleCfg($moduleId,$configKey)] eq ""} {
        tk_messageBox -icon info -type ok -message "Select an Analysis Definition first."
        return
    }
    analysisParametersEnsure $moduleId $configKey
    set w .analysisParameters
    catch {destroy $w}
    toplevel $w
    wm title $w "GX-TXT Analysis parameters — $moduleCfg($moduleId,$configKey)"
    wm geometry $w 820x520
    grid rowconfigure $w 1 -weight 1; grid columnconfigure $w 0 -weight 1
    ttk::label $w.note -text "Parameters are declared by the Scientific Analysis Definition and are persisted in Manifest Format 2. No module-specific GUI code is required." -wraplength 780 -justify left
    grid $w.note -row 0 -column 0 -sticky ew -padx 8 -pady 8
    ttk::frame $w.body; grid $w.body -row 1 -column 0 -sticky nsew -padx 8; grid rowconfigure $w.body 0 -weight 1; grid columnconfigure $w.body 0 -weight 1
    canvas $w.body.c -highlightthickness 0
    ttk::scrollbar $w.body.sy -orient vertical -command [list $w.body.c yview]
    $w.body.c configure -yscrollcommand [list $w.body.sy set]
    ttk::frame $w.body.c.inner
    $w.body.c create window 0 0 -anchor nw -window $w.body.c.inner
    bind $w.body.c.inner <Configure> [list apply [list {w} {set bb [$w.body.c bbox all]; if {[llength $bb] == 4} {$w.body.c configure -scrollregion $bb}}] $w]
    grid $w.body.c -row 0 -column 0 -sticky nsew; grid $w.body.sy -row 0 -column 1 -sticky ns
    ttk::frame $w.buttons
    ttk::button $w.buttons.defaults -text "Reset defaults" -command [list ::GX::analysisParametersResetDefaults $moduleId $configKey]
    ttk::button $w.buttons.preflight -text "Preflight..." -command [list ::GX::analysisPreflightDialog $moduleId $configKey]
    ttk::button $w.buttons.ok -text "Validate & close" -command [list ::GX::analysisParameterDialogClose $moduleId $configKey]
    pack $w.buttons.defaults $w.buttons.preflight $w.buttons.ok -side left -padx 4
    grid $w.buttons -row 2 -column 0 -sticky e -padx 8 -pady 8
    analysisParameterDialogRender $moduleId $configKey
}

proc ::GX::analysisParameterDialogClose {moduleId configKey} {
    if {[catch {analysisParametersValidate $moduleId $configKey} err]} { tk_messageBox -icon error -type ok -message $err; return }
    catch {refreshManifestPreview}
    destroy .analysisParameters
}

proc ::GX::analysisDefinitionPreflight_v084_before_analysis_sources {moduleId configKey} {
    variable moduleCfg
    variable currentSession
    set errors {}; set warnings {}; set lines {}
    if {![info exists moduleCfg($moduleId,$configKey)]} { return [dict create valid 0 errors [list selector_missing] warnings {} text "Configuration selector is missing."] }
    set defId [string trim $moduleCfg($moduleId,$configKey)]
    if {$defId eq "" || [analysisDefinitionField $defId descriptor ""] eq ""} { return [dict create valid 0 errors [list definition_missing] warnings {} text "No valid Analysis Definition is selected."] }
    set d [analysisDefinitionDict $defId]
    lappend lines "Definition: $defId" "Descriptor: [analysisDefinitionField $defId descriptor]" "Kind: [analysisDefinitionField $defId kind]" "Capabilities: [analysisDefinitionField $defId capabilities]" ""

    # Module selector compatibility is the same rule used by runtime writing.
    if {[lsearch -exact [analysisDefinitionIdsForConfig $moduleId $configKey] $defId] < 0} { lappend errors incompatible_definition }

    set modelId ""
    if {[info exists moduleCfg($moduleId,model_id)]} { set modelId [string trim $moduleCfg($moduleId,model_id)] }
    set req {}; set opt {}
    foreach vid [splitList [descriptorValue $d variables ids ""]] {
        set b [string trim [descriptorValue $d "variable.$vid" binding ""]]
        if {$b eq ""} continue
        set required [expr {[descriptorValue $d "variable.$vid" required 1] ? 1 : 0}]
        set resolved ""
        if {[lsearch -exact [moduleBindingRoles $moduleId] $b] >= 0} { catch {set resolved [resolveModuleBinding $moduleId $b $modelId]} }
        if {$required} { lappend req "$b -> $resolved" } else { lappend opt "$b -> $resolved" }
        if {$required && $resolved eq ""} { lappend errors "missing_binding:$b" }
        if {!$required && $resolved eq ""} { lappend warnings "optional_binding_unresolved:$b" }
    }
    lappend lines "Required bindings:"; if {[llength $req]} { foreach q $req { lappend lines "  $q" } } else { lappend lines "  (none)" }
    lappend lines "Optional bindings:"; if {[llength $opt]} { foreach q $opt { lappend lines "  $q" } } else { lappend lines "  (none)" }

    # Dataset contract preflight for descriptor-driven dataset selectors.
    foreach key [moduleConfigKeys $moduleId] {
        if {[string tolower [moduleConfigField $moduleId $key type string]] ne "dataset"} continue
        set ds [expr {[info exists moduleCfg($moduleId,$key)] ? [string trim $moduleCfg($moduleId,$key)] : ""}]
        set expected [string trim [moduleConfigField $moduleId $key contract ""]]
        set actual ""
        if {$currentSession ne "" && [file isdirectory $currentSession] && $ds ne ""} {
            catch {loadDatasetRegistry $currentSession}
            set actual [datasetField $ds kind ""]
        }
        lappend lines "Dataset $key: $ds  contract=$actual  expected=$expected"
        if {$actual ne "" && $expected ne "" && ![contractSatisfiesAny $actual $expected]} { lappend errors "dataset_contract_mismatch:$key:$actual" }
    }

    # Structural descriptor checks that do not require Octave/scientific data.
    set opIds [splitList [descriptorValue $d operations ids ""]]
    foreach op $opIds {
        set typ [string tolower [string trim [descriptorValue $d "operation.$op" type ""]]]
        if {$typ eq ""} { lappend errors "operation_type_missing:$op" }
        foreach dep [splitList [descriptorValue $d "operation.$op" depends ""]] {
            if {[lsearch -exact $opIds $dep] < 0} { lappend errors "unknown_dependency:$op:$dep" }
        }
    }
    if {[catch {analysisParametersValidate $moduleId $configKey} perr]} { lappend errors "parameter_validation:$perr" }
    lappend lines "" "Parameters:"; analysisParametersEnsure $moduleId $configKey
    variable analysisParamValue
    foreach pid [analysisDefinitionParameterIds $defId] {
        set k "$moduleId,$configKey,$pid"; set val [expr {[info exists analysisParamValue($k)] ? $analysisParamValue($k) : ""}]
        lappend lines "  $pid = $val"
    }
    set valid [expr {![llength $errors]}]
    lappend lines "" "Preflight: [expr {$valid ? {PASS} : {FAIL}}]"
    if {[llength $errors]} { lappend lines "Errors: [join $errors {, }]" }
    if {[llength $warnings]} { lappend lines "Warnings: [join $warnings {, }]" }
    lappend lines "" "Runtime note: gxtxt_analysis_validate_definition() repeats structural validation inside Octave before scientific execution."
    return [dict create valid $valid errors $errors warnings $warnings text [join $lines "\n"]]
}

proc ::GX::analysisPreflightDialog {moduleId configKey} {
    set rep [analysisDefinitionPreflight $moduleId $configKey]
    set w .analysisPreflight; catch {destroy $w}; toplevel $w; wm title $w "GX-TXT Analysis preflight"; wm geometry $w 900x600
    grid rowconfigure $w 0 -weight 1;grid columnconfigure $w 0 -weight 1
    text $w.t -wrap word -font TkFixedFont;ttk::scrollbar $w.sy -orient vertical -command [list $w.t yview];$w.t configure -yscrollcommand [list $w.sy set]
    grid $w.t -row 0 -column 0 -sticky nsew -padx {8 0} -pady 8;grid $w.sy -row 0 -column 1 -sticky ns -pady 8
    $w.t insert end [dict get $rep text];$w.t configure -state disabled
}

# Add Parameters/Preflight buttons beside every Analysis Definition selector.
proc ::GX::standardConfigWidget_v091_before_dataset_selection {parent id key row} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ne "analysis_definition"} { return [::GX::standardConfigWidget_v083_before_analysis_parameters $parent $id $key $row] }
    set label [moduleConfigField $id $key label $key]
    set vals [analysisDefinitionIdsForConfig $id $key]
    ttk::label $parent.l$row -text $label
    ttk::frame $parent.w$row
    ttk::combobox $parent.w$row.sel -textvariable ::GX::moduleCfg($id,$key) -values $vals -state readonly -width 36
    ttk::button $parent.w$row.params -text "Parameters..." -command [list ::GX::analysisParameterDialog $id $key]
    ttk::button $parent.w$row.preflight -text "Preflight..." -command [list ::GX::analysisPreflightDialog $id $key]
    bind $parent.w$row.sel <<ComboboxSelected>> [list ::GX::analysisDefinitionSelectionChanged $id $key]
    pack $parent.w$row.sel $parent.w$row.params $parent.w$row.preflight -side left -padx {0 4}
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
    analysisParametersEnsure $id $key
}

# Persist parameter values in Manifest Format 2 without changing the format
# version. Legacy manifests simply omit these additive sections.
proc ::GX::manifestStringV2_v084_before_analysis_sources {} {
    variable moduleOrder
    variable moduleCfg
    variable analysisParamValue
    set out [::GX::manifestStringV2_v083_before_analysis_parameters]
    foreach id $moduleOrder {
        foreach key [moduleConfigKeys $id] {
            if {[string tolower [moduleConfigField $id $key type string]] ne "analysis_definition"} continue
            if {![info exists moduleCfg($id,$key)] || [string trim $moduleCfg($id,$key)] eq ""} continue
            analysisParametersEnsure $id $key
            set defId [string trim $moduleCfg($id,$key)]
            append out "\n\[analysis_parameters.$id.$key\]\n"
            appendKV out definition_id $defId
            foreach pid [analysisDefinitionParameterIds $defId] {
                set k "$id,$key,$pid"
                appendKV out $pid [expr {[info exists analysisParamValue($k)] ? $analysisParamValue($k) : ""}]
            }
        }
    }
    return $out
}

proc ::GX::loadManifestV2_v084_before_analysis_sources {path} {
    variable moduleOrder
    variable moduleCfg
    variable analysisParamValue
    variable analysisParamDefinition
    ::GX::loadManifestV2_v083_before_analysis_parameters $path
    set d [parseIni $path]
    array unset analysisParamValue *
    array unset analysisParamDefinition *
    foreach id $moduleOrder {
        foreach key [moduleConfigKeys $id] {
            if {[string tolower [moduleConfigField $id $key type string]] ne "analysis_definition"} continue
            if {![info exists moduleCfg($id,$key)] || [string trim $moduleCfg($id,$key)] eq ""} continue
            set defId [string trim $moduleCfg($id,$key)]
            set analysisParamDefinition($id,$key) $defId
            foreach pid [analysisDefinitionParameterIds $defId] {
                set dk "analysis_parameters.$id.$key.$pid"
                if {[dict exists $d $dk]} { set analysisParamValue($id,$key,$pid) [dict get $d $dk] }
            }
            analysisParametersEnsure $id $key
        }
    }
}

# Runtime publishes the effective parameters in one standard section consumed by
# gxtxt_analysis_run(). Multiple selectors may share a parameter name only when
# their effective values are identical.
proc ::GX::writeStandardRuntimeConfig_v084_before_analysis_sources {id} {
    variable moduleCfg
    variable analysisParamValue
    set path [::GX::writeStandardRuntimeConfig_v083_before_analysis_parameters $id]
    set values [dict create]
    foreach key [moduleConfigKeys $id] {
        if {[string tolower [moduleConfigField $id $key type string]] ne "analysis_definition"} continue
        if {![info exists moduleCfg($id,$key)] || [string trim $moduleCfg($id,$key)] eq ""} continue
        analysisParametersEnsure $id $key
        analysisParametersValidate $id $key
        set defId [string trim $moduleCfg($id,$key)]
        foreach pid [analysisDefinitionParameterIds $defId] {
            set k "$id,$key,$pid"; set v [expr {[info exists analysisParamValue($k)] ? $analysisParamValue($k) : ""}]
            if {[dict exists $values $pid] && [dict get $values $pid] ne $v} { error "$id: Analysis Definition selectors provide conflicting values for parameter '$pid'." }
            dict set values $pid $v
        }
    }
    if {[dict size $values]} {
        set fd [open $path a];fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "\n\[analysis_parameters\]"
        foreach pid [lsort -dictionary [dict keys $values]] { putKV $fd $pid [dict get $values $pid] }
        close $fd
    }
    return $path
}

proc ::GX::defaults_v084_before_analysis_sources {} {
    variable analysisParamValue
    variable analysisParamDefinition
    ::GX::defaults_v083_before_analysis_parameters
    array unset analysisParamValue *
    array unset analysisParamDefinition *
}

# -----------------------------------------------------------------------------
# v0.8.5 - Standard Module API v1 multi-source dataset map (additive)
# -----------------------------------------------------------------------------
# Modules may opt in with:
#   [analysis_sources]
#   api_version=1
#   ids=primary
#   dynamic=1
# and optional per-source declarations:
#   [analysis_source.primary]
#   required=1
#   contracts=curve_family.table
#
# Runtime bindings are qualified as source.variable.  Legacy unqualified
# bindings remain valid and mean primary.variable.  No scientific alignment,
# join, interpolation or resampling is performed by this layer.
namespace eval ::GX {
    variable analysisSourceApiVersion 1
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
}

proc ::GX::moduleSupportsAnalysisSources {id} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return 0 }
    set d $moduleCatalog($id,dict)
    set enabled [string tolower [string trim [descriptorValue $d analysis_sources enabled ""]]]
    set ids [string trim [descriptorValue $d analysis_sources ids ""]]
    set api [string trim [descriptorValue $d analysis_sources api_version ""]]
    return [expr {$ids ne "" || $api ne "" || $enabled in {1 true yes on}}]
}

proc ::GX::moduleAnalysisSourceDeclaredIds {id} {
    variable moduleCatalog
    if {![moduleSupportsAnalysisSources $id]} { return {} }
    set d $moduleCatalog($id,dict)
    set ids [splitList [descriptorValue $d analysis_sources ids ""]]
    if {[llength $ids] == 0} { set ids {primary} }
    if {[lsearch -exact $ids primary] < 0} { set ids [linsert $ids 0 primary] }
    return $ids
}

proc ::GX::moduleAnalysisSourcesDynamic {id} {
    variable moduleCatalog
    if {![moduleSupportsAnalysisSources $id]} { return 0 }
    set d $moduleCatalog($id,dict)
    set v [string tolower [string trim [descriptorValue $d analysis_sources dynamic "1"]]]
    return [expr {$v in {1 true yes on}}]
}

proc ::GX::moduleAnalysisSourceField {id source field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($id,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($id,dict) "analysis_source.$source" $field $default]
}

proc ::GX::analysisSourceValidId {source} {
    return [regexp {^[A-Za-z][A-Za-z0-9_]*$} [string trim $source]]
}

proc ::GX::analysisSourcesResetModule {id} {
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
    foreach k [array names moduleAnalysisSource "$id,*,*"] { unset moduleAnalysisSource($k) }
    set moduleAnalysisSourceCount($id) 0
}

proc ::GX::analysisSourceAppendRow {id source datasetId} {
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
    if {![info exists moduleAnalysisSourceCount($id)]} { set moduleAnalysisSourceCount($id) 0 }
    incr moduleAnalysisSourceCount($id)
    set r $moduleAnalysisSourceCount($id)
    set moduleAnalysisSource($id,$r,id) $source
    set moduleAnalysisSource($id,$r,dataset_id) $datasetId
    return $r
}

proc ::GX::ensureModuleAnalysisSourceDefaults {{onlyId ""}} {
    variable moduleOrder
    variable moduleCfg
    variable moduleAnalysisSourceCount
    foreach id $moduleOrder {
        if {$onlyId ne "" && $id ne $onlyId} continue
        if {![moduleSupportsAnalysisSources $id]} continue
        if {[info exists moduleAnalysisSourceCount($id)] && $moduleAnalysisSourceCount($id) > 0} continue
        analysisSourcesResetModule $id
        foreach source [moduleAnalysisSourceDeclaredIds $id] {
            set ds [string trim [moduleAnalysisSourceField $id $source dataset_id ""]]
            if {$source eq "primary" && $ds eq "" && [info exists moduleCfg($id,dataset_id)]} {
                set ds [string trim $moduleCfg($id,dataset_id)]
            }
            analysisSourceAppendRow $id $source $ds
        }
    }
}

proc ::GX::analysisSourceRows {id} {
    variable moduleAnalysisSourceCount
    ensureModuleAnalysisSourceDefaults $id
    set n [expr {[info exists moduleAnalysisSourceCount($id)] ? $moduleAnalysisSourceCount($id) : 0}]
    set out {}; for {set r 1} {$r <= $n} {incr r} { lappend out $r }; return $out
}

proc ::GX::analysisSourceRowId {id row} {
    variable moduleAnalysisSource
    return [expr {[info exists moduleAnalysisSource($id,$row,id)] ? [string trim $moduleAnalysisSource($id,$row,id)] : ""}]
}

proc ::GX::analysisSourceRowDataset {id row} {
    variable moduleAnalysisSource
    return [expr {[info exists moduleAnalysisSource($id,$row,dataset_id)] ? [string trim $moduleAnalysisSource($id,$row,dataset_id)] : ""}]
}

proc ::GX::analysisSourceFindRow {id source} {
    foreach r [analysisSourceRows $id] { if {[analysisSourceRowId $id $r] eq $source} { return $r } }
    return 0
}

proc ::GX::analysisSourceDatasetFor {id source} {
    set r [analysisSourceFindRow $id $source]
    return [expr {$r ? [analysisSourceRowDataset $id $r] : ""}]
}

proc ::GX::analysisSourceIsDeclared {id source} {
    return [expr {[lsearch -exact [moduleAnalysisSourceDeclaredIds $id] $source] >= 0}]
}

proc ::GX::analysisSourceIsRequired {id source} {
    set fallback [expr {$source eq "primary" ? "1" : "0"}]
    set v [string tolower [string trim [moduleAnalysisSourceField $id $source required $fallback]]]
    return [expr {$v in {1 true yes on}}]
}

proc ::GX::datasetVariableNamesById {datasetId} {
    set raw [string trim [datasetField $datasetId variables ""]]
    if {$raw eq ""} { set raw [string trim [datasetField $datasetId columns ""]] }
    return [splitList $raw]
}

proc ::GX::analysisSourceExpectedContracts {id source} {
    set c [string trim [moduleAnalysisSourceField $id $source contracts ""]]
    if {$c eq "" && $source eq "primary"} { set c [string trim [moduleField $id inputs ""]] }
    return [splitList $c]
}

proc ::GX::analysisSourceDatasetChoices {id source} {
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} { catch {loadDatasetRegistry $currentSession} }
    set expected [analysisSourceExpectedContracts $id $source]
    set out {}
    foreach ds [datasetRegistryIds] {
        if {[llength $expected] && ![contractSatisfiesAny [datasetField $ds kind ""] $expected]} continue
        lappend out $ds
    }
    return $out
}

proc ::GX::analysisSourceValidateModule {id} {
    variable currentSession
    if {![moduleSupportsAnalysisSources $id]} { return }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "$id: open a valid session first." }
    loadDatasetRegistry $currentSession
    set seen {}
    set havePrimary 0
    foreach r [analysisSourceRows $id] {
        set source [analysisSourceRowId $id $r]
        set ds [analysisSourceRowDataset $id $r]
        if {$source eq ""} { error "$id: dataset source row $r has an empty Source ID." }
        if {![analysisSourceValidId $source]} { error "$id: invalid Source ID '$source'. Use letters, digits and underscore, starting with a letter." }
        if {[lsearch -exact $seen $source] >= 0} { error "$id: duplicate Source ID '$source'." }
        lappend seen $source
        if {$source eq "primary"} { set havePrimary 1 }
        if {$ds eq ""} {
            if {[analysisSourceIsRequired $id $source]} { error "$id: required dataset source '$source' has no Dataset ID." }
            continue
        }
        if {[datasetField $ds id ""] eq ""} { error "$id: dataset '$ds' for source '$source' is not registered in metadata/datasets.ini." }
        set expected [analysisSourceExpectedContracts $id $source]
        set actual [datasetField $ds kind ""]
        if {[llength $expected] && $actual ne "" && ![contractSatisfiesAny $actual $expected]} {
            error "$id: source '$source' dataset '$ds' has contract '$actual', expected '[join $expected ,]'."
        }
        set p [datasetResolvePath $currentSession $ds]
        if {![file isfile $p]} { error "$id: source '$source' canonical dataset file is missing: $p" }
    }
    if {!$havePrimary} { error "$id: multi-source modules require a 'primary' source for backward-compatible unqualified bindings." }
}

proc ::GX::analysisSourceQualifiedBindingChoices {id} {
    variable currentSession
    if {![moduleSupportsAnalysisSources $id]} { return [linsert [sourceVariableNames] 0 auto] }
    if {$currentSession ne "" && [file isdirectory $currentSession]} { catch {loadDatasetRegistry $currentSession} }
    set vals {auto}
    foreach r [analysisSourceRows $id] {
        set source [analysisSourceRowId $id $r]
        set ds [analysisSourceRowDataset $id $r]
        if {$source eq "" || $ds eq "" || ![analysisSourceValidId $source]} continue
        foreach col [datasetVariableNamesById $ds] { lappend vals "$source.$col" }
    }
    return $vals
}

proc ::GX::analysisSourceNormalizeBinding {id value} {
    set value [string trim $value]
    if {$value eq "" || $value eq "auto" || ![moduleSupportsAnalysisSources $id]} { return $value }
    set dot [string first "." $value]
    if {$dot > 0} {
        set candidate [string range $value 0 [expr {$dot-1}]]
        if {[analysisSourceFindRow $id $candidate]} { return $value }
    }
    return "primary.$value"
}

# Multi-source modules resolve explicit legacy bindings to primary.variable and
# expose model/semantic automatic bindings in the same namespace.  Legacy
# single-source modules retain the exact historical resolver.
proc ::GX::resolveModuleBinding_before_variable_ids {id role {modelId ""}} {
    if {![moduleSupportsAnalysisSources $id]} { return [::GX::resolveModuleBinding_v084_single_source $id $role $modelId] }
    variable moduleBinding
    set explicit [expr {[info exists moduleBinding($id,$role)] ? [string trim $moduleBinding($id,$role)] : "auto"}]
    if {$explicit ne "" && $explicit ne "auto"} { return [analysisSourceNormalizeBinding $id $explicit] }

    # Model preferred names are primary-scoped unless the user explicitly
    # qualifies another source.
    set pref ""
    set mf [moduleBindingField $id $role preferred_model_field ""]
    if {$modelId ne "" && $mf ne ""} { set pref [string trim [modelField $modelId $mf ""]] }
    set pds [analysisSourceDatasetFor $id primary]
    if {$pref ne "" && $pds ne "" && [lsearch -exact [datasetVariableNamesById $pds] $pref] >= 0} { return "primary.$pref" }

    # Preserve the established semantic resolver as a primary-source fallback.
    set old [::GX::resolveModuleBinding_v084_single_source $id $role $modelId]
    if {$old ne "" && $old ne "auto"} { return [analysisSourceNormalizeBinding $id $old] }
    return ""
}

# Keep the current resolver available while later CORE files are sourced.
proc ::GX::resolveModuleBinding {id role {modelId ""}} {
    return [resolveModuleBinding_before_variable_ids $id $role $modelId]
}

proc ::GX::analysisSourceAddGuiRow {id} {
    if {![moduleAnalysisSourcesDynamic $id]} { return }
    set used {}; foreach r [analysisSourceRows $id] { lappend used [analysisSourceRowId $id $r] }
    set n 2; set source "source$n"; while {[lsearch -exact $used $source] >= 0} { incr n; set source "source$n" }
    analysisSourceAppendRow $id $source ""
    analysisSourcesRenderForModule $id
    refreshModuleBindingChoices $id
    refreshManifestPreview
}

proc ::GX::analysisSourceRemoveGuiRow {id row} {
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
    set source [analysisSourceRowId $id $row]
    if {[analysisSourceIsRequired $id $source] ||
        (![moduleAnalysisSourcesDynamic $id] && [analysisSourceIsDeclared $id $source])} { return }
    set n $moduleAnalysisSourceCount($id)
    for {set r $row} {$r < $n} {incr r} {
        foreach f {id dataset_id} { set moduleAnalysisSource($id,$r,$f) $moduleAnalysisSource($id,[expr {$r+1}],$f) }
    }
    foreach f {id dataset_id} { catch {unset moduleAnalysisSource($id,$n,$f)} }
    incr moduleAnalysisSourceCount($id) -1
    analysisSourcesRenderForModule $id
    refreshModuleBindingChoices $id
    refreshManifestPreview
}

proc ::GX::analysisSourceGuiChanged {id} {
    after idle [list ::GX::refreshModuleBindingChoices $id]
    after idle ::GX::refreshManifestPreview
}

proc ::GX::renderModuleAnalysisSources {parent id} {
    variable moduleAnalysisSource
    destroyChildren $parent
    grid columnconfigure $parent 1 -weight 1
    ttk::frame $parent.bar
    if {[moduleAnalysisSourcesDynamic $id]} { ttk::button $parent.bar.add -text "+ Add source" -command [list ::GX::analysisSourceAddGuiRow $id]; pack $parent.bar.add -side left -padx {0 6} }
    ttk::label $parent.bar.note -text "Bindings use source.variable. Legacy unqualified bindings mean primary.variable. Dataset alignment remains an explicit Scientific Analysis operation." -wraplength 900 -justify left
    pack $parent.bar.note -side left
    grid $parent.bar -row 0 -column 0 -columnspan 3 -sticky ew -padx 4 -pady {2 5}
    foreach {c text} {0 {Source ID} 1 {Dataset ID} 2 {}} { ttk::label $parent.h$c -text $text; grid $parent.h$c -row 1 -column $c -sticky w -padx 4 }
    set rr 2
    foreach r [analysisSourceRows $id] {
        set source [analysisSourceRowId $id $r]
        ttk::entry $parent.s$r -textvariable ::GX::moduleAnalysisSource($id,$r,id) -width 22
        if {[analysisSourceIsDeclared $id $source]} { $parent.s$r state readonly } else { bind $parent.s$r <FocusOut> [list ::GX::analysisSourceGuiChanged $id] }
        set vals [analysisSourceDatasetChoices $id $source]
        ttk::combobox $parent.d$r -textvariable ::GX::moduleAnalysisSource($id,$r,dataset_id) -values $vals -state readonly -width 44
        datasetSelectorAttach $parent.d$r [list ::GX::analysisSourceDatasetChoices $id $source]
        bind $parent.d$r <<ComboboxSelected>> [list ::GX::analysisSourceGuiChanged $id]
        ttk::button $parent.rm$r -text "Remove" -command [list ::GX::analysisSourceRemoveGuiRow $id $r]
        if {[analysisSourceIsRequired $id $source] ||
            (![moduleAnalysisSourcesDynamic $id] && [analysisSourceIsDeclared $id $source])} {
            $parent.rm$r state disabled
        }
        grid $parent.s$r -row $rr -column 0 -sticky ew -padx 4 -pady 2
        grid $parent.d$r -row $rr -column 1 -sticky ew -padx 4 -pady 2
        grid $parent.rm$r -row $rr -column 2 -sticky w -padx 4 -pady 2
        incr rr
    }
}

proc ::GX::analysisSourcesRenderForModule {id} {
    variable ui
    if {![info exists ui(analysisModuleFrame,$id)]} { return }
    set base $ui(analysisModuleFrame,$id)
    if {[winfo exists $base.sources]} { renderModuleAnalysisSources $base.sources $id }
}

proc ::GX::refreshModuleBindingChoices {id} {
    variable ui
    if {![info exists ui(analysisModuleFrame,$id)]} { return }
    set base $ui(analysisModuleFrame,$id)
    if {![winfo exists $base.bind]} { return }
    set vals [analysisSourceQualifiedBindingChoices $id]
    set rr 0
    foreach role [moduleBindingRoles $id] {
        if {[winfo exists $base.bind.w$rr]} { $base.bind.w$rr configure -values $vals }
        incr rr
    }
}

# Final v0.8.5 Analysis builder: the source-map table is framework-owned and is
# shown only for modules that opt in through [analysis_sources].
proc ::GX::rebuildNativeAnalysisGui_before_core_script_surface {} {
    variable moduleOrder
    variable moduleRun
    variable moduleBinding
    variable ui

    set host [analysisScrollableHost]
    if {$host eq ""} { return }
    foreach k [array names ui "analysisModuleFrame,*"] { unset ui($k) }
    grid columnconfigure $host 0 -weight 1

    set row 0
    foreach id $moduleOrder {
        if {[moduleField $id kind ""] ne "analysis"} continue
        if {![moduleIsEnabled $id]} continue
        ensureModuleAnalysisSourceDefaults $id

        set base $host.m$row
        set ui(analysisModuleFrame,$id) $base
        ttk::labelframe $base -text "[moduleField $id name $id]  ($id)"
        grid $base -row $row -column 0 -sticky new -padx 6 -pady 6
        grid columnconfigure $base 0 -weight 1
        grid columnconfigure $base 1 -weight 1

        ttk::checkbutton $base.run -text "Run / recalculate now" -variable ::GX::moduleRun($id) -command ::GX::refreshManifestPreview
        grid $base.run -row 0 -column 0 -columnspan 2 -sticky w -padx 4 -pady 3

        set br 1
        if {[llength [moduleGraphIds $id]]} {
            ttk::labelframe $base.plots -text "Graphs offered by module (Graph Provider API v1)"
            grid $base.plots -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $base.plots 0 -weight 1
            buildModulePlotConfigFrame $base.plots $id
            incr br
        }

        ttk::labelframe $base.cfg -text "Calculation configuration"
        grid $base.cfg -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
        buildStandardConfigFrame $base.cfg $id
        incr br

        if {[moduleSupportsAnalysisSources $id]} {
            ttk::labelframe $base.sources -text "Dataset sources (Analysis Source Map API v1)"
            grid $base.sources -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $base.sources 1 -weight 1
            renderModuleAnalysisSources $base.sources $id
            incr br
        }

        set roles [moduleBindingRoles $id]
        if {[llength $roles]} {
            ttk::labelframe $base.bind -text "Input variable bindings"
            grid $base.bind -row $br -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
            grid columnconfigure $base.bind 1 -weight 1
            set vals [analysisSourceQualifiedBindingChoices $id]
            set rr 0
            foreach role $roles {
                ttk::label $base.bind.l$rr -text [moduleBindingField $id $role label $role]
                ttk::combobox $base.bind.w$rr -textvariable ::GX::moduleBinding($id,$role) -values $vals -state readonly -width 42
                bind $base.bind.w$rr <<ComboboxSelected>> [list ::GX::moduleBindingGuiSelected $id $role]
                grid $base.bind.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2
                grid $base.bind.w$rr -row $rr -column 1 -sticky ew -padx 4 -pady 2
                incr rr
            }
        }
        incr row
    }

    if {$row == 0} {
        ttk::frame $host.empty
        ttk::label $host.empty.title -text "No analysis modules are active in this experiment." -font TkHeadingFont
        ttk::label $host.empty.help -text "Open the Modules tab and activate the analysis modules you want to use. Only active modules are shown here." -wraplength 800 -justify left
        grid $host.empty.title -row 0 -column 0 -sticky w -pady {0 5}
        grid $host.empty.help -row 1 -column 0 -sticky w
        grid $host.empty -row 0 -column 0 -sticky nw -padx 12 -pady 12
    }

    refreshNativeAnalysisState
    update idletasks
    analysisScrollRefresh
    if {[info exists ui(analysisCanvas)] && [winfo exists $ui(analysisCanvas)]} { $ui(analysisCanvas) yview moveto 0 }
}

# Keep the current Analysis builder callable while later GUI extensions source.
# The Script Workspace file replaces this entry with its fixed decorator.
proc ::GX::rebuildNativeAnalysisGui {} {
    ::GX::rebuildNativeAnalysisGui_before_core_script_surface
}

proc ::GX::refreshNativeAnalysisState {} {
    variable moduleOrder
    variable ui
    ::GX::refreshNativeAnalysisState_v084_sources_base
    foreach id $moduleOrder {
        if {![info exists ui(analysisModuleFrame,$id)]} continue
        set base $ui(analysisModuleFrame,$id)
        if {[winfo exists $base.sources]} {
            setWidgetTreeState $base.sources 1
            foreach row [analysisSourceRows $id] {
                set source [analysisSourceRowId $id $row]
                if {[analysisSourceIsRequired $id $source] ||
                    (![moduleAnalysisSourcesDynamic $id] && [analysisSourceIsDeclared $id $source])} {
                    if {[winfo exists $base.sources.rm$row]} { $base.sources.rm$row state disabled }
                }
            }
        }
    }
}

# Additive Manifest Format 2 persistence.  Old manifests have no source-map
# sections and therefore fall back to descriptor defaults / legacy dataset_id.
proc ::GX::manifestStringV2_v085_before_dataset_inspection {} {
    variable moduleOrder
    variable moduleAnalysisSource
    set out [::GX::manifestStringV2_v084_before_analysis_sources]
    append out "\n\[analysis_source_map_api\]\n"; appendKV out version $::GX::analysisSourceApiVersion
    foreach id $moduleOrder {
        if {![moduleSupportsAnalysisSources $id]} continue
        ensureModuleAnalysisSourceDefaults $id
        set ids {}
        foreach r [analysisSourceRows $id] { set s [analysisSourceRowId $id $r]; if {$s ne ""} { lappend ids $s } }
        append out "\n\[module_analysis_sources.$id\]\n"; appendKV out ids [join $ids {;}]
        foreach r [analysisSourceRows $id] {
            set s [analysisSourceRowId $id $r]; if {$s eq ""} continue
            append out "\n\[module_analysis_source.$id.$s\]\n"
            appendKV out dataset_id [analysisSourceRowDataset $id $r]
        }
    }
    return $out
}

proc ::GX::loadManifestV2_v085_before_dataset_inspection {path} {
    variable moduleOrder
    variable moduleCfg
    ::GX::loadManifestV2_v084_before_analysis_sources $path
    set d [parseIni $path]
    foreach id $moduleOrder {
        if {![moduleSupportsAnalysisSources $id]} continue
        analysisSourcesResetModule $id
        set key "module_analysis_sources.$id.ids"
        set ids [expr {[dict exists $d $key] ? [splitList [dict get $d $key]] : {}}]
        if {[llength $ids]} {
            foreach s $ids {
                set dk "module_analysis_source.$id.$s.dataset_id"
                set ds [expr {[dict exists $d $dk] ? [dict get $d $dk] : ""}]
                analysisSourceAppendRow $id $s $ds
            }
        } else {
            ensureModuleAnalysisSourceDefaults $id
            # A module may remove its old config.dataset_id field when it
            # adopts Analysis Source Map. The saved Manifest still owns that
            # legacy value, even though descriptor config loading no longer
            # creates moduleCfg(id,dataset_id). Resolve it here in CORE.
            set legacyId [expr {[info exists moduleCfg($id,dataset_id)] ? [string trim $moduleCfg($id,dataset_id)] : ""}]
            set legacyKey "module_config.$id.dataset_id"
            if {$legacyId eq "" && [dict exists $d $legacyKey]} { set legacyId [string trim [dict get $d $legacyKey]] }
            if {$legacyId ne ""} {
                set r [analysisSourceFindRow $id primary]
                if {$r} { set ::GX::moduleAnalysisSource($id,$r,dataset_id) $legacyId }
            }
        }
    }
    catch {rebuildNativeAnalysisGui}
}

# Runtime keeps [dataset] as a primary-source compatibility alias and adds the
# complete source map with resolved paths/contracts/columns.  Existing modules
# therefore remain byte-compatible with the old runtime contract.
proc ::GX::writeStandardRuntimeConfig_v09797_public_api_runtime_base {id} {
    variable moduleCfg
    variable currentSession
    if {![moduleSupportsAnalysisSources $id]} { return [::GX::writeStandardRuntimeConfig_v084_before_analysis_sources $id] }
    analysisSourceValidateModule $id
    set primary [analysisSourceDatasetFor $id primary]
    set had [info exists moduleCfg($id,dataset_id)]
    if {$had} { set old $moduleCfg($id,dataset_id) }
    set moduleCfg($id,dataset_id) $primary
    try {
        set path [::GX::writeStandardRuntimeConfig_v084_before_analysis_sources $id]
    } finally {
        if {$had} { set moduleCfg($id,dataset_id) $old } else { catch {unset moduleCfg($id,dataset_id)} }
    }
    loadDatasetRegistry $currentSession
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    set ids {}; foreach r [analysisSourceRows $id] { set s [analysisSourceRowId $id $r]; if {$s ne ""} { lappend ids $s } }
    puts $fd "\n\[analysis_sources\]"; putKV $fd api_version 1; putKV $fd ids [join $ids {;}]
    foreach r [analysisSourceRows $id] {
        set s [analysisSourceRowId $id $r]; if {$s eq ""} continue
        set ds [analysisSourceRowDataset $id $r]
        puts $fd "\n\[analysis_source.$s\]"
        putKV $fd dataset_id $ds
        if {$ds ne ""} {
            putKV $fd path [datasetResolvePath $currentSession $ds]
            putKV $fd kind [datasetField $ds kind ""]
            putKV $fd columns [datasetField $ds columns ""]
        } else {
            putKV $fd path ""; putKV $fd kind ""; putKV $fd columns ""
        }
    }
    close $fd
    return $path
}

# Preflight now reports source-map configuration in addition to the existing
# Analysis Definition/parameter checks.
proc ::GX::analysisDefinitionPreflight {moduleId configKey} {
    set rep [::GX::analysisDefinitionPreflight_v084_before_analysis_sources $moduleId $configKey]
    if {![moduleSupportsAnalysisSources $moduleId]} { return $rep }
    set errors [dict get $rep errors]; set warnings [dict get $rep warnings]; set text [dict get $rep text]
    append text "\n\nDataset sources:\n"
    if {[catch {analysisSourceValidateModule $moduleId} e]} { lappend errors "analysis_sources:$e" }
    foreach r [analysisSourceRows $moduleId] {
        set s [analysisSourceRowId $moduleId $r]; set ds [analysisSourceRowDataset $moduleId $r]
        append text "  $s -> $ds"
        if {$ds ne ""} { append text "  ([datasetField $ds kind ""])" }
        append text "\n"
    }
    set valid [expr {![llength $errors]}]
    append text "Source-map preflight: [expr {$valid ? {PASS} : {FAIL}}]\n"
    return [dict create valid $valid errors $errors warnings $warnings text $text]
}

# Initialize/refresh source-map state without changing legacy module state.
proc ::GX::loadModuleCatalog_v088_before_acquisition_handler_api {} {
    ::GX::loadModuleCatalog_v084_before_analysis_sources
    ensureModuleAnalysisSourceDefaults
}

proc ::GX::defaults_v085_before_dataset_inspection {} {
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
    ::GX::defaults_v084_before_analysis_sources
    array unset moduleAnalysisSource *
    array unset moduleAnalysisSourceCount *
}

# v0.8.5 module help: surface source-map requirements without source inspection.
proc ::GX::moduleHelpText_before_plugin_install_v1 {id} {
    set out [::GX::moduleHelpText_v084_before_analysis_sources $id]
    if {![moduleSupportsAnalysisSources $id]} { return $out }
    append out "\n\nDATASET SOURCES (Analysis Source Map API v1)\n"
    append out "Dynamic sources: [expr {[moduleAnalysisSourcesDynamic $id] ? {yes} : {no}}]\n"
    foreach s [moduleAnalysisSourceDeclaredIds $id] {
        set req [expr {[analysisSourceIsRequired $id $s] ? {required} : {optional}}]
        set contracts [analysisSourceExpectedContracts $id $s]
        append out "- $s: $req"
        if {[llength $contracts]} { append out "; contracts=[join $contracts {, }]" }
        append out "\n"
    }
    append out "Bindings use source.variable; unqualified legacy bindings mean primary.variable.\n"
    append out "Dataset selection never performs implicit join/interpolation/resampling.\n"
    return $out
}

# Keep module details available until Plugin Install adds its package state.
proc ::GX::moduleHelpText {id} {
    return [::GX::moduleHelpText_before_plugin_install_v1 $id]
}

# OCR and table extraction are CORE services, available before GUI/module selection.
source [file join $::GX::scriptDir core tcl ocr_layout_api_v1.tcl]
source [file join $::GX::scriptDir core tcl table_extractor_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_spectrum_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_reference_library_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_library_manager_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_spectrum_import_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_spectrum_session_api_v1.tcl]
source [file join $::GX::scriptDir core tcl spectral_family_api_v1.tcl]

# v0.9.7.97: expose declared dependency public APIs to standard_octave
# consumers through runtime.ini. Consumers discover API contracts/capabilities
# from runtime metadata instead of reconstructing dependency filesystem paths.
proc ::GX::appendStandardRuntimePublicApis {moduleId runtimePath} {
    set seen [dict create]
    set fd [open $runtimePath a]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        foreach dep [splitList [moduleField $moduleId depends ""]] {
            set descriptor [moduleField $dep descriptor ""]
            if {$descriptor eq "" || ![file isfile $descriptor]} {
                error "$moduleId: dependency '$dep' has no discoverable module descriptor."
            }
            set descriptor [file normalize $descriptor]
            set moduleRoot [file dirname $descriptor]
            set d [parseIni $descriptor]
            foreach apiId [splitList [descriptorValue $d public_apis ids ""]] {
                if {[dict exists $seen $apiId]} {
                    error "$moduleId: public API '$apiId' is advertised by both '[dict get $seen $apiId]' and '$dep'."
                }
                dict set seen $apiId $dep
                set sec "public_api.$apiId"
                puts $fd "\n\[$sec\]"
                putKV $fd module_id $dep
                putKV $fd module_version [descriptorValue $d meta version ""]
                putKV $fd api_version [descriptorValue $d $sec api_version ""]
                putKV $fd capabilities [descriptorValue $d $sec capabilities ""]
                putKV $fd namespace [descriptorValue $d $sec namespace ""]
                putKV $fd octave_function [descriptorValue $d $sec octave_function ""]
                foreach {srcKey dstKey} {entrypoint tcl_entrypoint octave_entrypoint octave_entrypoint documentation documentation} {
                    set rel [string trim [descriptorValue $d $sec $srcKey ""]]
                    if {$rel eq ""} { putKV $fd $dstKey ""; continue }
                    set absolute [file normalize [file join $moduleRoot $rel]]
                    if {[string first "$moduleRoot/" "$absolute/"] != 0 || ![file isfile $absolute]} {
                        error "$moduleId: advertised $apiId $srcKey is outside dependency '$dep' or missing."
                    }
                    putKV $fd $dstKey $absolute
                }
            }
        }
    } finally {
        close $fd
    }
    return $runtimePath
}

proc ::GX::writeStandardRuntimeConfig_v087_before_dataset_publication {id} {
    set path [::GX::writeStandardRuntimeConfig_v09797_public_api_runtime_base $id]
    return [appendStandardRuntimePublicApis $id $path]
}
