# GX-TXT Spectral Family API v1: one parameterized collection of real spectra.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectralFamilyAPIv1 { variable apiVersion 1 }

proc ::GX::SpectralFamilyAPIv1::apiInfo {} {
    return [dict create api_name SPECTRAL_FAMILY_API_v1 api_version 1 contract spectrum.family]
}

proc ::GX::SpectralFamilyAPIv1::create {parameterQuantity parameterUnit members} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $parameterQuantity]} {
        error "Spectral Family API v1: invalid parameter quantity"
    }
    if {[string trim $parameterUnit] eq ""} {error "Spectral Family API v1: parameter unit is required"}
    if {[llength $members] < 2} {error "Spectral Family API v1: at least two member spectra are required"}
    set seen [dict create]
    set normalized {}
    set semantics ""
    foreach member $members {
        if {[catch {dict size $member}]} {error "Spectral Family API v1: member must be a dict"}
        foreach key {member_id parameter_value spectrum} {
            if {![dict exists $member $key]} {error "Spectral Family API v1: member missing $key"}
        }
        set id [dict get $member member_id]
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id] || [dict exists $seen $id]} {
            error "Spectral Family API v1: invalid or duplicate member ID '$id'"
        }
        dict set seen $id 1
        set value [dict get $member parameter_value]
        if {![string is double -strict $value] || [regexp -nocase {nan|inf} $value]} {
            error "Spectral Family API v1: member $id has non-finite parameter"
        }
        set spectrum [dict get $member spectrum]
        ::GX::SpectrumAPIv1::validate $spectrum
        set current [list {*}[lmap key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {dict get $spectrum $key}]]
        if {$semantics eq ""} {set semantics $current}
        if {$semantics ne $current} {error "Spectral Family API v1: member $id has incompatible spectral semantics"}
        lappend normalized [dict create member_id $id parameter_value [expr {double($value)}] spectrum $spectrum \
            source_dataset_id [expr {[dict exists $member source_dataset_id] ? [dict get $member source_dataset_id] : ""}]]
    }
    return [dict create contract spectrum.family parameter_quantity $parameterQuantity \
        parameter_unit $parameterUnit members $normalized member_count [llength $normalized] \
        spectrum_kind [lindex $semantics 0] x_quantity [lindex $semantics 1] \
        x_unit [lindex $semantics 2] y_quantity [lindex $semantics 3] \
        y_representation [lindex $semantics 4] y_unit [lindex $semantics 5]]
}

proc ::GX::SpectralFamilyAPIv1::publishSession {session datasetId family} {
    if {![dict exists $family contract] || [dict get $family contract] ne "spectrum.family"} {
        error "Spectral Family API v1: invalid family"
    }
    set family [create [dict get $family parameter_quantity] [dict get $family parameter_unit] [dict get $family members]]
    set sourceIds {}
    set columns [dict create member_id {} parameter_value {} spectral_x {} spectral_y {}]
    foreach member [dict get $family members] {
        set sourceId [dict get $member source_dataset_id]
        if {$sourceId ne "" && [lsearch -exact $sourceIds $sourceId] < 0} {lappend sourceIds $sourceId}
        set spec [dict get $member spectrum]
        foreach x [dict get $spec x] y [dict get $spec y] {
            dict lappend columns member_id [dict get $member member_id]
            dict lappend columns parameter_value [dict get $member parameter_value]
            dict lappend columns spectral_x $x
            dict lappend columns spectral_y $y
        }
    }
    set provenance [dict create family_member_count [dict get $family member_count] \
        parameter_quantity [dict get $family parameter_quantity] parameter_unit [dict get $family parameter_unit] \
        spectrum_kind [dict get $family spectrum_kind] y_representation [dict get $family y_representation] \
        source_dataset_ids $sourceIds]
    set definition [dict create dataset_id $datasetId contract spectrum.family storage auto \
        producer_version 1.0.0 source_dataset_ids $sourceIds source_variable_ids {} \
        source [join $sourceIds {;}] provenance $provenance \
        notes {Parameterized Spectral Family; each complete measured spectrum remains an independent source Dataset.} \
        replace_owned 0]
    set plan [::GX::datasetPublicationV2Prepare $session core.spectral_family $definition]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach {id schema} [list \
            member_id [dict create name {Member ID} dtype string dimension_ids row semantic_role member_identity] \
            parameter_value [dict create name [dict get $family parameter_quantity] dtype float64 dimension_ids row unit [dict get $family parameter_unit] semantic_role parameter] \
            spectral_x [dict create name [dict get $family x_quantity] dtype float64 dimension_ids row unit [dict get $family x_unit] semantic_role independent coordinate_role coordinate] \
            spectral_y [dict create name [dict get $family y_quantity] dtype float64 dimension_ids row unit [dict get $family y_unit] semantic_role measured coordinate_variable_ids spectral_x]] {
            ::GX::datasetPublicationV2DeclareVariable $writer $id $schema
        }
        set count [::GX::datasetPublicationV2Append $writer row $columns]
        if {$count != [llength [dict get $columns member_id]]} {error "Spectral Family API v1: incomplete Dataset write"}
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}

