# GX-TXT Interactive Document API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# CORE-managed authoritative UTF-8 documents scoped to the current Session.
# The public API exposes identities, ownership, format/version metadata and
# payloads, never internal Session filesystem paths.

namespace eval ::GX {
    variable interactiveDocumentApiVersion 1
}
namespace eval ::GX::DocumentSessionScope {variable identity {};variable epoch 0;variable token ""}
proc ::GX::interactiveDocumentApiInfo {} {
    return [dict create api_id INTERACTIVE_DOCUMENT_API_v1 api_version 1 operations {interactiveDocumentCreate interactiveDocumentExists interactiveDocumentList interactiveDocumentRead interactiveDocumentUpdate interactiveDocumentDelete interactiveDocumentSessionToken interactiveDocumentLifecycleSubscribe interactiveDocumentLifecycleUnsubscribe} document_owner CORE source_encoding UTF-8 session_scoped 1 profiles [dict create tex_project [interactiveDocumentTeXApiInfo]]]
}
proc ::GX::_interactiveDocumentSessionChanged {args} {
    variable ::GX::DocumentSessionScope::identity
    variable ::GX::DocumentSessionScope::epoch
    variable ::GX::DocumentSessionScope::token
    set next {}
    if {[info exists ::GX::currentSession]&&$::GX::currentSession ne ""} {
        set path [file normalize $::GX::currentSession]
        if {![catch {file stat $path status}]} {set next [list $path $status(dev) $status(ino)]} else {set next [list $path missing]}
    }
    if {$next ne $identity} {set identity $next;set token "document-session#[pid]-[incr epoch]-[clock clicks]"}
}
trace add variable ::GX::currentSession {write unset} ::GX::_interactiveDocumentSessionChanged

proc ::GX::interactiveDocumentIdValid {id} {
    return [regexp {^idoc_[0-9]{4,}$} $id]
}

proc ::GX::_interactiveDocumentRequireSession {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        error "Interactive Document API requires an open Session."
    }
    return [file normalize $currentSession]
}

proc ::GX::_interactiveDocumentRegistryPath {session} {
    return [file join $session metadata interactive_documents.ini]
}

proc ::GX::_interactiveDocumentStorageDir {session} {
    return [file join $session metadata interactive_documents]
}

proc ::GX::_interactiveDocumentValidateSingleLine {value label} {
    set value [string trim $value]
    if {$value eq ""} { error "$label is required." }
    if {[regexp {[\r\n]} $value]} { error "$label must be a single-line value." }
    return $value
}

proc ::GX::_interactiveDocumentValidateOwner {moduleId providerId} {
    set moduleId [_interactiveDocumentValidateSingleLine $moduleId "Module ID"]
    set providerId [_interactiveDocumentValidateSingleLine $providerId "Provider ID"]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $moduleId]} { error "Invalid Interactive Document module ID '$moduleId'." }
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $providerId]} { error "Invalid Interactive Document provider ID '$providerId'." }
    return [list $moduleId $providerId]
}

