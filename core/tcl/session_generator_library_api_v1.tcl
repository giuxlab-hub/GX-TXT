# GX-TXT Session Generator Library API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# Reusable, portable Session generators. Import only validates and installs
# packages; generator code is executed only after an explicit Generate Session
# request. Generated Sessions use the normal GX-TXT Session lifecycle.

namespace eval ::GX {
    variable sessionGeneratorLibraryApiVersion 1
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder {}
    variable sessionGeneratorRegistryDefaultsInitialized 0
    variable sessionGeneratorRegistryAcceptedInitialized 0
    variable sessionGeneratorRegistryLastSelected ""
    variable sessionGeneratorGui
    array set sessionGeneratorGui {}
}

proc ::GX::sessionGeneratorConfigDir {} {
    # Reuse the established Working Directory Profiles path resolver so GX-TXT
    # has one authoritative XDG configuration convention.
    return [file dirname [workspaceProfilesPath]]
}

proc ::GX::sessionGeneratorRegistryPath {} {
    return [file join [sessionGeneratorConfigDir] session_generator_libraries.ini]
}

proc ::GX::sessionGeneratorDataRoot {} {
    if {[info exists ::env(XDG_DATA_HOME)] && [string trim $::env(XDG_DATA_HOME)] ne ""} {
        set root $::env(XDG_DATA_HOME)
    } elseif {[info exists ::env(HOME)] && [string trim $::env(HOME)] ne ""} {
        set root [file join $::env(HOME) .local share]
    } else {
        set root [file join [pwd] .gxtxt-data]
    }
    return [file join $root gxtxt_pipeline session_generators]
}

proc ::GX::sessionGeneratorBundledRoot {} {
    variable scriptDir
    return [file join $scriptDir session_generator_libraries]
}

proc ::GX::sessionGeneratorSafeId {id {label "Identifier"}} {
    set id [string trim $id]
    if {$id eq ""} { error "$label is empty." }
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id] || $id in {. ..}} {
        error "Invalid $label '$id'. Allowed characters: letters, digits, dot, underscore and hyphen."
    }
    return $id
}

proc ::GX::sessionGeneratorSafeRelativePath {path {label "Package path"}} {
    set p [string trim [string map {\\ /} $path]]
    if {$p eq ""} { error "$label is empty." }
    if {[file pathtype $p] ne "relative" || [string match "/*" $p] || [regexp {^[A-Za-z]:/} $p]} {
        error "$label must be relative: $p"
    }
    foreach part [split $p /] {
        if {$part in {"" . ..}} { error "Unsafe $label: $p" }
    }
    return $p
}

proc ::GX::sessionGeneratorPathInside {root path} {
    set r [file normalize $root]
    set p [file normalize $path]
    return [expr {$p eq $r || [string first "$r/" "$p/"] == 0}]
}

proc ::GX::sessionGeneratorRegistryClear {} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    variable sessionGeneratorRegistryDefaultsInitialized
    variable sessionGeneratorRegistryAcceptedInitialized
    variable sessionGeneratorRegistryLastSelected
    array unset sessionGeneratorRegistry *
    set sessionGeneratorRegistryOrder {}
    set sessionGeneratorRegistryDefaultsInitialized 0
    set sessionGeneratorRegistryAcceptedInitialized 0
    set sessionGeneratorRegistryLastSelected ""
}

proc ::GX::sessionGeneratorRegistryLoadRaw {} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    variable sessionGeneratorRegistryDefaultsInitialized
    variable sessionGeneratorRegistryAcceptedInitialized
    variable sessionGeneratorRegistryLastSelected
    sessionGeneratorRegistryClear
    set path [sessionGeneratorRegistryPath]
    if {![file isfile $path]} { return }
    set d [parseIni $path]
    if {[dict exists $d registry.defaults_initialized]} {
        set sessionGeneratorRegistryDefaultsInitialized [expr {[dict get $d registry.defaults_initialized] in {1 true yes on} ? 1 : 0}]
    }
    if {[dict exists $d registry.accepted_initialized]} {
        set sessionGeneratorRegistryAcceptedInitialized [expr {[dict get $d registry.accepted_initialized] in {1 true yes on} ? 1 : 0}]
    }
    if {[dict exists $d registry.last_selected_library]} {
        set sessionGeneratorRegistryLastSelected [dict get $d registry.last_selected_library]
    }
    set sections {}
    foreach key [dict keys $d] {
        if {[regexp {^library\.([^.]+)\.id$} $key -> section]} { lappend sections $section }
    }
    foreach section [lsort -dictionary -unique $sections] {
        set id [string trim [dict get $d "library.$section.id"]]
        if {[catch {sessionGeneratorSafeId $id "library ID"}]} continue
        set loc [expr {[dict exists $d "library.$section.location"] ? [dict get $d "library.$section.location"] : ""}]
        set enabled [expr {[dict exists $d "library.$section.enabled"] ? [dict get $d "library.$section.enabled"] : 1}]
        if {[string trim $loc] eq ""} continue
        set sessionGeneratorRegistry($id,id) $id
        set sessionGeneratorRegistry($id,location) [file normalize $loc]
        set sessionGeneratorRegistry($id,enabled) [expr {$enabled in {1 true yes on} ? 1 : 0}]
        lappend sessionGeneratorRegistryOrder $id
    }
    set sessionGeneratorRegistryOrder [lsort -dictionary -unique $sessionGeneratorRegistryOrder]
}

proc ::GX::sessionGeneratorRegistryWrite {} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    variable sessionGeneratorRegistryDefaultsInitialized
    variable sessionGeneratorRegistryAcceptedInitialized
    variable sessionGeneratorRegistryLastSelected
    set path [sessionGeneratorRegistryPath]
    file mkdir [file dirname $path]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Session Generator Library API v1 registry"
    puts $fd "; Persistent user configuration; library contents live under the user data directory."
    puts $fd "\[registry\]"
    putKV $fd api_version 1
    putKV $fd defaults_initialized $sessionGeneratorRegistryDefaultsInitialized
    putKV $fd accepted_initialized $sessionGeneratorRegistryAcceptedInitialized
    putKV $fd last_selected_library $sessionGeneratorRegistryLastSelected
    set n 0
    foreach id $sessionGeneratorRegistryOrder {
        if {![info exists sessionGeneratorRegistry($id,id)]} continue
        incr n
        set section [format %04d $n]
        puts $fd "\n\[library.$section\]"
        putKV $fd id $id
        putKV $fd location $sessionGeneratorRegistry($id,location)
        putKV $fd enabled $sessionGeneratorRegistry($id,enabled)
    }
    close $fd
    return $path
}

proc ::GX::sessionGeneratorRegistrySet {id location {enabled 1}} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    set id [sessionGeneratorSafeId $id "library ID"]
    set sessionGeneratorRegistry($id,id) $id
    set sessionGeneratorRegistry($id,location) [file normalize $location]
    set sessionGeneratorRegistry($id,enabled) [expr {$enabled ? 1 : 0}]
    if {[lsearch -exact $sessionGeneratorRegistryOrder $id] < 0} { lappend sessionGeneratorRegistryOrder $id }
    set sessionGeneratorRegistryOrder [lsort -dictionary -unique $sessionGeneratorRegistryOrder]
}

