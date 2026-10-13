# GX-TXT Instrument Library API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The Instrument Library describes real laboratory instruments independently of
# Sessions and Experiments. Adding an entry to an Experiment copies a historical
# snapshot into the normal Instrument Module instance; later library edits never
# rewrite that Experiment unless the user explicitly requests synchronization.

namespace eval ::GX {
    variable instrumentLibraryApiVersion 1
    variable instrumentLibrary
    variable instrumentLibraryLoaded 0
    variable instrumentLibraryCounter 0
    variable instrumentLibrarySelection ""
    variable instrumentLibraryEditor
}

proc ::GX::instrumentLibraryTimestamp {} {
    return [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
}

proc ::GX::instrumentLibraryPath {} {
    if {[info exists ::env(XDG_CONFIG_HOME)] && [string trim $::env(XDG_CONFIG_HOME)] ne ""} {
        set root $::env(XDG_CONFIG_HOME)
    } elseif {[info exists ::env(HOME)] && [string trim $::env(HOME)] ne ""} {
        set root [file join $::env(HOME) .config]
    } else {
        set root [pwd]
    }
    return [file join $root gxtxt_pipeline instrument_library.ini]
}

proc ::GX::instrumentLibraryEnsureLoaded {} {
    variable instrumentLibraryLoaded
    if {!$instrumentLibraryLoaded} { instrumentLibraryLoad }
}

proc ::GX::instrumentLibraryGenerateId {} {
    variable instrumentLibraryCounter
    instrumentLibraryEnsureLoaded
    while {1} {
        incr instrumentLibraryCounter
        set id [format "library-instrument-%s-%d-%d-%d" \
            [clock format [clock seconds] -gmt 1 -format "%Y%m%dT%H%M%SZ"] \
            [pid] [clock clicks] $instrumentLibraryCounter]
        if {![instrumentLibraryExists $id]} { return $id }
    }
}

proc ::GX::instrumentLibraryIdsLoaded {} {
    variable instrumentLibrary
    set ids {}
    foreach key [array names instrumentLibrary "*,id"] {
        set id [string range $key 0 end-3]
        if {[lsearch -exact $ids $id] < 0} { lappend ids $id }
    }
    return [lsort -dictionary $ids]
}

proc ::GX::instrumentLibraryIds {} {
    instrumentLibraryEnsureLoaded
    return [instrumentLibraryIdsLoaded]
}

proc ::GX::instrumentLibraryLoad {} {
    variable instrumentLibrary
    variable instrumentLibraryLoaded
    array unset instrumentLibrary *
    set path [instrumentLibraryPath]
    if {![file isfile $path]} {
        set instrumentLibraryLoaded 1
        return {}
    }
    set d [parseIni $path]
    foreach key [dict keys $d] {
        if {[regexp {^instrument\.([^.]+)\.(.+)$} $key -> id field]} {
            set instrumentLibrary($id,$field) [dict get $d $key]
        }
    }
    set instrumentLibraryLoaded 1
    return [instrumentLibraryIdsLoaded]
}

proc ::GX::instrumentLibrarySave {} {
    variable instrumentLibrary
    variable instrumentLibraryLoaded
    variable instrumentLibraryApiVersion
    instrumentLibraryEnsureLoaded
    set path [instrumentLibraryPath]
    file mkdir [file dirname $path]
    set tmp "${path}.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Instrument Library API v1"
    puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
    puts $fd "\[registry\]"
    putKV $fd api_version $instrumentLibraryApiVersion
    set ids [instrumentLibraryIdsLoaded]
    putKV $fd entry_count [llength $ids]
    foreach id $ids {
        puts $fd "\n\[instrument.$id\]"
        foreach field {id display_name module_id category manufacturer model serial firmware default_role notes created_at updated_at demo demo_key} {
            putKV $fd $field [expr {[info exists instrumentLibrary($id,$field)] ? $instrumentLibrary($id,$field) : ""}]
        }
        set fieldNames {}
        foreach key [array names instrumentLibrary "$id,field.*"] {
            set field [string range $key [expr {[string length $id]+1}] end]
            lappend fieldNames $field
        }
        foreach field [lsort -dictionary -unique $fieldNames] {
            putKV $fd $field $instrumentLibrary($id,$field)
        }
    }
    close $fd
    file rename -force -- $tmp $path
    set instrumentLibraryLoaded 1
    return $path
}

proc ::GX::instrumentLibraryExists {id} {
    variable instrumentLibrary
    instrumentLibraryEnsureLoaded
    return [info exists instrumentLibrary($id,id)]
}

proc ::GX::instrumentLibraryField {id field {default ""}} {
    variable instrumentLibrary
    instrumentLibraryEnsureLoaded
    if {[info exists instrumentLibrary($id,$field)]} { return $instrumentLibrary($id,$field) }
    return $default
}

proc ::GX::instrumentLibraryGet {id} {
    if {![instrumentLibraryExists $id]} { error "Unknown Instrument Library entry '$id'." }
    set out [dict create]
    foreach field {id display_name module_id category manufacturer model serial firmware default_role notes created_at updated_at demo demo_key} {
        dict set out $field [instrumentLibraryField $id $field ""]
    }
    set fields [dict create]
    variable instrumentLibrary
    foreach key [array names instrumentLibrary "$id,field.*"] {
        set name [string range $key [expr {[string length $id]+7}] end]
        dict set fields $name $instrumentLibrary($key)
    }
    dict set out fields $fields
    return $out
}

proc ::GX::instrumentLibraryValidateEntry {entry {requireName 1}} {
    variable instrumentCatalog
    if {[catch {dict size $entry}]} { error "Instrument Library entry must be a dictionary." }
    if {$requireName && (![dict exists $entry display_name] || [string trim [dict get $entry display_name]] eq "")} {
        error "Instrument display name must not be empty."
    }
    set moduleId [expr {[dict exists $entry module_id] ? [dict get $entry module_id] : "instrument.generic"}]
    if {![info exists instrumentCatalog($moduleId,dict)]} { error "Unknown Instrument Module '$moduleId'." }
    if {[dict exists $entry fields] && [catch {dict size [dict get $entry fields]}]} {
        error "Instrument-specific fields must be a dictionary."
    }
    return $moduleId
}

proc ::GX::instrumentLibraryCreate {entry} {
    variable instrumentLibrary
    set moduleId [instrumentLibraryValidateEntry $entry]
    set id [instrumentLibraryGenerateId]
    set now [instrumentLibraryTimestamp]
    set defaults [dict create display_name "" module_id $moduleId category [instrumentModuleName $moduleId] manufacturer "" model "" serial "" firmware "" default_role "" notes "" demo 0 demo_key ""]
    dict for {field default} $defaults {
        set instrumentLibrary($id,$field) [expr {[dict exists $entry $field] ? [dict get $entry $field] : $default}]
    }
    set instrumentLibrary($id,id) $id
    set instrumentLibrary($id,created_at) $now
    set instrumentLibrary($id,updated_at) $now
    if {[dict exists $entry fields]} {
        dict for {key value} [dict get $entry fields] { set instrumentLibrary($id,field.$key) $value }
    }
    instrumentLibrarySave
    return $id
}

proc ::GX::instrumentLibraryUpdate {id changes} {
    variable instrumentLibrary
    if {![instrumentLibraryExists $id]} { error "Unknown Instrument Library entry '$id'." }
    if {[catch {dict size $changes}]} { error "Instrument Library changes must be a dictionary." }
    set allowed {display_name module_id category manufacturer model serial firmware default_role notes fields}
    dict for {field value} $changes {
        if {$field ni $allowed} { error "Instrument Library field '$field' is not editable." }
    }
    set candidate [instrumentLibraryGet $id]
    dict for {field value} $changes { dict set candidate $field $value }
    set moduleId [instrumentLibraryValidateEntry $candidate]
    foreach field {display_name module_id category manufacturer model serial firmware default_role notes} {
        if {[dict exists $changes $field]} { set instrumentLibrary($id,$field) [dict get $changes $field] }
    }
    if {[dict exists $changes fields]} {
        foreach key [array names instrumentLibrary "$id,field.*"] { unset instrumentLibrary($key) }
        dict for {key value} [dict get $changes fields] { set instrumentLibrary($id,field.$key) $value }
    }
    set instrumentLibrary($id,module_id) $moduleId
    set instrumentLibrary($id,updated_at) [instrumentLibraryTimestamp]
    instrumentLibrarySave
    return $id
}

proc ::GX::instrumentLibraryDelete {id} {
    variable instrumentLibrary
    if {![instrumentLibraryExists $id]} { return 0 }
    foreach key [array names instrumentLibrary "$id,*"] { unset instrumentLibrary($key) }
    instrumentLibrarySave
    return 1
}

proc ::GX::instrumentLibraryExport {id path} {
    if {![instrumentLibraryExists $id]} { error "Unknown Instrument Library entry '$id'." }
    set d [instrumentLibraryGet $id]
    file mkdir [file dirname [file normalize $path]]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT portable Instrument Library entry"
    puts $fd "\[instrument_library_entry\]"
    putKV $fd api_version 1
    putKV $fd source_id $id
    foreach field {display_name module_id category manufacturer model serial firmware default_role notes demo demo_key} { putKV $fd $field [dict get $d $field] }
    dict for {key value} [dict get $d fields] { putKV $fd "field.$key" $value }
    close $fd
    return $path
}

proc ::GX::instrumentLibraryImport {path} {
    if {![file isfile $path]} { error "Instrument Library import file does not exist: $path" }
    set d [parseIni $path]
    if {![dict exists $d instrument_library_entry.api_version] || [dict get $d instrument_library_entry.api_version] ne "1"} {
        error "Unsupported or missing Instrument Library entry API version."
    }
    set entry [dict create]
    foreach field {display_name module_id category manufacturer model serial firmware default_role notes demo demo_key} {
        set k "instrument_library_entry.$field"
        if {[dict exists $d $k]} { dict set entry $field [dict get $d $k] }
    }
    set fields [dict create]
    foreach key [dict keys $d] {
        if {[regexp {^instrument_library_entry\.field\.(.+)$} $key -> name]} { dict set fields $name [dict get $d $key] }
    }
    dict set entry fields $fields
    return [instrumentLibraryCreate $entry]
}

proc ::GX::instrumentLibraryDemoEntries {} {
    # Manufacturer/model names are real products; conservative demo records omit
    # unneeded specifications and use no plausible serial numbers.
    return [list \
        [dict create demo_key fluke87v display_name "Example — Fluke 87V" module_id instrument.generic category "Digital Multimeters" manufacturer "Fluke" model "87V" default_role "Electrical measurement" fields [dict create type "Digital multimeter"]] \
        [dict create demo_key keysight34465a display_name "Example — Keysight 34465A" module_id instrument.generic category "Bench Multimeters" manufacturer "Keysight" model "34465A" default_role "Precision electrical measurement" fields [dict create type "Bench digital multimeter"]] \
        [dict create demo_key rigoldho804 display_name "Example — RIGOL DHO804" module_id instrument.oscilloscope category "Oscilloscopes" manufacturer "RIGOL" model "DHO804" default_role "Acquisition" fields [dict create role "Acquisition"]] \
        [dict create demo_key tekmso24 display_name "Example — Tektronix MSO24" module_id instrument.oscilloscope category "Oscilloscopes" manufacturer "Tektronix" model "MSO24" default_role "Acquisition" fields [dict create role "Acquisition"]] \
        [dict create demo_key siglentsdg2042xp display_name "Example — Siglent SDG2042X Plus" module_id instrument.generic category "Signal Generators" manufacturer "Siglent" model "SDG2042X Plus" default_role "Signal generation" fields [dict create type "Function/arbitrary waveform generator"]] \
        [dict create demo_key rigoldg1022z display_name "Example — RIGOL DG1022Z" module_id instrument.generic category "Signal Generators" manufacturer "RIGOL" model "DG1022Z" default_role "Signal generation" fields [dict create type "Function/arbitrary waveform generator"]] \
        [dict create demo_key keysighte36312a display_name "Example — Keysight E36312A" module_id instrument.generic category "Power Supplies" manufacturer "Keysight" model "E36312A" default_role "DC supply" fields [dict create type "DC power supply"]] \
        [dict create demo_key rigoldp832a display_name "Example — RIGOL DP832A" module_id instrument.generic category "Power Supplies" manufacturer "RIGOL" model "DP832A" default_role "DC supply" fields [dict create type "DC power supply"]] \
        [dict create demo_key bk8600 display_name "Example — B&K Precision 8600" module_id instrument.generic category "Electronic Loads" manufacturer "B&K Precision" model "8600" default_role "DC load" fields [dict create type "Programmable DC electronic load"]] \
        [dict create demo_key keysighte4980a display_name "Example — Keysight E4980A" module_id instrument.generic category "LCR Meters" manufacturer "Keysight" model "E4980A" default_role "Impedance measurement" fields [dict create type "Precision LCR meter"]] \
        [dict create demo_key rsfpc1500 display_name "Example — Rohde & Schwarz FPC1500" module_id instrument.generic category "Spectrum Analyzers" manufacturer "Rohde & Schwarz" model "FPC1500" default_role "Spectrum analysis" fields [dict create type "Spectrum analyzer"]] \
        [dict create demo_key siglentssa3021xp display_name "Example — Siglent SSA3021X Plus" module_id instrument.generic category "Spectrum Analyzers" manufacturer "Siglent" model "SSA3021X Plus" default_role "Spectrum analysis" fields [dict create type "Spectrum analyzer"]] \
        [dict create demo_key keysightn9913c display_name "Example — Keysight N9913C" module_id instrument.generic category "RF Equipment" manufacturer "Keysight" model "N9913C" default_role "RF field analysis" fields [dict create type "Handheld RF analyzer"]] \
        [dict create demo_key fluke52ii display_name "Example — Fluke 52 II" module_id instrument.generic category "Temperature Measurement" manufacturer "Fluke" model "52 II" default_role "Temperature measurement" fields [dict create type "Digital thermometer"]] \
        [dict create demo_key hannahi5221 display_name "Example — Hanna Instruments HI5221" module_id instrument.generic category "pH / Ion Measurement" manufacturer "Hanna Instruments" model "HI5221" default_role "pH measurement" fields [dict create type "Benchtop pH meter"]] \
        [dict create demo_key mettlersd50 display_name "Example — METTLER TOLEDO SevenDirect SD50" module_id instrument.generic category "pH / Ion Measurement" manufacturer "METTLER TOLEDO" model "SevenDirect SD50" default_role "pH / ion measurement" fields [dict create type "Benchtop pH/ion meter"]] \
        [dict create demo_key genesys50 display_name "Example — Thermo Scientific GENESYS 50" module_id instrument.generic category "UV/Vis Spectrophotometers" manufacturer "Thermo Scientific" model "GENESYS 50" default_role "UV/Vis measurement" fields [dict create type "UV-Vis spectrophotometer"]] \
        [dict create demo_key agilent1260 display_name "Example — Agilent 1260 Infinity II LC" module_id instrument.generic category "Liquid Chromatography" manufacturer "Agilent" model "1260 Infinity II LC System" default_role "Liquid chromatography" fields [dict create type "HPLC system"]] \
        [dict create demo_key metrohm930 display_name "Example — Metrohm 930 Compact IC Flex" module_id instrument.generic category "Ion Chromatography" manufacturer "Metrohm" model "930 Compact IC Flex" default_role "Ion chromatography" fields [dict create type "Ion chromatograph"]] \
        [dict create demo_key shimadzugc2030 display_name "Example — Shimadzu Nexis GC-2030" module_id instrument.generic category "Gas Chromatography" manufacturer "Shimadzu" model "Nexis GC-2030" default_role "Gas chromatography" fields [dict create type "Gas chromatograph"]] \
    ]
}

proc ::GX::instrumentLibraryLoadDemo {} {
    set existing [dict create]
    foreach id [instrumentLibraryIds] {
        set key [instrumentLibraryField $id demo_key ""]
        if {$key ne ""} { dict set existing $key 1 }
    }
    set added 0
    foreach entry [instrumentLibraryDemoEntries] {
        set key [dict get $entry demo_key]
        if {[dict exists $existing $key]} continue
        dict set entry demo 1
        dict set entry serial ""
        dict set entry firmware ""
        dict set entry notes "# Example instrument\n\nDemo library entry for GUI, API, persistence and workflow testing. Replace with your laboratory's actual instrument metadata before scientific use."
        instrumentLibraryCreate $entry
        dict set existing $key 1
        incr added
    }
    return $added
}


proc ::GX::instrumentLibraryPersistCurrentExperiment {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return "" }
    set mdir [file join $currentSession metadata]
    file mkdir $mdir
    set path [file join $mdir manifest.ini]
    writeManifest $path
    catch {refreshManifestPreview}
    return $path
}

