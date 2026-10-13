# SPDX-License-Identifier: GPL-3.0-or-later
# Host-neutral History operations over Scientific Recipe's existing patches.
# Scientific hosts supply validation/restoration; Document owns durable commits.
proc ::GX::scientificHistoryCreate {owner snapshot} {
    set record [dict create format gxtxt.scientific_recipe.v1 workbench_id $owner required_apis {SCIENTIFIC_RECIPE_API_v1} \
        plugin_versions {} sources {} retention complete base $snapshot steps {} cursor 0]
    scientificHistoryValidate $owner $record
    return $record
}
proc ::GX::scientificHistoryValidate {owner record} {
    scientificRecipeEncode $record
    foreach field {base steps cursor workbench_id retention} {if {![dict exists $record $field]} {error "History requires $field"}}
    if {[dict get $record workbench_id] ne $owner || ![dict exists $::GX::ScientificRecipe::hosts $owner]} {error {History owner is unavailable or mismatched}}
    set steps [dict get $record steps];set cursor [dict get $record cursor]
    if {[llength $steps]>4096 || ![string is entier -strict $cursor] || $cursor<0 || $cursor>[llength $steps]} {error {Invalid History cursor or step limit}}
    if {[catch {dict size [dict get $record base]}]} {error {History checkpoint must be an inert dictionary}}
    foreach step $steps {
        foreach field {api_id api_version operation parameters targets result_ids working_unit patch description timestamp} {if {![dict exists $step $field]} {error "History step requires $field"}}
        if {[dict get $step api_id] ne "SCIENTIFIC_RECIPE_API_v1" || [dict get $step api_version]!=1 || [catch {dict size [dict get $step patch]}]} {error {Invalid scientific History step}}
    }
    uplevel #0 [list {*}[dict get $::GX::ScientificRecipe::hosts $owner validate] $record]
    return [dict create owner $owner count [llength $steps] cursor $cursor]
}
proc ::GX::scientificHistoryState {record {index -1}} {
    set steps [dict get $record steps]
    if {$index==-1} {set index [dict get $record cursor]}
    if {![string is entier -strict $index] || $index<0 || $index>[llength $steps]} {error {History index is outside the retained timeline}}
    set state [dict get $record base]
    for {set i 0} {$i<$index} {incr i} {set state [scientificRecipeApplyPatch $state [dict get [lindex $steps $i] patch]]}
    return $state
}
proc ::GX::scientificHistoryAppend {owner record snapshot description} {
    scientificHistoryValidate $owner $record
    if {[dict get $record cursor]!=[llength [dict get $record steps]]} {error {Confirm an explicit History branch before editing an older state}}
    set semantic [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 operation workspace_state \
        parameters {} targets {} result_ids {} working_unit {} description $description timestamp [clock seconds]]
    set candidate [scientificRecipeAppend $record [scientificHistoryState $record] $snapshot $semantic]
    dict set candidate cursor [llength [dict get $candidate steps]]
    scientificHistoryValidate $owner $candidate
    return $candidate
}
proc ::GX::scientificHistoryNavigate {owner record index} {
    scientificHistoryValidate $owner $record
    scientificHistoryState $record $index
    dict set record cursor $index
    scientificHistoryValidate $owner $record
    return $record
}
proc ::GX::scientificHistoryBranch {owner record index} {
    scientificHistoryValidate $owner $record
    scientificHistoryState $record $index
    dict set record steps [lrange [dict get $record steps] 0 [expr {$index-1}]]
    dict set record cursor $index
    scientificHistoryValidate $owner $record
    return $record
}

