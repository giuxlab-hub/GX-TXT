# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] ui_field_table_original_v1.tcl]
# Canonical scientific Preview projections. The managed Preview admission/lifetime
# owner supplies the Dataset; this service opens no arbitrary paths or payloads.
proc ::GX::_previewScientificIdentity {id} {
    return [dict create dataset_id $id contract [datasetField $id kind {}] revision [datasetRevisionToken $id] canonical_sha256 [datasetField $id canonical_sha256 {}] source_sha256 [datasetField $id source_sha256 {}] producer [datasetField $id source_module {}]]
}
proc ::GX::_previewScientificVariables {id} {
    set result {}
    foreach variable [datasetVariableSchemaV3 $id] {
        if {![datasetPublicationV2DictDefault $variable enabled 1] || [dict get $variable value_kind] eq {text}} continue
        set item {}
        foreach field {variable_id display_label dtype unit coordinate_role semantic_role} {dict set item $field [datasetPublicationV2DictDefault $variable $field {}]}
        set rank [dict get $variable rank]
        if {![string is integer -strict $rank] || $rank<1 || $rank>16} continue
        dict set item rank $rank
        foreach field {shape dimension_ids coordinate_variable_ids} {dict set item $field [datasetSchemaV3SplitIds [datasetPublicationV2DictDefault $variable $field {}]]}
        if {[llength [dict get $item shape]]!=$rank || [llength [dict get $item dimension_ids]]!=$rank} {error {Scientific Preview requires actual complete canonical dimensions}}
        lappend result $item
    }
    return $result
}
proc ::GX::_previewScientificEmptyView {id} {
    return [dict create source [_previewScientificIdentity $id] variables {} variable_total 0 variable_offset 0 variable_limit 0 selected_variable {} page {} frame {} metadata {} metadata_total 0 metadata_offset 0 metadata_limit 0 source_rows {} source_total 0 source_offset 0 source_limit 0]
}
proc ::GX::_previewScientificPageOptions {request default maximum} {
    foreach key [dict keys $request] {if {$key ni {offset limit}} {error {Unknown scientific Preview page option}}}
    set offset [datasetPublicationV2DictDefault $request offset 0];set limit [datasetPublicationV2DictDefault $request limit $default]
    if {![string is wideinteger -strict $offset] || $offset<0 || ![string is integer -strict $limit] || $limit<1 || $limit>$maximum} {error {Scientific Preview offset/limit exceeds its exact bounds}}
    return [list $offset $limit]
}
proc ::GX::_previewScientificUtf8Hex {value} {
    if {[string length $value]>98304 || ![regexp {^([0-9a-f][0-9a-f])*$} $value]} {error {Invalid declared UTF-8 hex source metadata}}
    set raw [binary decode hex $value];set decoded [encoding convertfrom utf-8 $raw]
    if {[encoding convertto utf-8 $decoded] ne $raw} {error {Source metadata is not exact UTF-8}}
    return $decoded
}
proc ::GX::_previewScientificSourceRows {id metadata} {
    set rows {};dict for {key value} [_previewScientificIdentity $id] {lappend rows [dict create key "CORE identity: $key" value $value]}
    # This is an explicit producer-declared reversible text representation,
    # never authority for the independently pinned Dataset/RAW identities above.
    set encoded [expr {[datasetPublicationV2DictDefault $metadata measurement.source_metadata_key_encoding {}] eq {utf8_hex_v1} && [datasetPublicationV2DictDefault $metadata measurement.source_metadata_value_encoding {}] eq {utf8_hex_v1}}]
    foreach key [lsort -dictionary [dict keys $metadata]] {
        if {$encoded && [regexp {^measurement[.]source_metadata[.]k_([0-9a-f]+)$} $key -> hex]} {
            set label [_previewScientificUtf8Hex $hex]
            if {![dict exists $metadata measurement.source_metadata_key.k_$hex] || [dict get $metadata measurement.source_metadata_key.k_$hex] ne $label} {error {Declared original source metadata key mapping disagrees}}
            lappend rows [dict create key "Source header: $label" value [_previewScientificUtf8Hex [dict get $metadata $key]]]
        } elseif {[string match acquisition.* $key] || [string match source.* $key] || (!$encoded && [string match measurement.source_* $key])} {
            lappend rows [dict create key "Source metadata: $key" value [dict get $metadata $key]]
        }
    }
    return $rows
}
proc ::GX::_previewScientificDatasetOperation {id operation request} {
    if {[catch {dict size $request}]} {error {Scientific Preview request must be an inert dictionary}}
    set before [_previewScientificIdentity $id];set result [dict create source $before]
    switch -- $operation {
        discover {
            lassign [_previewScientificPageOptions $request 32 64] offset limit
            set variables [_previewScientificVariables $id]
            dict set result variables [lrange $variables $offset [expr {$offset+$limit-1}]]
            dict set result variable_total [llength $variables];dict set result variable_offset $offset;dict set result variable_limit $limit
        }
        page {
            if {[lsort [dict keys $request]] ne {counts starts variable_id}} {error {Scientific values require variable_id and exact rank-shaped starts/counts}}
            set variables [_previewScientificVariables $id];set selected {};foreach variable $variables {if {[dict get $variable variable_id] eq [dict get $request variable_id]} {set selected $variable;break}}
            if {$selected eq {}} {error {Select an actual enabled canonical numeric Variable}}
            set starts [dict get $request starts];set counts [dict get $request counts];set rank [dict get $selected rank]
            if {[llength $starts]!=$rank || [llength $counts]!=$rank} {error {Scientific values page rank differs from the actual Variable}}
            set cells 1
            foreach start $starts count $counts extent [dict get $selected shape] {
                if {![string is wideinteger -strict $start] || ![string is wideinteger -strict $count] || $start<0 || $count<1 || $start>$extent || $count>$extent-$start} {error {Scientific values page is outside the actual canonical shape}}
                set cells [expr {$cells*$count}];if {$cells>512} {error {Scientific values page exceeds512 cells}}
            }
            set handle [datasetAccessOpen $::GX::currentSession $id]
            try {
                set page [datasetAccessReadHyperslab $handle [dict get $selected variable_id] $starts $counts]
                set coordinates {}
                foreach coordinateId [dict get $selected coordinate_variable_ids] {
                    set coordinate {};foreach variable $variables {if {[dict get $variable variable_id] eq $coordinateId} {set coordinate $variable;break}}
                    if {$coordinate eq {}} {error {Declared canonical coordinate Variable is unavailable}}
                    set coordinateStarts {};set coordinateCounts {};set coordinateCells 1
                    foreach dimension [dict get $coordinate dimension_ids] extent [dict get $coordinate shape] {
                        set axis [lsearch -exact [dict get $selected dimension_ids] $dimension]
                        if {$axis<0 || $extent != [lindex [dict get $selected shape] $axis]} {error {Canonical coordinate dimensions differ from their scientific Variable}}
                        lappend coordinateStarts [lindex $starts $axis];lappend coordinateCounts [lindex $counts $axis]
                        set coordinateCells [expr {$coordinateCells*[lindex $counts $axis]}]
                    }
                    set chunk [datasetAccessReadHyperslab $handle $coordinateId $coordinateStarts $coordinateCounts]
                    if {[llength [dict get $chunk values]]!=$coordinateCells} {error {Canonical coordinate page length differs}}
                    lappend coordinates [dict create variable_id $coordinateId dtype [dict get $coordinate dtype] unit [dict get $coordinate unit] rank [dict get $coordinate rank] dimension_id [expr {[dict get $coordinate rank]==1?[lindex [dict get $coordinate dimension_ids] 0]:{}}] dimension_ids [dict get $coordinate dimension_ids] starts $coordinateStarts counts $coordinateCounts values [dict get $chunk values]]
                }
            } finally {datasetAccessClose $handle}
            set values [dict get $page values]
            if {[llength $values]!=$cells} {error {Canonical scientific values page length disagrees}}
            dict set result selected_variable [dict get $selected variable_id]
            dict set result page [dict create variable_id [dict get $selected variable_id] dtype [dict get $selected dtype] unit [dict get $selected unit] order C starts $starts counts $counts values $values coordinates $coordinates]
        }
        metadata - source {
            lassign [_previewScientificPageOptions $request 16 50] offset limit
            set metadata [datasetMetadataRead $::GX::currentSession $id];set rows {}
            if {$operation eq {source}} {set rows [_previewScientificSourceRows $id $metadata];set field source_rows;set prefix source
            } else {foreach key [lsort -dictionary [dict keys $metadata]] {lappend rows [dict create key $key value [dict get $metadata $key]]};set field metadata;set prefix metadata}
            dict set result $field [lrange $rows $offset [expr {$offset+$limit-1}]]
            dict set result ${prefix}_total [llength $rows];dict set result ${prefix}_offset $offset;dict set result ${prefix}_limit $limit
        }
        default {error {Unknown scientific Preview operation}}
    }
    if {[_previewScientificIdentity $id] ne $before} {error {Scientific Dataset or metadata revision changed during the read}}
    return $result
}
proc ::GX::_previewScientificViewTyped {view} {
    set variable {record {variable_id text display_label text dtype text unit text rank int shape {array int} dimension_ids {array text} coordinate_variable_ids {array text} coordinate_role text semantic_role text}}
    set shape [list record [dict create source {record {dataset_id text contract text revision text canonical_sha256 text source_sha256 text producer text}} variables [list array $variable] variable_total int variable_offset int variable_limit int selected_variable text metadata {array {record {key text value text}}} metadata_total int metadata_offset int metadata_limit int source_rows {array {record {key text value text}}} source_total int source_offset int source_limit int]]
    set typed [nativeWorkspaceEncode $shape [dict remove $view page frame]];set fields [lindex $typed 1]
    if {[dict get $view page] eq {}} {dict set fields page {null {}}
    } else {dict set fields page [nativeWorkspaceEncode {record {variable_id text dtype text unit text order text starts {array int} counts {array int} values {array text} coordinates {array {record {variable_id text dtype text unit text rank int dimension_id text dimension_ids {array text} starts {array int} counts {array int} values {array text}}}}}} [dict get $view page]]}
    set frame [datasetPublicationV2DictDefault $view frame {}]
    if {$frame eq {}} {dict set fields frame {null {}}
    } else {dict set fields frame [nativeWorkspaceEncode {record {variable_id text dtype text unit text x_dimension_id text y_dimension_id text source_revision text starts {array int} counts {array int} indices {array {record {dimension_id text index int}}} minimum text maximum text finite_count int width int height int}} $frame]}
    return [list object $fields]
}

