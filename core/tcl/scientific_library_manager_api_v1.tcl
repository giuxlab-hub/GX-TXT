# GX-TXT Scientific Library Manager API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificLibraryManagerAPIv1 {}
namespace eval ::GX::ScientificLibraryManagerAPIv1 {
    # Opaque owner/process identities only. No passwords, decrypted secrets or
    # encoded secret frames are retained in this map or timer/callback scripts.
    variable credentialContexts {}
    variable credentialSerial 0
    variable credentialClosing 0
    variable credentialOperationSerial 0
    # At most five monotonic attempt reservations, independent of worker/Session
    # replacement. No credential, durable store or account-wide claim.
    variable credentialAttempts {}
    variable credentialNativeAdmission {}
}

proc ::GX::ScientificLibraryManagerAPIv1::apiInfo {} {
    return [dict create api_name SCIENTIFIC_LIBRARY_MANAGER_API_v1 api_version 1 \
        registry_version 1 capability_schema gxtxt.library_capabilities.v1 \
        operations {listLibraryTypes resolveLibraryProvider getLibraryInfo listInstalledLibraries queryCompatibleLibraries installLibrary updateLibrary removeLibrary verifyLibrary openLibrary listLibraryEntries openLibraryEntry readLibrarySpectrum libraryRoot listRegisteredLibraries registerLibrary unregisterLibrary getProviderCapabilities getLibraryCapabilities libraryCatalogPage openLibraryViewer invokeLibraryAction libraryRequest libraryEntriesPage getLibraryEntryInfo searchLibraryEntries readLibraryEntry exportLibraryEntry addLibraryEntry removeLibraryEntry credentialStatus credentialLock credentialProfileAdmin bindLibraryCredentialProfile credentialPrepare credentialSubmit credentialFinish} \
        host_credential_operations {credentialPrepare credentialSubmit credentialFinish} \
        script_exposure intentional_subset \
        script_operations {api_info effective_root list_types list_libraries list_installed_libraries library_info compatible_libraries legacy_entries provider_capabilities library_capabilities catalog_page entries_page entry_info search_entries read_entry export_entry add_entry remove_entry credential_status credential_unlock credential_lock}]
}
proc ::GX::ScientificLibraryManagerAPIv1::_helper {} {
    set path [file join $::GX::scriptDir core python scientific_library_manager.py]
    if {![file isfile $path]} {error "Scientific Library Manager CORE helper is missing"}
    return $path
}
proc ::GX::ScientificLibraryManagerAPIv1::_run {operation args} {
    if {$operation in {content library_capabilities} && [llength $args]} {
        set owned [_credentialFind [lindex $args 0]]
        if {$owned ne {}} {
            set reply [_credentialExchange $owned $operation $args]
            if {![dict get $reply ok]} {
                _credentialLegacyFailure $reply
            }
            return [dict get $reply result wire]
        }
    }
    if {[llength [info commands ::GX::runtimeToolResolve]]} {
        set python [::GX::runtimeToolResolve python]
    } else {
        set python [auto_execok python3]
    }
    if {$python eq ""} {error "Scientific Library Manager requires a configured Python runtime"}
    # The loaded module catalog is the host's authoritative installed-provider
    # view. Pass its descriptors to the helper for this invocation only.
    set descriptors {}
    if {[info exists ::GX::moduleOrder]} {
        foreach id $::GX::moduleOrder {
            set path [::GX::moduleField $id descriptor ""]
            if {$path ne "" && [info exists ::GX::moduleCatalog($id,dict)] &&
                [::GX::descriptorValue $::GX::moduleCatalog($id,dict) library_type_provider api_version ""] eq "1"} {
                lappend descriptors $path
            }
        }
    }
    if {![info exists ::GX::moduleOrder]} {
        if {[info exists ::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS)]} {
            set descriptors [split $::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS) [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]]
        } else {
            # Preserve the old helper's direct-catalog fallback before a host
            # module catalog exists, without changing the host environment.
            set descriptors [glob -nocomplain -directory [file join $::GX::scriptDir plugins modules] */module.ini]
        }
    }
    # Tcl exec interprets redirection/pipeline words even in a proper argv list.
    # All variable arguments therefore use the EXISTING managed request stdin
    # envelope; only the configured runtime, fixed helper and --request-sync use argv.
    set payload [dict create operation $operation arguments $args provider_descriptors $descriptors]
    if {$operation eq {content}} {_contentCheckInput $payload
    } elseif {[string bytelength $payload]>1048576} {error {Scientific Library Manager request exceeds the 1 MiB input bound}}
    set command [list $python -B [_helper] --request-sync]
    set failed [catch {set result [exec {*}$command << $payload 2>@1]} reason options]
    if {$failed} {
        set result $reason
        # Tcl may append its own child-status line to a nonzero helper exit.
        # The fixed request envelope itself ends with category/result fields.
        if {[dict exists $options -errorcode] && [lindex [dict get $options -errorcode] 0] eq {CHILDSTATUS}} {
            regsub {\nchild process exited abnormally$} $result {} result
        }
    }
    # Reuse the existing recursive Tcl envelope, returning the exact old inner
    # F/L/M/P/D or C wire to its established operation-specific decoder.
    if {![catch {dict get $result ok} ok] && [string is boolean -strict $ok]} {
        if {$ok && !$failed && [dict exists $result result wire]} {
            return [string trimright [dict get $result result wire] "\n"]
        }
        if {!$ok && [dict exists $result error]} {
            set detail [dict get $result error]
            if {$failed} {return -options $options "Scientific Library Manager: $detail"}
            error "Scientific Library Manager: $detail"
        }
    }
    if {$failed} {
        set detail [lindex [split $reason "\n"] 0]
        regsub {^GX-TXT Scientific Library Manager: } $detail {} detail
        return -options $options "Scientific Library Manager: $detail"
    }
    error {Scientific Library Manager returned a malformed request response}
}
proc ::GX::ScientificLibraryManagerAPIv1::_decode {text} {
    return [encoding convertfrom utf-8 [binary decode base64 $text]]
}
proc ::GX::ScientificLibraryManagerAPIv1::_info {wire} {
    set out [dict create]
    if {$wire eq ""} {return $out}
    foreach line [split $wire "\n"] {
        set parts [split $line "\t"]
        if {[llength $parts] != 3 || [lindex $parts 0] ne "F"} {
            error "Scientific Library Manager returned malformed information"
        }
        dict set out [_decode [lindex $parts 1]] [_decode [lindex $parts 2]]
    }
    return $out
}
proc ::GX::ScientificLibraryManagerAPIv1::_list {wire} {
    set out {}
    if {$wire eq ""} {return $out}
    foreach line [split $wire "\n"] {
        set parts [split $line "\t"]
        if {[llength $parts] != 2 || [lindex $parts 0] ne "L"} {
            error "Scientific Library Manager returned a malformed list"
        }
        lappend out [_decode [lindex $parts 1]]
    }
    return $out
}
proc ::GX::ScientificLibraryManagerAPIv1::_spectrum {wire} {
    set out [dict create metadata [dict create] provenance [dict create] x {} y {}]
    foreach line [split $wire "\n"] {
        if {$line eq ""} continue
        set parts [split $line "\t"]
        set prefix [lindex $parts 0]
        if {$prefix eq "D"} {
            if {[llength $parts] != 3} {error "Scientific Library Manager returned malformed spectrum data"}
            dict lappend out x [lindex $parts 1]
            dict lappend out y [lindex $parts 2]
        } elseif {$prefix in {F M P}} {
            if {[llength $parts] != 3} {error "Scientific Library Manager returned malformed spectrum metadata"}
            set key [_decode [lindex $parts 1]]
            set value [_decode [lindex $parts 2]]
            switch -- $prefix {
                F {dict set out $key $value}
                M {dict set out metadata $key $value}
                P {dict set out provenance $key $value}
            }
        } else {error "Scientific Library Manager returned an unknown spectrum record"}
    }
    return $out
}

