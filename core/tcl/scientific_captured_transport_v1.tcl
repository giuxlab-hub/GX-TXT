# Binary ingress and captured vector egress for existing provider calls.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::ScientificTransportv1::resourceArray {reference shape {dtype float64}} {
    # Explicit byte view of a canonical owned resource, never a caller path.
    ::GX::interactiveDocumentResourceInfo $reference
    set count 1
    if {[llength $shape]<1||[llength $shape]>16} {_error {Managed array requires one to 16 dimensions}}
    foreach dimension $shape {if {![string is wideinteger -strict $dimension]||$dimension<1} {_error {Managed array dimensions must be positive integers}};set count [expr {$count*$dimension}]}
    set width [::GX::datasetBinaryTransportWidth $dtype]
    if {$count*$width!=[dict get $reference size_bytes]||$count*$width>536870912} {_error {Managed array byte length differs from shape/dtype or exceeds 512 MiB}}
    if {[dict exists $reference metadata dtype]&&[dict get $reference metadata dtype] ne $dtype} {_error {Managed array dtype differs from its resource declaration}}
    if {[dict exists $reference metadata endian]&&[dict get $reference metadata endian] ne "little"} {_error {Managed arrays require declared little-endian bytes}}
    return [dict create kind managed_array reference $reference shape $shape dtype $dtype]
}
proc ::GX::ScientificTransportv1::_binaryJson {node workspace serialName} {
    upvar 1 $serialName serial
    switch -- [dict get $node kind] {
        managed_array {
            set node [resourceArray [dict get $node reference] [dict get $node shape] [dict get $node dtype]]
            set reference [dict get $node reference];set shape [dict get $node shape];set dtype [dict get $node dtype]
            set width [::GX::datasetBinaryTransportWidth $dtype];set bytes [dict get $reference size_bytes];set count [expr {$bytes/$width}]
            set name [format %032x.bin [incr serial]]
            set reader [::GX::interactiveDocumentResourceOpenReader $reference];set channel {}
            try {
                set channel [open [file join $workspace $name] {WRONLY CREAT EXCL}];fconfigure $channel -translation binary -encoding binary
                while 1 {set page [::GX::interactiveDocumentResourceNext $reader];puts -nonewline $channel [dict get $page bytes];if {[dict get $page eof]} break}
            } finally {if {$channel ne {}} {close $channel};::GX::interactiveDocumentResourceCloseReader $reader}
            return "{\"kind\":\"binary\",\"descriptor\":{\"version\":2,\"dtype\":\"$dtype\",\"endian\":\"little\",\"order\":\"F\",\"shape\":[_jsonArray $shape 1],\"count\":$count,\"byte_count\":$bytes,\"resource_id\":\"$name\"}}"
        }
        array {
            set shape [dict get $node shape];set real [dict get $node real];set count 1
            if {[llength $shape]<1||[llength $shape]>16} {_error {Binary input requires one to 16 dimensions}}
            foreach d $shape {if {![string is integer -strict $d]||$d<1} {_error {Binary input requires positive dimensions}};set count [expr {$count*$d}]}
            if {$count!=[llength $real]} {_error {Binary input shape differs from its values}}
            set complex [dict exists $node imaginary];set width [expr {$complex?16:8}]
            if {$count*$width>512*1024*1024} {_error {Binary input exceeds 512 MiB}}
            if {$complex} {set imaginary [dict get $node imaginary];if {[llength $imaginary]!=$count} {_error {Binary real and imaginary shapes differ}}}
            # Preserve the established finite-input contract and signed zero.
            foreach value $real {_number $value}
            if {$complex} {foreach value $imaginary {_number $value}}
            set name [format %032x.bin [incr serial]]
            set channel [open [file join $workspace $name] {WRONLY CREAT EXCL}]
            try {
                fconfigure $channel -translation binary -encoding binary
                for {set start 0} {$start<$count} {incr start 65536} {
                    set last [expr {min($count-1,$start+65535)}]
                    set values [lrange $real $start $last]
                    if {$complex} {
                        set interleaved {};foreach re $values im [lrange $imaginary $start $last] {lappend interleaved $re $im};set values $interleaved
                    }
                    puts -nonewline $channel [binary format q* $values]
                }
            } finally {close $channel}
            set dtype [expr {$complex?"complex128":"float64"}]
            return "{\"kind\":\"binary\",\"descriptor\":{\"version\":2,\"dtype\":\"$dtype\",\"endian\":\"little\",\"order\":\"F\",\"shape\":[_jsonArray $shape 1],\"count\":$count,\"byte_count\":[expr {$width*$count}],\"resource_id\":\"$name\"}}"
        }
        cell {
            set items {};foreach item [dict get $node items] {lappend items [_binaryJson $item $workspace serial]}
            return "{\"kind\":\"cell\",\"items\":\[[join $items ,]\]}"
        }
        struct {
            set items {};dict for {key item} [dict get $node fields] {
                if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $key]} {_error {Invalid typed struct field}}
                lappend items "[_escape $key]:[_binaryJson $item $workspace serial]"
            }
            return "{\"kind\":\"struct\",\"fields\":{[join $items ,]}}"
        }
        default {return [_json $node]}
    }
}
proc ::GX::ScientificTransportv1::withCapturedColumns {moduleId function family action a b c options fields consumer} {
    # Provider-owned consumer runs inside this exact allocation lifetime. It must
    # import scientific artifacts through the canonical Document resource API.
    set descriptor [::GX::moduleField $moduleId descriptor {}]
    if {$descriptor eq {}||![file isfile $descriptor]} {_error {Scientific provider is unavailable}}
    if {[llength $fields]<1||[llength $fields]>128||[llength [lsort -unique $fields]]!=[llength $fields]} {_error {Captured field identities must be unique and bounded}}
    set encodedFields {};foreach field $fields {if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $field]} {_error {Invalid captured field identity}};lappend encodedFields [_escape $field]}
    if {[dict exists $options fields result_fields]} {_error {Captured calls preserve all registered facts; output projection is not accepted}}
    set moduleDir [file dirname $descriptor]
    set root [file normalize [file join $moduleDir .. .. ..]]
    set octave [::GX::runtimeToolRequired octave]
    set allocation [::GX::resourceManagementAllocate scientific_transport [dict create kind directory session $::GX::currentSession lifetime computation]]
    set workspace [dict get $allocation path];set serial 0
    try {
        set json "{\"family\":[_escape $family],\"action\":[_escape $action],\"binary_workspace\":[_escape $workspace],\"capture_fields\":\[[join $encodedFields ,]\],\"a\":[_binaryJson $a $workspace serial],\"b\":[_binaryJson $b $workspace serial],\"c\":[_binaryJson $c $workspace serial],\"options\":[_binaryJson $options $workspace serial]}"
        if {[string bytelength $json]>1048576} {_error {Captured control request exceeds 1 MiB}}
        set request [file join $workspace request.json];set response [file join $workspace response.ini]
        set channel [open $request {WRONLY CREAT EXCL}];fconfigure $channel -encoding utf-8 -translation lf
        try {puts -nonewline $channel $json} finally {close $channel}
        set failed [catch {exec $octave --quiet --no-gui [file join $root core octave gxtxt_scientific_provider_worker_v1.m] $function $moduleDir $request $response 2>@1} output]
        if {[file isfile $response]&&[file size $response]>1048576} {_error {Captured control response exceeds 1 MiB}}
        set result [readResult $response]
        if {$failed} {_error "Scientific captured worker failed: $output"}
        set inputBytes 0
        for {set i 1} {$i<=$serial} {incr i} {incr inputBytes [file size [file join $workspace [format %032x.bin $i]]]}
        set artifact [file join $workspace captured-columns.bin];set outputBytes 0
        if {[file isfile $artifact]} {set outputBytes [file size $artifact]}
        dict set result transport [dict create input_binary_bytes $inputBytes output_binary_bytes $outputBytes control_request_bytes [file size $request] control_response_bytes [file size $response] provider_calls 1]
        return [{*}$consumer $result [file join $workspace captured-columns.bin]]
    } finally {
        ::GX::resourceManagementRelease [dict get $allocation id]
        ::GX::resourceManagementCleanup [list [dict get $allocation id]]
    }
}

