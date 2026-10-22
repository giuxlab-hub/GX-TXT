# SPDX-License-Identifier: GPL-3.0-or-later
# Backend-neutral Dataset curve identity, exact access and bounded display.
namespace eval ::GX::CurveSource {variable serial 0;variable records;array set records {}}
proc ::GX::curveSourceApiInfo {} {
    return [dict create api_id CURVE_SOURCE_API_v1 api_version 1 operations {open describe dataset_identity validate_snapshot validate_point_mask display display_batch display_cache_store display_cache_restore page locate_rows open_stream close_stream close} chunk_rows_max 65536 display_budget_max 65536 display_policy ordered_xy_extrema_per_source_row_bucket scientific_authority canonical_dataset display_is_scientific_data 0 continuity_policies {source_row_adjacency}]
}
proc ::GX::curveSourceDatasetIdentity {session dataset} {
    if {[file normalize $session] ne [file normalize [sessionInspectionCurrentSession]]} {error {Curve Source identity belongs to another active Session}}
    return [_curveSourceIdentity $session [datasetPublicationV2ValidateId dataset $dataset]]
}
proc ::GX::curveSourceValidateSnapshot {session descriptor} {
    if {[dict get $descriptor api_id] ne "CURVE_SOURCE_API_v1"||[dict get $descriptor api_version]!=1} {error "Invalid Curve Source snapshot"}
    set current {};set stale {};set missing {};set reasons {}
    foreach identity [dict get $descriptor source_identities] {
        set id [datasetPublicationV2ValidateId dataset [dict get $identity dataset_id]]
        if {[catch {set actual [_curveSourceIdentity $session $id]} message]} {lappend missing $id;lappend reasons "$id: $message";continue}
        lappend current $actual
        set changed 0;foreach key {dataset_id sha256 schema_identity} {if {![dict exists $identity $key]||[dict get $actual $key] ne [dict get $identity $key]} {set changed 1}}
        if {$changed} {lappend stale $id}
    }
    # Additive batch snapshots bind origin/continuity as well as payload/schema.
    # Old descriptors retain their established validation contract.
    if {[dict exists $descriptor batch_context]} {
        set id [dict get $descriptor request dataset_id]
        if {[catch {set context [_curveSourceBatchContext $session $id]} message]} {
            if {$id ni $missing} {lappend missing $id};lappend reasons "$id: $message"
        } elseif {$context ne [dict get $descriptor batch_context]} {
            if {$id ni $stale} {lappend stale $id};lappend reasons "$id: Session origin or declared continuity changed"
        }
    }
    set status [expr {$missing ne {} ? "missing" : $stale ne {} ? "stale" : "current"}]
    return [dict create status $status valid [expr {$status eq "current"}] missing_dataset_ids $missing stale_dataset_ids $stale source_identities $current reasons $reasons]
}
proc ::GX::_curveSourceBatchContext {session id {metadata @read}} {
    if {$metadata eq "@read"} {set metadata [datasetMetadataRead $session $id]}
    return [dict create session_origin [sessionOriginRead $session] continuity_policy [datasetPublicationV2DictDefault $metadata curve_source.continuity_policy {}] continuity_variable_id [datasetPublicationV2DictDefault $metadata curve_source.continuity_variable_id {}]]
}
proc ::GX::_curveSourceIdentity {session dataset} {
    set scientific {}
    foreach variable [datasetVariableSchemaV3 $dataset] {
        set variable [dict remove $variable display_label description semantic_reason]
        set canonical {}
        foreach key [lsort [dict keys $variable]] {lappend canonical $key [dict get $variable $key]}
        lappend scientific $canonical
    }
    return [dict create dataset_id $dataset sha256 [dict get [sessionInspectionDatasetPayload $dataset $session] sha256] schema_identity [datasetStorageSha256Text $session $scientific]]
}
proc ::GX::_curveSourceRequire {token} {
    variable ::GX::CurveSource::records;variable currentSession
    if {![info exists records($token)]} {error "Unknown or closed Curve Source token"}
    set record $records($token)
    if {[interactiveDocumentSessionToken] ne [dict get $record session_token]} {error "Curve Source belongs to a different Session lifetime"}
    foreach identity [dict get $record identities] {
        if {[_curveSourceIdentity [dict get $record session] [dict get $identity dataset_id]] ne $identity} {error "Curve Source payload or scientific schema changed; reopen the source"}
    }
    return $record
}
proc ::GX::curveSourceOpen {session request {progress {}}} {
    variable ::GX::CurveSource::serial;variable ::GX::CurveSource::records
    set session [file normalize $session]
    set ::GX::currentSession $session;loadDatasetRegistry $session
    if {[catch {dict size $request}]} {error "Curve Source request must be a dictionary"}
    foreach key [dict keys $request] {
        if {$key ni {dataset_id x_variable_id y_variable_id member_id filters selection_id start count display_budget transform_manifest order_variable_id}} {error "Unknown Curve Source field '$key'"}
    }
    foreach key {dataset_id x_variable_id y_variable_id} {
        if {![dict exists $request $key]} {error "Curve Source needs $key"}
        datasetPublicationV2ValidateId [expr {$key eq "dataset_id" ? "dataset" : "variable"}] [dict get $request $key]
    }
    foreach {key default minimum maximum} {start 0 0 -1 count -1 -1 -1 display_budget 4096 6 65536} {
        set value [datasetPublicationV2DictDefault $request $key $default]
        if {![string is entier -strict $value]||$value<$minimum||($maximum>=0&&$value>$maximum)} {error "Invalid Curve Source $key"}
        dict set request $key $value
    }
    set view "";set stream "";set sessionToken [interactiveDocumentSessionToken]
    try {
        set dataset [dict get $request dataset_id]
        set identity [_curveSourceIdentity $session $dataset]
        set identities [list $identity];set lineage "";set manifest {}
        set filters [datasetPublicationV2DictDefault $request filters {}]
        set selection [datasetPublicationV2DictDefault $request selection_id ""]
        set order [datasetPublicationV2DictDefault $request order_variable_id ""]
        if {[dict exists $request transform_manifest]} {
            if {$filters ne {}||$selection ne ""||$order ne ""} {error "Put filters/Selection/order in the explicit Transform manifest"}
            set manifest [dict get $request transform_manifest]
            set identities {}
            foreach source [dict get $manifest sources] {lappend identities [_curveSourceIdentity $session [dict get $source dataset_id]]}
            set transformOptions [datasetPublicationV2DictDefault $manifest options {}]
            if {[llength [dict get $manifest sources]]==1&&[datasetPublicationV2DictDefault $transformOptions include_lineage 0]} {
                if {[dict get [lindex [dict get $manifest sources] 0] dataset_id] ne $dataset} {error "Curve Source Dataset must match its single-source transform"}
                set lineage "[datasetPublicationV2DictDefault $transformOptions lineage_prefix selection_]source_row_ordinal"
            }
        } elseif {$filters ne {}||$selection ne ""||$order ne ""} {
            set source [dict create dataset_id $dataset x_variable_id [dict get $request x_variable_id] y_variable_id [dict get $request y_variable_id]]
            if {$filters ne {}} {dict set source row_filters $filters}
            if {$selection ne ""} {dict set source selection_id $selection}
            set existing [lmap variable [datasetVariableSchemaV3 $dataset] {dict get $variable variable_id}]
            set suffix 1;set prefix curve_source_
            while {1} {
                set collision 0
                foreach field {member_id source_dataset_id source_sha256 source_row_ordinal source_x_variable_id source_y_variable_id} {
                    if {"$prefix$field" in $existing} {set collision 1;break}
                }
                if {!$collision} break
                set prefix "curve_source[incr suffix]_"
            }
            set transformOptions [dict create include_lineage 1 lineage_prefix $prefix]
            set operation concat_rows
            if {$order ne ""} {set operation sort_rows;dict set transformOptions order_variable_ids [list $order]}
            set manifest [dict create api_version 1 operation $operation sources [list $source] options $transformOptions]
            set lineage ${prefix}source_row_ordinal
        }
        if {$manifest ne {}} {set view [datasetTransformOpenView $session $manifest]}
        set options [dict create start [dict get $request start] count [dict get $request count]]
        set variables [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
        if {[lindex $variables 0] eq [lindex $variables 1]} {error "Curve Source X/Y Variable IDs must be distinct"}
        set openChunkRows [expr {$progress eq {}?65536:4096}]
        if {$view eq ""} {set stream [tableStreamOpenDataset $session $dataset $variables $openChunkRows [dict merge $options [dict create numeric_transport auto]]]} else {set stream [datasetTransformOpenViewStream $view $variables $openChunkRows $options]}
        set metadata [tableStreamMetadata $stream]
        foreach spec [dict get $metadata variables] {if {[dict get $spec dtype] eq "string"} {error "Curve Source X/Y variables must be numeric"}}
        set total [dict get $metadata row_count]
        if {$total<0} {
            # Unknown provider counts need one bounded counting pass. Numeric
            # values never accumulate in Tcl; the display pass opens afresh.
            set total [dict get $request start]
            while {1} {
                set chunk [tableStreamNext $stream];incr total [dict get $chunk row_count]
                if {$progress ne {}} {curveSourceCooperativeBoundary $progress [dict create stage count_rows completed_rows $total total_rows -1]}
                if {$sessionToken ne [interactiveDocumentSessionToken]} {error {Curve Source opening cancelled by Session change}}
                if {[dict get $chunk eof]} break
            }
        }
        set start [dict get $request start]
        set count [dict get $request count]
        if {$count<0} {set count [expr {$total-$start}]}
        if {$count<1} {error "Curve Source range needs at least one row"}
        dict set request count $count
        tableStreamClose $stream;set stream ""
        set sourceId "curve-source:[datasetStorageSha256Text $session [list $identities [dict remove $request display_budget]]]"
        set token "curve-source#[pid]-[incr serial]"
        set records($token) [dict create session $session session_token [interactiveDocumentSessionToken] request $request identities $identities source_id $sourceId view $view manifest $manifest lineage_variable $lineage metadata $metadata row_count $count streams {} display {}]
        set view "";return $token
    } finally {
        if {$stream ne ""} {tableStreamClose $stream}
        if {$view ne ""} {datasetTransformCloseView $view}
    }
}
proc ::GX::curveSourceDescribe {token} {
    set record [_curveSourceRequire $token];set request [dict get $record request]
    set kind [expr {[dict get $record view] eq "" ? "dataset" : "transform_view"}]
    set identityKind [expr {$kind eq "dataset"||[dict get $record lineage_variable] ne "" ? "dataset_row" : "transform_view_row"}]
    set variables [dict get [dict get $record metadata] variables]
    if {$kind eq "dataset"} {set variables [list [datasetVariableV3ById [dict get $request dataset_id] [dict get $request x_variable_id]] [datasetVariableV3ById [dict get $request dataset_id] [dict get $request y_variable_id]]]}
    return [dict create api_id CURVE_SOURCE_API_v1 api_version 1 source_id [dict get $record source_id] source_kind $kind row_identity_kind $identityKind request $request row_count [dict get $record row_count] variables $variables source_identities [dict get $record identities] display_budget [dict get $request display_budget] display_is_scientific_data 0]
}
proc ::GX::curveSourceOpenStream {token {variableIds {}} {chunkRows 65536} {options {}}} {
    variable ::GX::CurveSource::records
    set record [_curveSourceRequire $token];set request [dict get $record request]
    if {![string is entier -strict $chunkRows]||$chunkRows<1||$chunkRows>65536} {error "Curve Source chunk_rows must be 1..65536"}
    foreach key [dict keys $options] {if {$key ni {start count numeric_transport}} {error "Unknown Curve Source stream option '$key'"}}
    set localStart [datasetPublicationV2DictDefault $options start 0]
    set localCount [datasetPublicationV2DictDefault $options count -1]
    set total [dict get $record row_count]
    if {![string is entier -strict $localStart]||![string is entier -strict $localCount]||$localStart<0||$localStart>$total||$localCount< -1||($localCount>=0&&$localStart+$localCount>$total)} {error "Exact Curve Source stream range is outside its source window"}
    if {$localCount<0} {set localCount [expr {$total-$localStart}]}
    set absolute [expr {[dict get $request start]+$localStart}]
    set range [dict create start $absolute count $localCount]
    if {$variableIds eq {}} {set variableIds [list [dict get $request x_variable_id] [dict get $request y_variable_id]]}
    if {[dict get $record view] eq ""} {
        dict set range numeric_transport [datasetPublicationV2DictDefault $options numeric_transport auto]
        set stream [tableStreamOpenDataset [dict get $record session] [dict get $request dataset_id] $variableIds $chunkRows $range]
    } else {set stream [datasetTransformOpenViewStream [dict get $record view] $variableIds $chunkRows $range]}
    dict lappend records($token) streams $stream;return $stream
}
proc ::GX::curveSourceCloseStream {token stream} {
    variable ::GX::CurveSource::records
    if {![info exists records($token)]||$stream ni [dict get $records($token) streams]} {error "Stream is not owned by this Curve Source"}
    tableStreamClose $stream
    set streams [dict get $records($token) streams]
    dict set records($token) streams [lreplace $streams [lsearch -exact $streams $stream] [lsearch -exact $streams $stream]]
}
proc ::GX::curveSourceLocateRows {token rowIds {progress ""}} {
    set record [_curveSourceRequire $token];set request [dict get $record request]
    set normalized {}
    foreach row $rowIds {
        if {![string is entier -strict $row]||$row<0||$row>18446744073709551615} {error "Invalid exact source row identity"}
        lappend normalized [expr {$row+0}]
    }
    set rowIds $normalized
    if {[llength $rowIds]<1||[llength $rowIds]>65536||[llength [lsort -unique $rowIds]]!=[llength $rowIds]} {error "Row lookup requires 1..65536 distinct source row identities"}
    set positions {};set stream "";set lineage [dict get $record lineage_variable]
    if {$lineage eq ""} {
        foreach row $rowIds {
            set position [expr {$row-[dict get $request start]}]
            if {$position<0||$position>=[dict get $record row_count]} {error "Requested row is outside this source"}
            lappend positions $position
        }
    } else {
        set wanted {};foreach row $rowIds {dict set wanted $row 1};set found {};set offset 0
        try {
            set stream [curveSourceOpenStream $token [list $lineage] 65536 [dict create numeric_transport values]]
            while {1} {
                set chunk [tableStreamNext $stream]
                foreach row [dict get $chunk values $lineage] {
                    if {[dict exists $wanted $row]} {
                        if {[dict exists $found $row]} {error "Source row identity is ambiguous in this view"}
                        dict set found $row $offset
                    }
                    incr offset
                }
                if {$progress ne ""} {curveSourceCooperativeBoundary $progress [dict create stage locate_rows completed_rows $offset total_rows [dict get $record row_count]];_curveSourceRequire $token}
                if {[dict get $chunk eof]} break
            }
        } finally {if {$stream ne ""} {curveSourceCloseStream $token $stream}}
        foreach row $rowIds {
            if {![dict exists $found $row]} {error "Requested row does not belong to this source"}
            lappend positions [dict get $found $row]
        }
    }
    return [dict create api_id CURVE_SOURCE_ROW_LOCATIONS_v1 source_id [dict get $record source_id] source_rows $rowIds positions $positions]
}
proc ::GX::_curveSourceNativeColumn {column} {
    if {[dict exists $column binary_block]} {
        set block [dict get $column binary_block];datasetBinaryValidateBlock $block [dict get $column count]
        return [dict create dtype [dict get $block dtype] endian [dict get $block endian] raw [binary decode base64 [dict get $block base64]]]
    }
    return [dict create values [dict get $column values] dtype [dict get $column dtype]]
}
proc ::GX::curveSourceDisplay {token} {
    variable ::GX::CurveSource::records
    set record [_curveSourceRequire $token]
    if {[dict get $record display] ne {}} {return [dict get $record display]}
    if {[dict get $record row_count]==1} {
        set request [dict get $record request]
        set ids [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
        set lineage [dict get $record lineage_variable]
        if {$lineage ne {}} {lappend ids $lineage}
        set stream [curveSourceOpenStream $token $ids 1 {numeric_transport values}]
        try {
            set chunk [tableStreamNext $stream];set point {}
            foreach id [lrange $ids 0 1] {
                set value [lindex [dict get $chunk values $id] 0]
                if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {The selected source point is nonfinite}}
                lappend point $value
            }
            set row [expr {$lineage eq {}?[dict get $request start]:[lindex [dict get $chunk values $lineage] 0]}]
            set result [dict create points [list $point] source_rows [list $row] breaks {} full_bounds [concat $point $point] finite_rows 1 display_rows 1 row_count 1 reduced 0 source_id [dict get $record source_id] display_is_scientific_data 0 diagnostics [tableStreamDiagnostics $stream]]
            dict set records($token) display $result
            return $result
        } finally {curveSourceCloseStream $token $stream}
    }
    native2DEnsure
    set request [dict get $record request];set scene [::GX::Native2D::core scene];set stream ""
    try {
        set ids [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
        set lineage [dict get $record lineage_variable]
        if {$lineage ne ""} {lappend ids $lineage}
        set stream [curveSourceOpenStream $token $ids]
        ::GX::Native2D::core sample_begin $scene [dict get $record row_count] [dict get $request display_budget] [dict get $request start]
        set position 0
        while {1} {
            set chunk [tableStreamNext $stream]
            set columns [dict get $chunk columns]
            set x [_curveSourceNativeColumn [lindex $columns 0]]
            set y [_curveSourceNativeColumn [lindex $columns 1]]
            if {$lineage eq ""} {::GX::Native2D::core sample_push $scene $position $x $y} else {::GX::Native2D::core sample_push $scene $position $x $y [_curveSourceNativeColumn [lindex $columns 2]]}
            incr position [dict get $chunk row_count]
            if {[dict get $chunk eof]} break
        }
        set diagnostics [tableStreamDiagnostics $stream]
        curveSourceCloseStream $token $stream;set stream ""
        set sampled [::GX::Native2D::core sample_finish $scene]
        set points [::GX::Native2D::core points $scene [dict get $sampled object]]
        set result [dict merge [dict remove $sampled object] [dict create points $points source_id [dict get $record source_id] row_count [dict get $record row_count] reduced [expr {[dict get $sampled display_rows]<[dict get $sampled finite_rows]}] display_is_scientific_data 0 diagnostics $diagnostics]]
        _curveSourceRequire $token
        set result [_curveSourceContinuityDisplay $token $result]
        dict set records($token) display $result
        return $result
    } finally {
        if {$stream ne ""} {curveSourceCloseStream $token $stream}
        ::GX::Native2D::core destroy $scene
    }
}
proc ::GX::curveSourcePage {token {start 0} {count 200}} {
    set record [_curveSourceRequire $token]
    if {![string is entier -strict $start]||$start<0||$start>[dict get $record row_count]} {error "Curve Source page starts outside its range"}
    if {![string is entier -strict $count]||$count<1||$count>1000} {error "Curve Source page count must be 1..1000"}
    set count [expr {min($count,[dict get $record row_count]-$start)}]
    if {$count<0} {error "Curve Source page starts outside its range"}
    set request [dict get $record request]
    set ids [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
    set lineage [dict get $record lineage_variable]
    if {$lineage ne ""} {lappend ids $lineage}
    set stream [curveSourceOpenStream $token $ids [expr {max(1,$count)}] [dict create start $start count $count numeric_transport values]]
    try {
        set chunk [tableStreamNext $stream];set rows {};set sourceRows {};set columns [dict get $chunk columns]
        set values [dict get $chunk values];set ids [dict get $chunk selected_variable_ids]
        for {set i 0} {$i<[dict get $chunk row_count]} {incr i} {
            lappend rows [lmap id [lrange $ids 0 1] {lindex [dict get $values $id] $i}]
            lappend sourceRows [expr {$lineage eq "" ? [dict get $request start]+$start+$i : [lindex [dict get $values $lineage] $i]}]
        }
        return [dict create source_id [dict get $record source_id] start $start count [llength $rows] row_count [dict get $record row_count] source_rows $sourceRows columns [lmap c [lrange $columns 0 1] {dict remove $c values binary_block}] rows $rows]
    } finally {curveSourceCloseStream $token $stream}
}
proc ::GX::curveSourceClose {token} {
    variable ::GX::CurveSource::records
    if {![info exists records($token)]} {error "Unknown or closed Curve Source token"}
    if {[info exists ::GX::CurveSource::jobs]} {
        dict for {job state} $::GX::CurveSource::jobs {if {[dict get $state source] eq $token} {error "Cancel the active Curve Source job before closing its source"}}
    }
    set record $records($token)
    foreach stream [dict get $record streams] {tableStreamClose $stream}
    if {[dict get $record view] ne ""} {datasetTransformCloseView [dict get $record view]}
    unset records($token)
}
proc ::GX::curveSourcePointMaskValidate {mask} {
    _curveSourceValidatePointMask $mask
    return validated
}
proc ::GX::_curveSourceValidatePointMask {mask} {
    if {$mask eq {}} return
    foreach field [dict keys $mask] {if {$field ni {api_id base_selected regions manual_rows}} {error "Unknown exact point selection field '$field'"}}
    foreach field {api_id base_selected regions manual_rows} {if {![dict exists $mask $field]} {error "Exact point selection needs $field"}}
    if {[dict get $mask api_id] ne "CURVE_SOURCE_POINT_MASK_v1"} {error "Unsupported exact point selection descriptor"}
    uiFieldNormalize [dict create type boolean] [dict get $mask base_selected]
    if {[llength [dict get $mask regions]]>65536||[dict size [dict get $mask manual_rows]]>65536} {error "Exact selection descriptor exceeds its bounded limit"}
    foreach region [dict get $mask regions] {
        if {[dict get $region mode] ni {add subtract}} {error "Selection region mode must be add or subtract"}
        set bounds [dict get $region bounds]
        if {[llength $bounds]!=4} {error "Selection region needs four XY bounds"}
        foreach value $bounds {uiFieldNormalize [dict create type number] $value}
        lassign $bounds x0 y0 x1 y1
        if {$x0>$x1||$y0>$y1} {error "Selection region bounds are reversed"}
    }
    dict for {row mode} [dict get $mask manual_rows] {
        if {![string is entier -strict $row]||$row<0||$row>18446744073709551615||$mode ni {1 2}} {error "Invalid exact selection row override"}
    }
}
proc ::GX::_curveSourceMaskPacked {packed mask} {
    # At most one bounded stream chunk enters Tcl. Original row IDs remain
    # integer values; predicates never operate on display/LOD coordinates.
    binary scan [dict get $packed xy] q* coordinates
    binary scan [dict get $packed source_rows] wu* rows
    set parameters {};set parameterBytes "";set position 0
    if {[dict exists $packed parameter]} {binary scan [dict get $packed parameter] q* parameters}
    set companionBytes {};if {[dict exists $packed companions]} {dict for {role bytes} [dict get $packed companions] {dict set companionBytes $role ""}}
    set xy "";set mapping "";set excluded "";set count 0
    set overrides [dict get $mask manual_rows];set regions [dict get $mask regions]
    foreach {x y} $coordinates row $rows {
        set selected [dict get $mask base_selected]
        foreach region $regions {
            lassign [dict get $region bounds] x0 y0 x1 y1
            if {$x>=$x0&&$x<=$x1&&$y>=$y0&&$y<=$y1} {set selected [expr {[dict get $region mode] eq "add"}]}
        }
        if {[dict exists $overrides $row]} {set selected [expr {[dict get $overrides $row]==1}]}
        if {$selected} {
            append xy [binary format q2 [list $x $y]];append mapping [binary format w $row];incr count
            if {[dict exists $packed parameter]} {append parameterBytes [binary format q [lindex $parameters $position]]}
            dict for {role bytes} $companionBytes {dict append companionBytes $role [string range [dict get $packed companions $role] [expr {8*$position}] [expr {8*$position+7}]]}
        } else {append excluded [binary format w $row]}
        incr position
    }
    set result [dict create xy $xy source_rows $mapping unselected_source_rows $excluded row_count $count]
    if {[dict exists $packed parameter]} {dict set result parameter $parameterBytes}
    if {[dict size $companionBytes]} {dict set result companions $companionBytes}
    return $result
}
proc ::GX::curveSourceWithNumericInput {token consumer {pointMask {}} {progress ""} {parameterVariable ""} {companionVariables {}}} {
    # Host adapter API: the consumer sees only newly owned temporary Numeric
    # input, never a Dataset/provider path. The files exist for this call only.
    set record [_curveSourceRequire $token];set request [dict get $record request]
    _curveSourceValidatePointMask $pointMask
    if {[dict size $companionVariables]>7} {error {Numeric input supports at most seven named companion variables}}
    dict for {role variable} $companionVariables {
        datasetPublicationV2ValidateId variable $role;datasetPublicationV2ValidateId variable $variable
        if {$role eq "__parameter"} {error {Reserved numeric companion role}}
    }
    native2DEnsure
    if {"numeric_row_audit" ni [dict get [::GX::Native2D::core api_info] capabilities]} {error {The loaded Native2D adapter lacks exact preprocessing row audit; restart with the matching CORE adapter}}
    if {[dict size $companionVariables]&&"numeric_companions" ni [dict get [::GX::Native2D::core api_info] capabilities]} {error {The loaded Native2D adapter lacks exact companion-column transport; restart with the matching CORE adapter}}
    set xy [file tempfile xyPath];set mapping [file tempfile rowPath]
    set gaps [file tempfile gapPath];fconfigure $gaps -translation binary -encoding binary
    fconfigure $xy -translation binary -encoding binary
    fconfigure $mapping -translation binary -encoding binary
    set selectedXY "";set selectedRows "";set selectedXYPath "";set selectedRowsPath ""
    set parameter "";set parameterPath "";set selectedParameter "";set selectedParameterPath ""
    set companionChannels {};set companionPaths {};set selectedCompanionChannels {};set selectedCompanionPaths {};set companionDescriptors {}
    set auditChannels {};set auditPaths {};set stream "";set scene [::GX::Native2D::core scene]
    try {
        foreach field {input_source_rows nonfinite_source_rows unselected_source_rows} {
            set channel [file tempfile path];fconfigure $channel -translation binary -encoding binary
            dict set auditChannels $field $channel;dict set auditPaths ${field}_file $path
        }
        if {$pointMask ne {}} {
            set selectedXY [file tempfile selectedXYPath];set selectedRows [file tempfile selectedRowsPath]
            fconfigure $selectedXY -translation binary -encoding binary;fconfigure $selectedRows -translation binary -encoding binary
        }
        if {$parameterVariable ne ""} {
            datasetPublicationV2ValidateId variable $parameterVariable
            set parameter [file tempfile parameterPath];fconfigure $parameter -translation binary -encoding binary
            if {$pointMask ne {}} {set selectedParameter [file tempfile selectedParameterPath];fconfigure $selectedParameter -translation binary -encoding binary}
        }
        dict for {role variable} $companionVariables {
            set channel [file tempfile path];fconfigure $channel -translation binary -encoding binary
            dict set companionChannels $role $channel;dict set companionPaths $role $path
            if {$pointMask ne {}} {set channel [file tempfile path];fconfigure $channel -translation binary -encoding binary;dict set selectedCompanionChannels $role $channel;dict set selectedCompanionPaths $role $path}
        }
        set ids [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
        set lineage [dict get $record lineage_variable]
        if {$lineage ne ""} {lappend ids $lineage}
        if {$parameterVariable ne ""&&$parameterVariable ni $ids} {lappend ids $parameterVariable}
        dict for {role variable} $companionVariables {if {$variable ni $ids} {lappend ids $variable}}
        set stream [curveSourceOpenStream $token $ids 65536]
        set streamVariables [dict get [tableStreamMetadata $stream] variables]
        dict for {role variable} $companionVariables {
            foreach descriptor $streamVariables {if {[dict get $descriptor variable_id] eq $variable} {dict set companionDescriptors $role [dict create variable_id $variable variable_descriptor $descriptor format float64_le file [dict get $companionPaths $role]];break}}
            if {![dict exists $companionDescriptors $role]} {error "Exact stream lacks companion variable '$variable'"}
        }
        set count 0;set total 0;set trainingCount 0;set previousFinite 1
        while {1} {
            set chunk [tableStreamNext $stream];set columns [dict get $chunk columns]
            set sourceRows [expr {$lineage eq "" ? "" : [_curveSourceNativeColumn [lindex $columns 2]]}]
            set parameterArgument {}
            if {$parameterVariable ne ""} {set parameterArgument [list [_curveSourceNativeColumn [lindex $columns [lsearch -exact $ids $parameterVariable]]]]}
            if {[dict size $companionVariables]} {
                set companionColumns {}
                dict for {role variable} $companionVariables {dict set companionColumns $role [_curveSourceNativeColumn [lindex $columns [lsearch -exact $ids $variable]]]}
                if {$parameterVariable ne ""} {dict set companionColumns __parameter [lindex $parameterArgument 0]}
                set packed [::GX::Native2D::core numeric_pack_columns $scene [_curveSourceNativeColumn [lindex $columns 0]] [_curveSourceNativeColumn [lindex $columns 1]] $sourceRows [expr {[dict get $request start]+$total}] $companionColumns]
                if {$parameterVariable ne ""} {
                    set bytes [dict get $packed companions __parameter];binary scan $bytes q* values
                    foreach value $values {if {![string is double -strict $value]||[catch {expr {abs($value)<Inf}} finite]||!$finite} {error {Numeric parameters must be finite for every finite XY pair}}}
                    dict set packed parameter $bytes;dict unset packed companions __parameter
                }
            } else {set packed [::GX::Native2D::core numeric_pack $scene [_curveSourceNativeColumn [lindex $columns 0]] [_curveSourceNativeColumn [lindex $columns 1]] $sourceRows [expr {[dict get $request start]+$total}] {*}$parameterArgument]}
            puts -nonewline $xy [dict get $packed xy];puts -nonewline $mapping [dict get $packed source_rows]
            foreach field {input_source_rows nonfinite_source_rows} {puts -nonewline [dict get $auditChannels $field] [dict get $packed $field]}
            if {$parameter ne ""} {puts -nonewline $parameter [dict get $packed parameter]}
            dict for {role channel} $companionChannels {puts -nonewline $channel [dict get $packed companions $role]}
            set gapBytes [dict get $packed break_before]
            if {[dict get $packed row_count]>0&&!$previousFinite} {set gapBytes [string replace $gapBytes 0 0 [binary format c 1]]}
            puts -nonewline $gaps $gapBytes
            if {[dict get $chunk row_count]} {set previousFinite [dict get $packed ends_finite]}
            if {$pointMask ne {}} {
                set chosen [_curveSourceMaskPacked $packed $pointMask]
                puts -nonewline $selectedXY [dict get $chosen xy];puts -nonewline $selectedRows [dict get $chosen source_rows]
                puts -nonewline [dict get $auditChannels unselected_source_rows] [dict get $chosen unselected_source_rows]
                incr trainingCount [dict get $chosen row_count]
                if {$selectedParameter ne ""} {puts -nonewline $selectedParameter [dict get $chosen parameter]}
                dict for {role channel} $selectedCompanionChannels {puts -nonewline $channel [dict get $chosen companions $role]}
            }
            incr count [dict get $packed row_count];incr total [dict get $chunk row_count]
            if {$progress ne ""} {
                curveSourceCooperativeBoundary $progress [dict create stage numeric_input completed_rows $total total_rows [dict get $record row_count]]
                _curveSourceRequire $token
            }
            if {[dict get $chunk eof]} break
        }
        close $xy;set xy "";close $mapping;set mapping "";close $gaps;set gaps ""
        if {$parameter ne ""} {close $parameter;set parameter ""}
        dict for {role channel} $companionChannels {close $channel};set companionChannels {}
        dict for {role channel} $auditChannels {close $channel};set auditChannels {}
        set diagnostics [tableStreamDiagnostics $stream]
        curveSourceCloseStream $token $stream;set stream ""
        _curveSourceRequire $token
        if {$count<2} {error "Numeric input needs at least two finite XY pairs"}
        set input [dict create api_id CURVE_SOURCE_NUMERIC_INPUT_v1 source_id [dict get $record source_id] row_count $count exact_rows $total finite_policy omit_nonfinite_pairs xy_format interleaved_float64_le source_rows_format uint64_le xy_file $xyPath source_rows_file $rowPath break_before_file $gapPath break_before_format uint8 diagnostics $diagnostics]
        set sourceDescriptor [curveSourceDescribe $token]
        set originalCount [dict get $record metadata row_count]
        if {[dict get $record lineage_variable] ne ""} {
            # Read canonical metadata only; never repeat the filtered data pass.
            set stream [tableStreamOpenDataset [dict get $record session] [dict get $request dataset_id] [list [dict get $request x_variable_id]] 1]
            try {set originalCount [dict get [tableStreamMetadata $stream] row_count]} finally {tableStreamClose $stream;set stream ""}
        }
        set selectedCount [expr {$pointMask eq {}?$count:$trainingCount}]
        dict set input preprocessing [dict create schema gxtxt.curve_source_preprocessing.v1 source $sourceDescriptor original_count $originalCount original_count_status [expr {$originalCount<0?"unavailable":"value"}] filtered_count $total finite_count $count selected_count $selectedCount nonfinite_count [expr {$total-$count}] selection_excluded_count [expr {$count-$selectedCount}] finite_policy omit_nonfinite_pairs duplicate_policy preserve_observations order_policy preserve_stream_order source_request $request row_identity_kind [dict get $sourceDescriptor row_identity_kind] selection_descriptor $pointMask]
        set input [dict merge $input $auditPaths]
        if {$parameterVariable ne ""} {dict set input parameter_file $parameterPath;dict set input parameter_format float64_le;dict set input parameter_variable_id $parameterVariable}
        if {[dict size $companionDescriptors]} {dict set input companion_columns $companionDescriptors}
        if {$pointMask ne {}} {
            close $selectedXY;set selectedXY "";close $selectedRows;set selectedRows ""
            if {$trainingCount<2} {error "Select at least two finite exact source points"}
            # The full-source gap mask cannot describe the selected subset.
            # Training represents independent samples, with its own row map.
            dict set input training [dict replace [dict remove $input break_before_file break_before_format] xy_file $selectedXYPath source_rows_file $selectedRowsPath row_count $trainingCount selection_descriptor $pointMask]
            if {$selectedParameter ne ""} {close $selectedParameter;set selectedParameter "";dict set input training parameter_file $selectedParameterPath}
            dict for {role channel} $selectedCompanionChannels {close $channel;dict set input training companion_columns $role file [dict get $selectedCompanionPaths $role]};set selectedCompanionChannels {}
        }
        return [uplevel #0 [list {*}$consumer $input]]
    } finally {
        if {$xy ne ""} {close $xy}
        if {$mapping ne ""} {close $mapping}
        if {$gaps ne ""} {close $gaps}
        if {$selectedXY ne ""} {close $selectedXY}
        if {$selectedRows ne ""} {close $selectedRows}
        if {$parameter ne ""} {close $parameter}
        if {$selectedParameter ne ""} {close $selectedParameter}
        dict for {role channel} $companionChannels {close $channel}
        dict for {role channel} $selectedCompanionChannels {close $channel}
        dict for {role channel} $auditChannels {close $channel}
        if {$stream ne ""} {curveSourceCloseStream $token $stream}
        ::GX::Native2D::core destroy $scene
        file delete -force -- $xyPath $rowPath $gapPath
        foreach path [list $selectedXYPath $selectedRowsPath $parameterPath $selectedParameterPath] {if {$path ne ""} {file delete -force -- $path}}
        foreach path [concat [dict values $companionPaths] [dict values $selectedCompanionPaths]] {file delete -force -- $path}
        foreach path [dict values $auditPaths] {file delete -force -- $path}
    }
}

source [file join [file dirname [info script]] curve_source_continuity_v1.tcl]
source [file join [file dirname [info script]] curve_source_display_cache.tcl]

# One canonical projection, with truthful per-group snapshots issued by the
# Curve Source owner. Unsupported view/Selection modes keep their existing
# single-source route; they are never silently approximated by this operation.
proc ::GX::curveSourceDisplayBatch {session request {options {}} {progress {}}} {
    set session [file normalize $session]
    if {$session ne [file normalize [sessionInspectionCurrentSession]]} {error {Curve Source batch belongs to another active Session}}
    foreach key [dict keys $request] {
        if {$key ni {dataset_id x_variable_id y_variable_id filters start count display_budget order_variable_id}} {error "Unsupported Curve Source batch field '$key'; use the existing explicit source operation"}
    }
    foreach key {dataset_id x_variable_id y_variable_id} {
        if {![dict exists $request $key]} {error "Curve Source batch needs $key"}
        datasetPublicationV2ValidateId [expr {$key eq "dataset_id"?"dataset":"variable"}] [dict get $request $key]
    }
    foreach key [dict keys $options] {if {$key ni {group_variable_ids max_series total_display_points}} {error "Unknown Curve Source batch option '$key'"}}
    foreach {key default minimum maximum} {start 0 0 2000000 count -1 -1 2000000 display_budget 4096 6 4096} {
        set value [datasetPublicationV2DictDefault $request $key $default]
        if {![string is entier -strict $value] || $value<$minimum || $value>$maximum} {error "Invalid Curve Source batch $key"}
        dict set request $key $value
    }
    set id [dict get $request dataset_id]
    set lifetime [interactiveDocumentSessionToken];set identity [_curveSourceIdentity $session $id]
    set x [dict get $request x_variable_id];set y [dict get $request y_variable_id]
    if {$x eq $y} {error {Curve Source X/Y Variable IDs must be distinct}}
    foreach vid [list $x $y] {
        set v [datasetVariableV3ById $id $vid]
        if {![dict get $v enabled] || [dict get $v rank]!=1 || [dict get $v dtype] eq "string"} {error {Curve Source batch needs enabled rank-one numeric X/Y Variables}}
    }
    set filters [graphSeriesNormalizeFilters $id [datasetPublicationV2DictDefault $request filters {}]]
    dict set request filters $filters
    set groupIds [datasetPublicationV2DictDefault $options group_variable_ids {}]
    if {[llength $groupIds]>16 || [llength [lsort -unique $groupIds]]!=[llength $groupIds]} {error {Curve Source batch needs at most16 distinct grouping Variables}}
    set specs {};set projection [list $x $y];set scalarIds {}
    foreach vid $groupIds {
        datasetPublicationV2ValidateId variable $vid
        set v [datasetVariableV3ById $id $vid]
        if {![dict get $v enabled] || [dict get $v rank]!=1} {error {Grouping requires enabled rank-one Variables}}
        lappend specs [dict create variable_id $vid dtype [dict get $v dtype]]
        if {$vid ni $projection} {lappend projection $vid}
        if {$vid ni $scalarIds} {lappend scalarIds $vid}
    }
    foreach filter $filters {
        set vid [dict get $filter filter_variable_id]
        if {$vid ni $projection} {lappend projection $vid}
        if {$vid ni $scalarIds} {lappend scalarIds $vid}
    }
    set order {};set ordering [datasetPublicationV2DictDefault $request order_variable_id {}]
    if {$ordering ne {}} {
        set v [datasetVariableV3ById $id $ordering]
        if {![dict get $v enabled] || [dict get $v rank]!=1 || [dict get $v dtype] eq "string"} {error {Native Curve Source batch currently supports rank-one numeric ordering; use the existing source operation for other keys}}
        set order [dict create variable_id $ordering dtype [dict get $v dtype]]
        if {$ordering ni $projection} {lappend projection $ordering}
        if {$ordering ni $scalarIds} {lappend scalarIds $ordering}
    }
    set continuity {};set metadata [datasetMetadataRead $session $id]
    set policy [datasetPublicationV2DictDefault $metadata curve_source.continuity_policy {}]
    if {$policy ne {}} {
        if {$policy ne "source_row_adjacency"} {error {Unsupported declared Curve Source continuity policy}}
        set vid [dict get $metadata curve_source.continuity_variable_id]
        set v [datasetVariableV3ById $id $vid]
        if {[dict get $v rank]!=1 || [dict get $v dtype] ni {int8 uint8 int16 uint16 int32 uint32 int64 uint64}} {error {Scientific continuity requires a rank-one integer row-identity Variable}}
        set continuity [dict create variable_id $vid dtype [dict get $v dtype]]
        if {$vid ni $projection} {lappend projection $vid}
        if {$vid ni $scalarIds} {lappend scalarIds $vid}
    }
    set config [dict create x_variable_id $x y_variable_id $y groups $specs filters $filters order $order continuity $continuity start [dict get $request start] count [dict get $request count] display_budget [dict get $request display_budget] max_series [datasetPublicationV2DictDefault $options max_series 512] total_display_points [datasetPublicationV2DictDefault $options total_display_points 100000]]
    native2DEnsure
    if {![llength [info commands ::gx::native2d::_preview_batch]]} {error {The shared Native2D adapter lacks Curve Source batch support}}
    set batchContext [_curveSourceBatchContext $session $id $metadata]
    if {[interactiveDocumentSessionToken] ne $lifetime || [_curveSourceIdentity $session $id] ne $identity || [_curveSourceBatchContext $session $id] ne $batchContext} {error {Curve Source batch changed during request admission}}
    set stream {};set native {};set position 0
    try {
        set native [::gx::native2d::_preview_batch begin $config]
        # Integer scalar identities stay tagged/exact when the native adapter
        # decodes canonical typed blocks; CSV retains its existing lexemes.
        set stream [tableStreamOpenDataset $session $id $projection 4096 {numeric_transport auto}]
        while 1 {
            set chunk [tableStreamNext $stream];set columns {}
            foreach column [dict get $chunk columns] vid $projection {dict set columns $vid [_curveSourceNativeColumn $column]}
            ::gx::native2d::_preview_batch push $native $columns
            incr position [dict get $chunk row_count]
            if {$progress ne {}} {
                curveSourceCooperativeBoundary $progress [dict create stage batch_display completed_rows $position total_rows [dict get [tableStreamMetadata $stream] row_count]]
                if {[interactiveDocumentSessionToken] ne $lifetime || [_curveSourceIdentity $session $id] ne $identity} {error {Curve Source batch cancelled by source or Session change}}
            }
            if {[dict get $chunk eof]} break
        }
        set diagnostics [tableStreamDiagnostics $stream]
        set closing $stream;set stream {};tableStreamClose $closing
        set nativeSeries [::gx::native2d::_preview_batch finish $native]
        dict set diagnostics native_batch [::gx::native2d::_preview_batch inspect $native]
        dict set diagnostics canonical_streams 1
        set output {}
        foreach item $nativeSeries {
            set selectedFilters $filters
            foreach vid $groupIds value [dict get $item group_key] {lappend selectedFilters [dict create filter_variable_id $vid predicate exact_equal value $value]}
            set selectedRequest [dict replace $request filters $selectedFilters count [dict get $item row_count] display_budget [dict get $item display_budget]]
            set sourceId "curve-source:[datasetStorageSha256Text $session [list [list $identity] [dict remove $selectedRequest display_budget] $batchContext]]"
            set descriptor [dict create api_id CURVE_SOURCE_API_v1 api_version 1 source_id $sourceId source_kind dataset_batch row_identity_kind dataset_row batch_context $batchContext request $selectedRequest row_count [dict get $item row_count] variables [list [datasetVariableV3ById $id $x] [datasetVariableV3ById $id $y]] source_identities [list $identity] display_budget [dict get $item display_budget] display_is_scientific_data 0]
            set display [dict merge [dict remove $item group_key display_budget] [dict create source_id $sourceId reduced [expr {[dict get $item display_rows]<[dict get $item finite_rows]}] display_is_scientific_data 0 diagnostics $diagnostics]]
            if {$policy ne {}} {dict set display continuity_policy $policy}
            lappend output [dict create group_key [dict get $item group_key] filters $selectedFilters source_descriptor $descriptor display $display]
        }
        if {[interactiveDocumentSessionToken] ne $lifetime || [_curveSourceIdentity $session $id] ne $identity || [_curveSourceBatchContext $session $id] ne $batchContext} {error {Curve Source batch source, Session or continuity changed before commit}}
        return [dict create api_id CURVE_SOURCE_API_v1 api_version 1 operation batch_display source_identities [list $identity] series $output diagnostics $diagnostics]
    } finally {
        try {if {$stream ne {}} {tableStreamClose $stream}} finally {
            if {$native ne {}} {::gx::native2d::_preview_batch destroy $native}
        }
    }
}