proc ::GX::instrumentLibraryApplyToExperiment {id} {
    variable instruments
    variable currentSession
    if {![instrumentLibraryExists $id]} { error "Unknown Instrument Library entry '$id'." }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Open or create a Session before adding a Library instrument to an Experiment." }
    set d [instrumentLibraryGet $id]
    set moduleId [dict get $d module_id]
    set n [addInstrumentFromModule $moduleId]
    set instruments($n,display_name) [dict get $d display_name]
    set instruments($n,library_id) $id
    set instruments($n,library_snapshot_at) [instrumentLibraryTimestamp]
    set instruments($n,library_source_updated_at) [dict get $d updated_at]
    foreach key [instrumentModuleFieldKeys $moduleId] {
        set value [instrumentModuleField $moduleId $key default ""]
        switch -- $key {
            role { set value [dict get $d default_role] }
            manufacturer - model - serial - firmware - notes { set value [dict get $d $key] }
            default {
                if {[dict exists [dict get $d fields] $key]} { set value [dict get [dict get $d fields] $key] }
                if {$key eq "type" && $value eq ""} { set value [dict get $d category] }
            }
        }
        set instruments($n,field,$key) $value
        if {$key in {role manufacturer model serial firmware notes}} { set instruments($n,$key) $value }
    }
    catch {instrumentLibraryPersistCurrentExperiment}
    catch {refreshNativeInstrumentationGui}
    return $n
}

