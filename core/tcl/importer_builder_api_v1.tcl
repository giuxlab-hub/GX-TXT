# GX-TXT declarative Importer Builder API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# Definitions are user-level data; their parser is the bundled generic CSV
# canonicalizer and publication remains the existing Dataset transaction path.
namespace eval ::GX {
    variable importerBuilderDefinitions [dict create]
}

proc ::GX::importerBuilderRoot {} {
    return [file join [file dirname [configurationPath]] importers]
}

proc ::GX::importerBuilderDefaults {} {
    return [dict create id "" name "" version 1.0.0 description "" match_regex "" \
        delimiter auto header_rows 1 skip_leading 0 footer_rows 0 comment_prefix "" \
        encoding utf-8-sig decimal dot contract table.generic metadata_name "" \
        metadata_filename_regex "" metadata_header_regex "" mappings {}]
}

proc ::GX::_importerBuilderValidateFields {definition} {
    if {[string first \x00 $definition]>=0} {error {Importer definition contains NUL}}
    if {[string bytelength $definition]>262144} {error {Importer definition exceeds256KiB}}
    if {[catch {dict size $definition}]} { error "Importer definition must be a dictionary." }
    foreach key [dict keys $definition] {if {![dict exists [importerBuilderDefaults] $key]} {error "Unknown importer field '$key'"}}
    set d [dict merge [importerBuilderDefaults] $definition]
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} [dict get $d contract]]} {error {Invalid Dataset contract identity}}
    set id [dict get $d id]
    if {![regexp {^[a-z][a-z0-9_.-]*$} $id]} { error "Importer ID must begin with a lowercase letter and contain only letters, digits, '.', '_' or '-'." }
    if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+$} [dict get $d version]]} { error "Importer version must be major.minor.patch." }
    foreach key {name description comment_prefix encoding contract metadata_name} {
        if {[regexp {[\r\n]} [dict get $d $key]]} { error "Importer $key must be one line." }
    }
    if {[string trim [dict get $d name]] eq "" || [string trim [dict get $d contract]] eq ""} {
        error "Importer name and Dataset contract are required."
    }
    if {[dict get $d delimiter] ni {auto comma semicolon tab whitespace}} { error "Unsupported importer delimiter." }
    if {[dict get $d decimal] ni {dot comma}} { error "Unsupported decimal convention." }
    if {![regexp {^[A-Za-z0-9_-]+$} [dict get $d encoding]]} { error "Invalid encoding name." }
    foreach key {header_rows skip_leading footer_rows} {
        set n [dict get $d $key]
        if {![string is integer -strict $n] || $n < [expr {$key eq "header_rows" ? 1 : 0}]} {
            error "Importer $key is out of range."
        }
    }
    foreach key {match_regex metadata_filename_regex metadata_header_regex} {
        set pattern [dict get $d $key]
        if {$pattern ne "" && [catch {regexp -- $pattern ""} reason]} { error "Invalid $key: $reason" }
    }
    if {[dict get $d metadata_name] ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $d metadata_name]]} {
        error "Metadata name is invalid."
    }
    if {[llength [dict get $d mappings]]>512} {error {At most512 mappings are supported}}
    set seen {}
    set normalized {}
    foreach mapping [dict get $d mappings] {
        if {[catch {dict size $mapping}]} { error "Each column mapping must be a dictionary." }
        foreach key [dict keys $mapping] {if {$key ni {column name unit scale offset}} {error "Unknown mapping field '$key'"}}
        foreach key {column name} {
            if {![dict exists $mapping $key]} { error "Column mapping is missing $key." }
        }
        set column [dict get $mapping column]
        set name [dict get $mapping name]
        if {![string is integer -strict $column] || $column < 1} { error "Mapping source column must be >= 1." }
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $name]} { error "Invalid canonical Variable name '$name'." }
        if {$name in $seen} { error "Duplicate canonical Variable name '$name'." }
        lappend seen $name
        set mapping [dict merge [dict create unit "" scale "" offset ""] $mapping]
        if {[regexp {[\r\n]} [dict get $mapping unit]]} { error "Unit must be one line." }
        foreach key {scale offset} {
            set value [dict get $mapping $key]
            if {$value ne "" && (![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite)} { error "Mapping $key must be finite numeric." }
        }
        lappend normalized $mapping
    }
    if {![llength $normalized]} { error "Define at least one source column mapping." }
    dict set d mappings $normalized
    return $d
}

