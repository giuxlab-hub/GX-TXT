# GX-TXT Scientific Reference Library API v1 (CORE).
# SPDX-License-Identifier: GPL-3.0-or-later
# Persistent libraries are independent of Sessions and use a compact SQLite
# metadata index plus typed binary numerical payloads via the CORE helper.
namespace eval ::GX::ReferenceLibraryAPIv1 { variable apiVersion 1 }

proc ::GX::ReferenceLibraryAPIv1::apiInfo {} {
    variable apiVersion
    return [dict create api_name SCIENTIFIC_REFERENCE_LIBRARY_API_v1 api_version $apiVersion format GXSRL_SQLITE_v1 spectrum_api SCIENTIFIC_SPECTRUM_API_v1]
}

proc ::GX::ReferenceLibraryAPIv1::root {} {
    if {[info exists ::env(XDG_DATA_HOME)] && [string trim $::env(XDG_DATA_HOME)] ne ""} {
        set dataRoot $::env(XDG_DATA_HOME)
    } elseif {[info exists ::env(HOME)] && [string trim $::env(HOME)] ne ""} {
        set dataRoot [file join $::env(HOME) .local share]
    } elseif {[info exists ::env(USERPROFILE)] && [string trim $::env(USERPROFILE)] ne ""} {
        set dataRoot [file join $::env(USERPROFILE) .local share]
    } else {
        set dataRoot [file join [pwd] .gxtxt-data]
    }
    return [file join $dataRoot gxtxt_pipeline scientific_reference_libraries]
}

proc ::GX::ReferenceLibraryAPIv1::_safeId {id} {
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id] || $id in {. ..}} {
        error "Scientific Reference Library API v1: invalid identifier '$id'"
    }
    return $id
}

proc ::GX::ReferenceLibraryAPIv1::_python {} {
    if {[llength [info commands ::GX::runtimeToolResolve]]} {
        set python [::GX::runtimeToolResolve python]
    } else {
        set python [auto_execok python3]
    }
    if {$python eq ""} { error "Scientific Reference Library API v1 requires a configured Python runtime" }
    return $python
}

proc ::GX::ReferenceLibraryAPIv1::_helper {} {
    set path [file join $::GX::scriptDir core python scientific_reference_library.py]
    if {![file isfile $path]} { error "Scientific Reference Library CORE helper is missing" }
    return $path
}

proc ::GX::ReferenceLibraryAPIv1::_run {command args} {
    set argv [concat [list [_python] [_helper] $command] $args]
    if {[catch {set result [exec {*}$argv 2>@1]} failure options]} {
        return -options $options "Scientific Reference Library API v1: $failure"
    }
    return [string trimright $result "\n"]
}

proc ::GX::ReferenceLibraryAPIv1::_encode {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::GX::ReferenceLibraryAPIv1::_decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}

proc ::GX::ReferenceLibraryAPIv1::_wireTemp {fields {metadata {}} {provenance {}} {data {}}} {
    foreach value [list $fields $metadata $provenance] {
        if {[catch {dict size $value}]} { error "Scientific Reference Library API v1: metadata must be a Tcl dict" }
    }
    set channel [file tempfile path]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        foreach prefix {F M P} mapping [list $fields $metadata $provenance] {
            dict for {key value} $mapping {
                puts $channel "$prefix\t[_encode $key]\t[_encode $value]"
            }
        }
        foreach pair $data {
            if {[llength $pair] != 2} { error "Scientific Reference Library API v1: data row must contain X and Y" }
            puts $channel "D\t[format %.17g [lindex $pair 0]]\t[format %.17g [lindex $pair 1]]"
        }
        close $channel
        return $path
    } on error {message options} {
        catch {close $channel}
        catch {file delete -- $path}
        return -options $options $message
    }
}

proc ::GX::ReferenceLibraryAPIv1::_parseWire {raw} {
    set fields [dict create]; set metadata [dict create]; set provenance [dict create]; set x {}; set y {}
    foreach line [split $raw "\n"] {
        if {$line eq ""} continue
        set parts [split $line "\t"]
        set prefix [lindex $parts 0]
        if {$prefix eq "D"} {
            if {[llength $parts] != 3} { error "Scientific Reference Library API v1: malformed numerical result" }
            lappend x [lindex $parts 1]
            lappend y [lindex $parts 2]
        } elseif {$prefix in {F M P}} {
            if {[llength $parts] != 3} { error "Scientific Reference Library API v1: malformed metadata result" }
            set key [_decode [lindex $parts 1]]
            set value [_decode [lindex $parts 2]]
            switch -- $prefix {
                F { dict set fields $key $value }
                M { dict set metadata $key $value }
                P { dict set provenance $key $value }
            }
        } else { error "Scientific Reference Library API v1: unknown result record" }
    }
    dict set fields metadata $metadata
    dict set fields provenance $provenance
    if {[llength $x]} { dict set fields x $x; dict set fields y $y }
    return $fields
}