proc ::GX::sessionGeneratorRegistryRemove {id} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    variable sessionGeneratorRegistryLastSelected
    foreach key [array names sessionGeneratorRegistry "$id,*"] { unset sessionGeneratorRegistry($key) }
    set pos [lsearch -exact $sessionGeneratorRegistryOrder $id]
    if {$pos >= 0} { set sessionGeneratorRegistryOrder [lreplace $sessionGeneratorRegistryOrder $pos $pos] }
    if {$sessionGeneratorRegistryLastSelected eq $id} { set sessionGeneratorRegistryLastSelected "" }
}

proc ::GX::sessionGeneratorWriteLibraryDescriptor {root values} {
    file mkdir $root
    set path [file join $root session-generator-library.ini]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Session Generator Library API v1"
    puts $fd "\[library\]"
    foreach key {api_version library_id name version description author} {
        set value [expr {[dict exists $values $key] ? [dict get $values $key] : ""}]
        putKV $fd $key $value
    }
    close $fd
    return $path
}

proc ::GX::sessionGeneratorLibraryRead {root} {
    set root [file normalize $root]
    pluginValidateTree $root
    set path [file join $root session-generator-library.ini]
    if {![file isfile $path]} { error "session-generator-library.ini is missing from library root: $root" }
    set d [parseIni $path]
    set api [string trim [descriptorValue $d library api_version ""]]
    if {$api ne "1"} { error "Unsupported Session Generator Library API version '$api'." }
    set id [sessionGeneratorSafeId [descriptorValue $d library library_id ""] "library ID"]
    set name [string trim [descriptorValue $d library name ""]]
    if {$name eq ""} { error "Library '$id' has no display name." }
    set version [string trim [descriptorValue $d library version ""]]
    if {$version eq ""} { error "Library '$id' has no version." }
    set description [string trim [descriptorValue $d library description ""]]
    set author [string trim [descriptorValue $d library author ""]]
    set generators [sessionGeneratorDiscoverGeneratorRoots $root]
    set seen {}
    set generatorInfos {}
    foreach genRoot $generators {
        set info [sessionGeneratorRead $genRoot $id]
        set gid [dict get $info generator_id]
        if {[lsearch -exact $seen $gid] >= 0} { error "Library '$id' contains duplicate generator ID '$gid'." }
        lappend seen $gid
        lappend generatorInfos $info
    }
    return [dict create root $root descriptor $path api_version 1 library_id $id name $name version $version description $description author $author generators $generatorInfos]
}

proc ::GX::sessionGeneratorDiscoverGeneratorRoots {libraryRoot} {
    set dir [file join $libraryRoot generators]
    if {![file isdirectory $dir]} { return {} }
    set out {}
    foreach p [lsort -dictionary [glob -nocomplain -directory $dir *]] {
        if {[file isdirectory $p] && [file isfile [file join $p generator.ini]]} { lappend out $p }
    }
    return $out
}

proc ::GX::sessionGeneratorRead {root {libraryId ""}} {
    set root [file normalize $root]
    pluginValidateTree $root
    set path [file join $root generator.ini]
    if {![file isfile $path]} { error "generator.ini is missing from generator root: $root" }
    set d [parseIni $path]
    set api [string trim [descriptorValue $d generator api_version ""]]
    if {$api ne "1"} { error "Unsupported Session Generator API version '$api'." }
    set id [sessionGeneratorSafeId [descriptorValue $d generator generator_id ""] "generator ID"]
    set name [string trim [descriptorValue $d generator name ""]]
    if {$name eq ""} { error "Generator '$id' has no display name." }
    set category [string trim [descriptorValue $d generator category "Uncategorized"]]
    if {$category eq ""} { set category "Uncategorized" }
    set description [string trim [descriptorValue $d generator description ""]]
    set version [string trim [descriptorValue $d generator version ""]]
    if {$version eq ""} { error "Generator '$id' has no version." }
    set type [string tolower [string trim [descriptorValue $d generator generator_type ""]]]
    if {$type ni {python template hybrid}} { error "Generator '$id' declares invalid generator type '$type'." }
    set entry [string trim [descriptorValue $d generator entry_point ""]]
    set template [string trim [descriptorValue $d generator template_source ""]]
    if {$type in {python hybrid} && $entry eq ""} { error "Generator '$id' requires generator.entry_point." }
    if {$type in {template hybrid} && $template eq ""} { error "Generator '$id' requires generator.template_source." }
    if {$entry ne ""} {
        set entry [sessionGeneratorSafeRelativePath $entry "Generator entry point"]
        set entryPath [file normalize [file join $root {*}[split $entry /]]]
        if {![sessionGeneratorPathInside $root $entryPath] || ![file isfile $entryPath]} { error "Generator '$id' entry point does not exist: $entry" }
    } else { set entryPath "" }
    if {$template ne ""} {
        set template [sessionGeneratorSafeRelativePath $template "Template source"]
        set templatePath [file normalize [file join $root {*}[split $template /]]]
        if {![sessionGeneratorPathInside $root $templatePath] || ![file isdirectory $templatePath]} { error "Generator '$id' template source does not exist: $template" }
        pluginValidateTree $templatePath
    } else { set templatePath "" }
    foreach {field default} {
        author "" tags "" required_capabilities "" suggested_session_name "" expected_purpose "" files_produced ""
    } {
        set value [string trim [descriptorValue $d generator $field $default]]
        dict set meta $field $value
    }
    return [dict merge [dict create root $root descriptor $path library_id $libraryId api_version 1 generator_id $id name $name category $category description $description version $version generator_type $type entry_point $entry entry_path $entryPath template_source $template template_path $templatePath] $meta]
}

proc ::GX::sessionGeneratorFindDescriptorRoots {root filename} {
    set out {}
    if {[file isfile [file join $root $filename]]} { lappend out $root }
    foreach p [pluginWalkPaths $root] {
        if {[file isfile $p] && [file tail $p] eq $filename} {
            set r [file dirname $p]
            if {[lsearch -exact $out $r] < 0} { lappend out $r }
        }
    }
    return $out
}

