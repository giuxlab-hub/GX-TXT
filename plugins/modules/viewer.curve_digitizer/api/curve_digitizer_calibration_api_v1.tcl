# GX-TXT Curve Digitalizer Calibration Manifest API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Public contract: ::GX::CurveDigitizerCalibration::read $datasetId ?$session?
# The implementation intentionally uses only CORE's public Dataset Metadata and
# Session Inspection APIs. It does not open viewer configuration files.

namespace eval ::GX::CurveDigitizerCalibration {
    variable apiVersion 1
    variable metadataPrefix curve_digitizer.
}

proc ::GX::CurveDigitizerCalibration::_required {metadata key} {
    set k "curve_digitizer.$key"
    if {![dict exists $metadata $k]} { error "Dataset calibration metadata is missing '$k'." }
    return [dict get $metadata $k]
}

proc ::GX::CurveDigitizerCalibration::_finite {value label} {
    if {![string is double -strict $value] || ![expr {abs(double($value)) < Inf}]} {
        error "Invalid numeric value for calibration field '$label'."
    }
    return $value
}

proc ::GX::CurveDigitizerCalibration::_matrix {metadata prefix} {
    set matrix {}
    for {set i 0} {$i < 3} {incr i} {
        set row {}
        for {set j 0} {$j < 3} {incr j} {
            set k "curve_digitizer.transform.${prefix}h${i}${j}"
            if {![dict exists $metadata $k]} { error "Dataset calibration metadata is missing '$k'." }
            lappend row [_finite [dict get $metadata $k] $k]
        }
        lappend matrix $row
    }
    return $matrix
}