proc ::GX::ReferenceLibraryAPIv1::_ids {raw} {
    if {$raw eq ""} { return {} }
    return [split $raw "\n"]
}

proc ::GX::ReferenceLibraryAPIv1::libraryPath {libraryId} {
    return [file join [root] "[_safeId $libraryId].gxsrl"]
}

proc ::GX::ReferenceLibraryAPIv1::createLibrary {info} {
    if {![dict exists $info library_id]} { error "Scientific Reference Library API v1: library_id required" }
    _safeId [dict get $info library_id]
    set request [_wireTemp $info]
    try { return [_run create [root] $request] } finally { catch {file delete -- $request} }
}

proc ::GX::ReferenceLibraryAPIv1::listLibraries {} { return [_ids [_run list [root]]] }
proc ::GX::ReferenceLibraryAPIv1::libraryInfo {libraryId} { return [_parseWire [_run info [root] [_safeId $libraryId]]] }
proc ::GX::ReferenceLibraryAPIv1::validateLibrary {libraryId} { return [_parseWire [_run validate [root] [_safeId $libraryId]]] }

proc ::GX::ReferenceLibraryAPIv1::upsertEntity {libraryId entityId info} {
    _safeId $libraryId; _safeId $entityId
    set request [_wireTemp $info]
    try { return [_run upsert-entity [root] $libraryId $entityId $request] } finally { catch {file delete -- $request} }
}

proc ::GX::ReferenceLibraryAPIv1::listEntities {libraryId} { return [_ids [_run entities [root] [_safeId $libraryId]]] }
proc ::GX::ReferenceLibraryAPIv1::entityInfo {libraryId entityId} { return [_parseWire [_run entity [root] [_safeId $libraryId] [_safeId $entityId]]] }

proc ::GX::ReferenceLibraryAPIv1::addSpectrum {libraryId spectrum} {
    _safeId $libraryId
    ::GX::SpectrumAPIv1::validate $spectrum
    _safeId [dict get $spectrum spectrum_id]
    set data {}
    foreach x [dict get $spectrum x] y [dict get $spectrum y] { lappend data [list $x $y] }
    set fields [dict remove $spectrum x y metadata provenance]
    set request [_wireTemp $fields [dict get $spectrum metadata] [dict get $spectrum provenance] $data]
    try { return [_run add-spectrum [root] $libraryId $request] } finally { catch {file delete -- $request} }
}

proc ::GX::ReferenceLibraryAPIv1::listSpectra {libraryId {entityId ""}} {
    _safeId $libraryId
    if {$entityId eq ""} { return [_ids [_run spectra [root] $libraryId]] }
    return [_ids [_run spectra [root] $libraryId [_safeId $entityId]]]
}

proc ::GX::ReferenceLibraryAPIv1::spectrumInfo {libraryId spectrumId} {
    return [_parseWire [_run spectrum-info [root] [_safeId $libraryId] [_safeId $spectrumId]]]
}

proc ::GX::ReferenceLibraryAPIv1::readSpectrum {libraryId spectrumId} {
    set spectrum [_parseWire [_run spectrum [root] [_safeId $libraryId] [_safeId $spectrumId]]]
    ::GX::SpectrumAPIv1::validate $spectrum
    return $spectrum
}

proc ::GX::ReferenceLibraryAPIv1::search {libraryId query} {
    return [_ids [_run search [root] [_safeId $libraryId] $query]]
}

proc ::GX::ReferenceLibraryAPIv1::exportLibrary {libraryId zipPath} {
    return [_run export [root] [_safeId $libraryId] [file normalize $zipPath]]
}

proc ::GX::ReferenceLibraryAPIv1::importLibrary {zipPath} {
    return [_run import [root] [file normalize $zipPath]]
}

# Versioned editing never changes the source library or its historical hash.
proc ::GX::ReferenceLibraryAPIv1::forkLibraryVersion {sourceId newId newVersion} {
    return [_run fork-version [root] [_safeId $sourceId] [_safeId $newId] $newVersion]
}