proc ::GX::_interactiveDocumentRegistryRead {session} {
    set path [_interactiveDocumentRegistryPath $session]
    if {![file exists $path]} { return [dict create] }
    if {![file isfile $path]} { error "Interactive Document registry is not a regular file." }
    if {[catch {set ini [parseIni $path]} err opts]} {
        return -options $opts "Interactive Document registry is corrupt: $err"
    }
    if {![dict exists $ini interactive_documents.api_version]} {
        error "Interactive Document registry is corrupt: missing API version."
    }
    if {[dict get $ini interactive_documents.api_version] ne "1"} {
        error "Unsupported Interactive Document registry version '[dict get $ini interactive_documents.api_version]'."
    }
    set count [expr {[dict exists $ini interactive_documents.count] ? [dict get $ini interactive_documents.count] : ""}]
    if {![string is integer -strict $count] || $count < 0} {
        error "Interactive Document registry is corrupt: invalid document count."
    }
    set registry [dict create]
    for {set i 1} {$i <= $count} {incr i} {
        set prefix "interactive_document.$i."
        set item [dict create]
        foreach field {id module_id provider_id format format_version sha256 storage_name created_at updated_at} {
            set key "$prefix$field"
            if {![dict exists $ini $key]} { error "Interactive Document registry is corrupt: missing $key." }
            dict set item $field [dict get $ini $key]
        }
        set revision [expr {[dict exists $ini ${prefix}revision] ? [dict get $ini ${prefix}revision] : 1}]
        if {![string is entier -strict $revision] || $revision<1} {error "Interactive Document registry is corrupt: invalid revision"}
        if {[dict exists $ini ${prefix}duplication_policy]} {dict set item duplication_policy [dict get $ini ${prefix}duplication_policy]}
        dict set item revision $revision
        dict set item origin [expr {[dict exists $ini ${prefix}origin] ? [dict get $ini ${prefix}origin] : [_originUnknown]}]
        dict set item generation [expr {[dict exists $ini ${prefix}generation] ? [dict get $ini ${prefix}generation] : "legacy:[dict get $item created_at]"}]
        set id [dict get $item id]
        if {![interactiveDocumentIdValid $id]} { error "Interactive Document registry is corrupt: invalid document ID '$id'." }
        if {[dict exists $registry $id]} { error "Interactive Document registry is corrupt: duplicate document ID '$id'." }
        lassign [_interactiveDocumentValidateOwner [dict get $item module_id] [dict get $item provider_id]] _ _
        _interactiveDocumentValidateSingleLine [dict get $item format] "Document format"
        _interactiveDocumentValidateSingleLine [dict get $item format_version] "Document format version"
        if {![regexp {^[0-9a-f]{64}$} [string tolower [dict get $item sha256]]]} {
            error "Interactive Document registry is corrupt: invalid SHA-256 for '$id'."
        }
        set storage [dict get $item storage_name]
        if {![regexp {^idoc_[0-9]{4,}\.[0-9a-f]{64}\.utf8$} $storage]} {
            error "Interactive Document registry is corrupt: invalid storage identity for '$id'."
        }
        dict set registry $id $item
    }
    return $registry
}