proc ::GX::instrumentLibrarySyncExperimentInstance {idx} {
    variable instruments
    if {![info exists instruments($idx,library_id)] || [string trim $instruments($idx,library_id)] eq ""} { error "This Experiment instrument is not linked to an Instrument Library entry." }
    set id $instruments($idx,library_id)
    if {![instrumentLibraryExists $id]} { error "The linked Instrument Library entry no longer exists." }
    set d [instrumentLibraryGet $id]
    # Explicit synchronization refreshes identity/reference metadata only. Role,
    # notes and setup-specific module fields remain historical Experiment data.
    set instruments($idx,display_name) [dict get $d display_name]
    foreach key {manufacturer model serial firmware} {
        if {[lsearch -exact [instrumentModuleFieldKeys $instruments($idx,module_id)] $key] >= 0} {
            set instruments($idx,field,$key) [dict get $d $key]
        }
        set instruments($idx,$key) [dict get $d $key]
    }
    set instruments($idx,library_snapshot_at) [instrumentLibraryTimestamp]
    set instruments($idx,library_source_updated_at) [dict get $d updated_at]
    catch {instrumentLibraryPersistCurrentExperiment}
    catch {refreshNativeInstrumentationGui}
    return $idx
}

# Persist only the Library relationship metadata in addition to the existing
# Instrument Module snapshot. The copied instrument fields remain authoritative
# for historical Experiment reproducibility.
proc ::GX::manifestStringV2_before_import_queue {} {
    variable instruments
    variable instrumentCount
    set out [::GX::manifestStringV2_before_instrument_library_v1]
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        if {![info exists instruments($i,library_id)] || [string trim $instruments($i,library_id)] eq ""} continue
        append out "\n\[instrument_library_link.$i\]\n"
        appendKV out api_version 1
        foreach field {library_id library_snapshot_at library_source_updated_at} {
            appendKV out $field [expr {[info exists instruments($i,$field)] ? $instruments($i,$field) : ""}]
        }
    }
    return $out
}

