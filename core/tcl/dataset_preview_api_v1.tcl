# GX-TXT Dataset Preview API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Generic CORE preview layer for canonical Datasets.  The preview is selected
# from Dataset/storage/media metadata rather than from a filename extension.
# Text/CSV remains supported, table-shaped binary datasets are sampled through
# the public Table Stream API, and media datasets can expose a safe derived
# visual preview plus an explicit system-application open action.

namespace eval ::GX {
    variable datasetPreviewApiVersion 1
    variable previewSettings
    variable previewSettingsLoaded 0
    variable previewCurrentPath ""
    variable previewCurrentMediaType ""
    variable previewCurrentContract ""
    variable previewCurrentFormat ""
    array set previewSettings {}
}

proc ::GX::previewSettingsDefaults {} {
    return [dict create \
        table_rows 12 \
        table_columns 16 \
        max_cell_chars 96 \
        metadata_fields 48 \
        metadata_value_chars 180 \
        image_inline 1 \
        image_thumbnailer auto \
        image_width_px 960 \
        image_height_px 640 \
        image_max_source_bytes 67108864 \
        pdf_thumbnail 1 \
        pdf_renderer auto \
        pdf_width_px 960 \
        audio_waveform 1 \
        audio_renderer auto \
        audio_preview_seconds 30 \
        audio_width_px 960 \
        audio_height_px 220 \
        external_open 1 \
        external_open_command "" \
        image_open_command "" \
        pdf_open_command "" \
        audio_open_command "" \
        binary_open_command ""]
}

proc ::GX::previewSettingsPath {} {
    # Working Directory Profiles owns the framework's authoritative XDG/HOME
    # configuration resolver. Keep preview settings in that same user-local
    # directory instead of duplicating the environment fallback rules here.
    return [file join [file dirname [workspaceProfilesPath]] dataset_preview.ini]
}

proc ::GX::previewSettingsWriteDefaults {} {
    set path [previewSettingsPath]
    file mkdir [file dirname $path]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Dataset Preview API v1 user settings"
    puts $fd "; This file is intentionally user-local and may be edited manually."
    puts $fd "; A future GUI may expose these values without changing their storage contract."
    puts $fd "\[preview\]"
    dict for {key value} [previewSettingsDefaults] { putKV $fd $key $value }
    close $fd
    return $path
}

proc ::GX::previewSettingsNormalize {key value default} {
    switch -- $key {
        table_rows - table_columns - max_cell_chars - metadata_fields - metadata_value_chars -
        image_width_px - image_height_px - image_max_source_bytes - pdf_width_px -
        audio_preview_seconds - audio_width_px - audio_height_px {
            if {![string is integer -strict $value] || $value < 1} { return $default }
            return $value
        }
        image_inline - pdf_thumbnail - audio_waveform - external_open {
            set v [string tolower [string trim $value]]
            if {$v in {1 true yes on}} { return 1 }
            if {$v in {0 false no off}} { return 0 }
            return $default
        }
        image_thumbnailer {
            set v [string tolower [string trim $value]]
            if {$v ni {auto magick none}} { return $default }
            return $v
        }
        pdf_renderer {
            set v [string tolower [string trim $value]]
            if {$v ni {auto pdftoppm mutool none}} { return $default }
            return $v
        }
        audio_renderer {
            set v [string tolower [string trim $value]]
            if {$v ni {auto ffmpeg none}} { return $default }
            return $v
        }
        default { return [string trim $value] }
    }
}

proc ::GX::previewSettingsLoad {{force 0}} {
    variable previewSettings
    variable previewSettingsLoaded
    if {$previewSettingsLoaded && !$force} { return [array get previewSettings] }
    array unset previewSettings *
    set defaults [previewSettingsDefaults]
    dict for {key value} $defaults { set previewSettings($key) $value }
    set path [previewSettingsPath]
    if {![file isfile $path]} { previewSettingsWriteDefaults }
    if {[file isfile $path]} {
        if {![catch {set parsed [parseIni $path]}]} {
            dict for {key default} $defaults {
                set iniKey "preview.$key"
                if {[dict exists $parsed $iniKey]} {
                    set previewSettings($key) [previewSettingsNormalize $key [dict get $parsed $iniKey] $default]
                }
            }
        }
    }
    set previewSettingsLoaded 1
    return [array get previewSettings]
}

proc ::GX::previewSetting {key} {
    variable previewSettings
    previewSettingsLoad
    if {![info exists previewSettings($key)]} { error "Unknown Dataset Preview setting '$key'." }
    return $previewSettings($key)
}

proc ::GX::datasetPreviewHumanBytes {n} {
    if {![string is wideinteger -strict $n] || $n < 0} { return "$n bytes" }
    set value [expr {double($n)}]
    foreach unit {B KiB MiB GiB TiB} {
        if {$value < 1024.0 || $unit eq "TiB"} {
            if {$unit eq "B"} { return "[format %.0f $value] B" }
            return "[format %.2f $value] $unit"
        }
        set value [expr {$value / 1024.0}]
    }
}

proc ::GX::datasetPreviewTruncate {value limit} {
    set value [string map [list "\r\n" " " "\n" " " "\r" " "] $value]
    if {[string length $value] <= $limit} { return $value }
    return "[string range $value 0 [expr {$limit-2}]]…"
}

