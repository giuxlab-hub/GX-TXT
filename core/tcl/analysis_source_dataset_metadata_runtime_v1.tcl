# GX-TXT Analysis Source Dataset Metadata Runtime Extension v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Dataset Metadata is authoritative in Dataset Metadata API v1 storage. This
# extension copies its public key/value resource into derived standard-module
# runtime state so Octave consumers never need to know or open CORE sidecars.

namespace eval ::GX {
    variable analysisSourceDatasetMetadataRuntimeApiVersion 1
}

proc ::GX::_analysisSourceDatasetMetadataRuntimeIds {runtime} {
    if {[dict exists $runtime analysis_sources.ids]} {
        return [splitList [dict get $runtime analysis_sources.ids]]
    }
    # Historical single-source modules have no Analysis Source Map section.
    # Treat their compatibility [dataset] entry as primary without adding an
    # analysis_sources section, so the existing source-map contract is unchanged.
    if {[dict exists $runtime dataset.id] && [string trim [dict get $runtime dataset.id]] ne ""} {
        return {primary}
    }
    return {}
}

proc ::GX::_analysisSourceDatasetMetadataRuntimeDatasetId {runtime sourceId} {
    set key "analysis_source.$sourceId.dataset_id"
    if {[dict exists $runtime $key]} { return [string trim [dict get $runtime $key]] }
    if {$sourceId eq "primary" && [dict exists $runtime dataset.id]} {
        return [string trim [dict get $runtime dataset.id]]
    }
    return ""
}

# Keep this wrapper outermost in the runtime-generation chain. The complete
# source map must already exist before Dataset Metadata is copied into runtime,
# and regeneration must always reread the authoritative Dataset Metadata API
# resource rather than reusing prior runtime/cache state.
proc ::GX::writeStandardRuntimeConfig_before_temporal_set_v1 {moduleId} {
    variable currentSession
    set path [::GX::writeStandardRuntimeConfig_before_dataset_metadata_runtime_v1 $moduleId]
    if {$currentSession eq "" || ![file isdirectory $currentSession] || ![file isfile $path]} { return $path }

    set runtime [parseIni $path]
    set sourceIds [_analysisSourceDatasetMetadataRuntimeIds $runtime]
    if {[llength $sourceIds] == 0} { return $path }

    loadDatasetRegistry $currentSession
    set fd [open $path a]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "\n\[analysis_source_dataset_metadata_api\]"
        putKV $fd api_version $::GX::analysisSourceDatasetMetadataRuntimeApiVersion

        foreach sourceId $sourceIds {
            # Source IDs are already validated by Analysis Source Map API v1.
            # Validate again before using them in section names because legacy
            # or externally produced runtime files must not create ambiguous INI
            # paths through punctuation normalization.
            if {![analysisSourceValidId $sourceId]} {
                error "$moduleId: invalid Analysis Source ID '$sourceId' while exporting Dataset Metadata."
            }

            set datasetId [_analysisSourceDatasetMetadataRuntimeDatasetId $runtime $sourceId]
            set metadata [dict create]
            set resourceFound 0
            if {$datasetId ne ""} {
                if {[datasetField $datasetId id ""] eq ""} {
                    error "$moduleId: Dataset Metadata source '$sourceId' refers to unregistered Dataset '$datasetId'."
                }
                # datasetMetadataRead is the public authority. Missing resources
                # are normal and return an empty dictionary. The internal path is
                # consulted only to expose whether the resource itself exists;
                # the path is never written to runtime or exposed to modules.
                set metadata [datasetMetadataRead $currentSession $datasetId]
                lassign [_datasetMetadataPath $currentSession $datasetId] _ metadataPath
                set resourceFound [expr {[file isfile $metadataPath] ? 1 : 0}]
            }

            puts $fd "\n\[analysis_source.$sourceId.dataset_metadata\]"
            putKV $fd api_version $::GX::analysisSourceDatasetMetadataRuntimeApiVersion
            putKV $fd dataset_id $datasetId
            putKV $fd found $resourceFound
            putKV $fd count [dict size $metadata]

            # Arbitrary Dataset Metadata keys are values, never INI/Octave field
            # names. This preserves exact identity for legal keys whose dots,
            # hyphens or underscores would otherwise normalize to the same field.
            set index 0
            foreach key [lsort -dictionary [dict keys $metadata]] {
                incr index
                puts $fd "\n\[analysis_source.$sourceId.dataset_metadata.$index\]"
                putKV $fd key $key
                putKV $fd value [dict get $metadata $key]
            }
        }
    } finally {
        close $fd
    }
    return $path
}