proc ::GX::CurveDigitizerCalibration::read {datasetId {session ""}} {
    set datasetId [string trim $datasetId]
    if {$datasetId eq ""} { error "Output Dataset ID must not be empty." }
    if {$session eq ""} { set session [::GX::sessionInspectionCurrentSession] }
    # Also validates existence; never treat an arbitrary metadata sidecar as a Dataset.
    ::GX::sessionInspectionDataset $datasetId $session
    set md [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $md curve_digitizer.plugin_id] ||
        [dict get $md curve_digitizer.plugin_id] ne "viewer.curve_digitizer"} {
        error "Dataset '$datasetId' was not published by GX-TXT Curve Digitalizer."
    }
    set version [_required $md manifest_version]
    if {$version ne "1"} { error "Unsupported Curve Digitalizer calibration manifest version '$version'." }
    set out [dict create api_version 1 manifest_version 1 dataset_id $datasetId]
    foreach key {source_dataset_id source_sha256 configuration_id calibration_type image_width image_height coordinate_origin y_direction physical_unit} {
        dict set out $key [_required $md $key]
    }
    foreach key {image_width image_height} {
        set n [dict get $out $key]
        if {![string is integer -strict $n] || $n < 2} { error "Invalid calibration image dimension '$key'." }
    }
    if {[dict get $out calibration_type] ni {pixel scale_bar affine projective}} {
        error "Invalid calibration type in Dataset metadata."
    }
    if {[dict get $out y_direction] ni {up down}} { error "Invalid calibration Y direction." }
    if {[dict get $out coordinate_origin] ni {top_left bottom_left}} { error "Invalid coordinate origin." }

    set transform [dict create \
        convention [_required $md transform.convention] \
        raster_origin [_required $md transform.raster_origin] \
        pixel_reference [_required $md transform.pixel_reference] \
        normalized_coordinates x_left_to_right_y_bottom_to_top \
        normalized_homography [_matrix $md ""]]
    foreach axis {x y} {
        set spec [dict create]
        foreach name {minimum maximum scale unit} {
            set k "transform.${axis}_${name}"
            set v [_required $md $k]
            if {$name in {minimum maximum}} { _finite $v $k }
            dict set spec $name $v
        }
        if {[dict get $spec scale] ni {linear log}} { error "Invalid scientific axis mapping." }
        dict set transform ${axis}_axis $spec
    }
    if {[dict exists $md curve_digitizer.transform.scientific_h00]} {
        dict set transform scientific_homography [_matrix $md scientific_]
    }
    dict set out transform $transform

    if {[dict get $out calibration_type] eq "scale_bar"} {
        set b [dict create]
        foreach name {pixel_length physical_length unit display_unit selection_method} {
            set value [_required $md scale_bar.$name]
            if {$name in {pixel_length physical_length}} {
                _finite $value scale_bar.$name
                if {$value <= 0} { error "Scale bar length must be positive." }
            }
            dict set b $name $value
        }
        foreach end {start end} {
            set pt {}
            foreach axis {x y} {
                set k "scale_bar.${end}_${axis}"
                lappend pt [_finite [_required $md $k] $k]
            }
            dict set b ${end}_px $pt
        }
        # Additive optional field: pre-1.2.6 publications have no documented
        # tick convention and must not silently be reinterpreted as center.
        set convention unspecified
        if {[dict exists $md curve_digitizer.scale_bar.edge_convention]} {
            set convention [dict get $md curve_digitizer.scale_bar.edge_convention]
            if {$convention ni {center inner outer unspecified}} {
                error "Unknown scale-bar tick-edge convention."
            }
        }
        dict set b edge_convention $convention
        dict set out scale_bar $b
    }
    if {[dict exists $md curve_digitizer.uncertainty]} {
        set u [dict create]
        dict for {k v} $md {
            if {[string match {curve_digitizer.uncertainty.*} $k]} {
                dict set u [string range $k [string length {curve_digitizer.uncertainty.}] end] $v
            }
        }
        if {[dict size $u]} { dict set out uncertainty $u }
        # Raw canonical JSON remains available for nonflat uncertainty payloads.
        dict set out uncertainty_json [dict get $md curve_digitizer.uncertainty]
    }
    if {[dict exists $md curve_digitizer.calibration_id] &&
        [dict exists $md curve_digitizer.calibration_sha256]} {
        set digest [string tolower [dict get $md curve_digitizer.calibration_sha256]]
        set calibrationId [dict get $md curve_digitizer.calibration_id]
        if {![regexp {^[0-9a-f]{64}$} $digest] ||
            $calibrationId ne "cal_[string range $digest 0 23]"} {
            error "Invalid calibration SHA-256 or stable ID."
        }
        dict set out calibration_id $calibrationId
        dict set out calibration_sha256 $digest
    }
    if {[dict exists $md curve_digitizer.raster_geometry]} {
        dict set out raster_geometry_json [dict get $md curve_digitizer.raster_geometry]
    }
    if {[dict exists $md curve_digitizer.raster_geometry.source_to_calibration]} {
        set pixelMapping [dict get $md curve_digitizer.raster_geometry.source_to_calibration]
        if {$pixelMapping ne "identity"} {
            error "Unsupported source-image-to-calibration pixel mapping '$pixelMapping'."
        }
        dict set out raster_pixel_mapping $pixelMapping
    } else {
        dict set out raster_pixel_mapping legacy_unrecorded
    }
    if {[dict exists $md curve_digitizer.calibration_method]} {
        dict set out calibration_method_json [dict get $md curve_digitizer.calibration_method]
        set method [dict create]
        foreach key {type point_selection tick_reference measurement_uncertainty} {
            if {[dict exists $md curve_digitizer.calibration_method.$key]} {
                dict set method $key [dict get $md curve_digitizer.calibration_method.$key]
            }
        }
        dict set out calibration_method $method
    }
    return $out
}

proc ::GX::CurveDigitizerCalibration::hasCalibration {datasetId {session ""}} {
    if {$session eq ""} { set session [::GX::sessionInspectionCurrentSession] }
    if {[catch {set md [::GX::datasetMetadataRead $session $datasetId]}]} { return 0 }
    return [expr {[dict exists $md curve_digitizer.plugin_id] &&
                  [dict get $md curve_digitizer.plugin_id] eq "viewer.curve_digitizer" &&
                  [dict exists $md curve_digitizer.manifest_version] &&
                  [dict get $md curve_digitizer.manifest_version] eq "1"}]
}