proc ::GX::datasetPreviewMediaClass {mediaType format contract path} {
    set media [string tolower [string trim $mediaType]]
    set format [string tolower [string trim $format]]
    set contract [string tolower [string trim $contract]]
    if {[string match "spectrum.*" $contract]} { return spectrum }
    if {[string match "*mesh*" $contract] || $format in {stl obj step stp}} { return mesh }
    if {[string match "video/*" $media] || [string match "video.*" $contract]} { return video }
    if {[string match "image/*" $media] || [string match "image.*" $contract]} { return image }
    if {$media eq "application/pdf" || $format eq "pdf" || $contract eq "document.pdf"} { return pdf }
    if {[string match "audio/*" $media] || [string match "audio.*" $contract] || [string match "audio*" $format]} { return audio }
    if {$media in {text/csv text/plain application/json application/xml text/xml} || [string match "text/*" $media]} { return text }
    if {$path ne ""} {
        set ext [string tolower [file extension $path]]
        if {$ext in {.png .jpg .jpeg .gif .bmp .tif .tiff .webp}} { return image }
        if {$ext eq ".pdf"} { return pdf }
        if {$ext in {.wav .flac .mp3 .ogg .oga .opus .m4a .aac .aiff .aif .pcm}} { return audio }
        if {$ext in {.mp4 .mov .mkv .avi .webm}} { return video }
        if {$ext in {.stl .obj .step .stp}} { return mesh }
    }
    return binary
}

proc ::GX::datasetPreviewResolveViewer {mediaType format contract path} {
    set class [datasetPreviewMediaClass $mediaType $format $contract $path]
    set preference auto
    if {[llength [info commands ::GX::configurationGet]]} {
        catch {set preference [configurationGet viewers.$class]}
    }
    set preference [string trim $preference]
    if {[regexp {^gxtxt:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$} $preference -> moduleId viewerId]} {
        return [dict create class $class mode viewer module_id $moduleId viewer_id $viewerId]
    }
    if {$preference eq "internal"} { return [dict create class $class mode preview] }
    if {$preference eq "system"} { return [dict create class $class mode system] }
    if {$preference ne "auto" && $preference ne ""} {
        if {[catch {llength $preference}]} { set preference [list $preference] }
        return [dict create class $class mode external command $preference]
    }
    if {$class eq "spectrum" && [moduleField viewer.spectral_library descriptor ""] ne "" && [moduleIsEnabled viewer.spectral_library]} {
        return [dict create class $class mode viewer module_id viewer.spectral_library viewer_id spectral_library]
    }
    if {$class eq "mesh" && [moduleField viewer.engine_3d descriptor ""] ne "" && [moduleIsEnabled viewer.engine_3d]} {
        if {[file isfile [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so]]} {
            return [dict create class $class mode viewer module_id viewer.engine_3d viewer_id engine_3d]
        }
    }
    if {$class eq "mesh" && [moduleField viewer.native_3d descriptor ""] ne "" && [moduleIsEnabled viewer.native_3d]} {
        return [dict create class $class mode viewer module_id viewer.native_3d viewer_id native_3d]
    }
    if {$class eq "video"} { return [dict create class $class mode system] }
    return [dict create class $class mode preview]
}

proc ::GX::datasetPreviewSetCurrentFile {path mediaType {contract ""} {format ""}} {
    variable previewCurrentPath
    variable previewCurrentMediaType
    variable previewCurrentContract
    variable previewCurrentFormat
    set previewCurrentPath ""
    set previewCurrentMediaType [string trim $mediaType]
    set previewCurrentContract [string trim $contract]
    set previewCurrentFormat [string trim $format]
    if {$path ne "" && [file isfile $path]} { set previewCurrentPath [file normalize $path] }
    datasetPreviewUpdateOpenButton
}

proc ::GX::datasetPreviewUpdateOpenButton {} {
    variable ui
    variable previewCurrentPath
    if {![info exists ui(datasetPreviewOpenButton)] || ![winfo exists $ui(datasetPreviewOpenButton)]} { return }
    set enabled [expr {$previewCurrentPath ne "" && [file isfile $previewCurrentPath]}]
    catch {$ui(datasetPreviewOpenButton) state [expr {$enabled ? "!disabled" : "disabled"}]}
}

proc ::GX::datasetPreviewConfiguredOpenCommand {mediaClass {systemOnly 0}} {
    if {!$systemOnly && [llength [info commands ::GX::configurationGet]] &&
        ![catch {set configured [configurationGet viewers.$mediaClass]}] &&
        $configured ne "" && $configured ni {auto system internal}} {
        # Viewer associations use argv-prefix lists, matching the established
        # Dataset Preview setting contract. Never invoke a shell here.
        return $configured
    }
    if {!$systemOnly} {
        set key binary_open_command
        if {$mediaClass eq "image"} { set key image_open_command }
        if {$mediaClass eq "pdf"} { set key pdf_open_command }
        if {$mediaClass eq "audio"} { set key audio_open_command }
        set value [string trim [previewSetting $key]]
        if {$value eq ""} { set value [string trim [previewSetting external_open_command]] }
        if {$value ne ""} {
            if {[catch {llength $value}]} { return [list $value] }
            return $value
        }
    }
    if {$::tcl_platform(platform) eq "windows"} {
        set exe [auto_execok explorer.exe]
        if {$exe ne ""} { return [list $exe] }
    } elseif {$::tcl_platform(os) eq "Darwin"} {
        set exe [auto_execok open]
        if {$exe ne ""} { return [list $exe] }
    } else {
        set exe [auto_execok xdg-open]
        if {$exe ne ""} { return [list $exe] }
        set exe [auto_execok gio]
        if {$exe ne ""} { return [list $exe open] }
    }
    return {}
}