proc ::GX::sessionGeneratorPackageOpen {source kind} {
    set source [file normalize $source]
    switch -- $kind {
        library { set descriptor session-generator-library.ini }
        generator { set descriptor generator.ini }
        default { error "Unknown Session Generator package kind '$kind'." }
    }
    if {[file isdirectory $source]} {
        pluginValidateTree $source
        set info [expr {$kind eq "library" ? [sessionGeneratorLibraryRead $source] : [sessionGeneratorRead $source]}]
        return [dict merge $info [dict create temporary_root "" source $source package_kind $kind]]
    }
    if {![file isfile $source]} { error "Session Generator package not found: $source" }
    if {[file tail $source] eq $descriptor} {
        set root [file dirname $source]
        pluginValidateTree $root
        set info [expr {$kind eq "library" ? [sessionGeneratorLibraryRead $root] : [sessionGeneratorRead $root]}]
        return [dict merge $info [dict create temporary_root "" source $source package_kind $kind]]
    }
    if {[string tolower [file extension $source]] ne ".zip"} { error "Choose a $descriptor file, package directory, or .zip package." }
    if {[auto_execok unzip] eq ""} { error "ZIP Session Generator packages require the 'unzip' command." }
    set listing [exec unzip -Z1 -- $source]
    set seen {}
    foreach line [split $listing "\n"] {
        set line [string trim $line]
        if {$line eq ""} continue
        if {![pluginZipEntrySafe $line]} { error "Unsafe path in Session Generator ZIP: $line" }
        set normalized [string trimright [string map {\\ /} $line] /]
        if {$normalized ne "" && [lsearch -exact $seen $normalized] >= 0} { error "Duplicate archive entry in Session Generator ZIP: $line" }
        if {$normalized ne ""} { lappend seen $normalized }
    }
    set dataRoot [sessionGeneratorDataRoot]
    set staging [file join $dataRoot .staging "open-[pid]-[clock clicks]"]
    file mkdir $staging
    if {[catch {exec unzip -qq -- $source -d $staging} err opts]} {
        catch {file delete -force -- $staging}
        return -options $opts $err
    }
    if {[catch {pluginValidateTree $staging} err opts]} {
        catch {file delete -force -- $staging}
        return -options $opts $err
    }
    set roots [sessionGeneratorFindDescriptorRoots $staging $descriptor]
    if {[llength $roots] != 1} {
        catch {file delete -force -- $staging}
        error "Session Generator ZIP must contain exactly one $descriptor; found [llength $roots]."
    }
    set root [lindex $roots 0]
    if {[catch {set info [expr {$kind eq "library" ? [sessionGeneratorLibraryRead $root] : [sessionGeneratorRead $root]}]} err opts]} {
        catch {file delete -force -- $staging}
        return -options $opts $err
    }
    return [dict merge $info [dict create temporary_root $staging source $source package_kind $kind]]
}

proc ::GX::sessionGeneratorPackageClose {info} {
    if {[dict exists $info temporary_root]} {
        set temp [dict get $info temporary_root]
        if {$temp ne "" && [file exists $temp]} { catch {file delete -force -- $temp} }
    }
}

proc ::GX::sessionGeneratorPackDirectory {source output} {
    variable scriptDir
    set python [runtimeToolRequired python]
    set helper [file join $scriptDir core python session_generator_package_v1.py]
    if {![file isfile $helper]} { error "Session Generator package helper is missing: $helper" }
    set source [file normalize $source]
    set output [file normalize $output]
    if {[string tolower [file extension $output]] ne ".zip"} { append output .zip }
    file mkdir [file dirname $output]
    if {[catch {exec $python $helper pack $source $output 2>@1} text opts]} { return -options $opts $text }
    return $output
}

proc ::GX::sessionGeneratorInstallBundledLibrary {directoryName} {
    set bundled [file join [sessionGeneratorBundledRoot] $directoryName]
    if {![file isdirectory $bundled]} { return }
    set info [sessionGeneratorLibraryRead $bundled]
    set id [dict get $info library_id]
    set target [file join [sessionGeneratorDataRoot] $id]
    if {![file exists $target]} {
        file mkdir [file dirname $target]
        file copy -force -- $bundled $target
    }
    set installed [sessionGeneratorLibraryRead $target]
    if {[dict get $installed library_id] ne $id} { error "Installed bundled Session Generator Library identity mismatch." }
    sessionGeneratorRegistrySet $id $target 1
}

proc ::GX::sessionGeneratorInstallDefaultLibrary {} {
    variable sessionGeneratorRegistryDefaultsInitialized
    sessionGeneratorInstallBundledLibrary gxtxt.numerical_examples
    set sessionGeneratorRegistryDefaultsInitialized 1
    sessionGeneratorRegistryWrite
}

proc ::GX::sessionGeneratorInstallAcceptedLibrary {} {
    variable sessionGeneratorRegistryAcceptedInitialized
    sessionGeneratorInstallBundledLibrary gxtxt.accepted_generators
    set sessionGeneratorRegistryAcceptedInitialized 1
    sessionGeneratorRegistryWrite
}

proc ::GX::sessionGeneratorRegistryLoad {} {
    variable sessionGeneratorRegistryDefaultsInitialized
    variable sessionGeneratorRegistryAcceptedInitialized
    sessionGeneratorRegistryLoadRaw
    if {!$sessionGeneratorRegistryDefaultsInitialized} {
        sessionGeneratorInstallDefaultLibrary
        sessionGeneratorRegistryLoadRaw
    }
    if {!$sessionGeneratorRegistryAcceptedInitialized} {
        sessionGeneratorInstallAcceptedLibrary
        sessionGeneratorRegistryLoadRaw
    }
    return [sessionGeneratorLibraryIds]
}

proc ::GX::sessionGeneratorLibraryIds {{enabledOnly 1}} {
    variable sessionGeneratorRegistry
    variable sessionGeneratorRegistryOrder
    set out {}
    foreach id $sessionGeneratorRegistryOrder {
        if {![info exists sessionGeneratorRegistry($id,id)]} continue
        if {$enabledOnly && !$sessionGeneratorRegistry($id,enabled)} continue
        lappend out $id
    }
    return $out
}

proc ::GX::sessionGeneratorLibraryPath {id} {
    variable sessionGeneratorRegistry
    set id [sessionGeneratorSafeId $id "library ID"]
    if {![info exists sessionGeneratorRegistry($id,location)]} { sessionGeneratorRegistryLoadRaw }
    if {![info exists sessionGeneratorRegistry($id,location)]} { error "Unknown Session Generator Library '$id'." }
    return $sessionGeneratorRegistry($id,location)
}

proc ::GX::sessionGeneratorLibraryInfo {id} {
    set info [sessionGeneratorLibraryRead [sessionGeneratorLibraryPath $id]]
    if {[dict get $info library_id] ne $id} { error "Session Generator Library registry identity mismatch for '$id'." }
    return $info
}

proc ::GX::sessionGeneratorListGenerators {libraryId} {
    return [dict get [sessionGeneratorLibraryInfo $libraryId] generators]
}

proc ::GX::sessionGeneratorGeneratorInfo {libraryId generatorId} {
    set generatorId [sessionGeneratorSafeId $generatorId "generator ID"]
    foreach info [sessionGeneratorListGenerators $libraryId] {
        if {[dict get $info generator_id] eq $generatorId} { return $info }
    }
    error "Generator '$generatorId' is not installed in library '$libraryId'."
}

proc ::GX::sessionGeneratorInstallLibrary {source} {
    variable sessionGeneratorRegistry
    sessionGeneratorRegistryLoadRaw
    set info [sessionGeneratorPackageOpen $source library]
    try {
        set id [dict get $info library_id]
        if {[info exists sessionGeneratorRegistry($id,id)]} { error "Session Generator Library '$id' is already installed." }
        set target [file join [sessionGeneratorDataRoot] $id]
        if {[file exists $target]} { error "Session Generator Library target already exists: $target" }
        file mkdir [file dirname $target]
        file copy -force -- [dict get $info root] $target
        if {[catch {set installed [sessionGeneratorLibraryRead $target]} err opts]} {
            catch {file delete -force -- $target}
            return -options $opts $err
        }
        sessionGeneratorRegistrySet $id $target 1
        sessionGeneratorRegistryWrite
        return $installed
    } finally {
        sessionGeneratorPackageClose $info
    }
}

proc ::GX::sessionGeneratorExportLibrary {libraryId output} {
    return [sessionGeneratorPackDirectory [sessionGeneratorLibraryPath $libraryId] $output]
}