proc ::GX::importerBuilderWrite {definition path {expected legacy}} {
    set d [importerBuilderValidate $definition]
    file mkdir [file dirname $path]
    set temp "${path}.[pid].[clock clicks].tmp"
    set ch [open $temp {WRONLY CREAT EXCL}]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT Importer Builder API v1"
        puts $ch "\[importer\]"
        foreach key {id name version description match_regex delimiter header_rows skip_leading footer_rows comment_prefix encoding decimal contract metadata_name metadata_filename_regex metadata_header_regex} {
            putKV $ch $key [dict get $d $key]
        }
        putKV $ch mapping_count [llength [dict get $d mappings]]
        set i 0
        foreach mapping [dict get $d mappings] {
            incr i
            puts $ch "\n\[mapping.$i\]"
            foreach key {column name unit scale offset} { putKV $ch $key [dict get $mapping $key] }
        }
    } on error {message options} {
        catch {file delete -- $temp}
        return -options $options $message
    } finally { close $ch }
    try {
        if {$expected ne {legacy}} {
            if {![catch {file lstat $path st}]} {
                _importerBuilderFileGuard $path
                if {$expected eq {absent} || [sha256File $path] ne $expected} {error {Importer changed while preparing Save; draft retained}}
                file attributes $temp -permissions [file attributes $path -permissions]
            } elseif {$expected ne {absent}} {error {Importer was removed while preparing Save; draft retained}}
        }
        if {$expected eq {absent}} {file rename -- $temp $path} else {file rename -force -- $temp $path}
    } finally {if {[file exists $temp]} {file delete -- $temp}}
    return $path
}