proc ::GX::datasetPreviewOpenCurrent {} {
    variable previewCurrentPath
    variable previewCurrentMediaType
    variable previewCurrentContract
    variable previewCurrentFormat
    set path $previewCurrentPath
    if {$path eq "" || ![file isfile $path]} {
        if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message "No preview file is available to open." }
        return
    }
    set identity [file tail $path]
    foreach id [sessionInspectionDatasetIds $::GX::currentSession] {if {[file normalize [file join $::GX::currentSession [datasetField $id path {}]]] eq [file normalize $path]} {set identity $id;break}}
    if {$previewCurrentContract eq "document.pdf" || $previewCurrentMediaType eq "application/pdf"} {return [pdfDatasetOpen $path $identity]}
    if {$previewCurrentContract eq "geometry.sketch"} {
        viewerOpen viewer.curve_workbench curve_workbench [dict create sketch_dataset_id $identity]
        return
    }
    set resolution [datasetPreviewResolveViewer $previewCurrentMediaType $previewCurrentFormat $previewCurrentContract $path]
    set mode [dict get $resolution mode]
    if {$mode eq "preview"} {
        catch {.top.nb select .top.nb.channels;.top.nb.channels.views select .top.nb.channels.views.preview}
        return $resolution
    }
    if {$mode eq "viewer"} {
        viewerOpen [dict get $resolution module_id] [dict get $resolution viewer_id] \
            [dict create source_path $path media_type $previewCurrentMediaType \
                contract $previewCurrentContract format $previewCurrentFormat]
        return $resolution
    }
    if {![previewSetting external_open]} { error "External Dataset opening is disabled in Dataset Preview settings." }
    set cls [dict get $resolution class]
    set command [expr {$mode eq "external" ? [dict get $resolution command] : [datasetPreviewConfiguredOpenCommand $cls 1]}]
    if {![llength $command]} {
        set message "No system opener is available. Configure the $cls association in Configuration > Viewers."
        if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message $message } else { error $message }
        return
    }
    if {[catch {exec {*}$command $path &} err]} {
        if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message "Could not open the file with the system application:\n$err" } else { error $err }
    }
}

proc ::GX::datasetPreviewTool {name} {
    if {$name in {ffmpeg magick pdftoppm mutool} && [llength [info commands ::GX::runtimeToolResolve]]} {
        if {[catch {set p [runtimeToolResolve $name]}]} { set p "" }
    } else {
        set p [auto_execok $name]
    }
    if {$p eq "" && $name eq "magick" && [file executable /opt/imagemagick/bin/magick]} { set p /opt/imagemagick/bin/magick }
    return $p
}

proc ::GX::datasetPreviewImageArtifact {path previewDir} {
    if {![previewSetting image_inline]} { return [dict create] }
    if {[file size $path] > [previewSetting image_max_source_bytes]} { return [dict create] }
    set mode [previewSetting image_thumbnailer]
    if {$mode eq "none"} { return [dict create] }
    set out [file join $previewDir image-preview.png]
    set magick [datasetPreviewTool magick]
    if {$mode in {auto magick} && $magick ne ""} {
        set geometry "[previewSetting image_width_px]x[previewSetting image_height_px]>"
        if {![catch {exec $magick $path -auto-orient -thumbnail $geometry $out 2>@1}] && [file isfile $out]} {
            return [dict create path $out media_type image/png label "Image preview"]
        }
    }
    set ext [string tolower [file extension $path]]
    if {$ext in {.png .gif .ppm .pgm}} {
        set fallback [file join $previewDir "image-preview$ext"]
        file copy -force -- $path $fallback
        set mt [expr {$ext eq ".png" ? "image/png" : ($ext eq ".gif" ? "image/gif" : "image/x-portable-pixmap")}]
        return [dict create path $fallback media_type $mt label "Image preview"]
    }
    return [dict create]
}

proc ::GX::datasetPreviewPdfArtifact {path previewDir} {
    if {![previewSetting pdf_thumbnail]} { return [dict create] }
    set mode [previewSetting pdf_renderer]
    if {$mode eq "none"} { return [dict create] }
    set width [previewSetting pdf_width_px]
    if {$mode in {auto pdftoppm}} {
        set tool [datasetPreviewTool pdftoppm]
        if {$tool ne ""} {
            set base [file join $previewDir pdf-page-1]
            if {![catch {exec $tool -f 1 -singlefile -png -scale-to $width $path $base 2>@1}] && [file isfile "${base}.png"]} {
                return [dict create path "${base}.png" media_type image/png label "PDF first page"]
            }
        }
    }
    if {$mode in {auto mutool}} {
        set tool [datasetPreviewTool mutool]
        if {$tool ne ""} {
            set out [file join $previewDir pdf-page-1.png]
            if {![catch {exec $tool draw -q -F png -w $width -o $out $path 1 2>@1}] && [file isfile $out]} {
                return [dict create path $out media_type image/png label "PDF first page"]
            }
        }
    }
    return [dict create]
}