proc ::GX::sessionGeneratorRemoveLibrary {libraryId} {
    sessionGeneratorRegistryLoadRaw
    set path [sessionGeneratorLibraryPath $libraryId]
    set dataRoot [sessionGeneratorDataRoot]
    if {![sessionGeneratorPathInside $dataRoot $path] || [file normalize $path] eq [file normalize $dataRoot]} {
        error "Refusing to remove a Session Generator Library outside the GX-TXT user data directory."
    }
    if {[file exists $path]} { file delete -force -- $path }
    sessionGeneratorRegistryRemove $libraryId
    sessionGeneratorRegistryWrite
    return $libraryId
}

proc ::GX::sessionGeneratorSlug {text} {
    set s [string tolower [string trim $text]]
    regsub -all {[^a-z0-9]+} $s - s
    set s [string trim $s -]
    if {$s eq ""} { set s library }
    return $s
}

proc ::GX::sessionGeneratorCreateLibrary {name {description ""} {version "1.0.0"} {author ""} {libraryId ""}} {
    variable sessionGeneratorRegistry
    sessionGeneratorRegistryLoadRaw
    set name [string trim $name]
    if {$name eq ""} { error "Library name is required." }
    if {$libraryId eq ""} {
        set libraryId "user.[sessionGeneratorSlug $name].[clock seconds].[pid]"
    }
    set libraryId [sessionGeneratorSafeId $libraryId "library ID"]
    if {[info exists sessionGeneratorRegistry($libraryId,id)]} { error "Session Generator Library '$libraryId' already exists." }
    set target [file join [sessionGeneratorDataRoot] $libraryId]
    if {[file exists $target]} { error "Session Generator Library target already exists: $target" }
    file mkdir [file join $target generators]
    sessionGeneratorWriteLibraryDescriptor $target [dict create api_version 1 library_id $libraryId name $name version $version description $description author $author]
    set info [sessionGeneratorLibraryRead $target]
    sessionGeneratorRegistrySet $libraryId $target 1
    sessionGeneratorRegistryWrite
    return $info
}

proc ::GX::sessionGeneratorUpdateLibraryMetadata {libraryId name description version author} {
    set info [sessionGeneratorLibraryInfo $libraryId]
    set name [string trim $name]
    set version [string trim $version]
    if {$name eq ""} { error "Library name is required." }
    if {$version eq ""} { error "Library version is required." }
    sessionGeneratorWriteLibraryDescriptor [dict get $info root] [dict create api_version 1 library_id $libraryId name $name version $version description $description author $author]
    return [sessionGeneratorLibraryInfo $libraryId]
}

proc ::GX::sessionGeneratorImportGenerator {source libraryId} {
    set lib [sessionGeneratorLibraryInfo $libraryId]
    set info [sessionGeneratorPackageOpen $source generator]
    try {
        set gid [dict get $info generator_id]
        foreach existing [dict get $lib generators] {
            if {[dict get $existing generator_id] eq $gid} { error "Generator '$gid' already exists in library '$libraryId'." }
        }
        set target [file join [dict get $lib root] generators $gid]
        if {[file exists $target]} { error "Generator target already exists: $target" }
        file mkdir [file dirname $target]
        file copy -force -- [dict get $info root] $target
        return [sessionGeneratorRead $target $libraryId]
    } finally {
        sessionGeneratorPackageClose $info
    }
}

proc ::GX::sessionGeneratorExportGenerator {libraryId generatorId output} {
    set info [sessionGeneratorGeneratorInfo $libraryId $generatorId]
    return [sessionGeneratorPackDirectory [dict get $info root] $output]
}

proc ::GX::sessionGeneratorAddGeneratorToLibrary {sourceLibraryId generatorId destinationLibraryId} {
    if {$sourceLibraryId eq $destinationLibraryId} { error "Choose a different destination library." }
    set src [sessionGeneratorGeneratorInfo $sourceLibraryId $generatorId]
    set dst [sessionGeneratorLibraryInfo $destinationLibraryId]
    foreach existing [dict get $dst generators] {
        if {[dict get $existing generator_id] eq $generatorId} { error "Generator '$generatorId' already exists in library '$destinationLibraryId'." }
    }
    set target [file join [dict get $dst root] generators $generatorId]
    file copy -force -- [dict get $src root] $target
    return [sessionGeneratorRead $target $destinationLibraryId]
}

proc ::GX::sessionGeneratorRemoveGenerator {libraryId generatorId} {
    set info [sessionGeneratorGeneratorInfo $libraryId $generatorId]
    set lib [sessionGeneratorLibraryInfo $libraryId]
    set path [dict get $info root]
    if {![sessionGeneratorPathInside [file join [dict get $lib root] generators] $path]} { error "Refusing to remove generator outside its library." }
    file delete -force -- $path
    return $generatorId
}

proc ::GX::sessionGeneratorDerivedTemplatePath {relative} {
    set rel [string map {\\ /} $relative]
    foreach part [split $rel /] {
        if {[string tolower $part] in {runtime cache .cache .runtime .staging}} { return 1 }
    }
    set tail [string tolower [file tail $rel]]
    if {$tail in {render_cache.mat runtime.ini runtime.json}} { return 1 }
    return 0
}

proc ::GX::sessionGeneratorCopyTemplate {source target {prefix ""}} {
    pluginValidateTree $source
    foreach p [lsort -dictionary [glob -nocomplain -directory $source * .*]] {
        set tail [file tail $p]
        if {$tail in {. ..}} continue
        set rel [expr {$prefix eq "" ? $tail : "$prefix/$tail"}]
        if {[sessionGeneratorDerivedTemplatePath $rel]} continue
        set out [file join $target {*}[split $rel /]]
        if {[file type $p] eq "link"} { error "Session templates may not contain symbolic links: $rel" }
        if {[file isdirectory $p]} {
            file mkdir $out
            sessionGeneratorCopyTemplate $p $target $rel
        } else {
            file mkdir [file dirname $out]
            file copy -force -- $p $out
        }
    }
}

proc ::GX::sessionGeneratorRunPython {info session} {
    set python [runtimeToolRequired python]
    set cmd [list $python [dict get $info entry_path] --target-session $session --library-id [dict get $info library_id] --generator-id [dict get $info generator_id]]
    set logPath [file join $session logs session_generator.log]
    if {[catch {exec {*}$cmd 2>@1} output opts]} {
        catch {
            set fd [open $logPath w]; fconfigure $fd -encoding utf-8 -translation lf; puts $fd $output; close $fd
        }
        return -options $opts "Generator process failed: $output"
    }
    set fd [open $logPath w]
    fconfigure $fd -encoding utf-8 -translation lf
    if {$output ne ""} { puts $fd $output }
    close $fd
}

proc ::GX::sessionGeneratorWriteProvenance {session libraryInfo generatorInfo} {
    set path [file join $session metadata session_generator.ini]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT generated Session provenance"
    puts $fd "\[session_generator\]"
    putKV $fd api_version 1
    putKV $fd library_id [dict get $libraryInfo library_id]
    putKV $fd library_version [dict get $libraryInfo version]
    putKV $fd generator_id [dict get $generatorInfo generator_id]
    putKV $fd generator_version [dict get $generatorInfo version]
    putKV $fd generator_type [dict get $generatorInfo generator_type]
    putKV $fd generated_at [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]
    close $fd
    return $path
}

