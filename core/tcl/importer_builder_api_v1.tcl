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

proc ::GX::importerBuilderValidate {definition} {
    if {[catch {dict size $definition}]} { error "Importer definition must be a dictionary." }
    set d [dict merge [importerBuilderDefaults] $definition]
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
    set seen {}
    set normalized {}
    foreach mapping [dict get $d mappings] {
        if {[catch {dict size $mapping}]} { error "Each column mapping must be a dictionary." }
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
            if {$value ne "" && ![string is double -strict $value]} { error "Mapping $key must be numeric." }
        }
        lappend normalized $mapping
    }
    if {![llength $normalized]} { error "Define at least one source column mapping." }
    dict set d mappings $normalized
    return $d
}

proc ::GX::importerBuilderWrite {definition path} {
    set d [importerBuilderValidate $definition]
    file mkdir [file dirname $path]
    set temp "${path}.[pid].tmp"
    set ch [open $temp w]
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
    } finally { close $ch }
    file rename -force -- $temp $path
    return $path
}

proc ::GX::importerBuilderRead {path} {
    if {![file isfile $path]} { error "Importer definition does not exist: $path" }
    set ini [parseIni $path]
    set d [importerBuilderDefaults]
    foreach key {id name version description match_regex delimiter header_rows skip_leading footer_rows comment_prefix encoding decimal contract metadata_name metadata_filename_regex metadata_header_regex} {
        if {[dict exists $ini importer.$key]} { dict set d $key [dict get $ini importer.$key] }
    }
    set count [expr {[dict exists $ini importer.mapping_count] ? [dict get $ini importer.mapping_count] : 0}]
    if {![string is integer -strict $count] || $count < 0 || $count > 512} { error "Importer mapping count is invalid." }
    set mappings {}
    for {set i 1} {$i <= $count} {incr i} {
        set mapping [dict create]
        foreach key {column name unit scale offset} {
            if {[dict exists $ini mapping.$i.$key]} { dict set mapping $key [dict get $ini mapping.$i.$key] }
        }
        lappend mappings $mapping
    }
    dict set d mappings $mappings
    return [importerBuilderValidate $d]
}

proc ::GX::importerBuilderReload {} {
    variable importerBuilderDefinitions
    set importerBuilderDefinitions [dict create]
    foreach path [glob -nocomplain -directory [importerBuilderRoot] *.ini] {
        if {[catch {set d [importerBuilderRead $path]}]} continue
        if {[file tail $path] ne "[dict get $d id].ini"} continue
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

proc ::GX::importerBuilderSave {definition} {
    variable importerBuilderDefinitions
    set d [importerBuilderValidate $definition]
    set id [dict get $d id]
    importerBuilderWrite $d [file join [importerBuilderRoot] "$id.ini"]
    dict set importerBuilderDefinitions $id $d
    return $id
}

proc ::GX::importerBuilderRemove {id} {
    variable importerBuilderDefinitions
    importerBuilderGet $id
    file delete -- [file join [importerBuilderRoot] "$id.ini"]
    dict unset importerBuilderDefinitions $id
}

proc ::GX::importerBuilderDuplicate {id newId} {
    set d [importerBuilderGet $id]
    if {[file exists [file join [importerBuilderRoot] "$newId.ini"]]} { error "Importer '$newId' already exists." }
    dict set d id $newId
    dict set d name "[dict get $d name] copy"
    return [importerBuilderSave $d]
}

proc ::GX::importerBuilderExport {id path} {
    set d [importerBuilderGet $id]
    if {[file exists $path]} { error "Export target already exists: $path" }
    return [importerBuilderWrite $d $path]
}

proc ::GX::importerBuilderImport {path} {
    set d [importerBuilderRead $path]
    if {[file exists [file join [importerBuilderRoot] "[dict get $d id].ini"]]} {
        error "Importer '[dict get $d id]' already exists; edit or duplicate it instead."
    }
    return [importerBuilderSave $d]
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
    set d [importerBuilderValidate $definition]
    if {![file isfile $sample]} { error "Select an existing sample file." }
    if {[dict get $d match_regex] ne "" && ![regexp -- [dict get $d match_regex] [file tail $sample]]} {
        error "Sample filename does not match the importer's matching rule."
    }
    set ch [file tempfile output]
    close $ch
    try {
        if {[dict get $d delimiter] eq "auto"} {
            set delim [csvDelimiter $sample auto]
            dict set d delimiter [expr {$delim eq "," ? "comma" : ($delim eq ";" ? "semicolon" : "tab")}]
        }
        set report [exec {*}[importerBuilderCommand $d $sample $output] 2>@1]
        set in [open $output r]
        fconfigure $in -encoding utf-8
        set preview {}
        try {
            for {set i 0} {$i < 12 && [gets $in line] >= 0} {incr i} { lappend preview $line }
        } finally { close $in }
        return [dict create report [string trim $report] preview [join $preview "\n"]]
    } finally { file delete -force -- $output }
}

proc ::GX::importerBuilderMetadata {definition source} {
    set d [importerBuilderValidate $definition]
    set name [dict get $d metadata_name]
    if {$name eq ""} { return [dict create] }
    set value ""
    set pattern [dict get $d metadata_filename_regex]
    if {$pattern ne ""} { regexp -- $pattern [file tail $source] -> value }
    if {$value eq "" && [dict get $d metadata_header_regex] ne ""} {
        set ch [open $source r]
        fconfigure $ch -encoding utf-8
        try {
            set text [read $ch 32768]
        } finally { close $ch }
        regexp -- [dict get $d metadata_header_regex] $text -> value
    }
    if {$value eq ""} { return [dict create] }
    return [dict create "importer_meta_$name" $value]
}