proc ::GX::CurveDigitizerCalibration::schema {} {
    return [dict create api_id CURVE_DIGITIZER_CALIBRATION_API_v1 api_version 1 \
        methods {read hasCalibration schema} \
        required_fields {source_dataset_id source_sha256 configuration_id calibration_type image_width image_height coordinate_origin y_direction physical_unit transform} \
        calibration_types {pixel scale_bar affine projective} \
        coordinate_units {pixel_center}]
}


# Calibration math is supplied by the producer, not reimplemented by consumers.
# Coordinate input/output: Tcl list of {x y} numeric pairs; atomic failure.
proc ::GX::CurveDigitizerCalibration::_matrixApply {h x y} {
    lassign [lindex $h 0] a b c
    lassign [lindex $h 1] d e f
    lassign [lindex $h 2] g k i
    set divisor [expr {double($g)*$x+double($k)*$y+double($i)}]
    if {![expr {abs($divisor)<Inf}] || abs($divisor) < 1e-12} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION SINGULAR} \
            "The calibration is singular at the requested point."
    }
    set u [expr {(double($a)*$x+double($b)*$y+double($c))/$divisor}]
    set v [expr {(double($d)*$x+double($e)*$y+double($f))/$divisor}]
    if {![expr {abs($u)<Inf && abs($v)<Inf}]} {error "Transformation produced non-finite coordinates."}
    return [list $u $v]
}

proc ::GX::CurveDigitizerCalibration::_inverse3 {m} {
    lassign [lindex $m 0] a b c
    lassign [lindex $m 1] d e f
    lassign [lindex $m 2] g h i
    set A [expr {$e*$i-$f*$h}]
    set B [expr {$c*$h-$b*$i}]
    set C [expr {$b*$f-$c*$e}]
    set D [expr {$f*$g-$d*$i}]
    set E [expr {$a*$i-$c*$g}]
    set F [expr {$c*$d-$a*$f}]
    set G [expr {$d*$h-$e*$g}]
    set H [expr {$b*$g-$a*$h}]
    set I [expr {$a*$e-$b*$d}]
    set det [expr {double($a)*$A+double($b)*$D+double($c)*$G}]
    if {![expr {abs($det)<Inf}] || abs($det) < 1e-14} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION SINGULAR} \
            "The calibration homography is not invertible."
    }
    return [list [list [expr {$A/$det}] [expr {$B/$det}] [expr {$C/$det}]] \
                 [list [expr {$D/$det}] [expr {$E/$det}] [expr {$F/$det}]] \
                 [list [expr {$G/$det}] [expr {$H/$det}] [expr {$I/$det}]]]
}

proc ::GX::CurveDigitizerCalibration::_axisForward {axis t} {
    set lo [expr {double([dict get $axis minimum])}]
    set hi [expr {double([dict get $axis maximum])}]
    if {[dict get $axis scale] eq "linear"} {
        return [expr {$lo+$t*($hi-$lo)}]
    }
    if {$lo<=0 || $hi<=0} {error "Logarithmic axis bounds must be positive."}
    set value [expr {exp(log($lo)+$t*(log($hi)-log($lo)))}]
    if {![expr {abs($value)<Inf}]} {error "Non-finite logarithmic axis coordinate."}
    return $value
}

proc ::GX::CurveDigitizerCalibration::_axisInverse {axis value} {
    set lo [expr {double([dict get $axis minimum])}]
    set hi [expr {double([dict get $axis maximum])}]
    if {$lo==$hi} {error "Scientific axis has zero range."}
    if {[dict get $axis scale] eq "linear"} {
        return [expr {(double($value)-$lo)/($hi-$lo)}]
    }
    if {$lo<=0 || $hi<=0 || $value<=0} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN} \
            "Non-positive coordinate on a logarithmic axis."
    }
    return [expr {(log(double($value))-log($lo))/(log($hi)-log($lo))}]
}

proc ::GX::CurveDigitizerCalibration::_checkUnitDomain {value} {
    if {![expr {abs(double($value))<Inf}] || $value < -1e-8 || $value > 1.00000001} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN} \
            "Point lies outside the calibrated raster domain."
    }
}