proc ::GX::sessionGeneratorVerifySession {session} {
    foreach dir {raw metadata channels analysis report logs} {
        if {![file isdirectory [file join $session $dir]]} { error "Generated Session is missing required directory '$dir'." }
    }
    set manifest [file join $session metadata manifest.ini]
    if {![file isfile $manifest]} {error "Generated Session is missing metadata/manifest.ini."}
    set parsed [parseIni $manifest]
    if {![dict exists $parsed pipeline.format] || [dict get $parsed pipeline.format] ne "2"} {
        error "Generated Session Manifest is not format 2."
    }
    return 1
}

proc ::GX::sessionGeneratorGenerate {libraryId generatorId sessionRoot sessionName} {
    variable cfg
    variable currentSession
    set libraryInfo [sessionGeneratorLibraryInfo $libraryId]
    set generatorInfo [sessionGeneratorGeneratorInfo $libraryId $generatorId]
    set root [string trim $sessionRoot]
    if {$root eq ""} { error "Session root is required." }
    set root [file normalize $root]
    file mkdir $root
    set requested [string trim $sessionName]
    if {$requested eq ""} { error "Enter a session name." }
    set safe [sanitize $requested]
    set target [file normalize [file join $root $safe]]
    if {[file exists $target]} { error "A session named '$safe' already exists in:\n$root" }

    set oldRoot $cfg(output_root)
    set oldName $cfg(session_name)
    set oldSession $currentSession
    set stagingName "gxtxt_generation_[pid]_[clock clicks]"
    set staging ""
    set finalizedTarget 0
    set success 0
    try {
        # Generation creates a new Session.  The fallback Manifest must not
        # inherit Experiment, module or source state from the prior Session.
        defaults
        loadModuleCatalog
        set cfg(output_root) $root
        set cfg(session_name) $stagingName
        set staging [file normalize [makeSession]]
        if {[file dirname $staging] ne $root} { error "Session generation staging area escaped the selected Session root." }
        set type [dict get $generatorInfo generator_type]
        if {$type in {template hybrid}} {
            sessionGeneratorCopyTemplate [dict get $generatorInfo template_path] $staging
        }
        if {$type in {python hybrid}} {
            sessionGeneratorRunPython $generatorInfo $staging
        }
        # Generators own scientific content; CORE owns the Session Manifest.
        # Retain an intentional generator Manifest and let normal open validate it.
        set manifest [file join $staging metadata manifest.ini]
        if {![file isfile $manifest]} {
            set cfg(session_name) $safe
            writeManifest $manifest
        }
        sessionGeneratorWriteProvenance $staging $libraryInfo $generatorInfo
        sessionGeneratorVerifySession $staging
        file rename -- $staging $target
        set staging ""
        set finalizedTarget 1
        set cfg(output_root) $root
        set cfg(session_name) $safe
        set currentSession ""
        openSessionPath $target
        set success 1
        return $target
    } finally {
        if {!$success} {
            if {$staging ne "" && [file exists $staging]} { catch {file delete -force -- $staging} }
            if {$finalizedTarget && [file exists $target]} { catch {file delete -force -- $target} }
            if {$oldSession ne "" && [file isfile [file join $oldSession metadata manifest.ini]]} {
                catch {openSessionPath $oldSession}
            } else {
                set currentSession $oldSession
            }
            catch {updateSessionUi}
        }
        if {!$success} {
            set cfg(output_root) $oldRoot
            set cfg(session_name) $oldName
        }
    }
}

proc ::GX::sessionGeneratorInfoText {libraryInfo generatorInfo} {
    set lines [list \
        "Name: [dict get $generatorInfo name]" \
        "Library: [dict get $libraryInfo name]" \
        "Category: [dict get $generatorInfo category]" \
        "Type: [dict get $generatorInfo generator_type]" \
        "Version: [dict get $generatorInfo version]"]
    if {[dict get $generatorInfo author] ne ""} { lappend lines "Author: [dict get $generatorInfo author]" }
    if {[dict get $generatorInfo expected_purpose] ne ""} { lappend lines "Purpose: [dict get $generatorInfo expected_purpose]" }
    if {[dict get $generatorInfo files_produced] ne ""} { lappend lines "Produces: [dict get $generatorInfo files_produced]" }
    if {[dict get $generatorInfo required_capabilities] ne ""} { lappend lines "Requires: [dict get $generatorInfo required_capabilities]" }
    if {[dict get $generatorInfo description] ne ""} { lappend lines "" [dict get $generatorInfo description] }
    return [join $lines "\n"]
}

# -----------------------------------------------------------------------------
# New Session generator browser
# -----------------------------------------------------------------------------
proc ::GX::sessionGeneratorBrowserPopulate {w} {
    variable sessionGeneratorGui
    sessionGeneratorRegistryLoad
    set tree $w.generator.tree
    $tree delete [$tree children {}]
    array unset sessionGeneratorGui "$w,node,*"
    set libraryCounter 0
    foreach libraryId [sessionGeneratorLibraryIds] {
        if {[catch {set libraryInfo [sessionGeneratorLibraryInfo $libraryId]} err]} continue
        incr libraryCounter
        set libNode "lib_$libraryCounter"
        $tree insert {} end -id $libNode -text [dict get $libraryInfo name] -open 1
        set sessionGeneratorGui($w,node,$libNode) [list library $libraryId]
        set categories [dict create]
        foreach generatorInfo [dict get $libraryInfo generators] {
            dict lappend categories [dict get $generatorInfo category] $generatorInfo
        }
        set categoryCounter 0
        foreach category [lsort -dictionary [dict keys $categories]] {
            incr categoryCounter
            set catNode "${libNode}_cat_$categoryCounter"
            $tree insert $libNode end -id $catNode -text $category -open 1
            set sessionGeneratorGui($w,node,$catNode) [list category $libraryId $category]
            foreach generatorInfo [lsort -command ::GX::sessionGeneratorCompareByName [dict get $categories $category]] {
                set gid [dict get $generatorInfo generator_id]
                set genNode "${libNode}_gen_[string map {. _ - _} $gid]"
                if {[$tree exists $genNode]} { append genNode "_[clock clicks]" }
                $tree insert $catNode end -id $genNode -text [dict get $generatorInfo name]
                set sessionGeneratorGui($w,node,$genNode) [list generator $libraryId $gid]
            }
        }
    }
}

proc ::GX::sessionGeneratorCompareByName {a b} {
    return [string compare -nocase [dict get $a name] [dict get $b name]]
}

proc ::GX::sessionGeneratorBrowserSelection {w} {
    variable sessionGeneratorGui
    variable ui
    set tree $w.generator.tree
    set sel [$tree selection]
    if {[llength $sel] != 1} return
    set node [lindex $sel 0]
    if {![info exists sessionGeneratorGui($w,node,$node)]} return
    set spec $sessionGeneratorGui($w,node,$node)
    if {[lindex $spec 0] ne "generator"} return
    lassign [lrange $spec 1 end] libraryId generatorId
    set libraryInfo [sessionGeneratorLibraryInfo $libraryId]
    set generatorInfo [sessionGeneratorGeneratorInfo $libraryId $generatorId]
    set sessionGeneratorGui($w,selected_library) $libraryId
    set sessionGeneratorGui($w,selected_generator) $generatorId
    $w.generator.info configure -state normal
    $w.generator.info delete 1.0 end
    $w.generator.info insert 1.0 [sessionGeneratorInfoText $libraryInfo $generatorInfo]
    $w.generator.info configure -state disabled
    if {[string trim $ui(newSessionName)] eq "" && [dict get $generatorInfo suggested_session_name] ne ""} {
        set ui(newSessionName) [dict get $generatorInfo suggested_session_name]
    }
    variable sessionGeneratorRegistryLastSelected
    set sessionGeneratorRegistryLastSelected $libraryId
    catch {sessionGeneratorRegistryWrite}
}

