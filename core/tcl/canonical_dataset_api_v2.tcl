# GX-TXT Canonical Dataset API v2
# SPDX-License-Identifier: GPL-3.0-or-later
# Backend-neutral access over the existing logical Dataset ID. Providers are a
# CORE implementation detail; consumers bind only to dataset_id + variable_id.

namespace eval ::GX {
    variable canonicalDatasetApiVersion 2
    variable datasetStorageProviderCommand
    variable datasetStorageProviderCaps
    variable datasetAccessHandle
    variable datasetAccessCounter 0
    variable csvProviderState
    variable csvProviderCounter 0
    variable hdf5ProviderState
    variable hdf5ProviderCounter 0
    array set datasetStorageProviderCommand {}
    array set datasetStorageProviderCaps {}
    array set datasetAccessHandle {}
    array set csvProviderState {}
    array set hdf5ProviderState {}
}

proc ::GX::datasetCapabilityNames {} {
    return {read_full read_selected_variables row_range_read random_access chunk_read hyperslab_read multidimensional groups implicit_axis typed_binary_read managed_binary_read}
}

proc ::GX::datasetStorageProviderRegister {provider commandPrefix capabilities} {
    variable datasetStorageProviderCommand
    variable datasetStorageProviderCaps
    set provider [string tolower [string trim $provider]]
    if {![regexp {^[a-z][a-z0-9_.-]*$} $provider]} { error "Invalid storage provider ID: $provider" }
    if {![llength $commandPrefix]} { error "Storage provider $provider requires a command" }
    set normalized [dict create]
    foreach name [datasetCapabilityNames] { dict set normalized $name 0 }
    dict for {name value} $capabilities {
        if {$name ni [datasetCapabilityNames]} { error "Unknown dataset capability: $name" }
        dict set normalized $name [expr {$value ? 1 : 0}]
    }
    set datasetStorageProviderCommand($provider) $commandPrefix
    set datasetStorageProviderCaps($provider) $normalized
    return $provider
}

proc ::GX::datasetStorageProviderIds {} {
    variable datasetStorageProviderCommand
    return [lsort [array names datasetStorageProviderCommand]]
}

proc ::GX::datasetStorageProviderCapabilities {provider} {
    variable datasetStorageProviderCaps
    set provider [string tolower [string trim $provider]]
    if {![info exists datasetStorageProviderCaps($provider)]} { error "Dataset storage provider '$provider' is unavailable" }
    return $datasetStorageProviderCaps($provider)
}

proc ::GX::datasetProviderFor {datasetId} {
    set provider [string tolower [string trim [datasetField $datasetId storage_provider ""]]]
    if {$provider ne ""} { return $provider }
    set format [string tolower [string trim [datasetField $datasetId format ""]]]
    set media [string tolower [string trim [datasetField $datasetId media_type ""]]]
    if {$format in {hdf5 h5} || $media in {application/x-hdf5 application/hdf5}} { return hdf5 }
    return csv
}

proc ::GX::datasetAccessRequireHandle {handle} {
    variable datasetAccessHandle
    if {![info exists datasetAccessHandle($handle,dataset_id)]} { error "Unknown or closed dataset access handle: $handle" }
}