proc ::GX::_previewScientificDeclared {design} {
    dict for {form maps} [_viewerGuiClientRoleMapsValidate $design] {if {[dict exists $maps scientific_preview_components]} {return 1}}
    return 0
}
proc ::GX::_previewScientificGuard {host form method {event 1}} {
    set gui [_datasetPreviewGuiRequire $host]
    if {![dict exists $::GX::PreviewCpp::mounts $host]} {error {Scientific native Preview has closed}}
    set r [dict get $::GX::PreviewCpp::mounts $host];set module [dict get $r module]
    if {[datasetPublicationV2DictDefault $r native_client_module {}] ne $module || [dict get $gui module] ne $module ||
        $method ni [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $r native_client_grants {}] PREVIEW_COMPONENT_GUI_API_v1 {}]} {error {Scientific operation lacks its actual admitted native capability}}
    if {![dict exists $r scientific_package_snapshot] || [_viewerNativeClientPackageSnapshot [dict get $r root]] ne [dict get $r scientific_package_snapshot] || [_previewCppDesign $module [dict get $r root]] ne [dict get $r design]} {error {Scientific Preview package/source changed after admission}}
    if {$event && (![dict get $r busy] || [datasetPublicationV2DictDefault $r scientific_scope {}] ne [list [dict get $r request] [dict get $r generation]])} {error {Scientific Preview event lifetime ended}}
    set maps [_viewerGuiClientRoleMapsValidate [dict get $r design]]
    if {![dict exists $maps $form scientific_preview_components]} {error {Scientific operation requires its actual declared section}}
    return [dict get $maps $form scientific_preview_components]
}
proc ::GX::_previewScientificRequest {operation sdk} {
    set typed [_viewerWorkspaceSdkValue $sdk]
    if {[lindex $typed 0] ne {object}} {error {Scientific request requires an explicit typed object}}
    set fields [lindex $typed 1]
    set allowed [expr {$operation eq {page}?{variable_id starts counts}:{offset limit}}]
    dict for {key value} $fields {
        if {$key ni $allowed} {error {Unknown typed scientific request field}}
        set expected [expr {$key eq {variable_id}?{text}:($key in {starts counts}?{array}:{int})}]
        if {[lindex $value 0] ne $expected} {error {Scientific page fields require their exact declared types}}
        if {$expected eq {array}} {foreach item [lindex $value 1] {if {[lindex $item 0] ne {int}} {error {Scientific indices require integers, not booleans or floats}}}}
    }
    return [nativeWorkspaceDecode $typed]
}
proc ::GX::_previewScientificEnvelope {host form operation status error view result sequence} {
    set generation [datasetPublicationV2DictDefault [dict get $::GX::PreviewCpp::mounts $host] generation 0]
    set typed [_viewerNativeClientEnvelope $operation $status $error $result [_previewScientificViewTyped $view] $sequence $generation]
    set fields [lindex $typed 1];dict set fields form_id [list text $form];set typed [list object $fields]
    if {[string length [encoding convertto utf-8 [_viewerWorkspaceTypedJson $typed]]]>49152} {error {Scientific receipt exceeds48KiB; request a smaller page}}
    return $typed
}
proc ::GX::_previewScientificSnapshot {host} {
    _datasetPreviewGuiRequire $host
    set r [dict get $::GX::PreviewCpp::mounts $host]
    if {[dict exists $r scientific_result]} {return [_viewerWorkspaceTypedJson [dict get $r scientific_result]]}
    return [_viewerWorkspaceTypedJson [_previewScientificEnvelope $host {} snapshot completed {} [_previewScientificEmptyView [dict get [datasetPreviewGuiContext $host] dataset_id]] {null {}} 0]]
}
proc ::GX::_previewScientificIndices {selected starts counts ordinal} {
    set values {}
    for {set axis [expr {[llength $counts]-1}]} {$axis>=0} {incr axis -1} {
        set count [lindex $counts $axis];set index [expr {[lindex $starts $axis]+$ordinal%$count}];set ordinal [expr {$ordinal/$count}]
        set values [linsert $values 0 "[lindex $selected $axis]=$index"]
    }
    return [join $values {, }]
}
proc ::GX::_previewScientificRender {host form view operation} {
    set roles [_previewScientificGuard $host $form scientific_preview_command]
    set design [dict get $::GX::PreviewCpp::mounts $host design]
    foreach role {metadata source} field {metadata source_rows} {
        if {$operation ne $role} continue
        set rows {};foreach item [dict get $view $field] {lappend rows [list [dict get $item key] [dict get $item value]]}
        datasetPreviewGuiTableSet $host [dict get $roles $role] $rows
        uiFieldTableOriginalAttach [dict get [_datasetPreviewGuiControl $host [dict get $roles $role]] widget] [list ::GX::_previewScientificGuard $host $form scientific_preview_command 0]
    }
    if {$operation ne {page}} return
    set page [dict get $view page];set id [dict get $roles values]
    set component [_previewCppNumericComponent $host $id table];set columns [dict get $component properties columns]
    if {[llength $columns] ni {2 3}} {error {Scientific Values table requires2or3 declared columns}}
    set selected {};foreach item [_previewScientificVariables [dict get $view source dataset_id]] {if {[dict get $item variable_id] eq [dict get $page variable_id]} {set selected $item;break}}
    set coordinate {}
    if {[llength [dict get $page counts]]==1 && [llength [dict get $page coordinates]]==1} {
        set candidate [lindex [dict get $page coordinates] 0]
        if {[dict get $candidate rank]==1 && [dict get $candidate counts] eq [dict get $page counts]} {set coordinate $candidate}
    }
    set rows {};set ordinal 0
    foreach value [dict get $page values] {
        set index [_previewScientificIndices [dict get $selected dimension_ids] [dict get $page starts] [dict get $page counts] $ordinal]
        if {[llength $columns]==2} {lappend rows [list $index $value]
        } else {lappend rows [list $index [expr {$coordinate eq {}?{}:[lindex [dict get $coordinate values] $ordinal]}] $value]}
        incr ordinal
    }
    datasetPreviewGuiTableSet $host $id $rows
    set widget [dict get [_datasetPreviewGuiControl $host $id] widget];set table [uiFieldComponentTableWidget $widget]
    set labels [list {Source indices}]
    if {[llength $columns]==3} {lappend labels [expr {$coordinate eq {}?{No scalar coordinate}:"[dict get $coordinate variable_id] ([dict get $coordinate unit])"}]}
    lappend labels "[dict get $page variable_id] ([dict get $page unit])"
    foreach column [$table cget -columns] label $labels {$table heading $column -text $label}
}
proc ::GX::_previewScientificCommand {host form intent} {
    set roles [_previewScientificGuard $host $form scientific_preview_command]
    set operation [dict get $intent command];set r [dict get $::GX::PreviewCpp::mounts $host]
    set sequence [expr {[datasetPublicationV2DictDefault $r scientific_sequence 0]+1}]
    dict set ::GX::PreviewCpp::mounts $host scientific_sequence $sequence
    set view [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $r scientific_views {}] $form [_previewScientificEmptyView [dict get [datasetPreviewGuiContext $host] dataset_id]]]
    try {
        set request [_previewScientificRequest $operation [dict get $intent request]]
        set delta [_previewScientificDatasetOperation [dict get $view source dataset_id] $operation $request]
        _previewScientificGuard $host $form scientific_preview_command
        set next [dict merge $view $delta]
        set receipt [_previewScientificEnvelope $host $form $operation completed {} $next {object {}} $sequence]
        _previewScientificRender $host $form $next $operation
        _previewScientificGuard $host $form scientific_preview_command
        dict set ::GX::PreviewCpp::mounts $host scientific_views $form $next
        dict set ::GX::PreviewCpp::mounts $host scientific_result $receipt
    } on error {message options} {
        if {[dict exists $::GX::PreviewCpp::mounts $host]} {
            if {[catch {set failed [_previewScientificEnvelope $host $form $operation failed [string range $message 0 2047] $view {null {}} $sequence]}]} {
                # A near-limit previous page plus diagnostic must not prevent a
                # fresh failed/null receipt or expose an older completed one.
                set failed [_previewScientificEnvelope $host $form $operation failed [string range $message 0 2047] [_previewScientificEmptyView [dict get $view source dataset_id]] {null {}} $sequence]
            }
            dict set ::GX::PreviewCpp::mounts $host scientific_result $failed
        }
        return -options $options $message
    }
}
proc ::GX::_previewScientificFailed {host message} {
    if {![dict exists $::GX::PreviewCpp::mounts $host]} return
    set r [dict get $::GX::PreviewCpp::mounts $host]
    if {![datasetPublicationV2DictDefault $r scientific_client 0]} return
    set sequence [expr {[datasetPublicationV2DictDefault $r scientific_sequence 0]+1}]
    set view [_previewScientificEmptyView [dict get [datasetPreviewGuiContext $host] dataset_id]]
    dict set ::GX::PreviewCpp::mounts $host scientific_sequence $sequence
    dict set ::GX::PreviewCpp::mounts $host scientific_result [_previewScientificEnvelope $host {} native_event failed [string range $message 0 2047] $view {null {}} $sequence]
}