proc ::GX::ReferenceLibraryAPIv1::updateReference {sourceId newId newVersion spectrum} {
    _safeId $sourceId; _safeId $newId
    ::GX::SpectrumAPIv1::validate $spectrum
    _safeId [dict get $spectrum spectrum_id]
    set data {}
    foreach x [dict get $spectrum x] y [dict get $spectrum y] { lappend data [list $x $y] }
    set fields [dict remove $spectrum x y metadata provenance]
    set request [_wireTemp $fields [dict get $spectrum metadata] [dict get $spectrum provenance] $data]
    try { return [_run update-reference [root] $sourceId $newId $newVersion $request] } \
        finally { catch {file delete -- $request} }
}

proc ::GX::ReferenceLibraryAPIv1::removeUserReference {sourceId newId newVersion spectrumId} {
    return [_run remove-user-reference [root] [_safeId $sourceId] [_safeId $newId] $newVersion [_safeId $spectrumId]]
}

proc ::GX::ReferenceLibraryAPIv1::updateLibrary {sourceId newId newVersion info} {
    _safeId $sourceId; _safeId $newId
    set request [_wireTemp $info]
    try { return [_run update-library [root] $sourceId $newId $newVersion $request] } \
        finally { catch {file delete -- $request} }
}

proc ::GX::ReferenceLibraryAPIv1::removeLibrary {libraryId} {
    return [_run remove-library [root] [_safeId $libraryId]]
}

# Rank an entire validated library in one read-only CORE process. This API
# implements the IR module's simple preprocessing path (no baseline,
# smoothing or derivative). The caller later performs exact public-api
# calculation and provenance lookup on the shortlisted references.
proc ::GX::ReferenceLibraryAPIv1::bulkRank {libraryId experimental options} {
    _safeId $libraryId
    if {[catch {dict size $experimental}] || ![dict exists $experimental x] || ![dict exists $experimental y]} {
        error "Scientific Reference Library API v1: bulkRank requires processed X/Y"
    }
    if {[catch {dict size $options}]} {error "Scientific Reference Library API v1: bulkRank options must be a dict"}
    set x [dict get $experimental x]
    set y [dict get $experimental y]
    if {[llength $x] != [llength $y] || [llength $x] < 8} {
        error "Scientific Reference Library API v1: bulkRank processed X/Y length mismatch"
    }
    set helper [file join $::GX::scriptDir core python scientific_reference_bulk_match.py]
    if {![file isfile $helper]} {error "Scientific Reference Library API v1: bulk matching helper missing"}
    set channel [file tempfile request]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        foreach xv $x yv $y {puts $channel "[format %.17g $xv]\t[format %.17g $yv]"}
        close $channel
        set command [list [_python] $helper --library [libraryPath $libraryId] --experimental $request \
            --experimental-representation [dict get $options experimental_representation] \
            --range-min [dict get $options range_min] --range-max [dict get $options range_max] \
            --normalization [dict get $options normalization] --step [dict get $options step] \
            --method [dict get $options method] \
            --fingerprint-min [dict get $options fingerprint_min] \
            --fingerprint-max [dict get $options fingerprint_max] \
            --fingerprint-weight [dict get $options fingerprint_weight] \
            --limit [dict get $options limit]]
        if {[catch {set raw [exec {*}$command 2>@1]} failure]} {
            error "Scientific Reference Library API v1 bulkRank: $failure"
        }
        set summarySeen 0
        set candidates {}
        set scanned 0; set skipped 0
        foreach line [split [string trim $raw] "\n"] {
            set parts [split $line "\t"]
            switch -- [lindex $parts 0] {
                SUMMARY {
                    if {$summarySeen || [llength $parts] != 3} {error "bulkRank malformed summary"}
                    set scanned [lindex $parts 1]
                    set skipped [lindex $parts 2]
                    set summarySeen 1
                }
                CANDIDATE {
                    if {!$summarySeen || [llength $parts] != 5} {error "bulkRank malformed candidate"}
                    set id [_safeId [lindex $parts 1]]
                    lappend candidates [dict create spectrum_id $id match_score [lindex $parts 2] \
                        full_spectrum_score [lindex $parts 3] fingerprint_score [lindex $parts 4]]
                }
                default {error "bulkRank unexpected result line"}
            }
        }
        if {!$summarySeen || ![string is integer -strict $scanned] || ![string is integer -strict $skipped]} {
            error "bulkRank missing or invalid scan count"
        }
        return [dict create scanned $scanned skipped $skipped candidates $candidates]
    } finally {
        catch {close $channel}
        catch {file delete -- $request}
    }
}