proc ::GX::ScientificTransportv1::stageDatasetResource {resource workspace} {
    # Transfer a live Dataset lease into an existing computation-owned directory.
    # The original lease remains owned/released by the Dataset Access caller.
    set resource [::GX::datasetBinaryResourceValidate $resource]
    if {[file pathtype $workspace] ne "absolute"||![file isdirectory $workspace]||[file type $workspace] ne "directory"} {_error {Managed array staging needs an absolute existing computation directory}}
    set source [file join [dict get $resource resource_root] [dict get $resource resource_id]]
    set target [file join $workspace [dict get $resource resource_id]]
    if {[file exists $target]} {_error {Refusing to overwrite a staged managed array}}
    set signature [::GX::sha256File $source];set copied 0
    try {
        file copy -- $source $target;set copied 1
        if {[file size $target]!=[dict get $resource byte_count]||[::GX::sha256File $target] ne $signature} {_error {Staged Dataset resource changed during transfer}}
        set descriptor [dict remove $resource resource_root]
        dict set descriptor shape [::GX::datasetSchemaV3SplitIds [dict get $resource shape]]
        return [dict create descriptor $descriptor sha256 $signature]
    } on error {message options} {
        if {$copied&&[file exists $target]} {file delete -- $target}
        return -options $options $message
    }
}