proc ::GX::datasetPreviewAudioArtifact {path previewDir} {
    if {![previewSetting audio_waveform]} { return [dict create] }
    set mode [previewSetting audio_renderer]
    if {$mode eq "none"} { return [dict create] }
    set tool [datasetPreviewTool ffmpeg]
    if {$tool eq ""} { return [dict create] }
    set out [file join $previewDir audio-waveform.png]
    set size "[previewSetting audio_width_px]x[previewSetting audio_height_px]"
    set seconds [previewSetting audio_preview_seconds]
    set filter "aresample=48000,aformat=channel_layouts=mono,showwavespic=s=$size:colors=black"
    set nullInput [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
    if {![catch {exec $tool -nostdin -v error -y -i $path -t $seconds -filter_complex $filter -frames:v 1 $out < $nullInput 2>@1}] && [file isfile $out]} {
        return [dict create path $out media_type image/png label "Audio waveform (first $seconds s)"]
    }
    return [dict create]
}

proc ::GX::datasetPreviewMediaArtifact {path mediaType format contract previewDir} {
    if {$contract eq "geometry.sketch"} {
        set image [file join $previewDir sketch.png]
        sketchDatasetPreview $path $image
        return [dict create media_type image/png path $image label {Sketch geometry}]
    }
    if {$path eq "" || ![file isfile $path]} { return [dict create] }
    switch -- [datasetPreviewMediaClass $mediaType $format $contract $path] {
        image { return [datasetPreviewImageArtifact $path $previewDir] }
        pdf { return [datasetPreviewPdfArtifact $path $previewDir] }
        audio { return [datasetPreviewAudioArtifact $path $previewDir] }
    }
    return [dict create]
}

proc ::GX::datasetPreviewTableSnapshot {session datasetId {maxRows ""} {maxColumns ""}} {
    if {$maxRows eq ""} { set maxRows [previewSetting table_rows] }
    if {$maxColumns eq ""} { set maxColumns [previewSetting table_columns] }
    set access ""
    set stream ""
    try {
        set access [datasetAccessOpen $session $datasetId]
        set metadata [datasetAccessMetadata $access]
        set variables [dict get $metadata variables]
        if {![llength $variables]} { return [dict create available 0 reason "Dataset has no tabular variables."] }
        set variableIds {}
        set selectedVariables {}
        foreach variable $variables {
            if {[dict get $variable rank] != 1} continue
            lappend variableIds [dict get $variable variable_id]
            lappend selectedVariables $variable
            if {[llength $variableIds] >= $maxColumns} break
        }
        if {![llength $variableIds]} { return [dict create available 0 reason "Dataset variables are not table-shaped."] }
        datasetAccessClose $access
        set access ""
        set stream [tableStreamOpenDataset $session $datasetId $variableIds $maxRows [dict create start 0 count -1 numeric_transport values]]
        set smeta [tableStreamMetadata $stream]
        set chunk [tableStreamNext $stream]
        set columns {}
        foreach variable [dict get $smeta variables] {
            set label [string trim [dict get $variable display_label]]
            if {$label eq ""} { set label [string trim [dict get $variable canonical]] }
            if {$label eq ""} { set label [dict get $variable variable_id] }
            lappend columns [dict create variable_id [dict get $variable variable_id] label $label unit [dict get $variable unit] dtype [dict get $variable dtype]]
        }
        set rows {}
        set nrows [dict get $chunk row_count]
        for {set r 0} {$r < $nrows} {incr r} {
            set row {}
            foreach column $columns {
                set vid [dict get $column variable_id]
                set values [dict get $chunk values $vid]
                lappend row [expr {$r < [llength $values] ? [lindex $values $r] : ""}]
            }
            lappend rows $row
        }
        return [dict create available 1 storage_provider [dict get $smeta storage_provider] row_count [dict get $smeta row_count] columns $columns rows $rows total_variable_count [llength $variables] selected_variable_count [llength $columns]]
    } finally {
        if {$stream ne ""} { catch {tableStreamClose $stream} }
        if {$access ne ""} { catch {datasetAccessClose $access} }
    }
}

proc ::GX::datasetPreviewRenderSchema {w datasetId} {
    if {[catch {set variables [datasetVariableSchemaV3 $datasetId]}]} { return }
    if {![llength $variables]} { return }
    $w insert end "\nVARIABLE SCHEMA\n===============\n"
    $w insert end [format "%-24s %-10s %-14s %-12s %-20s\n" "Variable" "dtype" "shape" "unit" "semantic role"]
    $w insert end [string repeat "-" 86]
    $w insert end "\n"
    foreach variable $variables {
        set name [string trim [dict get $variable canonical]]
        if {$name eq ""} { set name [dict get $variable variable_id] }
        $w insert end [format "%-24s %-10s %-14s %-12s %-20s\n" \
            [datasetPreviewTruncate $name 24] \
            [dict get $variable dtype] \
            [datasetPreviewTruncate [dict get $variable shape] 14] \
            [datasetPreviewTruncate [dict get $variable unit] 12] \
            [datasetPreviewTruncate [dict get $variable semantic_role] 20]]
    }
}

proc ::GX::datasetPreviewRenderTableSnapshot {w snapshot} {
    if {![dict get $snapshot available]} { return 0 }
    $w insert end "\nCANONICAL DATA SAMPLE\n=====================\n"
    $w insert end "Storage provider: [dict get $snapshot storage_provider]\n"
    set rows [dict get $snapshot row_count]
    if {$rows >= 0} { $w insert end "Dataset rows: $rows\n" }
    if {[dict get $snapshot total_variable_count] > [dict get $snapshot selected_variable_count]} {
        $w insert end "Columns shown: [dict get $snapshot selected_variable_count] of [dict get $snapshot total_variable_count]\n"
    }
    set headers {}
    foreach column [dict get $snapshot columns] {
        set label [dict get $column label]
        set unit [string trim [dict get $column unit]]
        if {$unit ne ""} { append label [format { [%s]} $unit] }
        lappend headers [datasetPreviewTruncate $label [previewSetting max_cell_chars]]
    }
    set headerLine [join $headers { | }]
    $w insert end "$headerLine\n"
    set dashLength [string length $headerLine]
    if {$dashLength < 24} { set dashLength 24 }
    if {$dashLength > 140} { set dashLength 140 }
    $w insert end [string repeat "-" $dashLength]
    $w insert end "\n"
    set index 0
    foreach row [dict get $snapshot rows] {
        incr index
        set cells {}
        foreach value $row { lappend cells [datasetPreviewTruncate $value [previewSetting max_cell_chars]] }
        $w insert end [format "ROW %-4d %s\n" $index [join $cells { | }]]
    }
    return 1
}

proc ::GX::datasetPreviewRenderMetadata {w session datasetId} {
    if {[catch {set md [datasetMetadataRead $session $datasetId]}] || ![dict size $md]} { return }
    $w insert end "\nDATASET METADATA\n================\n"
    set keys [lsort -dictionary [dict keys $md]]
    set limit [previewSetting metadata_fields]
    set shown 0
    foreach key $keys {
        if {$shown >= $limit} break
        incr shown
        $w insert end [format "%-30s %s\n" $key [datasetPreviewTruncate [dict get $md $key] [previewSetting metadata_value_chars]]]
    }
    if {[llength $keys] > $shown} { $w insert end "... [expr {[llength $keys]-$shown}] additional metadata field(s) not shown.\n" }
}

proc ::GX::datasetPreviewRenderImported {w datasetId} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "No Session is open." }
    loadDatasetRegistry $currentSession
    if {[datasetField $datasetId id ""] eq ""} { error "Unknown dataset: $datasetId" }
    set path [datasetResolvePath $currentSession $datasetId]
    set contract [datasetField $datasetId kind ""]
    set format [datasetField $datasetId format ""]
    set storageKind [string tolower [datasetField $datasetId storage_kind "text"]]
    set mediaType [datasetField $datasetId media_type ""]
    set provider [datasetField $datasetId storage_provider ""]
    set mediaClass [datasetPreviewMediaClass $mediaType $format $contract $path]
    datasetPreviewSetCurrentFile $path $mediaType $contract $format
    previewDescriptorClearWidgetArtifact $w
    $w configure -state normal
    $w delete 1.0 end
    $w insert end "DATASET PREVIEW\n===============\n"
    $w insert end "State:       IMPORTED\n"
    $w insert end "Dataset ID:  $datasetId\n"
    $w insert end "Contract:    $contract\n"
    $w insert end "Format:      $format\n"
    $w insert end "Storage:     $storageKind"
    if {$provider ne ""} { $w insert end " / $provider" }
    $w insert end "\n"
    if {$mediaType ne ""} { $w insert end "Media type:  $mediaType\n" }
    if {$path ne ""} {
        $w insert end "File:        $path\n"
        if {[file isfile $path]} { $w insert end "Size:        [datasetPreviewHumanBytes [file size $path]] ([file size $path] bytes)\n" }
    }
    $w insert end "Preview mode: $mediaClass\n"
    if {[string tolower $format] in {stl obj step stp vti vtp vtu}} {
        $w insert end [datasetPreview3DInfo $path $format]
    }

    datasetPreviewRenderSchema $w $datasetId
    if {![catch {set snapshot [datasetPreviewTableSnapshot $currentSession $datasetId]}]} {
        datasetPreviewRenderTableSnapshot $w $snapshot
    }

    set previewDir [previewDescriptorCreateTempDir]
    try {
        # Reuse a module-supplied descriptor when available, but CORE remains
        # responsible for a generic fallback so future binary formats are not
        # forced to implement a private preview UI.
        set modulePreview [dict create]
        set moduleHasArtifact 0
        catch {set modulePreview [acquisitionHandlerDatasetPreview $datasetId $previewDir]}
        if {[dict size $modulePreview]} {
            if {![catch {set pd [previewDescriptorNormalize $modulePreview $previewDir]} perr]} {
                set moduleHasArtifact [expr {[lsearch -exact [dict get $pd kinds] artifact] >= 0}]
                previewDescriptorRenderTextWidget $w $pd
            } else {
                $w insert end "\nPREVIEW PROVIDER DIAGNOSTIC\n===========================\n$perr\n"
            }
        }

        datasetPreviewRenderMetadata $w $currentSession $datasetId

        set artifact [dict create]
        if {!$moduleHasArtifact} {
            set artifact [datasetPreviewMediaArtifact $path $mediaType $format $contract $previewDir]
        }
        if {[dict size $artifact]} {
            set pd [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact $artifact] $previewDir]
            previewDescriptorRenderTextWidget $w $pd
        } elseif {$storageKind eq "binary" && $mediaClass eq "binary"} {
            $w insert end "\nBINARY DATASET\n==============\nRaw bytes are intentionally not rendered. Use the canonical data sample above when the Dataset is table-shaped, or Open with system app for the registered storage object.\n"
        } elseif {$mediaClass in {image pdf audio}} {
            $w insert end "\nVISUAL PREVIEW\n==============\nNo inline preview could be generated with the currently available/configured renderer. The original registered Dataset remains available through Open with system app.\n"
        }
    } finally {
        previewDescriptorCleanupDir $previewDir
    }
    $w insert end "\nThe registered Dataset payload is never rewritten to create this preview. Media thumbnails/waveforms are temporary derived artifacts.\n"
    $w configure -state disabled
}