proc ::GX::sessionGeneratorBrowserGenerate {w} {
    variable sessionGeneratorGui
    variable ui
    variable cfg
    if {![info exists sessionGeneratorGui($w,selected_generator)]} {
        tk_messageBox -parent $w -icon info -title "Generate Session" -message "Select a Session generator first."
        return
    }
    set libraryId $sessionGeneratorGui($w,selected_library)
    set generatorId $sessionGeneratorGui($w,selected_generator)
    set projectId [expr {[info exists ui(newSessionProjectIds)] && [dict exists $ui(newSessionProjectIds) $ui(newSessionProject)] ? [dict get $ui(newSessionProjectIds) $ui(newSessionProject)] : ""}]
    set root [expr {$projectId ne "" ? [projectSessionsRoot $projectId] : $cfg(output_root)}]
    if {[catch {
        set session [sessionGeneratorGenerate $libraryId $generatorId $root $ui(newSessionName)]
        if {$projectId ne ""} {
            set cfg(experiment_project_id) $projectId
            set cfg(experiment_project) [projectField $projectId name]
            set cfg(experiment_project_legacy) ""
            set eid [projectEnsureCurrentExperimentId]
            projectAssociateExperiment $projectId $eid $session $cfg(experiment_name)
            writeManifest [file join $session metadata manifest.ini]
        }
    } err]} {
        tk_messageBox -parent $w -icon error -title "Generate Session" -message $err
        return
    }
    destroy $w
    tk_messageBox -icon info -title "Generate Session" -message "Session generated:\n$session"
}

proc ::GX::sessionGeneratorBrowserShow {w} {
    variable sessionGeneratorGui
    if {[info exists sessionGeneratorGui($w,browser_visible)] && $sessionGeneratorGui($w,browser_visible)} { return }
    set sessionGeneratorGui($w,browser_visible) 1
    grid $w.generator -row 4 -column 0 -columnspan 2 -sticky nsew -padx 6 -pady {0 6}
    grid rowconfigure $w 4 -weight 1
    sessionGeneratorBrowserPopulate $w
    wm resizable $w 1 1
    sessionGeneratorFitDialog $w
}

proc ::GX::sessionGeneratorManagerRefresh {w} {
    variable sessionGeneratorGui
    sessionGeneratorRegistryLoadRaw
    set lt $w.manager.libraries.tree
    $lt delete [$lt children {}]
    foreach id [sessionGeneratorLibraryIds 0] {
        if {[catch {set info [sessionGeneratorLibraryInfo $id]}]} continue
        $lt insert {} end -id $id -text [dict get $info name]
    }
    if {[info exists sessionGeneratorGui($w,manager_library)] && [$lt exists $sessionGeneratorGui($w,manager_library)]} {
        $lt selection set $sessionGeneratorGui($w,manager_library)
        sessionGeneratorManagerLibrarySelection $w
    } elseif {[llength [$lt children {}]]} {
        set first [lindex [$lt children {}] 0]
        $lt selection set $first
        sessionGeneratorManagerLibrarySelection $w
    }
}

proc ::GX::sessionGeneratorManagerLibrarySelection {w} {
    variable sessionGeneratorGui
    set lt $w.manager.libraries.tree
    set sel [$lt selection]
    if {[llength $sel] != 1} return
    set id [lindex $sel 0]
    set info [sessionGeneratorLibraryInfo $id]
    set sessionGeneratorGui($w,manager_library) $id
    foreach field {name description version author} {
        set sessionGeneratorGui($w,meta_$field) [dict get $info $field]
    }
    set gt $w.manager.generators.tree
    $gt delete [$gt children {}]
    foreach gen [dict get $info generators] {
        $gt insert {} end -id [dict get $gen generator_id] -text [dict get $gen name]
    }
    $w.manager.add.destination configure -values [sessionGeneratorLibraryIds]
    set details "Library ID: $id\nVersion: [dict get $info version]\nAuthor: [dict get $info author]\n\n[dict get $info description]"
    $w.manager.details configure -state normal
    $w.manager.details delete 1.0 end
    $w.manager.details insert 1.0 $details
    $w.manager.details configure -state disabled
}

proc ::GX::sessionGeneratorManagerGeneratorSelection {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)]} return
    set gt $w.manager.generators.tree
    set sel [$gt selection]
    if {[llength $sel] != 1} return
    set gid [lindex $sel 0]
    set info [sessionGeneratorGeneratorInfo $sessionGeneratorGui($w,manager_library) $gid]
    set sessionGeneratorGui($w,manager_generator) $gid
    set lib [sessionGeneratorLibraryInfo $sessionGeneratorGui($w,manager_library)]
    $w.manager.details configure -state normal
    $w.manager.details delete 1.0 end
    $w.manager.details insert 1.0 [sessionGeneratorInfoText $lib $info]
    $w.manager.details configure -state disabled
}

proc ::GX::sessionGeneratorManagerCreateLibraryDialog {w} {
    variable sessionGeneratorGui
    set d $w.createLibrary
    catch {destroy $d}
    toplevel $d
    wm title $d "Create Session Generator Library"
    wm transient $d $w
    set sessionGeneratorGui($w,create_name) ""
    set sessionGeneratorGui($w,create_description) ""
    set sessionGeneratorGui($w,create_version) "1.0.0"
    set sessionGeneratorGui($w,create_author) ""
    grid columnconfigure $d 1 -weight 1
    set row 0
    foreach {field label} {create_name "Name" create_description "Description" create_version "Version" create_author "Author"} {
        ttk::label $d.l$row -text "$label:"
        ttk::entry $d.e$row -textvariable ::GX::sessionGeneratorGui($w,$field) -width 42
        grid $d.l$row -row $row -column 0 -sticky e -padx 5 -pady 4
        grid $d.e$row -row $row -column 1 -sticky ew -padx 5 -pady 4
        incr row
    }
    ttk::frame $d.buttons
    ttk::button $d.buttons.create -text "Create" -command [list ::GX::sessionGeneratorManagerCreateLibraryCommit $w $d]
    ttk::button $d.buttons.cancel -text "Cancel" -command [list destroy $d]
    pack $d.buttons.create $d.buttons.cancel -side left -padx 4
    grid $d.buttons -row $row -column 0 -columnspan 2 -pady 7
    focus $d.e0
}