proc ::GX::loadManifestV2_before_import_queue {path} {
    variable instruments
    variable instrumentCount
    ::GX::loadManifestV2_before_instrument_library_v1 $path
    set d [parseIni $path]
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        foreach field {library_id library_snapshot_at library_source_updated_at} {
            set k "instrument_library_link.$i.$field"
            set instruments($i,$field) [expr {[dict exists $d $k] ? [dict get $d $k] : ""}]
        }
    }
    catch {refreshNativeInstrumentationGui}
}

proc ::GX::instrumentLibrarySelectedId {w} {
    if {![winfo exists $w.pw.left.tree]} { return "" }
    set sel [$w.pw.left.tree selection]
    if {[llength $sel] != 1} { return "" }
    set item [lindex $sel 0]
    if {![string match "instrument:*" $item]} { return "" }
    return [string range $item 11 end]
}

proc ::GX::instrumentLibraryRenderDetails {w} {
    if {![winfo exists $w.details]} return
    destroyChildren $w.details
    set id [instrumentLibrarySelectedId $w]
    if {$id eq "" || ![instrumentLibraryExists $id]} {
        ttk::label $w.details.empty -text "Select an instrument to view its details."
        pack $w.details.empty -anchor nw -padx 8 -pady 8
        return
    }
    set d [instrumentLibraryGet $id]
    ttk::frame $w.details.meta
    pack $w.details.meta -fill x -padx 6 -pady 6
    grid columnconfigure $w.details.meta 1 -weight 1
    set r 0
    foreach {field label} {display_name Name module_id {Instrument module} category Type/Category manufacturer Manufacturer model Model serial Serial firmware Firmware default_role {Default role} id {Instrument ID} created_at Created updated_at Updated} {
        ttk::label $w.details.meta.l$r -text "$label:"
        ttk::label $w.details.meta.v$r -text [dict get $d $field] -anchor w -justify left
        grid $w.details.meta.l$r -row $r -column 0 -sticky ne -padx 4 -pady 2
        grid $w.details.meta.v$r -row $r -column 1 -sticky ew -padx 4 -pady 2
        incr r
    }
    dict for {key value} [dict get $d fields] {
        if {[string trim $value] eq ""} continue
        ttk::label $w.details.meta.l$r -text "[string totitle [string map {_ { }} $key]]:"
        ttk::label $w.details.meta.v$r -text $value -anchor w -justify left
        grid $w.details.meta.l$r -row $r -column 0 -sticky ne -padx 4 -pady 2
        grid $w.details.meta.v$r -row $r -column 1 -sticky ew -padx 4 -pady 2
        incr r
    }
    ttk::labelframe $w.details.notes -text "Notes / documentation"
    pack $w.details.notes -fill both -expand 1 -padx 6 -pady 6
    text $w.details.notes.t -wrap word -state disabled -height 10
    ttk::scrollbar $w.details.notes.sy -orient vertical -command [list $w.details.notes.t yview]
    $w.details.notes.t configure -yscrollcommand [list $w.details.notes.sy set]
    pack $w.details.notes.sy -side right -fill y
    pack $w.details.notes.t -side left -fill both -expand 1
    markupRenderStringToWidget $w.details.notes.t [dict get $d notes]
}