proc ::GX::datasetPreview3DInfo {path format} {
    set format [string tolower $format]
    set out "\n3-D OBJECT SUMMARY\n==================\n"
    if {![file isfile $path]} {return "${out}Payload is unavailable.\n"}
    append out "Format: [string toupper $format]\nSize: [datasetPreviewHumanBytes [file size $path]]\n"
    if {$format in {step stp}} {
        append out "STEP reconstruction is deferred to Native 3D Viewer.\n"
        return $out
    }
    if {[file size $path] > 16777216} {
        append out "Large geometry: metadata-only preview; open Native 3D Viewer for the object.\n"
        return $out
    }
    if {[catch {
        set fd [open $path rb]
        try {set bytes [read $fd 4194304]} finally {close $fd}
    }]} {return "${out}Source could not be read for a lightweight summary.\n"}
    switch -- $format {
        obj {
            set vertices [regexp -all -line {^v[[:space:]]+} $bytes]
            set faces [regexp -all -line {^f[[:space:]]+} $bytes]
            append out "Vertices in sampled text: $vertices\nFaces in sampled text: $faces\n"
        }
        stl {
            if {[string match -nocase {solid*} [string range $bytes 0 4]]} {
                append out "ASCII facet markers in sample: [regexp -all -nocase {facet[[:space:]]+normal} $bytes]\n"
            } else {append out "Binary STL; geometry is available in Native 3D Viewer.\n"}
        }
        vti - vtp - vtu {
            set header [string range $bytes 0 16383]
            foreach {attribute label} {WholeExtent {Grid extent} RangeMin {Declared scalar minimum} RangeMax {Declared scalar maximum}} {
                if {[regexp -nocase [format {%s="([^"]+)"} $attribute] $header -> value]} {append out "$label: $value\n"}
            }
            append out "No isovalue is inferred for this preview.\n"
        }
    }
    return $out
}

# Replace the imported-Dataset branch only. Pending/single-source CSV behavior
# remains the established implementation until import creates a canonical Dataset.
proc ::GX::datasetInspectionRenderPreview {w choice} {
    lassign [datasetInspectionParseChoice $choice] mode key
    if {$mode eq "imported" && $key ne ""} {
        set storageKind [string tolower [datasetField $key storage_kind "text"]]
        set format [string tolower [datasetField $key format "csv"]]
        # Preserve the established CSV/text preview verbatim.  The generic
        # Dataset preview takes over only when the registered representation is
        # binary or not CSV, which is exactly the gap this API is intended to fill.
        if {$storageKind eq "binary" || $format ne "csv"} {
            return [datasetPreviewRenderImported $w $key]
        }
    }
    set result [::GX::datasetInspectionRenderPreview_before_dataset_preview_v1 $w $choice]
    if {![catch {set info [datasetInspectionSelectedInfo $choice]}] && [dict exists $info path]} {
        set p [dict get $info path]
        datasetPreviewSetCurrentFile $p "" [expr {[dict exists $info contract] ? [dict get $info contract] : ""}]
    }
    return $result
}

# Pending binary/plugin sources already use Acquisition Handler inspection.
# Keep that behavior and make the same source available to the system opener.
proc ::GX::acquisitionHandlerPreviewPlugin {moduleId sourcePath} {
    variable ui
    set result [::GX::acquisitionHandlerPreviewPlugin_before_dataset_preview_v1 $moduleId $sourcePath]
    set media ""
    set format ""
    set inspected [dict create]
    if {$sourcePath ne "" && [file isfile $sourcePath]} {
        set previewDir [previewDescriptorCreateTempDir]
        try {
            if {![catch {set inspected [acquisitionHandlerInspect $moduleId $sourcePath $previewDir]}]} {
                if {[dict exists $inspected format]} { set format [dict get $inspected format] }
                if {[dict exists $inspected metadata "Media Type"]} { set media [dict get $inspected metadata "Media Type"] }
                if {$media eq "" && [dict exists $inspected preview_metadata "Media Type"]} { set media [dict get $inspected preview_metadata "Media Type"] }
                set providerHasArtifact 0
                if {![catch {set pd [previewDescriptorNormalize $inspected $previewDir]}]} {
                    set providerHasArtifact [expr {[lsearch -exact [dict get $pd kinds] artifact] >= 0}]
                }
                if {!$providerHasArtifact && [info exists ui(preview)] && [winfo exists $ui(preview)]} {
                    set artifact [datasetPreviewMediaArtifact $sourcePath $media $format "" $previewDir]
                    if {[dict size $artifact]} {
                        set w $ui(preview)
                        $w configure -state normal
                        set pd [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact $artifact] $previewDir]
                        previewDescriptorRenderTextWidget $w $pd
                        $w configure -state disabled
                    }
                }
            }
        } finally {
            previewDescriptorCleanupDir $previewDir
        }
    }
    datasetPreviewSetCurrentFile $sourcePath $media "" $format
    return $result
}

proc ::GX::buildDatasetPreviewGui {} {
    previewSettingsLoad
    datasetPreviewUpdateOpenButton
}

proc ::GX::augmentStandardGui_before_documentation_browser {} {
    ::GX::augmentStandardGui_before_dataset_preview_v1
    buildDatasetPreviewGui
}

# A Session may retain acq.rigol_csv while the selected Dataset is audio/PDF.
# In that state the old preview fed binary bytes to gets/CSV parsing, which can
# allocate an unbounded line and stall Tk. Sniff at most 64 KiB before routing.
proc ::GX::datasetPreviewUnsafeTextInput {path} {
    if {$path eq "" || ![file isfile $path]} { return 0 }
    set ext [string tolower [file extension $path]]
    if {$ext in {.wav .wave .mp3 .flac .ogg .opus .aac .m4a .pdf .png .jpg .jpeg .gif .tif .tiff .bmp .h5 .hdf5 .zip .gz .raw .pcm .bin}} { return 1 }
    if {[catch {
        set f [open $path rb]
        try { set sample [read $f 65536] } finally { close $f }
    }]} { return 1 }
    if {[string first "\x00" $sample] >= 0} { return 1 }
    if {[file size $path] > 65536 && [string first "\n" $sample] < 0} { return 1 }
    set controls 0
    binary scan $sample c* bytes
    foreach b $bytes {
        set b [expr {$b & 255}]
        if {$b < 32 && $b ni {9 10 13}} { incr controls }
    }
    return [expr {[llength $bytes] > 0 && $controls * 100 > [llength $bytes]}]
}

namespace eval ::GX {
    variable previewBinaryTaskPath ""
    variable previewBinaryTaskDir ""
    variable previewBinaryTaskOutput ""
    variable previewBinaryTaskPids {}
    variable previewBinaryTaskStarted 0
    variable previewBinaryTaskState ""
    variable previewBinaryTaskMedia ""
}

proc ::GX::datasetPreviewBinaryTaskStop {} {
    variable previewBinaryTaskDir
    variable previewBinaryTaskPids
    variable previewBinaryTaskPath
    variable previewBinaryTaskOutput
    variable previewBinaryTaskState
    foreach key {previewBinaryPoll previewBinaryExpiry} {
        if {[info exists ::GX::ui($key)]} {after cancel $::GX::ui($key);unset ::GX::ui($key)}
    }
    foreach pid $previewBinaryTaskPids { catch {exec kill -TERM -- $pid} }
    if {$previewBinaryTaskDir ne ""} { catch {file delete -force -- $previewBinaryTaskDir} }
    set previewBinaryTaskPids {}
    set previewBinaryTaskDir ""
    set previewBinaryTaskPath ""
    set previewBinaryTaskOutput ""
    set previewBinaryTaskState ""
}

proc ::GX::datasetPreviewBinaryArtifactShow {} {
    variable ui
    variable previewBinaryTaskDir
    variable previewBinaryTaskOutput
    variable previewBinaryTaskMedia
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)] || ![file isfile $previewBinaryTaskOutput]} return
    set w $ui(preview)
    set artifact [dict create path $previewBinaryTaskOutput media_type image/png label "$previewBinaryTaskMedia preview"]
    if {[catch {set descriptor [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact $artifact] $previewBinaryTaskDir]}]} return
    $w configure -state normal
    previewDescriptorRenderTextWidget $w $descriptor
    $w configure -state disabled
}