proc ::GX::ScientificLibraryManagerAPIv1::listLibraryTypes {} {return [_list [_run types]]}
proc ::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider {libraryType} {return [_info [_run provider $libraryType]]}
proc ::GX::ScientificLibraryManagerAPIv1::getLibraryInfo {libraryId} {return [_info [_run info $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::listInstalledLibraries {} {
    set out {}
    foreach libraryId [_list [_run list]] {lappend out [getLibraryInfo $libraryId]}
    return $out
}
proc ::GX::ScientificLibraryManagerAPIv1::queryCompatibleLibraries {libraryType} {
    return [_list [_run compatible $libraryType]]
}
proc ::GX::ScientificLibraryManagerAPIv1::installLibrary {packagePath} {
    return [_info [_run install [file normalize $packagePath]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::updateLibrary {libraryId packagePath} {
    return [_info [_run update $libraryId [file normalize $packagePath]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::removeLibrary {libraryId} {return [_info [_run remove $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::verifyLibrary {libraryId} {return [_info [_run verify $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::openLibrary {libraryId} {return [_info [_run open $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::listLibraryEntries {libraryId} {return [_list [_run entries $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::openLibraryEntry {libraryId entryId} {
    set library [openLibrary $libraryId]
    if {$entryId ni [listLibraryEntries $libraryId]} {
        error "Scientific Library Manager: entry '$entryId' is not in library '$libraryId'"
    }
    set provider [resolveLibraryProvider [dict get $library library_type]]
    set moduleId [dict get $provider entry_viewer_module]
    set viewerId [dict get $provider entry_viewer_id]
    if {$moduleId eq "" || $viewerId eq ""} {
        error "Scientific Library Manager: provider for '$libraryId' does not declare an entry viewer"
    }
    return [::GX::viewerOpen $moduleId $viewerId \
        [dict create library_id $libraryId entry_id $entryId]]
}
proc ::GX::ScientificLibraryManagerAPIv1::readLibrarySpectrum {libraryId spectrumId} {
    return [_spectrum [_run spectrum $libraryId $spectrumId]]
}

# Additive v1 registry contract. Configuration remains the public owner of
# libraries.scientific_root; the helper returns the same effective path.
proc ::GX::ScientificLibraryManagerAPIv1::libraryRoot {} {return [_run root]}
proc ::GX::ScientificLibraryManagerAPIv1::listRegisteredLibraries {} {
    set out {}
    foreach libraryId [_list [_run registered]] {lappend out [getLibraryInfo $libraryId]}
    return $out
}
proc ::GX::ScientificLibraryManagerAPIv1::registerLibrary {fields} {
    set args {}
    dict for {key value} $fields {lappend args $key $value}
    return [_info [_run register {*}$args]]
}
proc ::GX::ScientificLibraryManagerAPIv1::unregisterLibrary {libraryId} {
    return [_info [_run unregister $libraryId]]
}

# Additive Step2 capability discovery. Flat scalar keys preserve the existing
# information wire; no Python-repr dictionary or parallel registry is exposed.
proc ::GX::ScientificLibraryManagerAPIv1::getProviderCapabilities {libraryType} {return [_info [_run provider_capabilities $libraryType]]}
proc ::GX::ScientificLibraryManagerAPIv1::getLibraryCapabilities {libraryId} {return [_info [_run library_capabilities $libraryId]]}
proc ::GX::ScientificLibraryManagerAPIv1::libraryCatalogPage {{options {}}} {
    set values [dict merge {mode all query {} offset 0 limit 100} $options]
    foreach key [dict keys $options] {if {$key ni {mode query offset limit}} {error {Unknown Library catalog option}}}
    set raw [_info [_run catalog_page [dict get $values mode] [dict get $values query] [dict get $values offset] [dict get $values limit]]]
    return [_catalogPageDecode $raw]
}
proc ::GX::ScientificLibraryManagerAPIv1::_catalogPageDecode {raw} {
    set records {};set result {}
    dict for {key value} $raw {
        if {[regexp {^row\.([0-9]+)\.(.+)$} $key -> index field]} {dict set records $index $field $value} else {dict set result $key $value}
    }
    set rows {};foreach index [lsort -integer [dict keys $records]] {lappend rows [dict get $records $index]}
    dict set result records $rows
    return $result
}
proc ::GX::ScientificLibraryManagerAPIv1::openLibraryViewer {libraryId {context {}}} {
    set capability [getLibraryCapabilities $libraryId]
    set entry [expr {[dict exists $context entry_id] ? [dict get $context entry_id] : {}}]
    foreach key [dict keys $context] {if {$key ni {entry_id}} {error {Library opening accepts only an explicit entry_id context}}}
    set action [expr {$entry eq {} ? {open} : {entry_open}}]
    if {![dict exists $capability action.$action] || ![dict get $capability action.$action]} {error "Library action unavailable: [expr {[dict exists $capability reason.$action] ? [dict get $capability reason.$action] : {provider unavailable}}]"}
    set library [openLibrary $libraryId]
    set provider [resolveLibraryProvider [dict get $library library_type]]
    if {$entry ne {} && $entry ni [listLibraryEntries $libraryId]} {error {Selected library entry is stale or unavailable}}
    if {[dict get $provider library_viewer_module] ne {}} {
        set result [::GX::viewerOpen [dict get $provider library_viewer_module] [dict get $provider library_viewer_id] [dict merge $context [dict create library_id $libraryId]]]
        return [dict create status opened dispatch_kind library_viewer library_id $libraryId entry_id $entry result $result]
    }
    if {$entry eq {}} {set entry [lindex [listLibraryEntries $libraryId] 0]}
    if {$entry eq {}} {error {The registered entry Viewer requires a real library entry}}
    set result [openLibraryEntry $libraryId $entry]
    return [dict create status opened dispatch_kind entry_viewer library_id $libraryId entry_id $entry result $result]
}
proc ::GX::ScientificLibraryManagerAPIv1::invokeLibraryAction {libraryId actionId {parameters {}}} {
    set arguments {};dict for {key value} $parameters {lappend arguments $key $value}
    return [_info [_run library_action $libraryId $actionId {*}$arguments]]
}
proc ::GX::ScientificLibraryManagerAPIv1::libraryRequest {operation arguments callback} {
    if {$operation in {content library_capabilities} && [llength $arguments]} {
        set owned [_credentialFind [lindex $arguments 0]]
        if {$owned ne {}} {return [_credentialAsync $owned $operation $arguments $callback]}
    }
    if {$operation ni {catalog_page library_capabilities provider_capabilities library_action info entries verify install update remove register unregister provider types open content}} {error {Unsupported asynchronous Library operation}}
    # The helper still discovers the current authoritative installed providers.
    set descriptors {}
    foreach id $::GX::moduleOrder {
        if {[info exists ::GX::moduleCatalog($id,dict)] && [::GX::descriptorValue $::GX::moduleCatalog($id,dict) library_type_provider api_version {}] eq {1}} {lappend descriptors [::GX::moduleField $id descriptor]}
    }
    set options [dict create timeout_ms 120000 max_bytes 33554432 process_group 1 ui_lifetime 1 label {Scientific Library Manager}]
    # Public provider descriptor paths are inert request data, applied only to
    # this helper process's installed-provider view. No global host env change.
    set payload [dict create operation $operation arguments $arguments provider_descriptors $descriptors]
    if {$operation eq {content}} {_contentCheckInput $payload}
    return [::GX::scriptJobAsync [list [::GX::runtimeToolRequired python] -B [_helper] --request] $payload [list ::GX::ScientificLibraryManagerAPIv1::_requestDone $operation $callback] $options]
}
proc ::GX::ScientificLibraryManagerAPIv1::_requestDone {operation callback response} {
    if {[dict get $response ok]} {
        if {[catch {
            set wire [string trimright [dict get $response result wire] \n]
            if {$operation eq {content}} {set value [_contentDecode $wire]} elseif {$operation in {entries types}} {set value [_list $wire]} else {set value [_info $wire]}
            if {$operation eq {catalog_page}} {set value [_catalogPageDecode $value]}
            dict set response result $value
        } message options]} {
            set response [dict create ok 0 error $message category scientific_library_manager]
            if {[dict exists $options -errorcode] && [lrange [dict get $options -errorcode] 0 1] eq {GXTXT SCIENTIFIC_LIBRARY_MANAGER}} {
                dict set response error_code [lindex [dict get $options -errorcode] 2]
                if {[dict exists $options -library_error]} {dict set response error_details [dict get $options -library_error]}
            }
        }
    }
    uplevel #0 [list {*}$callback $response]
}

# Additive Step3 host/module content contract. The Step4 API-owned Bridge grants
# only its reviewed restricted forms; no automatic exposure of these procedures.
# Explicit JSON text preserves provider-owned input types without type guessing.
proc ::GX::ScientificLibraryManagerAPIv1::_contentOptions {options paging} {
    set out {}
    dict for {key value} $options {
        if {$key eq {provider_json}} {dict set out options_json $value
        } elseif {$paging && $key in {limit continuation}} {dict set out $key $value
        } else {error {Unknown Library content option}}
    }
    return $out
}
proc ::GX::ScientificLibraryManagerAPIv1::_contentDecode {wire} {
    if {[string length $wire]>25165824 || [llength [split $wire \n]]!=1} {error {Malformed or oversized Library content response}}
    set parts [split $wire \t]
    if {[llength $parts]!=2 || [lindex $parts 0] ne {C} || [regexp {[^A-Za-z0-9+/=]} [lindex $parts 1]]} {error {Malformed Library content wire}}
    set response [_decode [lindex $parts 1]]
    if {[dict get $response schema] ne {gxtxt.library_content_response.v1} || ![string is boolean -strict [dict get $response ok]]} {error {Unsupported Library content response schema}}
    foreach key [dict keys $response] {if {$key ni {schema ok operation result error}} {error {Unknown Library content response field}}}
    if {[dict exists $response operation] && [dict get $response operation] ni {list_entries entry_info search_entries read_entry export_entry add_entry remove_entry}} {error {Unsupported Library content operation response}}
    if {![dict get $response ok]} {
        set detail [dict get $response error];set code [dict get $detail code]
        if {$code ni {unsupported_operation library_not_found entry_not_found read_only authentication_required credentials_locked authentication_failed rate_limited temporarily_unavailable provider_unavailable invalid_provider_configuration integrity_failure policy_restricted provider_failure invalid_request invalid_provider_response}} {error {Invalid Library content error code}}
        return -options [dict create -code error -level 0 -errorcode [list GXTXT SCIENTIFIC_LIBRARY_MANAGER $code] -library_error $detail] [dict get $detail message]
    }
    set result [dict get $response result]
    if {[dict get $result schema] ni {gxtxt.library_entry_page.v1 gxtxt.library_entry_info.v1 gxtxt.library_entry.v1 gxtxt.library_entry_export.v1 gxtxt.library_entry_mutation.v1} || ![dict exists $result result_json]} {error {Unsupported Library content result schema}}
    return $result
}
proc ::GX::ScientificLibraryManagerAPIv1::_contentCall {libraryId operation parameters} {
    _contentCheckInput [list $libraryId $operation $parameters]
    return [_contentDecode [_run content $libraryId $operation $parameters]]
}
proc ::GX::ScientificLibraryManagerAPIv1::_contentCheckInput {payload} {
    if {[string bytelength $payload]>1048576} {
        set detail [dict create code invalid_request message {Library content request exceeds the 1 MiB input bound.}]
        return -options [dict create -code error -level 0 -errorcode {GXTXT SCIENTIFIC_LIBRARY_MANAGER invalid_request} -library_error $detail] [dict get $detail message]
    }
}
proc ::GX::ScientificLibraryManagerAPIv1::libraryEntriesPage {libraryId {options {}}} {
    return [_contentCall $libraryId list_entries [_contentOptions $options 1]]
}
proc ::GX::ScientificLibraryManagerAPIv1::getLibraryEntryInfo {libraryId entryId {options {}}} {
    return [_contentCall $libraryId entry_info [dict merge [_contentOptions $options 0] [dict create entry_id $entryId]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::searchLibraryEntries {libraryId queryJson {options {}}} {
    return [_contentCall $libraryId search_entries [dict merge [_contentOptions $options 1] [dict create query_json $queryJson]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::readLibraryEntry {libraryId entryId {options {}}} {
    return [_contentCall $libraryId read_entry [dict merge [_contentOptions $options 0] [dict create entry_id $entryId]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::exportLibraryEntry {libraryId entryId format {options {}}} {
    return [_contentCall $libraryId export_entry [dict merge [_contentOptions $options 0] [dict create entry_id $entryId format $format]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::addLibraryEntry {libraryId entryJson {options {}}} {
    return [_contentCall $libraryId add_entry [dict merge [_contentOptions $options 0] [dict create entry_json $entryJson]]]
}
proc ::GX::ScientificLibraryManagerAPIv1::removeLibraryEntry {libraryId entryId {options {}}} {
    return [_contentCall $libraryId remove_entry [dict merge [_contentOptions $options 0] [dict create entry_id $entryId]]]
}

# Step5 source implementation, MAIN503/523. Secret submission is deliberately
# fail-closed until MAIN accepts/provides the protected diagnostic boundary.
# An ordinary catch around scriptJobRequestSend cannot establish F3: Tcl's last
# error stack can contain its actual reversible payload argument. No reset of
# errorInfo/errorstack, redaction after logging or native availability is claimed.
proc ::GX::ScientificLibraryManagerAPIv1::_credentialError {code {outcome not_dispatched}} {
    set messages [dict create invalid_request {Invalid credential request.} \
        unavailable {Protected credential transport is unavailable.} \
        credentials_locked {Library credentials are locked.} \
        busy {The owned credential context is busy or still draining.} \
        transport_failure {The owned credential operation did not return a verified result.} \
        stale_context {The captured credential context is no longer current.}]
    if {![dict exists $messages $code]} {set code unavailable}
    set value [dict create schema gxtxt.library_credential_response.v1 ok 0 code $code message [dict get $messages $code]]
    if {$outcome eq {unknown}} {dict set value mutation_outcome unknown;dict set value message {Mutation outcome is unknown. Inspect the exact profile or binding revision before any further mutation.}}
    return $value
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialLegacyFailure {reply} {
    set code [dict get $reply code]
    switch -- $code {
        unavailable {set code unsupported_operation}
        busy {set code temporarily_unavailable}
        transport_failure {set code provider_failure}
        stale_context {set code credentials_locked}
    }
    set detail [dict create code $code message {Protected Library operation was refused.}]
    if {[dict exists $reply mutation_outcome] && [dict get $reply mutation_outcome] eq {unknown}} {
        dict set detail mutation_outcome unknown
        dict set detail message {Library mutation outcome is unknown; reconcile provider state before retry.}
    }
    return -options [dict create -code error -level 0 -errorcode [list GXTXT SCIENTIFIC_LIBRARY_MANAGER $code] -library_error $detail] [dict get $detail message]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialMutation {operation arguments} {
    return [expr {$operation eq {bind} || ($operation eq {profile_admin} && [lindex $arguments 0] in {create replace delete}) || ($operation eq {content} && [lindex $arguments 1] in {add_entry remove_entry})}]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialDescriptors {} {
    set result {}
    if {![info exists ::GX::moduleOrder]} {return $result}
    foreach id $::GX::moduleOrder {
        if {[info exists ::GX::moduleCatalog($id,dict)] && [::GX::descriptorValue $::GX::moduleCatalog($id,dict) library_type_provider api_version {}] eq {1}} {
            lappend result [::GX::moduleField $id descriptor]
        }
    }
    return $result
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialCurrent {record} {
    if {[dict get $record revoked]} {return 0}
    if {[file normalize [::GX::configurationPath]] ne [dict get $record configuration]} {return 0}
    if {[dict get $record role] eq {admin}} {return 1}
    return [expr {$::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [dict get $record session] && [::GX::interactiveDocumentSessionToken] eq [dict get $record session_token]}]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialFind {library} {
    variable credentialContexts
    dict for {id record} $credentialContexts {
        if {[dict get $record role] eq {runtime} && [dict get $record library] eq $library} {
            if {[catch {_credentialCurrent $record} current] || !$current} {_credentialRevoke $id;continue}
            return $id
        }
    }
    return {}
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialSessionChanged {args} {
    variable credentialContexts
    # Session identity is captured by the existing public token owner, including
    # the same-path directory replacement case. No private Document state read.
    dict for {id record} $credentialContexts {
        if {[dict get $record role] ne {runtime}} continue
        if {[catch {_credentialCurrent $record} current] || !$current} {_credentialRevoke $id}
    }
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialSessionTrace {} {
    set callback [list ::GX::ScientificLibraryManagerAPIv1::_credentialSessionChanged]
    foreach trace [trace info variable ::GX::currentSession] {
        if {[lsort [lindex $trace 0]] eq {unset write} && [lindex $trace 1] eq $callback} return
    }
    trace add variable ::GX::currentSession {write unset} $callback
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialFrame {record operation arguments} {
    if {$operation eq {credential_unlock} || ($operation eq {profile_admin} && [lindex $arguments 0] in {create replace})} {return {}}
    set payload [dict create operation $operation arguments $arguments provider_descriptors [dict get $record descriptors]]
    set bytes [encoding convertto utf-8 $payload]
    set size [string length [encoding convertto utf-8 $arguments]]
    if {$size>32768 || ($operation in {credential_unlock profile_admin bind} && $size>16384)} {return {}}
    set frame "GXTXT_LIBRARY_RUNTIME_V1\t[binary encode base64 -maxlen 0 $bytes]"
    # Existing Send independently includes actual queued channel bytes before
    # any write; this preflight does not inspect its private channel or state.
    if {[string length [encoding convertto utf-8 $frame]]+1>65536} {return {}}
    return $frame
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialDecode {frame} {
    if {[string length [encoding convertto utf-8 $frame]]>33554432 || [llength [split $frame \t]]!=2 || [lindex [split $frame \t] 0] ne {GXTXT_LIBRARY_RUNTIME_V1}} {return [_credentialError transport_failure]}
    set encoded [lindex [split $frame \t] 1]
    if {[regexp {[^A-Za-z0-9+/=]} $encoded]} {return [_credentialError transport_failure]}
    if {[catch {
        set bytes [binary decode base64 -strict $encoded]
        set value [encoding convertfrom utf-8 $bytes]
        if {[encoding convertto utf-8 $value] ne $bytes || [binary encode base64 -maxlen 0 $bytes] ne $encoded} {error invalid}
        if {[dict get $value schema] ne {gxtxt.library_credential_response.v1}} {error invalid}
        if {![string is boolean -strict [dict get $value ok]]} {error invalid}
        if {[dict get $value ok]} {
            if {[lsort [dict keys $value]] ne {ok result schema}} {error invalid}
            dict size [dict get $value result]
        } else {
            foreach key [dict keys $value] {if {$key ni {schema ok code message mutation_outcome}} {error invalid}}
            if {[dict get $value code] ni {invalid_request library_not_found unsupported_operation credentials_locked authentication_required authentication_failed provider_unavailable temporarily_unavailable invalid_provider_configuration integrity_failure policy_restricted provider_failure invalid_provider_response rate_limited read_only entry_not_found}} {error invalid}
            # Provider/runtime free text is not trusted as a diagnostic.
            dict set value message {Protected Library operation was refused.}
            if {[dict exists $value mutation_outcome] && [dict get $value mutation_outcome] ne {unknown}} {error invalid}
        }
    }]} {return [_credentialError transport_failure]}
    dict set value schema gxtxt.library_credential_response.v1
    return $value
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialNew {role library} {
    variable credentialContexts;variable credentialSerial;variable credentialClosing
    if {$credentialClosing} {return {}}
    _credentialSessionTrace
    if {[dict size $credentialContexts]>=4} {return {}}
    dict for {existing record} $credentialContexts {
        if {[dict get $record role] eq $role && [dict get $record library] eq $library} {return {}}
    }
    set configuration [file normalize [::GX::configurationPath]]
    set session {};set token {}
    if {$role eq {runtime}} {
        if {$::GX::currentSession eq {}} {return {}}
        set session [file normalize $::GX::currentSession];set token [::GX::interactiveDocumentSessionToken]
    }
    # Exactly16 random bytes, kept only as an owner identity (never an unlock
    # grant or transferable secret). Linux private runtime is the accepted slice.
    set random [open /dev/urandom rb]
    try {set bytes [read $random 16]} finally {close $random}
    if {[string length $bytes]!=16} {return {}}
    set owner [binary encode hex $bytes]
    set id credential-context-[incr credentialSerial]
    set init [dict create protocol_version 1 role $role owner_id $owner owner_pid [pid] session $session library_id $library configuration_file $configuration library_root [libraryRoot]]
    set record [dict create role $role library $library session $session session_token $token configuration $configuration descriptors [_credentialDescriptors] revoked 0 busy 0 generation $owner request {} callback {} poll {} mutation 0 dispatched 0]
    set request [::GX::scriptJobAsync [list [::GX::runtimeToolRequired python] -B [_helper] --runtime] {} [list ::GX::ScientificLibraryManagerAPIv1::_credentialEnded $id $owner] [dict create timeout_ms 0 max_bytes 33554432 process_group 1 ui_lifetime 1 duplex 1 label {Protected Library context}]]
    dict set record request $request
    dict set credentialContexts $id $record
    if {[catch {_credentialExchange $id runtime_init [list $init]} reply] ||
        ![dict get $reply ok] || ![dict exists $reply result ready] || ![dict get $reply result ready]} {_credentialRevoke $id;return {}}
    return $id
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialExchange {id operation arguments} {
    variable credentialContexts
    if {![dict exists $credentialContexts $id]} {return [_credentialError credentials_locked]}
    set record [dict get $credentialContexts $id]
    if {[dict get $record busy]} {return [_credentialError busy]}
    # A successor request retires the one completed protected reference. A late
    # caller epilogue must not revoke this new request using the prior REF.
    if {[dict exists $record protected] && [dict get $record protected phase] eq {consumed}} {
        dict unset record protected;dict set credentialContexts $id $record
    }
    if {![_credentialCurrent $record]} {_credentialRevoke $id;return [_credentialError stale_context]}
    set frame [_credentialFrame $record $operation $arguments]
    if {$frame eq {}} {return [_credentialError invalid_request]}
    set mutation [_credentialMutation $operation $arguments]
    dict set credentialContexts $id busy 1
    # This Tcl seam is for nonsecret content/metadata only. The future protected
    # boundary owns plaintext and reversible frames natively. MAIN003's separate
    # nonsecret Finish receives only after the complete native Submit returns.
    if {[catch {::GX::scriptJobRequestSend [dict get $record request] $frame} unused sendOptions]} {
        # Only these actual existing-owner codes certify refusal before write.
        # A channel/partial-write failure conservatively remains uncertain.
        set known 0
        if {[dict exists $sendOptions -errorcode] && [dict get $sendOptions -errorcode] in {{GXTXT SCRIPT_JOB INACTIVE} {GXTXT SCRIPT_JOB FRAME} {GXTXT SCRIPT_JOB BUSY}}} {set known 1}
        _credentialRevoke $id
        return [_credentialError transport_failure [expr {$mutation && !$known?{unknown}:{not_dispatched}}]]
    }
    if {[catch {
        set response [::GX::scriptJobRequestExchange [dict get $record request] {} [expr {$operation in {profile_admin bind}?15000:10000}]]
        set reply [_credentialDecode $response]
    }]} {
        _credentialRevoke $id
        return [_credentialError transport_failure [expr {$mutation?{unknown}:{not_dispatched}}]]
    }
    if {[dict exists $credentialContexts $id] && [dict get $credentialContexts $id generation] eq [dict get $record generation]} {dict set credentialContexts $id busy 0}
    if {![_credentialCurrent $record]} {_credentialRevoke $id;return [_credentialError stale_context [expr {$mutation?{unknown}:{not_dispatched}}]]}
    if {![dict get $reply ok] && [dict get $reply code] eq {transport_failure}} {_credentialRevoke $id;if {$mutation} {return [_credentialError transport_failure unknown]}}
    return $reply
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialRevoke {id} {
    variable credentialContexts
    if {![dict exists $credentialContexts $id]} {return 0}
    dict set credentialContexts $id revoked 1
    set record [dict get $credentialContexts $id]
    catch {::GX::scriptJobRequestCancel [dict get $record request] cancelled}
    if {[dict get $record poll] eq {}} {dict set credentialContexts $id poll [after 25 [list ::GX::ScientificLibraryManagerAPIv1::_credentialDrain $id [dict get $record generation]]]}
    return 1
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialDrain {id generation} {
    variable credentialContexts
    if {![dict exists $credentialContexts $id] || [dict get $credentialContexts $id generation] ne $generation} return
    if {[dict get $credentialContexts $id poll] ne {}} {after cancel [dict get $credentialContexts $id poll]}
    dict set credentialContexts $id poll {}
    set request [dict get $credentialContexts $id request]
    if {[catch {set state [::GX::scriptJobRequestDrain $request 1]}]} {
        # No timer/exception is a completed cleanup certificate. Retain revoked
        # ownership, fail busy, and let the actual terminal owner close it.
        return
    }
    if {![dict exists $credentialContexts $id]} return
    if {![dict get $state active]} {_credentialEnded $id $generation {};return}
    dict set credentialContexts $id poll [after 25 [list ::GX::ScientificLibraryManagerAPIv1::_credentialDrain $id $generation]]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialEnded {id generation response} {
    variable credentialContexts
    if {![dict exists $credentialContexts $id] || [dict get $credentialContexts $id generation] ne $generation} return
    set record [dict get $credentialContexts $id]
    if {[dict get $record poll] ne {}} {after cancel [dict get $record poll]}
    dict unset credentialContexts $id
    if {[dict exists $record protected]} {
        _credentialAttemptRelease $record 0
        set completion [dict get $record protected completion]
        if {$completion ne {}} {
            set failure [_credentialProtectedFailure $record]
            catch {uplevel #0 [list {*}$completion $failure]}
        }
    }
    if {[dict get $record callback] ne {}} {
        set failure [_credentialError transport_failure [expr {[dict get $record mutation] && [dict get $record dispatched]?{unknown}:{not_dispatched}}]]
        catch {uplevel #0 [list {*}[dict get $record callback] $failure]}
    }
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialCleanup {} {
    variable credentialContexts;variable credentialClosing
    set credentialClosing 1
    foreach id [dict keys $credentialContexts] {_credentialRevoke $id}
    # No nested event pump. Existing Drain remains the only observation owner;
    # on current ScriptJob source its500ms escalation uses after and may remain
    # pending while a synchronous Bridge is leaving. Do not turn a deadline or
    # requested TERM into a false locked/cleanup-complete receipt.
    set deadline [expr {[clock milliseconds]+1500}]
    while {[dict size $credentialContexts] && [clock milliseconds]<$deadline} {
        foreach id [dict keys $credentialContexts] {
            if {[dict exists $credentialContexts $id]} {_credentialDrain $id [dict get $credentialContexts $id generation]}
        }
        if {[dict size $credentialContexts]} {after 5}
    }
    return [dict create revoked 1 cleanup_pending [expr {[dict size $credentialContexts]>0}] remaining_contexts [dict size $credentialContexts]]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialAsync {id operation arguments callback} {
    variable credentialContexts
    set record [dict get $credentialContexts $id]
    if {[dict get $record busy] || ![_credentialCurrent $record]} {error {Protected Library context is busy or stale}}
    if {[dict exists $record protected] && [dict get $record protected phase] eq {consumed}} {
        dict unset record protected;dict set credentialContexts $id $record
    }
    set frame [_credentialFrame $record $operation $arguments]
    if {$frame eq {}} {error {Protected Library request exceeds its bounded frame}}
    dict set credentialContexts $id busy 1
    dict set credentialContexts $id mutation [_credentialMutation $operation $arguments]
    dict set credentialContexts $id dispatched 1
    dict set credentialContexts $id callback [list ::GX::ScientificLibraryManagerAPIv1::_credentialAsyncDecoded $operation $callback]
    if {[catch {::GX::scriptJobRequestSend [dict get $record request] $frame} unused sendOptions]} {
        if {[dict exists $sendOptions -errorcode] && [dict get $sendOptions -errorcode] in {{GXTXT SCRIPT_JOB INACTIVE} {GXTXT SCRIPT_JOB FRAME} {GXTXT SCRIPT_JOB BUSY}}} {dict set credentialContexts $id dispatched 0}
        _credentialRevoke $id
        return [dict get $record request]
    }
    dict set credentialContexts $id poll [after 0 [list ::GX::ScientificLibraryManagerAPIv1::_credentialAsyncPoll $id [dict get $record generation]]]
    return [dict get $record request]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialAsyncPoll {id generation} {
    variable credentialContexts
    if {![dict exists $credentialContexts $id] || [dict get $credentialContexts $id generation] ne $generation} return
    dict set credentialContexts $id poll {}
    set record [dict get $credentialContexts $id]
    if {![_credentialCurrent $record]} {_credentialRevoke $id;return}
    if {[catch {set state [::GX::scriptJobRequestDrain [dict get $record request] 1]}]} {_credentialRevoke $id;return}
    if {![dict exists $credentialContexts $id]} return
    if {![dict get $state active] || [dict get $state cancelled] ne {}} {_credentialRevoke $id;return}
    if {[llength [dict get $state messages]]} {
        set reply [_credentialDecode [lindex [dict get $state messages] 0]]
        if {![dict get $reply ok] && [dict get $reply code] eq {transport_failure}} {
            if {[dict get $record mutation] && [dict get $record dispatched]} {set reply [_credentialError transport_failure unknown]}
            _credentialRevoke $id
            # Deliver once using captured callback; later terminal sees none.
        }
        dict set credentialContexts $id busy 0;dict set credentialContexts $id callback {}
        if {![_credentialCurrent $record]} {_credentialRevoke $id;return}
        uplevel #0 [list {*}[dict get $record callback] $reply]
    } else {dict set credentialContexts $id poll [after 25 [list ::GX::ScientificLibraryManagerAPIv1::_credentialAsyncPoll $id $generation]]}
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialAsyncDecoded {operation callback response} {
    if {[dict get $response ok]} {
        # Feed the existing request decoder, preserving its established C/F wire
        # schema rather than inventing a parallel scientific result contract.
        _requestDone $operation $callback [dict create ok 1 result [dict get $response result]]
    } else {
        set code [dict get $response code]
        switch -- $code {
            unavailable {set code unsupported_operation}
            busy {set code temporarily_unavailable}
            transport_failure {set code provider_failure}
            stale_context {set code credentials_locked}
        }
        set value [dict create ok 0 category scientific_library_manager error {Protected Library operation was refused.} error_code $code]
        if {[dict exists $response mutation_outcome] && [dict get $response mutation_outcome] eq {unknown}} {
            dict set value mutation_outcome unknown
            dict set value error_details [dict create code $code message {Library mutation outcome is unknown; reconcile provider state before retry.} mutation_outcome unknown]
        }
        uplevel #0 [list {*}$callback $value]
    }
}
# MAIN003: Prepare and Finish are NONSECRET entrypoints. Submit is installed
# directly by the matching native Library package; there is no Tcl Submit shim.
# Trusted normal bootstrap only. Both exact artifacts are checked before the
# first load. No compiler, Tcl Submit shim, package-name fallback or hot reload.
proc ::GX::ScientificLibraryManagerAPIv1::_credentialLoadNative {root} {
    variable credentialNativeAdmission
    variable credentialContexts
    set credentialNativeAdmission {}
    if {$credentialContexts ne {} || $::tcl_platform(os) ne {Linux} ||
        [package vcompare [info tclversion] 8.6] != 0} {return 0}
    set artifacts {
        gxtxt_script_job_channel.so f1d8434edd6a7fe71001ef34f656ad7bdd55a1b45618b46186b77b6336924e14 Gxtxtscriptjobchannel
        gxtxt_library_credentials_native.so 2ed0d9e746b232096274b3ba5784c7d27c40b7ec077bfd1626038c20cb0e9066 Gxtxtlibrarycredentialsnative
    }
    if {[catch {
        set root [file normalize $root]
        if {$root ne [file normalize $::GX::scriptDir]} {error {Wrong native owner}}
        set bin [file join $root core tcl bin]
        file lstat $bin directory
        if {$directory(type) ne {directory}} {error {Native directory unavailable}}
        set checked {}
        foreach {name expected init} $artifacts {
            set path [file join $bin $name]
            file lstat $path fileInfo
            if {$fileInfo(type) ne {file} || $fileInfo(nlink) != 1 ||
                [::GX::sha256File $path] ne $expected} {error {Native artifact unavailable}}
            foreach loaded [info loaded] {
                if {[lindex $loaded 1] eq $init && [lindex $loaded 0] ne $path} {
                    error {Native owner already belongs to another root}
                }
            }
            lappend checked $path $init
        }
        foreach {path init} $checked {load $path $init}
    }]} {return 0}
    set credentialNativeAdmission [dict create root $root artifacts $artifacts]
    if {![_credentialNativeReady]} {set credentialNativeAdmission {};return 0}
    return 1
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialNativeInfo {} {
    variable credentialNativeAdmission
    if {$credentialNativeAdmission eq {} || [dict get $credentialNativeAdmission root] ne [file normalize $::GX::scriptDir]} {return {}}
    if {![llength [info commands ::GX::ScientificLibraryCredentialsNative::info]]} {return {}}
    if {[catch {
        set info [::GX::ScientificLibraryCredentialsNative::info]
        expr {[dict get $info schema] eq {gxtxt.library_credentials_native.v1} &&
            [dict get $info ready] eq {1} && [string is wideinteger -strict [dict get $info monotonic_ms]]}
    } ready] || !$ready} {return {}}
    return $info
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialNativeReady {} {
    return [expr {[_credentialNativeInfo] ne {}}]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialOperationEnvelope {ref state} {
    return [dict create schema gxtxt.library_credential_operation.v1 ok 1 operation_ref $ref state $state]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialOperationRecord {ref} {
    variable credentialContexts
    if {[catch {lsort [dict keys $ref]} keys] || $keys ne {context_id generation operation_id}} {return {}}
    set id [dict get $ref context_id];set generation [dict get $ref generation];set operation [dict get $ref operation_id]
    if {![regexp {^credential-context-[1-9][0-9]*$} $id] || [string length $id]>64 ||
        ![regexp {^[0-9a-f]{32}$} $generation] ||
        ![regexp {^credential-operation-[1-9][0-9]*$} $operation] || [string length $operation]>64 ||
        ![dict exists $credentialContexts $id]} {return {}}
    set record [dict get $credentialContexts $id]
    if {[dict get $record generation] ne $generation || ![dict exists $record protected] ||
        [dict get $record protected operation_id] ne $operation} {return {}}
    return $record
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialAttemptRelease {record success} {
    variable credentialAttempts
    if {![dict exists $record protected] || [dict get $record protected operation] ne {unlock}} return
    # Only verified success or certified no-write refunds this exact attempt.
    if {$success || ![dict get $record protected dispatched]} {
        set key [dict get $record protected operation_id]
        if {[dict exists $credentialAttempts $key]} {dict unset credentialAttempts $key}
    }
}
proc ::GX::ScientificLibraryManagerAPIv1::credentialPrepare {operation metadata} {
    variable credentialContexts;variable credentialOperationSerial;variable credentialAttempts
    set info [_credentialNativeInfo]
    if {$info eq {}} {return [_credentialError unavailable]}
    # Qualification is before protected inputs. Never remove owner traces or
    # pretend public C variable APIs cannot invoke them under a hostile host.
    foreach ownerVariable {::GX::ScientificLibraryManagerAPIv1::credentialContexts ::GX::scriptJobRequests} {
        if {[llength [trace info variable $ownerVariable]]} {return [_credentialError unavailable]}
    }
    if {[catch {lsort [dict keys $metadata]} keys]} {return [_credentialError invalid_request]}
    set role admin;set library {};set budget 15000
    switch -- $operation {
        unlock {
            if {$keys ne {library_id lifetime_seconds}} {return [_credentialError invalid_request]}
            set library [dict get $metadata library_id];set ttl [dict get $metadata lifetime_seconds]
            if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]*$} $library] || [string bytelength $library]>32768 ||
                ![regexp {^[1-9][0-9]{0,2}$} $ttl] || $ttl>900} {return [_credentialError invalid_request]}
            set role runtime;set budget 10000
        }
        profile_create - profile_replace {
            if {$keys ne {expected_revision profile_id provider_id}} {return [_credentialError invalid_request]}
            foreach field {profile_id provider_id} {
                set value [dict get $metadata $field]
                if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$} $value] || $value in {. ..}} {return [_credentialError invalid_request]}
            }
            set revision [dict get $metadata expected_revision]
            if {($operation eq {profile_create} && $revision ne {absent}) ||
                ($operation eq {profile_replace} && ![regexp {^[0-9a-f]{64}$} $revision])} {return [_credentialError invalid_request]}
        }
        default {return [_credentialError invalid_request]}
    }
    set now [dict get $info monotonic_ms]
    dict for {key stamp} $credentialAttempts {if {$now-$stamp>=60000} {dict unset credentialAttempts $key}}
    if {$operation eq {unlock} && [dict size $credentialAttempts]>=5} {return [_credentialError busy]}
    # Fresh unlock deliberately refuses an existing runtime, preserving its grant
    # on abandoned preparation. Caller explicitly Lock/drains before re-unlock.
    if {$role eq {runtime} && [_credentialFind $library] ne {}} {return [_credentialError busy]}
    set id [_credentialNew $role $library]
    if {$id eq {}} {return [_credentialError unavailable]}
    set record [dict get $credentialContexts $id]
    set serial credential-operation-[incr credentialOperationSerial]
    set ref [dict create context_id $id generation [dict get $record generation] operation_id $serial]
    dict set record busy 1
    dict set record protected [dict create operation_id $serial operation $operation metadata $metadata phase prepared \
        deadline_ms [expr {$now+$budget}] mutation [expr {$role eq {admin}}] dispatched 0 submit_code {} completion {} finish_claimed 0]
    dict set credentialContexts $id $record
    if {$operation eq {unlock}} {dict set credentialAttempts $serial $now}
    set current [_credentialNativeInfo]
    if {$current eq {} || [dict get $current monotonic_ms]>=[dict get $record protected deadline_ms]} {
        _credentialAttemptRelease $record 0;_credentialRevoke $id
        return [_credentialError unavailable]
    }
    return [_credentialOperationEnvelope $ref prepared]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialProtectedFinal {ref record reply} {
    variable credentialContexts
    set id [dict get $ref context_id]
    set success [expr {[dict exists $reply ok] && [dict get $reply ok]}]
    if {$success && [dict get $record role] eq {runtime}} {
        set valid 0
        if {[catch {
            set value [dict get $reply result]
            set valid [expr {[lsort [dict keys $value]] eq {authentication_required authentication_status cleanup_pending configured expires_in_seconds library_id result_json} &&
                [dict get $value library_id] eq [dict get $record library] &&
                [dict get $value authentication_status] eq {unlocked} &&
                [dict get $value configured] in {1 true} && [dict get $value cleanup_pending] in {0 false} &&
                [string is integer -strict [dict get $value expires_in_seconds]] &&
                [dict get $value expires_in_seconds]>0 && [dict get $value expires_in_seconds]<=900 &&
                [dict get $value authentication_required] in {1 true} &&
                [string bytelength [dict get $value result_json]]>0 &&
                [string bytelength [dict get $value result_json]]<=16384}]
        }]} {set valid 0}
        if {$valid} {
            # This private worker emits a fixed canonical six-field JSON sidecar.
            # Compare that exact closed representation, rather than infer JSON
            # booleans from arbitrary strings or refund before caller validation.
            set expected [format {{"library_id":"%s","configured":true,"authentication_required":true,"authentication_status":"unlocked","expires_in_seconds":%d,"cleanup_pending":false}} [dict get $record library] [dict get $value expires_in_seconds]]
            if {[dict get $value result_json] ne $expected} {set valid 0}
        }
        if {!$valid} {set success 0;set reply [_credentialProtectedFailure $record]}
    }
    # Acknowledged admin truth survives UI/Session retirement. A dead runtime
    # cannot return a current unlocked grant even if an earlier ACK was valid.
    if {[dict get $record role] eq {admin}} {
        if {[_credentialOperationRecord $ref] ne {}} {_credentialRevoke $id}
        return $reply
    }
    if {[_credentialOperationRecord $ref] eq {} || [catch {_credentialCurrent $record} current] || !$current} {
        _credentialAttemptRelease $record 0
        if {[_credentialOperationRecord $ref] ne {}} {_credentialRevoke $id}
        return [_credentialError stale_context]
    }
    # Sample after decode, JSON agreement and potentially fallible current-source
    # inspection, immediately before grant admission/refund. This is independent
    # of the unlock TTL which starts in the actual worker on successful unlock.
    set admission [_credentialNativeInfo]
    if {$admission eq {} || [dict get $admission monotonic_ms]>=[dict get $record protected deadline_ms]} {
        set success 0;set reply [_credentialProtectedFailure $record]
    }
    _credentialAttemptRelease $record $success
    if {!$success} {_credentialRevoke $id;return $reply}
    # Retain one nonsecret completed identity through caller type validation.
    # The next ordinary request retires it before dispatch, preventing a late
    # validation-failure epilogue from cancelling a successor operation.
    dict set credentialContexts $id protected phase consumed
    dict set credentialContexts $id protected completion {}
    dict set credentialContexts $id busy 0
    return $reply
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialProtectedFailure {record} {
    set unknown [expr {[dict get $record protected mutation] && [dict get $record protected dispatched]}]
    return [_credentialError transport_failure [expr {$unknown?{unknown}:{not_dispatched}}]]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialQuarantine {ref} {
    set record [_credentialOperationRecord $ref]
    if {$record eq {}} {return 0}
    set id [dict get $ref context_id]
    variable credentialContexts
    dict set credentialContexts $id protected phase quarantined
    _credentialRevoke $id
    return 1
}
proc ::GX::ScientificLibraryManagerAPIv1::credentialFinish {ref {callback {}}} {
    variable credentialContexts
    if {$callback ne {} && ([catch {llength $callback} count] || $count<1 || $count>64 || [string bytelength $callback]>32768)} {return [_credentialError invalid_request]}
    set record [_credentialOperationRecord $ref]
    if {$record eq {}} {return [_credentialError stale_context]}
    set id [dict get $ref context_id];set phase [dict get $record protected phase]
    if {[dict get $record protected finish_claimed]} {return [_credentialError busy]}
    # The first caller owns completion before Drain can invoke terminal handlers.
    # Its claim survives quarantine/revocation even when the callback is empty.
    dict set credentialContexts $id protected finish_claimed 1
    dict set credentialContexts $id protected phase finishing
    dict set credentialContexts $id protected completion $callback
    set record [dict get $credentialContexts $id]
    set info [_credentialNativeInfo]
    if {$phase ne {submitted} || $info eq {} ||
        [dict get $info monotonic_ms]>=[dict get $record protected deadline_ms] ||
        [catch {_credentialCurrent $record} current] || !$current} {
        set reply [_credentialProtectedFailure $record]
        _credentialAttemptRelease $record 0
        # Detach delivery before cancellation, which may settle synchronously.
        dict set credentialContexts $id protected completion {}
        _credentialRevoke $id
        if {$callback ne {}} {uplevel #0 [list {*}$callback $reply];return [_credentialOperationEnvelope $ref pending]}
        return $reply
    }
    if {$callback ne {}} {
        dict set credentialContexts $id poll [after 0 [list ::GX::ScientificLibraryManagerAPIv1::_credentialProtectedPoll $ref]]
        return [_credentialOperationEnvelope $ref pending]
    }
    set remaining [expr {[dict get $record protected deadline_ms]-[dict get $info monotonic_ms]}]
    if {[catch {
        set wire [::GX::scriptJobRequestExchange [dict get $record request] {} $remaining]
        set reply [_credentialDecode $wire]
    }]} {set reply [_credentialProtectedFailure $record]}
    if {![dict get $reply ok] && [dict get $reply code] eq {transport_failure}} {set reply [_credentialProtectedFailure $record]}
    return [_credentialProtectedFinal $ref $record $reply]
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialProtectedPoll {ref} {
    variable credentialContexts
    set record [_credentialOperationRecord $ref]
    if {$record eq {}} return
    set id [dict get $ref context_id];dict set credentialContexts $id poll {}
    if {[dict get $record protected phase] ne {finishing}} {
        # Quarantine may have inherited this already-armed poll. Clear its ID
        # before transferring to the existing Drain owner, or cleanup stalls.
        _credentialRevoke $id
        return
    }
    set info [_credentialNativeInfo]
    set failed [expr {$info eq {}}]
    if {!$failed} {set failed [expr {[dict get $info monotonic_ms]>=[dict get $record protected deadline_ms]}]}
    if {!$failed && ([catch {_credentialCurrent $record} current] || !$current)} {set failed 1}
    if {!$failed && [catch {::GX::scriptJobRequestDrain [dict get $record request] 1} state]} {set failed 1}
    if {[_credentialOperationRecord $ref] eq {}} return
    if {!$failed && (![dict get $state active] || [dict get $state cancelled] ne {})} {set failed 1}
    if {!$failed && ![llength [dict get $state messages]]} {
        dict set credentialContexts $id poll [after 25 [list ::GX::ScientificLibraryManagerAPIv1::_credentialProtectedPoll $ref]]
        return
    }
    if {!$failed && [llength [dict get $state messages]]!=1} {set failed 1}
    if {$failed} {set reply [_credentialProtectedFailure $record]
    } else {
        set reply [_credentialDecode [lindex [dict get $state messages] 0]]
        if {![dict get $reply ok] && [dict get $reply code] eq {transport_failure}} {set reply [_credentialProtectedFailure $record]}
    }
    set callback [dict get $record protected completion]
    dict set credentialContexts $id protected completion {}
    set reply [_credentialProtectedFinal $ref $record $reply]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $reply]}
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialFacade {operation arguments} {
    # Superseded UNSHIPPED secret forms never prepare/wait under protected args.
    if {$operation eq {credential_unlock} || ($operation eq {profile_admin} && [lindex $arguments 0] in {create replace})} {return [_credentialError unavailable]}
    # Existing owned revocation must remain available if a native command is
    # removed after unlock. Lock carries no protected values and needs no new
    # secret submission/backend admission to cancel its already owned request.
    if {$operation ne {credential_lock} && ![_credentialNativeReady]} {return [_credentialError unavailable]}
    if {[catch {_credentialFacadeImpl $operation $arguments} value]} {return [_credentialError transport_failure]}
    return $value
}
proc ::GX::ScientificLibraryManagerAPIv1::_credentialFacadeImpl {operation arguments} {
    variable credentialContexts
    switch -- $operation {
        credential_status {
            if {[llength $arguments]!=1} {return [_credentialError invalid_request]}
            set library [lindex $arguments 0];set id [_credentialFind $library];set temporary 0
            if {$id eq {}} {set id [_credentialNew runtime $library];set temporary 1}
            if {$id eq {}} {return [_credentialError unavailable]}
            set value [_credentialExchange $id credential_status [list $library]]
            if {$temporary} {_credentialRevoke $id}
            return $value
        }
        credential_lock {
            if {[llength $arguments]!=1} {return [_credentialError invalid_request]}
            set library [lindex $arguments 0];set pending 0
            if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]*$} $library] || [string length [encoding convertto utf-8 $library]]>16384} {return [_credentialError invalid_request]}
            dict for {id record} $credentialContexts {
                if {[dict get $record library] eq $library} {_credentialRevoke $id;set pending 1}
            }
            set status [expr {$pending?{revoking}:{locked}}]
            set boolean [expr {$pending?{true}:{false}}]
            # Library IDs above contain no JSON escaping characters. Unknown
            # configured/provider requirements are genuine null, not guessed
            # booleans; the JSON sidecar is the authoritative typed projection.
            set json [format {{"library_id":"%s","configured":null,"authentication_required":null,"authentication_status":"%s","expires_in_seconds":0,"cleanup_pending":%s}} $library $status $boolean]
            set result [dict create library_id $library configured {} authentication_required {} authentication_status $status expires_in_seconds 0 cleanup_pending $pending result_json $json]
            return [dict create schema gxtxt.library_credential_response.v1 ok 1 result $result]
        }
        credential_unlock {
            # Deliberately no secret-bearing Tcl implementation. MAIN576's
            # exact native/nonthrow transfer decision is still outstanding.
            return [_credentialError unavailable]
        }
        profile_admin {
            if {![llength $arguments] || [lindex $arguments 0] ni {list inspect inspect_binding create replace delete}} {return [_credentialError invalid_request]}
            if {[lindex $arguments 0] in {create replace}} {return [_credentialError unavailable]}
            set id [_credentialNew admin {}]
            if {$id eq {}} {return [_credentialError unavailable]}
            set value [_credentialExchange $id profile_admin $arguments]
            _credentialRevoke $id
            return $value
        }
        bind {
            if {[llength $arguments]!=4} {return [_credentialError invalid_request]}
            set id [_credentialNew admin {}]
            if {$id eq {}} {return [_credentialError unavailable]}
            set value [_credentialExchange $id bind $arguments]
            _credentialRevoke $id
            return $value
        }
    }
    return [_credentialError invalid_request]
}
proc ::GX::ScientificLibraryManagerAPIv1::credentialStatus {args} {return [_credentialFacade credential_status $args]}
proc ::GX::ScientificLibraryManagerAPIv1::credentialUnlock {args} {return [_credentialFacade credential_unlock $args]}
proc ::GX::ScientificLibraryManagerAPIv1::credentialLock {args} {return [_credentialFacade credential_lock $args]}
proc ::GX::ScientificLibraryManagerAPIv1::credentialProfileAdmin {args} {return [_credentialFacade profile_admin $args]}
proc ::GX::ScientificLibraryManagerAPIv1::bindLibraryCredentialProfile {args} {return [_credentialFacade bind $args]}
::GX::ScientificLibraryManagerAPIv1::_credentialSessionTrace