proc ::GX::datasetAccessProviderCall {handle operation args} {
    variable datasetAccessHandle
    variable datasetStorageProviderCommand
    datasetAccessRequireHandle $handle
    if {[string match read_* $operation]} {_datasetAccessSourceCheck $handle}
    set provider $datasetAccessHandle($handle,provider)
    set command $datasetStorageProviderCommand($provider)
    return [uplevel #0 [list {*}$command $operation $datasetAccessHandle($handle,provider_token) {*}$args]]
}

proc ::GX::_datasetAccessPathStamp {path} {
    file stat $path status
    return [list $status(dev) $status(ino) $status(size) $status(mtime) $status(ctime)]
}
proc ::GX::_datasetAccessCheckBinding {binding} {
    lassign $binding path expected
    if {[catch {_datasetAccessPathStamp $path} current] || $current ne $expected} {
        error {Canonical Dataset source changed or is unavailable; close and reopen this read handle.}
    }
}
proc ::GX::_datasetAccessProviderBinding {context descriptor} {
    set path [dict get $context path]
    set stamp [_datasetAccessPathStamp $path]
    if {[dict exists $descriptor path_stamp] && [dict get $descriptor path_stamp] ne {} &&
        [file normalize $path] eq [file normalize [dict get $descriptor path]]} {
        # Keep the descriptor-to-provider admission window guarded too. A
        # separately materialized representation owns its actual read path.
        set stamp [dict get $descriptor path_stamp]
    }
    set binding [list $path $stamp]
    _datasetAccessCheckBinding $binding
    return $binding
}
proc ::GX::_datasetAccessSourceCheck {handle} {
    variable datasetAccessHandle
    set token $datasetAccessHandle($handle,provider_token)
    switch -- $datasetAccessHandle($handle,provider) {
        csv {if {[info exists ::GX::csvProviderState($token,source_binding)]} {_datasetAccessCheckBinding $::GX::csvProviderState($token,source_binding)}}
        hdf5 {if {[info exists ::GX::hdf5ProviderState($token,source_binding)]} {_datasetAccessCheckBinding $::GX::hdf5ProviderState($token,source_binding)}}
    }
}

# Resolve a read descriptor through the existing schema/transaction owners.
# A foreign read borrows only their synchronous registry projection. It never
# activates a Session, publishes a catalog event, or opens a provider while that
# projection is installed. The returned descriptor belongs to the access handle.
proc ::GX::_datasetAccessDescriptorLoaded {session datasetId} {
    variable datasetRegistry
    if {[datasetField $datasetId id ""] eq ""} {error "Unknown dataset: $datasetId"}
    set variables [datasetVariableSchemaV3 $datasetId]
    set fields {};set locators {};set index 0
    foreach name [array names datasetRegistry "$datasetId,*"] {
        dict set fields [string range $name [expr {[string length $datasetId]+1}] end] $datasetRegistry($name)
    }
    foreach variable $variables {
        incr index
        dict set locators [dict get $variable variable_id] [datasetField $datasetId var${index}_storage_locator {}]
    }
    set path [datasetResolvePath $session $datasetId];set stamp {}
    if {$path ne {} && [file isfile $path]} {set stamp [_datasetAccessPathStamp $path]}
    return [dict create session $session dataset_id $datasetId record $fields variables $variables locators $locators provider [datasetProviderFor $datasetId] path $path path_stamp $stamp]
}
proc ::GX::_datasetAccessDescriptor {session datasetId} {
    variable currentSession;variable datasetRegistry
    if {$currentSession ne {} && [file normalize $currentSession] eq $session} {
        loadDatasetRegistry $session
        return [_datasetAccessDescriptorLoaded $session $datasetId]
    }
    if {[info commands ::GX::datasetAuthorityActive] ne {} && [datasetAuthorityActive]} {
        error {A Dataset transaction cannot switch Sessions}
    }
    set pending [array get datasetRegistry];set hints {}
    foreach name {datasetAuthorityBaseline datasetAuthorityLoadedSession datasetAuthorityReadSnapshot datasetAuthorityNotification datasetAuthorityFailure} {
        set var ::GX::$name
        if {[info exists $var]} {dict set hints $name [list 1 [set $var]]} else {dict set hints $name [list 0 {}]}
    }
    try {
        # Do not merge the active Session's pending edits into another source.
        array unset datasetRegistry *
        dict for {name saved} $hints {if {[lindex $saved 0]} {set ::GX::$name {}}}
        if {[info commands ::GX::datasetAuthorityTransaction] ne {}} {
            return [datasetAuthorityTransaction $session ::GX::_datasetAccessDescriptorLoaded $session $datasetId]
        }
        loadDatasetRegistry $session
        return [_datasetAccessDescriptorLoaded $session $datasetId]
    } finally {
        array unset datasetRegistry *;array set datasetRegistry $pending
        dict for {name saved} $hints {
            if {[lindex $saved 0]} {set ::GX::$name [lindex $saved 1]} else {unset -nocomplain ::GX::$name}
        }
    }
}
proc ::GX::_datasetAccessField {descriptor field {default {}}} {
    if {[dict exists $descriptor record $field]} {return [dict get $descriptor record $field]}
    return $default
}
proc ::GX::_datasetAccessHandleDescriptor {handle} {
    variable datasetAccessHandle
    datasetAccessRequireHandle $handle
    if {![info exists datasetAccessHandle($handle,descriptor)]} {
        # Older representation-open callers still construct the ordinary
        # handle fields. Reuse the descriptor captured by their provider at
        # open, rather than resolving a different later global schema.
        set provider $datasetAccessHandle($handle,provider)
        set token $datasetAccessHandle($handle,provider_token)
        if {$provider eq "csv" && [info exists ::GX::csvProviderState($token,descriptor)]} {
            set descriptor $::GX::csvProviderState($token,descriptor)
        } elseif {$provider eq "hdf5" && [info exists ::GX::hdf5ProviderState($token,descriptor)]} {
            set descriptor $::GX::hdf5ProviderState($token,descriptor)
        } else {set descriptor [_datasetAccessDescriptor $datasetAccessHandle($handle,session) $datasetAccessHandle($handle,dataset_id)]}
        set datasetAccessHandle($handle,descriptor) $descriptor
    }
    return $datasetAccessHandle($handle,descriptor)
}
proc ::GX::datasetAccessOpen {session datasetId} {
    variable datasetAccessHandle;variable datasetAccessCounter
    variable datasetStorageProviderCommand
    set session [file normalize $session]
    if {![file isdirectory $session]} {error "Dataset session directory does not exist: $session"}
    set descriptor [_datasetAccessDescriptor $session $datasetId]
    set provider [dict get $descriptor provider]
    if {![info exists datasetStorageProviderCommand($provider)]} {error "Dataset storage provider '$provider' is unavailable"}
    if {$provider eq "remote"} {
        return [datasetRemoteAccessOpen $session $datasetId $descriptor]
    }
    set path [dict get $descriptor path]
    if {$path eq {} || ![file isfile $path]} {error "Dataset $datasetId has no readable storage object"}
    set context [dict create session $session dataset_id $datasetId path $path descriptor $descriptor]
    set token [uplevel #0 [list {*}$datasetStorageProviderCommand($provider) open {} $context]]
    set metadata {}
    set handle "dataset#[incr datasetAccessCounter]"
    foreach {key value} [list dataset_id $datasetId session $session provider $provider provider_token $token metadata $metadata descriptor $descriptor] {
        set datasetAccessHandle($handle,$key) $value
    }
    return $handle
}

proc ::GX::datasetAccessCapabilities {handle} {
    variable datasetAccessHandle
    datasetAccessRequireHandle $handle
    if {$datasetAccessHandle($handle,provider) eq "remote"} {return [dict get $datasetAccessHandle($handle,metadata) capabilities]}
    return [datasetStorageProviderCapabilities $datasetAccessHandle($handle,provider)]
}

proc ::GX::datasetAccessTrueCapabilities {handle} {
    set out {}
    dict for {name enabled} [datasetAccessCapabilities $handle] { if {$enabled} { lappend out $name } }
    return $out
}

proc ::GX::_datasetAccessPublicDtype {schemaDtype providerDtype} {
    if {$schemaDtype eq "string" && ($providerDtype eq "object" || [string match {*string*} $providerDtype] || [regexp {^[|<>]?[SU][0-9]+$} $providerDtype])} {return string}
    return $providerDtype
}
proc ::GX::datasetAccessMetadata {handle} {
    variable datasetAccessHandle
    datasetAccessRequireHandle $handle
    if {$datasetAccessHandle($handle,metadata) ne ""} { return $datasetAccessHandle($handle,metadata) }
    set datasetId $datasetAccessHandle($handle,dataset_id)
    set descriptor [_datasetAccessHandleDescriptor $handle]
    set providerMeta [datasetAccessProviderCall $handle metadata]
    set variables {}
    set groupIds {}
    foreach variable [dict get $descriptor variables] {
        set variableId [dict get $variable variable_id]
        set providerVariable [dict create]
        if {[dict exists $providerMeta variables $variableId]} { set providerVariable [dict get $providerMeta variables $variableId] }
        foreach field {dtype rank shape} {
            if {[dict exists $providerVariable $field] && [dict get $providerVariable $field] ne ""} {
                set value [dict get $providerVariable $field]
                # HDF5 variable-length UTF-8 is represented as NumPy object
                # storage. Keep the public schema's string type rather than
                # leaking a backend dtype that no canonical consumer accepts.
                if {$field eq "dtype"} {set value [_datasetAccessPublicDtype [dict get $variable dtype] $value]}
                dict set variable $field $value
            }
        }
        set groupId [dict get $variable group_id]
        if {$groupId ne "" && $groupId ni $groupIds} { lappend groupIds $groupId }
        lappend variables $variable
    }
    set rowCount [_datasetAccessField $descriptor row_count ""]
    if {$rowCount eq "" && [dict exists $providerMeta row_count]} { set rowCount [dict get $providerMeta row_count] }
    if {$rowCount eq ""} { set rowCount -1 }
    set metadata [dict create \
        api_version 2 \
        dataset_id $datasetId \
        contract [_datasetAccessField $descriptor kind ""] \
        storage_provider $datasetAccessHandle($handle,provider) \
        format [_datasetAccessField $descriptor format ""] \
        row_count $rowCount \
        sample_count [_datasetAccessField $descriptor sample_count $rowCount] \
        capabilities [datasetAccessCapabilities $handle] \
        variables $variables \
        groups $groupIds]
    set datasetAccessHandle($handle,metadata) $metadata
    return $metadata
}

proc ::GX::datasetAccessVariableIds {handle} {
    set out {}
    foreach variable [dict get [datasetAccessMetadata $handle] variables] { lappend out [dict get $variable variable_id] }
    return $out
}

proc ::GX::datasetAccessNormalizeVariableIds {handle variableIds} {
    set known [datasetAccessVariableIds $handle]
    set out {}
    foreach variableId $variableIds {
        if {$variableId ni $known} { error "Dataset access handle $handle has no variable_id $variableId" }
        if {$variableId ni $out} { lappend out $variableId }
    }
    if {![llength $out]} { error "At least one variable_id is required" }
    return $out
}

proc ::GX::datasetAccessUniformValues {variable start count} {
    set origin [dict get $variable axis_origin]
    set step [dict get $variable axis_step]
    set total [dict get $variable axis_count]
    if {![string is double -strict $origin] || ![string is double -strict $step] || ![string is integer -strict $total]} {
        error "Uniform axis metadata is incomplete for [dict get $variable variable_id]"
    }
    if {$start < 0 || $start > $total} { error "Range start is outside the uniform axis" }
    if {$count < 0} { set count [expr {$total-$start}] }
    if {$count < 0 || $start+$count > $total} { error "Range count is outside the uniform axis" }
    set values {}
    for {set offset 0} {$offset < $count} {incr offset} { lappend values [expr {double($origin)+($start+$offset)*double($step)}] }
    return [dict create dtype [dict get $variable dtype] shape $count values $values start $start count $count synthesized 1]
}

proc ::GX::datasetBinaryTransportDtypes {} {
    return {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool}
}

proc ::GX::datasetBinaryTransportWidth {dtype} {
    set widths [dict create bool 1 int8 1 uint8 1 int16 2 uint16 2 int32 4 uint32 4 float32 4 int64 8 uint64 8 float64 8]
    if {![dict exists $widths $dtype]} { error "Unsupported typed binary read dtype '$dtype'" }
    return [dict get $widths $dtype]
}

proc ::GX::datasetBinaryShapeCount {shape} {
    set dimensions [datasetSchemaV3SplitIds $shape]
    if {![llength $dimensions]} { return 1 }
    set count 1
    foreach dimension $dimensions {
        if {![string is integer -strict $dimension] || $dimension < 0} { error "Invalid typed binary block shape" }
        set count [expr {$count*$dimension}]
    }
    return $count
}

proc ::GX::datasetBinaryValidateBlock {block {expectedCount -1}} {
    foreach field {__gxtxt_binary_block dtype endian shape base64 byte_count} {
        if {![dict exists $block $field]} { error "Typed binary read block is missing '$field'" }
    }
    if {[dict get $block __gxtxt_binary_block] ne "1"} { error "Invalid typed binary read block marker" }
    set dtype [string tolower [dict get $block dtype]]
    if {$dtype ni [datasetBinaryTransportDtypes]} { error "Unsupported typed binary read dtype '$dtype'" }
    set endian [string tolower [dict get $block endian]]
    if {$endian ni {little big}} { error "Unsupported typed binary read endian '$endian'" }
    set count [datasetBinaryShapeCount [dict get $block shape]]
    if {$expectedCount >= 0 && $count != $expectedCount} { error "Typed binary read block shape/count mismatch" }
    set byteCount [expr {$count*[datasetBinaryTransportWidth $dtype]}]
    if {![string is integer -strict [dict get $block byte_count]] || [dict get $block byte_count] != $byteCount} {
        error "Typed binary read block byte count mismatch"
    }
    set encoded [dict get $block base64]
    set encodedLength [expr {(($byteCount+2)/3)*4}]
    if {[string length $encoded] != $encodedLength || [regexp {[^A-Za-z0-9+/=]} $encoded]} {
        error "Invalid typed binary read Base64 length or alphabet"
    }
    return $count
}

proc ::GX::datasetBinaryBlockFromValues {dtype shape values} {
    set dtype [string tolower $dtype]
    if {$dtype ni {float32 float64}} { error "CORE synthesized binary coordinates require float32 or float64" }
    set count [datasetBinaryShapeCount $shape]
    if {[llength $values] != $count} { error "Synthesized binary coordinate shape/count mismatch" }
    if {$dtype eq "float32"} {
        set raw [binary format r* $values]
    } else {
        set raw [binary format q* $values]
    }
    set block [dict create __gxtxt_binary_block 1 dtype $dtype endian little shape $shape base64 [binary encode base64 -maxlen 0 $raw] byte_count [string length $raw]]
    datasetBinaryValidateBlock $block $count
    return $block
}

proc ::GX::datasetAccessVariableIsImplicit {handle variable} {
    variable datasetAccessHandle
    if {$datasetAccessHandle($handle,provider) eq "remote"} {return 0}
    set representationImplicit [expr {[info exists datasetAccessHandle($handle,is_representation)] && $datasetAccessHandle($handle,is_representation)}]
    set descriptor [_datasetAccessHandleDescriptor $handle]
    return [expr {[dict get $variable axis_kind] eq "uniform" && ($representationImplicit || [dict get $descriptor locators [dict get $variable variable_id]] eq "")}]
}

proc ::GX::datasetAccessReadRangeBinary {handle variableIds start count} {
    variable datasetAccessHandle
    datasetAccessRequireHandle $handle
    _datasetAccessSourceCheck $handle
    if {![string is integer -strict $start] || $start < 0} { error "start must be an integer >= 0" }
    if {![string is integer -strict $count] || $count < -1} { error "count must be -1 or an integer >= 0" }
    set variableIds [datasetAccessNormalizeVariableIds $handle $variableIds]
    set byId [dict create]
    foreach variable [dict get [datasetAccessMetadata $handle] variables] { dict set byId [dict get $variable variable_id] $variable }
    set physical {}; set implicit {}
    foreach variableId $variableIds {
        set variable [dict get $byId $variableId]
        set dtype [dict get $variable dtype]
        if {$dtype ni [datasetBinaryTransportDtypes]} { error "Variable $variableId dtype '$dtype' has no typed binary read transport" }
        if {[datasetAccessVariableIsImplicit $handle $variable]} {
            if {$dtype ni {float32 float64}} { error "Implicit variable $variableId dtype '$dtype' uses the value fallback" }
            lappend implicit $variableId
        } else {
            lappend physical $variableId
        }
    }
    set result [dict create]
    if {[llength $physical]} {
        if {![dict get [datasetAccessCapabilities $handle] typed_binary_read]} {
            error "Dataset provider does not expose typed binary reads"
        }
        set result [datasetAccessProviderCall $handle read_range_binary $physical $start $count]
    }
    foreach variableId $implicit {
        set variable [dict get $byId $variableId]
        set valuesItem [datasetAccessUniformValues $variable $start $count]
        set itemCount [dict get $valuesItem count]
        set block [datasetBinaryBlockFromValues [dict get $variable dtype] [dict get $valuesItem shape] [dict get $valuesItem values]]
        dict unset valuesItem values
        dict set valuesItem binary_block $block
        dict set valuesItem transport typed_binary
        dict set result $variableId $valuesItem
    }
    return $result
}

proc ::GX::datasetAccessReadRangeTransport {handle variableIds start count} {
    set variableIds [datasetAccessNormalizeVariableIds $handle $variableIds]
    set byId [dict create]
    foreach variable [dict get [datasetAccessMetadata $handle] variables] { dict set byId [dict get $variable variable_id] $variable }
    set binaryCapable [dict get [datasetAccessCapabilities $handle] typed_binary_read]
    set binaryIds {};set valueIds {}
    foreach variableId $variableIds {
        set variable [dict get $byId $variableId]
        set dtype [dict get $variable dtype]
        set implicit [datasetAccessVariableIsImplicit $handle $variable]
        set useBinary [expr {$dtype in [datasetBinaryTransportDtypes] && (($implicit && $dtype in {float32 float64}) || (!$implicit && $binaryCapable))}]
        if {$useBinary} {lappend binaryIds $variableId} else {lappend valueIds $variableId}
    }
    set result [dict create]
    if {[llength $binaryIds]} {
        set binary [datasetAccessReadRangeBinary $handle $binaryIds $start $count]
        foreach variableId $binaryIds {dict set result $variableId [dict get $binary $variableId]}
    }
    if {[llength $valueIds]} {
        set values [datasetAccessReadRange $handle $valueIds $start $count]
        foreach variableId $valueIds {
            set item [dict get $values $variableId]
            dict set item transport values
            dict set result $variableId $item
        }
    }
    return $result
}

proc ::GX::datasetAccessReadRange {handle variableIds start count} {
    variable datasetAccessHandle
    datasetAccessRequireHandle $handle
    _datasetAccessSourceCheck $handle
    if {![string is integer -strict $start] || $start < 0} { error "start must be an integer >= 0" }
    if {![string is integer -strict $count] || $count < -1} { error "count must be -1 or an integer >= 0" }
    set variableIds [datasetAccessNormalizeVariableIds $handle $variableIds]
    set datasetId $datasetAccessHandle($handle,dataset_id)
    set physical {}; set implicit {}; set byId [dict create]
    foreach variable [dict get [datasetAccessMetadata $handle] variables] { dict set byId [dict get $variable variable_id] $variable }
    foreach variableId $variableIds {
        set variable [dict get $byId $variableId]
        if {[datasetAccessVariableIsImplicit $handle $variable]} {
            lappend implicit $variableId
        } else {
            lappend physical $variableId
        }
    }
    set result [dict create]
    if {[llength $physical]} { set result [datasetAccessProviderCall $handle read_range $physical $start $count] }
    set resolvedCount $count
    if {$resolvedCount < 0 && [dict size $result]} {
        set first [lindex [dict keys $result] 0]
        set resolvedCount [dict get $result $first count]
    }
    foreach variableId $implicit {
        set variable [dict get $byId $variableId]
        set item [datasetAccessUniformValues $variable $start $resolvedCount]
        if {$resolvedCount < 0} { set resolvedCount [dict get $item count] }
        dict set result $variableId $item
    }
    foreach variableId $physical {
        set item [dict get $result $variableId]
        dict set item dtype [_datasetAccessPublicDtype [dict get $byId $variableId dtype] [dict get $item dtype]]
        dict set result $variableId $item
    }
    return $result
}

proc ::GX::datasetAccessReadVariables {handle variableIds} {
    set variableIds [datasetAccessNormalizeVariableIds $handle $variableIds]
    set byId [dict create]
    foreach variable [dict get [datasetAccessMetadata $handle] variables] { dict set byId [dict get $variable variable_id] $variable }
    set vectors {}; set arrays {}
    foreach variableId $variableIds {
        if {[dict get $byId $variableId rank] <= 1} { lappend vectors $variableId } else { lappend arrays $variableId }
    }
    set result [dict create]
    if {[llength $vectors]} { set result [datasetAccessReadRange $handle $vectors 0 -1] }
    foreach variableId $arrays {
        set variable [dict get $byId $variableId]
        set counts [datasetSchemaV3SplitIds [dict get $variable shape]]
        set starts [lrepeat [llength $counts] 0]
        dict set result $variableId [datasetAccessReadHyperslab $handle $variableId $starts $counts]
    }
    return $result
}

proc ::GX::datasetAccessReadFull {handle} {
    return [datasetAccessReadVariables $handle [datasetAccessVariableIds $handle]]
}

proc ::GX::datasetAccessReadHyperslab {handle variableId starts counts} {
    set caps [datasetAccessCapabilities $handle]
    if {![dict get $caps hyperslab_read]} { error "Dataset provider does not support hyperslab_read" }
    datasetAccessNormalizeVariableIds $handle [list $variableId]
    set item [datasetAccessProviderCall $handle read_hyperslab $variableId $starts $counts]
    foreach variable [dict get [datasetAccessMetadata $handle] variables] {
        if {[dict get $variable variable_id] eq $variableId} {
            dict set item dtype [_datasetAccessPublicDtype [dict get $variable dtype] [dict get $item dtype]]
            break
        }
    }
    return $item
}

proc ::GX::datasetAccessIterateChunks {handle variableIds chunkSize commandPrefix} {
    if {![string is integer -strict $chunkSize] || $chunkSize <= 0} { error "chunkSize must be an integer > 0" }
    if {![llength $commandPrefix]} { error "Chunk iteration requires a callback command" }
    set variableIds [datasetAccessNormalizeVariableIds $handle $variableIds]
    set metadata [datasetAccessMetadata $handle]
    set first {}
    foreach variable [dict get $metadata variables] {if {[dict get $variable variable_id] eq [lindex $variableIds 0]} {set first $variable;break}}
    set shape [datasetSchemaV3SplitIds [dict get $first shape]]
    set total [expr {[llength $shape] ? [lindex $shape 0] : [dict get $metadata row_count]}]
    set start 0; set chunks 0
    while {$total < 0 || $start < $total} {
        set request $chunkSize
        if {$total >= 0 && $start+$request > $total} { set request [expr {$total-$start}] }
        if {$request <= 0} break
        set data [datasetAccessReadRange $handle $variableIds $start $request]
        set first [lindex $variableIds 0]
        set actual [dict get $data $first count]
        if {$actual <= 0} break
        uplevel #0 [list {*}$commandPrefix $handle $start $data]
        incr chunks
        incr start $actual
        if {$actual < $request} break
    }
    return $chunks
}

proc ::GX::datasetAccessReadHyperslabBinary {handle variableId starts counts} {
    set variableId [lindex [datasetAccessNormalizeVariableIds $handle [list $variableId]] 0]
    set variable ""
    foreach candidate [dict get [datasetAccessMetadata $handle] variables] {
        if {[dict get $candidate variable_id] eq $variableId} { set variable $candidate; break }
    }
    if {$variable eq ""} { error "Dataset access handle has no variable_id $variableId" }
    if {[dict get $variable dtype] ni [datasetBinaryTransportDtypes]} {
        error "Variable $variableId dtype '[dict get $variable dtype]' has no typed binary read transport"
    }
    if {![dict get [datasetAccessCapabilities $handle] typed_binary_read]} {
        error "Dataset provider does not expose typed binary reads"
    }
    return [datasetAccessProviderCall $handle read_hyperslab_binary $variableId $starts $counts]
}

# Bounded resources from the same canonical provider. Tcl carries descriptors,
# never the numeric payload. Legacy values/Base64 operations stay available.
proc ::GX::datasetAccessReadRangeResource {handle variableIds start count} {
    if {![string is entier -strict $start] || $start<0 || ![string is entier -strict $count] || $count<0} {error {Resource reads require bounded nonnegative integer ranges}}
    set ids [datasetAccessNormalizeVariableIds $handle $variableIds]
    if {![dict get [datasetAccessCapabilities $handle] managed_binary_read]} {return [datasetAccessReadRange $handle $ids $start $count]}
    set schema {};foreach v [dict get [datasetAccessMetadata $handle] variables] {dict set schema [dict get $v variable_id] $v}
    set physical {};set fallback {}
    foreach id $ids {
        set v [dict get $schema $id]
        if {[dict get $v rank]!=1} {error {Range reads require rank-1 variables}}
        if {[dict get $v dtype] in [datasetBinaryTransportDtypes] && [dict get $v axis_kind] ne "uniform"} {lappend physical $id} else {lappend fallback $id}
    }
    set result {}
    if {[llength $physical]} {set result [datasetAccessProviderCall $handle read_range_resource $physical $start $count]}
    if {[llength $fallback]} {set result [dict merge $result [datasetAccessReadRange $handle $fallback $start $count]]}
    return $result
}
proc ::GX::datasetAccessReadHyperslabResource {handle variableId starts counts} {
    set variableId [lindex [datasetAccessNormalizeVariableIds $handle [list $variableId]] 0]
    if {![dict get [datasetAccessCapabilities $handle] managed_binary_read]} {error {Dataset provider has no managed binary resources}}
    return [datasetAccessProviderCall $handle read_hyperslab_resource $variableId $starts $counts]
}
proc ::GX::datasetAccessReleaseResource {handle resourceId} {
    return [datasetAccessProviderCall $handle release_resource $resourceId]
}
proc ::GX::datasetBinaryResourceValidate {resource {expectedCount -1}} {
    foreach field {version dtype endian order shape count byte_count resource_id resource_root} {if {![dict exists $resource $field]} {error "Incomplete binary resource: $field"}}
    if {[dict get $resource version]!=2 || [dict get $resource endian] ne "little" || [dict get $resource order] ne "F"} {error {Unsupported binary resource descriptor}}
    set dtype [dict get $resource dtype];set width [datasetBinaryTransportWidth $dtype]
    set count [datasetBinaryShapeCount [dict get $resource shape]]
    if {$count!=[dict get $resource count] || ($expectedCount>=0 && $count!=$expectedCount) || $count*$width!=[dict get $resource byte_count] || $count*$width>536870912} {error {Binary resource shape/count/size mismatch}}
    if {![regexp {^[a-f0-9]{32}\.bin$} [dict get $resource resource_id]]} {error {Invalid binary resource identity}}
    set root [dict get $resource resource_root]
    if {[file pathtype $root] ne "absolute" || ![file isdirectory $root] || [file type $root] eq "link"} {error {Invalid binary resource scope}}
    set path [file join $root [dict get $resource resource_id]]
    if {![file isfile $path] || [file type $path] ne "file" || [file size $path]!=[dict get $resource byte_count]} {error {Invalid binary resource file}}
    return $resource
}

proc ::GX::datasetAccessDiagnostics_before_storage_policy {handle} {
    return [datasetAccessProviderCall $handle diagnostics]
}

proc ::GX::datasetAccessClose {handle} {
    variable datasetAccessHandle
    if {![info exists datasetAccessHandle($handle,dataset_id)]} { return }
    set failure ""
    if {[catch {datasetAccessProviderCall $handle close} failure options]} {
        foreach name [array names datasetAccessHandle "$handle,*"] { unset datasetAccessHandle($name) }
        return -options $options $failure
    }
    foreach name [array names datasetAccessHandle "$handle,*"] { unset datasetAccessHandle($name) }
}

proc ::GX::datasetAccessWith {session datasetId variableName script} {
    set handle [datasetAccessOpen $session $datasetId]
    upvar 1 $variableName accessHandle
    set accessHandle $handle
    try { uplevel 1 $script } finally { datasetAccessClose $handle }
}

# Persist additive v2/v3 provider and schema fields while retaining the
# datasets.ini v1 layout understood by old readers.
proc ::GX::saveDatasetRegistry {session} {
    variable cfg
    variable datasetRegistry
    foreach id [datasetRegistryIds] {
        if {[datasetField $id variable_schema_api_version ""] ni {2 3}} { datasetSchemaEnsure $session $id }
    }
    set path [datasetRegistryPath $session]
    datasetAuthorityEnlist $path
    file mkdir [file dirname $path]
    set existed [file isfile $path];set previous {};set registered {}
    if {$existed} {
        set input [open $path rb];try {set previous [read $input]} finally {close $input}
        set registered [parseIni $path]
    }
    set ids [datasetRegistryIds];set newIds {}
    foreach id $ids {if {![dict exists $registered dataset.$id.id]} {lappend newIds $id}}
    set prior [array get datasetRegistry];set metadataBefore {};set temporary "$path.tmp.[pid].[clock clicks]"
    set profileIds {}
    if {[info commands ::GX::_datasetScientificProfileCommitCandidates] ne {}} {set profileIds [_datasetScientificProfileCommitCandidates $session $registered $ids]}
    # Newly registered Datasets get their initial namespace in the existing
    # private metadata resource. Existing legacy records keep dynamic fallback.
    # Snapshot only affected resources; recursive metadata registry saves see
    # the already committed IDs and cannot initialize them a second time.
    if {[info commands ::GX::datasetNamespaceSet] ne {}} {
        foreach id [lsort -unique [concat $newIds $profileIds]] {
            lassign [_datasetMetadataPath $session $id] relative metadataPath
            set bytes {};set present [file isfile $metadataPath]
            if {$present} {set input [open $metadataPath rb];try {set bytes [read $input]} finally {close $input}}
            dict set metadataBefore $metadataPath [list $present $bytes]
        }
    }
    try {
        set fd [open $temporary w]
        try {
            fconfigure $fd -encoding utf-8 -translation lf
            puts $fd "; GX-TXT Canonical Dataset registry"
            puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
            puts $fd "\[registry\]"
            putKV $fd api_version 1
            putKV $fd access_api_version 2
            putKV $fd session_mode [expr {[info exists cfg(session_mode)] ? $cfg(session_mode) : ""}]
            putKV $fd count [llength $ids]
            foreach id $ids {
                puts $fd "\n\[dataset.$id\]"
                set fields {}
                foreach name [array names datasetRegistry "$id,*"] { lappend fields [string range $name [expr {[string length $id]+1}] end] }
                foreach field [lsort -dictionary -unique $fields] { putKV $fd $field $datasetRegistry($id,$field) }
            }
        } finally {close $fd}
        file rename -force -- $temporary $path
        if {[info commands ::GX::datasetNamespaceSet] ne {}} {
            foreach id $newIds {
                set metadata [_datasetMetadataReadRegistered $session $id]
                if {[dict exists $metadata _gxtxt.framework.dataset_namespace]} continue
                set module [datasetField $id producer_module [datasetField $id source_module {}]]
                # Every recorded producer, including legacy acquisition paths,
                # receives its assigned namespace independently of Current.
                set namespace [expr {$module eq {}?"base":[datasetNamespaceForModule $module]}]
                _datasetFrameworkMetadataUpdate $session $id [dict create dataset_namespace $namespace]
            }
        }
        foreach id $profileIds {_datasetScientificProfileRefresh $session $id}
    } on error {message options} {
        array unset datasetRegistry *;array set datasetRegistry $prior
        if {$existed} {set fd [open $temporary wb];try {puts -nonewline $fd $previous} finally {close $fd};file rename -force -- $temporary $path} else {file delete -force -- $path}
        dict for {metadataPath state} $metadataBefore {
            lassign $state present bytes
            if {$present} {set fd [open $metadataPath wb];try {puts -nonewline $fd $bytes} finally {close $fd}} else {file delete -force -- $metadataPath}
        }
        return -options $options $message
    } finally {file delete -force -- $temporary}
    return $path
}

# CSV provider: complete compatibility reads, selected variables, ranges and
# bounded chunks. It intentionally advertises random_access=0 because a range
# starts by scanning the text prefix.
proc ::GX::csvStorageNativeAvailable {} {
    # Optional prebuilt acceleration of this same provider. No runtime compiler,
    # alternate source reader or Preview-owned path is involved. Older/missing
    # adapters keep the established values implementation available.
    variable csvNativeLoadAttempted
    if {![llength [info commands ::GX::DatasetCSV::native]]} {
        if {[info exists csvNativeLoadAttempted]} {return 0}
        set csvNativeLoadAttempted 1
        set library [file join $::GX::scriptDir core native2d bin gx2dtcl[info sharedlibextension]]
        if {![file isfile $library] || [catch {load $library Gx2dtcl}]} {return 0}
    }
    if {![llength [info commands ::GX::DatasetCSV::native]]} {return 0}
    if {[catch {set info [::GX::DatasetCSV::native api_info]}]} {return 0}
    if {[catch {expr {[dict exists $info abi_version] && [dict get $info abi_version]==1}} available]} {return 0}
    return $available
}
proc ::GX::csvStorageProvider {operation token args} {
    variable csvProviderState
    variable csvProviderCounter
    switch -- $operation {
        open {
            set context [lindex $args 0]
            set descriptor [expr {[dict exists $context descriptor] ? [dict get $context descriptor] : [_datasetAccessDescriptor [dict get $context session] [dict get $context dataset_id]]}]
            set binding [_datasetAccessProviderBinding $context $descriptor]
            set token "csv#[incr csvProviderCounter]"
            set csvProviderState($token,dataset_id) [dict get $context dataset_id]
            set csvProviderState($token,path) [dict get $context path]
            set csvProviderState($token,descriptor) $descriptor
            set csvProviderState($token,source_binding) $binding
            set csvProviderState($token,fd) ""
            set csvProviderState($token,next_row) 0
            set csvProviderState($token,payload_elements_read) 0
            set csvProviderState($token,prefix_elements_scanned) 0
            set csvProviderState($token,max_request_elements) 0
            return $token
        }
        metadata {
            set datasetId $csvProviderState($token,dataset_id)
            set vars [dict create]
            set descriptor $csvProviderState($token,descriptor)
            foreach variable [dict get $descriptor variables] {dict set vars [dict get $variable variable_id] [dict create dtype [dict get $variable dtype] rank [dict get $variable rank] shape [dict get $variable shape]]}
            return [dict create row_count [_datasetAccessField $descriptor row_count -1] variables $vars]
        }
        read_range { return [csvStorageProviderReadRange $token {*}$args] }
        read_hyperslab { error "CSV storage does not support multidimensional hyperslabs" }
        diagnostics { return [dict create process_id [pid] metadata_payload_elements 0 payload_elements_read $csvProviderState($token,payload_elements_read) prefix_elements_scanned $csvProviderState($token,prefix_elements_scanned) max_request_elements $csvProviderState($token,max_request_elements)] }
        close {
            if {[info exists csvProviderState($token,fd)] && $csvProviderState($token,fd) ne ""} {
                catch {close $csvProviderState($token,fd)}
            }
            foreach name [array names csvProviderState "$token,*"] { unset csvProviderState($name) }
            return
        }
        default { error "Unsupported CSV provider operation: $operation" }
    }
}

proc ::GX::csvStorageTypedValue {variable raw} {
    # CSV syntax quotes have already been decoded by datasetSchemaCsvSplit.
    # Quotes that survive that parser are scientific text, not delimiters.
    if {[dict get $variable dtype] eq "string" || [dict get $variable value_kind] eq "text"} { return $raw }
    set raw [string trim $raw " \t\r\n"]
    # Preserve a missing CSV field separately from a source NaN token.
    # Consumers such as Worksheet must be able to retain that distinction.
    if {$raw eq ""} { return "" }
    if {[dict get $variable value_kind] eq "elapsed_time" && [dict get $variable value_format] eq "hms"} {
        if {![regexp {^([0-9]+):([0-5][0-9]):([0-5][0-9](?:[.,][0-9]+)?)$} $raw -> hours minutes seconds]} { return NaN }
        set seconds [string map {, .} $seconds]
        # Public elapsed_time values are normalized to seconds. The declared
        # source unit remains schema metadata and must not rescale this value.
        return [expr {$hours*3600.0+$minutes*60.0+$seconds}]
    }
    if {[dict get $variable decimal_separator] eq ","} { set raw [string map {, .} $raw] }
    if {[string is double -strict $raw]} { return $raw }
    if {[string tolower $raw] in {nan +nan -nan inf +inf -inf infinity +infinity -infinity}} { return $raw }
    return NaN
}

proc ::GX::csvStorageProviderReadRange {token variableIds start count} {
    variable csvProviderState
    set datasetId $csvProviderState($token,dataset_id)
    set path $csvProviderState($token,path)
    set descriptor $csvProviderState($token,descriptor)
    set delimiter [_datasetAccessField $descriptor canonical_delimiter ""]
    if {$delimiter eq ""} {
        set delimiter [datasetSchemaDetectDelimiter $path]
    } else {
        switch -- $delimiter {
            tab { set delimiter "\t" }
            semicolon { set delimiter ";" }
            comma { set delimiter "," }
        }
    }
    set variables [dict create];set schema {}
    foreach variable [dict get $descriptor variables] {dict set schema [dict get $variable variable_id] $variable}
    foreach variableId $variableIds {
        set variable [dict get $schema $variableId]
        set position [dict get $variable canonical_position]
        if {![string is integer -strict $position] || $position < 1} { error "Variable $variableId is not physically present in CSV storage" }
        dict set variables $variableId [dict create variable $variable column [expr {$position-1}]]
        set columnValues($variableId) {}
    }
    # Multi-character historical separators retain their original Tcl policy.
    # The native parser consumes the SAME provider-owned translated channel.
    set native [expr {[string length $delimiter]==1 && [csvStorageNativeAvailable]}]
    set fd $csvProviderState($token,fd)
    if {$fd eq "" || $start < $csvProviderState($token,next_row)} {
        if {$fd ne ""} { close $fd }
        set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
        set csvProviderState($token,fd) $fd
        set csvProviderState($token,next_row) 0
        if {$native} {
            ::GX::DatasetCSV::native header $fd $delimiter
        } else {
            gets $fd header
            if {[string first {"} $header]>=0} {datasetSchemaCsvSplit $header $delimiter $fd}
        }
    }
    set row $csvProviderState($token,next_row);set taken 0;set skipped 0
    if {$native} {
        set prepared [::GX::DatasetCSV::native read $fd $delimiter $variables $row $start $count]
        set row [dict get $prepared next_row]
        set taken [dict get $prepared taken]
        set skipped [dict get $prepared skipped]
        foreach variableId $variableIds {set columnValues($variableId) [dict get $prepared values $variableId]}
    } else {
    while {$row < $start && [gets $fd line] >= 0} {
        if {[string trim $line] eq ""} continue
        if {[string first {"} $line]>=0} {datasetSchemaCsvSplit $line $delimiter $fd}
        incr row;incr skipped
    }
    while {$count < 0 || $taken < $count} {
        if {[gets $fd line] < 0} break
        if {[string trim $line] eq ""} continue
        set fields [datasetSchemaCsvSplit $line $delimiter $fd]
        foreach variableId $variableIds {
            set item [dict get $variables $variableId]
            set column [dict get $item column]
            # Keep the CSV token textual here. Tcl expr evaluates NaN/Inf as
            # arithmetic operands and raises a domain error before the typed
            # value parser can apply the declared missing/non-finite policy.
            if {$column < [llength $fields]} {
                set raw [lindex $fields $column]
            } else {
                set raw ""
            }
            # Keep the growing list unshared. Extracting it from a dictionary
            # and replacing that dictionary each row copies the entire prefix
            # on every append (quadratic work inside a bounded chunk).
            lappend columnValues($variableId) [csvStorageTypedValue [dict get $item variable] $raw]
        }
        incr row; incr taken
    }
    }
    set csvProviderState($token,next_row) $row
    set csvProviderState($token,prefix_elements_scanned) [expr {$csvProviderState($token,prefix_elements_scanned)+$skipped}]
    set elements [expr {$taken*[llength $variableIds]}]
    set csvProviderState($token,payload_elements_read) [expr {$csvProviderState($token,payload_elements_read)+$elements}]
    if {$elements > $csvProviderState($token,max_request_elements)} { set csvProviderState($token,max_request_elements) $elements }
    set out [dict create]
    foreach variableId $variableIds {
        set item [dict get $variables $variableId]
        set variable [dict get $item variable]
        dict set out $variableId [dict create dtype [dict get $variable dtype] shape $taken values $columnValues($variableId) start $start count $taken synthesized 0]
    }
    return $out
}

proc ::GX::datasetB64Encode {value} { return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]] }
proc ::GX::datasetB64Decode {value} { return [encoding convertfrom utf-8 [binary decode base64 $value]] }

proc ::GX::hdf5ProviderReadLine {channel} {
    if {[gets $channel line] < 0} { error "HDF5 provider worker terminated unexpectedly" }
    set parts [split $line "\t"]
    if {[lindex $parts 0] eq "ERROR"} { error "HDF5 provider: [datasetB64Decode [lindex $parts 1]]" }
    if {[lindex $parts 0] ne "OK"} { error "Invalid HDF5 provider response" }
    return $parts
}

proc ::GX::hdf5ProviderMetadata {token} {
    variable hdf5ProviderState
    if {$hdf5ProviderState($token,metadata) ne ""} { return $hdf5ProviderState($token,metadata) }
    set channel $hdf5ProviderState($token,channel)
    puts $channel META; flush $channel
    set head [hdf5ProviderReadLine $channel]
    if {[lindex $head 1] ne "META"} { error "Invalid HDF5 metadata response" }
    set count [lindex $head 2]
    set rawVariables {}; set groups {}
    for {set index 0} {$index < $count} {incr index} {
        if {[gets $channel line] < 0} { error "HDF5 metadata response ended early" }
        set parts [split $line "\t"]
        if {[lindex $parts 0] ne "VAR" || [llength $parts] != 16} { error "Invalid HDF5 variable metadata response" }
        set fields {}
        foreach value [lrange $parts 1 end] { lappend fields [datasetB64Decode $value] }
        lassign $fields locator dtype shape chunks compression name unit semanticRole dimensionIds coordinateRole axisKind axisOrigin axisStep groupId variableId
        lappend rawVariables [dict create locator $locator dtype $dtype rank [llength [datasetSchemaV3SplitIds $shape]] shape $shape chunks $chunks compression $compression name $name unit $unit semantic_role $semanticRole dimension_ids $dimensionIds coordinate_role $coordinateRole axis_kind $axisKind axis_origin $axisOrigin axis_step $axisStep group_id $groupId variable_id $variableId]
    }
    set groupCount [lindex $head 3]
    for {set index 0} {$index < $groupCount} {incr index} {
        if {[gets $channel line] < 0} { error "HDF5 group metadata response ended early" }
        set parts [split $line "\t"]
        if {[lindex $parts 0] ne "GROUP"} { error "Invalid HDF5 group metadata response" }
        lappend groups [datasetB64Decode [lindex $parts 1]]
    }
    if {[gets $channel line] < 0 || $line ne "END"} { error "Invalid HDF5 metadata terminator" }
    set datasetId $hdf5ProviderState($token,dataset_id)
    set mapped [dict create]; set rowCount -1
    set descriptor $hdf5ProviderState($token,descriptor)
    foreach schema [dict get $descriptor variables] {
        set variableId [dict get $schema variable_id]
        set wanted [dict get $descriptor locators $variableId]
        set match [dict create]
        foreach candidate $rawVariables {
            if {[info exists hdf5ProviderState($token,representation)] && $hdf5ProviderState($token,representation) && [dict get $candidate variable_id] eq $variableId} { set match $candidate; break }
            if {$wanted ne "" && [dict get $candidate locator] eq $wanted} { set match $candidate; break }
            if {$wanted eq "" && [dict get $candidate variable_id] eq $variableId} { set match $candidate; break }
            if {$wanted eq "" && [dict get $candidate name] eq [dict get $schema canonical]} { set match $candidate; break }
        }
        if {[dict size $match]} {
            dict set mapped $variableId $match
            set shape [datasetSchemaV3SplitIds [dict get $match shape]]
            if {[llength $shape] && ($rowCount < 0 || [lindex $shape 0] > $rowCount)} { set rowCount [lindex $shape 0] }
        }
    }
    set metadata [dict create variables $mapped row_count $rowCount provider_groups $groups]
    set hdf5ProviderState($token,metadata) $metadata
    return $metadata
}

proc ::GX::hdf5ProviderLocator {token variableId} {
    set metadata [hdf5ProviderMetadata $token]
    if {![dict exists $metadata variables $variableId]} { error "HDF5 storage has no mapping for variable_id $variableId" }
    return [dict get $metadata variables $variableId locator]
}

proc ::GX::hdf5ProviderDataResponse {channel expected} {
    set parts [hdf5ProviderReadLine $channel]
    if {[lindex $parts 1] ne "DATA" || [llength $parts] != 6} { error "Invalid HDF5 data response" }
    set dtype [datasetB64Decode [lindex $parts 2]]
    set shape [datasetB64Decode [lindex $parts 3]]
    set count [lindex $parts 4]
    set encoded [datasetB64Decode [lindex $parts 5]]
    # Preserve text/numeric cell representations (including a singleton NaN).
    # expr coerces a one-element result to a number and rejects NaN.
    if {$encoded eq ""} {set values {}} else {set values [split $encoded "\u001f"]}
    if {[llength $values] != $count} { error "HDF5 provider returned an inconsistent element count" }
    return [dict create dtype $dtype shape $shape values $values count $count synthesized 0]
}

proc ::GX::hdf5ProviderBinaryDataResponse {channel} {
    set parts [hdf5ProviderReadLine $channel]
    if {[lindex $parts 1] ne "BDATA" || [llength $parts] != 8} { error "Invalid HDF5 typed binary data response" }
    set dtype [string tolower [lindex $parts 2]]
    set endian [string tolower [lindex $parts 3]]
    set shape [datasetB64Decode [lindex $parts 4]]
    set count [lindex $parts 5]
    set byteCount [lindex $parts 6]
    set block [dict create __gxtxt_binary_block 1 dtype $dtype endian $endian shape $shape base64 [lindex $parts 7] byte_count $byteCount]
    datasetBinaryValidateBlock $block $count
    return [dict create dtype $dtype shape $shape binary_block $block count $count synthesized 0 transport typed_binary]
}

proc ::GX::hdf5ProviderResourceDataResponse {channel} {
    set parts [hdf5ProviderReadLine $channel]
    if {[lindex $parts 1] ne "RDATA" || [llength $parts]!=12} {error {Invalid HDF5 managed binary response}}
    lassign [lrange $parts 2 end] version dtype endian order shape count bytes id root sourceShape
    set resource [dict create version $version dtype $dtype endian $endian order $order shape $shape count $count byte_count $bytes resource_id $id resource_root [datasetB64Decode $root]]
    datasetBinaryResourceValidate $resource $count
    return [dict create dtype $dtype shape $sourceShape binary_resource $resource count $count synthesized 0 transport managed_binary]
}

proc ::GX::hdf5StorageProvider {operation token args} {
    variable hdf5ProviderState
    variable hdf5ProviderCounter
    variable scriptDir
    switch -- $operation {
        open {
            set context [lindex $args 0]
            set descriptor [expr {[dict exists $context descriptor] ? [dict get $context descriptor] : [_datasetAccessDescriptor [dict get $context session] [dict get $context dataset_id]]}]
            set binding [_datasetAccessProviderBinding $context $descriptor]
            set helper [file join $scriptDir core python gxtxt_hdf5_provider.py]
            if {![file isfile $helper]} { error "HDF5 provider helper is missing" }
            set python [runtimeToolRequired python]
            set command [list | $python -u $helper --file [dict get $context path] --session [dict get $context session]]
            if {[catch {set channel [open $command r+]} failure]} { error "HDF5 provider could not start: $failure" }
            # Python text stdout uses CRLF on Windows; normalize incoming
            # protocol records while keeping LF requests on the worker input.
            fconfigure $channel -encoding utf-8 -translation {auto lf} -buffering line
            if {[catch {set ready [hdf5ProviderReadLine $channel]} failure]} { catch {close $channel}; error $failure }
            if {[lindex $ready 1] ne "READY"} { catch {close $channel}; error "HDF5 provider did not become ready" }
            if {[catch {_datasetAccessCheckBinding $binding} failure]} {catch {close $channel};error $failure}
            set token "hdf5#[incr hdf5ProviderCounter]"
            set hdf5ProviderState($token,channel) $channel
            set hdf5ProviderState($token,dataset_id) [dict get $context dataset_id]
            set hdf5ProviderState($token,descriptor) $descriptor
            set hdf5ProviderState($token,source_binding) $binding
            set hdf5ProviderState($token,representation) [expr {[dict exists $context representation] && [dict get $context representation] ? 1 : 0}]
            set hdf5ProviderState($token,metadata) ""
            return $token
        }
        metadata { return [hdf5ProviderMetadata $token] }
        read_range {
            lassign $args variableIds start count
            set channel $hdf5ProviderState($token,channel)
            set out [dict create]
            foreach variableId $variableIds {
                set locator [hdf5ProviderLocator $token $variableId]
                puts $channel "READ\t[datasetB64Encode $locator]\t$start\t$count"; flush $channel
                set item [hdf5ProviderDataResponse $channel DATA]
                dict set item start $start
                dict set out $variableId $item
            }
            return $out
        }
        read_range_binary {
            lassign $args variableIds start count
            set channel $hdf5ProviderState($token,channel)
            set out [dict create]
            foreach variableId $variableIds {
                set locator [hdf5ProviderLocator $token $variableId]
                puts $channel "BREAD\t[datasetB64Encode $locator]\t$start\t$count"; flush $channel
                set item [hdf5ProviderBinaryDataResponse $channel]
                dict set item start $start
                dict set out $variableId $item
            }
            return $out
        }
        read_range_resource {
            lassign $args variableIds start count
            set channel $hdf5ProviderState($token,channel);set out {}
            foreach variableId $variableIds {
                set locator [hdf5ProviderLocator $token $variableId]
                puts $channel "RREAD\t[datasetB64Encode $locator]\t$start\t$count";flush $channel
                set item [hdf5ProviderResourceDataResponse $channel];dict set item start $start;dict set out $variableId $item
            }
            return $out
        }
        read_hyperslab_resource {
            lassign $args variableId starts counts
            set channel $hdf5ProviderState($token,channel);set locator [hdf5ProviderLocator $token $variableId]
            puts $channel "RHYPER\t[datasetB64Encode $locator]\t[datasetB64Encode [join $starts {;}]]\t[datasetB64Encode [join $counts {;}]]";flush $channel
            set item [hdf5ProviderResourceDataResponse $channel];dict set item starts $starts;dict set item counts $counts;return $item
        }
        release_resource {
            set id [lindex $args 0]
            if {![regexp {^[a-f0-9]{32}\.bin$} $id]} {error {Invalid Dataset resource identity}}
            set channel $hdf5ProviderState($token,channel);puts $channel "RELEASE\t$id";flush $channel
            set response [hdf5ProviderReadLine $channel]
            if {[lindex $response 1] ne "RELEASED"} {error {Invalid Dataset resource release response}}
            return 1
        }
        read_hyperslab {
            lassign $args variableId starts counts
            set channel $hdf5ProviderState($token,channel)
            set locator [hdf5ProviderLocator $token $variableId]
            puts $channel "HYPER\t[datasetB64Encode $locator]\t[datasetB64Encode [join $starts {;}]]\t[datasetB64Encode [join $counts {;}]]"; flush $channel
            set item [hdf5ProviderDataResponse $channel DATA]
            dict set item starts $starts
            dict set item counts $counts
            return $item
        }
        read_hyperslab_binary {
            lassign $args variableId starts counts
            set channel $hdf5ProviderState($token,channel)
            set locator [hdf5ProviderLocator $token $variableId]
            puts $channel "BHYPER\t[datasetB64Encode $locator]\t[datasetB64Encode [join $starts {;}]]\t[datasetB64Encode [join $counts {;}]]"; flush $channel
            set item [hdf5ProviderBinaryDataResponse $channel]
            dict set item starts $starts
            dict set item counts $counts
            return $item
        }
        diagnostics {
            set channel $hdf5ProviderState($token,channel)
            puts $channel STATS; flush $channel
            set parts [hdf5ProviderReadLine $channel]
            if {[lindex $parts 1] ne "STATS" || [llength $parts] != 10} { error "Invalid HDF5 diagnostics response" }
            set result [dict create process_id [lindex $parts 2] metadata_payload_elements [lindex $parts 3] payload_elements_read [lindex $parts 4] prefix_elements_scanned [lindex $parts 5] max_request_elements [lindex $parts 6] binary_blocks_read [lindex $parts 7] binary_bytes_read [lindex $parts 8] text_values_serialized [lindex $parts 9]]
            puts $channel RSTATS;flush $channel;set raw [hdf5ProviderReadLine $channel]
            if {[lindex $raw 1] ne "RSTATS" || [llength $raw]!=9} {error {Invalid HDF5 resource diagnostics}}
            foreach key {resources_written raw_bytes_written layout_copy_bytes serialization_copy_bytes provider_read_seconds resource_encode_seconds peak_outstanding_bytes} value [lrange $raw 2 end] {dict set result $key $value}
            return $result
        }
        close {
            if {![info exists hdf5ProviderState($token,channel)]} { return }
            set channel $hdf5ProviderState($token,channel)
            catch {puts $channel CLOSE; flush $channel; hdf5ProviderReadLine $channel}
            catch {close $channel}
            foreach name [array names hdf5ProviderState "$token,*"] { unset hdf5ProviderState($name) }
            return
        }
        default { error "Unsupported HDF5 provider operation: $operation" }
    }
}

::GX::datasetStorageProviderRegister csv ::GX::csvStorageProvider [dict create read_full 1 read_selected_variables 1 row_range_read 1 random_access 0 chunk_read 1 hyperslab_read 0 multidimensional 0 groups 0 implicit_axis 1]
::GX::datasetStorageProviderRegister hdf5 ::GX::hdf5StorageProvider [dict create read_full 1 read_selected_variables 1 row_range_read 1 random_access 1 chunk_read 1 hyperslab_read 1 multidimensional 1 groups 1 implicit_axis 1 typed_binary_read 1 managed_binary_read 1]
source [file join [file dirname [info script]] canonical_dataset_remote.tcl]