proc ::GX::CurveDigitizerCalibration::_transformOne {manifest point direction} {
    if {[llength $point]!=2} {error "Each point must be a pair {x y}."}
    lassign $point x y
    set x [_finite $x point_x]; set y [_finite $y point_y]
    set t [dict get $manifest transform]
    set h [dict get $t normalized_homography]
    if {$direction eq "pixel_to_scientific"} {
        if {$x < -1e-8 || $y < -1e-8 ||
            $x > [dict get $manifest image_width]-1+1e-8 ||
            $y > [dict get $manifest image_height]-1+1e-8} {
            return -code error -errorcode {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN} \
                "Raster pixel coordinate is outside the original Image Dataset."
        }
        lassign [_matrixApply $h $x $y] u v
        _checkUnitDomain $u; _checkUnitDomain $v
        return [list [_axisForward [dict get $t x_axis] $u] \
                     [_axisForward [dict get $t y_axis] $v]]
    }
    set u [_axisInverse [dict get $t x_axis] $x]
    set v [_axisInverse [dict get $t y_axis] $y]
    _checkUnitDomain $u; _checkUnitDomain $v
    lassign [_matrixApply [_inverse3 $h] $u $v] px py
    if {$px < -1e-7 || $py < -1e-7 ||
        $px > [dict get $manifest image_width]-1+1e-7 ||
        $py > [dict get $manifest image_height]-1+1e-7} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN} \
            "Inverse coordinate is outside the original Image Dataset."
    }
    return [list $px $py]
}

# Calibration realizations are published Dataset metadata, not private
# Interactive Document state. Never interpret column names or parse sidecars.
proc ::GX::CurveDigitizerCalibration::replicates {datasetId} {
    set base [read $datasetId]
    set session [::GX::sessionInspectionCurrentSession]
    set md [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $md curve_digitizer.measurement_count]} {
        # Historical Dataset: its one published calibration is still usable.
        return [list [dict merge $base [dict create measurement_id legacy_active \
            active 1 state accepted valid 1 label {Published calibration}]]]
    }
    set count [dict get $md curve_digitizer.measurement_count]
    if {![string is integer -strict $count] || $count<1 || $count>200} {
        error {Invalid published calibration measurement count.}
    }
    set items {}
    set names {}
    set activeCount 0
    for {set n 0} {$n<$count} {incr n} {
        set prefix "curve_digitizer.measurement.${n}."
        set m [dict create]
        foreach key {measurement_id label state active valid} {
            if {![dict exists $md ${prefix}${key}]} {error "Missing calibration measurement $n field $key."}
            dict set m $key [dict get $md ${prefix}${key}]
        }
        foreach field {corners_px axes scale_reference} {
            if {[dict exists $md ${prefix}$field]} {
                dict set m ${field}_json [dict get $md ${prefix}$field]
            }
        }
        set mid [dict get $m measurement_id]
        if {$mid in $names} {error {Duplicate calibration measurement ID.}}
        lappend names $mid
        if {[dict get $m state] ni {accepted rejected draft} ||
            [dict get $m active] ni {0 1} || [dict get $m valid] ni {0 1}} {
            error {Invalid calibration measurement state.}
        }
        if {[dict get $m active]} {incr activeCount}
        if {[dict get $m valid]} {
            foreach key {calibration_id calibration_sha256 calibration_type} {
                if {![dict exists $md ${prefix}${key}]} {error "Missing calibration measurement $n $key."}
                dict set m $key [dict get $md ${prefix}${key}]
            }
            set sha [dict get $m calibration_sha256]
            if {![regexp {^[a-f0-9]{64}$} $sha] ||
                [dict get $m calibration_id] ne "cal_[string range $sha 0 23]"} {
                error {Invalid calibration measurement fingerprint.}
            }
            set transform [dict get $base transform]
            set H {}
            for {set a 0} {$a<3} {incr a} {
                set row {}
                for {set b 0} {$b<3} {incr b} {
                    set key "${prefix}transform.h${a}${b}"
                    if {![dict exists $md $key]} {error "Missing $key."}
                    lappend row [_finite [dict get $md $key] $key]
                }
                lappend H $row
            }
            dict set transform normalized_homography $H
            dict unset transform scientific_homography
            foreach axis {x y} {
                set spec [dict create]
                foreach key {minimum maximum scale unit} {
                    set full "${prefix}transform.${axis}_${key}"
                    if {![dict exists $md $full]} {error "Missing $full."}
                    set value [dict get $md $full]
                    if {$key in {minimum maximum}} {_finite $value $full}
                    dict set spec $key $value
                }
                if {[dict get $spec scale] ni {linear log}} {error {Invalid calibration axis scale.}}
                dict set transform ${axis}_axis $spec
            }
            dict set m transform $transform
        }
        lappend items $m
    }
    if {$activeCount != 1} {error {Exactly one active calibration measurement is required.}}
    return $items
}

