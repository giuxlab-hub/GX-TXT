# SPDX-License-Identifier: GPL-3.0-or-later
# Exact copy exchange using the established geometry.sketch language. Owners
# supply read-only model snapshots; CORE stages a new scene before any commit.
namespace eval ::GX::GeometryExchange {variable serial 0;variable busy 0;variable readers {}}
proc ::GX::geometryExchangeApiInfo {} {
    return {api_id GEOMETRY_EXCHANGE_API_v1 api_version 1 format gxtxt.geometry.exchange format_version 1 transport {inline_bounded document_resource} session_scope same_session max_bytes 67108864 max_document_bytes 33554432 max_objects 16384 dependency_policies {strict closure} exact_geometry 1 implicit_dataset_publication 0 import_scene_policy new_target_owned_scene owner_payload_adapter 1 operations {info source_register export inspect import restore export_resource import_resource} cancellation trusted_local_callback}
}
proc ::GX::_geometryExchangeBounds {sketch} {
    if {[string bytelength $sketch]>67108864 || [dict size [dict get $sketch objects]]>16384 || [dict size [dict get $sketch constraints]]>4096 || [dict size [dict get $sketch parameters]]>16384} {error {Geometry exchange budget exceeded}}
    return [sketchDatasetValidate $sketch]
}
proc ::GX::_geometryExchangeDocumentRead {document} {
    set session [_interactiveDocumentRequireSession]
    set registry [_interactiveDocumentRegistryRead $session]
    if {![dict exists $registry $document]} {error {Exchange document is unavailable}}
    set path [_interactiveDocumentPayloadPath $session [dict get $registry $document]]
    if {[file size $path]>33554432} {error {Bounded exchange requires document metadata below 32 MiB}}
    return [interactiveDocumentRead $document]
}
proc ::GX::_geometryExchangeOwner {document} {
    set owner [_geometryExchangeDocumentRead $document]
    if {[info exists ::GX::DatasetPrivate::activeContext] && $::GX::DatasetPrivate::activeContext ne {} && [dict get $::GX::DatasetPrivate::activeContext module_id] ne [dict get $owner module_id]} {error {Geometry exchange write requires the destination document owner}}
    return $owner
}
proc ::GX::geometryExchangeSourceRegister {module provider callback} {
    variable ::GX::GeometryExchange::readers
    _interactiveDocumentValidateOwner $module $provider
    if {$::GX::DatasetPrivate::activeContext ne {} && [dict get $::GX::DatasetPrivate::activeContext module_id] ne $module} {error {Source adapter registration requires its module owner}}
    if {![llength $callback] || ![llength [info commands [lindex $callback 0]]]} {error {Source adapter requires a registered local command prefix}}
    dict set readers [list $module $provider] $callback
}
proc ::GX::_geometryExchangeSourceSnapshot {owner} {
    set payload [dict get $owner payload]
    if {[dict exists $payload schema] && [dict get $payload schema] eq "gxtxt.geometry.sketch"} {return [dict create sketch $payload groups {}]}
    set key [list [dict get $owner module_id] [dict get $owner provider_id]]
    if {[dict exists $::GX::GeometryExchange::readers $key]} {return [uplevel #0 [list {*}[dict get $::GX::GeometryExchange::readers $key] $owner]]}
    if {[dict get $owner format] ne "gxtxt.curve_workbench.workspace"} {error {Register an owner source adapter for this document format}}
    set objects {}
    dict for {id r} [dict get $payload curves] {
        if {![dict exists $r sketch_definition]} {error {This bounded adapter requires saved retained whole primitives; Dataset-backed/bulk curves need an owner adapter}}
        set unit [datasetPublicationV2DictDefault $r working_unit {}]
        dict set objects $id [dict create name [dict get $r name] definition [dict get $r sketch_definition] units [list $unit $unit] metadata [dict merge [datasetPublicationV2DictDefault $r sketch_metadata {}] [datasetPublicationV2DictDefault $r sketch_attributes {}]] provenance [datasetPublicationV2DictDefault $r sketch_provenance {}]]
    }
    set cad [dict get $payload cad_workspace]
    set parameters [datasetPublicationV2DictDefault [dict get $payload workspace_metadata] parameters {}]
    set module [dict get $owner module_id]
    if {[dict exists $::GX::Parameters::declarations $module]} {set parameters [dict merge [dict get $::GX::Parameters::declarations $module] $parameters]}
    set substitutions {}
    dict for {name r} [parameterSessionList] {
        set local gx_session_$name;while {[dict exists $parameters $local]} {append local _}
        dict set substitutions session.$name $local
        dict set parameters $local [dict create formula [dict get $r value] description "Captured Session parameter $name; original expression: [dict get $r formula]"]
    }
    dict for {name r} $parameters {dict set parameters $name formula [sketchDatasetParameterExpression [dict get $r formula] $substitutions]}
    set constraints [dict get $cad constraints]
    dict for {cid r} $constraints {if {[dict exists $r expression]} {dict set constraints $cid expression [sketchDatasetParameterExpression [dict get $r expression] $substitutions]}}
    set groups {};dict for {g r} [dict get $cad groups] {dict set groups $g [dict get $r members]}
    return [dict create sketch [dict create schema gxtxt.geometry.sketch version 1.0 objects $objects constraints $constraints parameters $parameters provenance [dict create producer $module source_document [dict get $owner id]]] groups $groups]
}
proc ::GX::_geometryExchangeDefinitionEqual {a b} {
    set scene [::GX::Native2D::core scene]
    try {
        set ai [::GX::Native2D::core sketch_create $scene $a 2];set bi [::GX::Native2D::core sketch_create $scene $b 2]
        return [expr {[::GX::Native2D::core sketch_definition $scene $ai] eq [::GX::Native2D::core sketch_definition $scene $bi]}]
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::geometryExchangeExport {document sketch selected {options {}}} {
    foreach k [dict keys $options] {if {$k ni {dependencies groups frame}} {error "Unknown exchange export option $k"}}
    set owner [_geometryExchangeDocumentRead $document]
    set capture [_geometryExchangeSourceSnapshot $owner]
    if {[_geometryExchangeDocumentRead $document] ne $owner} {error {Source changed during capture}}
    set authoritative [dict get $capture sketch]
    _geometryExchangeBounds $authoritative
    if {$sketch ne {}} {
        # A caller's existing canonical exporter may add inert metadata, but
        # cannot omit a dependency or replace a saved scientific definition.
        if {[lsort [dict keys [dict get $sketch objects]]] ne [lsort [dict keys [dict get $authoritative objects]]]} {error {Snapshot must contain the saved whole-object inventory}}
        dict for {id r} [dict get $authoritative objects] {
            if {![dict exists $sketch objects $id] || ![_geometryExchangeDefinitionEqual [dict get $r definition] [dict get $sketch objects $id definition]] || [dict get $r units] ne [dict get $sketch objects $id units]} {error "Unsaved or mismatched source definition $id"}
        }
        foreach collection {constraints parameters} {
            set supplied [dict get $sketch $collection];set saved [dict get $authoritative $collection]
            if {[lsort [dict keys $supplied]] ne [lsort [dict keys $saved]]} {error "Snapshot omits or adds saved $collection; unsupported dependency/topology capture"}
            dict for {key record} $saved {
                if {$collection eq "constraints"} {
                    foreach field {definition expression} {
                        if {[datasetPublicationV2DictDefault $record $field {}] ne [datasetPublicationV2DictDefault [dict get $supplied $key] $field {}]} {error "Unsaved or unsupported constraint $key $field"}
                    }
                } else {
                    foreach field {formula unit type min max editable} {
                        if {[datasetPublicationV2DictDefault $record $field {}] ne [datasetPublicationV2DictDefault [dict get $supplied $key] $field {}]} {error "Unsaved parameter $key $field"}
                    }
                }
            }
        }
    }
    # The saved owner snapshot supplies metadata/provenance as well as controls.
    set sketch $authoritative
    _geometryExchangeBounds $sketch
    set policy [datasetPublicationV2DictDefault $options dependencies strict]
    if {$policy ni {strict closure}} {error {Dependency policy must be strict or closure}}
    set selected [lsort -unique $selected]
    if {![llength $selected] || [llength $selected]>16384} {error {Select 1..16384 whole exact objects}}
    foreach id $selected {if {![dict exists $sketch objects $id]} {error "Unknown selected geometry $id"}}
    set groups [dict get $capture groups]
    if {[dict exists $options groups]} {
        dict for {g members} [dict get $capture groups] {if {![dict exists $options groups $g] || [dict get $options groups $g] ne $members} {error {Saved source groups cannot be omitted or changed}}}
        set groups [dict get $options groups]
    }
    if {[dict size $groups]>16384} {error {Group budget exceeded}}
    # Groups are sets of whole object IDs; nested provider-specific groups are
    # deliberately rejected rather than silently flattening their semantics.
    dict for {g members} $groups {foreach id $members {if {![dict exists $sketch objects $id]} {error "Group $g references unknown object $id"}}}
    set changed 1
    while {$changed} {
        set changed 0
        set sets [dict values $groups]
        dict for {cid record} [dict get $sketch constraints] {
            set refs {};set spec [dict get $record definition]
            foreach field {a b axis} {if {[dict exists $spec $field] && [dict get $spec $field] ne {}} {lappend refs [dict get $spec $field]}}
            lappend sets $refs
        }
        foreach refs $sets {
            set inside 0;set outside {}
            foreach id $refs {if {$id in $selected} {set inside 1} else {lappend outside $id}}
            if {$inside && $outside ne {}} {
                if {$policy eq "strict"} {error "Geometry dependencies cross selection: $outside"}
                foreach id $outside {if {![dict exists $sketch objects $id]} {error "Unresolved external geometry $id"};lappend selected $id;set changed 1}
            }
        }
    }
    set objects {};set constraints {};set keptGroups {}
    foreach id $selected {
        set r [dict get $sketch objects $id]
        set units [dict get $r units]
        if {[llength $units]!=2 || [lindex $units 0] eq {} || [lindex $units 0] ne [lindex $units 1]} {error "Geometry $id requires two equal declared coordinate units"}
        unitRegistryConvertCoordinates [lindex $units 0] [lindex $units 0] {0 1}
        dict set objects $id $r
    }
    dict for {cid record} [dict get $sketch constraints] {
        set spec [dict get $record definition]
        if {[dict get $spec a] in $selected} {dict set constraints $cid $record}
    }
    dict for {g members} $groups {if {[llength $members] && [lindex $members 0] in $selected} {dict set keptGroups $g $members}}
    set subset [dict replace $sketch objects $objects constraints $constraints]
    _geometryExchangeBounds $subset
    set frame [datasetPublicationV2DictDefault $options frame [dict create name source_world orientation xy_right_handed]]
    foreach key [dict keys $frame] {if {$key ni {name orientation calibration_source}} {error "Unknown scientific frame field $key"}}
    set body [dict create api_id GEOMETRY_EXCHANGE_API_v1 api_version 1 format gxtxt.geometry.exchange format_version 1 session_token [interactiveDocumentSessionToken] source [dict remove $owner payload] sketch $subset groups $keptGroups frame $frame dependency_policy $policy exactness retained_definitions copy 1]
    return [dict merge $body [dict create sha256 [datasetStorageSha256Text [_interactiveDocumentRequireSession] $body]]]
}
proc ::GX::geometryExchangeInspect {descriptor} {
    if {[string bytelength $descriptor]>67108864} {error {Geometry descriptor exceeds 64 MiB}}
    foreach k [dict keys $descriptor] {if {$k ni {api_id api_version format format_version session_token source sketch groups frame dependency_policy exactness copy sha256}} {error "Unknown descriptor field $k"}}
    foreach {k v} {api_id GEOMETRY_EXCHANGE_API_v1 api_version 1 format gxtxt.geometry.exchange format_version 1 exactness retained_definitions copy 1} {if {[dict get $descriptor $k] ne $v} {error "Unsupported exchange $k"}}
    if {[dict get $descriptor session_token] ne [interactiveDocumentSessionToken]} {error {Foreign or expired exchange Session}}
    if {[datasetStorageSha256Text [_interactiveDocumentRequireSession] [dict remove $descriptor sha256]] ne [dict get $descriptor sha256]} {error {Geometry descriptor integrity mismatch}}
    set old [dict get $descriptor source];set source [_geometryExchangeDocumentRead [dict get $old id]]
    foreach k {id module_id provider_id generation revision sha256} {if {[dict get $source $k] ne [dict get $old $k]} {error "Stale source document $k"}}
    _geometryExchangeBounds [dict get $descriptor sketch]
    # Recheck the source scientific snapshot (including Session parameter
    # dependencies) at inspection/import, beyond document revision alone.
    set capture [_geometryExchangeSourceSnapshot $source]
    dict for {id r} [dict get $descriptor sketch objects] {
        if {![dict exists $capture sketch objects $id] || ![_geometryExchangeDefinitionEqual [dict get $r definition] [dict get $capture sketch objects $id definition]]} {error {Source scientific definition changed}}
    }
    if {[dict get $capture sketch parameters] ne [dict get $descriptor sketch parameters]} {error {Source parameter dependencies changed}}
    dict for {g ids} [dict get $descriptor groups] {foreach id $ids {if {![dict exists $descriptor sketch objects $id]} {error {Unresolved exchange group}}}}
    return [dict create source $old object_count [dict size [dict get $descriptor sketch objects]] constraint_count [dict size [dict get $descriptor sketch constraints]] exactness retained_definitions frame [dict get $descriptor frame] portability same_session]
}
proc ::GX::_geometryExchangeIdentity {scene handle record} {
    native2DGeometryCall $scene identity [dict create object_token $handle name [dict get $record name]]
    dict for {key value} [datasetPublicationV2DictDefault $record metadata {}] {
        if {[string first . $key]>=0 && $key ni {gx.exchange_local_id gx.exchange_lineage}} {
            native2DGeometryCall $scene identity [dict create object_token $handle key $key value $value]
        }
    }
    if {[dict exists $record provenance exchange_lineage]} {
        native2DGeometryCall $scene identity [dict create object_token $handle key gx.exchange_lineage value [dict get $record provenance exchange_lineage]]
    }
}
proc ::GX::_geometryExchangeCancelled {options} {
    if {[dict exists $options cancel_command] && [uplevel #0 [list {*}[dict get $options cancel_command]]]} {return -code error -errorcode {GX GEOMETRY EXCHANGE CANCELLED} {Geometry copy cancelled before commit}}
}
proc ::GX::geometryExchangeImport {document descriptor {options {}}} {
    variable ::GX::GeometryExchange::serial;variable ::GX::GeometryExchange::busy
    if {$busy} {error {Geometry import is already committing}}
    foreach k [dict keys $options] {if {$k ni {target_unit payload_command transform cancel_command}} {error "Unknown exchange import option $k"}}
    geometryExchangeInspect $descriptor
    set before [_geometryExchangeOwner $document]
    if {$document eq [dict get $descriptor source id]} {error {Exchange requires independent source and destination documents}}
    set sketch [dict get $descriptor sketch];set units {}
    dict for {id r} [dict get $sketch objects] {lappend units [lindex [dict get $r units] 0]}
    set units [lsort -unique $units]
    if {[llength $units]!=1} {error {Normalize mixed source units before exchange}}
    set from [lindex $units 0];set to [datasetPublicationV2DictDefault $options target_unit $from]
    set factor [lindex [unitRegistryConvertCoordinates $from $to {1}] 0]
    if {$from ne $to} {dict for {cid r} [dict get $sketch constraints] {if {[dict exists $r expression]} {error {Expression-driven dimensional unit conversion requires owner parameter normalization}}}}
    # Explicit rigid placement: no guessing image pixel calibration. Dimensional
    # constraints currently support unit rescale only, not frame rotation.
    set matrix {1 0 0 1 0 0}
    if {[dict exists $options transform]} {
        set t [dict get $options transform]
        foreach k [dict keys $t] {if {$k ni {matrix source_frame target_frame calibration_source unit}} {error "Unknown transform field $k"}}
        foreach k {source_frame target_frame calibration_source unit matrix} {if {![dict exists $t $k] || [dict get $t $k] eq {}} {error "Explicit transform requires $k"}}
        if {[dict get $t source_frame] ne [dict get $descriptor frame name] || [dict get $t unit] ne $to} {error {Transform frame/unit mismatch}}
        set matrix [dict get $t matrix]
        if {[llength $matrix]!=6} {error {Expected six affine coefficients}}
        foreach v $matrix {if {![string is double -strict $v] || [catch {expr {abs($v)<Inf}} finite] || !$finite} {error {Nonfinite transform}}}
        lassign $matrix a b c d x y
        if {abs($a*$a+$b*$b-1)>1e-10 || abs($c*$c+$d*$d-1)>1e-10 || abs($a*$c+$b*$d)>1e-10 || abs($a*$d-$b*$c-1)>1e-10} {error {Only rigid orientation-preserving frame placement is supported}}
        if {[dict size [dict get $sketch constraints]] && $matrix ne {1 0 0 1 0 0}} {error {Constraint frame placement is unsupported; use common calibrated world frame}}
    }
    if {![dict exists $options payload_command] && [dict get $before format] ne "core.geometry_exchange"} {error {Destination owner must provide a pure payload_command for its document format}}
    set scene [native2DGeometryOpen $document];set map {};set handles {};set records {};set relations {};set busy 1;set committed 0
    try {
        dict for {source r} [dict get $sketch objects] {
            _geometryExchangeCancelled $options
            set local "gxcopy_[pid]_[incr serial]_[clock clicks]"
            set item [native2DGeometryCall $scene sketch [dict create definition [dict get $r definition] working_unit $from]]
            set handle [dict get $item object_token]
            _geometryExchangeIdentity $scene $handle $r
            native2DGeometryCall $scene style [dict create object_token $handle properties {color {0.05 0.25 0.5 1} line_width 2 marker 0}]
            dict set map $source $local;dict set handles $local $handle
            native2DGeometryCall $scene identity [dict create object_token $handle name [dict get $r name] key gx.exchange_local_id value $local]
            set lineage [dict create source_document [dict get $descriptor source id] source_generation [dict get $descriptor source generation] source_revision [dict get $descriptor source revision] source_sha256 [dict get $descriptor source sha256] source_object $source descriptor_sha256 [dict get $descriptor sha256]]
            dict set lineage source_origin [datasetPublicationV2DictDefault [dict get $descriptor source] origin [_originUnknown]]
            dict set lineage receiving_installation [installationIdentityCurrent]
            native2DGeometryCall $scene identity [dict create object_token $handle key gx.exchange_lineage value $lineage]
            dict set r provenance exchange_lineage $lineage
            dict set records $local $r
        }
        dict for {cid r} [dict get $sketch constraints] {
            _geometryExchangeCancelled $options
            set spec [dict get $r definition];set public [dict remove $spec a b axis]
            foreach f {a b axis} {if {[dict exists $spec $f] && [dict get $spec $f] ne {}} {dict set public ${f}_token [dict get $handles [dict get $map [dict get $spec $f]]];dict set spec $f [dict get $map [dict get $spec $f]]}}
            native2DGeometryCall $scene constraint_create [dict create definition $public]
            dict set r definition $spec;dict set relations "gxrelation_[incr serial]" $r
        }
        if {$from ne $to} {native2DGeometryCall $scene rescale_coordinates [dict create source_unit $from target_unit $to]}
        if {$matrix ne {1 0 0 1 0 0}} {native2DGeometryCall $scene affine [dict create object_tokens [dict values $handles] matrix $matrix copy 0]}
        dict for {local handle} $handles {
            set actual [native2DGeometryCall $scene describe [dict create object_token $handle]]
            dict set records $local definition [dict get $actual definition];dict set records $local units [list $to $to]
        }
        # Read the backend's post-conversion dimensions, rather than guessing
        # which constraint values have angular versus length semantics.
        set actualRelations [dict get [native2DGeometryCall $scene constraint_list {}] constraints]
        set index 0
        dict for {cid r} $relations {
            set public [lindex $actualRelations $index];incr index
            set spec {}
            foreach k {kind a_index b_index axis_index value tolerance angular_tolerance disabled anchor solved driven placed annotation branch curvature_tolerance} {if {[dict exists $public $k]} {dict set spec $k [dict get $public $k]}}
            foreach f {a b axis} {if {[dict exists $public ${f}_token]} {dict for {local h} $handles {if {$h eq [dict get $public ${f}_token]} {dict set spec $f $local;break}}}}
            dict set relations $cid definition $spec
        }
        set groups {};set groupHandles {}
        dict for {g ids} [dict get $descriptor groups] {
            set locals [lmap id $ids {dict get $map $id}]
            set item [native2DGeometryCall $scene group [dict create object_tokens [lmap id $locals {dict get $handles $id}]]]
            dict set groups $g $locals;dict set groupHandles $g [dict get $item object_token]
        }
        set copy [dict create schema gxtxt.geometry.sketch version 1.0 objects $records constraints $relations parameters [dict get $sketch parameters] provenance [dict create operation explicit_copy source [dict get $descriptor source] frame [dict get $descriptor frame] target_unit $to transform $matrix]]
        _geometryExchangeBounds $copy
        set receipt [dict create copy 1 source_to_destination $map object_tokens $handles group_tokens $groupHandles groups $groups sketch $copy target_document $document]
        if {[dict exists $options payload_command]} {
            set payload [uplevel #0 [list {*}[dict get $options payload_command] $before $receipt]]
        } else {
            set payload [dict get $before payload]
            dict lappend payload exchanges [dict remove $receipt object_tokens group_tokens]
        }
        if {[_geometryExchangeDocumentRead $document] ne $before} {error {Destination changed during import preparation}}
        geometryExchangeInspect $descriptor
        _geometryExchangeCancelled $options
        if {[string bytelength $payload]>33554432} {error {Destination payload exceeds bounded exchange document budget}}
        set result [native2DGeometryCheckpoint $scene $payload];set committed 1
        dict set receipt revision [dict get $result revision];dict set receipt scene_token $scene
        return $receipt
    } finally {
        set busy 0
        if {!$committed} {catch {native2DGeometryClose $scene}}
    }
}
proc ::GX::geometryExchangeRestore {document copy {groups {}}} {
    # Reopen an already committed destination copy without consulting its source.
    _geometryExchangeBounds $copy
    set scene [native2DGeometryOpen $document];set handles {}
    try {
        dict for {id r} [dict get $copy objects] {
            set item [native2DGeometryCall $scene sketch [dict create definition [dict get $r definition] working_unit [lindex [dict get $r units] 0]]]
            dict set handles $id [dict get $item object_token]
            _geometryExchangeIdentity $scene [dict get $item object_token] $r
            native2DGeometryCall $scene style [dict create object_token [dict get $item object_token] properties {color {0.05 0.25 0.5 1} line_width 2 marker 0}]
            native2DGeometryCall $scene identity [dict create object_token [dict get $item object_token] key gx.exchange_local_id value $id]
        }
        dict for {cid r} [dict get $copy constraints] {
            set spec [dict get $r definition];set public [dict remove $spec a b axis]
            foreach f {a b axis} {if {[dict exists $spec $f] && [dict get $spec $f] ne {}} {dict set public ${f}_token [dict get $handles [dict get $spec $f]]}}
            native2DGeometryCall $scene constraint_create [dict create definition $public]
        }
        set groupHandles {}
        dict for {g members} $groups {
            set r [native2DGeometryCall $scene group [dict create object_tokens [lmap id $members {dict get $handles $id}]]]
            dict set groupHandles $g [dict get $r object_token]
        }
        return [dict create scene_token $scene object_tokens $handles group_tokens $groupHandles]
    } on error {m o} {catch {native2DGeometryClose $scene};return -options $o $m}
}

# Resource transport is bounded; callers pass identities, not huge Tcl payloads.
proc ::GX::geometryExchangeExportResource {document selected {options {}}} {
    set descriptor [geometryExchangeExport $document {} $selected $options]
    set writer [interactiveDocumentResourceOpenWriter $document {format gxtxt.geometry.exchange.v1}]
    try {
        set bytes [encoding convertto utf-8 $descriptor]
        for {set i 0} {$i<[string length $bytes]} {incr i 1048576} {interactiveDocumentResourceAppend $writer [string range $bytes $i [expr {$i+1048575}]]}
        geometryExchangeInspect $descriptor
        return [interactiveDocumentResourceFinalize $writer]
    } on error {m o} {catch {interactiveDocumentResourceAbort $writer};return -options $o $m}
}
proc ::GX::geometryExchangeImportResource {document resource {options {}}} {
    interactiveDocumentResourceInfo $resource
    if {[dict get $resource metadata format] ne "gxtxt.geometry.exchange.v1"||[dict get $resource size_bytes]>67108864} {error {Unsupported or over-budget geometry resource}}
    set reader [interactiveDocumentResourceOpenReader $resource];set bytes {}
    try {while 1 {_geometryExchangeCancelled $options;set chunk [interactiveDocumentResourceNext $reader];append bytes [dict get $chunk bytes];if {[dict get $chunk eof]} break}} finally {interactiveDocumentResourceCloseReader $reader}
    set descriptor [encoding convertfrom utf-8 $bytes]
    geometryExchangeInspect $descriptor
    return [geometryExchangeImport $document $descriptor $options]
}