proc ::GX::SpectralFamilyAPIv1::readSession {session datasetId} {
    set handle [::GX::datasetAccessOpen $session $datasetId]
    try {
        set metadata [::GX::datasetAccessMetadata $handle]
        if {[dict get $metadata contract] ne "spectrum.family"} {error "Spectral Family API v1: Dataset has wrong contract"}
        set values [::GX::datasetAccessReadVariables $handle {member_id parameter_value spectral_x spectral_y}]
        set ids [dict get $values member_id values]
        set parameters [dict get $values parameter_value values]
        set xx [dict get $values spectral_x values]
        set yy [dict get $values spectral_y values]
        if {[llength $ids] != [llength $parameters] || [llength $ids] != [llength $xx] || [llength $ids] != [llength $yy]} {
            error "Spectral Family API v1: canonical columns have different lengths"
        }
        set members [dict create]
        set order {}
        foreach id $ids parameter $parameters x $xx y $yy {
            if {![dict exists $members $id]} {
                dict set members $id [dict create member_id $id parameter_value $parameter x {} y {}]
                lappend order $id
            }
            if {[dict get $members $id parameter_value] != $parameter} {error "Spectral Family API v1: member parameter changed within its spectrum"}
            set member [dict get $members $id]
            dict lappend member x $x
            dict lappend member y $y
            dict set members $id $member
        }
        set result {}
        foreach id $order {
            set member [dict get $members $id]
            set x [dict get $member x]
            set direction 0
            for {set i 1} {$i < [llength $x]} {incr i} {
                set step [expr {[lindex $x $i] > [lindex $x [expr {$i-1}]] ? 1 : -1}]
                if {[lindex $x $i] == [lindex $x [expr {$i-1}]] || ($direction && $step != $direction)} {
                    error "Spectral Family API v1: member $id X is not strictly monotonic"
                }
                set direction $step
            }
            lappend result $member
        }
        return [dict create contract spectrum.family members $result member_count [llength $result] dataset_id $datasetId]
    } finally {::GX::datasetAccessClose $handle}
}

proc ::GX::SpectralFamilyAPIv1::responseAt {family selectedX} {
    if {![string is double -strict $selectedX] || [regexp -nocase {nan|inf} $selectedX]} {
        error "Spectral Family API v1: selected coordinate must be finite"
    }
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set out {}
    foreach member [dict get $family members] {
        if {[dict exists $member x] && [dict exists $member y]} {
            set x [dict get $member x]
            set y [dict get $member y]
        } elseif {[dict exists $member spectrum]} {
            set x [dict get $member spectrum x]
            set y [dict get $member spectrum y]
        } else {
            error "Spectral Family API v1: member has no spectral samples"
        }
        if {[lindex $x 0] > [lindex $x end]} {set x [lreverse $x]; set y [lreverse $y]}
        set result [::GX::NumericAPIv1::interpolate $x $y [list $selectedX] [dict create method linear extrapolation error]]
        lappend out [dict create member_id [dict get $member member_id] parameter_value [dict get $member parameter_value] \
            selected_x $selectedX response [lindex [dict get $result yq] 0]]
    }
    return $out
}
