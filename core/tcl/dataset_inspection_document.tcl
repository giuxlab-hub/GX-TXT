# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only Dataset Inspection projection. Canonical content stays with its
# Metadata/Notes/Schema/Temporal authorities; external writes use File Publication.
proc ::GX::datasetInspectionSectionDocument {dataset section {request {}}} {
    if {$::GX::currentSession eq {} || [datasetField $dataset id {}] eq {}} {error {Activate a canonical Dataset before exporting its current view}}
    set mode [datasetPublicationV2DictDefault $request source saved]
    if {$mode ni {saved draft}} {error {Document source must be saved or draft}}
    set text "Dataset: $dataset\nSection: $section\nContent: [expr {$mode eq {draft} ? {currently displayed draft (not saved)} : {saved canonical content}}]\n\n"
    switch $section {
        notes {
            append text "Format: GX-Markup / Markdown source\n\n"
            append text [expr {$mode eq "draft" ? [dict get $request notes] : [datasetUserNotes $dataset]}]
        }
        metadata {
            set values [expr {$mode eq "draft" ? [dict get $request metadata] : [datasetMetadataRead $::GX::currentSession $dataset]}]
            dict for {key value} $values {
                if {[_datasetMetadataReserved $key]} continue
                append text "$key:\n$value\n\n"
            }
            if {$values eq {}} {append text {No user metadata.}}
            if {[dict exists $request pending_metadata]} {
                set pending [dict get $request pending_metadata]
                if {![catch {dict get $pending key} key] && ![_datasetMetadataReserved $key]} {append text "\nUnapplied key/value buffer:\n$key:\n[dict get $pending value]\n"}
            }
        }
        technical {
            append text "Read-only CORE Dataset Inspection / Provenance\n\n"
            dict for {key value} [sessionInspectionDataset $dataset] {
                if {[_datasetMetadataReserved $key]} continue
                append text "$key:\n$value\n\n"
            }
        }
        variables {
            set values [expr {$mode eq "draft" ? [dict get $request variables] : [datasetVariableSchemaV3 $dataset]}]
            foreach variable $values {
                foreach key {variable_id display_label canonical unit semantic_role value_kind dtype rank dimension_ids shape enabled source_column original_header instrument_id instrument_channel} {
                    if {[dict exists $variable $key]} {append text "$key: [dict get $variable $key]\n"}
                }
                append text "\n"
            }
        }
        temporal {
            foreach item [temporalSetList $dataset] {
                dict for {key value} [temporalSetRead [dict get $item id]] {append text "$key: $value\n"}
                append text "\n"
            }
        }
        default {error {This view requires its own scientific image/plot export. Select Notes, Metadata, Variables, Temporal Sets or Technical Details for text/PDF export.}}
    }
    return [dict create dataset_id $dataset section $section source $mode text $text session_token [interactiveDocumentSessionToken]]
}
