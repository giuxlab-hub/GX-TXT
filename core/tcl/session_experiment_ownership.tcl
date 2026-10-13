# SPDX-License-Identifier: GPL-3.0-or-later
# Private duplicate-worker policy. Registry identity, not a file suffix, owns
# persisted preparation. Preserve document generations so managed receipts keep
# their exact provenance in the new Session's independent lifetime.
proc ::GX::ExperimentClone::clarify {doc dependency} {
    error "Unsafe optional state: [dict get $doc id] ([dict get $doc module_id]/[dict get $doc provider_id], [dict get $doc format]): $dependency"
}
proc ::GX::ExperimentClone::dependencies {value doc depth} {
    variable removedDocuments;variable documents;variable ids;variable paths;variable source
    if {$depth>64} {clarify $doc {a dependency beyond the supported inspection depth}}
    if {![catch {dict get $value api_id} api] && $api eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        set owner [dict get $value document_id]
        if {$owner in $removedDocuments} {clarify $doc "excluded document/resource owner $owner"}
        if {![dict exists $documents $owner]} {clarify $doc "a retired or missing resource owner $owner whose preparation ownership cannot be established"}
        set resourcePath [file join $source metadata interactive_document_resources $owner "[dict get $value sha256].blob"]
        if {$resourcePath in $paths} {clarify $doc {resource is registered scientific payload}}
        ::GX::interactiveDocumentResourceInfo $value
        dict lappend ::GX::ExperimentClone::resources [dict get $doc id] $value
        dependencies [dict get $value metadata] $doc [expr {$depth+1}]
        return
    }
    if {![catch {dict get $value source_mode} mode] && $mode eq "dataset"} {clarify $doc {Dataset source mode}}
    if {$value in $ids} {clarify $doc "excluded Dataset $value"}
    if {$value in $removedDocuments} {clarify $doc "excluded Workspace/graph document $value"}
    if {![catch {dict size $value}]} {
        dict for {key field} $value {
            if {$key in {dataset_id source_dataset_id source_dataset_ids dataset_ids workspace_id source_workspace_id graph_id source_graph_id variant_id} && $field ne {}} {clarify $doc "excluded scientific binding $key=$field"}
        }
    }
    if {[regexp {^(analysis|datasets|raw|channels|cache|logs|report|metadata/(graphs|plot.dataset|datasets))(/|$)} $value]} {clarify $doc {CORE scientific/output authority}}
    if {[file pathtype $value] eq "relative" && [string first / $value]>=0 && [file normalize [file join $source $value]] in $paths} {clarify $doc "excluded relative scientific path $value"}
    foreach p $paths {if {$value eq $p || [string first "$p/" "$value/"]==0} {clarify $doc "excluded scientific path $p"}}
    # An absolute reference into the old Session would couple two experiments.
    # Do not rewrite an opaque provider payload or invalidate its checksum.
    if {$value eq $source || [string first "$source/" $value]>=0} {clarify $doc {an absolute source-Session path requiring provider-specific rebinding}}
    if {[catch {llength $value}]} return
    foreach item $value {if {$item ne $value} {dependencies $item $doc [expr {$depth+1}]}}
}
proc ::GX::ExperimentClone::report {action module provider object reason} {
    variable diagnostics
    lappend diagnostics [dict create action $action module_id $module provider_id $provider object $object reason $reason]
}
proc ::GX::ExperimentClone::excludeDocument {id item reason} {
    variable removedDocuments;variable documents
    lappend removedDocuments $id;dict unset documents $id
    # A corrupt excluded payload is an integrity error, not permission to copy
    # it. Ownership paths are read only from validated registry payload bytes.
    ownedDocumentPaths [dict get [::GX::interactiveDocumentRead $id] payload] 0
    report excluded [dict get $item module_id] [dict get $item provider_id] $id $reason
}
proc ::GX::ExperimentClone::documentsPlan {} {
    variable source;variable documents;variable removedDocuments;variable registry
    set ::GX::currentSession $source
    set registry [::GX::_interactiveDocumentRegistryRead $source]
    set documents $registry;set removedDocuments {}
    dict for {id item} $registry {
        set policy [::GX::_experimentDuplicationDocumentPolicy $item]
        if {[dict get $policy action] ne "COPY_PREPARATION"} {excludeDocument $id $item [dict get $policy origin]}
    }
}
proc ::GX::ExperimentClone::documentPayloadValidate {payload doc policy} {
    if {[dict get $policy payload_kind] eq "author_code" && [dict get $policy origin] ne "native_author_code"} {
        # An inert code envelope separates author text from owned dependencies.
        if {[catch {dict size $payload}] || [lsort [dict keys $payload]] ne {code metadata} || [catch {dict size [dict get $payload metadata]}]} {clarify $doc {author code requires code/metadata envelope}}
        dependencies [dict get $payload metadata] $doc 0
    } elseif {[dict get $policy payload_kind] ne "author_code"} {
        if {[catch {dict size $payload}]} {clarify $doc {opaque payload lacks structured dependency authority}}
        dependencies $payload $doc 0
    }
}
proc ::GX::ExperimentClone::documentsValidate {} {
    variable documents;variable source;variable resources
    # Omission can invalidate cross-document references. Iterate to a fixed
    # point so a retained object never references an omitted owner's resources.
    while 1 {
        set changed 0;set resources {}
        dict for {id item} $documents {
            set doc [::GX::interactiveDocumentRead $id]
            set policy [::GX::_experimentDuplicationDocumentPolicy $item]
            if {[catch {
                documentPayloadValidate [dict get $doc payload] $doc $policy
                if {[file isfile [file join $source metadata workbench_recovery "$id.gxr"]]} {
                    set state [::GX::_workbenchRecoveryRead $id]
                    foreach which {saved latest} {documentPayloadValidate [dict get $state $which payload] $doc $policy}
                }
            } reason]} {excludeDocument $id $item $reason;set changed 1}
        }
        if {!$changed} break
    }
    dict for {id item} $documents {report copied [dict get $item module_id] [dict get $item provider_id] $id {validated independent preparation and referenced resources}}
}
proc ::GX::ExperimentClone::filesPlan {} {
    variable allowedFiles;variable source;variable paths
    foreach module $::GX::moduleOrder {
        set policy [::GX::experimentDuplicationPolicyModule $module]
        if {![dict get $policy valid]} continue
        foreach relative [dict get $policy files] {
            set path [file normalize [file join $source $relative]]
            if {![::GX::_datasetDeletePathWithin $path $source] || $path in $paths || ![file isfile $path] || [file type $path] ne "file"} {
                report skipped $module descriptor $relative {missing, scientific, or unsafe preparation file}
            } else {lappend allowedFiles $path;report copied $module descriptor $relative {declared independent preparation owner}}
        }
    }
}
proc ::GX::ExperimentClone::ownedDocumentPaths {payload depth} {
    variable source;variable paths
    if {$depth>64} return
    if {![catch {dict size $payload}]} {
        dict for {key value} $payload {
            if {$key in {resource_path relative_path source_resource source_path path geometry_path}} {
                set path [expr {[file pathtype $value] eq "absolute" ? $value : [file join $source $value]}]
                if {$value ne {} && [::GX::_datasetDeletePathWithin $path $source] && [file isfile $path]} {lappend paths [file normalize $path]}
            }
        }
    }
    if {[catch {llength $payload}]} return
    foreach value $payload {if {$value ne $payload} {ownedDocumentPaths $value [expr {$depth+1}]}}
}
proc ::GX::ExperimentClone::documentsCopy {stage} {
    variable source;variable documents
    dict for {id item} $documents {
        set original [::GX::_interactiveDocumentPayloadPath $source $item]
        set destination [file join $stage metadata interactive_documents [dict get $item storage_name]]
        file mkdir [file dirname $destination];file copy -- $original $destination
        # Copy only live validated references, never an entire resource root
        # containing orphan blobs or unfinished/retired scientific resources.
        if {[dict exists $::GX::ExperimentClone::resources $id]} {
            foreach receipt [dict get $::GX::ExperimentClone::resources $id] {
                set owner [dict get $receipt document_id];set blob "[dict get $receipt sha256].blob"
                set destinationRoot [file join $stage metadata interactive_document_resources $owner]
                file mkdir $destinationRoot
                file copy -force -- [file join $source metadata interactive_document_resources $owner $blob] [file join $destinationRoot $blob]
            }
        }
        set checkpoint [file join $source metadata workbench_recovery "$id.gxr"]
        if {[file isfile $checkpoint]} {file mkdir [file join $stage metadata workbench_recovery];file copy -- $checkpoint [file join $stage metadata workbench_recovery "$id.gxr"]}
    }
    set registryPath [file join $source metadata interactive_documents.ini]
    set prior [expr {[file isfile $registryPath] ? [::GX::parseIni $registryPath] : {}}]
    if {[dict size $documents] || $prior ne {}} {
        set counter [::GX::datasetPublicationV2DictDefault $prior interactive_documents.high_water_id 0]
        iniWrite [file join $stage metadata interactive_documents.ini] [dict create interactive_documents.api_version 1 interactive_documents.count 0 interactive_documents.high_water_id $counter]
        ::GX::_interactiveDocumentRegistryWrite $stage $documents
    }
}
proc ::GX::ExperimentClone::graphKey {key} {
    return [regexp {^(module_plot\.|module_plot_region\.|plot\.|plot_variant\.|plot_variant_counter\.|plot_variant_region\.|plot_annotation\.|graph_series\.|graph_use\.|graph_notes\.|graph_metadata\.|level_scale\.)} $key]
}
proc ::GX::ExperimentClone::graphsReset {manifest} {
    dict for {key value} $manifest {
        if {[graphKey $key]} {dict unset manifest $key}
        if {[regexp {^module_graphs\..+\.enabled$} $key]} {dict set manifest $key {}}
    }
    # Offerings remain module descriptors, not cloned graphs. All start disabled.
    foreach module $::GX::moduleOrder {
        if {[llength [::GX::moduleGraphIds $module]]} {dict set manifest module_graphs.$module.enabled {}}
    }
    foreach key {graph_series_api.count graph_use.count graph_notes.count graph_metadata.count plot_annotations.count} {dict set manifest $key 0}
    return $manifest
}
proc ::GX::ExperimentClone::ownedOutputs {manifest} {
    variable paths;variable source
    # These hidden TSVs are CORE transport authorities for graph overrides,
    # not ordinary user preparation. Their old labels/styles must not survive.
    foreach name {.plot_axis_overrides.tsv .plot_legend_overrides.tsv .plot_graph_map.tsv} {lappend paths [file join $source analysis $name]}
    foreach module $::GX::moduleOrder {
        foreach name [::GX::splitList [::GX::moduleField $module outputs {}]] {lappend paths [file normalize [file join $source analysis $module $name]]}
        foreach graph [::GX::moduleGraphIds $module] {
            set name [::GX::moduleGraphField $module $graph file {}]
            if {$name ne {}} {
                set graphPath [file normalize [file join $source analysis $module $name]]
                lappend paths $graphPath
                set stem [file rootname [file tail $graphPath]]
                lappend paths [::GX::annotationPathForPlot $graphPath] [file join [file dirname $graphPath] .gxtxt_plotmeta "$stem.ini"] [file join [file dirname $graphPath] .gxtxt_plotmeta "$stem.xrange.ini"]
            }
        }
        # CORE's legacy rerender contract owns render_cache.mat even when an
        # older module descriptor does not list it among declared outputs.
        foreach name {render_cache.mat runtime.ini execution.ini python_runtime.ini .plot_graph_map.tsv} {lappend paths [file normalize [file join $source analysis $module $name]]}
    }
    # Pending acquisition input paths are scientific sources even before they
    # have a Dataset registration. External files remain untouched, too.
    foreach key [dict keys $manifest] {
        if {$key eq "acquisition.input_csv" || [regexp {^generic_csv_batch\.[0-9]+\.path$} $key]} {
            set value [dict get $manifest $key]
            if {$value ne {}} {lappend paths [file normalize [expr {[file pathtype $value] eq "absolute" ? $value : [file join $source $value]}]]}
        }
    }
}
proc ::GX::ExperimentClone::viewersClean {manifest} {
    variable source;variable paths;variable removedDocuments;variable registry
    set retainedLayers {};set excludedViewers {};set retainedViewers {}
    set count [::GX::datasetPublicationV2DictDefault $manifest viewer_layers.count 0]
    for {set index 1} {$index<=$count} {incr index} {
        set prefix viewer_layer.$index
        set module [dict get $manifest $prefix.module_id];set viewer [dict get $manifest $prefix.viewer_id]
        set identity [list $module $viewer];set excluded 0
        foreach field {dataset_id source_dataset_id} {if {[::GX::datasetPublicationV2DictDefault $manifest $prefix.$field {}] ne {}} {set excluded 1}}
        set resource [::GX::datasetPublicationV2DictDefault $manifest $prefix.resource_path {}]
        if {$resource ne {} && [file normalize [file join $source $resource]] in $paths} {set excluded 1}
        # A provider can host both preparation and measurements. Module identity
        # alone cannot establish ownership of an independent artifact layer.
        if {[regexp {^metadata/interactive_document_resources/(idoc_[0-9]+)(/|$)} $resource -> owner] && $owner in $removedDocuments} {set excluded 1}
        if {!$excluded} {
            set mode [::GX::datasetPublicationV2DictDefault $manifest $prefix.source_mode {}]
            set hash [::GX::datasetPublicationV2DictDefault $manifest $prefix.sha256 {}]
            if {[regexp {^(analysis|raw|channels|datasets|cache|logs|report|metadata/graphs|metadata/plot.dataset)(/|$)} $resource]} {set excluded 1}
            if {$mode ne "artifact" || $resource eq {} || [catch {::GX::viewerArtifactResolve $resource $hash}]} {set excluded 1}
        }
        if {$excluded} {
            report excluded $module $viewer [dict get $manifest $prefix.layer_id] {scientific, unproved, or missing viewer resource}
            dict set excludedViewers $identity 1
            if {$resource ne {}} {lappend paths [file normalize [file join $source $resource]]}
        } else {
            lappend ::GX::ExperimentClone::allowedFiles [file normalize [file join $source $resource]]
            report copied $module $viewer [dict get $manifest $prefix.layer_id] {validated independent artifact}
            dict set retainedViewers $identity 1
            dict set retainedLayers [list $module $viewer [dict get $manifest $prefix.layer_id]] 1
        }
    }
    foreach {section plural} {viewer_scene viewer_scenes viewer_layer viewer_layers viewer_attribute viewer_attributes} {
        set rebuilt {};set next 0
        set count [::GX::datasetPublicationV2DictDefault $manifest $plural.count 0]
        for {set index 1} {$index<=$count} {incr index} {
            set prefix $section.$index
            set identity [list [dict get $manifest $prefix.module_id] [dict get $manifest $prefix.viewer_id]]
            if {$section ne "viewer_scene"} {
                if {![dict exists $retainedLayers [concat $identity [list [dict get $manifest $prefix.layer_id]]]]} continue
            } elseif {[dict exists $excludedViewers $identity] && ![dict exists $retainedViewers $identity]} {continue}
            incr next
            foreach key [dict keys $manifest $prefix.*] {dict set rebuilt $section.$next.[string range $key [expr {[string length $prefix]+1}] end] [dict get $manifest $key]}
        }
        foreach key [dict keys $manifest $section.*] {dict unset manifest $key}
        set manifest [dict merge $manifest $rebuilt]
        dict set manifest $plural.count $next
    }
    return $manifest
}
