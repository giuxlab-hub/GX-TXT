# Genuine Native3D geometry and persistent representations. The existing CORE
# Viewer Scene/Layer and Interactive Document stores own all durable identity.
proc ::GX::PlotDatasetAPIv4::_3dReady {} {
    _ready
    if {![::GX::moduleIsEnabled viewer.native_3d]} {::GX::moduleSetEnabled viewer.native_3d 1}
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    if {![llength [info commands ::GX::Native3D::plotV4Geometry]]} {set path [file join $::GX::scriptDir core native3d bin libgx3de_plot_v4.so];if {[info exists ::env(GX3D_PLOT_V4_LIBRARY)]} {set path $::env(GX3D_PLOT_V4_LIBRARY)};load $path Gx3deplotv4}
}
proc ::GX::PlotDatasetAPIv4::_3dGeometry {spec directory} {
    _3dReady;validateSpec $spec;file mkdir $directory
    set dataset [dict get $spec dataset_id];set ids {};foreach role {x y z family color} {set id [_get $spec ${role}_variable_id {}];if {$id ne {}} {dict set ids $role $id}}
    if {[dict exists $ids color]&&[_get [_get $spec config {}] plot_type line3] in {line3 contour3}} {error {Color C is not supported by line3 or contour3; clear the binding or choose another scientific kind}}
    set path [file join $directory .xyz_source_[pid].tsv];set fd [open $path w];fconfigure $fd -encoding utf-8 -translation lf
    set context [::GX::datasetCoordinateRead $::GX::currentSession $dataset];set np [_get $spec native_presentation {}];set graphics [_get $np graphics {}];set effectiveConfig [dict merge [_get $spec config {}] [_get $np plot_config {}]];dict set spec config $effectiveConfig;set zLevel [_get [_get $np axes {}] z_level_scale [::GX::levelScaleDefaults]];set stream {};set position 0
    set canonicalGrid [expr {[dict get [::GX::datasetVariableV3ById $dataset [dict get $ids z]] rank]==2}]
    if {!$canonicalGrid} {set stream [::GX::tableStreamOpenDataset $::GX::currentSession $dataset [lsort -unique [dict values $ids]] 4096 {numeric_transport values}]}
    try {
        if {$canonicalGrid} {_3dCanonicalGridWrite $spec $ids $context $graphics $fd} else {
        while {1} {
            set chunk [::GX::tableStreamNext $stream];set columns [dict get $chunk values];set n [dict get $chunk row_count]
            set colorId [_get $ids color [dict get $ids z]];set target [_get $graphics color_unit auto]
            if {$target in {auto inherit {}}} {set target [expr {[dict exists $ids color]?{source}:[_get [_get [_get $spec axes {}] z {}] display_unit source]}]}
            set finite {};set indices {};set i 0;foreach value [dict get $columns $colorId] {if {[string is double -strict $value]&&[expr {abs($value)<Inf}]} {lappend finite $value;lappend indices $i};incr i}
            set colorValues [lrepeat $n NaN];foreach i $indices value [_coordinate $context $colorId $finite $target] {lset colorValues $i $value}
            foreach axis {x y z} {
                set target [_get [_get [_get $spec axes {}] $axis {}] display_unit source]
                set original [dict get $columns [dict get $ids $axis]];set finite {};set indices {};set i 0
                foreach value $original {if {[string is double -strict $value]&&[expr {abs($value)<Inf}]} {lappend finite $value;lappend indices $i};incr i}
                set converted [_coordinate $context [dict get $ids $axis] $finite $target];if {$axis eq {z}} {set converted [_levelValues $context [dict get $ids z] $converted $target $zLevel]};set result [lrepeat $n NaN];foreach i $indices value $converted {lset result $i $value};dict set columns [dict get $ids $axis] $result
            }
            for {set i 0} {$i<$n} {incr i} {
                set values {};foreach axis {x y z} {lappend values [lindex [dict get $columns [dict get $ids $axis]] $i]}
                set family _;if {[dict exists $ids family]} {set family [lindex [dict get $columns [dict get $ids family]] $i];if {$family ne {}} {set family [::GX::graphSeriesCanonicalMember [dict get [::GX::datasetVariableV3ById $dataset [dict get $ids family]] dtype] $family]};if {$family eq {}} {set family _missing;set values {NaN NaN NaN}}}
                set color [lindex $colorValues $i]
                foreach value [concat $values [list $color]] {if {![string is double -strict $value]} {set value NaN}}
                puts $fd [join [concat [list [expr {$position+$i}]] $values [list [binary encode base64 -maxlen 0 [encoding convertto utf-8 $family]] $color]] \t]
            }
            incr position $n;if {[dict get $chunk eof]} break
        }
        }
        close $fd;set fd {}
        set config [_get $spec config {}]
        set request [dict merge $config [dict create kind [_get $config plot_type line3] input $path]]
        dict set request palette [_palette [_get $graphics colormap viridis]];foreach key {color_min color_max} {if {[_get $graphics $key {}] ne {}} {dict set request $key [dict get $graphics $key]}}
        foreach axis {x y z} {dict set request ${axis}_scale [_get [_get [_get $spec axes {}] $axis {}] scale linear]}
        set result [::GX::Native3D::plotV4Geometry $request $directory];set layers {};foreach item [dict get $result layers] {dict set item family_identity [encoding convertfrom utf-8 [binary decode base64 [dict get $item family_identity]]];lappend layers $item};dict set result layers $layers;return $result
    } finally {if {$fd ne {}} {close $fd};if {$stream ne {}} {::GX::tableStreamClose $stream};file delete -- $path}
}
# Match the accepted canonical Y/X grid contract exactly. Public Dataset Access
# supplies typed bounded hyperslabs; the logical identity remains column-major
# y+x*ny even though the provider transports each slab in C order.
proc ::GX::PlotDatasetAPIv4::_gridValues {handle id starts counts context target} {
    set block [::GX::datasetAccessReadHyperslab $handle $id $starts $counts]
    set values [dict get $block values]
    foreach v $values {
        if {![string is double -strict $v]||![expr {abs($v)<Inf}]} {error {Canonical grid contains a nonfinite coordinate or cell; no hole filling is performed}}
        if {[dict get $block dtype] in {int64 uint64}&&($v>9007199254740992||$v< -9007199254740992)} {error {Canonical grid coordinate cannot be narrowed exactly to native display precision}}
    }
    return [_coordinate $context $id $values $target]
}
proc ::GX::PlotDatasetAPIv4::_3dCanonicalGridWrite {spec ids context graphics fd} {
    set dataset [dict get $spec dataset_id]
    if {[dict exists $ids family]} {error {A rank-two canonical grid has one surface; publish separate grids for families}}
    set config [_get $spec config {}]
    if {[_get $config plot_type surface] ni {surface mesh contour3 heatmap}} {error {Canonical rank-two grids require a gridded scientific plot kind}}
    if {[_get $config reduction_mode auto] eq {minmax}} {error {Canonical grids do not move cell values to different physical coordinates for display reduction}}
    set before [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]
    set h [::GX::datasetAccessOpen $::GX::currentSession $dataset]
    try {
        set variables {};foreach v [dict get [::GX::datasetAccessMetadata $h] variables] {dict set variables [dict get $v variable_id] $v}
        foreach axis {x y z} {set meta($axis) [dict get $variables [dict get $ids $axis]];set shape($axis) [::GX::datasetSchemaV3SplitIds [dict get $meta($axis) shape]]}
        if {[llength $shape(x)]!=1||[llength $shape(y)]!=1||[llength $shape(z)]!=2||$shape(z) ne [list {*}$shape(y) {*}$shape(x)]||[dict get $meta(x) dimension_ids] eq [dict get $meta(y) dimension_ids]||[::GX::datasetSchemaV3SplitIds [dict get $meta(z) dimension_ids]] ne [list {*}[::GX::datasetSchemaV3SplitIds [dict get $meta(y) dimension_ids]] {*}[::GX::datasetSchemaV3SplitIds [dict get $meta(x) dimension_ids]]]} {error {Canonical Z must have the exact Y/X axis dimensions; no transposition is inferred}}
        set nx [lindex $shape(x) 0];set ny [lindex $shape(y) 0]
        if {$nx<2||$ny<2||$nx>100000||$ny>100000||$nx*$ny>100000000} {error {Canonical grid exceeds the public scientific geometry limits}}
        foreach axis {x y} {
            set values {};set target [_get [_get [_get $spec axes {}] $axis {}] display_unit source]
            for {set start 0} {$start<[set n [expr {$axis eq {x}?$nx:$ny}]]} {incr start 4096} {lappend values {*}[_gridValues $h [dict get $ids $axis] [list $start] [list [expr {min(4096,$n-$start)}]] $context $target]}
            set sign 0;set prior [lindex $values 0];foreach v [lrange $values 1 end] {set d [expr {$v>$prior?1:$v<$prior?-1:0}];if {!$d||($sign&&$sign!=$d)} {error {Canonical grid axes must be strictly monotonic; no sorting is inferred}};set sign $d;set prior $v};set coordinates($axis) $values
        }
        set colorId [_get $ids color [dict get $ids z]]
        if {[dict exists $ids color]} {set c [dict get $variables $colorId];if {[::GX::datasetSchemaV3SplitIds [dict get $c shape]] ne $shape(z)||[dict get $c dimension_ids] ne [dict get $meta(z) dimension_ids]} {error {Canonical color must share the exact Z dimensions}}}
        set zTarget [_get [_get [_get $spec axes {}] z {}] display_unit source];set cTarget [_get $graphics color_unit source];if {$cTarget in {auto inherit {}}} {set cTarget [expr {[dict exists $ids color]?{source}:$zTarget}]}
        for {set y 0} {$y<$ny} {incr y} {
            for {set x 0} {$x<$nx} {incr x 4096} {
                set count [expr {min(4096,$nx-$x)}];set zz [_gridValues $h [dict get $ids z] [list $y $x] [list 1 $count] $context $zTarget]
                set cc [_gridValues $h $colorId [list $y $x] [list 1 $count] $context $cTarget]
                set zz [_levelValues $context [dict get $ids z] $zz $zTarget [_get [_get [_get $spec native_presentation {}] axes {}] z_level_scale [::GX::levelScaleDefaults]]]
                for {set i 0} {$i<$count} {incr i} {set ix [expr {$x+$i}];puts $fd [join [list [expr {$y+$ix*$ny}] [lindex $coordinates(x) $ix] [lindex $coordinates(y) $y] [lindex $zz $i] Xw== [lindex $cc $i]] \t]}
            }
        }
        if {$before ne [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]} {error {Canonical grid source changed during preparation}}
    } finally {::GX::datasetAccessClose $h}
}
proc ::GX::PlotDatasetAPIv4::_3dLayers {spec geometry {persistent 0}} {
    set layers {};set index 0;set type [_get [_get $spec config {}] plot_type line3]
    set np [_get $spec native_presentation {}];set graphics [_get $np graphics {}]
    set config [dict merge [_get $spec config {}] [_get $np plot_config {}]];set styles {}
    foreach {field setting fallback} {line_width line_width 1.5 point_size marker_size 5} {
        set value [_get $config $setting inherit]
        if {$value in {{} auto inherit}} {set value [_get $graphics $setting $fallback]}
        if {$value in {{} auto inherit}} {set value $fallback}
        dict set styles $field $value
    }
    set dataset [_get $spec dataset_id {}];set sha {};if {$dataset ne {}} {set sha [dict get [::GX::sessionInspectionDatasetPayload $dataset] sha256]}
    foreach item [dict get $geometry layers] {
        set id plot_v4_[incr index];set path [dict get $item path]
        if {$persistent} {set artifact [::GX::viewerArtifactRegister [string range [file normalize $path] [expr {[string length [file normalize $::GX::currentSession]]+1}] end]];set context {}} else {set artifact [dict create resource_path $path sha256 [::GX::sha256File $path]];set context [dict create temporary_root [file dirname $path]]}
        set fields [dict merge [dict create kind [expr {$type eq {scatter3}?{points}:$type in {line3 contour3}?{trajectory}:{surface}}] source_mode artifact format vtp format_version 1 layer_order $index representation [expr {$type eq {mesh}?{wireframe}:{surface}}] scalar_array [expr {$type in {line3}?{}:{scientific_scalar}}] source_dataset_id $dataset source_dataset_sha256 $sha source_update_policy snapshot] $artifact $styles]
        # Scientific axes can carry different units and are normalized
        # independently. Screen-sized native points avoid turning scatter
        # markers into stretched geometric spheres under that transform.
        if {$type eq {scatter3}} {dict set fields sphere_glyphs 0;dict set fields representation points}
        # Validate and normalize using the existing layer authority, then retain
        # a disposable scene snapshot without changing another Viewer layer.
        set layer [::GX::viewerLayerPrepare viewer.native_3d native_3d $id $fields $context]
        dict set layer absolute_path $path;dict set layer attributes {};dict set layers $id $layer
    }
    return $layers
}
# The scalar array is C (or the untransformed Z fallback), independent of the
# spatial Z axis/level presentation. Label the units actually written by the
# existing geometry preparation; a coordinate dB transform does not transform C.
proc ::GX::PlotDatasetAPIv4::_3dScalarLabel {spec} {
    set zId [_get $spec z_variable_id z]
    set colorId [_get $spec color_variable_id {}]
    set hasColor [expr {$colorId ne {}}]
    if {!$hasColor} {set colorId $zId}
    set variable {};set zVariable {}
    if {[dict exists $spec dataset_id]} {
        set variable [::GX::datasetVariableV3ById [dict get $spec dataset_id] $colorId]
        set zVariable [::GX::datasetVariableV3ById [dict get $spec dataset_id] $zId]
    }
    set axes [_get $spec axes {}];set zAxis [_get $axes z {}]
    if {$colorId eq $zId} {set label [_get $zAxis label $zId]} else {
        set label [_get $variable display_label {}]
        if {$label eq {}} {set label [_get $variable canonical $colorId]}
        if {$label eq {}} {set label $colorId}
    }
    set graphics [_get [_get $spec native_presentation {}] graphics {}]
    # Preserve the current preparation defaults (rank-two grids default to
    # source; streamed tables default to auto). Do not change scalar values.
    set default [expr {[_get $zVariable rank 1]==2?{source}:{auto}}]
    set target [_get $graphics color_unit $default]
    if {$target in {auto inherit {}}} {set target [expr {$hasColor?{source}:[_get $zAxis display_unit source]}]}
    set unit [_get $variable unit {}]
    if {$target ni {source auto inherit {}}} {set unit $target}
    if {$unit ne {}} {append label " ($unit)"}
    return $label
}
proc ::GX::PlotDatasetAPIv4::_3dDescriptor {spec geometry {persistent 0}} {
    set np [_get $spec native_presentation {}];set graphics [_get $np graphics {}];set legendConfig [_get $np legend {}];set layout [_get $np layout {}];set axisConfig [_get $np axes {}]
    set layers [_3dLayers $spec $geometry $persistent];set bounds [dict get $geometry bounds]
    set lows {};set highs {};set labels {};set tickLabels {};set physicalRanges {};set matrix {0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1};set index 0
    foreach axis {x y z} {
        set low [lindex $bounds [expr {$index*2}]];set high [lindex $bounds [expr {$index*2+1}]]
        set a [_get [_get $spec axes {}] $axis {}];set logarithmic [expr {[_get $a scale linear] eq {log}}]
        set pad [expr {$high>$low?($high-$low)*.045:max(1.,abs($low)*.05)}]
        set low [expr {$low-$pad}];set high [expr {$high+$pad}]
        foreach {field name} {min low max high} {set v [_get $a $field auto];if {$v ni {auto {} inherit}} {if {$logarithmic} {if {$v<=0} {error {Logarithmic axis limits must be positive}};set v [expr {log10($v)}]};set $name $v}}
        if {$high<=$low} {error {Invalid Native3D scientific axis limits}}
        set sign [expr {[_get $a direction normal] eq {reverse}?-1.:1.}]
        set scale [expr {$sign/($high-$low)}];set offset [expr {-$sign*($low/($high-$low)+.5)}]
        lset matrix [expr {$index*5}] $scale;lset matrix [expr {12+$index}] $offset
        set values {};for {set i 0} {$i<=2} {incr i} {set f [expr {$sign>0?$i/2.:1.-$i/2.}];set value [expr {$low+($high-$low)*$f}];if {$logarithmic} {set value [expr {pow(10.,$value)}]};if {abs($value)<1e-14*abs($high-$low)} {set value 0};lappend values [format %.7g $value]};lappend tickLabels $values
        lappend physicalRanges [list [expr {$logarithmic?pow(10.,$low):$low}] [expr {$logarithmic?pow(10.,$high):$high}]]
        lappend lows 0;lappend highs 1
        set id [_get $spec ${axis}_variable_id $axis];set label [_get $a label $id]
        set unit {};if {[dict exists $spec dataset_id]} {set unit [_get [::GX::datasetVariableV3ById [dict get $spec dataset_id] $id] unit {}]}
        set requested [_get $a display_unit source];if {$requested ni {source auto inherit {}}} {set unit $requested};if {$unit ne {}} {append label " ($unit)"};if {$axis eq {z}} {set level [_get $axisConfig z_level_scale [::GX::levelScaleDefaults]];if {[dict get $level scale] ne {linear}} {append label " ([dict get $level scale] re [dict get $level reference_value] [dict get $level reference_unit])"}};lappend labels $label
        incr index
    }
    set type [_get [_get $spec config {}] plot_type line3]
    set spans {};foreach range $physicalRanges axis {x y z} {lassign $range lo hi;if {[_get [_get [_get $spec axes {}] $axis {}] scale linear] eq {log}} {lappend spans [expr {log10($hi)-log10($lo)}]} else {lappend spans [expr {$hi-$lo}]}}
    set mode [_get $graphics aspect_mode auto];if {$mode in {inherit {}}} {set mode auto};set box {1 1 1}
    if {$mode eq {xy_equal}} {set h [expr {max([lindex $spans 0],[lindex $spans 1])}];set box [list [expr {[lindex $spans 0]/$h}] [expr {[lindex $spans 1]/$h}] 1]} elseif {$mode in {data_equal manual}} {
        set ratio {1 1 1};if {$mode eq {manual}} {set ratio [regexp -all -inline {[^,;[:space:]]+} [_get $graphics aspect_ratio {}]];if {[llength $ratio]!=3} {error {Manual 3D aspect requires three finite positive ratios}};foreach value $ratio {if {![string is double -strict $value]||$value<=0||![expr {abs($value)<Inf}]} {error {Invalid manual 3D aspect ratio}}}}
        set horizontal [expr {max([lindex $spans 0]/[lindex $ratio 0],[lindex $spans 1]/[lindex $ratio 1])}]
        lset ratio 2 [expr {max([lindex $ratio 2],[lindex $spans 2]/(1.5*$horizontal))}]
        set box {};foreach extent $spans value $ratio {lappend box [expr {$extent/$value}]};set largest [tcl::mathfunc::max {*}$box];set box [lmap v $box {expr {$v/$largest}}]
    } elseif {$mode ne {auto}} {error {Unknown Native3D aspect policy}}
    set boxMin {};set boxMax {};for {set i 0} {$i<3} {incr i} {set size [lindex $box $i];lset matrix [expr {$i*5}] [expr {[lindex $matrix [expr {$i*5}]]*$size}];lset matrix [expr {12+$i}] [expr {[lindex $matrix [expr {12+$i}]]*$size}];lappend boxMin [expr {-$size/2.}];lappend boxMax [expr {$size/2.}]}
    dict for {id layer} $layers {dict set layer local_transform [join $matrix {;}];dict set layers $id $layer}
    set view [dict replace [::GX::viewerSceneDefaults] background_rgb {1;1;1} background_bottom_rgb {1;1;1} background_gradient 0 lighting 0 scene_mode scientific axes_world 0 camera_position {2;2;2} camera_target {0;0;0} camera_up {0;0;1} projection orthographic orthographic_height 2 near_clip .001 far_clip 100 clip_box {-.5;-.5;-.5;.5;.5;.5}]
    lassign [dict get $geometry scalar_range] scalarLo scalarHi
    if {$scalarLo==$scalarHi} {set scalarLo [expr {$scalarLo-.5}];set scalarHi [expr {$scalarHi+.5}]}
    set colorbar [expr {$type in {surface mesh contour3 trisurf heatmap}||($type eq {scatter3}&&[dict exists $spec color_variable_id])}]
    set legend {};foreach layer [dict get $geometry layers] {set family [dict get $layer family_identity];if {$family ne {_}} {lappend legend $family}}
    set figure [dict create tick_labels $tickLabels physical_axis_ranges $physicalRanges axes_grid_visible 1 colorbar_visible $colorbar bounds_min {-.5;-.5;-.5} bounds_max {.5;.5;.5} axis_min [join $lows {;}] axis_max [join $highs {;}] x_label [lindex $labels 0] y_label [lindex $labels 1] z_label [lindex $labels 2] title [_get $spec title {}] legend [join $legend { · }] scalar_label [_3dScalarLabel $spec] scalar_min $scalarLo scalar_max $scalarHi palette {{0.267;0.004;0.329} {0.282;0.14;0.458} {0.253;0.265;0.53} {0.164;0.471;0.558} {0.135;0.659;0.518} {0.478;0.821;0.318} {0.993;0.906;0.144}}]
    dict set view clip_box [join [concat $boxMin $boxMax] {;}];dict set figure bounds_min [join $boxMin {;}];dict set figure bounds_max [join $boxMax {;}];dict set figure aspect_policy [dict create mode $mode normalized_box $box]
    set background [_get $graphics background #FFFFFF];if {$background ne {transparent}} {set rgb [_rgb $background];dict set view background_rgb $rgb;dict set view background_bottom_rgb $rgb}
    dict set view projection [_get $graphics projection orthographic]
    set az [_number $graphics view_azimuth -37.5];set el [_number $graphics view_elevation 30];set pi [expr {acos(-1)}]
    dict set view camera_position [join [list [expr {3*cos($el*$pi/180)*cos($az*$pi/180)}] [expr {3*cos($el*$pi/180)*sin($az*$pi/180)}] [expr {3*sin($el*$pi/180)}]] {;}]
    set style {};set dpi [_number $graphics dpi 100];set factor [expr {[_get $graphics font_unit px] in {pt points}?$dpi/72.:1.}]
    foreach key {font_size axis_label_font_size title_font_size} fallback {12 14 18} {dict set style $key [expr {[_number $graphics $key $fallback]*$factor}]}
    set lf [expr {[_get $legendConfig font_unit inherit] in {pt points}?$dpi/72.:[_get $legendConfig font_unit inherit] eq {inherit}?$factor:1.}]
    dict set style legend_font_size [expr {[_number $legendConfig font_size 12]*$lf}]
    set placement [_get $legendConfig placement inside]
    if {$placement eq {none}} {dict set figure legend {}} else {set content {};set columns [expr {max(1,int([_number $legendConfig columns 1]))}];set orientation [_get $legendConfig layout row];if {$orientation eq {stacked}} {set content [join $legend \n]} elseif {$orientation eq {grid}} {set rows {};for {set i 0} {$i<[llength $legend]} {incr i $columns} {lappend rows [join [lrange $legend $i [expr {$i+$columns-1}]] { · }]};set content [join $rows \n]} else {set content [join $legend { · }]};dict set figure legend $content}
    set lx .45;set ly .035
    switch -- $placement {above {set ly .90} right {set lx .89;set ly .5} left {set lx .1;set ly .5} manual {set lx [_number $legendConfig manual_x .8];set ly [_number $legendConfig manual_y .8]} inside {set preset [_get $legendConfig inside_preset northeast];set lx [expr {[string match *west $preset]?.2:.7}];set ly [expr {[string match south* $preset]?.2:.8}]}}
    dict set style legend_x $lx;dict set style legend_y $ly
    dict set style legend_alignment [expr {[_get $legendConfig alignment center] eq {left}?0:[_get $legendConfig alignment center] eq {right}?2:1}]
    foreach key {background border} {set value [_get $legendConfig $key none];dict set style legend_$key [expr {$value ni {none off 0 {}}}]}
    foreach key {background border} {set color [_get $legendConfig [expr {$key eq {border}?{border_color}:$key}] #FFFFFF];if {[catch {_rgb $color} rgb]} {set rgb {1;1;1}};foreach channel {r g b} value [split $rgb {;}] {dict set style legend_${key}_$channel $value}}
    if {![_number $layout layout_auto 1]} {foreach key {left right top bottom} {dict set style margin_$key [expr {[_number $layout layout_margin_$key 10]/100.}]}}
    foreach key {xgrid ygrid zgrid} {dict set style $key [expr {[_get $axisConfig $key [_get $graphics grid_mode both]] ni {none off 0}}]}
    set grid [_get $axisConfig grid_color [_get $graphics grid_color #B0B0B0]];if {$grid eq {}} {set grid #B0B0B0};foreach channel {r g b} value [split [_rgb $grid] {;}] {dict set style grid_$channel $value}
    dict set figure native_style $style
    if {[dict exists $graphics colorbar_visible]} {dict set figure colorbar_visible [expr {!![dict get $graphics colorbar_visible]}]}
    if {[_get $graphics colorbar_label {}] ne {}} {dict set figure scalar_label [dict get $graphics colorbar_label]}
    set map [_get $graphics colormap viridis];dict set figure palette [_palette $map]
    if {$map in {gray grey grayscale}} {dict set figure palette {{0;0;0} {1;1;1}};set map grayscale} elseif {$map in {cool_warm coolwarm}} {dict set figure palette {{.230;.299;.754} {.554;.690;.996} {.865;.865;.865} {.956;.598;.477} {.706;.016;.150}};set map cool_warm}
    foreach {field target} {color_min scalar_min color_max scalar_max} {set v [_get $graphics $field {}];if {$v ne {}} {dict set figure $target $v}}
    dict for {id layer} $layers {dict set layer color_array plot_v4_rgb;dict set layer colormap viridis;dict set layer scalar_range "[dict get $figure scalar_min];[dict get $figure scalar_max]";dict set layers $id $layer}
    return [dict create view $view layers $layers scientific_figure $figure native_presentation $np presentation [dict create plot_type $type source_owner PLOT_DATASET_API_v4] caption "[_get $spec title {}] · Native3D C++/VTK"]
}
proc ::GX::PlotDatasetAPIv4::_render3DDescriptor {descriptor destination} {
    dict set descriptor graphics_policy [::GX::native3dGraphicsPolicy]
    dict set descriptor cache_root [file join [::GX::configurationCacheDirectory] gx3de_viewer derived]
    dict set descriptor session_namespace [file normalize $::GX::currentSession]
    set vector [string range [string tolower [file extension $destination]] 1 end]
    set png [expr {$vector in {pdf svg}?"$destination.native.png":$destination}]
    set graphics [_get [_get $descriptor native_presentation {}] graphics {}]
    try {::GX::Engine3D::rpc [list render [::GX::Engine3D::preparedScene $descriptor] $png [_get $graphics width_px 1000] [_get $graphics height_px 720] full];if {$vector in {pdf svg}} {::GX::Engine3D::rpc [list export_vector $destination $vector]}} finally {if {$vector in {pdf svg}} {catch {file delete -- $png}}}
    if {![file isfile $destination]} {error {Native3D produced no scientific graph}};return $destination
}
proc ::GX::PlotDatasetAPIv4::render3DSpec {spec destination} {
    set directory [file join [file dirname $destination] .native_xyz_[pid]_[clock clicks]];file mkdir $directory
    try {set geometry [_3dGeometry $spec $directory];return [_render3DDescriptor [_3dDescriptor $spec $geometry] $destination]} finally {file delete -force -- $directory}
}
proc ::GX::PlotDatasetAPIv4::render3D {ref} {set spec [loadSpec $ref];set artifacts [artifacts $ref];set output [dict get $artifacts graph_artifact];file mkdir [file dirname $output];set temp "$output.native.[pid].png";try {render3DSpec $spec $temp;file rename -force -- $temp $output} finally {catch {file delete -- $temp}};set extra [_get [_get $spec output {}] extra_format [_get [_get $spec config {}] extra_format none]];if {$extra in {svg pdf}} {render3DSpec $spec [file rootname $output].$extra};markOwned $ref;return [dict create execution native renderer_owner PLOT_DATASET_API_v4 artifacts $artifacts]}
proc ::GX::PlotDatasetAPIv4::export3D {ref destination} {render3DSpec [loadSpec $ref] $destination}
proc ::GX::PlotDatasetAPIv4::interactiveSources {} {
    _ready;set result {};foreach id [::GX::plotVariantIds plot.dataset plot.dataset.xyz] {set ref [openPlot plot.dataset.xyz $id];if {[isOwned $ref]&&![catch {interactiveSourceInfo $ref}]} {lappend result $ref}};return $result
}
proc ::GX::PlotDatasetAPIv4::interactiveSourceInfo {ref} {set spec [loadSpec $ref];set id [dict get $spec dataset_id];set bindings {};foreach role {x y z family color} {set binding [::GX::plotVariantResolvedBinding plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role];if {$binding ne {}} {dict set bindings $role $binding}};dict create plot_ref $ref graph [readPlot $ref] bindings $bindings source_dataset_id $id source_sha256 [dict get [::GX::sessionInspectionDatasetPayload $id] sha256] fingerprint [sourceFingerprint $ref]}
proc ::GX::PlotDatasetAPIv4::sourceFingerprint {ref} {set spec [loadSpec $ref];set identities {};if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {set ids [list [dict get $spec dataset_id]]} else {set ids {};foreach p [dict get $spec panels] {foreach s [dict get $p series] {lappend ids [dict get $s dataset_id]}}};foreach id [lsort -unique $ids] {lappend identities [::GX::curveSourceDatasetIdentity $::GX::currentSession $id]};return [::GX::datasetStorageSha256Text $::GX::currentSession [list $spec $identities]]}
proc ::GX::PlotDatasetAPIv4::_representation {id} {set item [::GX::interactiveDocumentRead $id];if {[dict get $item module_id] ne {plot.dataset}||[dict get $item provider_id] ne {native_3d}||[dict get $item format] ne {gxtxt.plot_dataset.native_v4_scene}||[_get [dict get $item payload] renderer_owner {}] ne {PLOT_DATASET_API_v4}} {error {Representation is not owned by native Plot v4}};return [dict get $item payload]}
proc ::GX::PlotDatasetAPIv4::interactiveRepresentations {} {set result {};foreach item [::GX::interactiveDocumentList plot.dataset native_3d] {if {[dict get $item format] eq {gxtxt.plot_dataset.native_v4_scene}} {lappend result [dict create id [dict get $item id] plot_ref [dict get [_representation [dict get $item id]] source_plot_reference] status [interactiveStatus [dict get $item id]]]}};return $result}
proc ::GX::PlotDatasetAPIv4::interactiveStatus {id} {
    set state [_representation $id];set ref [dict get $state source_plot_reference]
    if {[catch {
        set fingerprint [sourceFingerprint $ref]
        set spec [loadSpec $ref]
        set expected [_3dScalarLabel $spec]
        set manual [_get [_get [_get $spec native_presentation {}] graphics {}] colorbar_label {}]
        if {$manual ne {}} {set expected $manual}
    }]} {return {SOURCE MISSING}}
    if {$fingerprint ne [dict get $state last_successful_sync_fingerprint]} {return {OUT OF SYNC}}
    # Source identity alone cannot certify a figure made by an older label
    # formatter. Preserve the stored receipt, but do not reuse its known wrong
    # C/Z label as a current scene after an owner correction. Explicit Sync
    # remains the existing way to replace an outdated representation.
    if {[catch {dict get $state scientific_figure scalar_label} label] || $label ne $expected} {return {OUT OF SYNC}}
    return SYNCED
}
proc ::GX::PlotDatasetAPIv4::buildScene {ref {id {}}} {
    _3dReady;set spec [loadSpec $ref];set fingerprint [sourceFingerprint $ref];set dir [file join $::GX::currentSession resources viewer.native_3d plot_v4 native_[clock clicks]]
    _saveActiveNativeRepresentation
    set previous {};if {$id ne {}} {set previous [_representation $id]}
    set geometry [_3dGeometry $spec $dir];set descriptor [_3dDescriptor $spec $geometry 1];set layers [dict get $descriptor layers]
    set scene [dict get $descriptor view]
    if {$previous ne {}} {
        set scene [dict get $previous viewer_scene];set old [dict get $previous layers]
        dict for {layer fields} $layers {
            if {[dict exists $old $layer]} {
                foreach key {visible opacity representation colormap scalar_range point_size line_width} {
                    if {[dict exists $old $layer $key]} {dict set fields $key [dict get $old $layer $key]}
                }
                if {[dict exists $old $layer sphere_glyphs] && [dict get $old $layer sphere_glyphs] ne {}} {
                    dict set fields sphere_glyphs [dict get $old $layer sphere_glyphs]
                }
                dict set layers $layer $fields
            }
        }
    }
    dict set scene scene_mode scientific
    set payload [dict create source_plot_reference $ref last_successful_sync_fingerprint $fingerprint viewer_scene $scene layers $layers scientific_figure [dict get $descriptor scientific_figure] presentation [dict get $descriptor presentation] caption [dict get $descriptor caption] renderer_owner PLOT_DATASET_API_v4]
    if {$id eq {}} {set item [::GX::interactiveDocumentCreate plot.dataset native_3d gxtxt.plot_dataset.native_v4_scene 1.0 $payload];set id [dict get $item id]} else {::GX::interactiveDocumentUpdate $id $payload}
    activateInteractive $id
    return [dict create plot_ref $ref representation_id $id source_fingerprint $fingerprint layer_ids [dict keys $layers] scene_dir $dir status SYNCED renderer_owner PLOT_DATASET_API_v4]
}
proc ::GX::PlotDatasetAPIv4::_saveActiveNativeRepresentation {} {
    variable activeRepresentation
    if {![info exists activeRepresentation]||[lindex $activeRepresentation 0] ne [::GX::interactiveDocumentSessionToken]} {return {}}
    set id [lindex $activeRepresentation 1];if {[catch {set payload [_representation $id]}]} {return {}}
    if {[lsort [dict keys [dict get $payload layers]]] ne [::GX::viewerLayerIds viewer.native_3d native_3d]} {return {}}
    set layers {};foreach layer [::GX::viewerLayerIds viewer.native_3d native_3d] {set current [::GX::viewerLayerGet viewer.native_3d native_3d $layer];if {[dict get $current sha256] ne [dict get $payload layers $layer sha256]} {return {}};dict set layers $layer $current}
    dict set payload layers $layers;dict set payload viewer_scene [::GX::viewerSceneGet viewer.native_3d native_3d];::GX::interactiveDocumentUpdate $id $payload;return $id
}
proc ::GX::PlotDatasetAPIv4::saveInteractivePresentation {id} {variable activeRepresentation;_representation $id;if {![info exists activeRepresentation]||[lindex $activeRepresentation 1] ne $id} {error {Representation is not the active native view}};return [_saveActiveNativeRepresentation]}
proc ::GX::PlotDatasetAPIv4::activateInteractive {id} {_saveActiveNativeRepresentation;set payload [_representation $id];foreach layer [::GX::viewerLayerIds viewer.native_3d native_3d] {::GX::viewerLayerRemove viewer.native_3d native_3d $layer};dict for {layer fields} [dict get $payload layers] {::GX::viewerLayerSet viewer.native_3d native_3d $layer [dict remove $fields absolute_path attributes]};::GX::viewerSceneSet viewer.native_3d native_3d [dict get $payload viewer_scene];set ::GX::PlotDatasetAPIv4::activeRepresentation [list [::GX::interactiveDocumentSessionToken] $id];::GX::sessionPersistenceCommit;return [dict create representation_id $id status [interactiveStatus $id] plot_ref [dict get $payload source_plot_reference]]}
proc ::GX::PlotDatasetAPIv4::refreshInteractive {ref} {foreach item [interactiveRepresentations] {if {[dict get $item plot_ref] eq $ref} {return [syncInteractive [dict get $item id]]}};openInteractive $ref}
proc ::GX::PlotDatasetAPIv4::renderTransientCurve3D {xs ys zs label destination} {
    _3dReady;set n [llength $xs];if {$n<2||$n!=[llength $ys]||$n!=[llength $zs]||[regexp {[\r\n]} $label]} {error {Invalid transient XYZ curve}}
    file mkdir $destination;set source [file join $destination native_transient_xyz.tsv];set f [open $source w]
    try {set row 0;foreach x $xs y $ys z $zs {foreach v [list $x $y $z] {if {![string is double -strict $v]||![expr {abs($v)<Inf}]} {error {Transient coordinates must be finite}}};puts $f "[incr row]\t$x\t$y\t$z\t_\t$z"}} finally {close $f}
    try {set geometry [::GX::Native3D::plotV4Geometry [dict create input $source kind line3 palette [_palette viridis]] $destination];set spec [dict create title $label config {plot_type line3}];set descriptor [_3dDescriptor $spec $geometry];set artifact [_render3DDescriptor $descriptor [file join $destination graph.png]]} finally {file delete -- $source}
    return [dict create artifact $artifact graph_id plot.dataset.xyz transient 1 renderer_owner PLOT_DATASET_API_v4]
}
# Grid PlotSpec state is held by the existing public Variant binding/config
# authority. Stable v2 loadSpec only derives XY, so v4 resolves XYZ explicitly.
proc ::GX::PlotDatasetAPIv4::loadSpec {ref {deriveIfMissing 1}} {
    _ready
    if {[dict get $ref graph_id] ne {plot.dataset.xyz}} {set spec [::GX::PlotDatasetAPIv2::loadSpec $ref $deriveIfMissing]} else {
        set variant [_get $ref variant_id {}];if {$variant eq {}} {error {A 3D Plot requires a persistent Variant}}
        set record [::GX::PlotDatasetAPIv1::readPlot $ref]
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_3d graph_id plot.dataset.xyz config [dict get $record config] title [dict get $record config title]]
        foreach role {x y z family color} {
            set binding [::GX::plotVariantResolvedBinding plot.dataset plot.dataset.xyz $variant $role]
            if {$binding eq {}} {if {$role in {x y z}} {error "3D Plot is missing $role binding"};continue}
            set ds [dict get $binding dataset_id]
            if {[dict exists $spec dataset_id]&&[dict get $spec dataset_id] ne $ds} {error {XYZ axes must share their canonical Dataset}}
            dict set spec dataset_id $ds;dict set spec ${role}_variable_id [dict get $binding variable_id]
        }
        set metadata [::GX::graphMetadataRead [_graphRef $ref]]
        if {[dict exists $metadata native_plot_v4_axes]} {dict set spec axes [dict get $metadata native_plot_v4_axes]}
    }
    set metadata [::GX::graphMetadataRead [_graphRef $ref]];if {[dict exists $metadata native_plot_v4_presentation]} {dict set spec native_presentation [dict get $metadata native_plot_v4_presentation]}
    if {[dict get $spec graph_id] ne {plot.dataset.xyz}} {set spec [_cellFieldRestore $spec $metadata]}
    if {[llength [info commands ::GX::graphRendererEffectiveSpec]]} {set spec [::GX::graphRendererEffectiveSpec $ref $spec]}
    return $spec
}
proc ::GX::PlotDatasetAPIv4::deriveSpec {ref} {if {[dict get $ref graph_id] eq {plot.dataset.xyz}} {return [loadSpec $ref]};return [::GX::PlotDatasetAPIv2::deriveSpec $ref]}

proc ::GX::PlotDatasetAPIv4::prepare3DPreview {ref directory} {
    set spec [loadSpec $ref];set geometry [_3dGeometry $spec $directory];set descriptor [_3dDescriptor $spec $geometry]
    set f [open [file join $directory scene.tcldict] w];try {fconfigure $f -encoding utf-8;puts $f $descriptor} finally {close $f}
    return $descriptor
}
proc ::GX::PlotDatasetAPIv4::previewExportCommand {ref directory} {
    if {[dict get $ref graph_id] ne {plot.dataset.xyz}} {return [list ::GX::PlotDatasetAPIv4::_exportRef $ref $directory]}
    variable apiDir
    return [list [auto_execok tclsh] [file join [file dirname $apiDir] runtime native_v4_preview.tcl] $::GX::scriptDir $::GX::currentSession $ref $directory]
}
proc ::GX::PlotDatasetAPIv4::_previewReady {ref w} {
    variable ::GX::DatasetViewer::state
    set descriptor [prepare3DPreview $ref $state($w,temp)]
    set state($w,compactLayers) [dict get $descriptor layers];set state($w,view) [dict get $descriptor view]
    set state($w,caption) [dict get $descriptor caption];set state($w,scientificFigure) [dict get $descriptor scientific_figure];set state($w,presentation) [dict get $descriptor presentation]
    set state($w,sourceInfo) [interactiveSourceInfo $ref]
    $state($w,compactCanvas).tools.axes configure -state normal
    ::GX::meshDatasetWorkerStart $w
}
proc ::GX::PlotDatasetAPIv4::_sourceCheck {ref fingerprint} {if {[sourceFingerprint $ref] ne $fingerprint} {error {Native Plot scientific source changed; refresh the representation explicitly}};return [list PLOT_DATASET_API_v4 $ref $fingerprint]}
proc ::GX::PlotDatasetAPIv4::_openNativeConsultation {ref} {
    set spec [loadSpec $ref];set id [dict get $spec dataset_id];set fingerprint [sourceFingerprint $ref]
    set w .gxNativePlotV4;if {![winfo exists $w]} {toplevel $w;wm title $w {Native scientific Plot Dataset v4};wm geometry $w 1050x760;ttk::frame $w.view;pack $w.view -fill both -expand 1}
    raise $w
    return [::GX::native3DPreviewAcquire $w.view $id [list PLOT_DATASET_API_v4 $ref $fingerprint] [list ::GX::PlotDatasetAPIv4::_sourceCheck $ref $fingerprint] [list ::GX::PlotDatasetAPIv4::_previewReady $ref]]
}
proc ::GX::PlotDatasetAPIv4::openInteractive {ref} {set scene {};foreach item [interactiveRepresentations] {if {[dict get $item plot_ref] eq $ref&&[dict get $item status] eq {SYNCED}} {set scene [dict create plot_ref $ref representation_id [dict get $item id] status SYNCED];activateInteractive [dict get $item id];break}};if {$scene eq {}} {set scene [buildScene $ref]};dict set scene window [_openNativeConsultation $ref];return $scene}
proc ::GX::PlotDatasetAPIv4::syncInteractive {id} {set state [_representation $id];set ref [dict get $state source_plot_reference];set result [buildScene $ref $id];dict set result window [_openNativeConsultation $ref];return $result}

proc ::GX::PlotDatasetAPIv4::_number {d key default} {set v [_get $d $key $default];if {![string is double -strict $v]||![expr {abs($v)<Inf}]} {return $default};return $v}
proc ::GX::PlotDatasetAPIv4::_rgb {color} {
 if {[regexp {^#([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{2})$} $color -> r g b]} {scan $r %x r;scan $g %x g;scan $b %x b;return [join [list [expr {$r/255.}] [expr {$g/255.}] [expr {$b/255.}]] {;}]}
 if {$color eq {white}} {return {1;1;1}};if {$color eq {black}} {return {0;0;0}}
 set parts [split $color {;}];if {[llength $parts]==3} {foreach value $parts {if {![string is double -strict $value]||$value<0||$value>1} {error {Invalid RGB color}}};return $color};error {Native scientific color must be #RRGGBB or R;G;B}
}

proc ::GX::PlotDatasetAPIv4::openRepresentation {id} {_3dReady;_representation $id;return [dict create representation_id $id renderer_owner PLOT_DATASET_API_v4 window [::GX::native3DOpenScientificDocument $id]]}

proc ::GX::PlotDatasetAPIv4::_palette {name} {
    variable apiDir;variable paletteCache
    if {![info exists paletteCache]} {set paletteCache {}}
    set name [string trim $name];if {$name in {{} auto inherit}} {set name viridis}
    if {[dict exists $paletteCache $name]} {return [dict get $paletteCache $name]}
    if {$name in {cool_warm coolwarm}} {return {{.230;.299;.754} {.554;.690;.996} {.865;.865;.865} {.956;.598;.477} {.706;.016;.150}}}
    if {$name eq {grayscale}} {set name gray}
    if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $name]} {error {Colormap must name a mathematical RGB palette}}
    set script [file join [file dirname $apiDir] runtime native_v4_palette.m]
    set output [exec -- [::GX::runtimeToolRequired octave] --quiet --no-gui --no-window-system $script $name 64 2>@1]
    set palette {};foreach line [split $output \n] {if {[string match #* $line]||[string trim $line] eq {}} continue;set values [split [string trim $line]];if {[llength $values]!=3} {error "Invalid native RGB palette response: $line"};foreach value $values {if {![string is double -strict $value]||$value<0||$value>1} {error {Invalid mathematical RGB palette}}};lappend palette [join $values {;}]}
    if {[llength $palette]<2||[llength $palette]>256} {error {Mathematical color palette is unavailable}}
    dict set paletteCache $name $palette;return $palette
}

# Scientific consultation is a public v4 construction boundary. Provider graph
# identities stay with Graph Workflow; no synthetic plot.dataset Variant is made.
proc ::GX::PlotDatasetAPIv4::consultationSource {reference} {
    set ref [::GX::graphResourceRef $reference]
    if {[dict get $ref kind] ne {provider}} {error {Scientific 3D consultation requires a canonical provider graph}}
    if {[dict get $ref module_id] eq {plot.dataset} && [dict get $ref graph_id] eq {plot.dataset.xyz}} {
        previewCompatibility $ref
        set info [interactiveSourceInfo $ref]
        set resolved [dict create original_reference $ref representation_reference $ref source_info $info fingerprint [dict get $info fingerprint]]
    } else {
        # This owner validates actual producer bindings, units, retained runtime/
        # cache hashes and coordinate receipts. It does not invent a Plot ID.
        set resolved [::GX::graphWorkflowScientific3DSource $ref]
        if {![dict exists $resolved prepared_source]} {error {The provider has no admitted scientific 3D preparation}}
    }
    set info [dict get $resolved source_info]
    if {[dict get $info plot_ref] ne $ref || [dict get $resolved original_reference] ne $ref} {error {Scientific 3D source changed its original graph identity}}
    set context [::GX::datasetCoordinateRead $::GX::currentSession [dict get $info source_dataset_id]]
    set key [list [::GX::interactiveDocumentSessionToken] PLOT_DATASET_API_v4 $ref [dict get $resolved fingerprint] $context]
    dict set resolved owner ::GX::PlotDatasetAPIv4
    dict set resolved renderer_owner PLOT_DATASET_API_v4
    dict set resolved source_key $key
    dict set resolved coordinate_context $context
    return $resolved
}
proc ::GX::PlotDatasetAPIv4::consultationExportCommand {reference directory} {
    set source [consultationSource $reference]
    if {[dict exists $source prepared_source]} {
        # Reuse the existing immutable-producer exporter and its expectation
        # verification/native converter inside this v4 admission boundary.
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1
        return [::GX::PlotDataset3DAPIv1::previewGraphExportCommand [dict get $source original_reference] $directory]
    }
    return [previewExportCommand [dict get $source original_reference] $directory]
}
proc ::GX::PlotDatasetAPIv4::_consultationLayers {layers directory} {
    set directory [file normalize $directory]
    if {![dict size $layers]} {error {Scientific 3D scene has invalid native layers}}
    dict for {id layer} $layers {
        set artifact [file normalize [dict get $layer absolute_path]]
        if {[string first "$directory/" $artifact]!=0 || ![file isfile $artifact] ||
            [dict get $layer source_mode] ne {artifact} || [dict get $layer format] ne {vtp} ||
            [::GX::sha256File $artifact] ne [dict get $layer sha256]} {error {Scientific 3D native layer is outside its preparation or changed}}
    }
    return $layers
}
proc ::GX::PlotDatasetAPIv4::consultationScene {reference expectedSourceKey directory} {
    set source [consultationSource $reference]
    if {[dict get $source source_key] ne $expectedSourceKey} {error {Scientific 3D source changed during native preparation; activate again}}
    set directory [file normalize $directory]
    set path [file join $directory scene.tcldict]
    if {![file isfile $path] || [file size $path]>8388608} {error {Scientific 3D scene is missing or exceeds its existing intake budget}}
    set fd [open $path r]
    try {fconfigure $fd -encoding utf-8;set descriptor [read $fd 8388609]} finally {close $fd}
    if {[string bytelength $descriptor]>8388608} {error {Scientific 3D scene exceeds its existing intake budget}}
    foreach key {layers view caption scientific_figure presentation} {if {![dict exists $descriptor $key]} {error "Scientific 3D scene lacks $key"}}
    _consultationLayers [dict get $descriptor layers] $directory
    # The native descriptor/view/units are not rewritten. Ownership and original
    # canonical source identities are additional receipts, not another renderer.
    dict set descriptor renderer_owner PLOT_DATASET_API_v4
    dict set descriptor source_info [dict get $source source_info]
    dict set descriptor source_key $expectedSourceKey
    return $descriptor
}
proc ::GX::PlotDatasetAPIv4::xyzConsultationSource {datasetId axes} {
    if {[llength $axes]!=3 || {} in $axes || [llength [lsort -unique $axes]]!=3} {error {XYZ requires three explicit distinct canonical Variable IDs}}
    set variables {}
    foreach id $axes {
        set variable [::GX::datasetVariableV3ById $datasetId $id]
        if {![dict get $variable enabled] || [dict get $variable rank]!=1 || [dict get $variable value_kind] eq {text}} {error "Variable $id is not an enabled rank-one numerical variable."}
        lappend variables $variable
    }
    set context [::GX::datasetCoordinateRead $::GX::currentSession $datasetId]
    if {[dict get $context dataset_id] ne $datasetId} {error {XYZ coordinate context belongs to another Dataset}}
    set identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $datasetId]
    if {[dict get $identity dataset_id] ne $datasetId || [dict get $identity sha256] ne [dict get $context source_sha256]} {error {XYZ coordinate/source identity changed}}
    set key [list [::GX::interactiveDocumentSessionToken] PLOT_DATASET_API_v4 $datasetId $axes $identity $context $variables]
    return [dict create renderer_owner PLOT_DATASET_API_v4 dataset_id $datasetId variable_ids $axes variables $variables coordinate_context $context source_identity $identity source_key $key]
}

# Existing bounded XYZ construction, now admitted and owned by the public v4 facade.
proc ::GX::PlotDatasetAPIv4::xyzConsultationPrepare {id axes w} {
    variable ::GX::DatasetViewer::state
    ::GX::datasetViewerCheck $w
    if {$state($w,id) ne $id} {error {XYZ host belongs to another Dataset}}
    set source [xyzConsultationSource $id $axes]
    set state($w,plotV4XYZSource) $source
    set state($w,coordinateContext) [dict get $source coordinate_context]
    set labels {}
    foreach axis {X Y Z} vid $axes {
        set v [::GX::datasetVariableV3ById $id $vid]
        if {![dict get $v enabled] || [dict get $v rank]!=1 || [dict get $v value_kind] eq "text"} {error "Variable $vid is not an enabled rank-one numerical variable."}
        lappend labels "$axis: $vid — [dict get $v canonical] ([dict get $v unit])"
    }
    set access [::GX::datasetAccessOpen $::GX::currentSession $id]
    try {set rows [dict get [::GX::datasetAccessMetadata $access] row_count]} finally {::GX::datasetAccessClose $access}
    set limit [expr {$rows<0?100000:min(100000,$rows)}]
    set stream [::GX::tableStreamOpenDataset $::GX::currentSession $id $axes 2048 [dict create count $limit]]
    set total [dict get [::GX::tableStreamMetadata $stream] row_count]
    set state($w,xyzStream) $stream;set state($w,xyzAxes) $axes
    set state($w,xyzTotal) $total;set state($w,xyzRows) 0;set state($w,xyzPoints) {};set state($w,xyzSourceRows) {}
    set state($w,xyzStride) [expr {max(1,int(ceil(($total<0?100000:min(100000,$total))/12000.0)))}]
    set state($w,caption) "$id · read-only 3D scatter\n[join $labels { · }]"
    set state($w,prepareAfter) [after idle [list ::GX::PlotDatasetAPIv4::xyzConsultationChunk $w]]
}
proc ::GX::PlotDatasetAPIv4::xyzConsultationChunk {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,xyzStream)]} return
    if {[catch {
        ::GX::datasetViewerCheck $w
        set source [xyzConsultationSource $state($w,id) $state($w,xyzAxes)]
        if {[dict get $source source_key] ne [dict get $state($w,plotV4XYZSource) source_key]} {error {XYZ scientific source changed during preparation}}
        set chunk [::GX::tableStreamNext $state($w,xyzStream)]
        lassign $state($w,xyzAxes) x y z
        set n 0
        foreach xv [dict get $chunk values $x] yv [dict get $chunk values $y] zv [dict get $chunk values $z] {
            set row [expr {[dict get $chunk offset]+$n}];incr n
            if {$row%$state($w,xyzStride) || [llength $state($w,xyzPoints)]>=12000} continue
            if {[catch {expr {abs(double($xv))<Inf && abs(double($yv))<Inf && abs(double($zv))<Inf}} finite] || !$finite} continue
            lappend state($w,xyzPoints) [list $xv $yv $zv]
            lappend state($w,xyzSourceRows) [expr {$row+1}]
        }
        incr state($w,xyzRows) [dict get $chunk nrows]
        if {![dict get $chunk eof]} {
            set state($w,prepareAfter) [after 1 [list ::GX::PlotDatasetAPIv4::xyzConsultationChunk $w]]
            return
        }
        ::GX::tableStreamClose $state($w,xyzStream);unset state($w,xyzStream)
        set state($w,xyzCanonicalPoints) $state($w,xyzPoints)
        set presentation [xyzCoordinatePresentation $state($w,coordinateContext) $state($w,xyzAxes) $state($w,xyzCanonicalPoints)]
        set points [dict get $presentation points];set count [llength $points]
        if {!$count} {error {No finite XYZ triples in the bounded display selection.}}
        set path [file join $state($w,temp) xyz.vtp]
        set f [open $path w]
        try {
            puts $f "<?xml version=\"1.0\"?><VTKFile type=\"PolyData\" version=\"0.1\" byte_order=\"LittleEndian\"><PolyData><Piece NumberOfPoints=\"$count\" NumberOfVerts=\"$count\" NumberOfLines=\"0\" NumberOfStrips=\"0\" NumberOfPolys=\"0\">"
            puts $f {<PointData><DataArray type="Int64" Name="source_row" format="ascii">}
            puts $f $state($w,xyzSourceRows);puts $f {</DataArray></PointData><Points><DataArray type="Float64" NumberOfComponents="3" format="ascii">}
            foreach point $points {puts $f $point}
            puts $f {</DataArray></Points><Verts><DataArray type="Int64" Name="connectivity" format="ascii">}
            for {set i 0} {$i<$count} {incr i} {puts -nonewline $f "$i "}
            puts $f {</DataArray><DataArray type="Int64" Name="offsets" format="ascii">}
            for {set i 1} {$i<=$count} {incr i} {puts -nonewline $f "$i "}
            puts $f {</DataArray></Verts></Piece></PolyData></VTKFile>}
        } finally {close $f}
        set layer [dict merge [::GX::native3DPreviewLayer] [dict create absolute_path $path resource_path $path sha256 [::GX::sha256File $path] kind points representation points local_transform [dict get $presentation local_transform]]]
        set state($w,compactLayers) [dict create scatter $layer]
        set state($w,view) [dict get $presentation view]
        set state($w,scientificFigure) [dict get $presentation scientific_figure]
        set state($w,presentation) [dict remove $presentation points]
        $state($w,compactCanvas).tools.axes configure -state normal
        set state($w,caption) [dict get $presentation caption]
        append state($w,caption) "\n$count finite points; [expr {$state($w,xyzTotal)<0?{unknown}:$state($w,xyzTotal)}] canonical rows. Display scan: first $state($w,xyzRows) rows (limit 100000); stride $state($w,xyzStride), point limit 12000. No connectivity or interpolation."
        dict append state($w,scientificFigure) legend " · $count pts / $state($w,xyzRows) scanned; stride $state($w,xyzStride)"
        set state($w,xyzDisplayReceipt) [dict create dataset_id $state($w,id) variable_ids $state($w,xyzAxes) total_rows $state($w,xyzTotal) scanned_rows $state($w,xyzRows) displayed_points $count stride $state($w,xyzStride) source_rows $state($w,xyzSourceRows) coordinate_presentation [dict remove $presentation points]]
        unset state($w,xyzPoints) state($w,xyzSourceRows)
        set state($w,plotV4Receipt) [dict create renderer_owner PLOT_DATASET_API_v4 source_key [dict get $source source_key] dataset_id $state($w,id) variable_ids $state($w,xyzAxes) source_identity [dict get $source source_identity] coordinate_context [dict get $source coordinate_context] display_receipt $state($w,xyzDisplayReceipt)]
        ::GX::datasetViewerCheck $w
        ::GX::meshDatasetWorkerStart $w
    } message]==1} {::GX::native3DPreviewFailure $w $message}
}

# A view-owned normalized frame keeps independent scientific axis magnification
# visible. The fixed camera never refits it away; VTP values remain display-unit
# coordinates and the retained source triples are never transformed in place.
proc ::GX::PlotDatasetAPIv4::xyzCoordinatePresentation {context axes canonicalPoints} {
    if {[llength $axes]!=3||[llength [lsort -unique $axes]]!=3} {error {XYZ presentation requires three distinct Variables}}
    if {![llength $canonicalPoints]||[llength $canonicalPoints]>12000} {error {XYZ presentation requires 1..12000 finite source triples}}
    foreach point $canonicalPoints {
        if {[llength $point]!=3} {error {XYZ source samples must be triples}}
        foreach value $point {if {![string is double -strict $value]||[catch {expr {abs(double($value))<Inf}} finite]||!$finite} {error {XYZ source samples must be finite}}}
    }
    set columns {};set labels {};set lows {};set highs {};set ranges {};set policies {};set notices {}
    set transform {0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1}
    foreach index {0 1 2} axis {X Y Z} vid $axes {
        set settings [::GX::scientificDatasetCoordinateSettings $context $vid]
        set values [lmap p $canonicalPoints {lindex $p $index}];set shown {}
        if {[dict exists $context variables $vid]} {
            # Canonical Dataset readers expose HMS values in seconds. Return
            # only the presentation buffer to the declared source frame before
            # using the shared source-pivot coordinate policy.
            set source [dict get $settings source]
            if {[dict get $source value_kind] eq "elapsed_time"&&[dict get $source value_format] eq "hms"} {set values [::GX::elapsedTimeConvert $values [dict get $source unit]]}
            for {set start 0} {$start<[llength $values]} {incr start 4096} {
                set result [::GX::datasetCoordinateSnapshotValues $context $vid [lrange $values $start [expr {$start+4095}]] {mode canonical}]
                lappend shown {*}[dict get $result values]
            }
        } else {set shown $values}
        set sorted [lsort -real $shown];set lo [lindex $sorted 0];set hi [lindex $sorted end]
        set pad [expr {$lo==$hi?max(1.0,abs($lo)*.05):($hi-$lo)*.05}]
        set reference [list [expr {$lo-$pad}] [expr {$hi+$pad}]];set displayed $reference
        if {[dict get $settings view_factor]!=1} {
            set sourceRange [lsort -real [dict get [::GX::datasetCoordinateSnapshotValues $context $vid $reference {direction inverse}] values]]
            set range [::GX::datasetCoordinateSnapshotViewRange $context $vid $sourceRange]
            set displayed [lsort -real [dict get [::GX::datasetCoordinateSnapshotValues $context $vid [dict get $range canonical_range]] values]]
        } else {set range [dict create view_factor 1 view_pivot [dict get $settings view_pivot]]}
        lassign $displayed lo hi
        if {[catch {expr {$lo<$hi&&abs($lo)<Inf&&abs($hi)<Inf&&abs($hi-$lo)<Inf}} valid]||!$valid} {error {XYZ coordinate policy collapses or overflows the display range}}
        set width [expr {$hi-$lo}];set scale [expr {1.0/$width}];set offset [expr {-($lo/$width+.5)}]
        if {$scale==0||abs($scale)>=Inf||abs($offset)>=Inf} {error {XYZ coordinate frame is not representable}}
        lset transform [expr {$index*5}] $scale;lset transform [expr {12+$index}] $offset
        lappend columns $shown;lappend lows $lo;lappend highs $hi
        set unit [dict get $settings display_unit];set source [dict get $settings source]
        lappend labels "$vid ([expr {$unit eq {}?{undeclared}:$unit}])"
        dict set policies $vid $settings
        lappend ranges [dict merge $range [dict create variable_id $vid reference_display_range $reference display_range $displayed]]
        lappend notices "$axis×[format %.6g [dict get $settings view_factor]] @[format %.6g [dict get $settings view_pivot]] [dict get $source unit]"
    }
    set points {};foreach x [lindex $columns 0] y [lindex $columns 1] z [lindex $columns 2] {lappend points [list $x $y $z]}
    set notice "[join $notices { · }]; calibration unapplied"
    set view [dict replace [::GX::viewerSceneDefaults] background_rgb {1;1;1} background_bottom_rgb {1;1;1} background_gradient 0 lighting 0 axes_world 0 orientation_indicator_visible 1 camera_position {2;2;2} camera_target {0;0;0} camera_up {0;0;1} projection orthographic orthographic_height 2 near_clip .001 far_clip 100 clip_box {-.5;-.5;-.5;.5;.5;.5}]
    set figure [dict create axes_grid_visible 1 colorbar_visible 0 bounds_min {-.5;-.5;-.5} bounds_max {.5;.5;.5} axis_min [join $lows {;}] axis_max [join $highs {;}] x_label [lindex $labels 0] y_label [lindex $labels 1] z_label [lindex $labels 2] title "[dict get $context dataset_id] — XYZ scatter" legend $notice scalar_label {}]
    return [dict create schema gxtxt.xyz_coordinate_presentation.v1 context $context variable_ids $axes points $points local_transform [join $transform {;}] view $view scientific_figure $figure ranges $ranges coordinate_policies $policies calibration_applied 0 source_values_modified 0 caption "[dict get $figure title]\n[join $labels { · }]\n$notice"]
}


# Read-only counterpart of widgetReceipt for the existing shared 3D host.
# A construction receipt is never reported current merely because an old frame
# remains visible; the same canonical source and live host must still validate.
proc ::GX::PlotDatasetAPIv4::consultationReceipt {hostWindow} {
    variable ::GX::DatasetViewer::state
    ::GX::datasetViewerCheck $hostWindow
    if {![info exists state($hostWindow,plotV4Receipt)]} {error {No admitted public v4 scientific scene is available}}
    set receipt $state($hostWindow,plotV4Receipt)
    if {[info exists state($hostWindow,plotV4XYZSource)]} {
        set current [xyzConsultationSource $state($hostWindow,id) $state($hostWindow,xyzAxes)]
    } else {set current [consultationSource [dict get $receipt source_info plot_ref]]}
    if {[dict get $current source_key] ne [dict get $receipt source_key]} {error {The public v4 scientific scene belongs to a changed source}}
    set ready [expr {[info exists state($hostWindow,ready)] && $state($hostWindow,ready) && [info exists state($hostWindow,image)] && $state($hostWindow,image) ne {}}]
    set busy [expr {[info exists state($hostWindow,busy)] && $state($hostWindow,busy)}]
    dict set receipt status [expr {!$ready?{preparing}:$busy?{updating}:{current}}]
    dict set receipt source_current 1
    set layers {}
    dict for {id layer} [_consultationLayers $state($hostWindow,compactLayers) $state($hostWindow,temp)] {dict set layers $id [dict create kind [dict get $layer kind] format [dict get $layer format] sha256 [dict get $layer sha256]]}
    dict set receipt native_layers $layers
    return $receipt
}
