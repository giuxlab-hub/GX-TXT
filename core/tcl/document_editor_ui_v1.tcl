# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation helpers subordinate to the existing common document owner.
proc ::GX::_documentEditorDirty {record text} {
    expr {$text ne [dict get $record baseline_text] || [dict get $record assets] ne [datasetPublicationV2DictDefault [dict get $record baseline] assets {}]}
}
proc ::GX::_documentEditorHostCommand {handle operation} {
    set record [_documentEditorRecord $handle]
    set callback [dict get $record options on_command]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $operation]
    } elseif {[string match zoom_* $operation]} {documentEditorCommand $handle $operation}
}
proc ::GX::_documentEditorUiInit {handle} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];set parent [dict get $record parent]
    foreach key {source preview} {
        set widget [dict get $record $key];if {$widget eq {}} continue
        documentPresentationZoomAttach $widget [$widget cget -font]
        foreach {sequence operation} {<F8> zoom_in <F7> zoom_out <Control-0> zoom_reset} {
            bind $widget $sequence "[list ::GX::_documentEditorHostCommand $handle $operation];break"
        }
        if {$key eq {source} && [dict get $record options mode] eq {editable} && [dict get $record options on_command] ne {}} {
            foreach {sequence operation} {<Control-s> save_existing <Control-S> publish_new <Control-Shift-s> publish_new} {
                bind $widget $sequence "[list ::GX::_documentEditorHostCommand $handle $operation];break"
            }
        }
    }
    set pw $parent.editor.pw
    if {[winfo exists $pw]} {
        bind $pw <ButtonPress-1> +[list ::GX::_documentEditorSashPress $handle %x %y]
        bind $pw <ButtonRelease-1> +[list ::GX::_documentEditorSashRelease $handle]
        foreach event {<Map> <Configure>} {bind $pw $event +[list ::GX::_documentEditorSplittersSchedule $handle]}
        _documentEditorSplittersSchedule $handle
        foreach pane {outline properties resources} {
            ttk::frame $pw.$pane
            ttk::label $pw.$pane.title -text [string totitle $pane]
            pack $pw.$pane.title -side top -anchor w -padx 5 -pady 4
        }
        ttk::treeview $pw.outline.tree -show tree -selectmode browse -height 8
        bind $pw.outline.tree <<TreeviewSelect>> [list ::GX::_documentEditorOutlineSelect $handle]
        text $pw.properties.text -wrap word -state disabled -width 28 -exportselection 0
        pack $pw.properties.text -fill both -expand 1
        ttk::treeview $pw.resources.tree -columns {size dimensions} -show {tree headings} -selectmode browse -height 4
        $pw.resources.tree heading #0 -text Image;$pw.resources.tree heading size -text Bytes;$pw.resources.tree heading dimensions -text Dimensions
        $pw.resources.tree column #0 -width 130;$pw.resources.tree column size -width 65;$pw.resources.tree column dimensions -width 90
        foreach pane {outline resources} {
            set tree $pw.$pane.tree;set table $pw.$pane.table
            ttk::frame $table
            ttk::scrollbar $table.y -command [list $tree yview]
            ttk::scrollbar $table.x -orient horizontal -command [list $tree xview]
            $tree configure -yscrollcommand [list $table.y set] -xscrollcommand [list $table.x set]
            grid $tree -in $table -row 0 -column 0 -sticky nsew
            raise $tree
            grid $table.y -row 0 -column 1 -sticky ns
            grid $table.x -row 1 -column 0 -sticky ew
            grid rowconfigure $table 0 -weight 1;grid columnconfigure $table 0 -weight 1
            pack $table -fill both -expand 1
        }
        ttk::frame $pw.resources.actions
        foreach {operation title} {insert_image Add replace_image Replace remove_image Remove} {
            ttk::button $pw.resources.actions.$operation -text $title -command [list ::GX::_documentEditorDialogCommand $handle $operation]
            pack $pw.resources.actions.$operation -side top -fill x -padx 4 -pady 2
        }
        pack $pw.resources.actions -fill x
        text $pw.resources.details -height 5 -width 28 -wrap word -state disabled -exportselection 0
        pack $pw.resources.details -fill x
        bind $pw.resources.tree <<TreeviewSelect>> [list ::GX::_documentEditorResourceDetails $handle]
        uiTextEditingAttach [winfo toplevel $parent] [list $pw.properties.text $pw.resources.details]
    }
    _documentEditorPanelsRefresh $handle
    _documentEditorZoom $handle [dict get $record zoom]
}
proc ::GX::_documentEditorDialogCommand {handle operation} {
    if {[catch {documentEditorCommand $handle $operation} message]} {tk_messageBox -parent [winfo toplevel [dict get [_documentEditorRecord $handle] parent]] -icon warning -message $message}
}
proc ::GX::_documentEditorPanelsRefresh {handle} {
    set record [_documentEditorRecord $handle];set pw [dict get $record parent].editor.pw
    if {![winfo exists $pw.outline.tree]} return
    set outline $pw.outline.tree;set selected [$outline selection]
    $outline delete [$outline children {}]
    set n 0;set fenced 0
    foreach line [split [_documentEditorText $record] \n] {
        incr n
        if {[regexp {^```} [string trim $line]]} {set fenced [expr {!$fenced}];continue}
        if {!$fenced && [regexp {^(#{1,6})[[:space:]]+(.*)$} $line -> marks title]} {
            $outline insert {} end -id line$n -text "[string repeat {  } [expr {[string length $marks]-1}]]$title" -values [list $n]
        }
    }
    foreach item $selected {if {[$outline exists $item]} {$outline selection set $item}}
    uiFieldInspectionColumnsFit $outline
    set props $pw.properties.text;$props configure -state normal;$props delete 1.0 end
    set baseline [dict get $record baseline]
    foreach {key label} {dataset_id {Canonical Dataset} producer Producer sha256 {Baseline SHA256}} {
        $props insert end "$label: [datasetPublicationV2DictDefault $baseline $key {(none)}]\n\n"
    }
    _documentAssociationInsert $props [datasetPublicationV2DictDefault $baseline association {state unassociated}]
    set status [documentEditorCommand $handle inspect]
    $props insert end "Save Existing: [expr {[dict get $status can_replace]?{authorized; checked again on Save}:{unavailable; use Publish New}}]\n\nDestination: [dict get $record destination_id]\n\nUnsaved changes: [dict get $status dirty]\n"
    $props configure -state disabled
    set tree $pw.resources.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {name reference} [_documentEditorAssetCatalog $record] {
        set metadata [dict get $reference metadata]
        set dimensions "[datasetPublicationV2DictDefault $metadata width {?}] × [datasetPublicationV2DictDefault $metadata height {?}]"
        $tree insert {} end -id $name -text $name -values [list [dict get $reference size_bytes] $dimensions]
    }
    foreach item $selected {if {[$tree exists $item]} {$tree selection set $item}}
    uiFieldInspectionColumnsFit $tree
    set inert [expr {[dict get $record options asset_provider] ne {} || [dict get $record options mode] ne {editable}}]
    foreach operation {insert_image replace_image remove_image} {$pw.resources.actions.$operation state [expr {$inert?{disabled}:{!disabled}}]}
    _documentEditorResourceDetails $handle
}
proc ::GX::_documentEditorOutlineSelect {handle} {
    set record [_documentEditorRecord $handle];set tree [dict get $record parent].editor.pw.outline.tree
    set item [lindex [$tree selection] 0];if {$item eq {}} return
    set source [dict get $record source];set line [lindex [$tree item $item -values] 0]
    $source mark set insert $line.0;$source see $line.0;focus $source
}
proc ::GX::_documentEditorResourceDetails {handle} {
    set record [_documentEditorRecord $handle];set base [dict get $record parent].editor.pw.resources
    set name [lindex [$base.tree selection] 0]
    $base.details configure -state normal;$base.details delete 1.0 end
    set assets [_documentEditorAssetCatalog $record]
    if {$name ne {} && [dict exists $assets $name]} {
        set reference [dict get $assets $name];set metadata [dict get $reference metadata]
        $base.details insert end "Target: assets/$name\nSHA256: [dict get $reference sha256]\nBytes: [dict get $reference size_bytes]\nDimensions: [datasetPublicationV2DictDefault $metadata width {?}] × [datasetPublicationV2DictDefault $metadata height {?}]\nMedia: [datasetPublicationV2DictDefault $metadata media_type {unknown}]\n"
        if {[datasetPublicationV2DictDefault $reference schema {}] eq {gxtxt.source_asset.v1}} {$base.details insert end {Portable source snapshot: attach explicitly to the Session before editing its resources.}}
    } else {$base.details insert end {Images use immutable managed resources. Review Markdown references when removing an image.}}
    $base.details configure -state disabled
}
proc ::GX::_documentEditorZoom {handle factor} {
    variable ::GX::DocumentSource::editors
    variable ::GX::DocumentSource::zoom
    if {![string is double -strict $factor] || $factor<.5 || $factor>3.0} {error {Markdown zoom must be between0.5 and3}}
    set record [_documentEditorRecord $handle]
    foreach key {source preview} {
        set widget [dict get $record $key];if {$widget eq {} || ![dict exists $zoom $widget]} continue
        dict set zoom $widget factor $factor
        documentPresentationZoom $widget current
        if {$key eq {preview}} {
            foreach {tag base family style} {gx_h1 18 TkDefaultFont bold gx_h2 15 TkDefaultFont bold gx_h3 12 TkDefaultFont bold gx_bold 10 TkDefaultFont bold gx_italic 10 TkDefaultFont italic gx_list 10 TkDefaultFont bold gx_code 10 TkFixedFont normal gx_codeblock 10 TkFixedFont normal gx_table 10 TkFixedFont normal} {
                set size [font actual $family -size]
                set scaled [expr {max(4,round(abs($size)*$base/10.*$factor))}]
                $widget tag configure $tag -font [list [font actual $family -family] [expr {$size<0?-$scaled:$scaled}] $style]
            }
        }
    }
    dict set editors $handle zoom $factor
}
proc ::GX::_documentEditorSplitters {handle} {
    set record [_documentEditorRecord $handle]
    if {[dict get $record options mode] ne {editable}} {return {}}
    # Capture the declared map-of-arrays in canonical Tcl list form, just as
    # the typed Workspace codec decodes it. Equivalent brace spellings must
    # not make the native History journal appear to differ after cold reopen.
    set result {}
    dict for {key positions} [dict get $record splitters] {
        set canonical {};foreach position $positions {lappend canonical $position}
        dict set result $key $canonical
    }
    return $result
}
proc ::GX::_documentEditorLayoutKey {view} {
    set key main
    foreach pane {source rendered outline properties resources} {if {[dict get $view $pane]} {append key _$pane}}
    return $key
}
proc ::GX::_documentEditorDefaultSplitters {key} {
    set count [expr {[llength [split $key _]]-1}];set ratios {}
    for {set i 1} {$i<$count} {incr i} {lappend ratios [expr {$i/double($count)}]}
    return $ratios
}
proc ::GX::_documentEditorViewSplitters {handle} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];set values [dict get $record splitters]
    set old [dict get $record layout_key];set new [_documentEditorLayoutKey [dict get $record view]]
    if {$new ne $old} {
        if {[dict get $values main] ne [_documentEditorDefaultSplitters $old]} {dict set values $old [dict get $values main]}
        dict set values main [datasetPublicationV2DictDefault $values $new [_documentEditorDefaultSplitters $new]]
        dict set editors $handle splitters $values;dict set editors $handle layout_key $new
    }
    _documentEditorSplittersSchedule $handle
}
proc ::GX::_documentEditorSplittersSchedule {handle} {
    variable ::GX::DocumentSource::editors
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    if {[datasetPublicationV2DictDefault $record splitter_idle {}] ne {}} return
    dict set editors $handle splitter_idle [after idle [list ::GX::_documentEditorSplittersApply $handle]]
}
proc ::GX::_documentEditorSplittersApply {handle} {
    variable ::GX::DocumentSource::editors
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    set pending [datasetPublicationV2DictDefault $record splitter_idle {}]
    if {$pending ne {}} {after cancel $pending;dict set editors $handle splitter_idle {}}
    if {[dict get $record dragging]} return
    if {[datasetPublicationV2DictDefault $record applying 0]} return
    set pw [dict get $record parent].editor.pw
    if {![winfo exists $pw] || ![winfo ismapped $pw] || [winfo width $pw]<=1 || ![dict exists $record splitters main]} return
    set panes [$pw panes];set requested {};set positions {}
    foreach pane $panes {lappend requested [winfo reqwidth $pane]}
    for {set i 0} {$i<[llength $panes]-1} {incr i} {lappend positions [$pw sashpos $i]}
    set geometry [list [winfo width $pw] [ttk::style theme use] $panes $requested [dict get $record splitters main]]
    if {[datasetPublicationV2DictDefault $record splitter_settled {}] eq [list $geometry $positions]} return
    dict set editors $handle applying 1
    try {
    # This is already an idle callback. Pumping idle events here permits another
    # editor to enter and continually requeue Configure work inside this one.
    set targets {};set i 0
    foreach ratio [dict get $record splitters main] {
        if {$i>=[llength $panes]-1} break
        dict set targets $i [expr {round($ratio*[winfo width $pw])}];incr i
    }
    # ttk clamps a sash against its neighbours. Set both directions so newly
    # inserted panes settle without collapsing earlier panes against old sashes.
    foreach index [concat [dict keys $targets] [lreverse [dict keys $targets]]] {
        if {[$pw sashpos $index] != [dict get $targets $index]} {$pw sashpos $index [dict get $targets $index]}
    }
    set positions {}
    for {set i 0} {$i<[llength $panes]-1} {incr i} {lappend positions [$pw sashpos $i]}
    # Remember actual clamped positions as well as requested ratios. Narrow
    # windows must settle even when Tk cannot satisfy the requested positions.
    dict set editors $handle splitter_settled [list $geometry $positions]
    } finally {if {[dict exists $editors $handle]} {dict set editors $handle applying 0}}
}
proc ::GX::_documentEditorSplittersRestore {handle values} {
    variable ::GX::DocumentSource::editors
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    if {![dict exists $values main]} {dict set values main [_documentEditorDefaultSplitters [_documentEditorLayoutKey [dict get $record view]]]}
    dict set editors $handle splitters $values
    _documentEditorSplittersApply $handle
    _documentEditorSplittersSchedule $handle
}
proc ::GX::_documentEditorSashPress {handle x y} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];set pw [dict get $record parent].editor.pw
    dict set editors $handle dragging [expr {[$pw identify $x $y] ne {}}]
}
proc ::GX::_documentEditorSashRelease {handle} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle]
    if {![dict get $record dragging]} return
    set pw [dict get $record parent].editor.pw;set positions {};set width [winfo width $pw]
    for {set i 0} {$i<[llength [$pw panes]]-1} {incr i} {lappend positions [expr {[$pw sashpos $i]/double($width)}]}
    dict set editors $handle dragging 0
    dict set editors $handle splitters main $positions
    dict set editors $handle splitters [dict get $record layout_key] $positions
    _documentEditorChanged $handle
}
proc ::GX::documentImageBytesDescribe {bytes} {
    if {[string length $bytes]<24 || [string length $bytes]>4194304} {error {Managed Markdown image must be a PNG of at most4MiB}}
    binary scan [string range $bytes 0 23] H16@16II signature width height
    if {$signature ne {89504e470d0a1a0a} || $width<1 || $height<1 || $width>4096 || $height>4096} {error {PNG dimensions must be1..4096}}
    # Header checks precede the existing Tk decoder to bound decoded allocation.
    set photo [image create photo -data $bytes -format png]
    try {
        if {[image width $photo]!=$width || [image height $photo]!=$height} {error {PNG dimensions changed during decoding}}
    } finally {image delete $photo}
    return [dict create format png media_type image/png width $width height $height role markdown_image scientific_authority 1 disposable 0]
}
proc ::GX::_documentEditorImageRecord {handle} {
    set record [_documentEditorRecord $handle]
    if {[dict get $record options mode] ne {editable}} {error {Document is read-only}}
    if {[dict get $record session] eq {} || [dict get $record session] ne [_documentEditorSessionToken]} {error {Document Session changed or is unavailable; reopen in the matching Session before editing images}}
    if {[dict get $record options asset_provider] ne {}} {error {Portable source images are read-only until explicit Session attachment}}
    return $record
}
proc ::GX::_documentEditorImage {handle operation request} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorImageRecord $handle];set parent [dict get $record parent];set assets [dict get $record assets]
    set name [datasetPublicationV2DictDefault $request name {}]
    if {$operation ne {insert_image} && $name eq {}} {set name [lindex [$parent.editor.pw.resources.tree selection] 0]}
    if {$operation eq {remove_image}} {
        if {$name eq {} || ![dict exists $assets $name]} {error {Choose an image in Resources}}
        dict unset assets $name;dict set editors $handle assets $assets
        markupSourceChanged [dict get $record source];return
    }
    if {[dict exists $request bytes]} {set bytes [dict get $request bytes]
    } else {
        set path [tk_getOpenFile -parent [winfo toplevel $parent] -title {Choose PNG image} -filetypes {{{PNG image} .png}}]
        if {$path eq {}} return
        # The native chooser pumps events. Recheck the same live editor and
        # Session before any resource creation or overwrite of its asset map.
        set current [_documentEditorImageRecord $handle]
        if {[dict get $current session] ne [dict get $record session] || [dict get $current assets] ne $assets} {error {Document image resources changed while the chooser was open; choose the image again}}
        set record $current
        if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Choose a regular PNG of at most4MiB}}
        set stream [open $path rb];try {set bytes [read $stream 4194305]} finally {close $stream}
        if {$name eq {}} {set name [file tail $path]}
    }
    if {$name eq {}} {set name image.png}
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} $name]} {error {Image name must be a portable logical resource name}}
    if {$operation eq {insert_image} && [dict exists $assets $name]} {error {Image name already exists; choose Replace in Resources}}
    if {$operation eq {replace_image} && ![dict exists $assets $name]} {error {Choose an existing managed image}}
    set caption [datasetPublicationV2DictDefault $request caption Image]
    if {[regexp {[\]\r\n]} $caption]} {error {Image caption must be single-line without closing brackets}}
    if {![dict exists $assets $name] && [dict size $assets]>=32} {error {At most32 managed document images are allowed}}
    set total [string length $bytes]
    dict for {key value} $assets {if {$key ne $name} {incr total [dict get [interactiveDocumentResourceInfo $value] size_bytes]}}
    if {$total>16777216} {error {Managed document images exceed16MiB}}
    set metadata [documentImageBytesDescribe $bytes];dict set metadata filename $name
    set cap [dict get $record options capability]
    set owner [dict get $record asset_owner]
    if {$owner eq {}} {
        set owner [datasetDocumentAssetOwnerCreate $cap {operation markdown_image_edit}]
        dict set editors $handle asset_owner $owner
    }
    set resource [datasetDocumentAssetWrite $cap $owner $name $metadata $bytes]
    dict set assets $name $resource;dict set editors $handle assets $assets
    set source [dict get $record source]
    if {$operation eq {insert_image}} {
        $source insert insert "\n!\[$caption\](assets/$name)\n"
    }
    markupSourceChanged $source
}
proc ::GX::_documentEditorImagesClear {handle} {
    variable ::GX::DocumentSource::editors
    if {![dict exists $editors $handle]} return
    foreach photo [dict get $editors $handle photos] {catch {image delete $photo}}
    dict set editors $handle photos {};dict set editors $handle image_pairs {}
}
proc ::GX::_documentEditorImageRender {handle widget relative caption} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle]
    if {![regexp {^assets/([A-Za-z][A-Za-z0-9_.-]{0,95})$} $relative -> name]} {$widget insert end "Image unavailable: $caption (no authorized logical resource)\n";return}
    if {[catch {
        if {[dict exists $record assets $name]} {
            set reference [interactiveDocumentResourceInfo [dict get $record assets $name]]
            if {[dict get $reference size_bytes]>4194304} {error {Managed image exceeds4MiB}}
            set reader [interactiveDocumentResourceOpenReader $reference]
            try {
                set bytes {}
                while {1} {set chunk [interactiveDocumentResourceNext $reader];append bytes [dict get $chunk bytes];if {[dict get $chunk eof]} break}
            } finally {interactiveDocumentResourceCloseReader $reader}
        } else {
            set provider [dict get $record options asset_provider]
            if {$provider eq {}} {error {No managed source image}}
            set bytes [uplevel #0 [list {*}$provider read $name]]
        }
        documentImageBytesDescribe $bytes
        set original [image create photo -data $bytes -format png]
    } reason]} {$widget insert end "Image unavailable: $caption ($reason)\n";return}
    set displayed [image create photo]
    set photos [dict get $record photos];lappend photos $original $displayed;dict set editors $handle photos $photos
    set pairs [dict get $record image_pairs];lappend pairs [list $displayed $original];dict set editors $handle image_pairs $pairs
    _documentEditorImagesFit $handle
    $widget image create end -image $displayed;$widget insert end "\n$caption\n"
}
proc ::GX::_documentEditorImagesFit {handle} {
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    set widget [dict get $record preview];if {$widget eq {} || ![winfo exists $widget]} return
    set available [expr {max(80,[winfo width $widget]-35)}]
    foreach pair [dict get $record image_pairs] {
        lassign $pair displayed original
        set factor [expr {max(1,int(ceil([image width $original]/double($available))))}]
        $displayed copy $original -subsample $factor $factor -shrink
    }
}

proc ::GX::_documentAssociationInsert {widget association} {
    if {[datasetPublicationV2DictDefault $association state unassociated] ne {associated}} {
        $widget insert end "Associated source: none\n\n";return
    }
    foreach {key label} {source_filename {Source filename} language Language project_name {Project name} project_id {Project ID} source_state {Source status} source_sha256 {Source SHA256} owner {Source owner} diagnostic Explanation} {
        if {[dict exists $association $key] && [dict get $association $key] ne {}} {$widget insert end "$label: [dict get $association $key]\n\n"}
    }
}

proc ::GX::_documentEditorAssetCatalog {record} {
    set assets {}
    set provider [dict get $record options asset_provider]
    if {$provider ne {}} {set assets [uplevel #0 [list {*}$provider catalog]]}
    return [dict merge $assets [dict get $record assets]]
}