proc ::GX::datasetPreviewBinaryTaskExpire {path dir} {
    variable previewBinaryTaskPath
    variable previewBinaryTaskDir
    if {$previewBinaryTaskPath eq $path && $previewBinaryTaskDir eq $dir} {
        datasetPreviewBinaryTaskStop
    }
}

proc ::GX::datasetPreviewBinaryArtifactPoll {path} {
    variable ui
    variable previewBinaryTaskPath
    variable previewBinaryTaskOutput
    variable previewBinaryTaskPids
    variable previewBinaryTaskStarted
    variable previewBinaryTaskState
    unset -nocomplain ui(previewBinaryPoll)
    if {$path ne $previewBinaryTaskPath || $previewBinaryTaskState ne "running"} return
    if {$ui(previewBinaryEpoch)!=$ui(previewEpoch) || $ui(previewBinaryStamp) ne [datasetPreviewStamp]} {datasetPreviewBinaryTaskStop;return}
    set alive 0
    foreach pid $previewBinaryTaskPids { if {![catch {exec kill -0 -- $pid}]} { set alive 1 } }
    if {$alive && [clock milliseconds] - $previewBinaryTaskStarted < 15000} {
        set ui(previewBinaryPoll) [after 100 [list ::GX::datasetPreviewBinaryArtifactPoll $path]]
        return
    }
    if {$alive} { foreach pid $previewBinaryTaskPids { catch {exec kill -TERM -- $pid} } }
    set previewBinaryTaskPids {}
    if {[file isfile $previewBinaryTaskOutput] && [file size $previewBinaryTaskOutput] > 100} {
        set previewBinaryTaskState ready
        if {[info exists ui(preview)] && [winfo exists $ui(preview)]} { catch {datasetPreviewBinaryArtifactShow} }
    } else {
        set previewBinaryTaskState failed
        if {[info exists ui(preview)] && [winfo exists $ui(preview)]} {
            set w $ui(preview)
            $w configure -state normal
            $w insert end "\nA visual sample could not be generated. The source file remains available through Open with system app.\n"
            $w configure -state disabled
        }
    }
    datasetPreviewActionsState
    set ui(previewBinaryExpiry) [after 300000 [list ::GX::datasetPreviewBinaryTaskExpire $previewBinaryTaskPath $::GX::previewBinaryTaskDir]]
}