proc ::GX::importerBuilderRead {path} {
    _importerBuilderFileGuard $path
    set ch [open $path rb];try {set raw [read $ch 1048577]} finally {close $ch}
    # Existing INI escaping/parser remains the authority; validate structure first
    # so malformed/duplicate lines cannot silently disappear in parseIni.
    set decoded [_importerBuilderWorker ini [dict create source [file normalize $path]]]
    set text [dict get $decoded text]
    if {[encoding convertto utf-8 $text] ne $raw || [string first \x00 $text]>=0} {error {Importer INI must be UTF-8 text}}
    set section {};set seen {};set sections {};set lineNo 0
    foreach line [split $text \n] {
        incr lineNo;set line [string trim $line]
        if {$line eq {} || [string index $line 0] in {\; #}} continue
        if {[regexp {^\[(importer|mapping\.[1-9][0-9]*)\]$} $line -> section]} {
            if {$section in $sections} {error "Duplicate INI section at line $lineNo"};lappend sections $section;continue
        }
        if {$section eq {} || ![regexp {^([^=]+)=(.*)$} $line -> key value]} {error "Malformed importer INI line $lineNo"}
        set key [string trim $key];set identity $section.$key
        if {$identity in $seen} {error "Duplicate importer INI field at line $lineNo"};lappend seen $identity
        set allowed [expr {$section eq {importer}?[concat [dict keys [importerBuilderDefaults]] mapping_count]:{column name unit scale offset}}]
        if {$key ni $allowed || $key eq {mappings}} {error "Unknown importer INI field '$identity'"}
    }
    set ini [parseIni $path]
    if {[sha256File $path] ne [dict get $decoded ini_sha256]} {error {Importer definition changed while parsing; reload it}}
    set d [importerBuilderDefaults]
    foreach key [dict keys $d] {if {$key ne {mappings} && [dict exists $ini importer.$key]} {dict set d $key [dict get $ini importer.$key]}}
    if {![dict exists $ini importer.mapping_count]} {error {Importer mapping_count is missing}}
    set count [dict get $ini importer.mapping_count]
    if {![string is integer -strict $count] || $count<1 || $count>512} {error {Importer mapping count must be1..512}}
    set mappings {}
    for {set i 1} {$i<=$count} {incr i} {
        set m {};foreach key {column name unit scale offset} {if {[dict exists $ini mapping.$i.$key]} {dict set m $key [dict get $ini mapping.$i.$key]}}
        lappend mappings $m
    }
    foreach section $sections {if {$section ne {importer} && [scan $section {mapping.%d}]>$count} {error {Importer contains undeclared mapping sections}}}
    dict set d mappings $mappings
    return [importerBuilderValidate $d]
}

proc ::GX::importerBuilderReload {} {
    variable importerBuilderDefinitions;variable importerBuilderDiagnostics
    set importerBuilderDefinitions {};set importerBuilderDiagnostics {}
    foreach path [lsort -dictionary [glob -nocomplain -directory [importerBuilderRoot] *.ini]] {
        if {[catch {
            set d [importerBuilderRead $path]
            if {[file tail $path] ne "[dict get $d id].ini"} {error {Filename differs from declared importer ID}}
        } reason]} {lappend importerBuilderDiagnostics [dict create path $path error $reason];continue}
        dict set importerBuilderDefinitions [dict get $d id] $d
    }
    return $importerBuilderDefinitions
}

proc ::GX::importerBuilderGet {id} {
    variable importerBuilderDefinitions
    if {![dict exists $importerBuilderDefinitions $id]} { importerBuilderReload }
    if {![dict exists $importerBuilderDefinitions $id]} { error "Unknown importer definition '$id'." }
    return [dict get $importerBuilderDefinitions $id]
}

proc ::GX::importerBuilderSave {definition {expected_sha256 legacy}} {
    variable importerBuilderDefinitions
    set d [importerBuilderValidate $definition];set id [dict get $d id]
    set path [file join [importerBuilderRoot] "$id.ini"]
    file mkdir [file dirname $path]
    _importerBuilderMutate $path $expected_sha256 [list ::GX::importerBuilderWrite $d $path $expected_sha256]
    dict set importerBuilderDefinitions $id $d
    return $id
}

proc ::GX::importerBuilderRemove {id {expected_sha256 legacy}} {
    variable importerBuilderDefinitions
    if {![regexp {^[a-z][a-z0-9_.-]*$} $id]} {error {Invalid importer ID}}
    set path [file join [importerBuilderRoot] "$id.ini"]
    _importerBuilderMutate $path $expected_sha256 [list file delete -- $path]
    if {[dict exists $importerBuilderDefinitions $id]} {dict unset importerBuilderDefinitions $id}
}

proc ::GX::importerBuilderDuplicate {id newId} {
    set d [importerBuilderGet $id];dict set d id $newId;dict set d name "[dict get $d name] copy"
    return [importerBuilderSave $d absent]
}

proc ::GX::importerBuilderExport {id path} {
    set d [importerBuilderGet $id]
    file mkdir [file dirname $path]
    return [_importerBuilderMutate $path absent [list ::GX::importerBuilderWrite $d $path absent]]
}

proc ::GX::importerBuilderImport {path} {
    set d [importerBuilderRead $path]
    # Importing recipe INI is data portability, not scientific execution.
    return [importerBuilderSave $d absent]
}

proc ::GX::importerBuilderCommand {definition input output} {
    set d [importerBuilderValidate $definition]
    set helper [file join $::GX::scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
    set command [list [runtimeToolResolve python] $helper --input $input --output $output \
        --delimiter [dict get $d delimiter] --header-rows [dict get $d header_rows] \
        --encoding [dict get $d encoding] --skip-leading [dict get $d skip_leading] \
        --footer-rows [dict get $d footer_rows] --comment-prefix [dict get $d comment_prefix] \
        --decimal [dict get $d decimal]]
    if {[dict get $d delimiter] eq "whitespace"} { lappend command --whitespace }
    foreach mapping [dict get $d mappings] {
        set name [dict get $mapping name]
        lappend command --map "[dict get $mapping column]=$name"
        foreach {key flag} {scale --scale offset --offset} {
            if {[dict get $mapping $key] ne ""} { lappend command $flag "$name=[dict get $mapping $key]" }
        }
    }
    return $command
}

proc ::GX::importerBuilderTest {definition sample} {
    # Compatibility entrypoint for headless callers. GUI uses Request directly.
    set key ::GX::ImporterBuilder::sync[incr ::GX::ImporterBuilder::serial]
    importerBuilderRequest test $definition $sample [list ::GX::_importerBuilderSyncDone $key]
    vwait $key
    set response [set $key];unset $key
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::_importerBuilderSyncDone {key token response} {set $key $response}

proc ::GX::importerBuilderMetadata {definition source} {
    set result [importerBuilderEffectiveSnapshot $definition $source];set d [dict get $result definition]
    return [importerBuilderMetadataFromText $d $source [dict get $result header_text]]
}

# P032 additive immutable requests and CAS; old recipe entrypoints stay callable.
namespace eval ::GX::ImporterBuilder {variable requests {};variable serial 0}
proc ::GX::_importerBuilderWorkerCommand {operation} {
    return [list [runtimeToolResolve python] -I -B [file join $::GX::scriptDir core python gxtxt_importer_builder_worker.py] $operation]
}
proc ::GX::_importerBuilderWorker {operation request} {
    set response [exec -- {*}[ _importerBuilderWorkerCommand $operation] << $request]
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::importerBuilderSnapshot {definition {source {}}} {
    set d [_importerBuilderValidateFields $definition]
    set request [dict create definition $d]
    if {$source ne {}} {dict set request source [file normalize $source]}
    set receipt [_importerBuilderWorker snapshot $request]
    dict set receipt contract_state [importerBuilderContractState [dict get $d contract]]
    return $receipt
}
proc ::GX::importerBuilderEffectiveSnapshot {definition source} {
    set packet [importerBuilderSnapshot $definition $source]
    set payload [dict create definition [dict get $packet definition] source [file normalize $source] expected_source_identity [dict get $packet source_identity] expected_config_sha256 [dict get $packet config_sha256] expected_parser_sha256 [dict get $packet parser_sha256]]
    return [_importerBuilderWorker header $payload]
}
proc ::GX::importerBuilderValidate {definition} {return [dict get [importerBuilderSnapshot $definition] definition]}
proc ::GX::importerBuilderContractState {id} {
    if {![llength [info commands ::GX::contractRegistryKnown]]} {return UNKNOWN_UNAVAILABLE}
    contractRegistryIds
    if {![contractRegistryKnown $id]} {return UNKNOWN_UNAVAILABLE}
    if {[contractRegistryField $id providers {}] eq {} && [contractRegistryField $id producers {}] eq {}} {return UNKNOWN_UNAVAILABLE}
    if {![contractSatisfies $id table.generic]} {return INCOMPATIBLE_TABLE}
    return KNOWN_COMPATIBLE
}
proc ::GX::importerBuilderRequireExecutable {definition} {
    set state [importerBuilderContractState [dict get $definition contract]]
    if {$state ne {KNOWN_COMPATIBLE}} {error "Dataset contract '[dict get $definition contract]': $state; install its compatible provider before Test/Import"}
}
proc ::GX::_importerBuilderFileGuard {path} {
    if {![file isfile $path] || [file type $path] eq {link}} {error {Importer definition must be an ordinary file}}
    file stat $path st
    if {$st(nlink)!=1 || $st(size)>1048576} {error {Importer definition must be unlinked and within1MiB}}
}
proc ::GX::importerBuilderDescribe {id} {
    if {![regexp {^[a-z][a-z0-9_.-]*$} $id]} {error {Invalid importer ID}}
    set path [file join [importerBuilderRoot] "$id.ini"]
    _importerBuilderFileGuard $path
    return [_importerBuilderDescribeFromPath $id $path]
}
proc ::GX::_importerBuilderDescribeFromPath {id path} {
    _importerBuilderFileGuard $path
    set before [sha256File $path];set d [importerBuilderRead $path]
    if {[sha256File $path] ne $before} {error {Importer definition changed during Read}}
    return [dict create definition $d file_sha256 $before contract_state [importerBuilderContractState [dict get $d contract]]]
}
proc ::GX::_importerBuilderMutate {path expected command} {
    set lock "$path.lock"
    if {[catch {set ch [open $lock {WRONLY CREAT EXCL}]}]} {error {Importer is being changed; retry after its owner finishes}}
    close $ch
    try {
        if {[file type [file dirname $path]] eq {link}} {error {Importer directory is a link}}
        if {![catch {file lstat $path st}]} {
            _importerBuilderFileGuard $path
            if {$expected eq {absent} || ($expected ne {legacy} && [sha256File $path] ne $expected)} {error {Importer changed on disk; reload or duplicate; your draft is retained}}
        } elseif {$expected ni {legacy absent}} {error {Importer was removed; your draft is retained}}
        return [uplevel #0 $command]
    } finally {file delete -- $lock}
}
proc ::GX::importerBuilderMetadataFromText {definition source header} {
    set name [dict get $definition metadata_name];if {$name eq {}} {return {}}
    set value {};set pattern [dict get $definition metadata_filename_regex]
    if {$pattern ne {}} {regexp -- $pattern [file tail $source] -> value}
    if {$value eq {} && [dict get $definition metadata_header_regex] ne {}} {regexp -- [dict get $definition metadata_header_regex] $header -> value}
    if {$value eq {}} {return {}}
    return [dict create importer_meta_$name $value]
}
proc ::GX::_importerBuilderAdmission {} {
    variable ::GX::ImporterBuilder::requests
    set pending 0
    dict for {token record} $requests {
        if {[dict get $record status] in {allocating running} || ([dict get $record allocation] ne {} && ![datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $record cleanup {}] ok 0])} {incr pending}
    }
    if {$pending>=8} {error {At most8 active or unreleased CSV requests; resolve retained resource cleanup before starting more}}
}
proc ::GX::importerBuilderReloadAsync {callback {progressCallback {}}} {
    variable ::GX::ImporterBuilder::requests;variable ::GX::ImporterBuilder::serial
    _importerBuilderAdmission
    set root [file normalize [importerBuilderRoot]]
    set identity absent
    if {[file exists $root]} {if {![file isdirectory $root] || [file type $root] eq {link}} {error {Recipe inventory root must be an ordinary directory}};file stat $root st;set identity [list $st(dev) $st(ino)]}
    set pins {}
    foreach relative {core/tcl/importer_builder_api_v1.tcl core/tcl/importer_builder_inventory_request.tcl core/python/gxtxt_importer_builder_worker.py app/configuration_manifest.tcl} {dict set pins $relative [sha256File [file join $::GX::scriptDir $relative]]}
    set token importer-builder#[incr serial]
    set record [dict create status allocating packet [dict create root $root root_identity $identity code_pins $pins file_limit 64 entry_limit 256] source {} operation inventory callback $callback progress_callback $progressCallback request {} allocation {} timer {} cancelled 0]
    dict set requests $token $record
    resourceManagementAsync allocate {subsystem importer_builder kind directory category temporary lifetime computation expected_bytes 1048576 retention_seconds 0} [list ::GX::_importerBuilderAllocated $token]
    return $token
}
proc ::GX::importerBuilderRequest {operation definition source callback {progressCallback {}}} {
    variable ::GX::ImporterBuilder::requests;variable ::GX::ImporterBuilder::serial
    if {$operation ni {preview test}} {error {Choose Preview or Test}}
    _importerBuilderAdmission
    set packet [importerBuilderSnapshot $definition $source]
    importerBuilderRequireExecutable [dict get $packet definition]
    set token importer-builder#[incr serial]
    set record [dict create status allocating packet $packet source [file normalize $source] operation $operation callback $callback progress_callback $progressCallback request {} allocation {} timer {} cancelled 0]
    dict set requests $token $record
    resourceManagementAsync allocate {subsystem importer_builder kind directory category temporary lifetime computation expected_bytes 1048576 retention_seconds 0} [list ::GX::_importerBuilderAllocated $token]
    return $token
}
proc ::GX::_importerBuilderAllocated {token code allocation} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token]} return
    if {$code || ![dict exists $allocation id]} {_importerBuilderDone $token [dict create ok 0 error "CSV temporary allocation failed: $allocation"];return}
    dict set requests $token allocation $allocation
    if {[dict get $requests $token cancelled]} {_importerBuilderDone $token {ok 0 error Cancelled};return}
    set record [dict get $requests $token];set packet [dict get $record packet]
    if {[dict get $record operation] eq {inventory}} {
        set payload [dict merge $packet [dict create resource_root [dict get $allocation path]]]
    } else {
        set payload [dict create definition [dict get $packet definition] source [dict get $record source] root [dict get $allocation path] expected_source_identity [dict get $packet source_identity] expected_config_sha256 [dict get $packet config_sha256] expected_parser_sha256 [dict get $packet parser_sha256]]
    }
    if {[catch {set id [scriptJobAsync [_importerBuilderWorkerCommand [dict get $record operation]] $payload [list ::GX::_importerBuilderDone $token] {timeout_ms 3600000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {CSV Builder inspection}}]} reason]} {_importerBuilderDone $token [dict create ok 0 error $reason];return}
    dict set requests $token request $id;dict set requests $token status running
    _importerBuilderTick $token
}
proc ::GX::_importerBuilderTick {token} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token] || [dict get $requests $token status] ne {running}} return
    set record [dict get $requests $token];set path [file join [dict get $record allocation path] progress.tcldict]
    if {[file isfile $path] && [file type $path] ne {link} && [file size $path]<=8192} {
        if {![catch {set ch [open $path r];try {set value [read $ch 8193]} finally {close $ch};dict size $value}]} {
            dict set requests $token progress $value
            if {[dict get $record progress_callback] ne {}} {uplevel #0 [list {*}[dict get $record progress_callback] $token $value]}
        }
    }
    if {[dict exists $requests $token] && [dict get $requests $token status] eq {running}} {dict set requests $token timer [after 100 [list ::GX::_importerBuilderTick $token]]}
}
proc ::GX::_importerBuilderDone {token response} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token]} return
    set record [dict get $requests $token]
    if {[dict get $record timer] ne {}} {after cancel [dict get $record timer]}
    if {[dict get $record cancelled]} {set response {ok 0 error {CSV request cancelled} error_type cancelled}}
    dict set requests $token status [expr {[dict get $response ok]?{completed}:([dict get $record cancelled]?{cancelled}:{failed})}]
    dict set requests $token response $response;dict set requests $token timer {}
    if {[dict get $record allocation] ne {}} {
        set id [dict get $record allocation id]
        resourceManagementAsync release [list resource_id $id state verified_orphan retention_seconds 0] [list ::GX::_importerBuilderReleased $token $id]
    }
    if {[dict get $record callback] ne {}} {uplevel #0 [list {*}[dict get $record callback] $token $response]}
    _importerBuilderPrune
}
proc ::GX::_importerBuilderCleanupFailed {token response} {
    variable ::GX::ImporterBuilder::requests
    set old [dict get $requests $token]
    # Keep the owned allocation and bounded diagnostic, never a full source/config
    # packet or response after cleanup failure. Admission bounds unreleased rows.
    set compact [dict create status cleanup_failed payload_retained 0 terminal_status [datasetPublicationV2DictDefault $old terminal_status [dict get $old status]] operation [dict get $old operation] allocation [dict get $old allocation] cancelled [dict get $old cancelled] request {} timer {} cleanup [dict create ok 0 status recovery_required error [string range $response 0 2047]]]
    dict set requests $token $compact
}
proc ::GX::_importerBuilderReleased {token id code response} {
    if {$code} {_importerBuilderCleanupFailed $token $response;return}
    resourceManagementAsync cleanup [list $id] [list ::GX::_importerBuilderCleaned $token]
}
proc ::GX::_importerBuilderCleaned {token code response} {
    variable ::GX::ImporterBuilder::requests
    if {$code} {_importerBuilderCleanupFailed $token $response;return}
    dict set requests $token cleanup [dict create ok 1 receipt [string range $response 0 4095]]
    if {[dict get $requests $token status] eq {cleanup_failed}} {dict set requests $token status [dict get $requests $token terminal_status]}
    _importerBuilderPrune
}
proc ::GX::_importerBuilderForgettable {record} {
    return [expr {[dict get $record status] in {completed failed cancelled} && ([dict get $record allocation] eq {} || [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $record cleanup {}] ok 0])}]
}
proc ::GX::_importerBuilderPrune {} {
    variable ::GX::ImporterBuilder::requests
    set terminal {}
    dict for {token record} $requests {if {[_importerBuilderForgettable $record]} {lappend terminal $token}}
    foreach token [lrange $terminal 0 end-16] {dict unset requests $token}
}
proc ::GX::importerBuilderRequestForget {token} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token] || ![_importerBuilderForgettable [dict get $requests $token]]} {return 0}
    dict unset requests $token;return 1
}
proc ::GX::importerBuilderRequestRetryCleanup {token} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token] || [dict get $requests $token status] ne {cleanup_failed} || [datasetPublicationV2DictDefault [dict get $requests $token cleanup] retrying 0]} {return 0}
    set id [dict get $requests $token allocation id]
    dict set requests $token cleanup retrying 1
    resourceManagementAsync release [list resource_id $id state verified_orphan retention_seconds 0] [list ::GX::_importerBuilderReleased $token $id]
    return 1
}

proc ::GX::importerBuilderCancel {token} {
    variable ::GX::ImporterBuilder::requests
    if {![dict exists $requests $token] || [dict get $requests $token status] in {completed failed cancelled cleanup_failed}} {return 0}
    dict set requests $token cancelled 1
    set request [dict get $requests $token request];if {$request ne {}} {scriptJobRequestCancel $request cancelled}
    return 1
}
proc ::GX::importerBuilderRequestInspect {token} {
    if {![dict exists $::GX::ImporterBuilder::requests $token]} {error {Unknown CSV Builder request}}
    return [dict get $::GX::ImporterBuilder::requests $token]
}