proc ::GX::instrumentLibraryRefreshWindow {{w .gxInstrumentLibrary}} {
    if {![winfo exists $w.pw.left.tree]} return
    $w.pw.left.tree delete [$w.pw.left.tree children {}]
    set groups [dict create]
    foreach id [instrumentLibraryIds] {
        set category [instrumentLibraryField $id category "Other"]
        if {[string trim $category] eq ""} { set category "Other" }
        dict lappend groups $category $id
    }
    set gi 0
    foreach category [lsort -dictionary [dict keys $groups]] {
        incr gi
        set parent "category:$gi"
        $w.pw.left.tree insert {} end -id $parent -text $category -open 1
        foreach id [lsort -command {apply {{a b} {string compare -nocase [::GX::instrumentLibraryField $a display_name] [::GX::instrumentLibraryField $b display_name]}}} [dict get $groups $category]] {
            $w.pw.left.tree insert $parent end -id "instrument:$id" -text [instrumentLibraryField $id display_name $id]
        }
    }
    instrumentLibraryRenderDetails $w
}

proc ::GX::instrumentLibraryEditorModuleChanged {w} {
    variable instrumentLibraryEditor
    if {![winfo exists $w.fields]} return
    destroyChildren $w.fields
    set moduleId $instrumentLibraryEditor(module_id)
    if {$moduleId eq ""} return
    grid columnconfigure $w.fields 1 -weight 1
    set r 0
    foreach key [instrumentModuleFieldKeys $moduleId] {
        if {$key in {role manufacturer model serial firmware notes}} continue
        set label [instrumentModuleField $moduleId $key label $key]
        ttk::label $w.fields.l$r -text "$label:"
        ttk::entry $w.fields.e$r -textvariable ::GX::instrumentLibraryEditor(field,$key)
        grid $w.fields.l$r -row $r -column 0 -sticky e -padx 4 -pady 2
        grid $w.fields.e$r -row $r -column 1 -sticky ew -padx 4 -pady 2
        incr r
    }
}

