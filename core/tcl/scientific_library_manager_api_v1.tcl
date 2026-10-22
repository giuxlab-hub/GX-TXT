# GX-TXT Scientific Library Manager API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificLibraryManagerAPIv1 {}

proc ::GX::ScientificLibraryManagerAPIv1::apiInfo {} {
    return [dict create api_name SCIENTIFIC_LIBRARY_MANAGER_API_v1 api_version 1 \
        registry_version 1 capability_schema gxtxt.library_capabilities.v1 \
        operations {listLibraryTypes resolveLibraryProvider getLibraryInfo listInstalledLibraries queryCompatibleLibraries installLibrary updateLibrary removeLibrary verifyLibrary openLibrary listLibraryEntries openLibraryEntry readLibrarySpectrum libraryRoot listRegisteredLibraries registerLibrary unregisterLibrary getProviderCapabilities getLibraryCapabilities libraryCatalogPage openLibraryViewer invokeLibraryAction libraryRequest} \
        script_exposure host_module_only]
}
proc ::GX::ScientificLibraryManagerAPIv1::_helper {} {
    set path [file join $::GX::scriptDir core python scientific_library_manager.py]
    if {![file isfile $path]} {error "Scientific Library Manager CORE helper is missing"}
    return $path
}
proc ::GX::ScientificLibraryManagerAPIv1::_run {operation args} {
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
    set hadCatalogEnv [info exists ::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS)]
    if {$hadCatalogEnv} {set priorCatalogEnv $::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS)}
    if {[info exists ::GX::moduleOrder]} {
        set ::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS) [join $descriptors [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]]
    }
    set command [concat [list $python [_helper] $operation] $args]
    set failed [catch {set result [exec {*}$command 2>@1]} reason options]
    if {$hadCatalogEnv} {set ::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS) $priorCatalogEnv
    } else {unset -nocomplain ::env(GXTXT_LIBRARY_PROVIDER_DESCRIPTORS)}
    if {$failed} {
        set detail [lindex [split $reason "\n"] 0]
        regsub {^GX-TXT Scientific Library Manager: } $detail {} detail
        return -options $options "Scientific Library Manager: $detail"
    }
    return [string trimright $result "\n"]
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
    if {$operation ni {catalog_page library_capabilities provider_capabilities library_action info entries verify install update remove register unregister provider types open}} {error {Unsupported asynchronous Library operation}}
    # The helper still discovers the current authoritative installed providers.
    set descriptors {}
    foreach id $::GX::moduleOrder {
        if {[info exists ::GX::moduleCatalog($id,dict)] && [::GX::descriptorValue $::GX::moduleCatalog($id,dict) library_type_provider api_version {}] eq {1}} {lappend descriptors [::GX::moduleField $id descriptor]}
    }
    set options [dict create timeout_ms 120000 max_bytes 33554432 process_group 1 ui_lifetime 1 label {Scientific Library Manager}]
    # Public provider descriptor paths are inert request data, applied only to
    # this helper process's installed-provider view. No global host env change.
    return [::GX::scriptJobAsync [list [::GX::runtimeToolRequired python] -B [_helper] --request] [dict create operation $operation arguments $arguments provider_descriptors $descriptors] [list ::GX::ScientificLibraryManagerAPIv1::_requestDone $operation $callback] $options]
}
proc ::GX::ScientificLibraryManagerAPIv1::_requestDone {operation callback response} {
    if {[dict get $response ok]} {
        if {[catch {
            set wire [string trimright [dict get $response result wire] \n]
            if {$operation in {entries types}} {set value [_list $wire]} else {set value [_info $wire]}
            if {$operation eq {catalog_page}} {set value [_catalogPageDecode $value]}
            dict set response result $value
        } message]} {set response [dict create ok 0 error $message category scientific_library_manager]}
    }
    uplevel #0 [list {*}$callback $response]
}
