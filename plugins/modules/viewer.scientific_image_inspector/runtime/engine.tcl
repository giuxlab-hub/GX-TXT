# Scientific Image Inspector: one validated ImageMagick adapter (no shell).
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {
    variable engineHelp ""
    variable jobCounter 0
    variable jobs
    variable waits
    variable temps {}
    variable timeoutMs 30000
    variable maxOutput 1048576
    variable maxPixels 100000000
}
proc ::GX::SII::get {d key {fallback ""}} {
    if {[dict exists $d $key]} {return [dict get $d $key]}
    return $fallback
}
proc ::GX::SII::magickPath {} {
    if {![llength [info commands ::GX::runtimeToolRequired]]} {
        error "GX-TXT Configuration API is not available"
    }
    return [::GX::runtimeToolRequired magick]
}
proc ::GX::SII::magickVersion {} {
    return [lindex [split [run [list [magickPath] -version] 8000] \n] 0]
}
proc ::GX::SII::capabilities {} {
    variable engineHelp
    set magick [magickPath]
    set ver [run [list $magick -version] 8000]
    if {$engineHelp eq ""} { set engineHelp [run [list $magick -help] 8000] }
    set formats [run [list $magick -list format] 12000]
    set colors [run [list $magick -list colorspace] 8000]
    set channels [run [list $magick -list channel] 8000]
    set filters [run [list $magick -list filter] 8000]
    set policy [run [list $magick -list policy] 8000]
    set delegates [run [list $magick -list delegate] 8000]
    return [dict create version $ver formats $formats colorspaces $colors channels $channels filters $filters policy $policy delegates $delegates]
}
proc ::GX::SII::operationStatus {id} {
    variable engineHelp
    set spec [catalogGet $id]
    set support [dict get $spec support]
    if {$support ne "executable"} {
        return [dict create state $support reason [dict get $spec reason]]
    }
    if {[catch {set tool [magickPath]} reason]} {return [dict create state unavailable reason $reason]}
    if {$engineHelp eq ""} {
        if {[catch {set engineHelp [run [list $tool -help] 8000]} reason]} {
            return [dict create state unavailable reason $reason]
        }
    }
    set flag [dict get $spec option]
    if {$flag ne "" && [string first $flag $engineHelp] < 0} {
        return [dict create state unavailable reason "Option $flag is absent from this ImageMagick build"]
    }
    return [dict create state executable reason "Validated adapter available"]
}
proc ::GX::SII::_onReadable {id} {
    variable jobs
    variable waits
    variable maxOutput
    if {![info exists jobs($id)]} {return}
    set job $jobs($id)
    set ch [dict get $job channel]
    if {![catch {set part [read $ch]} msg]} {
        set old [dict get $job output]
        if {[string length $old] + [string length $part] > $maxOutput} {
            dict set job overflow 1
            set part [string range $part 0 [expr {$maxOutput-[string length $old]}]]
        }
        dict set job output "$old$part"
    } else {
        dict set job read_error $msg
    }
    set jobs($id) $job
    if {[eof $ch] || [get $job overflow 0] || [dict exists $job read_error]} {
        fileevent $ch readable {}
        set closeCode [catch {close $ch} reason]
        if {[dict get $job timer] ne ""} {after cancel [dict get $job timer]}
        if {$closeCode} {dict set job failure $reason}
        if {[get $job overflow 0]} {dict set job failure "ImageMagick output exceeded the safety limit"}
        if {[dict exists $job read_error]} {dict set job failure [dict get $job read_error]}
        set jobs($id) $job
        set waits($id) 1
    }
}
proc ::GX::SII::_terminate {id why} {
    variable jobs
    variable waits
    if {![info exists jobs($id)]} {return}
    set job $jobs($id)
    if {[info exists waits($id)] && $waits($id)} {return}
    foreach child [dict get $job pids] {
        if {$::tcl_platform(platform) eq "windows"} {
            catch {exec taskkill /PID $child /T /F}
        } else {
            catch {exec kill -TERM -- $child}
        }
    }
    dict set job failure $why
    set jobs($id) $job
    # Closing asynchronously avoids waiting on a process in the GUI callback.
    set ch [dict get $job channel]
    fileevent $ch readable [list ::GX::SII::_onReadable $id]
    after 1000 [list ::GX::SII::_forceFinish $id]
}
proc ::GX::SII::_forceFinish {id} {
    variable jobs
    variable waits
    if {![info exists jobs($id)] || ([info exists waits($id)] && $waits($id))} {return}
    set job $jobs($id)
    foreach child [dict get $job pids] {
        if {$::tcl_platform(platform) ne "windows"} {catch {exec kill -KILL -- $child}}
    }
    catch {fileevent [dict get $job channel] readable {}}
    catch {close [dict get $job channel]}
    set waits($id) 1
}
proc ::GX::SII::cancel {} {
    variable jobCounter
    _terminate $jobCounter "Operation cancelled by user"
}
proc ::GX::SII::run {argv {limitMs ""}} {
    variable jobCounter
    variable jobs
    variable waits
    variable timeoutMs
    if {$limitMs eq ""} {set limitMs $timeoutMs}
    if {$limitMs < 100 || $limitMs > 240000} {error "Invalid execution timeout"}
    set id [incr jobCounter]
    set ch [open |[list {*}$argv 2>@1] r]
    fconfigure $ch -translation binary -encoding utf-8 -blocking 0 -buffering none
    set jobs($id) [dict create channel $ch pids [pid $ch] output "" timer "" argv $argv]
    set waits($id) 0
    fileevent $ch readable [list ::GX::SII::_onReadable $id]
    dict set jobs($id) timer [after $limitMs [list ::GX::SII::_terminate $id "ImageMagick timed out"]]
    vwait ::GX::SII::waits($id)
    set job $jobs($id)
    unset jobs($id) waits($id)
    if {[dict exists $job failure]} {error "[dict get $job failure]: [string range [dict get $job output] end-1000 end]"}
    return [dict get $job output]
}
proc ::GX::SII::tempFile {extension} {
    variable temps
    if {![regexp {^\.[a-z0-9]+$} $extension]} {error "Invalid temporary format"}
    set base [::GX::configurationTempDirectory]
    set fd [file tempfile tmp [file join $base sii-]]
    close $fd
    file delete -- $tmp
    set path "$tmp$extension"
    lappend temps $path
    return $path
}
proc ::GX::SII::cleanTemps {} {
    variable temps
    foreach p $temps {catch {file delete -- $p}}
    set temps {}
}
proc ::GX::SII::datasetIds {} {
    set session [::GX::sessionInspectionCurrentSession]
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds $session] {
        if {[catch {set ds [::GX::sessionInspectionDataset $id $session]}]} continue
        set contract [get $ds contract [get $ds kind ""]]
        if {$contract eq "image.raster" || (![catch {::GX::contractSatisfies $contract image.raster} yes] && $yes)} {lappend out $id}
    }
    return [lsort -dictionary $out]
}
proc ::GX::SII::sourceInfo {datasetId} {
    set session [::GX::sessionInspectionCurrentSession]
    if {[lsearch -exact [datasetIds] $datasetId] < 0} {error "Not an authorized image.raster Dataset: $datasetId"}
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set payload [::GX::sessionInspectionDatasetPayload $datasetId $session]
    set path [dict get $payload path]
    if {![file isfile $path] || [file type $path] ne "file"} {error "Source image is not a regular file"}
    set sha [get $payload sha256]
    if {![regexp -nocase {^[a-f0-9]{64}$} $sha]} {error "Missing canonical SHA-256"}
    if {[llength [info commands ::GX::sha256File]] && ![string equal -nocase [::GX::sha256File $path] $sha]} {
        error "Source Dataset SHA-256 mismatch; image is not trusted"
    }
    set metadata {}
    if {[llength [info commands ::GX::datasetMetadataRead]]} {
        catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}
    }
    return [dict create id $datasetId sha256 $sha path $path contract image.raster metadata $metadata \
        format [get $ds format] media_type [get $ds media_type] size_bytes [file size $path]]
}
proc ::GX::SII::frame0 {path} {
    # Paths are already provided by canonical Session API; first frame is explicit.
    return "${path}\[0\]"
}
proc ::GX::SII::limits {} {
    return {-limit memory 192MiB -limit map 384MiB -limit disk 768MiB -limit time 30 -limit thread 2 -limit list-length 64}
}
proc ::GX::SII::inspectFile {path} {
    # Metadata only. -ping avoids eager full raster decode.
    set fmt [join {%m %w %h %z {%[channels]} {%[colorspace]} {%[type]} {%[orientation]} %n %x %y %U %b} "\t"]
    set raw [string trim [run [list [magickPath] identify {*}[limits] -ping -format $fmt [frame0 $path]]]]
    # IM's escapes are textual; translate them without Tcl interpolation.
    set fields [split [string map [list {\t} "\t"] $raw] "\t"]
    if {[llength $fields] != 13} {error "Unexpected ImageMagick identify result: $raw"}
    lassign $fields format w h depth channels space type orientation frames xres yres units bytes
    if {![string is integer -strict $w] || ![string is integer -strict $h] || $w < 1 || $h < 1} {error "Invalid image dimensions"}
    variable temps
    if {$format ni {PNG JPEG TIFF BMP BMP2 BMP3} && !($format eq "MIFF" && [lsearch -exact $temps $path] >= 0)} {
        error "Only importer-supported raster sources or plugin-owned intermediate rasters are accepted: $format"
    }
    return [dict create format $format width $w height $h pixel_count [expr {wide($w)*wide($h)}] \
        depth $depth channels $channels colorspace $space type $type orientation $orientation frames $frames \
        resolution_x $xres resolution_y $yres density_units $units im_bytes $bytes]
}
proc ::GX::SII::inspect {datasetId} {
    set info [sourceInfo $datasetId]
    set measurements [inspectFile [dict get $info path]]
    # Count container frames/pages via header probing only; no pixel decode.
    if {[catch {set frames [run [list [magickPath] identify {*}[limits] -ping -format "%n\n" [dict get $info path]] 16000]}]} {
        dict set measurements frame_count unavailable
    } else {
        set count [lindex [split [string trim $frames] "\n"] 0]
        dict set measurements frame_count [expr {[string is integer -strict $count] ? $count : "unavailable"}]
    }
    return [dict merge $info $measurements [dict create engine [magickVersion]]]
}
proc ::GX::SII::detailedInfo {path} {
    set result [run [list [magickPath] identify {*}[limits] -verbose [frame0 $path]] 35000]
    return $result
}
proc ::GX::SII::number {value low high integer} {
    if {$integer} {
        if {![string is integer -strict $value]} {error "Expected integer; got '$value'"}
    } else {
        if {![string is double -strict $value]} {error "Expected finite number; got '$value'"}
    }
    if {$value < $low || $value > $high || $value != $value} {error "Value $value outside [$low, $high]"}
    return $value
}
proc ::GX::SII::geometry {text} {
    # Strict numeric syntax, no ImageMagick substitutions or flags.
    if {![regexp {^([1-9][0-9]{0,6})x([1-9][0-9]{0,6})([+-][0-9]{1,7})?([+-][0-9]{1,7})?$} $text -> w h]} {
        error "Geometry must be WxH or WxH+X+Y (positive dimensions)"
    }
    if {wide($w) * wide($h) > 100000000} {error "Geometry exceeds 100 megapixels"}
    return $text
}
proc ::GX::SII::validate {id values} {
    set spec [catalogGet $id]
    set state [dict get [operationStatus $id] state]
    if {$state ne "executable"} {error "Operation $id is not executable ($state)"}
    set names {}
    set out {}
    foreach field [dict get $spec params] {
        lassign $field name type default lo hi choices
        lappend names $name
        set v [get $values $name $default]
        switch -- $type {
            int {number $v $lo $hi 1}
            number - percent {number $v $lo $hi 0}
            geometry {geometry $v}
            enum {if {[lsearch -exact $choices $v] < 0} {error "Unsupported $name: $v"}}
            default {error "Internal catalog type not understood: $type"}
        }
        dict set out $name $v
    }
    foreach k [dict keys $values] {if {[lsearch -exact $names $k] < 0} {error "Unknown parameter '$k' for $id"}}
    if {$id eq "level" && [dict get $out black] >= [dict get $out white]} {error "Black level must be below white level"}
    return $out
}
proc ::GX::SII::operationArgs {id values} {
    set p [validate $id $values]
    set op [dict get [catalogGet $id] option]
    switch -- $id {
        level {return [list $op "[dict get $p black]%,[dict get $p white]%"]}
        brightness_contrast {return [list $op "[dict get $p brightness]x[dict get $p contrast]"]}
        contrast_stretch {return [list $op "[dict get $p black]%,[dict get $p white]%"]}
        sigmoidal {return [list $op "[dict get $p contrast]x[dict get $p midpoint]%"]}
        modulate {return [list $op "[dict get $p brightness],[dict get $p saturation],[dict get $p hue]"]}
        blur - gaussian_blur - sharpen - emboss {return [list $op "[dict get $p radius]x[dict get $p sigma]"]}
        unsharp {return [list $op "[dict get $p radius]x[dict get $p sigma]+[dict get $p gain]+[dict get $p threshold]"]}
        median {return [list -statistic Median "[dict get $p size]x[dict get $p size]"]}
        erode - dilate - open - close - gradient {
            set method [dict get [dict create erode Erode dilate Dilate open Open close Close gradient Edge] $id]
            return [list -morphology $method "Disk:[dict get $p radius]"]
        }
        gamma {return [list $op [dict get $p gamma]]}
        resize - sample - extent {return [list $op [dict get $p geometry]]}
        crop {return [list $op [dict get $p rect] +repage]}
        rotate {return [list $op [dict get $p degrees]]}
        deskew - threshold - white_threshold - black_threshold - solarize {return [list $op "[dict get $p threshold]%"]}
        colorspace {return [list $op [dict get $p space]]}
        posterize {return [list $op [dict get $p levels]]}
        quantize {return [list $op [dict get $p count]]}
        alpha_extract - alpha_deactivate {return [list $op [dict get $p mode]]}
        edge {return [list $op [dict get $p radius]]}
        default {
            if {[llength [dict get [catalogGet $id] params]]} {error "Operation requires an explicit formatter: $id"}
            return [list $op]
        }
    }
}
proc ::GX::SII::validateSteps {steps} {
    if {[llength $steps] > 64} {error "Processing chain exceeds 64 steps"}
    set clean {}
    foreach s $steps {
        if {![dict exists $s op] || ![dict exists $s params]} {error "Malformed processing step"}
        set op [dict get $s op]
        set params [validate $op [dict get $s params]]
        set scope [get $s scope all]
        if {$scope ni {all roi}} {error "Unsupported operation scope"}
        set roi [get $s roi {}]
        if {$scope eq "roi"} {
            if {![dict get [catalogGet $op] roi]} {error "$op cannot be restricted to ROI"}
            if {[llength $roi] != 4} {error "ROI must be x y width height"}
            lassign $roi x y w h
            foreach n [list $x $y $w $h] {number $n 0 1000000 1}
            if {$w <= 0 || $h <= 0} {error "ROI dimensions must be positive"}
            if {wide($w)*wide($h) > 100000000} {error "ROI too large"}
        }
        lappend clean [dict create op $op params $params scope $scope roi $roi]
    }
    return $clean
}
proc ::GX::SII::processFile {path steps output {format miff}} {
    set steps [validateSteps $steps]
    if {$format ni {miff png16 tiff16 tiff32f}} {error "Unsupported output format"}
    set info [inspectFile $path]
    if {[dict get $info pixel_count] > 100000000} {error "Full-resolution processing requires an image no larger than 100 megapixels"}
    set previous [frame0 $path]
    set scratch {}
    try {
        foreach step $steps {
            set intermediate [tempFile .miff]
            lappend scratch $intermediate
            set op [dict get $step op]
            set args [operationArgs $op [dict get $step params]]
            if {[dict get $step scope] eq "roi"} {
                lassign [dict get $step roi] x y w h
                set dimensions [expr {[llength $scratch] == 1 ? $info : [inspectFile $previous]}]
                if {$x+$w > [dict get $dimensions width] || $y+$h > [dict get $dimensions height]} {
                    error "ROI exceeds the raster dimensions at this processing step"
                }
                set args [list \( +clone -crop "${w}x${h}+${x}+${y}" +repage {*}$args \) -geometry "+${x}+${y}" -compose Copy -composite]
            }
            set cmd [list [magickPath] {*}[limits] $previous {*}$args -define quantum:format=floating-point MIFF:$intermediate]
            run $cmd 35000
            if {![file isfile $intermediate]} {error "ImageMagick did not produce a processing stage"}
            set previous $intermediate
        }
        set outargs {}
        switch -- $format {
            png16 {set outargs [list -depth 16 PNG:$output]}
            tiff16 {set outargs [list -depth 16 -compress Zip TIFF:$output]}
            tiff32f {set outargs [list -define quantum:format=floating-point -depth 32 -compress Zip TIFF:$output]}
            miff {set outargs [list -define quantum:format=floating-point MIFF:$output]}
        }
        set cmd [list [magickPath] {*}[limits] $previous {*}$outargs]
        run $cmd 35000
        if {![file isfile $output] || [file size $output] == 0} {error "ImageMagick did not produce the expected output"}
        return $output
    } finally {
        foreach scratchFile $scratch {catch {file delete -- $scratchFile}}
    }
}
proc ::GX::SII::previewFile {source output {width 1100} {height 850}} {
    number $width 80 4000 1
    number $height 80 4000 1
    run [list [magickPath] {*}[limits] [frame0 $source] -thumbnail "${width}x${height}>" -depth 8 PNG:$output] 35000
    if {![file isfile $output]} {error "Image preview is missing"}
    return $output
}
proc ::GX::SII::regionArgs {roi} {
    if {$roi eq ""} {return {}}
    if {[llength $roi] != 4} {error "ROI must contain 4 integers"}
    lassign $roi x y w h
    foreach v $roi {number $v 0 1000000 1}
    if {$w < 1 || $h < 1} {error "ROI dimensions must be positive"}
    return [list -crop "${w}x${h}+${x}+${y}" +repage]
}
proc ::GX::SII::stats {source {roi {}} {channel All}} {
    if {$channel ni {All Gray R G B A}} {error "Unsupported statistical channel"}
    set chanargs {}
    if {$channel eq "Gray"} {set chanargs {-colorspace Gray}}
    if {$channel in {R G B A}} {set chanargs [list -channel $channel -separate]}
    set fmt {minimum=%[fx:minima]\nmaximum=%[fx:maxima]\nmean=%[fx:mean]\nstddev=%[fx:standard_deviation]\nmedian=%[fx:median]\nrms=%[fx:root_mean_square]\nskewness=%[fx:skewness]\nkurtosis=%[fx:kurtosis]\nentropy=%[entropy]\nunique_colors=%k}
    set result [run [list [magickPath] {*}[limits] [frame0 $source] {*}[regionArgs $roi] {*}$chanargs -format $fmt info:] 35000]
    set d {}
    foreach line [split [string map [list {\n} "\n"] $result] \n] {
        if {[regexp {^([a-z_]+)=(.*)$} $line -> k val]} {dict set d $k $val}
    }
    return $d
}
proc ::GX::SII::histogram {source {channel Gray} {roi {}}} {
    if {$channel ni {Gray R G B A}} {error "Unsupported histogram channel"}
    set cmd [list [magickPath] {*}[limits] [frame0 $source] {*}[regionArgs $roi]]
    if {$channel eq "Gray"} {
        lappend cmd -colorspace Gray
    } else {
        lappend cmd -channel $channel -separate
    }
    lappend cmd -depth 8 -format %c histogram:info:-
    set text [run $cmd 35000]
    set bins [lrepeat 256 0]
    foreach line [split $text \n] {
        # ImageMagick histogram records contain 8-bit hex color values (#XX or #XXXXXX).
        if {![regexp {^\s*([0-9]+):.*?#([0-9A-Fa-f]{2})(?:[0-9A-Fa-f]{4,6})?} $line -> count hex]} continue
        scan $hex %x index
        lset bins $index [expr {[lindex $bins $index] + $count}]
    }
    return [dict create channel $channel bins $bins bin_depth 8 roi $roi]
}

proc ::GX::SII::palette {source {roi {}} {colors 16}} {
    number $colors 2 128 1
    set text [run [list [magickPath] {*}[limits] [frame0 $source] {*}[regionArgs $roi] -colors $colors -depth 8 -format %c histogram:info:-] 35000]
    set out {}
    foreach line [split $text \n] {
        if {[regexp {^\s*([0-9]+):.*?(#[0-9a-fA-F]{6,8})\s} $line -> count hex]} {
            lappend out [list $count $hex]
        }
    }
    return [lsort -integer -decreasing -index 0 $out]
}

proc ::GX::SII::pixel {source x y} {
    number $x 0 1000000 1
    number $y 0 1000000 1
    set info [inspectFile $source]
    if {$x >= [dict get $info width] || $y >= [dict get $info height]} {error "Pixel outside image bounds"}
    return [run [list [magickPath] {*}[limits] [frame0 $source] -crop "1x1+${x}+${y}" +repage txt:-] 30000]
}

# Public headless processing entrypoint: only a canonical Dataset ID is accepted.
# Caller releases the result using releaseResult, or publishes it using publish.
proc ::GX::SII::process {datasetId steps {format miff}} {
    if {$format ni {miff png16 tiff16 tiff32f}} {error "Invalid processing format"}
    set source [sourceInfo $datasetId]
    set ext [expr {$format eq "miff" ? ".miff" : ($format eq "png16" ? ".png" : ".tif")}]
    set temporary [tempFile $ext]
    try {
        processFile [dict get $source path] $steps $temporary $format
        return [dict create result_path $temporary source_dataset_id $datasetId source_sha256 [dict get $source sha256] format $format]
    } on error {message opts} {
        catch {file delete -- $temporary}
        return -options $opts $message
    }
}
proc ::GX::SII::releaseResult {path} {
    variable temps
    set index [lsearch -exact $temps $path]
    if {$index < 0} {error "Cannot release a file not owned by Scientific Image Inspector"}
    catch {file delete -- $path}
    set temps [lreplace $temps $index $index]
}

proc ::GX::SII::publish {sourceId steps outputId {format tiff16} {manifest {}}} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} $outputId]} {error "Invalid target Dataset ID"}
    if {$format ni {png16 tiff16 tiff32f}} {error "Unsupported publish format"}
    set token [::GX::interactiveDocumentSessionToken]
    set source [sourceInfo $sourceId]
    set steps [validateSteps $steps]
    set extension [expr {$format eq "png16" ? ".png" : ".tif"}]
    set temp [tempFile $extension]
    try {
        processFile [dict get $source path] $steps $temp $format
        if {$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed while processing; publication refused"}
        # Confirm source was not switched or externally modified during processing.
        set now [sourceInfo $sourceId]
        if {[dict get $now sha256] ne [dict get $source sha256]} {error "Source Dataset changed"}
        set metadata [dict create \
            image.inspector.source_dataset_id $sourceId \
            image.inspector.source_sha256 [dict get $source sha256] \
            image.inspector.operations [list {*}$steps] \
            image.inspector.engine [magickVersion] \
            image.inspector.format $format \
            image.inspector.color_policy {ImageMagick color-space operations only; source ICC not reinterpreted} \
            image.inspector.roi_coordinates {per-step current raster coordinates; top-left origin}]
        if {$manifest eq {}} {set manifest [makeManifest $sourceId $steps {} {} {} $format {}]}
        dict set manifest output dataset_id $outputId
        dict set manifest output expected_sha256 [::GX::sha256File $temp]
        dict set manifest output raster_properties [inspectFile $temp]
        manifestValidate $manifest
        dict set metadata image.inspector.manifest $manifest
        dict set metadata image.inspector.manifest_schema scientific_image_inspector.manifest.v1
        set req [dict create dataset_id $outputId contract image.raster \
            format [expr {$format eq "png16" ? "png" : "tiff"}] \
            media_type [expr {$format eq "png16" ? "image/png" : "image/tiff"}] \
            storage_kind binary source_file $temp source_dataset_ids [list $sourceId] \
            source {Scientific Image Inspector derived raster} \
            producer_version $::GX::SII::version \
            provenance "Non-destructive ImageMagick processing of $sourceId ([dict get $source sha256])" \
            structured_metadata $metadata]
        # Replacement is never automatic and foreign datasets cannot be overwritten.
        return [::GX::datasetFilePublicationPublish [::GX::sessionInspectionCurrentSession] $::GX::SII::moduleId $req]
    } finally {
        catch {file delete -- $temp}
    }
}
