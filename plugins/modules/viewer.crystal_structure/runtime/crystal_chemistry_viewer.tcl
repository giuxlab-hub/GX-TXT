# SPDX-License-Identifier: GPL-3.0-or-later
# Crystal and density semantics stay here; Native 3D receives VTP/VTI layers.
namespace eval ::GX::CrystalViewer {
    variable window .crystal_chemistry_viewer
    variable dataset ""
    variable field ""
    variable supercell 1
    variable isovalues "0.05"
    variable opacity 0.48
    variable sliceAxis z
    variable sliceFraction 0.5
    variable contourLevel 0.05
    variable atoms {}
    variable summary {}
    variable catalog {}
    variable librarySearch ""
    variable message "Choose a CIF crystal or CUBE density source."
}

proc ::GX::CrystalViewer::_session {} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq ""} {
        error "Crystal Chemistry Viewer requires an open Session"
    }
    return $::GX::currentSession
}
proc ::GX::CrystalViewer::_root {} {
    return [file dirname [file dirname [::GX::moduleField viewer.crystal_structure descriptor]]]
}
proc ::GX::CrystalViewer::_plugin {} {
    return [file dirname [::GX::moduleField viewer.crystal_structure descriptor]]
}
proc ::GX::CrystalViewer::_statePath {} {
    return [file join [_session] metadata crystal_chemistry_viewer.ini]
}
proc ::GX::CrystalViewer::saveState {} {
    variable dataset; variable field; variable supercell; variable isovalues
    variable opacity; variable sliceAxis; variable sliceFraction; variable contourLevel
    set path [_statePath]
    file mkdir [file dirname $path]
    set fd [::open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "\[crystal_viewer\]"
        foreach key {dataset field supercell isovalues opacity sliceAxis sliceFraction contourLevel} {
            set value [set $key]
            if {[regexp {[\r\n]} $value]} {error "Invalid viewer state value"}
            puts $fd "$key=$value"
        }
    } finally {close $fd}
    ::GX::sessionPersistenceCommit
    return $path
}
proc ::GX::CrystalViewer::loadState {} {
    set path [_statePath]
    if {![file isfile $path]} {return {}}
    set ini [::GX::parseIni $path]
    set state [dict create]
    foreach key {dataset field supercell isovalues opacity sliceAxis sliceFraction contourLevel} {
        dict set state $key [::GX::descriptorValue $ini crystal_viewer $key ""]
    }
    return $state
}
proc ::GX::CrystalViewer::_catalog {} {
    variable catalog
    set path [file join [_plugin] library index.tsv]
    set fd [::open $path r]
    fconfigure $fd -encoding utf-8
    try {set data [read $fd]} finally {close $fd}
    set catalog {}
    foreach line [lrange [split $data "\n"] 1 end] {
        if {$line eq ""} continue
        set f [split $line "\t"]
        if {[llength $f] != 9} continue
        lassign $f kind id title rel digest rights url citation paired
        dict set catalog $id [dict create kind $kind id $id title $title relative_path $rel \
            sha256 $digest rights $rights url $url citation $citation paired_structure $paired]
    }
    return $catalog
}
proc ::GX::CrystalViewer::libraryEntries {} {return [_catalog]}
proc ::GX::CrystalViewer::_datasetIds {kind} {
    set ids {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[catch {set payload [::GX::sessionInspectionDatasetPayload $id]}]} continue
        set format [string tolower [dict get $payload format]]
        if {$format eq $kind} {lappend ids $id}
    }
    return $ids
}
proc ::GX::CrystalViewer::_source {id} {
    if {$id eq ""} {error "Select a source Dataset"}
    set payload [::GX::sessionInspectionDatasetPayload $id]
    set format [string tolower [dict get $payload format]]
    if {$format ni {cif cube}} {error "Dataset '$id' is not a CIF or CUBE source"}
    return $payload
}
proc ::GX::CrystalViewer::_sourcePath {id} {
    set payload [_source $id]
    set path [dict get $payload path]
    if {![file isfile $path]} {error "Canonical source '$id' is missing"}
    return $path
}
proc ::GX::CrystalViewer::installLibraryEntry {libraryId} {
    variable catalog
    if {$catalog eq ""} {_catalog}
    if {![dict exists $catalog $libraryId]} {error "Unknown library entry '$libraryId'"}
    set item [dict get $catalog $libraryId]
    set source [file join [_plugin] library [dict get $item relative_path]]
    if {[::GX::sha256File $source] ne [dict get $item sha256]} {
        error "Installed library source failed its recorded SHA-256"
    }
    set kind [dict get $item kind]
    set id [expr {$kind eq "cif" ? "crystal.cod.$libraryId" : "density.$libraryId"}]
    if {$id in [::GX::sessionInspectionDatasetIds]} {
        set payload [_source $id]
        if {[dict get $payload sha256] ne [dict get $item sha256]} {
            error "Existing Dataset '$id' conflicts with library source SHA-256"
        }
        return $id
    }
    set contract [expr {$kind eq "cif" ? "structure.crystal" : "field.scalar_3d"}]
    set media [expr {$kind eq "cif" ? "chemical/x-cif" : "chemical/x-gaussian-cube"}]
    set md [dict create chemistry.format $kind chemistry.source_id $libraryId \
        chemistry.title [dict get $item title] chemistry.source_url [dict get $item url] \
        chemistry.license [dict get $item rights] chemistry.citation [dict get $item citation] \
        chemistry.source_sha256 [dict get $item sha256]]
    ::GX::datasetFilePublicationPublish [_session] viewer.crystal_structure [dict create \
        dataset_id $id contract $contract format $kind source_file $source \
        storage_kind binary media_type $media producer_version 1.0.0 \
        source [dict get $item url] \
        provenance "[dict get $item title]; [dict get $item citation]; rights=[dict get $item rights]; original SHA-256=[dict get $item sha256]" \
        structured_metadata $md]
    return $id
}
proc ::GX::CrystalViewer::_decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 -strict $value]]
}
proc ::GX::CrystalViewer::_helper {action source {out ""} {xyz {}}} {
    variable supercell; variable sliceAxis; variable sliceFraction; variable contourLevel
    set python [::GX::runtimeToolRequired python]
    set script [file join [_plugin] runtime crystal_data.py]
    set cmd [list $python -B $script $action $source --tcl]
    if {$action eq "render"} {
        lappend cmd --out $out --supercell $supercell --slice-axis $sliceAxis \
            --slice-fraction $sliceFraction --contour $contourLevel
    } elseif {$action eq "sample"} {
        lappend cmd --xyz {*}$xyz
    }
    set raw [exec {*}$cmd]
    set lines [split [string trim $raw] "\n"]
    if {[lindex $lines 0] ne "GXCRYSTAL1" || [lindex $lines end] ne "OK"} {
        error "Crystal renderer returned an incomplete result"
    }
    set md {}; set atoms {}
    foreach line [lrange $lines 1 end-1] {
        set f [split $line "\t"]
        if {[lindex $f 0] eq "M" && [llength $f] == 3} {
            dict set md [_decode [lindex $f 1]] [_decode [lindex $f 2]]
        } elseif {[lindex $f 0] eq "A" && [llength $f] == 4} {
            set index [lindex $f 1]; set key [_decode [lindex $f 2]]
            while {[llength $atoms] <= $index} {lappend atoms {}}
            set atom [lindex $atoms $index]
            dict set atom $key [_decode [lindex $f 3]]
            lset atoms $index $atom
        }
    }
    return [dict create metadata $md atoms $atoms]
}
proc ::GX::CrystalViewer::_layer {id path kind fields sourceId} {
    if {![file isfile $path]} {return}
    set relative [string range $path [expr {[string length [file normalize [_session]]] + 1}] end]
    set artifact [::GX::viewerArtifactRegister $relative]
    set payload [_source $sourceId]
    set props [dict merge [dict create kind $kind source_mode artifact resource_path $relative \
        sha256 [dict get $artifact sha256] format [string range [file extension $path] 1 end] \
        format_version 1 source_dataset_id $sourceId \
        source_dataset_sha256 [dict get $payload sha256]] $fields]
    ::GX::viewerLayerSet viewer.native_3d native_3d $id $props
}
proc ::GX::CrystalViewer::_clearLayers {} {
    foreach id [::GX::viewerLayerIds viewer.native_3d native_3d] {
        if {[string match crystal_* $id]} {::GX::viewerLayerRemove viewer.native_3d native_3d $id}
    }
}
proc ::GX::CrystalViewer::_renderSource {sourceId dirname {repeats 1}} {
    variable supercell
    set path [_sourcePath $sourceId]
    set digest [dict get [_source $sourceId] sha256]
    set out [file join [_session] resources crystal_chemistry $dirname $digest]
    file mkdir $out
    set previous $supercell
    try {
        set supercell $repeats
        set result [_helper render $path $out]
    } finally {set supercell $previous}
    return [list $out $result]
}
proc ::GX::CrystalViewer::openDataset {id} {
    variable dataset; variable field
    set p [_source $id]
    set dataset $id
    if {[dict get $p format] eq "cube"} {set field $id}
    _refresh
    return $id
}
proc ::GX::CrystalViewer::setFieldDataset {id} {
    variable field
    if {$id ne "" && [dict get [_source $id] format] ne "cube"} {
        error "Electron-density overlay requires a Gaussian CUBE Dataset"
    }
    set field $id
    _refresh
    return $field
}
proc ::GX::CrystalViewer::showScene {} {
    variable dataset; variable field; variable supercell; variable isovalues
    variable opacity; variable atoms; variable summary; variable message
    if {$dataset eq ""} {error "Choose a crystal or molecular CUBE Dataset"}
    if {$supercell ni {1 2 3}} {error "Supercell must be 1, 2 or 3 per axis"}
    if {![string is double -strict $opacity] || $opacity < 0 || $opacity > 1} {
        error "Density opacity must be between 0 and 1"
    }
    set iso {}
    foreach x [split $isovalues ";"] {
        set x [string trim $x]
        if {![string is double -strict $x]} {error "Isovalues must be finite numbers separated by semicolons"}
        lappend iso $x
    }
    if {![llength $iso] || [llength $iso] > 32} {error "Choose 1 to 32 isovalues"}
    set [namespace current]::isovalues [join $iso ";"]
    set source [_source $dataset]
    set kind [dict get $source format]
    lassign [_renderSource $dataset structure [expr {$kind eq "cif" ? $supercell : 1}]] out parsed
    set atoms [dict get $parsed atoms]
    set summary [dict get $parsed metadata]
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    _clearLayers
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict create scene_mode scientific]
    _layer crystal_atoms [file join $out atoms.vtp] points [dict create radius_array radius_A scalar_array atomic_number layer_order 10] $dataset
    _layer crystal_bonds [file join $out bonds.vtp] trajectory [dict create tube_radius 0.065 layer_order 20] $dataset
    _layer crystal_cell [file join $out cell.vtp] trajectory [dict create tube_radius 0.028 layer_order 30] $dataset
    _layer crystal_axes [file join $out axes.vtp] trajectory [dict create tube_radius 0.045 layer_order 31] $dataset
    if {$field ne ""} {
        if {[dict get [_source $field] format] ne "cube"} {error "Density overlay must be CUBE"}
        lassign [_renderSource $field density 1] fieldOut fieldParsed
        _layer crystal_density [file join $fieldOut density.vti] isosurface [dict create \
            scalar_array electron_density isovalues $isovalues opacity $opacity layer_order 40] $field
        _layer crystal_slice [file join $fieldOut slice.vtp] surface [dict create \
            scalar_array electron_density opacity 0.30 layer_order 50] $field
        _layer crystal_contour [file join $fieldOut contour.vtp] trajectory [dict create \
            tube_radius 0.024 layer_order 60] $field
        dict set summary density_range [dict get [dict get $fieldParsed metadata] range]
        dict set summary density_unit [dict get [dict get $fieldParsed metadata] field_unit]
    }
    saveState
    ::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]
    set message "Rendered [llength $atoms] atoms; source SHA-256 [dict get $source sha256]"
    _refresh
    return [dict create atoms [llength $atoms] dataset_id $dataset field_dataset_id $field]
}
proc ::GX::CrystalViewer::_xyz {atom} {
    set text [dict get $atom cartesian]
    return [regexp -all -inline -- {-?[0-9]+(?:[.][0-9]+)?(?:[eE][+-]?[0-9]+)?} $text]
}
proc ::GX::CrystalViewer::_sub {a b} {
    set result {}
    foreach x $a y $b {lappend result [expr {double($x)-double($y)}]}
    return $result
}
proc ::GX::CrystalViewer::_dot {a b} {
    set result 0.
    foreach x $a y $b {set result [expr {$result+$x*$y}]}
    return $result
}
proc ::GX::CrystalViewer::_cross {a b} {
    lassign $a ax ay az; lassign $b bx by bz
    return [list [expr {$ay*$bz-$az*$by}] [expr {$az*$bx-$ax*$bz}] [expr {$ax*$by-$ay*$bx}]]
}
proc ::GX::CrystalViewer::measure {indices} {
    variable atoms
    if {[llength $indices] ni {2 3 4}} {error "Select 2, 3 or 4 sites for distance, angle or dihedral"}
    set pts {}
    foreach index $indices {
        if {![string is integer -strict $index] || $index < 0 || $index >= [llength $atoms]} {error "Invalid site selection"}
        lappend pts [_xyz [lindex $atoms $index]]
    }
    if {[llength $pts] == 2} {
        set v [_sub [lindex $pts 0] [lindex $pts 1]]
        return [dict create kind distance value [expr {sqrt([_dot $v $v])}] unit Å]
    }
    set a [_sub [lindex $pts 0] [lindex $pts 1]]
    set b [_sub [lindex $pts 2] [lindex $pts 1]]
    set da [expr {sqrt([_dot $a $a])}]; set db [expr {sqrt([_dot $b $b])}]
    if {$da == 0 || $db == 0} {error "Coincident sites cannot define an angle"}
    if {[llength $pts] == 3} {
        set cos [expr {max(-1.,min(1.,[_dot $a $b]/($da*$db)))}]
        return [dict create kind angle value [expr {acos($cos)*180./acos(-1.)}] unit deg]
    }
    set c [_sub [lindex $pts 3] [lindex $pts 2]]
    set n1 [_cross $a $b]; set n2 [_cross $b $c]
    set n1n [expr {sqrt([_dot $n1 $n1])}]; set n2n [expr {sqrt([_dot $n2 $n2])}]
    if {$n1n == 0 || $n2n == 0} {error "Collinear sites cannot define a dihedral"}
    set bh [lmap x $b {expr {$x/$db}}]
    set y [_dot [_cross $n1 $n2] $bh]
    set x [_dot $n1 $n2]
    return [dict create kind dihedral value [expr {atan2($y,$x)*180./acos(-1.)}] unit deg]
}
proc ::GX::CrystalViewer::_selectedIndices {} {
    variable window
    set ids [$window.right.sites selection]
    return [lmap id $ids {expr {int($id)}}]
}
proc ::GX::CrystalViewer::_selection {} {
    variable window; variable atoms; variable message; variable field
    set indices [_selectedIndices]
    if {[llength $indices] == 1} {
        set a [lindex $atoms [lindex $indices 0]]
        set message "Site [dict get $a label] · [dict get $a element] · occupancy [dict get $a occupancy] · fractional [dict get $a fractional] · Cartesian [dict get $a cartesian] Å · symmetry op [dict get $a operator]"
        if {$field ne ""} {
            if {![catch {set sampled [dict get [_helper sample [_sourcePath $field] "" [_xyz $a]] metadata]}]} {
                if {[dict get $sampled inside] eq "True"} {
                    append message " · field value [format %.5g [dict get $sampled value]] [dict get $sampled field_unit]"
                } else {append message " · outside density grid"}
            }
        }
    } elseif {[llength $indices] in {2 3 4}} {
        set measurement [measure $indices]
        set message "[string totitle [dict get $measurement kind]]: [format %.4f [dict get $measurement value]] [dict get $measurement unit]"
    } else {
        set message "Select 1 site to inspect; 2, 3 or 4 sites to measure."
    }
}
proc ::GX::CrystalViewer::_refresh {} {
    variable window; variable dataset; variable field; variable atoms; variable summary
    if {![winfo exists $window]} {return}
    set structures [concat [_datasetIds cif] [_datasetIds cube]]
    if {$dataset ni $structures} {set dataset ""; set atoms {}; set summary [dict create]}
    set fields [_datasetIds cube]
    if {$field ni $fields} {set field ""}
    $window.left.source configure -values $structures
    $window.left.field configure -values [linsert $fields 0 ""]
    $window.left.show configure -state [expr {$dataset eq "" ? "disabled" : "normal"}]
    foreach key {fit x y z} {
        $window.right.camera.$key configure -state [expr {[llength $atoms] ? "normal" : "disabled"}]
    }
    $window.right.sites delete [$window.right.sites children {}]
    set i 0
    foreach a $atoms {
        set xyz [_xyz $a]
        $window.right.sites insert {} end -id $i -values [list [dict get $a label] [dict get $a element] \
            [dict get $a occupancy] [dict get $a fractional] \
            [join [lmap x $xyz {format %.3f $x}] {, }]]
        incr i
    }
    set lines {}
    if {$dataset ne ""} {
        set p [_source $dataset]
        lappend lines "Source Dataset: $dataset" "Exact source SHA-256: [dict get $p sha256]"
        set md [::GX::datasetMetadataRead [_session] $dataset]
        foreach {key label} {chemistry.source_url URL chemistry.license Rights chemistry.citation Citation chemistry.source_id {Source ID}} {
            if {[dict exists $md $key]} {lappend lines "$label: [dict get $md $key]"}
        }
    }
    if {$field ne ""} {
        set fp [_source $field]
        lappend lines "Field Dataset: $field" "Field source SHA-256: [dict get $fp sha256]"
        set fmd [::GX::datasetMetadataRead [_session] $field]
        foreach {key label} {chemistry.source_url {Field URL} chemistry.license {Field rights}} {
            if {[dict exists $fmd $key]} {lappend lines "$label: [dict get $fmd $key]"}
        }
    }
    foreach {key label} {formula Formula space_group {Space group} cell {Cell a,b,c,α,β,γ} expanded_count {Symmetry-expanded atoms} density_range {Density range} density_unit {Field units}} {
        if {[dict exists $summary $key]} {lappend lines "$label: [dict get $summary $key]"}
    }
    $window.right.detailBox.details configure -state normal
    $window.right.detailBox.details delete 1.0 end
    $window.right.detailBox.details insert end [join $lines "\n"]
    $window.right.detailBox.details configure -state disabled
}
proc ::GX::CrystalViewer::_installSelected {} {
    variable window; variable catalog; variable dataset; variable field; variable message
    set selected [$window.left.libraryBox.list selection]
    if {![llength $selected]} {error "Select a library entry"}
    set entry [lindex $selected 0]
    set item [dict get $catalog $entry]
    set id [installLibraryEntry $entry]
    if {[dict get $item kind] eq "cif"} {
        set dataset $id
    } else {
        set field $id
        if {[dict get $item paired_structure] ne ""} {
            set dataset [installLibraryEntry [dict get $item paired_structure]]
        } else {set dataset $id}
    }
    set message "Installed [dict get $item title] as Dataset $id. Open 3D scene to view."
    _refresh
    return $id
}
proc ::GX::CrystalViewer::_importLocal {} {
    variable dataset; variable field; variable message
    set path [tk_getOpenFile -parent $::GX::CrystalViewer::window \
        -title {Import crystal structure or electron density} \
        -filetypes {{{Crystal structures and density} {.cif .cube .cub}} {{All files} *}}]
    if {$path eq ""} return
    set format [string tolower [file extension $path]]
    if {$format ni {.cif .cube .cub}} {error "Choose a CIF or Gaussian CUBE source"}
    set prefix [expr {$format eq ".cif" ? "crystal.local" : "density.local"}]
    set stem [string tolower [regsub -all {[^A-Za-z0-9._-]} [file rootname [file tail $path]] _]]
    set base "$prefix.$stem"
    set id $base
    set n 2
    while {$id in [::GX::sessionInspectionDatasetIds]} {set id "${base}_$n"; incr n}
    set imported [::GX::acquisitionHandlerImportSourceToSession acq.crystal_density [_session] $path $id "" {}]
    set dataset [lindex $imported 0]
    if {$format ne ".cif"} {set field $dataset}
    ::GX::sessionPersistenceCommit
    set message "Imported [file tail $path] as $dataset"
    _refresh
    return $dataset
}
proc ::GX::CrystalViewer::_filterLibrary {} {
    variable window; variable catalog; variable librarySearch
    if {![winfo exists $window.left.libraryBox.list]} {return}
    set tree $window.left.libraryBox.list
    $tree delete [$tree children {}]
    set q [string tolower [string trim $librarySearch]]
    foreach id [dict keys $catalog] {
        set item [dict get $catalog $id]
        if {$q ne "" && [string first $q [string tolower "[dict get $item title] $id [dict get $item kind] [dict get $item citation]"]] < 0} continue
        $tree insert {} end -id $id -values [list [string toupper [dict get $item kind]] \
            [dict get $item title] [dict get $item rights]]
    }
}
proc ::GX::CrystalViewer::_guard {script} {
    if {[catch {uplevel #0 $script} problem]} {
        set ::GX::CrystalViewer::message $problem
        tk_messageBox -icon error -title {Crystal Chemistry Viewer} -message $problem
    }
}
proc ::GX::CrystalViewer::_camera {preset} {
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    ::GX::Native3D::cameraPreset $preset
}
proc ::GX::CrystalViewer::open {context} {
    variable window; variable dataset; variable field; variable supercell
    variable isovalues; variable opacity; variable sliceAxis; variable sliceFraction
    variable contourLevel; variable message; variable catalog
    package require Tk
    _session
    _catalog
    set saved [loadState]
    foreach key {dataset field supercell isovalues opacity sliceAxis sliceFraction contourLevel} {
        if {[dict exists $saved $key] && [dict get $saved $key] ne ""} {set $key [dict get $saved $key]}
    }
    if {[dict exists $context open_context dataset_id]} {
        set candidate [dict get $context open_context dataset_id]
        if {$candidate in [::GX::sessionInspectionDatasetIds]} {set dataset $candidate}
    }
    catch {destroy $window}
    toplevel $window
    wm title $window {Crystal Chemistry Viewer}
    wm geometry $window 1240x860+35+35
    ttk::frame $window.top -padding 12
    ttk::label $window.top.title -text {Crystal Chemistry Viewer} -font {TkDefaultFont 16 bold}
    ttk::label $window.top.hint -text {CIF crystal structures · Gaussian CUBE electron density · Session-backed sources}
    pack $window.top.title $window.top.hint -anchor w
    pack $window.top -fill x
    ttk::panedwindow $window.panes -orient horizontal
    ttk::frame $window.left -padding 10
    ttk::frame $window.right -padding 10
    $window.panes add $window.left -weight 2
    $window.panes add $window.right -weight 3
    pack $window.panes -fill both -expand 1
    ttk::label $window.left.libraryTitle -text {Installed example library} -font {TkDefaultFont 11 bold}
    ttk::label $window.left.searchLabel -text {Search by name, COD ID or source type}
    ttk::entry $window.left.search -textvariable ::GX::CrystalViewer::librarySearch
    ttk::frame $window.left.libraryBox
    ttk::treeview $window.left.libraryBox.list -columns {type title rights} -show headings -height 6 -selectmode browse \
        -yscrollcommand [list $window.left.libraryBox.scroll set]
    ttk::scrollbar $window.left.libraryBox.scroll -orient vertical -command [list $window.left.libraryBox.list yview]
    foreach {key title width} {type Type 65 title Structure 210 rights Rights 80} {
        $window.left.libraryBox.list heading $key -text $title
        $window.left.libraryBox.list column $key -width $width
    }
    pack $window.left.libraryBox.scroll -side right -fill y
    pack $window.left.libraryBox.list -side left -fill both -expand 1
    _filterLibrary
    ttk::button $window.left.install -text {Install selected into Session} -command {::GX::CrystalViewer::_guard ::GX::CrystalViewer::_installSelected}
    ttk::button $window.left.import -text {Import local CIF / CUBE…} -command {::GX::CrystalViewer::_guard ::GX::CrystalViewer::_importLocal}
    ttk::button $window.left.refresh -text {Refresh Session sources} -command {::GX::CrystalViewer::_guard ::GX::CrystalViewer::_refresh}
    ttk::label $window.left.sourceLabel -text {Structure source Dataset}
    ttk::combobox $window.left.source -textvariable ::GX::CrystalViewer::dataset -state readonly -width 42
    ttk::label $window.left.fieldLabel -text {Electron-density CUBE Dataset}
    ttk::combobox $window.left.field -textvariable ::GX::CrystalViewer::field -state readonly -width 42
    ttk::label $window.left.superLabel -text {Supercell (a × b × c)}
    ttk::combobox $window.left.super -textvariable ::GX::CrystalViewer::supercell -values {1 2 3} -state readonly -width 8
    ttk::label $window.left.isoLabel -text {Isovalues (semicolon-separated; signed values allowed)}
    ttk::entry $window.left.iso -textvariable ::GX::CrystalViewer::isovalues
    ttk::label $window.left.opacityLabel -text {Density opacity}
    ttk::scale $window.left.opacity -from 0.05 -to 1.0 -variable ::GX::CrystalViewer::opacity
    ttk::label $window.left.sliceLabel -text {Slice plane and relative position}
    ttk::combobox $window.left.axis -textvariable ::GX::CrystalViewer::sliceAxis -values {x y z} -state readonly -width 5
    ttk::scale $window.left.fraction -from 0.02 -to 0.98 -variable ::GX::CrystalViewer::sliceFraction
    ttk::label $window.left.contourLabel -text {Contour value on slice}
    ttk::entry $window.left.contour -textvariable ::GX::CrystalViewer::contourLevel
    ttk::button $window.left.show -text {Open / update 3D structure and density} -command {::GX::CrystalViewer::_guard ::GX::CrystalViewer::showScene}
    foreach widget {libraryTitle} {pack $window.left.$widget -anchor w -pady {0 6}}
    pack $window.left.searchLabel -anchor w -pady {0 2}
    pack $window.left.search -fill x -pady {0 4}
    pack $window.left.libraryBox -fill both -expand 1
    pack $window.left.install $window.left.import $window.left.refresh -fill x -pady 2
    pack $window.left.sourceLabel -anchor w -pady {7 2}
    pack $window.left.source -fill x
    pack $window.left.fieldLabel -anchor w -pady {7 2}
    pack $window.left.field -fill x
    pack $window.left.superLabel $window.left.super $window.left.isoLabel $window.left.iso \
        $window.left.opacityLabel $window.left.opacity $window.left.sliceLabel \
        $window.left.axis $window.left.fraction $window.left.contourLabel \
        $window.left.contour $window.left.show -anchor w -fill x -pady 2
    ttk::label $window.right.siteTitle -text {Symmetry-expanded sites and measurements} -font {TkDefaultFont 11 bold}
    ttk::label $window.right.siteHint -text {Select one site to inspect, or 2–4 sites to measure distance, angle or dihedral.}
    ttk::treeview $window.right.sites -columns {site element occupancy fractional cartesian} -show headings -height 18 -selectmode extended
    foreach {key title width} {site Site 85 element Element 75 occupancy Occupancy 85 fractional Fractional 175 cartesian {Cartesian [Å]} 180} {
        $window.right.sites heading $key -text $title
        $window.right.sites column $key -width $width
    }
    ttk::frame $window.right.camera
    ttk::button $window.right.camera.fit -text {Fit} -command {::GX::CrystalViewer::_guard {::GX::CrystalViewer::_camera fit}}
    ttk::button $window.right.camera.x -text {View a} -command {::GX::CrystalViewer::_guard {::GX::CrystalViewer::_camera front}}
    ttk::button $window.right.camera.y -text {View b} -command {::GX::CrystalViewer::_guard {::GX::CrystalViewer::_camera right}}
    ttk::button $window.right.camera.z -text {View c} -command {::GX::CrystalViewer::_guard {::GX::CrystalViewer::_camera top}}
    pack $window.right.camera.fit $window.right.camera.x $window.right.camera.y $window.right.camera.z -side left -padx 3
    ttk::label $window.right.selection -textvariable ::GX::CrystalViewer::message -justify left -anchor w -wraplength 700
    ttk::label $window.right.detailTitle -text {Source and scientific metadata} -font {TkDefaultFont 10 bold}
    ttk::frame $window.right.detailBox
    text $window.right.detailBox.details -height 9 -wrap word -font TkDefaultFont \
        -relief solid -borderwidth 1 -background white -yscrollcommand [list $window.right.detailBox.scroll set]
    ttk::scrollbar $window.right.detailBox.scroll -orient vertical -command [list $window.right.detailBox.details yview]
    pack $window.right.detailBox.scroll -side right -fill y
    pack $window.right.detailBox.details -side left -fill both -expand 1
    pack $window.right.siteTitle $window.right.siteHint -anchor w -pady 3
    pack $window.right.sites -fill both -expand 1
    pack $window.right.camera -anchor w -pady 8
    pack $window.right.selection -fill x -pady 5
    pack $window.right.detailTitle -anchor w -pady {4 2}
    pack $window.right.detailBox -fill both -pady 3
    ttk::label $window.status -textvariable ::GX::CrystalViewer::message -anchor w -padding 8
    pack $window.status -fill x
    bind $window.right.sites <<TreeviewSelect>> {::GX::CrystalViewer::_selection}
    bind $window.left.libraryBox.list <Double-1> {::GX::CrystalViewer::_guard ::GX::CrystalViewer::_installSelected}
    bind $window.left.search <KeyRelease> {::GX::CrystalViewer::_filterLibrary}
    _refresh
    return $window
}
proc ::GX::CrystalViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Crystal viewer action must be open or rerender"}
    return [open $scene]
}
::GX::viewerBackendRegister crystal_chemistry_tk ::GX::CrystalViewer::viewerDispatch
