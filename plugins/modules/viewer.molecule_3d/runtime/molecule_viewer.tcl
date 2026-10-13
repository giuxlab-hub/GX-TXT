# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::MoleculeViewer {
    variable window .gxMoleculeViewer
    variable selected ""
    variable style ball_and_stick
    variable frame 0
    variable labels 1
    variable queryKind name
    variable query ""
    variable localPath ""
    variable libraryId ""
    variable atoms {}
    variable bonds {}
    variable frames {}
    variable source [dict create]
    variable report "Select two, three or four atoms to measure molecular geometry."
}

proc ::GX::MoleculeViewer::root {} {
    return [file dirname [::GX::moduleField viewer.molecule_3d descriptor]]
}
proc ::GX::MoleculeViewer::helper {} {
    return [file join [file dirname [::GX::moduleField acq.molecule_structure descriptor]] runtime molecule_io.py]
}
proc ::GX::MoleculeViewer::session {} {return [::GX::sessionInspectionCurrentSession]}
proc ::GX::MoleculeViewer::decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 -strict $value]]
}
proc ::GX::MoleculeViewer::runHelper {args} {
    set python [::GX::runtimeToolRequired python]
    return [exec $python -B [helper] {*}$args]
}
proc ::GX::MoleculeViewer::datasetIds {} {
    set result {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        set d [::GX::sessionInspectionDataset $id]
        if {[dict exists $d kind] && [dict get $d kind] eq "molecular.structure"} {lappend result $id}
    }
    return $result
}
proc ::GX::MoleculeViewer::uniqueId {base} {
    regsub -all {[^A-Za-z0-9._-]} [string tolower $base] _ base
    if {$base eq "" || ![regexp {^[A-Za-z_]} $base]} {set base "molecule_$base"}
    set used [::GX::sessionInspectionDatasetIds]
    set candidate $base
    set i 2
    while {$candidate in $used} {set candidate "${base}_$i"; incr i}
    return $candidate
}
proc ::GX::MoleculeViewer::importFile {path {id ""}} {
    if {![file isfile $path]} {error "Molecular source file does not exist: $path"}
    if {$id eq ""} {set id [uniqueId [file rootname [file tail $path]]]}
    set result [::GX::acquisitionHandlerImportSourceToSession \
        acq.molecule_structure [session] $path $id molecular.structure {}]
    ::GX::sessionPersistenceCommit
    return [lindex $result 0]
}
proc ::GX::MoleculeViewer::libraryRows {} {
    set path [file join [root] library manifest.tsv]
    set fd [::open $path r]
    fconfigure $fd -encoding utf-8 -translation lf
    set rows {}; set header [split [string trimright [gets $fd] "\r"] "\t"]
    try {
        while {[gets $fd line] >= 0} {
            if {[string trim $line] eq ""} continue
            set values [split [string trimright $line "\r"] "\t"]
            if {[llength $values] != [llength $header]} {error "Invalid CCD library manifest row"}
            set row [dict create]
            foreach key $header value $values {dict set row $key $value}
            lappend rows $row
        }
    } finally {close $fd}
    return $rows
}
proc ::GX::MoleculeViewer::installLibrary {code} {
    set row {}
    foreach entry [libraryRows] {if {[dict get $entry id] eq $code} {set row $entry; break}}
    if {$row eq ""} {error "Unknown CCD library identifier: $code"}
    set path [file join [root] library [dict get $row file]]
    if {![file isfile $path] || ![string equal -nocase [::GX::sha256File $path] [dict get $row sha256]]} {
        error "CCD library source SHA-256 mismatch: $code"
    }
    set id [importFile $path [uniqueId "ccd_$code"]]
    set md [::GX::datasetMetadataRead [session] $id]
    foreach {key value} [list molecule.source_service wwPDB-CCD molecule.source_id $code \
        molecule.reference_name [dict get $row name] \
        molecule.source_url [dict get $row source_url] molecule.license [dict get $row rights] \
        molecule.rights_url [dict get $row rights_url] molecule.citation [dict get $row source] \
        molecule.library_original_sha256 [dict get $row sha256]] {dict set md $key $value}
    ::GX::datasetMetadataWrite [session] $id $md
    ::GX::sessionPersistenceCommit
    return $id
}
proc ::GX::MoleculeViewer::lookup {kind identifier} {
    if {$kind ni {name cid smiles inchi inchikey}} {error "Unsupported PubChem query type"}
    set target [file join [session] raw molecule_lookup]
    file mkdir $target
    set output [file join $target "lookup_[pid]_[clock microseconds].sdf"]
    try {
        set response [runHelper resolve $kind $identifier $output]
        set fields [split [lindex [split $response "\n"] 0] "\t"]
        if {[lindex $fields 0] ne "RESOLVED" || [llength $fields] != 3} {error "PubChem resolver returned an invalid response"}
        set cid [decode [lindex $fields 1]]
        set url [decode [lindex $fields 2]]
        set digest [::GX::sha256File $output]
        set id [importFile $output [uniqueId "pubchem_$cid"]]
        set md [::GX::datasetMetadataRead [session] $id]
        foreach {key value} [list molecule.source_service PubChem-PUG-REST \
            molecule.source_id $cid molecule.source_url $url \
            molecule.reference_name [expr {$kind eq "name" ? $identifier : "PubChem CID $cid"}] \
            molecule.query_kind $kind molecule.query_identifier $identifier \
            molecule.retrieved_at [clock format [clock seconds] -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"] \
            molecule.online_original_sha256 $digest] {dict set md $key $value}
        ::GX::datasetMetadataWrite [session] $id $md
        ::GX::sessionPersistenceCommit
        return $id
    } finally {catch {file delete -- $output}}
}
proc ::GX::MoleculeViewer::loadDataset {id} {
    variable selected
    variable source
    variable frames
    variable frame
    if {$id ni [datasetIds]} {error "Molecular Dataset is not available: $id"}
    set source [::GX::sessionInspectionDatasetPayload $id]
    set records [runHelper inspect [dict get $source path]]
    set parsed [dict create]
    foreach line [split $records "\n"] {
        set columns [split $line "\t"]
        set kind [lindex $columns 0]
        set fields {}
        foreach value [lrange $columns 1 end] {lappend fields [decode $value]}
        switch -- $kind {
            FRAME {
                dict set parsed [lindex $fields 0] title [lindex $fields 1]
                dict set parsed [lindex $fields 0] atoms {}
                dict set parsed [lindex $fields 0] bonds {}
            }
            ATOM {
                set k [lindex $fields 0]
                set one [dict get $parsed $k]
                dict lappend one atoms [dict create index [lindex $fields 1] element [lindex $fields 2] \
                    x [lindex $fields 3] y [lindex $fields 4] z [lindex $fields 5] charge [lindex $fields 6]]
                dict set parsed $k $one
            }
            BOND {
                set k [lindex $fields 0]
                set one [dict get $parsed $k]
                dict lappend one bonds [lrange $fields 1 end]
                dict set parsed $k $one
            }
        }
    }
    if {![dict exists $parsed 0]} {error "Molecular source has no readable conformer"}
    set frames $parsed
    set selected $id
    if {![dict exists $frames $frame]} {set frame 0}
    showFrame
    return [dict create id $id sha256 [dict get $source sha256] conformers [dict size $frames]]
}
proc ::GX::MoleculeViewer::showFrame {} {
    variable frame
    variable frames
    variable atoms
    variable bonds
    if {![dict exists $frames $frame]} {error "Conformer index is not available"}
    set atoms [dict get $frames $frame atoms]
    set bonds [dict get $frames $frame bonds]
    refreshWidgets
}
proc ::GX::MoleculeViewer::point {index} {
    variable atoms
    if {![string is integer -strict $index] || $index < 1 || $index > [llength $atoms]} {
        error "Atom index is out of range: $index"
    }
    set a [lindex $atoms [expr {$index - 1}]]
    return [list [dict get $a x] [dict get $a y] [dict get $a z]]
}
proc ::GX::MoleculeViewer::sub {a b} {
    return [list [expr {[lindex $a 0]-[lindex $b 0]}] \
        [expr {[lindex $a 1]-[lindex $b 1]}] [expr {[lindex $a 2]-[lindex $b 2]}]]
}
proc ::GX::MoleculeViewer::dot {a b} {
    return [expr {[lindex $a 0]*[lindex $b 0]+[lindex $a 1]*[lindex $b 1]+[lindex $a 2]*[lindex $b 2]}]
}
proc ::GX::MoleculeViewer::cross {a b} {
    return [list [expr {[lindex $a 1]*[lindex $b 2]-[lindex $a 2]*[lindex $b 1]}] \
        [expr {[lindex $a 2]*[lindex $b 0]-[lindex $a 0]*[lindex $b 2]}] \
        [expr {[lindex $a 0]*[lindex $b 1]-[lindex $a 1]*[lindex $b 0]}]]
}
proc ::GX::MoleculeViewer::norm {a} {expr {sqrt([dot $a $a])}}
proc ::GX::MoleculeViewer::measure {kind indices} {
    set needed [dict get [dict create distance 2 angle 3 dihedral 4] $kind]
    if {[llength $indices] != $needed || [llength [lsort -unique $indices]] != $needed} {
        error "$kind requires exactly $needed distinct atom indices"
    }
    set p {}; foreach index $indices {lappend p [point $index]}
    if {$kind eq "distance"} {return [expr {[norm [sub [lindex $p 0] [lindex $p 1]]]}]}
    if {$kind eq "angle"} {
        set a [sub [lindex $p 0] [lindex $p 1]]
        set b [sub [lindex $p 2] [lindex $p 1]]
        set d [expr {[norm $a]*[norm $b]}]
        if {$d < 1e-12} {error "Angle is undefined for coincident atoms"}
        set cosine [expr {max(-1.0,min(1.0,[dot $a $b]/$d))}]
        return [expr {acos($cosine)*180.0/acos(-1)}]
    }
    set b0 [sub [lindex $p 0] [lindex $p 1]]
    set b1 [sub [lindex $p 2] [lindex $p 1]]
    set b2 [sub [lindex $p 3] [lindex $p 2]]
    set d [norm $b1]
    if {$d < 1e-12} {error "Dihedral is undefined for coincident central atoms"}
    set n1 [cross $b0 $b1]
    set n2 [cross $b1 $b2]
    if {[norm $n1] < 1e-12 || [norm $n2] < 1e-12} {error "Dihedral is undefined for collinear atoms"}
    set unit [lmap x $b1 {expr {$x/$d}}]
    return [expr {atan2([dot [cross $n1 $n2] $unit],[dot $n1 $n2])*180.0/acos(-1)}]
}
proc ::GX::MoleculeViewer::statePath {} {return [file join [session] metadata molecule_viewer.ini]}
proc ::GX::MoleculeViewer::saveState {} {
    variable selected; variable frame; variable style; variable labels
    if {$selected eq ""} {error "Select a molecular Dataset first"}
    set path [statePath]
    set fd [::open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "\[molecule_viewer\]"
        puts $fd "dataset_id=$selected"
        puts $fd "frame=$frame"
        puts $fd "style=$style"
        puts $fd "labels=$labels"
        puts $fd "source_sha256=[dict get [::GX::sessionInspectionDatasetPayload $selected] sha256]"
    } finally {close $fd}
    ::GX::sessionPersistenceCommit
    return $path
}
proc ::GX::MoleculeViewer::loadState {} {
    set path [statePath]
    if {![file isfile $path]} {return {}}
    set ini [::GX::parseIni $path]
    set state [dict create]
    foreach key {dataset_id frame style labels source_sha256} {
        dict set state $key [::GX::descriptorValue $ini molecule_viewer $key ""]
    }
    return $state
}
proc ::GX::MoleculeViewer::render3D {} {
    variable selected; variable frame; variable style; variable atoms
    if {$selected eq ""} {error "Select a molecular Dataset first"}
    set source [::GX::sessionInspectionDatasetPayload $selected]
    set relative [file join metadata molecule_viewer [format "%s_%s_%s_%s.vtp" \
        [string map {. _ - _} $selected] [string range [dict get $source sha256] 0 11] $frame $style]]
    set output [file join [session] $relative]
    file mkdir [file dirname $output]
    if {![file isfile $output]} {runHelper mesh [dict get $source path] $output --frame $frame --style $style}
    set artifact [::GX::viewerArtifactRegister $relative]
    foreach layer [::GX::viewerLayerIds viewer.native_3d native_3d] {
        if {[string match molecule_* $layer]} {::GX::viewerLayerRemove viewer.native_3d native_3d $layer}
    }
    # Choose an initial camera normal to the thinnest molecular dimension.
    # This exposes planar molecules and bent triatomics without changing the
    # generic Native 3D renderer's scientific meaning.
    set mins {}; set maxs {}
    foreach key {x y z} {
        set values [lmap atom $atoms {dict get $atom $key}]
        lappend mins [::tcl::mathfunc::min {*}$values]
        lappend maxs [::tcl::mathfunc::max {*}$values]
    }
    set spans {}; set center {}
    for {set i 0} {$i < 3} {incr i} {
        lappend spans [expr {[lindex $maxs $i]-[lindex $mins $i]}]
        lappend center [expr {([lindex $maxs $i]+[lindex $mins $i])/2.0}]
    }
    set axis 0
    for {set i 1} {$i < 3} {incr i} {
        if {[lindex $spans $i] < [lindex $spans $axis]} {set axis $i}
    }
    set maxSpan [::tcl::mathfunc::max {*}$spans]
    set radialMargin [expr {$style eq "space_filling" ? 4.0 : 1.2}]
    set distance [expr {max(5.0,2.2*($maxSpan+$radialMargin))}]
    set position $center
    lset position $axis [expr {[lindex $position $axis]+$distance}]
    set up [expr {$axis == 1 ? {0;0;1} : {0;1;0}}]
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict create scene_mode scientific \
        camera_position [join $position {;}] camera_target [join $center {;}] camera_up $up]
    ::GX::viewerLayerSet viewer.native_3d native_3d molecule_main [dict create \
        kind surface source_mode artifact resource_path $relative \
        sha256 [dict get $artifact sha256] format vtp format_version 1 \
        scalar_array element source_dataset_id $selected \
        source_dataset_sha256 [dict get $source sha256] layer_order 10]
    set result [::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]]
    saveState
    return $result
}
proc ::GX::MoleculeViewer::pick {event} {
    variable atoms; variable window
    if {![dict exists $event event] || [dict get $event event] ne "pick" || ![dict exists $event position]} return
    set p [dict get $event position]
    if {[llength $p] != 3} return
    set best -1; set distance Inf
    foreach atom $atoms {
        set idx [dict get $atom index]
        set d [norm [sub $p [point $idx]]]
        if {$d < $distance} {set best $idx; set distance $d}
    }
    if {$best < 1 || $distance > 1.25 || ![winfo exists $window.structure.data.atoms]} return
    $window.structure.data.atoms selection set $best
    $window.structure.data.atoms see $best
    showAtom
}
proc ::GX::MoleculeViewer::selectedIndices {} {
    variable window
    if {![winfo exists $window.structure.data.atoms]} {return {}}
    return [lsort -integer [$window.structure.data.atoms selection]]
}
proc ::GX::MoleculeViewer::showAtom {} {
    variable window; variable atoms; variable report
    set indices [selectedIndices]
    if {[llength $indices] == 1} {
        set a [lindex $atoms [expr {[lindex $indices 0]-1}]]
        set report "Atom [dict get $a index]: [dict get $a element], charge [dict get $a charge]; Cartesian ([dict get $a x], [dict get $a y], [dict get $a z]) Å"
    } else {
        set report "Selected atoms: [join $indices {, }]. Choose Distance, Angle or Dihedral."
    }
    drawProjection
}
proc ::GX::MoleculeViewer::measureSelection {kind} {
    variable report
    set indices [selectedIndices]
    if {[catch {set value [measure $kind $indices]} problem]} {set report $problem; return}
    set unit [expr {$kind eq "distance" ? "Å" : "°"}]
    set report "[string totitle $kind] [join $indices {–}]: [format %.4f $value] $unit"
}
proc ::GX::MoleculeViewer::projectionClick {x y} {
    variable atoms; variable window
    if {![winfo exists $window.structure.projbox.projection]} return
    set best -1; set dmin 144
    foreach atom $atoms {
        set id [dict get $atom index]
        set tag "atom_$id"
        set box [$window.structure.projbox.projection bbox $tag]
        if {[llength $box] != 4} continue
        set dx [expr {($x-([lindex $box 0]+[lindex $box 2])/2.0)}]
        set dy [expr {($y-([lindex $box 1]+[lindex $box 3])/2.0)}]
        set dist [expr {$dx*$dx+$dy*$dy}]
        if {$dist < $dmin} {set dmin $dist; set best $id}
    }
    if {$best > 0} {$window.structure.data.atoms selection set $best; $window.structure.data.atoms see $best; showAtom}
}
proc ::GX::MoleculeViewer::drawProjection {} {
    variable window; variable atoms; variable bonds; variable labels
    if {![winfo exists $window.structure.projbox.projection] || ![llength $atoms]} return
    set c $window.structure.projbox.projection
    $c delete all
    set width [winfo width $c]; if {$width < 100} {set width 540}
    set height [winfo height $c]; if {$height < 100} {set height 310}
    set xs [lmap a $atoms {dict get $a x}]
    set ys [lmap a $atoms {dict get $a y}]
    set x0 [::tcl::mathfunc::min {*}$xs]; set x1 [::tcl::mathfunc::max {*}$xs]
    set y0 [::tcl::mathfunc::min {*}$ys]; set y1 [::tcl::mathfunc::max {*}$ys]
    set span [expr {max($x1-$x0,$y1-$y0,1.0)}]
    set scale [expr {min(($width-50.0)/$span,($height-50.0)/$span)}]
    set cx [expr {($x0+$x1)/2.0}]; set cy [expr {($y0+$y1)/2.0}]
    set coords [dict create]
    foreach a $atoms {
        dict set coords [dict get $a index] [list \
            [expr {$width/2.0+([dict get $a x]-$cx)*$scale}] \
            [expr {$height/2.0-([dict get $a y]-$cy)*$scale}]]
    }
    foreach bond $bonds {
        lassign $bond i j order
        lassign [dict get $coords $i] ax ay; lassign [dict get $coords $j] bx by
        $c create line $ax $ay $bx $by -fill #6b7280 -width [expr {$order > 1 ? 3 : 2}]
    }
    set colors [dict create H #dbe3ed C #424b5a N #3b75cf O #d94e55 S #dab638 P #d48232 \
        Cl #41a75b F #61ba65 Fe #c6843e]
    set chosen [selectedIndices]
    foreach a $atoms {
        set id [dict get $a index]; set sym [dict get $a element]
        lassign [dict get $coords $id] x y
        set r [expr {$id in $chosen ? 11 : 8}]
        set fill [expr {[dict exists $colors $sym] ? [dict get $colors $sym] : "#9d7cc6"}]
        $c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] \
            -fill $fill -outline [expr {$id in $chosen ? "#121826" : "#f8fafc"}] \
            -width [expr {$id in $chosen ? 3 : 1}] -tags "atom_$id"
        if {$labels} {$c create text [expr {$x+14}] [expr {$y-11}] -anchor w \
            -text "$sym$id" -fill #253042 -font {TkDefaultFont 9 bold} -tags "atom_$id"}
    }
}
proc ::GX::MoleculeViewer::refreshWidgets {} {
    variable window; variable atoms; variable bonds; variable frames; variable selected
    if {![winfo exists $window]} return
    set t $window.structure.data.atoms
    $t delete [$t children {}]
    foreach a $atoms {
        set idx [dict get $a index]
        $t insert {} end -id $idx -values [list $idx [dict get $a element] \
            [dict get $a charge] [format %.3f [dict get $a x]] \
            [format %.3f [dict get $a y]] [format %.3f [dict get $a z]]]
    }
    set t $window.structure.data.bonds
    $t delete [$t children {}]
    foreach bond $bonds {$t insert {} end -values $bond}
    $window.structure.top.conformer configure -values [lsort -integer [dict keys $frames]]
    set md [::GX::datasetMetadataRead [session] $selected]
    set details "Dataset: $selected | atoms: [llength $atoms] | bonds: [llength $bonds]"
    foreach {key label} {molecule.reference_name Name molecule.net_formal_charge {Formal charge} \
        molecule.coordinates Coordinates} {
        if {[dict exists $md $key]} {append details " | $label: [dict get $md $key]"}
    }
    $window.structure.summary configure -text $details
    set info "Canonical source: [dict get [::GX::sessionInspectionDatasetPayload $selected] relative_path]\n"
    append info "Canonical SHA-256: [dict get [::GX::sessionInspectionDatasetPayload $selected] sha256]\n"
    set record [::GX::sessionInspectionDataset $selected]
    foreach key {source_raw source_sha256 provenance created_at} {
        if {[dict exists $record $key]} {append info "$key: [dict get $record $key]\n"}
    }
    foreach key [lsort [dict keys $md]] {append info "$key: [dict get $md $key]\n"}
    $window.source.text configure -state normal
    $window.source.text delete 1.0 end
    $window.source.text insert end $info
    $window.source.text configure -state disabled
    drawProjection
}
proc ::GX::MoleculeViewer::refreshDatasets {} {
    variable window; variable selected
    if {![winfo exists $window]} return
    set ids [datasetIds]
    $window.structure.top.dataset configure -values $ids
    if {$selected ni $ids && [llength $ids]} {set selected [lindex $ids 0]}
    if {$selected ne ""} {loadDataset $selected}
}
proc ::GX::MoleculeViewer::showError {title problem} {
    tk_messageBox -parent .gxMoleculeViewer -icon error -title $title -message $problem
}
proc ::GX::MoleculeViewer::guiInstall {} {
    variable libraryId; variable selected
    if {[catch {set selected [installLibrary $libraryId]; refreshDatasets} problem]} {showError {Install molecule} $problem}
}
proc ::GX::MoleculeViewer::guiImport {} {
    variable localPath; variable selected
    if {$localPath eq ""} {set localPath [tk_getOpenFile -parent .gxMoleculeViewer -title {Open molecular structure} \
        -filetypes {{{Molecular structures} {.sdf .mol .xyz .pdb .ent}} {{All files} *}}]}
    if {$localPath eq ""} return
    if {[catch {set selected [importFile $localPath]; refreshDatasets} problem]} {showError {Import molecule} $problem}
}
proc ::GX::MoleculeViewer::guiLookup {} {
    variable queryKind; variable query; variable selected
    if {[catch {set selected [lookup $queryKind $query]; refreshDatasets} problem]} {showError {PubChem lookup} $problem}
}
proc ::GX::MoleculeViewer::guiRender {} {
    if {[catch {render3D} problem]} {showError {Render molecule} $problem}
}
proc ::GX::MoleculeViewer::guiSave {} {
    if {[catch {saveState} problem]} {showError {Save molecule view} $problem}
}
proc ::GX::MoleculeViewer::open {context} {
    variable window; variable selected; variable frame; variable style; variable labels; variable libraryId
    package require Tk
    set state [loadState]
    if {[dict exists $state style] && [dict get $state style] in {ball_and_stick space_filling}} {set style [dict get $state style]}
    if {[dict exists $state frame] && [string is integer -strict [dict get $state frame]]} {set frame [dict get $state frame]}
    if {[dict exists $state labels] && [dict get $state labels] in {0 1}} {set labels [dict get $state labels]}
    set ids [datasetIds]
    if {[dict exists $state dataset_id] && [dict get $state dataset_id] in $ids} {
        set selected [dict get $state dataset_id]
        if {[dict exists $state source_sha256] && [dict get $state source_sha256] ne "" &&
            ![string equal -nocase [dict get $state source_sha256] [dict get [::GX::sessionInspectionDatasetPayload $selected] sha256]]} {
            error "Saved molecular source SHA-256 changed"
        }
    } elseif {[llength $ids]} {set selected [lindex $ids 0]}
    if {[dict exists $context open_context dataset_id] && [dict get $context open_context dataset_id] in $ids} {
        set selected [dict get $context open_context dataset_id]
    }
    catch {destroy $window}
    toplevel $window
    wm title $window {Molecule Viewer}
    wm geometry $window 1060x760+30+30
    ttk::notebook $window.tabs
    ttk::frame $window.structure -padding 10
    ttk::frame $window.library -padding 10
    ttk::frame $window.source -padding 10
    $window.tabs add $window.structure -text Structure
    $window.tabs add $window.library -text {Library & import}
    $window.tabs add $window.source -text Source
    pack $window.tabs -fill both -expand 1
    ttk::frame $window.structure.top
    ttk::label $window.structure.top.l -text {Molecular Dataset}
    ttk::combobox $window.structure.top.dataset -textvariable ::GX::MoleculeViewer::selected -values $ids -state readonly -width 36
    ttk::label $window.structure.top.f -text Conformer
    ttk::combobox $window.structure.top.conformer -textvariable ::GX::MoleculeViewer::frame -state readonly -width 5
    ttk::label $window.structure.top.s -text Display
    ttk::combobox $window.structure.top.style -textvariable ::GX::MoleculeViewer::style \
        -values {ball_and_stick space_filling} -state readonly -width 17
    ttk::checkbutton $window.structure.top.labels -text {Atom labels} \
        -variable ::GX::MoleculeViewer::labels -command ::GX::MoleculeViewer::drawProjection
    ttk::button $window.structure.top.render -text {Open 3D structure} -command ::GX::MoleculeViewer::guiRender
    ttk::button $window.structure.top.save -text {Save view} -command ::GX::MoleculeViewer::guiSave
    ttk::button $window.structure.top.fit -text {Fit 3D view} -command {catch {::GX::Native3D::cameraPreset fit}}
    ttk::button $window.structure.top.reset -text {Reset 3D view} -command {catch {::GX::Native3D::cameraPreset reset}}
    grid $window.structure.top.l -row 0 -column 0 -sticky w -padx 4 -pady 4
    grid $window.structure.top.dataset -row 0 -column 1 -sticky ew -padx 4 -pady 4
    grid $window.structure.top.f -row 0 -column 2 -sticky w -padx 4 -pady 4
    grid $window.structure.top.conformer -row 0 -column 3 -sticky w -padx 4 -pady 4
    grid $window.structure.top.s -row 1 -column 0 -sticky w -padx 4 -pady 4
    grid $window.structure.top.style -row 1 -column 1 -sticky w -padx 4 -pady 4
    grid $window.structure.top.labels -row 1 -column 2 -sticky w -padx 4 -pady 4
    grid $window.structure.top.render -row 2 -column 0 -sticky w -padx 4 -pady 4
    grid $window.structure.top.fit -row 2 -column 1 -sticky w -padx 4 -pady 4
    grid $window.structure.top.reset -row 2 -column 2 -sticky w -padx 4 -pady 4
    grid $window.structure.top.save -row 2 -column 3 -sticky w -padx 4 -pady 4
    grid columnconfigure $window.structure.top 1 -weight 1
    ttk::label $window.structure.summary -anchor w -wraplength 1000
    ttk::panedwindow $window.structure.panes -orient horizontal
    ttk::frame $window.structure.projbox
    ttk::label $window.structure.projbox.title -text {Coordinate projection (select atoms here or in table)}
    canvas $window.structure.projbox.projection -background #f8fafc -height 310 -width 540 -highlightthickness 1 -highlightbackground #c6cfda
    pack $window.structure.projbox.title -anchor w -pady 3
    pack $window.structure.projbox.projection -fill both -expand 1
    ttk::frame $window.structure.data
    ttk::label $window.structure.data.atomtitle -text {Atoms — select 2, 3 or 4 for geometry}
    ttk::treeview $window.structure.data.atoms -columns {index element charge x y z} -show headings -selectmode extended -height 13
    foreach {key label width} {index # 44 element Element 72 charge Charge 62 x {X [Å]} 74 y {Y [Å]} 74 z {Z [Å]} 74} {
        $window.structure.data.atoms heading $key -text $label
        $window.structure.data.atoms column $key -width $width -stretch 0
    }
    ttk::label $window.structure.data.bondtitle -text {Bonds (source order or inferred single bonds)}
    ttk::treeview $window.structure.data.bonds -columns {a b order} -show headings -height 5
    foreach {key label} {a Atom1 b Atom2 order Order} {$window.structure.data.bonds heading $key -text $label; $window.structure.data.bonds column $key -width 75}
    pack $window.structure.data.atomtitle -anchor w
    pack $window.structure.data.atoms -fill both -expand 1
    pack $window.structure.data.bondtitle -anchor w -pady {8 0}
    pack $window.structure.data.bonds -fill x
    $window.structure.panes add $window.structure.projbox -weight 3
    $window.structure.panes add $window.structure.data -weight 2
    ttk::frame $window.structure.measure
    ttk::button $window.structure.measure.distance -text {Distance (2 atoms)} -command {::GX::MoleculeViewer::measureSelection distance}
    ttk::button $window.structure.measure.angle -text {Angle (3 atoms)} -command {::GX::MoleculeViewer::measureSelection angle}
    ttk::button $window.structure.measure.dihedral -text {Dihedral (4 atoms)} -command {::GX::MoleculeViewer::measureSelection dihedral}
    pack $window.structure.measure.distance $window.structure.measure.angle $window.structure.measure.dihedral -side left -padx 4
    ttk::label $window.structure.report -textvariable ::GX::MoleculeViewer::report -anchor w -wraplength 990
    pack $window.structure.top -anchor w
    pack $window.structure.summary -fill x -pady 7
    pack $window.structure.panes -fill both -expand 1
    pack $window.structure.measure -anchor w -pady 8
    pack $window.structure.report -fill x -pady 5
    ttk::label $window.library.title -text {Installed CC0 wwPDB Chemical Component Dictionary examples}
    ttk::frame $window.library.listbox
    ttk::treeview $window.library.listbox.list -columns {id name} -show headings -height 15
    ttk::scrollbar $window.library.listbox.scroll -orient vertical -command [list $window.library.listbox.list yview]
    $window.library.listbox.list configure -yscrollcommand [list $window.library.listbox.scroll set]
    $window.library.listbox.list heading id -text {CCD ID}; $window.library.listbox.list column id -width 90 -stretch 0
    $window.library.listbox.list heading name -text {Molecule}; $window.library.listbox.list column name -width 700
    foreach row [libraryRows] {
        $window.library.listbox.list insert {} end -id [dict get $row id] -values [list [dict get $row id] [dict get $row name]]
    }
    pack $window.library.listbox.scroll -side right -fill y
    pack $window.library.listbox.list -side left -fill both -expand 1
    ttk::frame $window.library.actions
    ttk::label $window.library.actions.code -text {CCD ID}
    ttk::entry $window.library.actions.id -textvariable ::GX::MoleculeViewer::libraryId -width 10
    ttk::button $window.library.actions.install -text {Install selected in Session} -command ::GX::MoleculeViewer::guiInstall
    pack $window.library.actions.code $window.library.actions.id $window.library.actions.install -side left -padx 4
    ttk::separator $window.library.sep -orient horizontal
    ttk::frame $window.library.file
    ttk::label $window.library.file.label -text {Local SDF/MOL, XYZ or PDB}
    ttk::entry $window.library.file.path -textvariable ::GX::MoleculeViewer::localPath -width 65
    ttk::button $window.library.file.open -text {Browse / import} -command ::GX::MoleculeViewer::guiImport
    pack $window.library.file.label $window.library.file.path $window.library.file.open -side left -padx 4
    ttk::frame $window.library.online
    ttk::label $window.library.online.label -text {PubChem 3D lookup}
    ttk::combobox $window.library.online.kind -textvariable ::GX::MoleculeViewer::queryKind \
        -values {name cid smiles inchi inchikey} -state readonly -width 12
    ttk::entry $window.library.online.query -textvariable ::GX::MoleculeViewer::query -width 49
    ttk::button $window.library.online.lookup -text {Lookup and import} -command ::GX::MoleculeViewer::guiLookup
    pack $window.library.online.label $window.library.online.kind $window.library.online.query $window.library.online.lookup -side left -padx 4
    ttk::label $window.library.note -text {Library rights: CC0-1.0. PubChem online lookup records the exact CID, URL, retrieval date and source hash.} -wraplength 900
    pack $window.library.title -anchor w -pady 4
    pack $window.library.listbox -fill both -expand 1 -pady 4
    pack $window.library.actions -anchor w -pady 5
    pack $window.library.sep -fill x -pady 7
    pack $window.library.file $window.library.online -anchor w -pady 5
    pack $window.library.note -anchor w -pady 9
    ttk::label $window.source.title -text {Original source identity and Dataset provenance}
    text $window.source.text -wrap word -state disabled -height 30
    pack $window.source.title -anchor w -pady 5
    pack $window.source.text -fill both -expand 1
    bind $window.library.listbox.list <<TreeviewSelect>> {set ::GX::MoleculeViewer::libraryId [lindex [%W selection] 0]}
    bind $window.structure.top.dataset <<ComboboxSelected>> {::GX::MoleculeViewer::loadDataset $::GX::MoleculeViewer::selected}
    bind $window.structure.top.conformer <<ComboboxSelected>> {::GX::MoleculeViewer::showFrame}
    bind $window.structure.data.atoms <<TreeviewSelect>> {::GX::MoleculeViewer::showAtom}
    bind $window.structure.projbox.projection <Button-1> {::GX::MoleculeViewer::projectionClick %x %y}
    bind $window.structure.projbox.projection <Configure> {::GX::MoleculeViewer::drawProjection}
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    ::GX::Native3D::subscribeInteraction ::GX::MoleculeViewer::pick
    if {$selected ne ""} {loadDataset $selected} else {$window.tabs select $window.library}
    return $window
}
proc ::GX::MoleculeViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Molecule Viewer supports open and rerender"}
    return [open $scene]
}
::GX::viewerBackendRegister molecule_3d_tk ::GX::MoleculeViewer::viewerDispatch