namespace eval ::GX::ScientificHistory {variable viewers {};variable strip}
proc ::GX::scientificHistoryViewerAttach {window owner callbacks {record {}}} {
    foreach field {capture restore commit guard} {if {![dict exists $callbacks $field]} {error "History host requires $field"}}
    set snapshot [uplevel #0 [dict get $callbacks capture]]
    if {$record eq {}} {set record [scientificHistoryCreate $owner $snapshot]}
    scientificHistoryValidate $owner $record
    dict set ::GX::ScientificHistory::viewers $window [dict create owner $owner callbacks $callbacks record $record \
        browsing 0 browse_cursor [dict get $record cursor] restoring 0 token [interactiveDocumentSessionToken]]
    bind $window <Destroy> +[list ::GX::_scientificHistoryDestroyed $window %W]
    return $record
}
proc ::GX::_scientificHistoryDestroyed {window destroyed} {
    if {$window eq $destroyed && [dict exists $::GX::ScientificHistory::viewers $window]} {
        set adapter [dict get $::GX::ScientificHistory::viewers $window]
        if {[dict exists $adapter strip_subscription]} {configurationUnsubscribe [dict get $adapter strip_subscription]}
        dict unset ::GX::ScientificHistory::viewers $window
        array unset ::GX::ScientificHistory::strip "$window,*"
    }
}
proc ::GX::_scientificHistoryGuard {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter token] ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Workspace}}
    if {![uplevel #0 [dict get $adapter callbacks guard]]} {error {Finish or cancel the active operation before navigating History}}
    return $adapter
}
proc ::GX::scientificHistoryViewerRecord {window} {return [dict get $::GX::ScientificHistory::viewers $window record]}
proc ::GX::scientificHistoryViewerState {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    set record [dict get $adapter record]
    set index [expr {[dict get $adapter browsing] ? [dict get $adapter browse_cursor] : [dict get $record cursor]}]
    return [scientificHistoryState $record $index]
}
proc ::GX::scientificHistoryViewerEditable {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} {return 1}
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    return [expr {![dict get $adapter browsing] && ![dict get $adapter restoring]}]
}
proc ::GX::scientificHistoryViewerPrepareEdit {window} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter browsing]} {error {History browsing is read-only. Return to latest or explicitly restart here.}}
    set record [dict get $adapter record];set cursor [dict get $record cursor]
    if {$cursor<[llength [dict get $record steps]]} {
        if {[tk_messageBox -parent $window -type okcancel -default cancel -icon warning -title {Branch Workspace History} \
            -message {Editing here discards later local History steps. Published Datasets and exported files remain. Restart editing here?}] ne "ok"} {return 0}
        _scientificHistoryCommit $window [scientificHistoryBranch [dict get $adapter owner] $record $cursor]
    }
    return 1
}
proc ::GX::_scientificHistoryCommit {window record} {
    set adapter [_scientificHistoryGuard $window]
    set prior [dict get $adapter record]
    set state [scientificHistoryState $record]
    scientificHistoryValidate [dict get $adapter owner] $record
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {
        uplevel #0 [list {*}[dict get $adapter callbacks restore] $state]
        uplevel #0 [list {*}[dict get $adapter callbacks commit] $record]
        dict set ::GX::ScientificHistory::viewers $window record $record
        dict set ::GX::ScientificHistory::viewers $window browsing 0
        dict set ::GX::ScientificHistory::viewers $window browse_cursor [dict get $record cursor]
    } on error {message options} {
        uplevel #0 [list {*}[dict get $adapter callbacks restore] [scientificHistoryState $prior]]
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
    scientificHistoryViewerRefresh $window
}
proc ::GX::scientificHistoryViewerChanged {window description} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter restoring]} {return [dict get $adapter record]}
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter browsing]} {error {History browsing is read-only}}
    set record [dict get $adapter record]
    set snapshot [uplevel #0 [dict get $adapter callbacks capture]]
    try {
        set candidate [scientificHistoryAppend [dict get $adapter owner] $record $snapshot $description]
        # Live state is already the captured state. Avoid needless native source
        # reconstruction; commit only the inert recipe through the host owner.
        uplevel #0 [list {*}[dict get $adapter callbacks commit] $candidate]
        dict set ::GX::ScientificHistory::viewers $window record $candidate
        dict set ::GX::ScientificHistory::viewers $window browse_cursor [dict get $candidate cursor]
    } on error {message options} {
        dict set ::GX::ScientificHistory::viewers $window restoring 1
        try {uplevel #0 [list {*}[dict get $adapter callbacks restore] [scientificHistoryState $record]]} finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
        return -options $options $message
    }
    scientificHistoryViewerRefresh $window
    return $candidate
}
proc ::GX::scientificHistoryViewerNavigate {window action} {
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    set count [llength [dict get $record steps]];set cursor [dict get $record cursor]
    switch $action {
        undo {if {[dict get $adapter browsing] || $cursor==0} return;_scientificHistoryCommit $window [scientificHistoryNavigate [dict get $adapter owner] $record [expr {$cursor-1}]]}
        redo {if {[dict get $adapter browsing] || $cursor==$count} return;_scientificHistoryCommit $window [scientificHistoryNavigate [dict get $adapter owner] $record [expr {$cursor+1}]]}
        previous {scientificHistoryViewerBrowse $window [expr {max(0,[dict get $adapter browse_cursor]-1)}]}
        next {scientificHistoryViewerBrowse $window [expr {min($count,[dict get $adapter browse_cursor]+1)}]}
        latest {scientificHistoryViewerBrowse $window $count}
        branch {
            set index [dict get $adapter browse_cursor]
            if {$index==$count} return
            if {[tk_messageBox -parent $window -type okcancel -default cancel -icon warning -message "Discard later local History and restart at step $index? External published/exported results remain."] ne "ok"} return
            _scientificHistoryCommit $window [scientificHistoryBranch [dict get $adapter owner] $record $index]
        }
        default {error {Unknown History action}}
    }
}
proc ::GX::scientificHistoryViewerBrowse {window index} {
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    set count [llength [dict get $record steps]]
    set previous [uplevel #0 [dict get $adapter callbacks capture]]
    set latest [expr {$index==$count}]
    set desired [scientificHistoryState $record [expr {$latest ? [dict get $record cursor] : $index}]]
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {uplevel #0 [list {*}[dict get $adapter callbacks restore] $desired]} on error {message options} {
        uplevel #0 [list {*}[dict get $adapter callbacks restore] $previous]
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
    dict set ::GX::ScientificHistory::viewers $window browsing [expr {!$latest}]
    dict set ::GX::ScientificHistory::viewers $window browse_cursor [expr {$latest ? [dict get $record cursor] : $index}]
    scientificHistoryViewerRefresh $window
}
proc ::GX::scientificHistoryViewerClear {window workspace} {
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    if {[dict get $adapter browsing] || [dict get $record cursor]!=[llength [dict get $record steps]]} {error {Return to latest before clearing History}}
    if {[dict get $record steps] eq {}} return
    set name [dict get [sessionWorkspaceGet $workspace] name]
    set decision [tk_messageBox -parent $window -type yesnocancel -default cancel -icon warning -title {Clear Workspace History} \
        -message "Clear historical steps for '$name', preserving all current state?\nYes: save an external Workspace backup first.\nNo: clear without backup.\nCancel: keep all History."]
    if {$decision eq "cancel"} return
    if {$decision eq "yes"} {
        set destination [workspaceSaveFile export_dir -parent $window -title {Save protected Workspace backup} -defaultextension .zip -filetypes {{{Workspace ZIP} {.zip}}}]
        if {$destination eq {}} return
        set package [sessionWorkspaceExport $workspace]
        filePublicationPublishBundle [list [dict create id history_backup destination $destination writer [list ::GX::_scientificHistoryBackupWriter $package]]]
    }
    set context [dict create owner [dict get $adapter owner] document_id $workspace retention complete]
    set candidate [scientificRecipeRebase $record [uplevel #0 [dict get $adapter callbacks capture]] $context]
    _scientificHistoryCommit $window $candidate
}
proc ::GX::_scientificHistoryBackupWriter {resource channel context} {
    set reader [interactiveDocumentResourceOpenReader $resource]
    try {
        while 1 {
            set block [interactiveDocumentResourceNext $reader]
            puts -nonewline $channel [dict get $block bytes]
            if {[dict get $block eof]} break
        }
    } finally {interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::scientificHistoryStripFields {} {
    return [dict create visible [dict create type boolean label {Show Description / History strip} default 1] mode [dict create type choice label {Strip mode} values {Description History} default Description] grouped [dict create type boolean label {Group consecutive related operations} default 1]]
}
proc ::GX::scientificHistoryStripValidate {values} {
    set result {}
    dict for {key field} [scientificHistoryStripFields] {dict set result $key [uiFieldNormalize $field [datasetPublicationV2DictDefault $values $key [dict get $field default]]]}
    foreach key [dict keys $values] {if {![dict exists $result $key]} {error {Unknown History strip preference}}}
    return $result
}
proc ::GX::scientificHistoryViewerStripSet {window values} {
    set adapter [_scientificHistoryGuard $window]
    set settings [scientificHistoryStripValidate [dict merge [dict get $adapter strip_settings] $values]]
    set id [dict get $adapter strip_configuration]
    if {$id ne {}} {configurationCommit [list [dict create id $id scope session value $settings session_token [_configurationSessionToken]]]} else {_scientificHistoryStripApply $window $settings}
}
proc ::GX::scientificHistoryViewerStripToggle {window} {
    set settings [dict get $::GX::ScientificHistory::viewers $window strip_settings]
    scientificHistoryViewerStripSet $window [dict create visible [expr {![dict get $settings visible]}]]
}
proc ::GX::_scientificHistoryStripChanged {window id} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![winfo exists $window]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter token] ne [interactiveDocumentSessionToken]} return
    set config [dict get $adapter strip_configuration]
    if {$id ni [list {} $config]} return
    _scientificHistoryStripApply $window [scientificHistoryStripValidate [dict get [configurationResolve $config] effective]]
}
proc ::GX::_scientificHistoryStripApply {window settings} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![winfo exists $window]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set frame [dict get $adapter strip]
    dict set ::GX::ScientificHistory::viewers $window strip_settings $settings
    set ::GX::ScientificHistory::strip($window,mode) [dict get $settings mode]
    _scientificHistoryStripSwitch $window 0
    if {[dict get $settings visible]} {
        if {[winfo manager $frame] eq {}} {pack $frame {*}[dict get $adapter strip_layout]}
    } else {pack forget $frame}
    scientificHistoryViewerRefresh $window
}
proc ::GX::scientificHistoryViewerStrip {window parent status {configurationId {}} {layout {-fill x}}} {
    set frame $parent.historyStrip
    ttk::frame $frame -height [expr {max(32,[font metrics TkDefaultFont -linespace]+12)}]
    pack propagate $frame 0
    set ::GX::ScientificHistory::strip($window,mode) Description
    ttk::combobox $frame.choice -state readonly -values {Description History} -width 12 -textvariable ::GX::ScientificHistory::strip($window,mode)
    pack $frame.choice -side left -fill y
    pack forget $status
    pack $status -in $frame -side left -fill x -expand 1;raise $status
    canvas $frame.timeline -height 30 -background #edf1f5 -highlightthickness 0 -xscrollincrement 24
    bind $frame.choice <<ComboboxSelected>> [list ::GX::_scientificHistoryStripSwitch $window]
    bind $frame.timeline <Button-1> [list ::GX::_scientificHistoryStripClick $window %x %y]
    bind $frame.timeline <Button-3> [list ::GX::_scientificHistoryStripContext $window %X %Y]
    bind $frame.timeline <Button-4> [list $frame.timeline xview scroll -3 units]
    bind $frame.timeline <Button-5> [list $frame.timeline xview scroll 3 units]
    ttk::button $frame.details -text Details -command [list ::GX::scientificHistoryViewerDetails $window]
    pack $frame.details -side right
    bind $frame <Configure> [list ::GX::_scientificHistoryStripSize $window]
    bind $frame.choice <Configure> [list ::GX::_scientificHistoryStripSize $window]
    dict set ::GX::ScientificHistory::viewers $window strip $frame
    dict set ::GX::ScientificHistory::viewers $window status $status
    dict set ::GX::ScientificHistory::viewers $window strip_configuration $configurationId
    dict set ::GX::ScientificHistory::viewers $window strip_layout $layout
    set settings [scientificHistoryStripValidate {}]
    if {$configurationId ne {}} {
        set settings [scientificHistoryStripValidate [dict get [configurationResolve $configurationId] effective]]
        dict set ::GX::ScientificHistory::viewers $window strip_subscription [configurationSubscribe [list ::GX::_scientificHistoryStripChanged $window]]
    }
    _scientificHistoryStripApply $window $settings
    scientificHistoryViewerRefresh $window
    return $frame
}
proc ::GX::_scientificHistoryStripSize {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window strip]} return
    set frame [dict get $::GX::ScientificHistory::viewers $window strip]
    if {![winfo exists $frame]} return
    set height [expr {max(32,[font metrics TkDefaultFont -linespace]+12,[winfo reqheight $frame.choice],[winfo reqheight $frame.details])}]
    if {[$frame cget -height]!=$height} {$frame configure -height $height}
    $frame.timeline configure -height $height
    scientificHistoryViewerRefresh $window
}
proc ::GX::_scientificHistoryStripSwitch {window {persist 1}} {
    if {$persist} {return [scientificHistoryViewerStripSet $window [dict create mode $::GX::ScientificHistory::strip($window,mode)]]}
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set frame [dict get $adapter strip]
    pack forget [dict get $adapter status] $frame.timeline
    if {$::GX::ScientificHistory::strip($window,mode) eq "History"} {pack $frame.timeline -side left -fill both -expand 1} else {pack [dict get $adapter status] -in $frame -side left -fill x -expand 1}
}
proc ::GX::_scientificHistoryStripClick {window x y} {
    set frame [dict get $::GX::ScientificHistory::viewers $window strip]
    foreach item [$frame.timeline find overlapping [$frame.timeline canvasx $x] [$frame.timeline canvasy $y] [$frame.timeline canvasx $x] [$frame.timeline canvasy $y]] {
        foreach tag [$frame.timeline gettags $item] {if {[regexp {^history_step_([0-9]+)$} $tag -> index]} {scientificHistoryViewerBrowse $window $index;return}}
    }
}
proc ::GX::_scientificHistoryStripContext {window x y} {
    set menu $window.historyContext
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    $menu delete 0 end
    foreach {action label} {previous {Previous history step} next {Next history step} latest {Return to latest} branch {Restart here / discard later local history…}} {
        if {[dict exists $::GX::ViewerCommands::windows $window handlers $action]} {viewerCommandMenuAdd $window $menu $action} else {$menu add command -label $label -command [list ::GX::scientificHistoryViewerNavigate $window $action]}
    }
    uiMenuPopup $menu $x $y
}
proc ::GX::scientificHistoryGroupedEntries {record {grouped 1}} {
    set result [list [dict create first 0 last 0 count 1 description Baseline timestamp {} operation baseline api_id {}]];set index 0
    foreach step [dict get $record steps] {
        incr index
        set entry [dict create first $index last $index count 1]
        foreach key {description timestamp operation api_id} {dict set entry $key [dict get $step $key]}
        set previous [lindex $result end];set merge $grouped
        foreach key {description operation api_id} {if {[dict get $entry $key] ne [dict get $previous $key]} {set merge 0}}
        if {[dict get $previous timestamp] eq {} || abs([dict get $entry timestamp]-[dict get $previous timestamp])>60} {set merge 0}
        if {$merge} {dict set previous last $index;dict incr previous count;dict set previous timestamp [dict get $entry timestamp];lset result end $previous} else {lappend result $entry}
    }
    return $result
}
proc ::GX::scientificHistoryViewerDetails {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set text {}
    if {$::GX::ScientificHistory::strip($window,mode) eq "Description"} {
        set status [dict get $adapter status];set variable [$status cget -textvariable]
        set text [expr {$variable eq {} ? [$status cget -text] : [uplevel #0 [list set $variable]]}]
    } else {
        set record [dict get $adapter record];set index 0
        append text "History cursor: [dict get $adapter browse_cursor] / [llength [dict get $record steps]]\n\n0: Baseline\n"
        foreach step [dict get $record steps] {append text "[incr index]: [dict get $step description]\n  [clock format [dict get $step timestamp] -format {%Y-%m-%d %H:%M:%S}]\n"}
    }
    set dialog $window.historyDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog "[wm title $window] — $::GX::ScientificHistory::strip($window,mode) details"
    text $dialog.text -width 90 -height 22 -wrap word -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    $dialog.text insert end $text;$dialog.text configure -state disabled
    pack $dialog.scroll -side right -fill y;pack $dialog.text -fill both -expand 1
    bind $dialog <Escape> [list destroy $dialog]
}
proc ::GX::scientificHistoryViewerRefresh {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict exists $adapter strip] && [winfo exists [dict get $adapter strip].timeline]} {
        set canvas [dict get $adapter strip].timeline;$canvas delete all
        set record [dict get $adapter record];set x 3;set index 0
        set height [[dict get $adapter strip] cget -height]
        set grouped [dict get $adapter strip_settings grouped]
        foreach step [scientificHistoryGroupedEntries $record $grouped] {
            set index [dict get $step last];set first [dict get $step first]
            set label [expr {$index==0 ? "Baseline" : "$index: [dict get $step description]"}]
            if {[dict get $step count]>1} {set label "$first–$index: [dict get $step description] ×[dict get $step count]"}
            if {[dict get $step timestamp] ne {}} {append label " · [clock format [dict get $step timestamp] -format %H:%M:%S]"}
            set cursor [dict get $adapter browse_cursor]
            set fill [expr {$cursor>=$first && $cursor<=$index ? "#c5dff4" : "#edf1f5"}]
            set tag history_step_$index
            set text [$canvas create text [expr {$x+6}] [expr {$height/2.0}] -anchor w -text $label -tags $tag]
            set bounds [$canvas bbox $text];set right [expr {[lindex $bounds 2]+6}]
            if {$right<$x+40} {set right [expr {$x+40}]}
            set rectangle [$canvas create rectangle $x 1 $right [expr {$height-1}] -fill $fill -outline #c7cdd5 -tags $tag]
            $canvas lower $rectangle $text
            set x [expr {$right+4}]
        }
        $canvas configure -scrollregion [list 0 0 $x $height]
    }
    viewerCommandMenusRefresh $window
}