proc ::GX::CurveDigitizerCalibration::_forMeasurement {datasetId measurementId} {
    set base [read $datasetId]
    if {$measurementId eq {}} {return $base}
    foreach item [replicates $datasetId] {
        if {[dict get $item measurement_id] ne $measurementId} continue
        if {![dict get $item valid]} {
            return -code error -errorcode {CURVE_DIGITIZER CALIBRATION INVALID_MEASUREMENT} \
                "Calibration measurement '$measurementId' is incomplete or invalid."
        }
        dict set base transform [dict get $item transform]
        dict set base calibration_type [dict get $item calibration_type]
        set xUnit [dict get $item transform x_axis unit]
        set yUnit [dict get $item transform y_axis unit]
        dict set base physical_unit [expr {$xUnit eq $yUnit && $xUnit ne {px} ? $xUnit : {}}]
        set axis [dict get $item transform y_axis]
        set descending [expr {[dict get $axis minimum] > [dict get $axis maximum]}]
        dict set base y_direction [expr {$descending ? "down" : "up"}]
        dict set base coordinate_origin [expr {$descending ? "top_left" : "bottom_left"}]
        dict set base calibration_id [dict get $item calibration_id]
        dict set base calibration_sha256 [dict get $item calibration_sha256]
        dict set base measurement_id $measurementId
        return $base
    }
    return -code error -errorcode {CURVE_DIGITIZER CALIBRATION UNKNOWN_MEASUREMENT} \
        "Unknown calibration measurement '$measurementId'."
}

proc ::GX::CurveDigitizerCalibration::transformPoints {datasetId points direction {measurementId ""}} {
    if {$direction ni {pixel_to_scientific scientific_to_pixel}} {
        error "Direction must be pixel_to_scientific or scientific_to_pixel."
    }
    set manifest [_forMeasurement $datasetId $measurementId]
    if {[dict get $manifest raster_pixel_mapping] ni {identity legacy_unrecorded}} {
        error "Unsupported upstream pixel geometry."
    }
    set result {}
    foreach point $points {lappend result [_transformOne $manifest $point $direction]}
    return $result
}

proc ::GX::CurveDigitizerCalibration::identity {datasetId {measurementId ""}} {
    set cal [_forMeasurement $datasetId $measurementId]
    if {![dict exists $cal calibration_sha256]} {
        return [dict create available 0 reason legacy_fingerprint_unavailable dataset_id $datasetId]
    }
    return [dict create available 1 calibration_id [dict get $cal calibration_id] \
        sha256 [dict get $cal calibration_sha256] \
        source_sha256 [dict get $cal source_sha256]]
}