proc ::GX::datasetPreviewBinaryArtifactStart {path class} {
    variable previewBinaryTaskPath
    variable previewBinaryTaskDir
    variable previewBinaryTaskOutput
    variable previewBinaryTaskPids
    variable previewBinaryTaskStarted
    variable previewBinaryTaskState
    variable previewBinaryTaskMedia
    if {$previewBinaryTaskPath eq $path} {
        if {$previewBinaryTaskState eq "ready"} { datasetPreviewBinaryArtifactShow }
        if {$previewBinaryTaskState ne "failed"} { return }
    }
    datasetPreviewBinaryTaskStop
    set cmd {}
    set dir [previewDescriptorCreateTempDir]
    set out [file join $dir preview.png]
    if {$class eq "audio" && [previewSetting audio_waveform]} {
        set tool [datasetPreviewTool ffmpeg]
        if {$tool ne ""} {
            set size "[previewSetting audio_width_px]x[previewSetting audio_height_px]"
            set seconds [expr {min(10, [previewSetting audio_preview_seconds])}]
            set filter "aresample=24000,aformat=channel_layouts=mono,showwavespic=s=$size:colors=black"
            set cmd [list $tool -nostdin -v error -threads 1 -y -i $path -t $seconds -filter_complex $filter -frames:v 1 $out]
        }
    } elseif {$class eq "pdf" && [previewSetting pdf_thumbnail]} {
        set tool [datasetPreviewTool pdftoppm]
        if {$tool ne ""} {
            set base [file join $dir preview]
            set cmd [list $tool -f 1 -singlefile -png -scale-to [previewSetting pdf_width_px] $path $base]
        }
    } elseif {$class eq "image" && [previewSetting image_inline] && [file size $path] <= [previewSetting image_max_source_bytes]} {
        set tool [datasetPreviewTool magick]
        if {$tool ne ""} {
            set geometry "[previewSetting image_width_px]x[previewSetting image_height_px]>"
            set cmd [list $tool $path -auto-orient -thumbnail $geometry $out]
        }
    }
    if {![llength $cmd]} { catch {file delete -force -- $dir}; return }
    set log [file join $dir renderer.log]
    if {[catch {set pids [exec {*}$cmd > $log 2>@1 &]}]} { catch {file delete -force -- $dir}; return }
    set previewBinaryTaskPath $path
    set previewBinaryTaskDir $dir
    set previewBinaryTaskOutput $out
    set previewBinaryTaskPids $pids
    set previewBinaryTaskStarted [clock milliseconds]
    set previewBinaryTaskState running
    set previewBinaryTaskMedia $class
    set ::GX::ui(previewBinaryEpoch) $::GX::ui(previewEpoch)
    set ::GX::ui(previewBinaryStamp) [datasetPreviewStamp]
    set ::GX::ui(previewBinaryPoll) [after 100 [list ::GX::datasetPreviewBinaryArtifactPoll $path]]
}