proc ::GX::_previewScientificPlotDefaults {id} {
    set variables [_previewScientificVariables $id];set byId {}
    foreach variable $variables {if {[dict get $variable rank]==1} {dict set byId [dict get $variable variable_id] $variable}}
    set metadata [datasetMetadataRead $::GX::currentSession $id]
    set x [datasetPublicationV2DictDefault $metadata spectral_x_variable_id {}]
    set y [datasetPublicationV2DictDefault $metadata spectral_y_variable_id {}]
    if {$x ne {} || $y ne {}} {
        if {$x eq $y || ![dict exists $byId $x] || ![dict exists $byId $y] || $x ni [dict get $byId $y coordinate_variable_ids] || [dict get $byId $x dimension_ids] ne [dict get $byId $y dimension_ids]} {error {Declared scientific X/Y references disagree with the actual canonical Variables}}
        return [dict create plot_x $x plot_y $y]
    }
    set times {};foreach variable $variables {if {[dict get $variable rank]==1 && [dict get $variable semantic_role] eq {time}} {lappend times [dict get $variable variable_id]}}
    if {[llength $times]==1} {
        set x [lindex $times 0];set signals {}
        foreach variable $variables {if {[dict get $variable rank]==1 && [dict get $variable semantic_role] eq {signal} && $x in [dict get $variable coordinate_variable_ids]} {lappend signals [dict get $variable variable_id]}}
        if {[llength $signals]==1} {return [dict create plot_x $x plot_y [lindex $signals 0]]}
    }
    return {}
}

source [file join [file dirname [info script]] viewer_scientific_frame_v1.tcl]