proc ::GX::CurveDigitizerCalibration::_jacobianOne {cal point} {
    if {[llength $point]!=2} {error "Each point must be a pair {x y}."}
    lassign $point x y
    set x [_finite $x point_x];set y [_finite $y point_y]
    # Central-domain/singularity checks and scientific coordinates use the same
    # validation routine exposed by transformPoints.
    lassign [_transformOne $cal $point pixel_to_scientific] sx sy
    set t [dict get $cal transform]
    set h [dict get $t normalized_homography]
    lassign [lindex $h 0] a b c
    lassign [lindex $h 1] d e f
    lassign [lindex $h 2] g k i
    set den [expr {double($g)*$x+double($k)*$y+double($i)}]
    lassign [_matrixApply $h $x $y] u v
    set du_dx [expr {($a-$u*$g)/$den}]
    set du_dy [expr {($b-$u*$k)/$den}]
    set dv_dx [expr {($d-$v*$g)/$den}]
    set dv_dy [expr {($e-$v*$k)/$den}]
    set ax [dict get $t x_axis]
    set ay [dict get $t y_axis]
    set fx [expr {[dict get $ax scale] eq "linear" ? \
        double([dict get $ax maximum])-double([dict get $ax minimum]) : \
        $sx*log(double([dict get $ax maximum])/double([dict get $ax minimum]))}]
    set fy [expr {[dict get $ay scale] eq "linear" ? \
        double([dict get $ay maximum])-double([dict get $ay minimum]) : \
        $sy*log(double([dict get $ay maximum])/double([dict get $ay minimum]))}]
    set j [list [list [expr {$fx*$du_dx}] [expr {$fx*$du_dy}]] \
                [list [expr {$fy*$dv_dx}] [expr {$fy*$dv_dy}]]]
    set determinant [expr {[lindex $j 0 0]*[lindex $j 1 1]-[lindex $j 0 1]*[lindex $j 1 0]}]
    if {![expr {abs($determinant)<Inf}] || abs($determinant)<1e-14} {
        return -code error -errorcode {CURVE_DIGITIZER CALIBRATION SINGULAR} \
            "Local calibration Jacobian is singular."
    }
    return [dict create valid 1 point_px $point scientific_point [list $sx $sy] \
        jacobian $j determinant $determinant]
}

proc ::GX::CurveDigitizerCalibration::jacobian {datasetId points} {
    set cal [read $datasetId]
    set out {}
    foreach point $points {lappend out [_jacobianOne $cal $point]}
    return $out
}

proc ::GX::CurveDigitizerCalibration::pointUncertainty {datasetId points} {
    set cal [read $datasetId]
    set out {}
    # Not knowing a per-point or calibration uncertainty is not zero error.
    set sigma ""
    if {[dict exists $cal uncertainty pixel_sigma_px]} {
        set sigma [_finite [dict get $cal uncertainty pixel_sigma_px] uncertainty.pixel_sigma_px]
        if {$sigma<0} {error "Pixel coordinate uncertainty cannot be negative."}
    }
    foreach point $points {
        set local [_jacobianOne $cal $point]
        if {$sigma eq ""} {
            lappend out [dict create status unavailable reason no_quantified_uncertainty \
                point_px $point local_valid 1]
            continue
        }
        set j [dict get $local jacobian]
        set sx [expr {$sigma*hypot([lindex $j 0 0],[lindex $j 0 1])}]
        set sy [expr {$sigma*hypot([lindex $j 1 0],[lindex $j 1 1])}]
        lappend out [dict create status reported_and_propagated input_pixel_sigma_px $sigma \
            output_sigma_x $sx output_sigma_y $sy \
            assumption isotropic_independent_pixel_errors \
            note {Does not include unknown systematic calibration uncertainty.}]
    }
    return $out
}

# Preserve ABI: schema/hasCalibration/read remain stable, new methods additive.
rename ::GX::CurveDigitizerCalibration::schema ::GX::CurveDigitizerCalibration::_schema_before_batch
proc ::GX::CurveDigitizerCalibration::schema {} {
    set base [_schema_before_batch]
    dict set base methods {read hasCalibration schema transformPoints identity jacobian pointUncertainty replicates}
    dict set base point_structure {list_of_2_numeric_coordinates}
    dict set base supported_directions {pixel_to_scientific scientific_to_pixel}
    dict set base measurement_selection {optional_stable_measurement_id_or_active_default}
    dict set base fingerprint {sha256_of_source_raster_and_calibration_mapping}
    return $base
}