proc ::GX::sessionGeneratorManagerCreateLibraryCommit {w d} {
    variable sessionGeneratorGui
    if {[catch {set info [sessionGeneratorCreateLibrary $sessionGeneratorGui($w,create_name) $sessionGeneratorGui($w,create_description) $sessionGeneratorGui($w,create_version) $sessionGeneratorGui($w,create_author)]} err]} {
        tk_messageBox -parent $d -icon error -title "Create Library" -message $err
        return
    }
    set sessionGeneratorGui($w,manager_library) [dict get $info library_id]
    destroy $d
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerSaveMetadata {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)]} return
    if {[catch {sessionGeneratorUpdateLibraryMetadata $sessionGeneratorGui($w,manager_library) $sessionGeneratorGui($w,meta_name) $sessionGeneratorGui($w,meta_description) $sessionGeneratorGui($w,meta_version) $sessionGeneratorGui($w,meta_author)} err]} {
        tk_messageBox -parent $w -icon error -title "Library Metadata" -message $err
        return
    }
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerImportLibrary {w} {
    set p [tk_getOpenFile -parent $w -title "Import Session Generator Library" -filetypes {{{Session Generator Library} {.zip .ini}} {{ZIP archives} {.zip}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {set info [sessionGeneratorInstallLibrary $p]} err]} { tk_messageBox -parent $w -icon error -title "Import Library" -message $err; return }
    variable sessionGeneratorGui
    set sessionGeneratorGui($w,manager_library) [dict get $info library_id]
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerExportLibrary {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)]} return
    set id $sessionGeneratorGui($w,manager_library)
    set p [tk_getSaveFile -parent $w -title "Export Session Generator Library" -defaultextension .zip -initialfile "$id.zip" -filetypes {{{ZIP archive} {.zip}}}]
    if {$p eq ""} return
    if {[catch {sessionGeneratorExportLibrary $id $p} err]} { tk_messageBox -parent $w -icon error -title "Export Library" -message $err }
}

proc ::GX::sessionGeneratorManagerRemoveLibrary {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)]} return
    set id $sessionGeneratorGui($w,manager_library)
    set answer [tk_messageBox -parent $w -icon warning -type yesno -default no -title "Remove Library" -message "Remove the locally installed Session Generator Library '$id'?\n\nAlready generated Sessions will not be deleted."]
    if {$answer ne "yes"} return
    if {[catch {sessionGeneratorRemoveLibrary $id} err]} { tk_messageBox -parent $w -icon error -title "Remove Library" -message $err; return }
    catch {unset sessionGeneratorGui($w,manager_library)}
    catch {unset sessionGeneratorGui($w,manager_generator)}
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerImportGenerator {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)]} { tk_messageBox -parent $w -message "Select a destination library first."; return }
    set p [tk_getOpenFile -parent $w -title "Import Session Generator" -filetypes {{{Session Generator} {.zip .ini}} {{ZIP archives} {.zip}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {sessionGeneratorImportGenerator $p $sessionGeneratorGui($w,manager_library)} err]} { tk_messageBox -parent $w -icon error -title "Import Generator" -message $err; return }
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerExportGenerator {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)] || ![info exists sessionGeneratorGui($w,manager_generator)]} return
    set gid $sessionGeneratorGui($w,manager_generator)
    set p [tk_getSaveFile -parent $w -title "Export Session Generator" -defaultextension .zip -initialfile "$gid.zip" -filetypes {{{ZIP archive} {.zip}}}]
    if {$p eq ""} return
    if {[catch {sessionGeneratorExportGenerator $sessionGeneratorGui($w,manager_library) $gid $p} err]} { tk_messageBox -parent $w -icon error -title "Export Generator" -message $err }
}

proc ::GX::sessionGeneratorManagerAddGenerator {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)] || ![info exists sessionGeneratorGui($w,manager_generator)]} return
    set dest [string trim $sessionGeneratorGui($w,destination_library)]
    if {$dest eq ""} { tk_messageBox -parent $w -message "Choose a destination library."; return }
    if {[catch {sessionGeneratorAddGeneratorToLibrary $sessionGeneratorGui($w,manager_library) $sessionGeneratorGui($w,manager_generator) $dest} err]} { tk_messageBox -parent $w -icon error -title "Add Generator" -message $err; return }
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerRemoveGenerator {w} {
    variable sessionGeneratorGui
    if {![info exists sessionGeneratorGui($w,manager_library)] || ![info exists sessionGeneratorGui($w,manager_generator)]} return
    set gid $sessionGeneratorGui($w,manager_generator)
    set answer [tk_messageBox -parent $w -icon warning -type yesno -default no -title "Remove Generator" -message "Remove generator '$gid' from this library?"]
    if {$answer ne "yes"} return
    if {[catch {sessionGeneratorRemoveGenerator $sessionGeneratorGui($w,manager_library) $gid} err]} { tk_messageBox -parent $w -icon error -title "Remove Generator" -message $err; return }
    catch {unset sessionGeneratorGui($w,manager_generator)}
    sessionGeneratorManagerRefresh $w
    sessionGeneratorBrowserPopulate $w
}

proc ::GX::sessionGeneratorManagerHide {w} {
    variable sessionGeneratorGui
    grid remove $w.manager
    if {[info exists sessionGeneratorGui($w,browser_visible)] && $sessionGeneratorGui($w,browser_visible)} {
        grid $w.generator -row 4 -column 0 -columnspan 2 -sticky nsew -padx 6 -pady {0 6}
        sessionGeneratorBrowserPopulate $w
    }
    set sessionGeneratorGui($w,manager_visible) 0
    update idletasks
    sessionGeneratorFitDialog $w
}

proc ::GX::sessionGeneratorFitDialog {w} {
    update idletasks
    set width [expr {min([winfo reqwidth $w], [winfo screenwidth $w] - 40)}]
    set height [expr {min([winfo reqheight $w], [winfo screenheight $w] - 80)}]
    wm geometry $w "${width}x${height}+20+20"
}

proc ::GX::sessionGeneratorManagerShow {w} {
    variable sessionGeneratorGui
    if {![winfo exists $w.manager]} { return }
    # The browser already fills a normal laptop display. Give the manager the
    # same dialog area so its actions remain visible instead of extending the
    # window beyond the screen edge.
    grid remove $w.generator
    grid $w.manager -row 4 -column 0 -columnspan 2 -sticky nsew -padx 6 -pady {0 6}
    set sessionGeneratorGui($w,manager_visible) 1
    sessionGeneratorManagerRefresh $w
    sessionGeneratorFitDialog $w
}

