# SPDX-License-Identifier: GPL-3.0-or-later
# Private fixed-pair parent. Public Document/Resource/Job owners keep authority.
# No authored command, path, callback, native handle or new persistent registry.
namespace eval ::GX::PCBPair {
    variable workerSha b0c22d4abac4850d84bbafa1f623e53fea0dc7c476dcf04b84971c53d17ac837
    variable licenseSha 6532771f09b24eadc3e75b9c2ecb035c38ebea295542833e892fab9018c678da
    variable pairStamp 30b62781f742c4e27e5032325f3bf69aabee749c58797ce1c5dc2a273f656ed1
    variable approved [dict create board 550d7d86ff63cd1e7672fb5c9a4860798ff868ece50b7e40ee9aedff153445ca schematic f073caca2fc4fb4d24c942dbdb2dfb9edee17221adfd8ed175b7ceb359be5639]
    variable names {board.original.brd schematic.original.sch SOURCE_LICENSE.md attribution.json index.json index.tcldict layout.json layout.tcldict receipt.json receipt.tcldict}
}
proc ::GX::_pcbPairRequire {condition message} {if {!$condition} {return -code error -errorcode {GXTXT PCB PAIR_REFUSED} $message}}
proc ::GX::_pcbPairKeys {value keys} {
    _pcbPairRequire [expr {![catch {dict size $value}] && [llength $value]==2*[dict size $value] && [lsort [dict keys $value]] eq [lsort $keys]}] {PCB data has an unsupported or duplicate field}
}
proc ::GX::_pcbPairInteger {value minimum maximum} {
    _pcbPairRequire [expr {[string is entier -strict $value] && $value>=$minimum && $value<=$maximum}] {PCB integer exceeds its finite contract}
    return $value
}
proc ::GX::_pcbPairSha {value} {
    _pcbPairRequire [regexp {^[0-9a-f]{64}$} $value] {PCB SHA256 is invalid}
    return $value
}
proc ::GX::_pcbPairIdentity {identity} {
    _pcbPairKeys $identity {device inode size mode uid gid links mtime_ns ctime_ns}
    foreach key {device inode size mode uid gid links} {_pcbPairInteger [dict get $identity $key] 0 18446744073709551615}
    foreach key {mtime_ns ctime_ns} {_pcbPairInteger [dict get $identity $key] -9223372036854775808 9223372036854775807}
    _pcbPairRequire [expr {[dict get $identity links]==1 && [dict get $identity size]<=4194304 && [dict get $identity mode]<=4095}] {PCB capture is outside the ordinary single-link source contract}
    return $identity
}
proc ::GX::_pcbPairRootStamp {path} {
    _pcbPairRequire [expr {[file pathtype $path] eq {absolute} && [file normalize $path] eq $path}] {PCB owner needs its real absolute root}
    set current [lindex [file split $path] 0]
    foreach part [lrange [file split $path] 1 end] {
        set current [file join $current $part];file lstat $current s
        _pcbPairRequire [expr {$s(type) eq {directory}}] {PCB owner root has a replaced or linked component}
    }
    file lstat $path s
    return [list $path $s(dev) $s(ino) $s(mode) $s(uid) $s(gid)]
}
proc ::GX::_pcbPairFileStamp {path maximum {private 0}} {
    _pcbPairRequire [expr {[file pathtype $path] eq {absolute} && [file normalize $path] eq $path}] {PCB artifact path is not real and absolute}
    _pcbPairRootStamp [file dirname $path]
    file lstat $path s
    _pcbPairRequire [expr {$s(type) eq {file} && $s(nlink)==1 && $s(size)>=0 && $s(size)<=$maximum}] {PCB artifact is not a bounded ordinary single-link file}
    if {$private} {_pcbPairRequire [expr {[file owned $path] && ($s(mode)&07777)==0600}] {PCB staged artifact must remain owned0600}}
    return [list $s(dev) $s(ino) $s(size) $s(mode) $s(uid) $s(gid) $s(nlink) $s(mtime) $s(ctime)]
}
proc ::GX::_pcbPairExclusiveBytes {path bytes} {
    set channel [open $path {WRONLY CREAT EXCL} 0600]
    try {fconfigure $channel -translation binary -encoding binary;puts -nonewline $channel $bytes;flush $channel} finally {close $channel}
    return $path
}
proc ::GX::_pcbPairCapture {path envelope name} {
    documentNativeEnsure
    _pcbPairRequire [expr {[llength [info commands ::GX::NativeDocument::sourceCapture]]==1}] {Install the matching native Document library with the private PCB capture capability}
    _pcbPairRequire [expr {[regexp {^[a-z0-9_.-]+$} $name] && [string first \x00 $path]<0 && [string length $path]<=4096 && ![regexp {[\r\n]} $path]}] {PCB source pathname is unsupported}
    set captured [::GX::NativeDocument::sourceCapture $path]
    _pcbPairKeys $captured {schema identity bytes}
    _pcbPairRequire [expr {[dict get $captured schema] eq {gxtxt.native_source_capture.v1}}] {Native PCB capture schema is unsupported}
    set identity [_pcbPairIdentity [dict get $captured identity]]
    set bytes [dict get $captured bytes]
    _pcbPairRequire [expr {[string length $bytes]==[dict get $identity size] && [string length $bytes]<=4194304 && [binary format a* $bytes] eq $bytes}] {Native PCB capture did not return exact binary bytes}
    set snapshot [file join $envelope $name]
    _pcbPairExclusiveBytes $snapshot $bytes
    set before [_pcbPairFileStamp $snapshot 4194304 1]
    set sha [_pcbPairSha [sha256File $snapshot]]
    _pcbPairRequire [expr {[_pcbPairFileStamp $snapshot 4194304 1] eq $before}] {Owned capture snapshot changed during hashing}
    return [dict create path $path identity $identity bytes [string length $bytes] sha256 $sha snapshot $snapshot]
}
proc ::GX::_pcbPairSameCapture {left right} {
    foreach key {path bytes sha256} {if {[dict get $left $key] ne [dict get $right $key]} {return 0}}
    if {![_pcbPairSameIdentity [dict get $left identity] [dict get $right identity]]} {return 0}
    return 1
}
proc ::GX::_pcbPairSameIdentity {left right} {
    _pcbPairIdentity $left;_pcbPairIdentity $right
    foreach key {device inode size mode uid gid links mtime_ns ctime_ns} {if {[dict get $left $key] ne [dict get $right $key]} {return 0}}
    return 1
}
proc ::GX::_pcbPairProjectCapture {project envelope phase} {
    set result {}
    foreach {name short} {handlers.cpp source design.gxtxt-viewer design project.json project} {
        dict set result $short [_pcbPairCapture [file join $project $name] $envelope "$phase-project-$short.bin"]
    }
    return $result
}
proc ::GX::_pcbPairStorageAdmit {allocation} {
    foreach key {id path envelope category retention_seconds managed} {_pcbPairRequire [dict exists $allocation $key] {Incomplete managed PCB allocation}}
    set path [dict get $allocation path]
    _pcbPairRequire [expr {[dict get $allocation managed] && [dict get $allocation category] eq {retained_diagnostic} && [dict get $allocation retention_seconds]==0 && [dict get $allocation envelope] eq $path}] {PCB evidence requires an actual retained diagnostic directory allocation}
    _pcbPairRootStamp $path;file lstat $path s;file lstat /srv/gxtxt/agents raid
    _pcbPairRequire [expr {[file owned $path] && ($s(mode)&07777)==0700 && $s(dev)==$raid(dev) && [string first /srv/gxtxt/agents/ $path]==0}] {Configure managed Resource storage on the supported task RAID with private0700 directories; this fixed-pair adapter cannot use other storage}
    set channel [open /proc/self/mountinfo r]
    try {set mountinfo [read $channel 1048577]} finally {close $channel}
    _pcbPairRequire [expr {[string length $mountinfo]<=1048576}] {Resource mount information exceeds the supported bound}
    set best {};set bestLength -1
    foreach line [split $mountinfo \n] {
        set halves [split $line { }];set separator [lsearch -exact $halves -]
        if {$separator<6 || [llength $halves]<$separator+3} continue
        set mount [lindex $halves 4]
        # Escaped mount spellings are outside this deliberately fixed capability.
        if {[string first \\ $mount]>=0} continue
        if {$path eq $mount || [string first "$mount/" $path]==0 || $mount eq {/}} {
            if {[string length $mount]>$bestLength} {set bestLength [string length $mount];set best [list $mount [lindex $halves [expr {$separator+1}]] [lindex $halves [expr {$separator+2}]]]}
        }
    }
    _pcbPairRequire [expr {[llength $best]==3 && [lindex $best 0] eq {/srv/gxtxt/agents} && [lindex $best 1] eq {ext4} && [string match /dev/md* [lindex $best 2]]}] {PCB fixed-pair import requires actual managed Resource storage on the task MD/ext4 RAID; configure the existing Resource owner or use another supported source facility}
    set staged [file join $path staged]
    _pcbPairRequire [expr {[catch {file lstat $staged ignored}]}] {PCB worker child must be absent before the one request}
    return $staged
}
proc ::GX::_pcbPairRequestJson {packet} {
    set fields [list [format {"schema":"gxtxt.eagle_pair_worker_request.v1","request_id":%s,"workdir":%s} [viewerDevelopmentJsonString [dict get $packet epoch]] [viewerDevelopmentJsonString [dict get $packet staged]]]]
    foreach role {board schematic} {
        set source [dict get $packet sources $role];set ids {}
        dict for {key value} [dict get $source identity] {lappend ids "[viewerDevelopmentJsonString $key]:$value"}
        lappend fields [format {%s:{"path":%s,"sha256":%s,"bytes":%s,"identity":{%s}}} [viewerDevelopmentJsonString $role] [viewerDevelopmentJsonString [dict get $source path]] [viewerDevelopmentJsonString [dict get $source sha256]] [dict get $source bytes] [join $ids ,]]
    }
    set json "\{[join $fields ,]\}"
    _pcbPairRequire [expr {[string length [encoding convertto utf-8 $json]]<=16384}] {PCB request exceeds16KiB}
    return $json
}
proc ::GX::_pcbPairCurrent {packet} {
    if {[catch {
        _pcbPairRequire [expr {[interactiveDocumentSessionToken] eq [dict get $packet session_token] && [_pcbPairRootStamp [_interactiveDocumentRequireSession]] eq [dict get $packet session_root]}] {PCB Session owner changed}
        _pcbPairRequire [_viewerGuiPCBCurrent [dict get $packet window] [dict get $packet form] [dict get $packet epoch] [dict get $packet authority]] {PCB form or admission changed}
        if {[dict exists $packet allocation]} {_pcbPairRequire [expr {[_pcbPairRootStamp [dict get $packet allocation path]] eq [dict get $packet allocation_root]}] {PCB allocation identity changed}}
    }]} {return 0}
    return 1
}
proc ::GX::_pcbPairStore {packet} {
    set window [dict get $packet window];set form [dict get $packet form]
    if {[dict exists $::GX::ViewerGui::instances $window pcb_source_forms $form epoch] && [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form epoch] eq [dict get $packet epoch]} {
        dict set ::GX::ViewerGui::instances $window pcb_source_forms $form parent $packet
    }
    return $packet
}
proc ::GX::_pcbPairNotify {packet detail} {
    _pcbPairStore $packet
    catch {_viewerGuiPCBProgress [dict get $packet window] [dict get $packet form] [dict get $packet epoch] [dict get $packet state] $detail}
}
proc ::GX::_pcbPairCloseCaptured {packet} {
    # Cleanup never resolves a numeric Document in the current Session.
    # No raw input channel survives an event-loop yield: Tcl channel names can
    # be reused. Resource reader/writer tokens have their existing owner serial.
    dict set packet cleanup_pending 0
    if {[dict exists $packet writer] && [dict get $packet writer] ne {}} {
        set token [dict get $packet writer];catch {interactiveDocumentResourceAbort $token}
        if {[dict exists $::GX::DocumentResource::writers $token]} {dict set packet cleanup_pending 1} else {dict set packet writer {}}
    }
    if {[dict exists $packet reader] && [dict get $packet reader] ne {}} {
        set token [dict get $packet reader];catch {interactiveDocumentResourceCloseReader $token}
        if {[dict exists $::GX::DocumentResource::readers $token]} {dict set packet cleanup_pending 1} else {dict set packet reader {}}
    }
    return $packet
}
proc ::GX::_pcbPairImportCancel {packet} {
    if {$packet eq {}} {return {}}
    dict set packet cancelled 1
    if {[dict exists $packet request] && [dict get $packet request] ne {}} {catch {scriptJobRequestCancel [dict get $packet request] cancelled}}
    # Do not cancel a continuation carrying the only remaining cleanup packet.
    set packet [_pcbPairCloseCaptured $packet]
    if {[dict get $packet canonical_state] ni {COMMITTED OUTCOME_UNKNOWN}} {dict set packet state CANCELLED}
    _pcbPairStore $packet
    return $packet
}
proc ::GX::_pcbPairImportDispose {packet} {return [_pcbPairImportCancel $packet]}
proc ::GX::_pcbPairRetire {packet state detail} {
    set packet [_pcbPairCloseCaptured $packet]
    dict set packet state $state
    dict set packet status $state
    dict set packet detail $detail
    dict set packet message $detail
    # Unknown/stale evidence remains retained_diagnostic/0. No direct file erase.
    if {[dict exists $packet allocation] && [dict get $packet worker_settled] && ![dict get $packet cleanup_pending]} {
        set disposition retained_diagnostic
        if {$state in {COMMITTED COMMITTED_DISPLAY_UNAVAILABLE} && ![dict get $packet cancelled]} {set disposition verified_orphan}
        if {[catch {resourceManagementRelease [dict get $packet allocation id] $disposition 0} release]} {dict set packet retention {Captured allocation retained; owner release not established}} else {dict set packet retention $release}
    }
    _pcbPairStore $packet
    set displayFailed [catch {_viewerGuiPCBComplete [dict get $packet window] [dict get $packet form] [dict get $packet epoch] $packet} displayed]
    if {[dict get $packet canonical_state] eq {COMMITTED} && ($displayFailed || ![dict exists $displayed state] || [dict get $displayed state] ne {COMMITTED})} {
        dict set packet state COMMITTED_DISPLAY_UNAVAILABLE
        dict set packet status COMMITTED_DISPLAY_UNAVAILABLE
        dict set packet detail {Source committed; the original form is unavailable for display}
        dict set packet message [dict get $packet detail]
        _pcbPairStore $packet
    }
    return $packet
}
proc ::GX::_pcbPairDescriptor {row name} {
    _pcbPairKeys $row {name sha256 bytes mode}
    _pcbPairRequire [expr {[dict get $row name] eq $name && $name in $::GX::PCBPair::names && [dict get $row mode] eq {384}}] {PCB artifact name or full permissions changed}
    _pcbPairSha [dict get $row sha256]
    set limit 16777216
    if {$name in {board.original.brd schematic.original.sch}} {set limit 4194304}
    if {$name eq {SOURCE_LICENSE.md}} {set limit 65536}
    _pcbPairInteger [dict get $row bytes] 1 $limit
    return $row
}
proc ::GX::_pcbPairReadBytes {path limit} {
    set before [_pcbPairFileStamp $path $limit 1]
    set channel [open $path rb]
    try {set bytes [read $channel [expr {$limit+1}]]} finally {close $channel}
    _pcbPairRequire [expr {[string length $bytes]<=$limit && [string length $bytes]==[lindex $before 2] && [_pcbPairFileStamp $path $limit 1] eq $before}] {PCB artifact changed while reading}
    return $bytes
}
proc ::GX::_pcbPairMirror {bytes kind descriptor} {
    _pcbPairRequire [expr {[string length $bytes]<=16777216}] {PCB mirror exceeds16MiB}
    set text [encoding convertfrom utf-8 $bytes]
    _pcbPairRequire [expr {[encoding convertto utf-8 $text] eq $bytes}] {PCB mirror must contain exact valid UTF8}
    _pcbPairKeys $text {ok result}
    _pcbPairRequire [expr {[dict get $text ok] eq {1}}] {PCB mirror is not a successful prepared envelope}
    set result [dict get $text result]
    _pcbPairKeys $result {schema kind json_artifact data}
    _pcbPairRequire [expr {[dict get $result schema] eq {gxtxt.eagle_pair_tcl_data.v1} && [dict get $result kind] eq $kind}] {PCB mirror schema/kind is unsupported}
    set actual [dict get $result json_artifact]
    _pcbPairDescriptor $actual "$kind.json"
    foreach key {name sha256 bytes mode} {_pcbPairRequire [expr {[dict get $actual $key] eq [dict get $descriptor $key]}] {PCB mirror references different JSON bytes}}
    return [dict get $result data]
}
proc ::GX::_pcbPairReference {row pair} {
    _pcbPairKeys $row {source_id role path}
    _pcbPairRequire [expr {[regexp "^eagle:${pair}:\[0-9a-f\]{64}$" [dict get $row source_id]] && [dict get $row role] in {board schematic} && [llength [dict get $row path]]<=64 && [string bytelength $row]<=65536}] {Unsupported PCB source identity}
    return [dict get $row source_id]
}
proc ::GX::_pcbPairRows {rows kind pair} {
    set limit [expr {$kind eq {index}?65536:16384}]
    _pcbPairRequire [expr {[llength $rows]<=$limit}] {PCB mirror record count exceeds its admitted bound}
    set ids {};set pointCount 0;set kinds {}
    foreach row $rows {
        _pcbPairRequire [expr {[string bytelength $row]<=65536}] {PCB mirror row exceeds64KiB}
        set type [dict get $row kind]
        set keys {kind source_id role path}
        if {$kind eq {index}} {
            switch -- $type {
                schematic_part {set extra {raw selected_device_ref selected_package package_present electrical_device}}
                device_pin {set extra {part gate pin pads declared_net declared_net_present state all_mapped_pads_unconnected}}
                net {set extra {name pinrefs}}
                board_package {set extra {library package raw pad_names}}
                board_element {set extra {raw package_ref category}}
                board_pad {set extra {element package library pad primitive reference_kind definition_ref element_ref raw placement logical_pins net net_present category}}
                default {error {Unsupported PCB structural record kind}}
            }
        } else {
            set keys [concat $keys {exact_mm approximate_view_mm raw layer layer_present}]
            switch -- $type {
                outline_definition {set extra {}}
                via_centre {set extra {net net_present copper_diameter extent}}
                trace_centreline {set extra {net net_present copper_fill}}
                polygon_boundary_definition {set extra {net net_present closed vertex_raw copper_fill}}
                pad_centre {set extra {element pad net net_present placement exact_element_degrees exact_pad_degrees reference_kind definition_ref element_ref copper_shape primitive}}
                default {error {Unsupported PCB layout record kind}}
            }
            set n [llength [dict get $row exact_mm]]
            _pcbPairRequire [expr {$n>0 && $n<=4096 && [llength [dict get $row approximate_view_mm]]==$n}] {PCB coordinate page exceeds its admitted shape}
            incr pointCount $n
            _pcbPairRequire [expr {$pointCount<=65536}] {PCB layout exceeds65536 source points}
            foreach exact [dict get $row exact_mm] approximate [dict get $row approximate_view_mm] {
                _pcbPairRequire [expr {[llength $exact]==2 && [llength $approximate]==2}] {PCB coordinate row requires exactly two components}
                foreach coordinate $exact {_pcbPairRequire [expr {[string length $coordinate]<=128 && [regexp {^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$} $coordinate]}] {PCB exact coordinate spelling is unsupported}}
                foreach coordinate $approximate {_pcbPairRequire [expr {[string length $coordinate]<=128 && [string is double -strict $coordinate] && ![regexp -nocase {nan|inf} $coordinate]}] {PCB approximate view coordinate is nonfinite}}
            }
        }
        _pcbPairKeys $row [concat $keys $extra]
        set id [_pcbPairReference [dict create source_id [dict get $row source_id] role [dict get $row role] path [dict get $row path]] $pair]
        _pcbPairRequire [expr {![dict exists $ids $id]}] {PCB source identity is duplicated within a mirror}
        dict set ids $id 1
        dict incr kinds $type
        foreach key {net declared_net layer} {
            if {[dict exists $row $key]} {
                set present [dict get $row ${key}_present]
                _pcbPairRequire [expr {$present in {0 1} && ($present || [dict get $row $key] eq {})}] {PCB optional source-field presence is inconsistent}
            }
        }
        foreach key {definition_ref element_ref package_ref selected_device_ref} {if {[dict exists $row $key]} {_pcbPairReference [dict get $row $key] $pair}}
    }
    return [dict create points $pointCount counts $kinds]
}
proc ::GX::_pcbPairPreparedDomain {receipt index layout descriptors} {
    set pair $::GX::PCBPair::pairStamp
    _pcbPairKeys $receipt {schema status parser worker_sha256 request_id worker_pid owned_process_group pair_stamp originals artifacts structural_counts artifact_limits original_recheck canonical_document_written complete_transition_performed supported_counts excluded visible_point_budget actual_point_count limitations}
    _pcbPairRequire [expr {[dict get $receipt schema] eq {gxtxt.eagle_pair_worker_receipt.v1} && [dict get $receipt status] eq {PREPARED_STAGED_SOURCE_ONLY} && [dict get $receipt parser] eq {gxtxt.eagle_paired_source.v1} && [dict get $receipt worker_sha256] eq $::GX::PCBPair::workerSha && [dict get $receipt pair_stamp] eq $pair && [dict get $receipt canonical_document_written] eq {0} && [dict get $receipt complete_transition_performed] eq {0}}] {PCB prepared receipt is not the reviewed fixed worker result}
    foreach key {worker_pid owned_process_group} {_pcbPairInteger [dict get $receipt $key] 1 2147483647}
    set priorNames [lrange $::GX::PCBPair::names 0 7]
    set seen {};set beforeReceipts 0
    _pcbPairRequire [expr {[llength [dict get $receipt artifacts]]==8}] {PCB receipt must inventory exactly eight prior artifacts}
    foreach descriptor [dict get $receipt artifacts] {
        set name [dict get $descriptor name];_pcbPairDescriptor $descriptor $name
        _pcbPairRequire [expr {$name in $priorNames && $name ni $seen}] {PCB receipt prior inventory is unsupported or duplicated}
        lappend seen $name
        foreach key {name sha256 bytes mode} {_pcbPairRequire [expr {[dict get $descriptor $key] eq [dict get $descriptors $name $key]}] {PCB receipt prior descriptor differs from canonical Resources}}
        incr beforeReceipts [dict get $descriptor bytes]
    }
    _pcbPairRequire [expr {[lsort $seen] eq [lsort $priorNames]}] {PCB receipt prior inventory is incomplete}
    set limits [dict get $receipt artifact_limits]
    _pcbPairKeys $limits {per_json_or_tcl_bytes per_original_bytes per_notice_bytes cumulative_attempted_bytes expected_success_file_count prior_artifact_count attempted_bytes_before_receipts receipt_inventory}
    foreach {key value} {per_json_or_tcl_bytes 16777216 per_original_bytes 4194304 per_notice_bytes 65536 cumulative_attempted_bytes 100663296 expected_success_file_count 10 prior_artifact_count 8} {_pcbPairRequire [expr {[dict get $limits $key] eq $value}] {PCB prepared artifact limits changed}}
    _pcbPairRequire [expr {[dict get $limits attempted_bytes_before_receipts]==$beforeReceipts && [dict get $limits receipt_inventory] eq {Prior artifacts only; final receipt identities are in stdout}}] {PCB receipt inventory/attempted-byte convention changed}
    _pcbPairKeys [dict get $receipt originals] {board schematic}
    foreach role {board schematic} {
        set original [dict get $receipt originals $role]
        _pcbPairKeys $original {path original_name sha256 bytes original_identity copy}
        _pcbPairRequire [expr {[dict get $original sha256] eq [dict get $::GX::PCBPair::approved $role] && [dict get $original copy] eq [expr {$role eq {board}?{board.original.brd}:{schematic.original.sch}}] && [file tail [dict get $original path]] eq [dict get $original original_name]}] {PCB original roles/hash/name changed}
        set identity [_pcbPairIdentity [dict get $original original_identity]]
        _pcbPairRequire [expr {[dict get $original bytes]==[dict get $identity size] && [dict get $original bytes]==[dict get $descriptors [dict get $original copy] bytes] && [dict get $original sha256] eq [dict get $descriptors [dict get $original copy] sha256]}] {PCB original receipt differs from admitted artifacts}
    }
    _pcbPairKeys $index {schema pair_stamp records counts source_xml structural_pair_reconciled scientific_or_manufacturing_validation limitations}
    _pcbPairRequire [expr {[dict get $index schema] eq {gxtxt.eagle_pair_index.v1} && [dict get $index pair_stamp] eq $pair && [dict get $index structural_pair_reconciled] eq {1} && [dict get $index scientific_or_manufacturing_validation] eq {0}}] {PCB index schema or scope is unsupported}
    _pcbPairKeys [dict get $index counts] {parts elements element_classes board_contacts nets schematic_pinrefs electrical_pads}
    foreach key {parts elements board_contacts nets schematic_pinrefs electrical_pads} {_pcbPairInteger [dict get $index counts $key] 0 65536}
    _pcbPairKeys [dict get $index counts element_classes] {board_only_unmapped electrical_device packaged_without_connects}
    dict for {key value} [dict get $index counts element_classes] {_pcbPairInteger $value 0 65536}
    _pcbPairRows [dict get $index records] index $pair
    _pcbPairKeys $layout {schema pair_stamp units unit_policy layers fit_outline_exact_mm objects fit_outline_approximate_view_mm actual_object_count actual_point_count supported_counts excluded adapter_object_budget adapter_point_budget visible_point_budget all_geometry_visible_guaranteed exceeds_visible_point_budget library_definition_projection limitations}
    _pcbPairRequire [expr {[dict get $layout schema] eq {gxtxt.eagle_pair_layout.v1} && [dict get $layout pair_stamp] eq $pair && [dict get $layout units] eq {mm} && [dict get $layout unit_policy] eq {qualified-historical-XML-mm-orthogonal-subset.v1} && [dict get $layout adapter_object_budget] eq {16384} && [dict get $layout adapter_point_budget] eq {65536} && [dict get $layout visible_point_budget] eq {4096} && [dict get $layout all_geometry_visible_guaranteed] eq {0}}] {PCB layout subset/unit/budget policy is unsupported}
    set measured [_pcbPairRows [dict get $layout objects] layout $pair]
    _pcbPairRequire [expr {[dict get $measured points]==[dict get $layout actual_point_count] && [llength [dict get $layout objects]]==[dict get $layout actual_object_count] && [dict get $layout actual_point_count]==[dict get $receipt actual_point_count] && [dict get $receipt visible_point_budget] eq {4096}}] {PCB layout counts differ from actual bounded source records}
    foreach key [dict keys [dict get $measured counts]] {_pcbPairRequire [expr {[dict get $measured counts $key]==[dict get $layout supported_counts $key] && [dict get $layout supported_counts $key]==[dict get $receipt supported_counts $key]}] {PCB supported counts differ across mirrors}}
    _pcbPairRequire [expr {[lsort [dict keys [dict get $measured counts]]] eq [lsort [dict keys [dict get $layout supported_counts]]]}] {PCB supported-count inventory is incomplete}
    _pcbPairRequire [expr {[dict get $index counts] eq [dict get $receipt structural_counts] && [dict get $layout excluded] eq [dict get $receipt excluded] && [dict get $index limitations] eq [dict get $layout limitations] && [dict get $layout limitations] eq [dict get $receipt limitations]}] {PCB summaries differ across the complete prepared mirrors}
    _pcbPairRequire [expr {[llength [dict get $layout excluded]]<=4096 && [string bytelength [dict get $layout limitations]]<=16384}] {PCB disclosure summary exceeds its admitted bound}
    foreach exclusion [dict get $layout excluded] {_pcbPairKeys $exclusion {scope primitive reason count};_pcbPairInteger [dict get $exclusion count] 0 65536}
    return [dict create pair_stamp $pair original_names [dict create board [dict get $receipt originals board original_name] schematic [dict get $receipt originals schematic original_name]] structural_counts [dict get $receipt structural_counts] supported_counts [dict get $receipt supported_counts] excluded [dict get $receipt excluded] actual_point_count [dict get $receipt actual_point_count] visible_point_budget 4096 limitations [dict get $receipt limitations] resource_count 10 unit_policy [dict get $layout unit_policy]]
}
proc ::GX::_pcbPairPreparedValidate {packet response} {
    _pcbPairKeys $response {ok result}
    _pcbPairRequire [expr {[dict get $response ok] eq {1}}] {PCB worker did not prepare a complete source pair}
    set result [dict get $response result]
    _pcbPairKeys $result {status request_id pair_stamp workdir receipt_sha256 receipt receipt_json_artifact receipt_tcl_artifact cumulative_artifact_bytes canonical_document_written}
    _pcbPairRequire [expr {[dict get $result status] eq {PREPARED_STAGED_SOURCE_ONLY} && [dict get $result request_id] eq [dict get $packet epoch] && [dict get $result pair_stamp] eq $::GX::PCBPair::pairStamp && [dict get $result workdir] eq [dict get $packet staged] && [dict get $result receipt] eq {receipt.json} && [dict get $result canonical_document_written] eq {0}}] {PCB worker result does not match this captured operation}
    set staged [dict get $packet staged]
    _pcbPairRootStamp $staged;file lstat $staged mode
    _pcbPairRequire [expr {[file owned $staged] && ($mode(mode)&07777)==0700}] {PCB staging root must remain owned0700}
    set entries {}
    foreach path [glob -nocomplain -directory $staged * .*] {set name [file tail $path];if {$name ni {. ..}} {lappend entries $name}}
    _pcbPairRequire [expr {[lsort $entries] eq [lsort $::GX::PCBPair::names]}] {PCB staging has missing or undeclared artifacts}
    set descriptors {}
    foreach {field name} {receipt_json_artifact receipt.json receipt_tcl_artifact receipt.tcldict} {
        set descriptor [_pcbPairDescriptor [dict get $result $field] $name]
        dict set descriptors $name $descriptor
        set bytes [_pcbPairReadBytes [file join $staged $name] 16777216]
        set snapshot [file join [dict get $packet allocation path] "verified-$name"]
        _pcbPairExclusiveBytes $snapshot $bytes
        _pcbPairRequire [expr {[string length $bytes]==[dict get $descriptor bytes] && [sha256File $snapshot] eq [dict get $descriptor sha256]}] {PCB final receipt bytes differ from actual managed stdout pins}
        dict set packet verified_paths $name $snapshot
    }
    _pcbPairRequire [expr {[dict get $result receipt_sha256] eq [dict get $descriptors receipt.json sha256]}] {PCB final JSON receipt pin disagrees}
    set receipt [_pcbPairMirror [_pcbPairReadBytes [dict get $packet verified_paths receipt.tcldict] 16777216] receipt [dict get $descriptors receipt.json]]
    _pcbPairRequire [expr {[dict get $receipt request_id] eq [dict get $packet epoch] && [llength [dict get $receipt artifacts]]==8}] {PCB prepared receipt has the wrong operation or inventory}
    set total 0
    foreach descriptor [dict get $receipt artifacts] {
        set name [dict get $descriptor name];_pcbPairDescriptor $descriptor $name
        _pcbPairRequire [expr {![dict exists $descriptors $name]}] {PCB artifact descriptor is duplicated}
        dict set descriptors $name $descriptor
        set bytes [_pcbPairReadBytes [file join $staged $name] [dict get $descriptor bytes]]
        set snapshot [file join [dict get $packet allocation path] "verified-$name"]
        _pcbPairExclusiveBytes $snapshot $bytes
        _pcbPairRequire [expr {[string length $bytes]==[dict get $descriptor bytes] && [sha256File $snapshot] eq [dict get $descriptor sha256]}] {PCB staged artifact differs from its complete prepared receipt}
        dict set packet verified_paths $name $snapshot
    }
    _pcbPairRequire [expr {[lsort [dict keys $descriptors]] eq [lsort $::GX::PCBPair::names]}] {PCB complete ten-artifact inventory is required}
    dict for {name descriptor} $descriptors {incr total [dict get $descriptor bytes]}
    _pcbPairRequire [expr {$total<100663297 && $total==[dict get $result cumulative_artifact_bytes] && [dict get $descriptors SOURCE_LICENSE.md sha256] eq $::GX::PCBPair::licenseSha}] {PCB cumulative byte or unchanged license policy differs}
    set index [_pcbPairMirror [_pcbPairReadBytes [dict get $packet verified_paths index.tcldict] 16777216] index [dict get $descriptors index.json]]
    set layout [_pcbPairMirror [_pcbPairReadBytes [dict get $packet verified_paths layout.tcldict] 16777216] layout [dict get $descriptors layout.json]]
    set summary [_pcbPairPreparedDomain $receipt $index $layout $descriptors]
    foreach role {board schematic} {
        set original [dict get $receipt originals $role];set initial [dict get $packet sources $role]
        _pcbPairRequire [expr {[dict get $original path] eq [dict get $initial path] && [dict get $original sha256] eq [dict get $initial sha256] && [dict get $original bytes]==[dict get $initial bytes] && [_pcbPairSameIdentity [dict get $original original_identity] [dict get $initial identity]]}] {PCB worker original differs from fresh parent capture}
    }
    _pcbPairRequire [expr {[string bytelength $summary]<=65536}] {PCB inspector summary exceeds64KiB}
    dict set packet descriptors $descriptors
    dict set packet summary $summary
    dict set packet prepared_receipt $receipt
    return $packet
}
proc ::GX::_pcbPairStagingCheck {packet} {
    _pcbPairRequire [_pcbPairCurrent $packet] {PCB captured authority expired; previous completed source retained}
    set actual [interactiveDocumentRead [dict get $packet document_id]]
    foreach key {id module_id provider_id format format_version generation revision sha256} {
        _pcbPairRequire [expr {[dict get $actual $key] eq [dict get $packet staging_metadata $key]}] {PCB staging Document identity changed}
    }
    _pcbPairRequire [expr {[dict get $actual payload] eq [dict get $packet staging_payload]}] {PCB staging payload changed}
    return $actual
}
proc ::GX::_pcbPairWorkerDone {packet response} {
    # ScriptJob invokes this only after its existing EOF/retirement owner has
    # closed the captured request. The callback owns this packet after Dispose.
    dict set packet worker_settled 1
    dict set packet request {}
    if {![_pcbPairCurrent $packet]} {return [_pcbPairRetire $packet STALE {Preparation retired after the form or Session changed; no current source was created}]}
    try {
        set packet [_pcbPairPreparedValidate $packet $response]
        _pcbPairRequire [_pcbPairCurrent $packet] {PCB authority changed during prepared artifact admission}
        set authority [dict get $packet authority]
        set payload [dict create schema gxtxt.pcb.eagle_pair.staging.v1 state incomplete epoch [dict get $packet epoch] pair_stamp $::GX::PCBPair::pairStamp worker_sha256 $::GX::PCBPair::workerSha]
        set owner [interactiveDocumentCreate [dict get $authority module_id] [dict get $authority provider_id] gxtxt.pcb.eagle_pair.staging.v1 1 $payload]
        dict set packet document_id [dict get $owner id]
        dict set packet staging_metadata $owner
        dict set packet staging_payload $payload
        dict set packet canonical_state STAGING
        dict set packet artifact_index 0
        dict set packet offset 0
        dict set packet state STREAMING
        _pcbPairNotify $packet {Importing ten source Resources into a new incomplete Document; prior source retained}
        _pcbPairSchedule $packet step
    } on error {message options} {
        return [_pcbPairRetire $packet FAILED $message]
    }
}
proc ::GX::_pcbPairSchedule {packet operation} {
    _pcbPairRequire [expr {$operation in {step final}}] {Unsupported private PCB continuation}
    _pcbPairStore $packet
    # The timer itself carries the finite owned cleanup packet. Disposing the
    # form invalidates mutation, but must not cancel its only cleanup carrier.
    if {$operation eq {step}} {after 0 [list ::GX::_pcbPairStep $packet]} else {after 0 [list ::GX::_pcbPairFinalize $packet]}
}
proc ::GX::_pcbPairStep {packet} {
    if {![_pcbPairCurrent $packet]} {return [_pcbPairRetire $packet STALE {Source import stopped after captured authority changed; incomplete staging retained}]}
    try {
        _pcbPairStagingCheck $packet
        set position [dict get $packet artifact_index]
        if {$position==10} {
            if {[dict get $packet state] eq {STREAMING}} {
                dict set packet state VALIDATING
                dict set packet artifact_index 0
                _pcbPairNotify $packet {Checking every canonical Resource to EOF before the final source gate}
                _pcbPairSchedule $packet step
            } else {
                # All checked readers have reached EOF and have been closed.
                # This timer establishes the literal last yield before capture.
                _pcbPairSchedule $packet final
            }
            return
        }
        set name [lindex $::GX::PCBPair::names $position]
        set descriptor [dict get $packet descriptors $name]
        if {[dict get $packet state] eq {STREAMING}} {
            set path [dict get $packet verified_paths $name]
            if {[dict get $packet writer] eq {}} {
                set stamp [_pcbPairFileStamp $path [dict get $descriptor bytes] 1]
                _pcbPairRequire [expr {[sha256File $path] eq [dict get $descriptor sha256]}] {Verified PCB snapshot changed before streaming}
                dict set packet input_stamp $stamp
                dict set packet offset 0
                dict set packet writer [interactiveDocumentResourceOpenWriter [dict get $packet document_id] [dict create format gxtxt.pcb.eagle_pair.artifact.v1 role $name pair_stamp $::GX::PCBPair::pairStamp worker_sha256 $::GX::PCBPair::workerSha]]
                _pcbPairStore $packet
            }
            _pcbPairRequire [expr {[_pcbPairFileStamp $path [dict get $descriptor bytes] 1] eq [dict get $packet input_stamp]}] {PCB snapshot changed between Resource chunks}
            set expected [expr {min(1048576,[dict get $descriptor bytes]-[dict get $packet offset])}]
            set channel [open $path rb]
            try {seek $channel [dict get $packet offset] start;set bytes [read $channel $expected]} finally {close $channel}
            _pcbPairRequire [expr {[string length $bytes]==$expected && [_pcbPairFileStamp $path [dict get $descriptor bytes] 1] eq [dict get $packet input_stamp]}] {PCB snapshot changed while streaming a Resource chunk}
            interactiveDocumentResourceAppend [dict get $packet writer] $bytes
            dict incr packet offset $expected
            if {[dict get $packet offset]==[dict get $descriptor bytes]} {
                set reference [interactiveDocumentResourceFinalize [dict get $packet writer]]
                dict set packet writer {}
                _pcbPairRequire [expr {[dict get $reference sha256] eq [dict get $descriptor sha256] && [dict get $reference size_bytes]==[dict get $descriptor bytes] && [dict get $reference document_id] eq [dict get $packet document_id] && [dict get $reference owner_generation] eq [dict get $packet staging_metadata generation]}] {Finalized PCB Resource differs from the prepared descriptor}
                dict set packet resources $name $reference
                dict incr packet artifact_index
            }
        } elseif {[dict get $packet state] eq {VALIDATING}} {
            set reference [dict get $packet resources $name]
            if {[dict get $packet reader] eq {}} {
                interactiveDocumentResourceInfo $reference
                dict set packet reader [interactiveDocumentResourceOpenReader $reference]
                _pcbPairStore $packet
            }
            set result [interactiveDocumentResourceNext [dict get $packet reader] 1048576]
            if {[dict get $result eof]} {
                interactiveDocumentResourceCloseReader [dict get $packet reader]
                dict set packet reader {}
                dict set packet checked_resources $name $reference
                dict incr packet artifact_index
            }
        } else {error {PCB continuation phase is not admitted}}
        _pcbPairStagingCheck $packet
        _pcbPairSchedule $packet step
    } on error {message options} {
        return [_pcbPairRetire $packet FAILED $message]
    }
}
proc ::GX::_pcbPairPayload {packet} {
    set receipt [dict get $packet prepared_receipt]
    set payload [dict create schema gxtxt.pcb.eagle_pair.source.v1 state completed parser gxtxt.eagle_paired_source.v1 worker_sha256 $::GX::PCBPair::workerSha pair_stamp $::GX::PCBPair::pairStamp originals [dict get $receipt originals] artifacts [dict get $packet resources] descriptors [dict get $packet descriptors] summary [dict get $packet summary] license [dict create notice SOURCE_LICENSE.md sha256 $::GX::PCBPair::licenseSha upstream https://github.com/sparkfun/SparkFun_Buck_Regulator_AP63357DV-7 upstream_commit 2daeae4799b416ed27fc1dfa3123d6cc68747f38 hardware_license CC-BY-SA-4.0 derived_index_layout_license CC-BY-SA-4.0 framework_code_license GPL-3.0-or-later]]
    _pcbPairRequire [expr {[string length [encoding convertto utf-8 $payload]]<=262144}] {Canonical PCB source metadata exceeds256KiB}
    return $payload
}
proc ::GX::_pcbPairFinalize {packet} {
    if {![_pcbPairCurrent $packet]} {return [_pcbPairRetire $packet STALE {Final source admission expired; previous completed binding retained}]}
    try {
        _pcbPairRequire [expr {[dict get $packet reader] eq {} && [dict get $packet writer] eq {} && [lsort [dict keys [dict get $packet checked_resources]]] eq [lsort $::GX::PCBPair::names]}] {All ten checked Resource readers must close before the final gate}
        set envelope [dict get $packet allocation path]
        # No yield from here through Update. Every source capture opens a fresh
        # native FD; hashing uses only those exact owned binary snapshots.
        foreach role {board schematic} {
            set final [_pcbPairCapture [dict get $packet sources $role path] $envelope "final-$role.bin"]
            _pcbPairRequire [_pcbPairSameCapture [dict get $packet sources $role] $final] {Original PCB source changed after the last Resource yield; no completion performed}
        }
        set projects [_pcbPairProjectCapture [dict get $packet authority project] $envelope final]
        foreach key {source design project} {_pcbPairRequire [_pcbPairSameCapture [dict get $packet project_captures $key] [dict get $projects $key]] {PCB project/design/source changed after the last Resource yield}}
        _pcbPairStagingCheck $packet
        dict for {name reference} [dict get $packet resources] {
            _pcbPairRequire [expr {$reference eq [dict get $packet checked_resources $name]}] {PCB Resource receipt changed after checked EOF}
            interactiveDocumentResourceInfo $reference
        }
        set payload [_pcbPairPayload $packet]
        dict set packet state COMMITTING
        _pcbPairNotify $packet {Final authority check; completing the new canonical source}
        # Volatile admission LAST; no callback/notification after this gate.
        _pcbPairStagingCheck $packet
        _pcbPairRequire [_pcbPairCurrent $packet] {PCB volatile authority changed immediately before completion}
        dict set packet update_attempted 1
        dict set packet canonical_state COMMITTING
        set completed [interactiveDocumentUpdate [dict get $packet document_id] $payload gxtxt.pcb.eagle_pair.source.v1 1]
        dict set packet canonical_state COMMITTED
        dict set packet completed_metadata $completed
        _pcbPairStore $packet
        set record [_pcbPairDocumentRead [dict get $packet document_id] [dict create module_id [dict get $packet authority module_id] provider_id [dict get $packet authority provider_id]]]
        dict set packet document $record
        if {![_pcbPairCurrent $packet]} {return [_pcbPairRetire $packet COMMITTED_DISPLAY_UNAVAILABLE {Source committed; original host/source admission changed before display}]}
        return [_pcbPairRetire $packet COMMITTED {Immutable source snapshot committed; external originals remain unchanged}]
    } on error {message options} {
        if {[dict get $packet canonical_state] eq {COMMITTED}} {return [_pcbPairRetire $packet COMMITTED_DISPLAY_UNAVAILABLE "Source committed; completed consultation unavailable: $message"]}
        if {[dict exists $packet update_attempted]} {dict set packet canonical_state OUTCOME_UNKNOWN;return [_pcbPairRetire $packet OUTCOME_UNKNOWN {Canonical completion outcome unknown; retain captured staging and reconcile only its exact original Session/generation}]}
        return [_pcbPairRetire $packet FAILED $message]
    }
}
proc ::GX::_pcbPairResourceBytes {reference maximum} {
    _pcbPairRequire [expr {[dict get $reference size_bytes]<=$maximum}] {PCB consultation resource exceeds its finite bound}
    set reader [interactiveDocumentResourceOpenReader $reference]
    set result {}
    try {
        while 1 {
            set chunk [interactiveDocumentResourceNext $reader 1048576]
            append result [dict get $chunk bytes]
            _pcbPairRequire [expr {[string length $result]<=$maximum}] {PCB consultation resource grew beyond its finite bound}
            if {[dict get $chunk eof]} break
        }
    } finally {interactiveDocumentResourceCloseReader $reader}
    return $result
}
proc ::GX::_pcbPairDocumentRead {document expectedOwner} {
    _pcbPairKeys $expectedOwner {module_id provider_id}
    set token [interactiveDocumentSessionToken]
    set root [_pcbPairRootStamp [_interactiveDocumentRequireSession]]
    # Bound the canonical UTF8 payload BEFORE generic Read consumes it in full.
    set registry [_interactiveDocumentRegistryRead [_interactiveDocumentRequireSession]]
    _pcbPairRequire [dict exists $registry $document] {PCB source Document does not exist}
    set registered [dict get $registry $document]
    _pcbPairRequire [expr {[dict get $registered format] eq {gxtxt.pcb.eagle_pair.source.v1} && [dict get $registered format_version] eq {1}}] {Select an exact completed PCB source profile}
    foreach key {module_id provider_id} {_pcbPairRequire [expr {[dict get $registered $key] eq [dict get $expectedOwner $key]}] {PCB source belongs to another declared module/provider}}
    set payloadPath [_interactiveDocumentPayloadPath [_interactiveDocumentRequireSession] $registered]
    _pcbPairFileStamp $payloadPath 262144
    set record [interactiveDocumentRead $document]
    _pcbPairRequire [expr {[string length [encoding convertto utf-8 [dict get $record payload]]]<=262144}] {PCB canonical payload exceeds256KiB}
    set payload [dict get $record payload]
    _pcbPairKeys $payload {schema state parser worker_sha256 pair_stamp originals artifacts descriptors summary license}
    _pcbPairRequire [expr {[dict get $payload schema] eq {gxtxt.pcb.eagle_pair.source.v1} && [dict get $payload state] eq {completed} && [dict get $payload parser] eq {gxtxt.eagle_paired_source.v1} && [dict get $payload worker_sha256] eq $::GX::PCBPair::workerSha && [dict get $payload pair_stamp] eq $::GX::PCBPair::pairStamp}] {PCB canonical source schema/state/worker policy is unsupported}
    _pcbPairKeys [dict get $payload artifacts] $::GX::PCBPair::names
    _pcbPairKeys [dict get $payload descriptors] $::GX::PCBPair::names
    set resourceStamps {};set total 0
    dict for {name reference} [dict get $payload artifacts] {
        set descriptor [_pcbPairDescriptor [dict get $payload descriptors $name] $name]
        _pcbPairRequire [expr {[dict get $reference document_id] eq $document && [dict get $reference owner_generation] eq [dict get $record generation] && [dict get $reference sha256] eq [dict get $descriptor sha256] && [dict get $reference size_bytes]==[dict get $descriptor bytes]}] {PCB Resource must belong to this exact Document generation and descriptor}
        set metadata [dict get $reference metadata]
        _pcbPairRequire [expr {[dict get $metadata format] eq {gxtxt.pcb.eagle_pair.artifact.v1} && [dict get $metadata role] eq $name && [dict get $metadata pair_stamp] eq [dict get $payload pair_stamp] && [dict get $metadata worker_sha256] eq $::GX::PCBPair::workerSha}] {PCB Resource metadata has another role or source policy}
        interactiveDocumentResourceInfo $reference
        incr total [dict get $reference size_bytes]
        dict set resourceStamps $name [dict create sha256 [dict get $reference sha256] size_bytes [dict get $reference size_bytes] owner_generation [dict get $reference owner_generation]]
    }
    _pcbPairRequire [expr {$total<=100663296 && [dict get $payload artifacts SOURCE_LICENSE.md sha256] eq $::GX::PCBPair::licenseSha}] {PCB completed artifacts exceed their budget or changed the license notice}
    set mirrors {}
    foreach kind {receipt index layout} {
        set bytes [_pcbPairResourceBytes [dict get $payload artifacts "$kind.tcldict"] 16777216]
        dict set mirrors $kind [_pcbPairMirror $bytes $kind [dict get $payload descriptors "$kind.json"]]
    }
    set summary [_pcbPairPreparedDomain [dict get $mirrors receipt] [dict get $mirrors index] [dict get $mirrors layout] [dict get $payload descriptors]]
    _pcbPairRequire [expr {$summary eq [dict get $payload summary] && [string bytelength $summary]<=65536 && [dict get $payload originals] eq [dict get $mirrors receipt originals]}] {PCB canonical summary/original provenance differs from complete Resources}
    set license [dict get $payload license]
    _pcbPairKeys $license {notice sha256 upstream upstream_commit hardware_license derived_index_layout_license framework_code_license}
    _pcbPairRequire [expr {[dict get $license notice] eq {SOURCE_LICENSE.md} && [dict get $license sha256] eq $::GX::PCBPair::licenseSha && [dict get $license upstream] eq {https://github.com/sparkfun/SparkFun_Buck_Regulator_AP63357DV-7} && [dict get $license upstream_commit] eq {2daeae4799b416ed27fc1dfa3123d6cc68747f38} && [dict get $license hardware_license] eq {CC-BY-SA-4.0} && [dict get $license derived_index_layout_license] eq {CC-BY-SA-4.0} && [dict get $license framework_code_license] eq {GPL-3.0-or-later}}] {PCB license/attribution policy changed}
    _pcbPairRequire [expr {[interactiveDocumentSessionToken] eq $token && [_pcbPairRootStamp [_interactiveDocumentRequireSession]] eq $root}] {PCB Session changed during source consultation}
    set after [interactiveDocumentRead $document]
    foreach key {id module_id provider_id format format_version generation revision sha256 payload} {_pcbPairRequire [expr {[dict get $after $key] eq [dict get $record $key]}] {PCB canonical identity changed during consultation}}
    dict set record payload $payload
    dict set record document_id $document
    dict set record summary $summary
    dict set record stamp [dict create document_id $document generation [dict get $record generation] revision [dict get $record revision] sha256 [dict get $record sha256] pair_stamp [dict get $payload pair_stamp] resource_stamps $resourceStamps]
    return $record
}
proc ::GX::_pcbPairDocumentList {module provider} {
    set candidates {}
    foreach record [interactiveDocumentList $module $provider] {
        if {[dict get $record format] eq {gxtxt.pcb.eagle_pair.source.v1} && [dict get $record format_version] eq {1}} {lappend candidates $record}
    }
    _pcbPairRequire [expr {[llength $candidates]<=128}] {More than128 completed PCB sources require bounded consultation; this first fixed-pair form cannot list them all}
    set result {}
    foreach record $candidates {
        set validated [_pcbPairDocumentRead [dict get $record id] [dict create module_id $module provider_id $provider]]
        lappend result [dict remove $validated payload]
    }
    return $result
}
proc ::GX::_pcbPairImportBegin {window form authority} {
    set epoch [dict get $authority epoch]
    _pcbPairRequire [regexp {^[A-Za-z0-9_-]{1,96}$} $epoch] {PCB operation epoch is unsupported}
    set packet [dict create window $window form $form authority $authority epoch $epoch state CHOOSING canonical_state NONE cancelled 0 worker_settled 1 request {} writer {} reader {} input_channel {} resources {} session_token [interactiveDocumentSessionToken] session_root [_pcbPairRootStamp [_interactiveDocumentRequireSession]]]
    _pcbPairStore $packet
    try {
        _pcbPairRequire [_pcbPairCurrent $packet] {PCB form is not currently admitted}
        foreach {role extension caption} {board .brd {Choose the approved BabyBuck5V board} schematic .sch {Choose its paired BabyBuck5V schematic}} {
            set path [tk_getOpenFile -parent $window -title $caption -filetypes [list [list "EAGLE $role" [list *$extension]]]]
            _pcbPairRequire [_pcbPairCurrent $packet] {PCB authority changed while choosing originals}
            if {$path eq {}} {return [_pcbPairRetire $packet CANCELLED {Pair selection cancelled; no worker or canonical source was created}]}
            # Preserve the chooser's spelling for native literal/no-follow
            # admission; normalization could hide a linked source ancestor.
            dict set packet paths $role $path
        }
        set allocation [resourceManagementAllocate pcb_paired_source [dict create category retained_diagnostic kind directory lifetime owner retention_seconds 0 expected_bytes 268435456 session [_interactiveDocumentRequireSession]]]
        dict set packet allocation $allocation
        dict set packet allocation_root [_pcbPairRootStamp [dict get $allocation path]]
        dict set packet staged [_pcbPairStorageAdmit $allocation]
        set envelope [dict get $allocation path]
        foreach role {board schematic} {
            set source [_pcbPairCapture [dict get $packet paths $role] $envelope "initial-$role.bin"]
            _pcbPairRequire [expr {[dict get $source sha256] eq [dict get $::GX::PCBPair::approved $role] && [dict get $source bytes]>0 && [string tolower [file extension [dict get $source path]]] eq [expr {$role eq {board}?{.brd}:{.sch}}]}] {Only the unchanged approved BabyBuck5V board and schematic pair is supported}
            dict set packet sources $role $source
        }
        dict set packet project_captures [_pcbPairProjectCapture [dict get $authority project] $envelope initial]
        set worker [file join $::GX::scriptDir core python gxtxt_eagle_paired_source.py]
        _pcbPairFileStamp $worker 1048576
        _pcbPairRequire [expr {[sha256File $worker] eq $::GX::PCBPair::workerSha}] {PCB worker source changed; independent review is required}
        set license [file join $::GX::scriptDir docs development task210 pcb_paired_source SOURCE_LICENSE.md]
        _pcbPairRequire [expr {[sha256File $license] eq $::GX::PCBPair::licenseSha}] {PCB source license notice changed}
        _pcbPairRequire [_pcbPairCurrent $packet] {PCB authority changed before managed submission}
        set python [runtimeToolRequired python]
        set command [list env LC_ALL=C.UTF-8 LANG=C.UTF-8 $python -I -B $worker [dict get $packet paths board] [dict get $packet paths schematic] [dict get $packet staged]]
        dict set packet state WORKER_RUNNING
        dict set packet worker_settled 0
        set request [scriptJobAsync $command [_pcbPairRequestJson $packet] [list ::GX::_pcbPairWorkerDone $packet] [dict create timeout_ms 90000 max_bytes 65536 process_group 1 ui_lifetime 1 label {PCB paired-source preparation}]]
        dict set packet request $request
        _pcbPairNotify $packet {Preparing one fixed source pair; no canonical source committed}
        return $packet
    } on error {message options} {
        return [_pcbPairRetire $packet FAILED $message]
    }
}