proc ::GX::datasetPreviewSafeBinary {path {datasetId ""}} {
    variable ui
    variable currentSession
    variable cfg
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} return
    set w $ui(preview)
    previewDescriptorClearWidgetArtifact $w
    $w configure -state normal
    $w delete 1.0 end
    set media ""
    set format ""
    if {$datasetId ne "" && $currentSession ne ""} {
        set media [datasetField $datasetId media_type ""]
        set format [datasetField $datasetId format ""]
    }
    set class [datasetPreviewMediaClass $media $format "" $path]
    datasetPreviewSetCurrentFile $path $media [expr {$datasetId ne "" ? [datasetField $datasetId kind ""] : ""}] $format
    $w insert end "BINARY DATASET PREVIEW\n======================\n"
    if {$datasetId ne ""} { $w insert end "Dataset:    $datasetId\n" }
    $w insert end "File:       [file normalize $path]\n"
    $w insert end "Size:       [datasetPreviewHumanBytes [file size $path]] ([file size $path] bytes)\n"
    $w insert end "Type:       $class"
    if {$media ne ""} { $w insert end " / $media" }
    $w insert end "\n\nBinary bytes are never rendered as CSV or text.\n"
    if {$datasetId ne ""} {
        $w insert end "\nREGISTERED DATASET\n==================\n"
        $w insert end "Format: [datasetField $datasetId format ""]\n"
        $w insert end "Contract: [datasetField $datasetId kind ""]\n"
        catch {datasetPreviewRenderSchema $w $datasetId}
        catch {datasetPreviewRenderMetadata $w $currentSession $datasetId}
    } else {
        set moduleId [expr {[info exists cfg(acquisition_module)] ? $cfg(acquisition_module) : ""}]
        if {($class eq "audio" && $moduleId in {acq.wav acq.audio}) ||
            ($class eq "pdf" && $moduleId eq "acq.pdf_document") ||
            ($class eq "image" && $moduleId eq "acq.image_binary")} {
            $w insert end "Acquisition module: $moduleId (selected). Import to register the full source as a Dataset.\n"
        } else {
            $w insert end "Select the acquisition module for this file type before import.\n"
        }
    }
    $w insert end "\nUse Open with system app for the complete file.\n"
    $w configure -state disabled
    datasetPreviewBinaryArtifactStart [file normalize $path] $class
}

# Guard both the button and tab entry points, independent of which acquisition
# module happens to be selected in the current Workspace.
proc ::GX::refreshCsvPreview {} {
    variable cfg
    variable csvPreviewDatasetChoice
    variable currentSession
    variable ui
    if {[info exists csvPreviewDatasetChoice] && $csvPreviewDatasetChoice ne ""} {
        lassign [datasetInspectionParseChoice $csvPreviewDatasetChoice] mode key
        if {$mode eq "imported" && $currentSession ne "" && [datasetField $key id ""] ne ""} {
            if {[dict get [datasetViewerDescribe $key] target] in {scientific mesh structure}} {return [datasetInspectionRenderPreview $ui(preview) $csvPreviewDatasetChoice]}
            set path [datasetResolvePath $currentSession $key]
            if {![catch {set page [datasetPreviewPage $currentSession $key [dict create count 10]]}] && [dict get $page available]} {
                return [datasetPreviewRenderImported $ui(preview) $key]
            }
            if {$path ne "" && [file isfile $path] &&
                ([datasetField $key storage_kind "text"] eq "binary" || [datasetPreviewUnsafeTextInput $path])} {
                return [datasetPreviewSafeBinary $path $key]
            }
            if {[info exists ui(preview)] && [winfo exists $ui(preview)]} {
                return [datasetInspectionRenderPreview $ui(preview) $csvPreviewDatasetChoice]
            }
        }
    }
    if {[info exists cfg(input_csv)] && [datasetPreviewUnsafeTextInput $cfg(input_csv)]} {
        return [datasetPreviewSafeBinary $cfg(input_csv)]
    }
    return [::GX::refreshCsvPreview_before_binary_guard_v1]
}

proc ::GX::ensureVariablesForCurrentInput {} {
    variable cfg
    if {[info exists cfg(input_csv)] && [datasetPreviewUnsafeTextInput $cfg(input_csv)]} { return }
    return [::GX::ensureVariablesForCurrentInput_before_binary_guard_v1]
}