proc ::GX::_interactiveDocumentRegistryWrite {session registry} {
    set path [_interactiveDocumentRegistryPath $session]
    file mkdir [file dirname $path]
    set tmp "$path.tmp.[pid].[clock clicks]"
    set highWater 0
    if {[file exists $path]} {set ini [parseIni $path];if {[dict exists $ini interactive_documents.high_water_id]} {set highWater [dict get $ini interactive_documents.high_water_id]}}
    if {![string is entier -strict $highWater]||$highWater<0} {error "Invalid Interactive Document allocation counter"}
    foreach id [dict keys $registry] {scan [string range $id 5 end] %d n;set highWater [expr {max($highWater,$n)}]}
    if {[catch {
        set fd [open $tmp w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "; GX-TXT Interactive Document API v1"
        puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
        puts $fd "\[interactive_documents\]"
        putKV $fd api_version 1
        putKV $fd high_water_id $highWater
        set ids [lsort -dictionary [dict keys $registry]]
        putKV $fd count [llength $ids]
        set i 0
        foreach id $ids {
            incr i
            puts $fd "\n\[interactive_document.$i\]"
            set item [dict get $registry $id]
            foreach field {id module_id provider_id format format_version sha256 storage_name created_at updated_at revision generation} {
                putKV $fd $field [dict get $item $field]
            }
            if {[dict exists $item duplication_policy]} {putKV $fd duplication_policy [dict get $item duplication_policy]}
            if {[dict exists $item origin]} {putKV $fd origin [dict get $item origin]}
        }
        close $fd
        file rename -force -- $tmp $path
    } err opts]} {
        catch {close $fd}
        catch {file delete -force -- $tmp}
        return -options $opts $err
    }
    return $path
}

proc ::GX::_interactiveDocumentPublicMetadata {item} {
    set out $item
    catch {dict unset out storage_name}
    return $out
}

proc ::GX::_interactiveDocumentNextId {registry} {
    set max 0
    set path [_interactiveDocumentRegistryPath [_interactiveDocumentRequireSession]]
    if {[file exists $path]} {set ini [parseIni $path];if {[dict exists $ini interactive_documents.high_water_id]} {set max [dict get $ini interactive_documents.high_water_id]}}
    if {![string is entier -strict $max]||$max<0} {error "Invalid Interactive Document allocation counter"}
    foreach id [dict keys $registry] {
        if {[regexp {^idoc_([0-9]+)$} $id -> n]} {
            scan $n %d n
            if {$n > $max} { set max $n }
        }
    }
    while 1 {
        incr max
        set id [format "idoc_%04d" $max]
        if {![dict exists $registry $id]} { return $id }
    }
}

proc ::GX::_interactiveDocumentWritePayload {session id payload} {
    set dir [_interactiveDocumentStorageDir $session]
    file mkdir $dir
    set temporary [file join $dir ".$id.[pid].[clock clicks].tmp"]
    if {[catch {
        set fd [open $temporary w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts -nonewline $fd $payload
        close $fd
        set sha [string tolower [sha256File $temporary]]
        set storage "$id.$sha.utf8"
        set target [file join $dir $storage]
        if {[file exists $target]} {
            file delete -force -- $temporary
        } else {
            file rename -- $temporary $target
        }
    } err opts]} {
        catch {close $fd}
        catch {file delete -force -- $temporary}
        return -options $opts $err
    }
    return [dict create sha256 $sha storage_name $storage]
}

proc ::GX::_interactiveDocumentPayloadPath {session item} {
    set dir [file normalize [_interactiveDocumentStorageDir $session]]
    set path [file normalize [file join $dir [dict get $item storage_name]]]
    if {[string first "$dir/" "$path/"] != 0} {
        error "Interactive Document storage escaped the Session registry."
    }
    if {![file isfile $path]} {
        error "Interactive Document '[dict get $item id]' payload is missing."
    }
    return $path
}

proc ::GX::interactiveDocumentCreate {moduleId providerId format formatVersion payload {documentId ""}} {
    return [_interactiveDocumentCreateWithOrigin $moduleId $providerId $format $formatVersion $payload $documentId {}]
}
# The managed Workspace importer supplies a verified inert origin parent at
# initial allocation. Public creation keeps its existing signature/semantics.
proc ::GX::_interactiveDocumentCreateWithOrigin {moduleId providerId format formatVersion payload documentId originParent} {
    set session [_interactiveDocumentRequireSession]
    lassign [_interactiveDocumentValidateOwner $moduleId $providerId] moduleId providerId
    set format [_interactiveDocumentValidateSingleLine $format "Document format"]
    set formatVersion [_interactiveDocumentValidateSingleLine $formatVersion "Document format version"]
    set registry [_interactiveDocumentRegistryRead $session]
    if {$documentId eq ""} {
        set documentId [_interactiveDocumentNextId $registry]
    } elseif {![interactiveDocumentIdValid $documentId]} {
        error "Invalid Interactive Document ID '$documentId'."
    }
    if {[dict exists $registry $documentId]} { error "Interactive Document '$documentId' already exists." }
    if {[file exists [file join $session metadata interactive_document_resources $documentId .retired.ini]]} {error "Document ID '$documentId' retains published scientific resources; choose a new ID"}
    set stored [_interactiveDocumentWritePayload $session $documentId $payload]
    set origin [_originCreate interactive_document [dict merge [dict create session_origin [sessionOriginRead $session]] $originParent]]
    if {$originParent ne {}} {dict lappend origin events [dict create kind receive_workspace installation_id [installationIdentityCurrent] at [projectTimestamp]]}
    set now [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    set item [dict create id $documentId module_id $moduleId provider_id $providerId format $format format_version $formatVersion sha256 [dict get $stored sha256] storage_name [dict get $stored storage_name] created_at $now updated_at $now revision 1 generation "document#[pid]-[clock clicks]"]
    if {[llength [info commands ::GX::_experimentDuplicationRegistrationReceipt]]} {
        set item [_experimentDuplicationRegistrationReceipt $item]
    }
    dict set item origin $origin
    if {[catch {
        dict set registry $documentId $item
        _interactiveDocumentRegistryWrite $session $registry
    } err opts]} {
        catch {file delete -force -- [file join [_interactiveDocumentStorageDir $session] [dict get $stored storage_name]]}
        return -options $opts $err
    }
    if {[llength [info commands _parameterWorkspaceMetadataSeed]]} {_parameterWorkspaceMetadataSeed $session $item $payload}
    return [_interactiveDocumentPublicMetadata $item]
}

proc ::GX::interactiveDocumentExists {documentId} {
    if {![interactiveDocumentIdValid $documentId]} { return 0 }
    set session [_interactiveDocumentRequireSession]
    return [dict exists [_interactiveDocumentRegistryRead $session] $documentId]
}

proc ::GX::interactiveDocumentList {{moduleId ""} {providerId ""}} {
    set session [_interactiveDocumentRequireSession]
    if {$moduleId ne "" || $providerId ne ""} {
        if {$moduleId eq "" || $providerId eq ""} { error "Interactive Document filtering requires both module and provider IDs." }
        lassign [_interactiveDocumentValidateOwner $moduleId $providerId] moduleId providerId
    }
    set out {}
    set registry [_interactiveDocumentRegistryRead $session]
    foreach id [lsort -dictionary [dict keys $registry]] {
        set item [dict get $registry $id]
        if {$moduleId ne "" && ([dict get $item module_id] ne $moduleId || [dict get $item provider_id] ne $providerId)} continue
        lappend out [_interactiveDocumentPublicMetadata $item]
    }
    return $out
}

proc ::GX::interactiveDocumentRead {documentId {historyPolicy stored}} {
    if {$historyPolicy ni {current stored}} {error {Unknown Document History read policy}}
    if {$historyPolicy eq {current} && [llength [info commands _historyDocumentBarrier]]} {_historyDocumentBarrier $documentId}
    if {![interactiveDocumentIdValid $documentId]} { error "Invalid Interactive Document ID '$documentId'." }
    set session [_interactiveDocumentRequireSession]
    set registry [_interactiveDocumentRegistryRead $session]
    if {![dict exists $registry $documentId]} { error "Interactive Document '$documentId' does not exist in the current Session." }
    set item [dict get $registry $documentId]
    set path [_interactiveDocumentPayloadPath $session $item]
    set actual [string tolower [sha256File $path]]
    if {$actual ne [string tolower [dict get $item sha256]]} {
        error "Interactive Document '$documentId' is corrupt: payload SHA-256 mismatch."
    }
    if {[catch {
        set fd [open $path r]
        fconfigure $fd -encoding utf-8 -translation lf
        set payload [read $fd]
        close $fd
    } err opts]} {
        catch {close $fd}
        return -options $opts "Interactive Document '$documentId' is unreadable: $err"
    }
    if {[llength [info commands _parameterWorkspaceMetadataSeed]]} {_parameterWorkspaceMetadataSeed $session $item $payload}
    set out [_interactiveDocumentPublicMetadata $item]
    dict set out payload $payload
    return $out
}

proc ::GX::interactiveDocumentUpdate {documentId payload {format ""} {formatVersion ""}} {
    if {![interactiveDocumentIdValid $documentId]} { error "Invalid Interactive Document ID '$documentId'." }
    set session [_interactiveDocumentRequireSession]
    set registry [_interactiveDocumentRegistryRead $session]
    if {![dict exists $registry $documentId]} { error "Interactive Document '$documentId' does not exist in the current Session." }
    set item [dict get $registry $documentId]
    set prior $item
    if {$format ne ""} { dict set item format [_interactiveDocumentValidateSingleLine $format "Document format"] }
    if {$formatVersion ne ""} { dict set item format_version [_interactiveDocumentValidateSingleLine $formatVersion "Document format version"] }
    if {([dict get $item format] ne [dict get $prior format] || [dict get $item format_version] ne [dict get $prior format_version]) && [llength [info commands ::GX::_experimentDuplicationDocumentTransition]]} {
        set item [_experimentDuplicationDocumentTransition $prior $item]
    }
    set oldStorage [dict get $item storage_name]
    set stored [_interactiveDocumentWritePayload $session $documentId $payload]
    if {[dict get $stored sha256] eq [dict get $prior sha256] && [dict get $item format] eq [dict get $prior format] && [dict get $item format_version] eq [dict get $prior format_version]} {if {[llength [info commands _parameterWorkspaceMetadataSeed]]} {_parameterWorkspaceMetadataSeed $session $item $payload};return [_interactiveDocumentPublicMetadata $item]}
    dict incr item revision
    dict set item sha256 [dict get $stored sha256]
    dict set item storage_name [dict get $stored storage_name]
    dict set item updated_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    dict set registry $documentId $item
    if {[catch {_interactiveDocumentRegistryWrite $session $registry} err opts]} {
        if {[dict get $stored storage_name] ne $oldStorage} {
            catch {file delete -force -- [file join [_interactiveDocumentStorageDir $session] [dict get $stored storage_name]]}
        }
        return -options $opts $err
    }
    if {$oldStorage ne [dict get $stored storage_name]} {
        catch {file delete -force -- [file join [_interactiveDocumentStorageDir $session] $oldStorage]}
    }
    if {[llength [info commands _parameterWorkspaceMetadataSeed]]} {_parameterWorkspaceMetadataSeed $session $item $payload}
    return [_interactiveDocumentPublicMetadata $item]
}

proc ::GX::interactiveDocumentDelete {documentId} {
    if {[llength [info commands _historyDocumentBarrier]]} {_historyDocumentBarrier $documentId}
    if {![interactiveDocumentIdValid $documentId]} { error "Invalid Interactive Document ID '$documentId'." }
    set session [_interactiveDocumentRequireSession]
    set registry [_interactiveDocumentRegistryRead $session]
    if {![dict exists $registry $documentId]} { error "Interactive Document '$documentId' does not exist in the current Session." }
    set item [dict get $registry $documentId]
    set resourcePlan {}
    if {[llength [info commands _documentResourceDeletePlan]]} {set resourcePlan [_documentResourceDeletePlan $documentId]}
    dict unset registry $documentId
    if {[catch {_interactiveDocumentRegistryWrite $session $registry} message options]} {
        if {$resourcePlan ne {}} {_documentResourceDeleteRollback $resourcePlan}
        return -options $options $message
    }
    set receipt [dict create api_id INTERACTIVE_DOCUMENT_API_v1 api_version 1 event deleted document_id $documentId owner_generation [dict get $item generation] revision [dict get $item revision] module_id [dict get $item module_id] provider_id [dict get $item provider_id] session_token [interactiveDocumentSessionToken]]
    try {
        if {$resourcePlan ne {}} {_documentResourceDeleteCommit $documentId $resourcePlan}
        if {[llength [info commands workbenchRecoveryForget]]} {workbenchRecoveryForget $documentId}
        file delete -- [file join [_interactiveDocumentStorageDir $session] [dict get $item storage_name]]
    } on error {message options} {
        dict set options -errorcode {GX DOCUMENT DELETE_COMMITTED}
        return -options $options "Document '$documentId' was deleted; owned-resource cleanup failed: $message"
    } finally {
        if {[llength [info commands _interactiveDocumentDeletedNotify]]} {_interactiveDocumentDeletedNotify $receipt}
    }
    return $documentId
}

# Opaque process-local Session identity for adapters that keep external UI
# processes alive. It intentionally does not expose the Session path and is not
# persisted as scientific state.
proc ::GX::interactiveDocumentSessionToken {} {
    _interactiveDocumentRequireSession
    _interactiveDocumentSessionChanged
    return $::GX::DocumentSessionScope::token
}

# Ownership checks need registry metadata, not a hash of the full scientific
# payload. Explicit payload reads continue to verify SHA-256 every time.
proc ::GX::interactiveDocumentMetadata {documentId} {
    if {![interactiveDocumentIdValid $documentId]} {error {Invalid Document ID}}
    set registry [_interactiveDocumentRegistryRead [_interactiveDocumentRequireSession]]
    if {![dict exists $registry $documentId]} {error {Document owner is unavailable}}
    return [_interactiveDocumentPublicMetadata [dict get $registry $documentId]]
}