proc ::GX::instrumentLibraryEditorSave {w mode id} {
    variable instrumentLibraryEditor
    set notes [$instrumentLibraryEditor(notes_widget) get 1.0 "end-1c"]
    set fields [dict create]
    foreach key [instrumentModuleFieldKeys $instrumentLibraryEditor(module_id)] {
        if {$key in {role manufacturer model serial firmware notes}} continue
        if {[info exists instrumentLibraryEditor(field,$key)]} { dict set fields $key $instrumentLibraryEditor(field,$key) }
    }
    set entry [dict create display_name $instrumentLibraryEditor(display_name) module_id $instrumentLibraryEditor(module_id) category $instrumentLibraryEditor(category) manufacturer $instrumentLibraryEditor(manufacturer) model $instrumentLibraryEditor(model) serial $instrumentLibraryEditor(serial) firmware $instrumentLibraryEditor(firmware) default_role $instrumentLibraryEditor(default_role) notes $notes fields $fields]
    if {[catch {
        if {$mode eq "new"} { instrumentLibraryCreate $entry } else { instrumentLibraryUpdate $id $entry }
    } err]} {
        tk_messageBox -parent $w -icon error -title "Instrument Library" -message $err
        return
    }
    destroy $w
    catch {instrumentLibraryRefreshWindow}
}

