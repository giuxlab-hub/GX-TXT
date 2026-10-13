# GX-TXT Scientific Library Manager API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificLibraryManagerAPIv1 {}

proc ::GX::ScientificLibraryManagerAPIv1::apiInfo {} {
    return [dict create api_name SCIENTIFIC_LIBRARY_MANAGER_API_v1 api_version 1 \
        registry_version 1]
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