proc ::GX::sessionGeneratorBuildManager {w} {
    variable sessionGeneratorGui
    ttk::labelframe $w.manager -text "Library Manager"
    grid columnconfigure $w.manager 0 -weight 1
    grid rowconfigure $w.manager 1 -weight 1
    grid rowconfigure $w.manager 3 -weight 1

    ttk::frame $w.manager.top
    ttk::label $w.manager.top.title -text "Libraries"
    ttk::button $w.manager.top.hide -text "Hide Manager" -command [list ::GX::sessionGeneratorManagerHide $w]
    pack $w.manager.top.title -side left
    pack $w.manager.top.hide -side right
    grid $w.manager.top -row 0 -column 0 -sticky ew -padx 5 -pady 4

    ttk::labelframe $w.manager.libraries -text "Installed Libraries"
    ttk::treeview $w.manager.libraries.tree -show tree -height 5 -selectmode browse
    pack $w.manager.libraries.tree -fill both -expand 1
    grid $w.manager.libraries -row 1 -column 0 -sticky nsew -padx 5 -pady 3
    bind $w.manager.libraries.tree <<TreeviewSelect>> [list ::GX::sessionGeneratorManagerLibrarySelection $w]

    ttk::frame $w.manager.libActions
    foreach {name label command} {
        import "Import Library..." sessionGeneratorManagerImportLibrary
        export "Export Library..." sessionGeneratorManagerExportLibrary
        create "Create Library..." sessionGeneratorManagerCreateLibraryDialog
        remove "Remove Library" sessionGeneratorManagerRemoveLibrary
    } {
        ttk::button $w.manager.libActions.$name -text $label -command [list ::GX::$command $w]
        pack $w.manager.libActions.$name -side left -padx 2 -pady 2
    }
    grid $w.manager.libActions -row 2 -column 0 -sticky ew -padx 5

    ttk::labelframe $w.manager.generators -text "Generators in Selected Library"
    ttk::treeview $w.manager.generators.tree -show tree -height 5 -selectmode browse
    pack $w.manager.generators.tree -fill both -expand 1
    grid $w.manager.generators -row 3 -column 0 -sticky nsew -padx 5 -pady 3
    bind $w.manager.generators.tree <<TreeviewSelect>> [list ::GX::sessionGeneratorManagerGeneratorSelection $w]

    ttk::frame $w.manager.genActions
    ttk::button $w.manager.genActions.import -text "Import Generator..." -command [list ::GX::sessionGeneratorManagerImportGenerator $w]
    ttk::button $w.manager.genActions.export -text "Export Generator..." -command [list ::GX::sessionGeneratorManagerExportGenerator $w]
    ttk::button $w.manager.genActions.remove -text "Remove Generator" -command [list ::GX::sessionGeneratorManagerRemoveGenerator $w]
    pack $w.manager.genActions.import $w.manager.genActions.export $w.manager.genActions.remove -side left -padx 2
    grid $w.manager.genActions -row 4 -column 0 -sticky ew -padx 5 -pady 2

    ttk::frame $w.manager.add
    ttk::label $w.manager.add.label -text "Destination library:"
    ttk::combobox $w.manager.add.destination -textvariable ::GX::sessionGeneratorGui($w,destination_library) -state readonly -width 28
    ttk::button $w.manager.add.copy -text "Add Generator to Library..." -command [list ::GX::sessionGeneratorManagerAddGenerator $w]
    pack $w.manager.add.label $w.manager.add.destination $w.manager.add.copy -side left -padx 2
    grid $w.manager.add -row 5 -column 0 -sticky ew -padx 5 -pady 2

    ttk::labelframe $w.manager.meta -text "Library Metadata"
    grid columnconfigure $w.manager.meta 1 -weight 1
    set row 0
    foreach {field label} {name "Name" description "Description" version "Version" author "Author"} {
        ttk::label $w.manager.meta.l$row -text "$label:"
        ttk::entry $w.manager.meta.e$row -textvariable ::GX::sessionGeneratorGui($w,meta_$field)
        grid $w.manager.meta.l$row -row $row -column 0 -sticky e -padx 3 -pady 2
        grid $w.manager.meta.e$row -row $row -column 1 -sticky ew -padx 3 -pady 2
        incr row
    }
    ttk::button $w.manager.meta.save -text "Save Metadata" -command [list ::GX::sessionGeneratorManagerSaveMetadata $w]
    grid $w.manager.meta.save -row $row -column 0 -columnspan 2 -pady 3
    grid $w.manager.meta -row 6 -column 0 -sticky ew -padx 5 -pady 3

    text $w.manager.details -height 7 -width 48 -wrap word -state disabled
    grid $w.manager.details -row 7 -column 0 -sticky nsew -padx 5 -pady 4
    grid rowconfigure $w.manager 7 -weight 1
}

# Keep the established manual New Session path untouched and replace only the
# dialog composition so generator mode remains optional.
proc ::GX::newSessionDialog {{preferredProjectId ""}} {
    variable cfg
    variable ui
    variable sessionGeneratorGui
    if {[string trim $cfg(output_root)] eq ""} {
        tk_messageBox -icon info -title "New Session" -message "Set Session root or load a Workspace profile before creating a session."
        return
    }
    set root [file normalize $cfg(output_root)]
    set ui(newSessionName) ""
    set projectChoices [newSessionProjectChoices $preferredProjectId]
    set w .gxNewSession
    catch {destroy $w}
    array unset sessionGeneratorGui "$w,*"
    toplevel $w
    wm title $w "New Session"
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::label $w.rootLabel -text "Session root:"
    ttk::label $w.root -text $root
    ttk::label $w.nameLabel -text "Session name:"
    ttk::entry $w.name -textvariable ::GX::ui(newSessionName) -width 36
    ttk::label $w.projectLabel -text "Location:"
    ttk::combobox $w.project -textvariable ::GX::ui(newSessionProject) -values $projectChoices -state readonly -width 45
    ttk::frame $w.buttons
    ttk::button $w.buttons.create -text "Create" -command [list ::GX::newSessionDialogCommit $w]
    ttk::button $w.buttons.generate -text "Generate Session..." -command [list ::GX::sessionGeneratorBrowserShow $w]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    grid $w.rootLabel -row 0 -column 0 -sticky e -padx 6 -pady 6
    grid $w.root -row 0 -column 1 -sticky w -padx 6 -pady 6
    grid $w.nameLabel -row 1 -column 0 -sticky e -padx 6 -pady 6
    grid $w.name -row 1 -column 1 -sticky ew -padx 6 -pady 6
    grid $w.projectLabel -row 2 -column 0 -sticky e -padx 6 -pady 6
    grid $w.project -row 2 -column 1 -sticky ew -padx 6 -pady 6
    pack $w.buttons.create $w.buttons.generate $w.buttons.cancel -side left -padx 4
    grid $w.buttons -row 3 -column 0 -columnspan 2 -pady 8

    ttk::labelframe $w.generator -text "Session Generator Library"
    grid columnconfigure $w.generator 0 -weight 3 -minsize 380
    grid columnconfigure $w.generator 2 -weight 2 -minsize 340
    grid rowconfigure $w.generator 0 -weight 1
    ttk::treeview $w.generator.tree -show tree -height 16 -selectmode browse -yscrollcommand [list $w.generator.scroll set]
    ttk::scrollbar $w.generator.scroll -orient vertical -command [list $w.generator.tree yview]
    text $w.generator.info -height 12 -width 48 -wrap word -state disabled
    grid $w.generator.tree -row 0 -column 0 -sticky nsew -padx 4 -pady 4
    grid $w.generator.scroll -row 0 -column 1 -sticky ns -pady 4
    grid $w.generator.info -row 0 -column 2 -sticky nsew -padx 4 -pady 4
    ttk::frame $w.generator.actions
    ttk::button $w.generator.actions.generate -text "Generate Session" -command [list ::GX::sessionGeneratorBrowserGenerate $w]
    ttk::button $w.generator.actions.manage -text "Manage Libraries..." -command [list ::GX::sessionGeneratorManagerShow $w]
    pack $w.generator.actions.generate $w.generator.actions.manage -side left -padx 4
    grid $w.generator.actions -row 1 -column 0 -columnspan 3 -pady 4
    bind $w.generator.tree <<TreeviewSelect>> [list ::GX::sessionGeneratorBrowserSelection $w]

    sessionGeneratorBuildManager $w
    grid remove $w.manager
    set sessionGeneratorGui($w,browser_visible) 0
    set sessionGeneratorGui($w,manager_visible) 0

    bind $w.name <Return> [list ::GX::newSessionDialogCommit $w]
    bind $w <Escape> [list destroy $w]
    sessionGeneratorFitDialog $w
    focus $w.name
    grab $w
    tkwait window $w
}