proc ::GX::instrumentLibraryEditDialog {{mode new} {id ""}} {
    variable instrumentLibraryEditor
    variable instrumentOrder
    array unset instrumentLibraryEditor *
    if {$mode eq "edit"} {
        if {$id eq "" || ![instrumentLibraryExists $id]} return
        set d [instrumentLibraryGet $id]
    } else {
        set d [dict create display_name "" module_id instrument.generic category "Laboratory instruments" manufacturer "" model "" serial "" firmware "" default_role "" notes "" fields [dict create]]
    }
    foreach field {display_name module_id category manufacturer model serial firmware default_role} { set instrumentLibraryEditor($field) [dict get $d $field] }
    dict for {key value} [dict get $d fields] { set instrumentLibraryEditor(field,$key) $value }
    set w .gxInstrumentLibraryEditor
    catch {destroy $w}
    toplevel $w
    wm title $w [expr {$mode eq "new" ? "New Library Instrument" : "Edit Library Instrument"}]
    wm geometry $w 1000x760
    grid columnconfigure $w 1 -weight 1
    grid rowconfigure $w 10 -weight 1
    set r 0
    foreach {field label} {display_name {Display name} category {Type / category} manufacturer Manufacturer model Model serial {Serial number} firmware {Firmware / version} default_role {Default role}} {
        ttk::label $w.l$r -text "$label:"
        ttk::entry $w.e$r -textvariable ::GX::instrumentLibraryEditor($field)
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 3
        grid $w.e$r -row $r -column 1 -sticky ew -padx 5 -pady 3
        incr r
    }
    ttk::label $w.moduleLabel -text "Instrument module:"
    ttk::combobox $w.module -textvariable ::GX::instrumentLibraryEditor(module_id) -values $instrumentOrder -state readonly
    bind $w.module <<ComboboxSelected>> [list ::GX::instrumentLibraryEditorModuleChanged $w]
    grid $w.moduleLabel -row $r -column 0 -sticky e -padx 5 -pady 3
    grid $w.module -row $r -column 1 -sticky ew -padx 5 -pady 3
    incr r
    ttk::labelframe $w.fields -text "Instrument-module fields"
    grid $w.fields -row $r -column 0 -columnspan 2 -sticky ew -padx 5 -pady 5
    incr r
    ttk::labelframe $w.notes -text "Notes / documentation — GX-Markup / Markdown"
    grid $w.notes -row $r -column 0 -columnspan 2 -sticky nsew -padx 5 -pady 5
    grid rowconfigure $w.notes 0 -weight 1; grid columnconfigure $w.notes 0 -weight 1
    ttk::frame $w.notes.editor
    grid $w.notes.editor -row 0 -column 0 -sticky nsew
    lassign [buildMarkupEditorWidget $w.notes.editor [dict get $d notes]] source preview
    set instrumentLibraryEditor(notes_widget) $source
    incr r
    ttk::frame $w.buttons
    ttk::button $w.buttons.save -text "Save" -command [list ::GX::instrumentLibraryEditorSave $w $mode $id]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    pack $w.buttons.save $w.buttons.cancel -side left -padx 4
    grid $w.buttons -row $r -column 0 -columnspan 2 -pady 7
    instrumentLibraryEditorModuleChanged $w
}

proc ::GX::instrumentLibraryDeleteSelected {w} {
    set id [instrumentLibrarySelectedId $w]
    if {$id eq ""} return
    if {[tk_messageBox -parent $w -icon question -type yesno -title "Delete Library Instrument" -message "Delete this Instrument Library entry?\n\nExisting Experiment snapshots will not be deleted or changed."] eq "yes"} {
        instrumentLibraryDelete $id
        instrumentLibraryRefreshWindow $w
    }
}

proc ::GX::instrumentLibraryAddSelected {w} {
    set id [instrumentLibrarySelectedId $w]
    if {$id eq ""} return
    if {[catch {instrumentLibraryApplyToExperiment $id} err]} { tk_messageBox -parent $w -icon error -message $err; return }
    tk_messageBox -parent $w -icon info -message "Instrument added to the current Experiment as a historical snapshot."
}

proc ::GX::instrumentLibraryExportSelected {w} {
    set id [instrumentLibrarySelectedId $w]
    if {$id eq ""} return
    set path [tk_getSaveFile -parent $w -title "Export Instrument Library Entry" -defaultextension .ini -filetypes {{{GX-TXT instrument entry} {.ini}} {{All files} *}}]
    if {$path eq ""} return
    if {[catch {instrumentLibraryExport $id $path} err]} { tk_messageBox -parent $w -icon error -message $err }
}

proc ::GX::instrumentLibraryImportDialog {w} {
    set path [tk_getOpenFile -parent $w -title "Import Instrument Library Entry" -filetypes {{{GX-TXT instrument entry} {.ini}} {{All files} *}}]
    if {$path eq ""} return
    if {[catch {instrumentLibraryImport $path} err]} { tk_messageBox -parent $w -icon error -message $err; return }
    instrumentLibraryRefreshWindow $w
}

proc ::GX::instrumentLibraryLoadDemoDialog {w} {
    if {[catch {set n [instrumentLibraryLoadDemo]} err]} { tk_messageBox -parent $w -icon error -message $err; return }
    instrumentLibraryRefreshWindow $w
    tk_messageBox -parent $w -icon info -message "Added $n demo Instrument Library entries. Existing demo entries were not duplicated."
}

proc ::GX::instrumentLibraryOpenWindow {} {
    instrumentLibraryEnsureLoaded
    set w .gxInstrumentLibrary
    catch {destroy $w}
    toplevel $w
    wm title $w "Instrument Library"
    wm geometry $w 1180x720
    instrumentLibraryBuildInterface $w [list destroy $w]
    return $w
}

# GUI host adapter only: share the established Library widgets/callbacks between
# the standalone entry point and the embedded Session canvas. Storage is unchanged.
proc ::GX::instrumentLibraryEditSelected {w} {
    set id [instrumentLibrarySelectedId $w]
    if {$id ne ""} {instrumentLibraryEditDialog edit $id}
}
proc ::GX::instrumentLibraryBuildInterface {w closeCommand} {
    ttk::frame $w.toolbar
    foreach {name text command} [list \
        new "New instrument" [list ::GX::instrumentLibraryEditDialog new] \
        edit "Edit" [list ::GX::instrumentLibraryEditSelected $w] \
        delete "Delete" [list ::GX::instrumentLibraryDeleteSelected $w] \
        add "Add to Experiment" [list ::GX::instrumentLibraryAddSelected $w] \
        import "Import" [list ::GX::instrumentLibraryImportDialog $w] \
        export "Export" [list ::GX::instrumentLibraryExportSelected $w] \
        demo "Load Demo Library" [list ::GX::instrumentLibraryLoadDemoDialog $w]] {
        ttk::button $w.toolbar.$name -text $text -command $command
        pack $w.toolbar.$name -side left -padx 3 -pady 4
    }
    ttk::button $w.toolbar.close -text "Close" -command $closeCommand
    pack $w.toolbar.close -side right -padx 3 -pady 4
    pack $w.toolbar -fill x -padx 5
    ttk::panedwindow $w.pw -orient horizontal
    ttk::frame $w.pw.left
    ttk::frame $w.details
    $w.pw add $w.pw.left -weight 1
    $w.pw add $w.details -weight 2
    pack $w.pw -fill both -expand 1 -padx 5 -pady 5
    ttk::treeview $w.pw.left.tree -show tree -selectmode browse
    ttk::scrollbar $w.pw.left.sy -orient vertical -command [list $w.pw.left.tree yview]
    $w.pw.left.tree configure -yscrollcommand [list $w.pw.left.sy set]
    pack $w.pw.left.sy -side right -fill y
    pack $w.pw.left.tree -side left -fill both -expand 1
    bind $w.pw.left.tree <<TreeviewSelect>> [list ::GX::instrumentLibraryRenderDetails $w]
    instrumentLibraryRefreshWindow $w
    return $w
}

proc ::GX::instrumentLibrarySyncDialog {idx} {
    variable instruments
    if {![info exists instruments($idx,library_id)] || $instruments($idx,library_id) eq ""} return
    if {[tk_messageBox -icon question -type yesno -title "Sync from Instrument Library" -message "Refresh display name, manufacturer, model, serial and firmware from the current Library entry?\n\nExperiment-specific role, notes and setup fields will be preserved."] eq "yes"} {
        if {[catch {instrumentLibrarySyncExperimentInstance $idx} err]} { tk_messageBox -icon error -message $err }
    }
}

# Add Instrument Library access and source provenance to the existing
# Instrumentation page without replacing the established instance editor.
proc ::GX::refreshNativeInstrumentationGui {} {
    variable instruments
    variable instrumentCount
    ::GX::refreshNativeInstrumentationGui_before_instrument_library_v1
    set f .top.nb.instr
    if {![winfo exists $f]} return
    if {[winfo exists $f.bar] && ![winfo exists $f.bar.library]} {
        ttk::button $f.bar.library -text "Instrument Library..." -command ::GX::instrumentLibraryOpenWindow
        pack $f.bar.library -side left -padx 8
    }
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        if {![info exists instruments($i,library_id)] || [string trim $instruments($i,library_id)] eq ""} continue
        set id $instruments($i,library_id)
        set name [expr {[instrumentLibraryExists $id] ? [instrumentLibraryField $id display_name $id] : "$id (missing)"}]
        ttk::frame $f.body.i$i.library
        ttk::label $f.body.i$i.library.name -text "Library source: $name" -anchor w
        ttk::button $f.body.i$i.library.sync -text "Sync from Library" -command [list ::GX::instrumentLibrarySyncDialog $i]
        pack $f.body.i$i.library.name -side left -fill x -expand 1
        pack $f.body.i$i.library.sync -side right
        grid $f.body.i$i.library -row 0 -column 1 -sticky ew -padx 4 -pady 3
    }
}
