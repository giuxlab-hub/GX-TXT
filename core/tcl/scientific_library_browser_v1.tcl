# SPDX-License-Identifier: GPL-3.0-or-later
# Generic host Browser adjunct to the existing Scientific Libraries workspace.
# All semantics come from installed domain schemas; no vendor/domain switches.
namespace eval ::GX::LibraryBrowser {variable serial 0;variable states {};variable flowPending {}}
proc ::GX::LibraryBrowser::str {value} {return [::GX::viewerDevelopmentJsonString $value]}
proc ::GX::LibraryBrowser::object {fields} {return [::GX::LibraryEntryAcquisitionDispatchAPIv1::_strings $fields]}
proc ::GX::LibraryBrowser::array {values} {set result {};foreach value $values {lappend result [str $value]};return \[[join $result ,]\]}
proc ::GX::LibraryBrowser::scopeJson {scope} {
    set result {};dict for {key values} $scope {lappend result "[str $key]:[array $values]"}
    return \{[join $result ,]\}
}
proc ::GX::LibraryBrowser::scopedJson {w json} {
    set scope [dict get $::GX::LibraryBrowser::states $w scope]
    if {$scope eq {}} {return $json}
    set body [string range [string trim $json] 1 end-1]
    if {[string trim $body] ne {}} {append body ,}
    return \{$body\"scope\":[scopeJson $scope]\}
}
proc ::GX::LibraryBrowser::domain {w operation json} {
    return [::GX::ScientificLibraryManagerAPIv1::domainRequest $operation [scopedJson $w $json]]
}
proc ::GX::LibraryBrowser::scopeDescribe {w} {
    return [::GX::ScientificLibraryManagerAPIv1::describeScope [scopedJson $w {{}}]]
}
proc ::GX::LibraryBrowser::status {w message} {
    variable states
    if {![dict exists $states $w]} return
    dict set states $w status $message
    # Host children can disappear before its parent Destroy callback. Status
    # is advisory; retain it in the controller without interrupting retirement.
    if {[catch {{*}[dict get $states $w status_command] $message} reason]} {
        dict set states $w status_delivery_error $reason
    }
}
proc ::GX::LibraryBrowser::providerSignature {} {
    # Cache invalidation only: reuse the same enabled descriptor admission as
    # the Manager. No provider execution, network, registry or credential read.
    set result {}
    foreach id [lsort $::GX::moduleOrder] {
        if {![info exists ::GX::moduleCatalog($id,dict)] || ![::GX::ScientificLibraryManagerAPIv1::_descriptorSupported $id]} continue
        set path [::GX::moduleField $id descriptor {}]
        set stamp missing
        if {[file isfile $path]} {set stamp [list [file mtime $path] [file size $path]]}
        lappend result [list $id [::GX::moduleField $id version {}] $path $stamp]
    }
    return $result
}
proc ::GX::LibraryBrowser::guard {w} {
    variable states
    if {![dict exists $states $w] || [dict get $states $w closing] || ![winfo exists [dict get $states $w owner]]} {error {Library Viewer is closing or unavailable}}
    if {![::GX::viewerGuiDesignGuard [dict get $states $w owner]]} {error {This Library Viewer belongs to a previous Session context; reopen it. The unsaved draft remains available until you choose to discard it.}}
    if {[providerSignature] ne [dict get $states $w provider_signature]} {
        error {Library provider availability changed; reopen this Viewer to load current domains, types and Source Connectors. Your unsaved draft is preserved: copy it or explicitly discard it when closing.}
    }
}
proc ::GX::LibraryBrowser::run {w script} {
    set code [catch {guard $w;uplevel 1 $script} message]
    if {$code ni {0 2}} {status $w $message;return {}}
    # Preserve explicit successful results and early-return branches. Callers
    # only advance navigation history after a pinned/scoped inspection succeeds.
    return $message
}
proc ::GX::LibraryBrowser::table {parent columns} {
    ttk::frame $parent
    ttk::treeview $parent.tree -columns $columns -show headings -selectmode extended -height 9
    foreach column $columns {$parent.tree heading $column -text [string totitle [string map {_ { }} $column]];$parent.tree column $column -width 180 -minwidth 80}
    ttk::scrollbar $parent.y -orient vertical -command [list $parent.tree yview]
    ttk::scrollbar $parent.x -orient horizontal -command [list $parent.tree xview]
    $parent.tree configure -yscrollcommand [list $parent.y set] -xscrollcommand [list $parent.x set]
    grid $parent.tree -row 0 -column 0 -sticky nsew;grid $parent.y -row 0 -column 1 -sticky ns;grid $parent.x -row 1 -column 0 -sticky ew
    grid rowconfigure $parent 0 -weight 1;grid columnconfigure $parent 0 -weight 1
    ::GX::uiFieldInspectionColumnsFit $parent.tree
    bind $parent.tree <Control-c> {::GX::uiFieldComponentTableCopy %W;break}
    bind $parent.tree <Control-C> {::GX::uiFieldComponentTableCopy %W;break}
    bind $parent.tree <Configure> [list ::GX::uiFieldInspectionColumnsSchedule $parent.tree]
    bind $parent.tree <Map> [list ::GX::uiFieldInspectionColumnsSchedule $parent.tree]
    return $parent.tree
}
# Trusted GUI Host bridge: the Builder declares three pages, while the same
# existing Library controller owns presentation state and existing public calls.
proc ::GX::LibraryBrowser::mountPages {window group pages statusCommand {scope {}}} {
    variable states
    if {[lsort [dict keys $pages]] ne {manual records sources}} {error {Library Browser requires exactly records, sources and manual pages}}
    foreach page {records sources manual} {
        set root [dict get $pages $page]
        if {![winfo exists $root] || [winfo toplevel $root] ne $window || [winfo children $root] ne {}} {error {Library pages must be empty native frames owned by this Viewer}}
    }
    set w [dict get $pages records]
    if {[dict exists $states $w]} {error {Library Browser group is already mounted}}
    set context [::GX::ScientificLibraryManagerAPIv1::describeScope [format {{"scope":%s}} [scopeJson $scope]]]
    set scope [dict get $context scope];set schemas [dict get $context catalog]
    dict set states $w [dict create owner $window group $group page_hosts $pages pages {} status_command $statusCommand scope $scope scope_context $context schemas $schemas rows {} source_rows {} bundle {} request {} generation 0 history {} forward_history {} attachments {} allocations {} pdf_views {} gallery_images {} gallery_allocations {} gallery_active 0 gallery_queue {} gallery_count 0 gallery_failures 0 inline_views {} view_stacks {} named_views {} resource_serial 0 closing 0 destroyed 0 preview {}]
    dict set states $w provider_signature [providerSignature]
    try {
        foreach page {records sources manual} {
            set host [dict get $pages $page]
            ttk::frame $host.body -padding 6
            pack $host.body -fill both -expand 1
            if {$scope ne {}} {
                set dimensions {};dict for {axis ids} $scope {lappend dimensions "$axis: [llength $ids]"}
                ttk::label $host.body.scope -text "Filtered Library view • [join $dimensions { • }]\nFilters apply before paging; outside links retain their assertions." -padding 4
                pack $host.body.scope -fill x
                wrapLabel $host.body.scope
                ttk::button $host.body.scopeDetails -text {View exact scope and availability…} -command [list ::GX::LibraryBrowser::scopeView $w $page]
                pack $host.body.scopeDetails -anchor w -pady 2
            }
            dict set states $w pages $page $host.body
        }
        # Long forms use the existing shared canvas/focus scroll owner.
        foreach page {records sources} {
            set body [dict get $states $w pages $page]
            canvas $body.viewport -highlightthickness 0 -width 1 -height 1
            ttk::scrollbar $body.scroll -orient vertical -command [list $body.viewport yview]
            $body.viewport configure -yscrollcommand [list $body.scroll set]
            ttk::frame $body.viewport.content -padding 3
            $body.viewport create window 0 0 -anchor nw -window $body.viewport.content -tags content
            bind $body.viewport <Configure> [list $body.viewport itemconfigure content -width %w]
            bind $body.viewport.content <Configure> [list $body.viewport configure -scrollregion [list 0 0 %w %h]]
            pack $body.scroll -side right -fill y;pack $body.viewport -fill both -expand 1
            ::GX::uiFieldScrollAreaAttach $body.viewport $body.viewport.content
            dict set states $w pages $page $body.viewport.content
        }
        buildRecords $w;buildSources $w;buildManual $w
        bind $window <Destroy> +[list ::GX::LibraryBrowser::closed $w %W]
        dict set states $w draft_baseline [draftSnapshot $w]
        refresh $w
    } on error {message options} {
        closed $w $window
        return -options $options $message
    }
    return $w
}
proc ::GX::LibraryBrowser::pageRoot {w page} {return [dict get $::GX::LibraryBrowser::states $w pages $page]}
proc ::GX::LibraryBrowser::scopeView {w page} {
    run $w {
        set context [scopeDescribe $w]
        set view [inlineView $w scope_$page $page {Exact literal Library view scope}]
        text $view.text -wrap word -height 12 -width 1 -yscrollcommand [list $view.scroll set]
        ttk::scrollbar $view.scroll -orient vertical -command [list $view.text yview]
        pack $view.scroll -side right -fill y;pack $view.text -fill both -expand 1
        $view.text insert end "Scope (literal IDs; OR within each dimension, AND across dimensions):\n[scopeJson [dict get $context scope]]\n\nAvailability diagnostics:\n"
        foreach row [dict get $context diagnostics] {$view.text insert end "[dict get $row axis] / [dict get $row id]: [dict get $row reason]\n"}
        $view.text configure -state disabled
    }
}
proc ::GX::LibraryBrowser::focusPage {w page} {
    variable states
    if {$page ni {records sources manual} || ![dict exists $states $w] || [dict get $states $w closing]} {error {Library page is unavailable}}
    guard $w
    set root [dict get $states $w page_hosts $page]
    set child $root
    while {$child ne [dict get $states $w owner]} {
        set parent [winfo parent $child]
        if {[winfo class $parent] eq {TNotebook} && $child in [$parent tabs]} {$parent select $child}
        set child $parent
    }
    set target [expr {$page eq {records}?"[pageRoot $w records].search.query":($page eq {sources}?"[pageRoot $w sources].lookup.query":"[manualRoot $w].identity.type")}]
    if {[winfo exists $target]} {::GX::uiFieldFocusWhenMapped $root $target 0}
    return $page
}
# Historical internal callers receive the same original Viewer, never a second
# Library workspace. A legacy installed design must be upgraded explicitly.
proc ::GX::LibraryBrowser::open {{parent .}} {
    variable states
    dict for {controller state} $states {
        if {[dict get $state owner] eq $parent} {focusPage $controller records;return $parent}
    }
    set window [::GX::viewerOpen viewer.scientific_library_workspace scientific_library_workspace {}]
    if {![llength [info commands ::GX::viewerGuiDesignLibraryPage]]} {error {Update Scientific Libraries to the compatible unified Viewer; embedded pages are unavailable}}
    after idle [list ::GX::LibraryBrowser::redirectFocus $window scientific_libraries 0]
    return $window
}
proc ::GX::LibraryBrowser::redirectFocus {window group attempt} {
    variable states
    if {![winfo exists $window]} return
    dict for {controller state} $states {
        if {[dict get $state owner] eq $window && [dict get $state group] eq $group} {
            ::GX::viewerGuiDesignLibraryPage $window $group records
            return
        }
    }
    if {[dict exists $::GX::ViewerGui::instances $window design]} {
        set supported 0
        foreach component [dict get $::GX::ViewerGui::instances $window design components] {
            if {[dict get $component type] eq {library_browser} && [dict get $component properties group] eq $group} {set supported 1;break}
        }
        if {!$supported} {tk_messageBox -parent $window -icon info -title {Scientific Libraries update required} -message {This installed Viewer has no integrated Library pages. Update the Scientific Libraries module to a compatible unified design.};return}
    }
    if {$attempt>=600} {return}
    after 50 [list ::GX::LibraryBrowser::redirectFocus $window $group [expr {$attempt+1}]]
}
proc ::GX::LibraryBrowser::draftSnapshot {w} {
    if {[catch {
        set p [manualRoot $w]
        set snapshot [list [manualParameters $w 1] [$p.suggestions.paste get 1.0 end-1c] $::GX::LibraryBrowser::manualInclude($w)]
        foreach key {relation source kind evidence} {lappend snapshot [$p.suggestions.claim.$key get]}
        lappend snapshot [dict get $::GX::LibraryBrowser::states $w manual_selected]
        lappend snapshot [::GX::datasetPublicationV2DictDefault [dict get $::GX::LibraryBrowser::states $w] table_rows {}]
        lappend snapshot [expr {[winfo exists $p.fields.content.template]?[$p.fields.content.template get]:{}}]
    }]} {return changed-unreviewed-candidate-paste}
    return $snapshot
}
proc ::GX::LibraryBrowser::canClose {w} {
    variable states
    if {![dict exists $states $w]} {return 1}
    if {[draftSnapshot $w] eq [dict get $states $w draft_baseline]} {return 1}
    set answer [tk_messageBox -parent [dict get $states $w owner] -type yesno -icon question -title {Unsaved Library draft} -message {Close and discard the unsaved manual draft?} -detail {Choose No to return to the existing Viewer. Persistent Libraries are unchanged until Save.}]
    return [expr {$answer eq {yes}}]
}
proc ::GX::LibraryBrowser::inlineView {w key page title} {
    variable states
    focusPage $w $page
    set host [dict get $states $w page_hosts $page]
    set view $host.view[incr ::GX::LibraryBrowser::serial]
    ttk::frame $view -padding 6
    ttk::frame $view.navigation
    ttk::label $view.navigation.title -text $title -width 1 -anchor w
    ttk::button $view.navigation.back -text {Back to page} -command [list ::GX::LibraryBrowser::inlineClose $w $view]
    pack $view.navigation.back -side right -padx 4
    pack $view.navigation.title -side left -fill x -expand 1
    pack $view.navigation -fill x -pady 4
    bind $view.navigation <Configure> [list ::GX::LibraryBrowser::inlineLayout $view %w]
    set stack [::GX::datasetPublicationV2DictDefault [dict get $states $w view_stacks] $page {}]
    foreach child [winfo children $host] {pack forget $child}
    pack $view -fill both -expand 1
    lappend stack $view
    dict set states $w view_stacks $page $stack
    dict set states $w inline_views $view [dict create page $page key $key]
    dict set states $w named_views $key $view
    bind $view <Destroy> [list ::GX::LibraryBrowser::inlineDestroyed $w $view %W]
    return $view
}
proc ::GX::LibraryBrowser::inlineLayout {view width} {
    if {[winfo exists $view.navigation.title]} {$view.navigation.title configure -wraplength [expr {max(120,$width-[winfo reqwidth $view.navigation.back]-24)}]}
}
proc ::GX::LibraryBrowser::viewFor {w key} {return [dict get $::GX::LibraryBrowser::states $w named_views $key]}
proc ::GX::LibraryBrowser::inlineClose {w view} {
    if {[dict exists $::GX::LibraryBrowser::states $w pdf_views $view]} {pdfClose $w $view} else {catch {destroy $view}}
}
proc ::GX::LibraryBrowser::inlineDestroyed {w view actual} {
    variable states
    if {$view ne $actual || ![dict exists $states $w inline_views $view]} return
    set info [dict get $states $w inline_views $view];set page [dict get $info page]
    dict unset states $w inline_views $view
    set key [dict get $info key]
    if {[dict exists $states $w named_views $key] && [dict get $states $w named_views $key] eq $view} {dict unset states $w named_views $key}
    if {[dict exists $info allocation_id] && ![dict exists $states $w pdf_views $view]} {catch {releaseAllocation $w [dict get $info allocation_id]}}
    set keep {};foreach item [dict get $states $w view_stacks $page] {if {$item ne $view && [winfo exists $item]} {lappend keep $item}}
    dict set states $w view_stacks $page $keep
    if {[dict get $states $w destroyed]} return
    set host [dict get $states $w page_hosts $page]
    if {![winfo exists $host]} return
    catch {
        foreach child [winfo children $host] {pack forget $child}
        if {[llength $keep]} {pack [lindex $keep end] -fill both -expand 1} else {pack $host.body -fill both -expand 1}
    }
}
proc ::GX::LibraryBrowser::closed {w actual} {
    variable states
    if {![dict exists $states $w] || $actual ne [dict get $states $w owner]} return
    dict set states $w destroyed 1
    catch {galleryClear $w}
    set state [dict get $states $w]
    if {[dict get $state request] ne {}} {catch {::GX::scriptJobRequestCancel [dict get $state request]}}
    set held {}
    dict for {view media} [dict get $state pdf_views] {
        lappend held [dict get $media allocation_id]
        catch {pdfClose $w $view}
    }
    foreach allocation [dict get $state allocations] {
        if {[dict get $allocation id] in $held} continue
        catch {::GX::resourceManagementRelease [dict get $allocation id]};catch {::GX::resourceManagementCleanup [list [dict get $allocation id]]}
    }
    dict unset states $w
    unset -nocomplain ::GX::LibraryBrowser::manualInclude($w)
}
proc ::GX::LibraryBrowser::close {w} {
    # The owning GUI Host closes its own window. This only retires this
    # embedded controller and never destroys or repurposes the Viewer shell.
    if {![dict exists $::GX::LibraryBrowser::states $w]} return
    closed $w [dict get $::GX::LibraryBrowser::states $w owner]
}
proc ::GX::LibraryBrowser::releaseAllocation {w id} {
    variable states
    ::GX::resourceManagementRelease $id
    ::GX::resourceManagementCleanup [list $id]
    if {[dict exists $states $w]} {
        set keep {};foreach allocation [dict get $states $w allocations] {if {[dict get $allocation id] ne $id} {lappend keep $allocation}}
        dict set states $w allocations $keep
    }
}
proc ::GX::LibraryBrowser::pdfOpen {w view allocation source title} {
    variable states
    if {![llength [info commands ::GX::datasetMediaViewerOpenArtifact]]} {error {This CORE has no managed Library PDF reader; install the compatible framework revision.}}
    if {[dict get $states $w closing]} {error {Library Browser is closing its readers}}
    if {![winfo exists $view]} {error {PDF consultation requires an existing embedded Library view}}
    if {[winfo exists $view.identity]} {wrapLabel $view.identity}
    frame $view.pdf -container 1 -width 1 -height 1 -highlightthickness 0
    pack $view.pdf -fill both -expand 1
    ttk::frame $view.actions
    ttk::button $view.actions.external -text {Open original copy externally…} -command [list ::GX::LibraryBrowser::externalOpen [dict get $source path]]
    ttk::button $view.actions.close -text Close -command [list ::GX::LibraryBrowser::pdfRequestClose $w $view]
    flow $view.actions
    pack $view.actions -side bottom -fill x -before $view.pdf
    update idletasks
    if {[catch {::GX::datasetMediaViewerOpenArtifact $source $view.pdf $title} owner options]} {
        catch {destroy $view};return -options $options $owner
    }
    dict set states $w pdf_views $view [dict create owner $owner allocation_id [dict get $allocation id] allocation $allocation source $source closing 0]
    bind $view <Destroy> +[list ::GX::LibraryBrowser::pdfDestroyed $w $view %W]
    status $w {Read-only PDF consultation; original source unchanged.}
    return $owner
}
proc ::GX::LibraryBrowser::pdfRequestClose {w view} {run $w {pdfClose $w $view}}
proc ::GX::LibraryBrowser::pdfDestroyed {w view actual} {
    if {$view ne $actual || ![dict exists $::GX::LibraryBrowser::states $w pdf_views $view]} return
    if {[catch {pdfClose $w $view} reason]} {status $w "PDF cleanup pending: $reason"}
}
proc ::GX::LibraryBrowser::pdfClose {w view} {
    variable states
    if {![dict exists $states $w pdf_views $view]} {catch {destroy $view};return}
    set media [dict get $states $w pdf_views $view]
    if {[dict get $media closing]} return
    dict set states $w pdf_views $view closing 1
    # The existing owner may retire asynchronously. Its callback is the only
    # authority to release bytes, and captures the allocation beyond UI lifetime.
    set callback [list ::GX::LibraryBrowser::pdfRetired $w $view [dict get $media allocation]]
    if {[catch {::GX::datasetViewerClose [dict get $media owner] $callback} message options]} {
        if {[dict exists $states $w pdf_views $view]} {dict set states $w pdf_views $view closing 0}
        return -options $options $message
    }
    if {[winfo exists $view.actions]} {foreach child [winfo children $view.actions] {catch {$child state disabled}}}
    status $w {Closing PDF reader before releasing its managed source…}
}
proc ::GX::LibraryBrowser::pdfRetired {w view allocation} {
    variable states
    if {[dict exists $states $w pdf_views $view]} {dict unset states $w pdf_views $view}
    if {[catch {releaseAllocation $w [dict get $allocation id]} reason]} {status $w "PDF reader closed; Resource cleanup pending: $reason"}
    catch {destroy $view}
}
proc ::GX::LibraryBrowser::wrapLabel {widget} {
    $widget configure -width 1
    bind $widget <Configure> [list ::GX::LibraryBrowser::wrapLabelWidth $widget %w]
}
proc ::GX::LibraryBrowser::wrapLabelWidth {widget width} {
    if {![winfo exists $widget]} return
    set padding [$widget cget -padding]
    set left [lindex $padding 0];if {$left eq {}} {set left 0}
    set right [expr {[llength $padding]>=3?[lindex $padding 2]:$left}]
    set wrap [expr {max(80,$width-max(8,$left+$right))}]
    if {[$widget cget -wraplength]!=$wrap} {$widget configure -wraplength $wrap}
}
proc ::GX::LibraryBrowser::flow {frame} {
    $frame configure -width 1
    grid propagate $frame 0
    bind $frame <Configure> [list ::GX::LibraryBrowser::flowLayout $frame %w]
    foreach child [winfo children $frame] {
        set callback [list ::GX::LibraryBrowser::flowSchedule $frame]
        if {$callback ni [split [bind $child <Configure>] \n]} {bind $child <Configure> +$callback}
    }
    bind $frame <Destroy> [list ::GX::LibraryBrowser::flowDestroyed $frame %W]
    flowLayout $frame [expr {max(120,[winfo width $frame])}]
}
proc ::GX::LibraryBrowser::flowSchedule {frame} {
    variable flowPending
    if {![winfo exists $frame] || [dict exists $flowPending $frame]} return
    dict set flowPending $frame [after idle [list ::GX::LibraryBrowser::flowApply $frame]]
}
proc ::GX::LibraryBrowser::flowApply {frame} {
    variable flowPending
    if {[dict exists $flowPending $frame]} {dict unset flowPending $frame}
    if {[winfo exists $frame]} {flowLayout $frame [winfo width $frame]}
}
proc ::GX::LibraryBrowser::flowDestroyed {frame actual} {
    variable flowPending
    if {$actual eq $frame && [dict exists $flowPending $frame]} {after cancel [dict get $flowPending $frame];dict unset flowPending $frame}
}
proc ::GX::LibraryBrowser::flowLayout {frame width} {
    if {![winfo exists $frame]} return
    set result [::GX::uiFieldControlsLayout $frame $width]
    set height [dict get $result height]
    if {[$frame cget -height]!=$height} {$frame configure -height $height}
}
proc ::GX::LibraryBrowser::galleryClear {w} {
    variable states
    if {![dict exists $states $w]} return
    if {[dict get $states $w gallery_active]} {
        catch {::GX::scriptJobRequestCancel [dict get $states $w request]}
        dict set states $w request {};dict set states $w generation [expr {[dict get $states $w generation]+1}]
    }
    set strip [pageRoot $w records].detail.resources.gallery
    if {[winfo exists $strip]} {foreach child [winfo children $strip] {destroy $child}}
    foreach image [dict get $states $w gallery_images] {catch {image delete $image}}
    dict set states $w gallery_images {};dict set states $w gallery_active 0;dict set states $w gallery_queue {}
    set button [pageRoot $w records].detail.resources.loadGallery
    if {[winfo exists $button]} {$button configure -text {Show local image thumbnails}}
}
proc ::GX::LibraryBrowser::galleryLoad {w} {
    variable states
    run $w {
        if {[dict get $states $w gallery_active]} {galleryClear $w;status $w {Thumbnail request cancelled. Original Library resources are unchanged.};return}
        if {[dict get $states $w request] ne {} && ![dict get $states $w gallery_active]} {error {Wait for the current request or cancel it before loading thumbnails}}
        set reference [dict get $states $w selected_reference]
        set resources [dict get $states $w selected_entry resources]
        galleryClear $w
        set queue {};set index -1
        foreach resource $resources {
            incr index
            if {[dict get $resource availability] ne {local} || ![string match image/* [::GX::datasetPublicationV2DictDefault $resource media_type {}]]} continue
            lappend queue [list $index $resource]
            if {[llength $queue]==4} break
        }
        dict set states $w gallery_queue $queue
        dict set states $w gallery_count 0;dict set states $w gallery_failures 0
        dict set states $w gallery_active 1
        [pageRoot $w records].detail.resources.loadGallery configure -text {Cancel thumbnails}
        galleryNext $w
    }
}
proc ::GX::LibraryBrowser::galleryNext {w} {
    variable states
    set queue [dict get $states $w gallery_queue]
    if {$queue eq {}} {
        dict set states $w gallery_active 0
        [pageRoot $w records].detail.resources.loadGallery configure -text {Show local image thumbnails}
        status $w "[dict get $states $w gallery_count] local image thumbnails • [dict get $states $w gallery_failures] unavailable previews • exact source SHA retained; no network or Session changes"
        return
    }
    lassign [lindex $queue 0] index resource
    dict set states $w gallery_queue [lrange $queue 1 end]
    set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime viewer retention_seconds 0]]
    set state [dict get $states $w];dict lappend state allocations $allocation;dict set states $w $state
    if {[catch {
        set reference [dict get $states $w selected_reference]
        set staged [::GX::LibraryEntryAcquisitionDispatchAPIv1::_stage [dict create reference $reference resource_index $index] $allocation]
        set maximum [::GX::previewSetting image_max_source_bytes]
        set stream [::open [dict get $staged source_path] rb]
        try {set bytes [read $stream [expr {$maximum+1}]]} finally {::close $stream}
        if {[string length $bytes]>$maximum} {error {Image exceeds configured preview byte limit}}
        # The shared conversion consumes only the bounded in-memory bytes; it
        # does not retain a path/lease and needs no disk-derived thumbnail.
        releaseAllocation $w [dict get $allocation id]
        set generation [dict get $states $w generation]
        set callback [list ::GX::LibraryBrowser::galleryReply $w $generation $reference $index [dict get $resource role] [dict get $staged sha256]]
        dict set states $w request [::GX::datasetPreviewImageMemory $bytes $callback]
        status $w {Preparing bounded local image thumbnail with the shared media owner…}
    } reason]} {
        catch {releaseAllocation $w [dict get $allocation id]}
        dict set states $w gallery_failures [expr {[dict get $states $w gallery_failures]+1}]
        galleryNext $w
    }
}
proc ::GX::LibraryBrowser::galleryReply {w generation reference index role expected response} {
    variable states
    if {![dict exists $states $w] || [dict get $states $w generation]!=$generation || ![dict get $states $w gallery_active] || [dict get $states $w selected_reference] ne $reference} return
    dict set states $w request {}
    if {[catch {guard $w}]} {galleryClear $w;return}
    if {[catch {
        if {![dict get $response ok]} {error [dict get $response error]}
        set result [dict get $response result]
        if {[dict get $result original_sha256] ne $expected} {error {Image source identity changed}}
        set original [image create photo -data [binary decode base64 [dict get $result data_base64]]]
        set factor [expr {max(1,int(ceil(max([image width $original]/120.0,[image height $original]/90.0))))}]
        set thumbnail [image create photo];$thumbnail copy $original -subsample $factor $factor;image delete $original;unset original
        set state [dict get $states $w];dict lappend state gallery_images $thumbnail;dict set states $w $state
        set strip [pageRoot $w records].detail.resources.gallery
        set count [dict get $states $w gallery_count]
        ttk::button $strip.item$count -image $thumbnail -compound top -text $role -command [list ::GX::LibraryBrowser::galleryOpen $w $reference $index]
        dict set states $w gallery_count [expr {$count+1}]
        flow $strip
    } reason]} {
        if {[info exists original]} {catch {image delete $original}}
        dict set states $w gallery_failures [expr {[dict get $states $w gallery_failures]+1}]
    }
    galleryNext $w
}
proc ::GX::LibraryBrowser::galleryOpen {w reference index} {
    variable states
    run $w {
        if {[dict get $states $w selected_reference] ne $reference} {error {Image selection belongs to an earlier Library revision}}
        [pageRoot $w records].detail.resources.values.tree selection set [expr {$index+1}]
        openResource $w
    }
}
proc ::GX::LibraryBrowser::imageDisplay {view original} {
    ttk::frame $view.picture
    canvas $view.picture.canvas -highlightthickness 0 -width 1 -height 1
    ttk::scrollbar $view.picture.x -orient horizontal -command [list $view.picture.canvas xview]
    ttk::scrollbar $view.picture.y -orient vertical -command [list $view.picture.canvas yview]
    $view.picture.canvas configure -xscrollcommand [list $view.picture.x set] -yscrollcommand [list $view.picture.y set]
    grid $view.picture.canvas -row 0 -column 0 -sticky nsew
    grid $view.picture.y -row 0 -column 1 -sticky ns
    grid $view.picture.x -row 1 -column 0 -sticky ew
    grid rowconfigure $view.picture 0 -weight 1;grid columnconfigure $view.picture 0 -weight 1
    pack $view.picture -fill both -expand 1
    set shown [image create photo]
    $view.picture.canvas create image 0 0 -anchor nw -image $shown
    ttk::frame $view.imageActions
    ttk::button $view.imageActions.fit -text {Fit image} -command [list ::GX::LibraryBrowser::imageScale $view $original $shown fit]
    ttk::button $view.imageActions.original -text {Original pixels} -command [list ::GX::LibraryBrowser::imageScale $view $original $shown original]
    pack $view.imageActions.fit $view.imageActions.original -side left -padx 4;pack $view.imageActions -fill x
    bind $view.picture.canvas <Configure> [list ::GX::LibraryBrowser::imageScale $view $original $shown fit]
    bind $view <Destroy> +[list ::GX::LibraryBrowser::imageClosed $view %W $original]
    bind $view <Destroy> +[list ::GX::LibraryBrowser::imageClosed $view %W $shown]
    imageScale $view $original $shown original
}
proc ::GX::LibraryBrowser::imageScale {view original shown mode} {
    if {![winfo exists $view.picture.canvas]} return
    set factor 1
    if {$mode eq {fit}} {
        set x [expr {double([image width $original])/max(1,[winfo width $view.picture.canvas])}]
        set y [expr {double([image height $original])/max(1,[winfo height $view.picture.canvas])}]
        set factor [expr {max(1,int(ceil(max($x,$y))))}]
    }
    $shown blank;$shown copy $original -subsample $factor $factor
    $view.picture.canvas configure -scrollregion [list 0 0 [image width $shown] [image height $shown]]
}
proc ::GX::LibraryBrowser::buildRecords {w} {
    set p [pageRoot $w records]
    ttk::frame $p.search
    ttk::label $p.search.label -text Search
    ttk::entry $p.search.query -width 24
    ttk::combobox $p.search.type -values [linsert [dict keys [dict get $::GX::LibraryBrowser::states $w schemas record_types]] 0 {All record types}] -state readonly -width 20
    $p.search.type set {All record types}
    ttk::button $p.search.go -text Search -command [list ::GX::LibraryBrowser::refresh $w]
    ttk::button $p.search.previous -text Previous -command [list ::GX::LibraryBrowser::page $w -100]
    ttk::button $p.search.next -text Next -command [list ::GX::LibraryBrowser::page $w 100]
    pack $p.search.label $p.search.query $p.search.type $p.search.go $p.search.previous $p.search.next -side left -padx 3
    pack $p.search -fill x
    flow $p.search
    bind $p.search.query <Return> [list ::GX::LibraryBrowser::refresh $w]
    table $p.list {library_id entry_id record_type label};pack $p.list -fill both -expand 1 -pady 5
    bind $p.list.tree <<TreeviewSelect>> [list ::GX::LibraryBrowser::inspect $w]
    ::GX::uiFieldComponentCreate $p.detail tabs {} {} {};pack $p.detail -fill both -expand 1
    foreach {tab label} {properties {Typed properties and provenance} related {Incoming / outgoing relations} resources {Images and documents}} {ttk::frame $p.detail.$tab;$p.detail add $p.detail.$tab -text $label}
    table $p.detail.properties.values {field value};pack $p.detail.properties.values -fill both -expand 1
    ttk::frame $p.detail.related.actions
    ttk::button $p.detail.related.actions.open -text {Open selected related entry} -command [list ::GX::LibraryBrowser::follow $w]
    ttk::button $p.detail.related.actions.acquire -text {Import selected related entries…} -command [list ::GX::LibraryBrowser::acquireRelated $w]
    ttk::button $p.detail.related.actions.back -text Back -command [list ::GX::LibraryBrowser::back $w]
    ttk::button $p.detail.related.actions.forward -text Forward -command [list ::GX::LibraryBrowser::forward $w]
    pack $p.detail.related.actions.open $p.detail.related.actions.back $p.detail.related.actions.forward $p.detail.related.actions.acquire -side left -padx 3;pack $p.detail.related.actions -fill x
    flow $p.detail.related.actions
    ttk::frame $p.detail.related.filters
    ttk::combobox $p.detail.related.filters.direction -values {both outgoing incoming} -state readonly -width 10;$p.detail.related.filters.direction set both
    ttk::combobox $p.detail.related.filters.type -values [linsert [dict keys [dict get $::GX::LibraryBrowser::states $w schemas relations]] 0 {All relation types}] -state readonly -width 25;$p.detail.related.filters.type set {All relation types}
    ttk::entry $p.detail.related.filters.source -width 16
    ttk::button $p.detail.related.filters.query -text Filter -command [list ::GX::LibraryBrowser::relatedRefresh $w 0]
    ttk::button $p.detail.related.filters.previous -text Previous -command [list ::GX::LibraryBrowser::relatedPage $w -100]
    ttk::button $p.detail.related.filters.next -text Next -command [list ::GX::LibraryBrowser::relatedPage $w 100]
    ttk::label $p.detail.related.filters.sourceLabel -text Source
    grid $p.detail.related.filters.direction -row 0 -column 0 -sticky ew -padx 2 -pady 2
    grid $p.detail.related.filters.type -row 0 -column 1 -columnspan 4 -sticky ew -padx 2 -pady 2
    grid $p.detail.related.filters.sourceLabel -row 1 -column 0 -sticky w -padx 2
    foreach {control column} {source 1 query 2 previous 3 next 4} {grid $p.detail.related.filters.$control -row 1 -column $column -sticky ew -padx 2 -pady 2}
    grid columnconfigure $p.detail.related.filters 1 -weight 1
    pack $p.detail.related.filters -fill x
    table $p.detail.related.values {relation_type direction target_kind target_container target_id revision target_sha256 source_id resolution scope evidence};pack $p.detail.related.values -fill both -expand 1
    ttk::button $p.detail.resources.loadGallery -text {Show local image thumbnails} -command [list ::GX::LibraryBrowser::galleryLoad $w]
    pack $p.detail.resources.loadGallery -anchor w -pady 3
    ttk::frame $p.detail.resources.gallery
    pack $p.detail.resources.gallery -fill x
    table $p.detail.resources.values {role availability media_type sha256};pack $p.detail.resources.values -fill both -expand 1
    ttk::button $p.detail.resources.open -text {Open selected original / image} -command [list ::GX::LibraryBrowser::openResource $w]
    pack $p.detail.resources.open -anchor w -pady 3
    ttk::frame $p.actions
    ttk::button $p.actions.acquire -text {Import selected records…} -command [list ::GX::LibraryBrowser::acquire $w]
    ttk::button $p.actions.displayed -text {Import displayed record…} -command [list ::GX::LibraryBrowser::acquireDisplayed $w]
    ttk::button $p.actions.edit -text {Edit displayed record…} -command [list ::GX::LibraryBrowser::edit $w]
    ttk::button $p.actions.receipt -text {Last receipt} -command [list ::GX::LibraryBrowser::showReceipt $w]
    pack $p.actions.acquire $p.actions.displayed $p.actions.edit $p.actions.receipt -side left -padx 3;pack $p.actions -fill x
    flow $p.actions
    pack configure $p.actions -after $p.search
    ttk::label $p.displayed -text {Displayed record: none} -padding 4
    pack $p.displayed -fill x -before $p.detail
    wrapLabel $p.displayed
    foreach tree [list $p.list.tree $p.detail.properties.values.tree $p.detail.related.values.tree $p.detail.resources.values.tree] {$tree configure -height 5}
}
proc ::GX::LibraryBrowser::refresh {w {offset 0}} {
    variable states
    run $w {
        set p [pageRoot $w records];set type [$p.search.type get];if {$type eq {All record types}} {set type {}}
        set result [domain $w search [format {{"query":%s,"record_type":%s,"offset":%d,"limit":100}} [str [$p.search.query get]] [str $type] $offset]]
        dict set states $w rows [dict get $result records];dict set states $w offset $offset
        $p.list.tree delete [$p.list.tree children {}]
        set index 0;foreach row [dict get $result records] {$p.list.tree insert {} end -id [incr index] -values [list [dict get $row library_id] [dict get $row entry_id] [dict get $row record_type] [dict get $row label]]}
        set unavailable [::GX::datasetPublicationV2DictDefault $result unavailable_libraries {}]
        dict set states $w unavailable_libraries $unavailable
        status $w "[llength [dict get $result records]] / [dict get $result total] persistent records • [llength $unavailable] unavailable Libraries • offset $offset • no Session changes"
    }
}
proc ::GX::LibraryBrowser::page {w delta} {refresh $w [expr {max(0,[dict get $::GX::LibraryBrowser::states $w offset]+$delta)}]}
proc ::GX::LibraryBrowser::reference {w} {
    set ids [[pageRoot $w records].list.tree selection]
    if {[llength $ids]!=1} {error {Select exactly one record to inspect}}
    return [dict remove [lindex [dict get $::GX::LibraryBrowser::states $w rows] [expr {[lindex $ids 0]-1}]] label]
}
proc ::GX::LibraryBrowser::inspect {w {reference {}}} {
    variable states
    run $w {
        if {$reference eq {}} {set reference [reference $w]}
        set json [object $reference]
        set entry [domain $w detail [format {{"reference":%s}} $json]]
        galleryClear $w
        dict set states $w selected_reference $reference;dict set states $w selected_entry $entry
        [pageRoot $w records].displayed configure -text "Displayed: [dict get $reference library_id]/[dict get $reference entry_id] • revision [dict get $entry revision] • SHA256 [dict get $entry content_sha256]"
        set p [pageRoot $w records].detail
        $p.properties.values.tree delete [$p.properties.values.tree children {}]
        dict for {key value} [dict get $entry fields] {$p.properties.values.tree insert {} end -values [list $key $value]}
        dict for {key value} [dict get $entry provenance] {$p.properties.values.tree insert {} end -values [list provenance.$key $value]}
        set related [domain $w related [format {{"reference":%s,"limit":100}} $json]]
        dict set states $w relations [dict get $related records]
        $p.related.values.tree delete [$p.related.values.tree children {}]
        set n 0;foreach edge [dict get $related records] {
            set direction [expr {[dict get $edge from_reference library_id] eq [dict get $reference library_id] && [dict get $edge from_reference entry_id] eq [dict get $reference entry_id]?{outgoing}:{incoming}}]
            $p.related.values.tree insert {} end -id [incr n] -values [relationCells $w $edge $direction]
        }
        $p.resources.values.tree delete [$p.resources.values.tree children {}]
        set n 0;foreach resource [dict get $entry resources] {$p.resources.values.tree insert {} end -id [incr n] -values [list [dict get $resource role] [dict get $resource availability] [::GX::datasetPublicationV2DictDefault $resource media_type {}] [::GX::datasetPublicationV2DictDefault $resource sha256 {}]]}
        status $w "[dict get $entry label] • [dict get $entry record_type] • revision [dict get $entry revision] • [dict get $related total] related assertions (first 100 shown)"
        set inspected 1
    }
}
proc ::GX::LibraryBrowser::relatedTarget {w edge} {
    set reference [dict get $::GX::LibraryBrowser::states $w selected_reference]
    set from [dict get $edge from_reference]
    if {[dict get $from library_id] eq [dict get $reference library_id] && [dict get $from entry_id] eq [dict get $reference entry_id]} {return [dict get $edge target]}
    return $from
}
proc ::GX::LibraryBrowser::relationCells {w edge direction} {
    set target [relatedTarget $w $edge];set kind [dict get $target kind]
    set values [list [dict get $edge relation_type] $direction $kind]
    switch $kind {
        library_entry {set container library_id;set identity entry_id;set hash content_sha256}
        canonical_dataset {set container session_id;set identity dataset_id;set hash sha256}
        external_source_entity {set container source_id;set identity external_id;set hash sha256}
        default {set container {};set identity {};set hash {}}
    }
    foreach key [list $container $identity revision $hash] {lappend values [::GX::datasetPublicationV2DictDefault $target $key {}]}
    lappend values [dict get $edge source_id] [dict get $edge resolution_status] [::GX::datasetPublicationV2DictDefault $edge scope_status unfiltered] [dict get $edge evidence]
    return $values
}
proc ::GX::LibraryBrowser::follow {w} {
    variable states
    run $w {
        set selected [[pageRoot $w records].detail.related.values.tree selection]
        if {[llength $selected]!=1} {error {Select one relation}}
        set edge [lindex [dict get $states $w relations] [expr {[lindex $selected 0]-1}]]
        set reference [dict get $states $w selected_reference]
        set target [relatedTarget $w $edge]
        if {[dict get $target kind] eq {external_source_entity}} {
            set parameters [dict create source_id [dict get $target source_id] external_id [dict get $target external_id] record_type [dict get $target record_type]]
            set candidates [domain $w resolve_external_id [object $parameters]]
            if {![llength [dict get $candidates records]]} {error {No exact local candidate for this external source identity. Its evidence remains unresolved; no implicit remote fetch or import.}}
            set labels {};set mapping {};foreach candidate [dict get $candidates records] {set label "[dict get $candidate library_id]/[dict get $candidate entry_id] revision [dict get $candidate revision]";lappend labels $label;dict set mapping $label $candidate}
            dict set states $w external_candidates $mapping
            ::GX::uiFieldFormCreate $w.externalCandidate {Review exact external identity candidate} [dict create candidate [dict create type choice values $labels label {Pinned local candidate}]] [dict create candidate [lindex $labels 0]] [list ::GX::LibraryBrowser::externalCandidate $w] [dict get $::GX::LibraryBrowser::states $w owner]
            return
        }
        if {[::GX::datasetPublicationV2DictDefault $edge scope_status {}] eq {outside_scope}} {error [dict get $edge scope_reason]}
        if {[dict get $target kind] eq {canonical_dataset}} {
            ::GX::datasetViewerOpenReference $target
            status $w {Opened the exact current-Session Dataset through its existing read-only Viewer. The Library assertion is unchanged.}
            return
        }
        if {[dict get $target kind] ne {library_entry}} {error {Unsupported relation anchor; the original assertion is retained}}
        if {[inspect $w $target] eq {1}} {set state [dict get $states $w];dict lappend state history $reference;dict set state forward_history {};dict set states $w $state}
    }
}
proc ::GX::LibraryBrowser::back {w} {
    variable states
    set history [dict get $states $w history]
    if {$history eq {}} return
    set old [dict get $states $w selected_reference]
    if {[inspect $w [lindex $history end]] eq {1}} {set state [dict get $states $w];dict lappend state forward_history $old;dict set state history [lrange $history 0 end-1];dict set states $w $state}
}
proc ::GX::LibraryBrowser::buildSources {w} {
    variable states
    set p [pageRoot $w sources]
    ttk::frame $p.top
    ttk::label $p.top.label -text {Registered source}
    ttk::combobox $p.top.source -state readonly -width 22
    ttk::button $p.top.reload -text Refresh -command [list ::GX::LibraryBrowser::sourceList $w]
    ttk::button $p.top.register -text {Register installed connector…} -command [list ::GX::LibraryBrowser::register $w]
    ttk::button $p.top.credentials -text {Credentials…} -command [list ::GX::LibraryBrowser::credentials $w]
    pack $p.top.label $p.top.source $p.top.reload $p.top.register $p.top.credentials -side left -padx 3;pack $p.top -fill x
    ttk::frame $p.lookup
    ttk::label $p.lookup.label -text {Query / exact source identity}
    ttk::entry $p.lookup.query -width 28
    ttk::button $p.lookup.search -text {Look up (read only)} -command [list ::GX::LibraryBrowser::lookup $w]
    ttk::button $p.lookup.cancel -text {Cancel request} -command [list ::GX::LibraryBrowser::cancel $w]
    pack $p.lookup.label $p.lookup.query $p.lookup.search $p.lookup.cancel -side left -padx 3;pack $p.lookup -fill x -pady 4
    bind $p.lookup.query <Return> [list ::GX::LibraryBrowser::lookup $w]
    table $p.results {entry_id metadata};pack $p.results -fill both -expand 1
    ttk::button $p.preview -text {Preview selected exact record} -command [list ::GX::LibraryBrowser::sourcePreview $w]
    pack $p.preview -anchor w -pady 3
    table $p.selection {entry_id record_type label resources};pack $p.selection -fill both -expand 1
    bind $p.selection.tree <Double-1> [list ::GX::LibraryBrowser::sourceInspect $w]
    ttk::button $p.inspect -text {Inspect source record…} -command [list ::GX::LibraryBrowser::sourceInspect $w]
    pack $p.inspect -anchor w -pady 3
    ttk::label $p.hint -text {Select any subset above. Source lookup and preview do not save Library entries or create Datasets.} -wraplength 1000
    pack $p.hint -fill x;wrapLabel $p.hint
    ttk::frame $p.options
    ttk::label $p.options.label -text {Destination Library ID prefix}
    ttk::entry $p.options.prefix -width 24;$p.options.prefix insert 0 personal
    ttk::checkbutton $p.options.files -text {Download selected linked files} -variable ::GX::LibraryBrowser::download($w)
    set ::GX::LibraryBrowser::download($w) 1
    ttk::checkbutton $p.options.alternatives -text {Include reviewed source suggestions} -variable ::GX::LibraryBrowser::alternatives($w)
    set ::GX::LibraryBrowser::alternatives($w) 0
    pack $p.options.label $p.options.prefix $p.options.files $p.options.alternatives -side left -padx 3;pack $p.options -fill x -pady 3
    table $p.suggestions {sku native_class evidence};pack $p.suggestions -fill both -expand 1
    ttk::button $p.suggestionPreview -text {Review selected suggestion…} -command [list ::GX::LibraryBrowser::suggestionPreview $w]
    pack $p.suggestionPreview -anchor w
    ttk::button $p.commit -text {Import selected into persistent Libraries} -command [list ::GX::LibraryBrowser::sourceImport $w]
    pack $p.commit -anchor w -pady 5
    foreach row [list $p.top $p.lookup $p.options] {flow $row}
    foreach table [list $p.results.tree $p.selection.tree $p.suggestions.tree] {$table configure -height 5}
    sourceList $w
}
proc ::GX::LibraryBrowser::sourceList {w} {
    set ids {}
    if {[dict get $::GX::LibraryBrowser::states $w scope] eq {}} {
        foreach record [::GX::ScientificLibraryManagerAPIv1::listRegisteredLibraries] {if {[dict get $record mode] eq {remote}} {lappend ids [dict get $record library_id]}}
    } else {foreach record [dict get [scopeDescribe $w] sources] {lappend ids [dict get $record library_id]}}
    [pageRoot $w sources].top.source configure -values $ids
    if {[llength $ids] && [[pageRoot $w sources].top.source get] ni $ids} {[pageRoot $w sources].top.source set [lindex $ids 0]}
    if {![llength $ids]} {[pageRoot $w sources].top.source set {}}
}
proc ::GX::LibraryBrowser::register {w} {
    run $w {
        set choices [dict keys [dict get [scopeDescribe $w] connectors]]
        if {$choices eq {}} {
            if {[dict get $::GX::LibraryBrowser::states $w scope] ne {}} {error {No installed Source Connector matches this Library view scope. View its exact scope and availability, or explicitly use an eligible view.}}
            error {Install a Library Source Connector with the existing Plugin Manager}
        }
        ::GX::uiFieldFormCreate $w.register {Register Library Source Connector} [dict create connector [dict create type choice values $choices label Connector] library_id {type string label {Stable source registration ID}} display_name {type string label {Source display name}}] [dict create connector [lindex $choices 0]] [list ::GX::LibraryBrowser::registerCommit $w] [dict get $::GX::LibraryBrowser::states $w owner]
    }
}
proc ::GX::LibraryBrowser::registerCommit {w values} {
    run $w {
        set scope [dict get $::GX::LibraryBrowser::states $w scope]
        if {[dict exists $scope library_ids] && [dict get $values library_id] ni [dict get $scope library_ids]} {error {Choose a source registration ID within this Library view scope}}
        set info [dict get [scopeDescribe $w] connectors [dict get $values connector]]
        set type [lindex [dict get $info library_types] 0]
        ::GX::ScientificLibraryManagerAPIv1::registerLibrary [dict create library_id [dict get $values library_id] library_type $type mode remote display_name [dict get $values display_name] config.connector [dict get $values connector]]
        sourceList $w
        status $w {Source registered. Connection has not been probed. Use Look up for an on-demand source check.}
    }
}
proc ::GX::LibraryBrowser::credentials {w} {
    run $w {
        set source [[pageRoot $w sources].top.source get]
        if {$source eq {}} {error {Choose a registered source}}
        ::GX::_scientificLibraryCredentialsDialog [dict get $::GX::LibraryBrowser::states $w owner]
    }
}
proc ::GX::LibraryBrowser::cancel {w} {
    variable states
    if {[dict get $states $w gallery_active]} {galleryClear $w;status $w {Thumbnail request cancelled. Original Library resources are unchanged.};return}
    if {[dict get $states $w request] ne {}} {::GX::scriptJobRequestCancel [dict get $states $w request];status $w {Cancellation requested. A committed Library batch remains saved; wait for its receipt.}}
}
proc ::GX::LibraryBrowser::request {w operation arguments stage} {
    variable states
    if {[dict get $states $w request] ne {}} {error {Wait for the current source request or cancel it}}
    if {[dict get $states $w scope] ne {}} {
        if {$operation eq {content}} {
            lassign $arguments source action parameters
            set eligible {};foreach row [dict get [scopeDescribe $w] sources] {lappend eligible [dict get $row library_id]}
            if {$source ni $eligible} {error {Source registration is outside or unavailable in this Library view scope}}
            set options [::GX::datasetPublicationV2DictDefault $parameters options_json {{}}]
            dict set parameters options_json [scopedJson $w $options]
            set arguments [list $source $action $parameters]
        } elseif {$operation eq {source_import}} {lassign $arguments source json;set arguments [list $source [scopedJson $w $json]]}
    }
    set generation [expr {[dict get $states $w generation]+1}];dict set states $w generation $generation
    set token [::GX::ScientificLibraryManagerAPIv1::libraryRequest $operation $arguments [list ::GX::LibraryBrowser::reply $w $generation $stage]]
    dict set states $w request $token
    status $w {Source request in progress…}
}
proc ::GX::LibraryBrowser::lookup {w} {
    variable states
    run $w {
        dict set states $w source_rows {};dict set states $w bundle {};dict set states $w alternative_skus {}
        [pageRoot $w sources].selection.tree delete [[pageRoot $w sources].selection.tree children {}]
        set source [[pageRoot $w sources].top.source get];if {$source eq {}} {error {Register and select a source first}}
        dict set states $w source_library $source
        request $w content [list $source search_entries [dict create query_json [str [[pageRoot $w sources].lookup.query get]] limit 50]] search
    }
}
proc ::GX::LibraryBrowser::sourcePreview {w} {
    variable states
    run $w {
        set ids [[pageRoot $w sources].results.tree selection]
        if {[llength $ids]!=1} {error {Select one exact source result; ambiguity must be resolved before import}}
        set row [lindex [dict get $states $w source_rows] [expr {[lindex $ids 0]-1}]]
        dict set states $w primary_source_entry [dict get $row entry_id]
        request $w content [list [dict get $states $w source_library] read_entry [dict create entry_id [dict get $row entry_id]]] preview
    }
}
proc ::GX::LibraryBrowser::suggestionPreview {w} {
    variable states
    run $w {
        if {!$::GX::LibraryBrowser::alternatives($w)} {error {Enable Include reviewed source suggestions to inspect an optional candidate}}
        set ids [[pageRoot $w sources].suggestions.tree selection]
        if {[llength $ids]!=1} {error {Choose one actual supplier suggestion}}
        set suggestion [lindex [dict get $states $w bundle suggestions] [expr {[lindex $ids 0]-1}]]
        set sku [dict get $suggestion sku]
        dict set states $w pending_alternative $sku
        request $w content [list [dict get $states $w source_library] read_entry [dict create entry_id $sku]] alternative
    }
}
proc ::GX::LibraryBrowser::reply {w generation stage response} {
    variable states
    if {![dict exists $states $w] || [dict get $states $w generation]!=$generation || ![winfo exists $w]} return
    dict set states $w request {}
    run $w {
        if {![dict get $response ok]} {error [dict get $response error]}
        set result [dict get $response result];set p [pageRoot $w sources]
        switch $stage {
            search {
                dict set states $w source_rows [dict get $result records]
                $p.results.tree delete [$p.results.tree children {}]
                set n 0;foreach row [dict get $result records] {$p.results.tree insert {} end -id [incr n] -values [list [dict get $row entry_id] [dict get $row metadata]]}
                status $w {Lookup completed without saving Library entries. Select an exact result and preview.}
            }
            preview - alternative {
                set bundle [dict get $result payload]
                if {$stage eq {alternative}} {
                    set old [dict get $states $w bundle]
                    dict set old entries [concat [dict get $old entries] [dict get $bundle entries]]
                    set bundle $old
                    set skus [::GX::datasetPublicationV2DictDefault [dict get $states $w] alternative_skus {}]
                    lappend skus [dict get $states $w pending_alternative]
                    dict set states $w alternative_skus [lsort -unique $skus]
                }
                dict set states $w bundle $bundle
                $p.commit state [expr {[::GX::datasetPublicationV2DictDefault $bundle persistent_import_available 1]?{!disabled}:{disabled}}]
                $p.selection.tree delete [$p.selection.tree children {}]
                set n 0;foreach row [dict get $bundle entries] {
                    set entry [dict get $row entry]
                    $p.selection.tree insert {} end -id [incr n] -values [list [dict get $entry entry_id] [dict get $entry record_type] [dict get $entry label] [llength [dict get $entry resources]]]
                }
                $p.suggestions.tree delete [$p.suggestions.tree children {}]
                set n 0;foreach suggestion [dict get $bundle suggestions] {$p.suggestions.tree insert {} end -id [incr n] -values [list [dict get $suggestion sku] [dict get $suggestion native_class] [dict get $suggestion evidence]]}
                if {![::GX::datasetPublicationV2DictDefault $bundle persistent_import_available 1]} {
                    status $w [dict get $bundle persistence_reason]
                } else {status $w {Preview ready. Select only the records and resources to save. Suggestions are source claims; engineering compatibility is unverified.}}
            }
            image {sourceImageReply $w $result}
            imported {dict set states $w last_receipt $result;refresh $w;status $w "Library source import: [dict get $result status]. View last operation receipt for per-Library results."}
        }
    }
}
proc ::GX::LibraryBrowser::sourceImport {w} {
    variable states
    run $w {
        set p [pageRoot $w sources];set chosen [$p.selection.tree selection]
        if {$chosen eq {}} {error {Select the records to preserve in Libraries}}
        set bundle [dict get $states $w bundle];set ids {};set destinations {}
        foreach id $chosen {
            set row [lindex [dict get $bundle entries] [expr {$id-1}]]
            lappend ids [dict get $row entry entry_id]
            dict set destinations [dict get $row library_type] "[$p.options.prefix get]-[dict get $row library_type]"
        }
        set alternativeSkus {};if {$::GX::LibraryBrowser::alternatives($w)} {set alternativeSkus [::GX::datasetPublicationV2DictDefault [dict get $states $w] alternative_skus {}]}
        set primary [dict get [lindex [dict get $bundle entries] 0] entry]
        set expected [::GX::datasetPublicationV2DictDefault $bundle source_record_sha256 [::GX::datasetPublicationV2DictDefault [dict get $primary provenance] original_record_sha256 {}]]
        set parameters [format {"entry_id":%s,"selected_ids":%s,"expected_source_sha256":%s,"download_assets":%s,"selected_alternatives":%s} [str [dict get $states $w primary_source_entry]] [array $ids] [str $expected] [expr {$::GX::LibraryBrowser::download($w)?{true}:{false}}] [array $alternativeSkus]]
        set scope [dict get $states $w scope]
        if {[dict exists $scope library_ids]} {
            set fields {};set initial {}
            set libraries [::GX::ScientificLibraryManagerAPIv1::listRegisteredLibraries]
            foreach type [dict keys $destinations] {
                set choices {};foreach record $libraries {
                    if {[dict get $record library_id] in [dict get $scope library_ids] && [dict get $record library_type] eq $type && [dict get $record mode] eq {managed} && [dict get $record state] eq {installed}} {lappend choices [dict get $record library_id]}
                }
                if {$choices eq {}} {error "No installed persistent Library destination for $type matches this view's Library IDs. Choose a view scope containing both the source registration and the intended destination Library."}
                dict set fields $type [dict create type choice values $choices label "Destination Library for $type"]
                dict set initial $type [lindex $choices 0]
            }
            ::GX::uiFieldFormCreate $w.sourceDestinations {Review scoped persistent Library destinations} $fields $initial [list ::GX::LibraryBrowser::sourceImportDestinations $w [dict get $states $w source_library] $parameters] [dict get $states $w owner]
            reviewSummary $w.sourceDestinations {Exact selected source records} "Registered source: [dict get $states $w source_library]\nSource identity: [dict get $states $w primary_source_entry]\nSelected entry IDs: [join $ids {, }]\nOriginal source record SHA256: $expected\nOnly the explicitly selected records enter the chosen persistent Libraries; no Session Dataset is created."
            return
        }
        set parameters \{$parameters,\"destinations\":[object $destinations]\}
        request $w source_import [list [dict get $states $w source_library] $parameters] imported
    }
}
proc ::GX::LibraryBrowser::sourceImportDestinations {w source parameters destinations} {
    run $w {
        set parameters \{$parameters,\"destinations\":[object $destinations]\}
        request $w source_import [list $source $parameters] imported
        catch {destroy $w.sourceDestinations}
    }
}
proc ::GX::LibraryBrowser::manualRoot {w} {return [pageRoot $w manual].viewport.content}
proc ::GX::LibraryBrowser::buildManual {w} {
    set tab [pageRoot $w manual]
    canvas $tab.viewport -highlightthickness 0
    ttk::scrollbar $tab.scroll -orient vertical -command [list $tab.viewport yview]
    $tab.viewport configure -yscrollcommand [list $tab.scroll set]
    ttk::frame $tab.viewport.content -padding 6
    $tab.viewport create window 0 0 -anchor nw -window $tab.viewport.content -tags content
    bind $tab.viewport <Configure> [list $tab.viewport itemconfigure content -width %w]
    bind $tab.viewport.content <Configure> [list $tab.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $tab.scroll -side right -fill y
    pack $tab.viewport -fill both -expand 1
    set p $tab.viewport.content
    ttk::frame $p.identity
    ttk::label $p.identity.typeLabel -text {Record schema}
    set writableTypes {}
    dict for {type definition} [dict get $::GX::LibraryBrowser::states $w schemas record_types] {
        if {![dict exists $definition normalized_projection]} {lappend writableTypes $type}
    }
    ttk::combobox $p.identity.type -state readonly -values $writableTypes -width 32
    ttk::label $p.identity.sourceLabel -text {Source / attribution}
    ttk::entry $p.identity.source -width 36
    grid $p.identity.typeLabel -row 0 -column 0 -sticky w -padx 4 -pady 4
    grid $p.identity.type -row 0 -column 1 -sticky ew -padx 4 -pady 4
    grid $p.identity.sourceLabel -row 1 -column 0 -sticky w -padx 4 -pady 4
    grid $p.identity.source -row 1 -column 1 -sticky ew -padx 4 -pady 4
    grid columnconfigure $p.identity 1 -weight 1
    pack $p.identity -fill x
    ttk::frame $p.names
    foreach {key label default} {library {Library ID} personal label {Entry label} {} entry {Stable entry ID (blank creates new)} {}} {
        ttk::label $p.names.${key}Label -text $label -wraplength 180;ttk::entry $p.names.$key -width 26;$p.names.$key insert 0 $default
        set row [expr {$key eq {library}?0:($key eq {label}?1:2)}]
        grid $p.names.${key}Label -row $row -column 0 -sticky w -padx 4 -pady 3
        grid $p.names.$key -row $row -column 1 -sticky ew -padx 4 -pady 3
    }
    grid columnconfigure $p.names 1 -weight 1
    pack $p.names -fill x -pady 4
    ttk::frame $p.fields
    ttk::frame $p.fields.content
    pack $p.fields.content -fill x
    pack $p.fields -fill x
    ttk::label $p.pasteLabel -text {Paste original specifications (name TAB value or name: value; parsed according to schema)}
    pack $p.pasteLabel -fill x;wrapLabel $p.pasteLabel
    text $p.paste -height 5 -wrap none -undo 1;pack $p.paste -fill x
    ttk::labelframe $p.suggestions -text {Optional pasted suggestions — engineering compatibility unverified} -padding 6
    set s $p.suggestions
    set ::GX::LibraryBrowser::manualInclude($w) 0
    ttk::checkbutton $s.include -text {Include individually checked candidates (off by default)} -variable ::GX::LibraryBrowser::manualInclude($w)
    pack $s.include -anchor w
    ttk::label $s.help -text {Paste TSV with a candidate_id header and declared field names. Candidate keys identify source records; they do not assert equivalent parts. Parse, review, then check only the desired rows.} -wraplength 680
    pack $s.help -fill x;wrapLabel $s.help
    text $s.paste -height 4 -wrap none -undo 1;pack $s.paste -fill x
    ttk::frame $s.filter
    ttk::label $s.filter.label -text {Filter reviewed rows}
    ttk::entry $s.filter.query
    pack $s.filter.label -side left;pack $s.filter.query -side left -fill x -expand 1
    bind $s.filter.query <KeyRelease> [list ::GX::LibraryBrowser::manualCandidatesRender $w]
    pack $s.filter -fill x -pady 3
    ttk::frame $s.actions
    foreach {key title command} {parse {Parse candidates} manualCandidates all {Check all} manualCandidatesAll none {Uncheck all} manualCandidatesNone header {Copy schema TSV header} manualCandidateHeader} {
        ttk::button $s.actions.$key -text $title -command [list ::GX::LibraryBrowser::$command $w]
        pack $s.actions.$key -side left -padx 3
    }
    pack $s.actions -fill x
    table $s.rows {checked candidate label fields source};$s.rows.tree configure -height 4
    pack $s.rows -fill x
    ttk::label $s.count -text {No candidates parsed};pack $s.count -anchor w
    ttk::button $s.inspect -text {Inspect selected candidate…} -command [list ::GX::LibraryBrowser::manualCandidateInspect $w]
    pack $s.inspect -anchor w
    bind $s.rows.tree <Double-1> [list ::GX::LibraryBrowser::manualCandidateToggle $w]
    bind $s.rows.tree <space> "[list ::GX::LibraryBrowser::manualCandidateToggle $w]\nbreak"
    bind $s.rows.tree <Return> "[list ::GX::LibraryBrowser::manualCandidateInspect $w]\nbreak"
    ttk::frame $s.claim
    foreach {key title} {relation {Declared relation} source {Suggestion source / attribution} kind {Assertion by} evidence {Original suggestion / differences}} {
        ttk::label $s.claim.${key}label -text $title -wraplength 180
        if {$key in {relation kind}} {ttk::combobox $s.claim.$key -state readonly} else {ttk::entry $s.claim.$key}
        set n [expr {$key eq {relation}?0:($key eq {source}?1:($key eq {kind}?2:3))}]
        grid $s.claim.${key}label -row $n -column 0 -sticky w -padx 3 -pady 3
        grid $s.claim.$key -row $n -column 1 -sticky ew -padx 3 -pady 3
    }
    $s.claim.kind configure -values {user source};$s.claim.kind set user
    grid columnconfigure $s.claim 1 -weight 1;pack $s.claim -fill x
    pack $s -fill x -pady 6
    ttk::frame $p.files
    ttk::label $p.files.label -text {Local file role}
    ttk::combobox $p.files.role -values {photo datasheet drawing pinout footprint_illustration document} -width 22;$p.files.role set document
    ttk::button $p.files.add -text {Add downloaded PDF / image…} -command [list ::GX::LibraryBrowser::attach $w]
    ttk::button $p.files.clear -text {Clear selected files} -command [list ::GX::LibraryBrowser::clearAttachments $w]
    grid $p.files.label -row 0 -column 0 -sticky w -padx 3
    grid $p.files.role -row 0 -column 1 -sticky ew -padx 3
    grid $p.files.add -row 1 -column 0 -columnspan 2 -sticky w -pady 3
    grid $p.files.clear -row 1 -column 2 -sticky w -pady 3
    pack $p.files -fill x -pady 3
    ttk::label $p.fileSummary -text {No local attachments} -wraplength 700;pack $p.fileSummary -fill x;wrapLabel $p.fileSummary
    table $p.attachments {role filename sha256}
    $p.attachments.tree configure -height 3
    pack $p.attachments -fill x
    bind $p.attachments.tree <Double-1> [list ::GX::LibraryBrowser::manualOpenAttachment $w]
    ttk::button $p.openAttachment -text {Preview selected original file} -command [list ::GX::LibraryBrowser::manualOpenAttachment $w]
    pack $p.openAttachment -anchor w
    ttk::frame $p.actions
    ttk::button $p.actions.preview -text {Preview typed record} -command [list ::GX::LibraryBrowser::manualPreview $w]
    ttk::button $p.actions.save -text {Save into persistent Library} -command [list ::GX::LibraryBrowser::manualSave $w]
    ttk::button $p.actions.cancel -text {Cancel draft} -command [list ::GX::LibraryBrowser::manualCancel $w]
    pack $p.actions.preview $p.actions.save $p.actions.cancel -side left -padx 3;pack $p.actions -fill x -pady 4
    bind $p.identity.type <<ComboboxSelected>> [list ::GX::LibraryBrowser::manualFields $w]
    set types [$p.identity.type cget -values]
    if {[llength $types]} {
        set initial [lindex $types 0]
        foreach type $types {
            if {[dict exists $::GX::LibraryBrowser::states $w schemas record_types $type manual_templates]} {set initial $type;break}
        }
        $p.identity.type set $initial;manualFields $w
    } else {
        dict set ::GX::LibraryBrowser::states $w manual_controls {}
        dict set ::GX::LibraryBrowser::states $w manual_editors {}
        dict set ::GX::LibraryBrowser::states $w previous {}
        dict set ::GX::LibraryBrowser::states $w manual_candidates {}
        dict set ::GX::LibraryBrowser::states $w manual_selected {}
        $p.actions.preview state disabled;$p.actions.save state disabled
        $s.help configure -text {No writable record schema matches this Library view scope. Managed provider metadata is read-only; no unrestricted template is substituted.}
        foreach control {include actions.parse actions.all actions.header} {$s.$control configure -state disabled}
    }
    foreach row [list $s.actions $p.actions] {flow $row}
    ::GX::uiFieldScrollAreaAttach $tab.viewport $tab.viewport.content
}
proc ::GX::LibraryBrowser::manualSelectorsRestore {w} {
    if {![dict exists $::GX::LibraryBrowser::states $w pages manual]} return
    set state [dict get $::GX::LibraryBrowser::states $w]
    if {[::GX::datasetPublicationV2DictDefault $state closing 0] || [::GX::datasetPublicationV2DictDefault $state destroyed 0]} return
    set p [manualRoot $w]
    if {![winfo exists $p]} return
    if {[winfo exists $p.identity.type] && [dict exists $state manual_record_type]} {$p.identity.type set [dict get $state manual_record_type]}
    if {[winfo exists $p.fields.content.template] && [dict exists $state manual_template]} {$p.fields.content.template set [dict get $state manual_template]}
}
proc ::GX::LibraryBrowser::manualContextReady {w} {
    if {[catch {guard $w} message]} {
        manualSelectorsRestore $w
        status $w $message
        return 0
    }
    return 1
}
proc ::GX::LibraryBrowser::manualFields {w {reset 0}} {
    variable states
    # Native selectors change their own value before this callback. Refuse and
    # restore that selector BEFORE touching the existing draft's widgets.
    # reset=1 is reserved for deliberate internal Edit/Cancel initialization.
    if {!$reset && ![manualContextReady $w]} {return 0}
    set p [manualRoot $w];set type [$p.identity.type get]
    if {!$reset && [dict exists $states $w manual_record_type] && $type eq [dict get $states $w manual_record_type]} {return 1}
    if {$type ne {} && ![dict exists $states $w schemas record_types $type]} {manualSelectorsRestore $w;status $w {This schema is unavailable; reopen the Viewer for current providers.};return 0}
    foreach child [winfo children $p.fields.content] {destroy $child}
    dict set states $w manual_record_type $type;dict set states $w manual_template {}
    if {![dict exists $states $w schemas record_types $type]} {
        dict set states $w manual_controls {};dict set states $w manual_editors {};dict set states $w previous {}
        dict set states $w manual_candidates {};dict set states $w manual_selected {}
        return
    }
    set definition [dict get $states $w schemas record_types $type]
    set controls {};set editors {};set n 0
    if {[dict exists $definition manual_templates]} {
        ttk::label $p.fields.content.templateLabel -text {Field template}
        ttk::combobox $p.fields.content.template -state readonly -values [dict keys [dict get $definition manual_templates]]
        $p.fields.content.template set [lindex [dict keys [dict get $definition manual_templates]] 0]
        grid $p.fields.content.templateLabel -row $n -column 0 -sticky w -padx 6 -pady 8
        grid $p.fields.content.template -row $n -column 1 -sticky ew -padx 6 -pady 8
        bind $p.fields.content.template <<ComboboxSelected>> [list ::GX::LibraryBrowser::manualTemplate $w]
    }
    dict for {key fieldDefinition} [dict get $definition fields] {
        set field $p.fields.content.f[incr n]
        set label [::GX::datasetPublicationV2DictDefault $fieldDefinition label $key]
        set editor [::GX::datasetPublicationV2DictDefault $fieldDefinition editor entry]
        ttk::label ${field}label -wraplength 190 -text "$label[expr {[::GX::datasetPublicationV2DictDefault $fieldDefinition required 0]?{ *}:{}}]"
        if {$editor eq {table}} {
            table $field [dict keys [dict get $fieldDefinition columns]]
            $field.tree configure -height 5
            dict for {column columnDefinition} [dict get $fieldDefinition columns] {
                $field.tree heading $column -text [::GX::datasetPublicationV2DictDefault $columnDefinition label $column]
                $field.tree column $column -width 155
            }
            ttk::frame $field.actions
            foreach {action title} {add Add edit Edit remove Remove} {
                ttk::button $field.actions.$action -text $title -command [list ::GX::LibraryBrowser::tableEdit $w $key $action]
                pack $field.actions.$action -side left -padx 3
            }
            grid $field.actions -row 2 -column 0 -sticky ew -pady 3
            flow $field.actions
            dict set states $w table_rows $key {}
            bind $field.tree <Double-1> [list ::GX::LibraryBrowser::tableEdit $w $key edit]
            bind $field.tree <Delete> [list ::GX::LibraryBrowser::tableEdit $w $key remove]
        } elseif {$editor eq {multiline}} {text $field -height 3 -wrap word -undo 1
        } elseif {$editor eq {choice}} {ttk::combobox $field -values [dict get $fieldDefinition choices]
        } else {ttk::entry $field -width 28}
        grid ${field}label -row $n -column 0 -sticky nw -padx 6 -pady 5
        grid $field -row $n -column 1 -sticky ew -padx 6 -pady 5
        dict set controls $key $field
        dict set editors $key $editor
    }
    grid columnconfigure $p.fields.content 1 -weight 1
    dict set states $w manual_controls $controls;dict set states $w manual_editors $editors;dict set states $w previous {}
    if {[dict exists $definition manual_templates]} {manualTemplate $w 1}
    manualSuggestionsReset $w
    manualDestination $w $definition
}
proc ::GX::LibraryBrowser::manualDestination {w definition} {
    set scope [dict get $::GX::LibraryBrowser::states $w scope]
    if {![dict exists $scope library_ids]} return
    set p [manualRoot $w];set choices {}
    foreach record [::GX::ScientificLibraryManagerAPIv1::listRegisteredLibraries] {
        if {[dict get $record library_id] in [dict get $scope library_ids] && [dict get $record mode] eq {managed} && [dict get $record library_type] eq [dict get $definition library_type] && [dict get $record state] eq {installed}} {lappend choices [dict get $record library_id]}
    }
    if {[$p.names.library get] ni $choices} {$p.names.library delete 0 end;$p.names.library insert 0 [lindex $choices 0]}
    foreach action {preview save} {$p.actions.$action state [expr {[llength $choices]?{!disabled}:{disabled}}]}
    if {$choices eq {}} {$p.suggestions.help configure -text {No installed persistent Library destination for this schema matches the declared Library IDs. Remote source registrations cannot store a manual record. Use an eligible view/destination; no unrestricted Library is substituted.}}
}
proc ::GX::LibraryBrowser::manualSuggestionsReset {w} {
    variable states
    set s [manualRoot $w].suggestions
    set type [[manualRoot $w].identity.type get];set relations {}
    set columns [dict keys [dict get $states $w schemas record_types $type fields]]
    $s.help configure -text "Paste TSV with distinct candidate_id keys and actual typed values. Available schema columns: [join $columns {, }]. Optional metadata: label, source_id. Parse, inspect and check only the desired rows; these are attributed suggestions, not verified compatible parts."
    dict for {name schema} [dict get $states $w schemas relations] {
        if {[::GX::datasetPublicationV2DictDefault $schema manual_suggestion 0] && $type in [dict get $schema from_types] && $type in [dict get $schema to_types]} {lappend relations $name}
    }
    $s.claim.relation configure -values $relations;$s.claim.relation set [lindex $relations 0]
    $s.include configure -state [expr {[llength $relations]?{normal}:{disabled}}]
    set ::GX::LibraryBrowser::manualInclude($w) 0
    dict set states $w manual_candidates {};dict set states $w manual_selected {}
    $s.rows.tree delete [$s.rows.tree children {}]
    $s.filter.query delete 0 end;$s.count configure -text {No candidates parsed}
}
proc ::GX::LibraryBrowser::manualCandidateHeader {w} {
    variable states
    set type [[manualRoot $w].identity.type get]
    set columns [linsert [dict keys [dict get $states $w schemas record_types $type fields]] 0 candidate_id]
    clipboard clear;clipboard append [join $columns \t]
    status $w {Current provider schema header copied. Paste into a local table or candidate box and add your own actual source values.}
}
proc ::GX::LibraryBrowser::manualCandidates {w} {
    variable states
    run $w {
        set s [manualRoot $w].suggestions
        set result [domain $w manual_candidates [format {{"record_type":%s,"text":%s,"library_id":%s,"source_id":%s}} [str [[manualRoot $w].identity.type get]] [str [$s.paste get 1.0 end-1c]] [str [[manualRoot $w].names.library get]] [str [[manualRoot $w].identity.source get]]]]
        dict set states $w manual_candidates [dict get $result candidates]
        dict set states $w manual_candidates_text [$s.paste get 1.0 end-1c]
        dict set states $w manual_selected {}
        manualCandidatesRender $w
        status $w {Candidates parsed offline. No row is checked and nothing is saved. Review exact fields and attribution before including suggestions.}
    }
}
proc ::GX::LibraryBrowser::manualCandidatesRender {w} {
    variable states
    set tree [manualRoot $w].suggestions.rows.tree
    set selection [$tree selection];set focused [$tree focus];set position [$tree yview]
    $tree delete [$tree children {}]
    set s [manualRoot $w].suggestions;set filter [string tolower [$s.filter.query get]]
    set n 0;set shown 0
    foreach candidate [dict get $states $w manual_candidates] {
        incr n
        if {$filter ne {} && [string first $filter [string tolower $candidate]]<0} continue
        incr shown
        set key [dict get $candidate candidate_id]
        $tree insert {} end -id $n -values [list [expr {$key in [dict get $states $w manual_selected]?{[x]}:{[ ]}}] $key [dict get $candidate label] [dict get $candidate fields] [dict get $candidate source_id]]
    }
    foreach id $selection {if {[$tree exists $id]} {$tree selection add $id}}
    if {$focused ne {} && [$tree exists $focused]} {$tree focus $focused}
    if {[llength $position]} {$tree yview moveto [lindex $position 0]}
    $s.count configure -text "$n candidates; [llength [dict get $states $w manual_selected]] checked; $shown shown. No compatibility verification."
}
proc ::GX::LibraryBrowser::manualCandidateInspect {w} {
    variable states
    run $w {
        set tree [manualRoot $w].suggestions.rows.tree
        if {[llength [$tree selection]]!=1} {error {Select one reviewed candidate row}}
        set candidate [lindex [dict get $states $w manual_candidates] [expr {[lindex [$tree selection] 0]-1}]]
        set review [inlineView $w manual_candidate manual {User-pasted candidate — independent identity, compatibility unverified}]
        ttk::label $review.title -text [dict get $candidate candidate_id] -padding 8;pack $review.title -fill x
        table $review.fields {field original_value};pack $review.fields -fill both -expand 1
        dict for {key value} [dict get $candidate fields] {$review.fields.tree insert {} end -values [list $key $value]}
        text $review.original -height 3 -wrap word;$review.original insert 1.0 [dict get $candidate original_text];$review.original configure -state disabled;pack $review.original -fill x
        ttk::button $review.close -text Close -command [list destroy $review];pack $review.close -anchor e -padx 8 -pady 8
    }
}
proc ::GX::LibraryBrowser::manualCandidateToggle {w} {
    variable states
    set tree [manualRoot $w].suggestions.rows.tree
    if {[llength [$tree selection]]!=1} return
    set key [dict get [lindex [dict get $states $w manual_candidates] [expr {[lindex [$tree selection] 0]-1}]] candidate_id]
    set selected [dict get $states $w manual_selected];set index [lsearch -exact $selected $key]
    if {$index<0} {lappend selected $key} else {set selected [lreplace $selected $index $index]}
    dict set states $w manual_selected $selected;manualCandidatesRender $w
}
proc ::GX::LibraryBrowser::manualCandidatesAll {w} {
    set selected {};foreach row [dict get $::GX::LibraryBrowser::states $w manual_candidates] {lappend selected [dict get $row candidate_id]}
    dict set ::GX::LibraryBrowser::states $w manual_selected $selected;manualCandidatesRender $w
}
proc ::GX::LibraryBrowser::manualCandidatesNone {w} {dict set ::GX::LibraryBrowser::states $w manual_selected {};manualCandidatesRender $w}
proc ::GX::LibraryBrowser::manualTemplate {w {reset 0}} {
    variable states
    if {!$reset && ![manualContextReady $w]} {return 0}
    set p [manualRoot $w]
    set definition [dict get $states $w schemas record_types [$p.identity.type get]]
    set selected [$p.fields.content.template get]
    if {!$reset && [dict exists $states $w manual_template] && $selected eq [dict get $states $w manual_template]} {return 1}
    set template [dict get $definition manual_templates $selected]
    dict for {key value} [dict get $template fields] {
        set control [dict get $states $w manual_controls $key]
        if {[$control get] eq {}} {$control insert 0 $value}
    }
    dict for {key rows} [dict get $template tables] {
        # Template rows are empty prompts. Preserve already-entered properties.
        set old [dict get $states $w table_rows $key]
        set keep {};foreach row $old {if {[::GX::datasetPublicationV2DictDefault $row source_value {}] ne {}} {lappend keep $row}}
        dict set states $w table_rows $key [concat $keep $rows]
        tableRender $w $key
    }
    dict set states $w manual_template $selected
}
proc ::GX::LibraryBrowser::tableRender {w key} {
    variable states
    set control [dict get $states $w manual_controls $key]
    set schema [dict get $states $w schemas record_types [[manualRoot $w].identity.type get] fields $key]
    $control.tree delete [$control.tree children {}]
    set n 0;foreach row [dict get $states $w table_rows $key] {
        set values {};foreach column [dict keys [dict get $schema columns]] {lappend values [::GX::datasetPublicationV2DictDefault $row $column {}]}
        $control.tree insert {} end -id [incr n] -values $values
    }
}
proc ::GX::LibraryBrowser::tableEdit {w key action} {
    variable states
    run $w {
        set control [dict get $states $w manual_controls $key]
        set rows [dict get $states $w table_rows $key]
        set index -1;set initial {}
        if {$action ne {add}} {
            set selected [$control.tree selection]
            if {[llength $selected]!=1} {error {Select one specification row}}
            set index [expr {[lindex $selected 0]-1}];set initial [lindex $rows $index]
        }
        if {$action eq {remove}} {dict set states $w table_rows $key [lreplace $rows $index $index];tableRender $w $key;return}
        if {[llength $rows]>=100 && $action eq {add}} {error {A manual specification table is bounded to 100 rows}}
        set columns [dict get $states $w schemas record_types [[manualRoot $w].identity.type get] fields $key columns]
        set fields {}
        dict for {column definition} $columns {
            set field [dict create type string label [::GX::datasetPublicationV2DictDefault $definition label $column]]
            if {[dict exists $definition choices]} {dict set field type choice;dict set field values [dict get $definition choices]}
            dict set fields $column $field
        }
        ::GX::uiFieldFormCreate $w.specificationRow {Technical specification — preserve original value} $fields $initial [list ::GX::LibraryBrowser::tableCommit $w $key $index] [dict get $::GX::LibraryBrowser::states $w owner]
    }
}
proc ::GX::LibraryBrowser::tableCommit {w key index values} {
    variable states
    # The existing UIField form catches this refusal and retains its edits.
    guard $w
    set rows [dict get $states $w table_rows $key]
    if {$index<0} {lappend rows $values} else {set rows [lreplace $rows $index $index $values]}
    dict set states $w table_rows $key $rows
    tableRender $w $key
}
proc ::GX::LibraryBrowser::tableJson {w key} {
    variable states
    set schema [dict get $states $w schemas record_types [[manualRoot $w].identity.type get] fields $key]
    set result {}
    foreach row [dict get $states $w table_rows $key] {
        set skip [::GX::datasetPublicationV2DictDefault $schema skip_empty_field {}]
        if {$skip ne {} && [::GX::datasetPublicationV2DictDefault $row $skip {}] eq {}} continue
        set fields {}
        dict for {column definition} [dict get $schema columns] {
            set value [::GX::datasetPublicationV2DictDefault $row $column {}]
            if {$value eq {}} continue
            set encoded [str $value]
            if {[dict get $definition type] in {number integer}} {
                if {![regexp {^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?$} $value]} {error "Enter a valid numeric value in $column, or leave it blank"}
                set encoded $value
            }
            lappend fields "[str $column]:$encoded"
        }
        lappend result \{[join $fields ,]\}
    }
    return \[[join $result ,]\]
}
proc ::GX::LibraryBrowser::attach {w} {
    variable states
    run $w {
        set paths [tk_getOpenFile -parent [dict get $states $w owner] -multiple 1 -title {Select already-downloaded PDF or images} -filetypes {{{PDF and images} {.pdf .png .jpg .jpeg .gif}} {{All files} *}}]
        set attachments [dict get $states $w attachments]
        foreach path $paths {lappend attachments [dict create path $path role [[manualRoot $w].files.role get] expected_sha256 [::GX::sha256File $path]]}
        if {[llength $attachments]>32} {error {Select at most 32 local attachments}}
        dict set states $w attachments $attachments
        manualAttachments $w
    }
}
proc ::GX::LibraryBrowser::clearAttachments {w} {dict set ::GX::LibraryBrowser::states $w attachments {};manualAttachments $w}
proc ::GX::LibraryBrowser::manualParameters {w {withFiles 0}} {
    variable states
    set p [manualRoot $w];set fields {}
    dict for {key control} [dict get $states $w manual_controls] {
        switch [dict get $states $w manual_editors $key] {
            table {dict set fields $key [tableJson $w $key]}
            multiline {dict set fields $key [$control get 1.0 end-1c]}
            default {dict set fields $key [$control get]}
        }
    }
    set attachments {}
    if {$withFiles} {foreach item [dict get $states $w attachments] {lappend attachments [object $item]}}
    set parameters [format {"record_type":%s,"fields":%s,"raw_fields":true,"source_id":%s,"label":%s,"entry_id":%s,"pasted_text":%s,"attachments":[%s]} [str [$p.identity.type get]] [object $fields] [str [$p.identity.source get]] [str [$p.names.label get]] [str [$p.names.entry get]] [str [$p.paste get 1.0 end-1c]] [join $attachments ,]]
    if {[dict get $states $w previous] ne {}} {append parameters ,\"previous\": [object [dict get $states $w previous]]}
    append parameters ,\"library_id\": [str [$p.names.library get]]
    if {$::GX::LibraryBrowser::manualInclude($w)} {
        if {![dict exists $states $w manual_candidates_text] || [dict get $states $w manual_candidates_text] ne [$p.suggestions.paste get 1.0 end-1c]} {error {Parse and review the changed candidate paste before saving}}
        append parameters [format {,"suggestions":{"include":true,"text":%s,"selected_ids":%s,"relation_type":%s,"source_id":%s,"assertion_kind":%s,"evidence":%s}} [str [$p.suggestions.paste get 1.0 end-1c]] [array [dict get $states $w manual_selected]] [str [$p.suggestions.claim.relation get]] [str [$p.suggestions.claim.source get]] [str [$p.suggestions.claim.kind get]] [str [$p.suggestions.claim.evidence get]]]
    }
    return $parameters
}
proc ::GX::LibraryBrowser::manualPreview {w} {
    variable states
    run $w {
        set parameters [manualParameters $w 1]
        set result [domain $w manual_prepare \{[manualParameters $w]\}]
        if {[[manualRoot $w].names.entry get] eq {}} {[manualRoot $w].names.entry insert 0 [dict get $result entry entry_id];set parameters [manualParameters $w 1]}
        if {[dict exists $result expected_version]} {append parameters ,\"expected_version\": [str [dict get $result expected_version]]}
        set review [inlineView $w manual_review manual {Review manual Library entry — no network or Session changes}]
        set content [::GX::uiFieldScrollableCreate $review.viewport 1]
        pack $review.viewport -fill both -expand 1
        ttk::label $content.title -text "[dict get $result entry label] • [dict get $result entry record_type]" -padding 10
        pack $content.title -fill x;wrapLabel $content.title
        ttk::label $content.suggestions -text "Selected suggestions: [llength [::GX::datasetPublicationV2DictDefault $result selected_suggestions {}]]. Independent entries with attributed directed links; compatibility unverified." -wraplength 850 -padding 6
        pack $content.suggestions -fill x;wrapLabel $content.suggestions
        ::GX::uiFieldComponentCreate $content.tabs tabs {} {} {};pack $content.tabs -fill both -expand 1
        if {[llength [::GX::datasetPublicationV2DictDefault $result selected_suggestions {}]]} {
            ttk::frame $content.tabs.suggestions;$content.tabs add $content.tabs.suggestions -text {Selected independent suggestions}
            table $content.tabs.suggestions.values {candidate entry revision status};$content.tabs.suggestions.values.tree configure -height 4
            pack $content.tabs.suggestions.values -fill x
            table $content.tabs.suggestions.details {field original_value};pack $content.tabs.suggestions.details -fill both -expand 1
            ttk::label $content.tabs.suggestions.claim -text {User/source assertion only; engineering compatibility remains unverified.} -wraplength 850
            pack $content.tabs.suggestions.claim -fill x -pady 5;wrapLabel $content.tabs.suggestions.claim
            set n 0
            foreach row [dict get $result selected_suggestions] {
                set candidate [dict get $row entry]
                $content.tabs.suggestions.values.tree insert {} end -id [incr n] -values [list [dict get $row candidate_id] [dict get $candidate entry_id] [dict get $candidate revision] [dict get $row status]]
            }
            bind $content.tabs.suggestions.values.tree <<TreeviewSelect>> [list ::GX::LibraryBrowser::manualReviewCandidate $content [dict get $result selected_suggestions]]
            $content.tabs.suggestions.values.tree selection set 1
            manualReviewCandidate $content [dict get $result selected_suggestions]
        }
        ttk::frame $content.tabs.identity;$content.tabs add $content.tabs.identity -text {Identity and source}
        table $content.tabs.identity.values {field value};pack $content.tabs.identity.values -fill both -expand 1
        dict for {key value} [dict get $result entry fields] {
            if {[dict get $states $w manual_editors $key] eq {table}} continue
            $content.tabs.identity.values.tree insert {} end -values [list $key $value]
        }
        $content.tabs.identity.values.tree insert {} end -values [list source_id [dict get $result entry provenance source_id]]
        dict for {key editor} [dict get $states $w manual_editors] {
            if {$editor ne {table}} continue
            set columns [dict keys [dict get $states $w schemas record_types [[manualRoot $w].identity.type get] fields $key columns]]
            ttk::frame $content.tabs.$key;$content.tabs add $content.tabs.$key -text [string totitle [string map {_ { }} $key]]
            table $content.tabs.$key.values $columns;pack $content.tabs.$key.values -fill both -expand 1
            foreach row [::GX::datasetPublicationV2DictDefault [dict get $result entry fields] $key {}] {
                set values {};foreach column $columns {lappend values [::GX::datasetPublicationV2DictDefault $row $column {}]}
                $content.tabs.$key.values.tree insert {} end -values $values
            }
        }
        ttk::frame $content.tabs.files;$content.tabs add $content.tabs.files -text {Original local files}
        table $content.tabs.files.values {role filename sha256};pack $content.tabs.files.values -fill both -expand 1
        foreach file [dict get $states $w attachments] {$content.tabs.files.values.tree insert {} end -values [list [dict get $file role] [file tail [dict get $file path]] [dict get $file expected_sha256]]}
        ttk::frame $review.actions
        ttk::button $review.actions.save -text {Save reviewed entries} -command [list ::GX::LibraryBrowser::manualCommit $w $parameters [[manualRoot $w].names.library get] $review]
        ttk::button $review.actions.cancel -text {Cancel review} -command [list destroy $review]
        flow $review.actions
        pack $review.actions -side bottom -fill x -before $review.viewport
        status $w {Review ready; nothing saved.}
    }
}
proc ::GX::LibraryBrowser::manualReviewCandidate {review candidates} {
    if {![winfo exists $review.tabs.suggestions.values.tree]} return
    set selected [$review.tabs.suggestions.values.tree selection]
    if {[llength $selected]!=1} return
    set entry [dict get [lindex $candidates [expr {[lindex $selected 0]-1}]] entry]
    set tree $review.tabs.suggestions.details.tree;$tree delete [$tree children {}]
    foreach key {entry_id revision content_sha256} {$tree insert {} end -values [list $key [dict get $entry $key]]}
    dict for {key value} [dict get $entry fields] {$tree insert {} end -values [list $key $value]}
    $tree insert {} end -values [list attribution [dict get $entry provenance source_id]]
}
proc ::GX::LibraryBrowser::manualSave {w} {run $w {manualCommit $w [manualParameters $w 1] [[manualRoot $w].names.library get] {}}}
proc ::GX::LibraryBrowser::manualCommit {w parameters library review} {
    variable states
    run $w {
        set result [domain $w manual_import \{$parameters\}]
        dict set states $w last_receipt $result
        set saved {};foreach row [dict get $result entries] {if {[dict get $row entry_id] eq [dict get $result primary_entry_id]} {set saved $row;break}}
        set reference [dict create library_id [dict get $result library_id] entry_id [dict get $saved entry_id]]
        set actual [domain $w detail [format {{"reference":%s}} [object $reference]]]
        dict set reference revision [dict get $actual revision];dict set reference content_sha256 [dict get $actual content_sha256]
        dict set states $w previous $reference
        [manualRoot $w].names.entry delete 0 end;[manualRoot $w].names.entry insert 0 [dict get $saved entry_id]
        if {[dict exists $states $w named_views manual_review]} {destroy [viewFor $w manual_review]}
        dict set states $w draft_baseline [draftSnapshot $w]
        refresh $w
        status $w "Saved primary record and [llength [dict get $result selected_suggestions]] selected suggestions in Library [dict get $result library_id], version [dict get $result version]. Zero Session Datasets created."
    }
}
proc ::GX::LibraryBrowser::manualCancel {w} {
    set p [manualRoot $w]
    manualFields $w 1;clearAttachments $w
    $p.paste delete 1.0 end
    $p.suggestions.paste delete 1.0 end
    foreach field [list $p.names.label $p.names.entry] {$field delete 0 end}
    dict set ::GX::LibraryBrowser::states $w draft_baseline [draftSnapshot $w]
    status $w {Manual draft cancelled. Persistent Libraries and Sessions are unchanged.}
}
proc ::GX::LibraryBrowser::manualAttachments {w} {
    variable states
    set table [manualRoot $w].attachments.tree
    $table delete [$table children {}]
    set files [dict get $states $w attachments];set n 0
    foreach file $files {$table insert {} end -id [incr n] -values [list [dict get $file role] [file tail [dict get $file path]] [dict get $file expected_sha256]]}
    [manualRoot $w].fileSummary configure -text "[llength $files] user-selected local files • double-click to view the original • source bytes/SHA checked on Save"
}
proc ::GX::LibraryBrowser::manualOpenAttachment {w} {
    variable states
    run $w {
        set ids [[manualRoot $w].attachments.tree selection]
        if {[llength $ids]!=1} {error {Select one local file}}
        set file [lindex [dict get $states $w attachments] [expr {[lindex $ids 0]-1}]]
        set path [dict get $file path]
        set stream [::open $path rb];try {set magic [read $stream 5]} finally {::close $stream}
        set isPdf [expr {$magic eq {%PDF-} || [string tolower [file extension $path]] eq {.pdf}}]
        if {$isPdf} {
            file stat $path info
            if {$info(type) ne {file} || $info(size)>33554432} {error {Local PDF is absent or exceeds 32 MiB}}
        }
        if {[::GX::sha256File $path] ne [dict get $file expected_sha256]} {error {The selected local file changed; select it again}}
        if {$isPdf} {
            manualPdf $w $file
        } elseif {[string tolower [file extension $path]] in {.png .jpg .jpeg .gif}} {
            set view [inlineView $w local_image manual "Local original — [file tail $path]"]
            set image [localImage $w $path]
            imageDisplay $view $image
            ttk::label $view.source -text "[dict get $file role] • original SHA256 [dict get $file expected_sha256]" -width 1 -wraplength 600 -padding 8;pack $view.source -fill x
            status $w {Selected original image opened read-only. Original source bytes and Library/Session data are unchanged.}
        } else {externalOpen $path}
    }
}
proc ::GX::LibraryBrowser::manualPdf {w file} {
    variable states
    if {![llength [info commands ::GX::datasetMediaViewerOpenArtifact]]} {error {This CORE has no managed Library PDF reader; install the compatible framework revision.}}
    set path [dict get $file path];file stat $path before
    if {$before(type) ne {file} || $before(size)>33554432} {error {Local PDF is absent or exceeds 32 MiB}}
    set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime viewer retention_seconds 0]]
    set state [dict get $states $w];dict lappend state allocations $allocation;dict set states $w $state
    try {
        set staged [file join [dict get $allocation path] original.pdf]
        set input [::open $path rb]
        try {
            set output [::open $staged {WRONLY CREAT EXCL}];fconfigure $output -translation binary
            try {set copied [fcopy $input $output -size 33554433]} finally {::close $output}
        } finally {::close $input}
        file stat $path after
        if {$copied>33554432 || $copied!=$before(size) || $before(dev)!=$after(dev) || $before(ino)!=$after(ino) || $before(size)!=$after(size)} {error {Local PDF changed while preparing its read-only view}}
        set expected [dict get $file expected_sha256]
        if {[::GX::sha256File $staged] ne $expected || [::GX::sha256File $path] ne $expected} {error {Local PDF bytes changed after selection}}
        set stream [::open $staged rb];try {set magic [read $stream 5]} finally {::close $stream}
        if {$magic ne {%PDF-}} {error {Selected local file is not a PDF}}
        set identity [dict create api_id SCIENTIFIC_LIBRARY_MANAGER_API_v1 reference draft-file-sha256:$expected sha256 $expected]
        set source [dict create allocation_id [dict get $allocation id] path $staged sha256 $expected source_identity $identity]
        set view [inlineView $w local_pdf manual "Local PDF — [file tail $path]"]
        ttk::label $view.identity -text "Draft local PDF • [file tail $path]\nOriginal SHA256: $expected • nothing saved to Library or Session" -wraplength 900 -padding 8
        pack $view.identity -fill x
        pdfOpen $w $view $allocation $source "Local PDF — [file tail $path]"
    } on error {message options} {
        if {[info exists view]} {catch {destroy $view}}
        catch {releaseAllocation $w [dict get $allocation id]}
        return -options $options $message
    }
}
proc ::GX::LibraryBrowser::edit {w} {
    variable states
    run $w {
        if {![dict exists $states $w selected_reference]} {error {Display one Library entry before editing}}
        set reference [dict get $states $w selected_reference]
        set entry [domain $w detail [format {{"reference":%s}} [object $reference]]]
        if {[::GX::datasetPublicationV2DictDefault $entry read_only 0]} {error {This entry is a read-only view of managed provider metadata. Use the normal Library package lifecycle to update its source.}}
        set p [manualRoot $w]
        $p.identity.type set [dict get $entry record_type];manualFields $w 1
        dict for {key value} [dict get $entry fields] {
            if {![dict exists $states $w manual_controls $key]} continue
            set control [dict get $states $w manual_controls $key]
            set kind [dict get $states $w schemas record_types [dict get $entry record_type] fields $key type]
            set editor [dict get $states $w manual_editors $key]
            if {$editor eq {table}} {dict set states $w table_rows $key $value;tableRender $w $key;continue}
            if {$editor eq {multiline}} {$control insert 1.0 $value;continue}
            if {$kind eq {string}} {$control insert 0 $value} else {
                # Preserve JSON types via the existing native typed decoder.
                set typed [::GX::nativeWorkspaceJsonDecode [dict get $entry result_json]]
                set fieldTyped [dict get [lindex [dict get [lindex $typed 1] fields] 1] $key]
                $control insert 0 [::GX::nativeWorkspaceJsonEncode $fieldTyped]
            }
        }
        foreach {control value} [list $p.names.library [dict get $reference library_id] $p.names.entry [dict get $entry entry_id] $p.names.label [dict get $entry label] $p.identity.source [dict get $entry provenance source_id]] {$control delete 0 end;$control insert 0 $value}
        dict set states $w previous $reference
        clearAttachments $w
        $p.paste delete 1.0 end
        $p.paste insert 1.0 [::GX::datasetPublicationV2DictDefault [dict get $entry provenance] original_text {}]
        focusPage $w manual
        status $w {Editing a new immutable revision. Existing source bytes/history remain preserved.}
    }
}
proc ::GX::LibraryBrowser::openResource {w} {
    variable states
    run $w {
        set selected [[pageRoot $w records].detail.resources.values.tree selection]
        if {[llength $selected]!=1} {error {Select one local image or document}}
        set index [expr {[lindex $selected 0]-1}]
        set reference [dict get $states $w selected_reference]
        set resource [lindex [dict get $states $w selected_entry resources] $index]
        if {[dict get $resource availability] ne {local}} {error "External reference: [dict get $resource url]. Download was not claimed; use a source import or add your local file."}
        set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime viewer retention_seconds 0]]
        set state [dict get $states $w];dict lappend state allocations $allocation;dict set states $w $state
        if {[catch {::GX::LibraryEntryAcquisitionDispatchAPIv1::_stage [dict create reference $reference resource_index $index] $allocation} staged options]} {
            catch {releaseAllocation $w [dict get $allocation id]};return -options $options $staged
        }
        set view [inlineView $w library_resource records "Original Library resource — [dict get $resource role]"]
        dict set states $w inline_views $view allocation_id [dict get $allocation id]
        ttk::label $view.identity -text "[dict get $staged media_type]\nSHA256: [dict get $staged sha256]" -wraplength 800 -padding 8;pack $view.identity -fill x
        if {[string match image/* [dict get $staged media_type]]} {
            set image [localImage $w [dict get $staged source_path]]
            imageDisplay $view $image
        } elseif {[dict get $staged media_type] eq {application/pdf}} {
            set identity [dict create api_id SCIENTIFIC_LIBRARY_MANAGER_API_v1 reference "[dict get $staged library_id]/[dict get $staged entry_id]/resource/$index" sha256 [dict get $staged sha256] revision [dict get $staged revision]]
            set source [dict create allocation_id [dict get $allocation id] path [dict get $staged source_path] sha256 [dict get $staged sha256] source_identity $identity]
            if {[catch {pdfOpen $w $view $allocation $source "Library PDF — [dict get $resource role]"} message options]} {
                catch {destroy $view};catch {releaseAllocation $w [dict get $allocation id]};return -options $options $message
            }
        } elseif {[dict get $staged media_type] eq {chemical/x-mdl-sdfile}} {
            ::GX::viewerOpen viewer.molecule_3d molecule_3d [dict create library_source [dict merge $staged [dict create reference $reference resource_index $index]]]
        } else {
            ttk::label $view.path -text "Original bytes staged read-only for viewing:\n[dict get $staged source_path]\nUse Open original in your configured document application, or explicitly import it to a Session with its installed Acquisition Handler." -wraplength 800 -padding 12;pack $view.path -fill both -expand 1
            ttk::button $view.open -text {Open original document} -command [list ::GX::LibraryBrowser::externalOpen [dict get $staged source_path]];pack $view.open -pady 8
        }
    }
}
proc ::GX::LibraryBrowser::imageClosed {view actual image} {if {$view eq $actual} {catch {image delete $image}}}
proc ::GX::LibraryBrowser::externalOpen {path} {
    if {$::tcl_platform(platform) eq {windows}} {exec {*}[auto_execok start] {} $path &} else {exec xdg-open $path &}
}
proc ::GX::LibraryBrowser::acquire {w} {
    variable states
    run $w {
        set ids [[pageRoot $w records].list.tree selection]
        if {$ids eq {}} {error {Select one or more rows in Library records; use Import displayed record for the detail currently shown}}
        set references {};foreach id $ids {lappend references [lindex [dict get $states $w rows] [expr {$id-1}]]}
        acquireReferences $w $references {Selected Library records}
    }
}
proc ::GX::LibraryBrowser::acquireDisplayed {w} {
    variable states
    run $w {
        if {![dict exists $states $w selected_reference]} {error {Display a Library entry before importing it}}
        acquireReferences $w [list [dict get $states $w selected_reference]] {Displayed Library entry}
    }
}
proc ::GX::LibraryBrowser::acquireRelated {w} {
    variable states
    run $w {
        set ids [[pageRoot $w records].detail.related.values.tree selection]
        if {$ids eq {} || [llength $ids]>100} {error {Select between 1 and 100 related rows for explicit review}}
        set references {};set seen {}
        foreach id $ids {
            set edge [lindex [dict get $states $w relations] [expr {$id-1}]]
            set reference [relatedTarget $w $edge]
            if {[::GX::datasetPublicationV2DictDefault $edge scope_status {}] eq {outside_scope}} {error [dict get $edge scope_reason]}
            if {[dict get $reference kind] ne {library_entry} || [dict get $edge resolution_status] ne {resolved}} {error {Select resolved, current Library-entry relations only. External, missing, stale and Dataset references are not implicitly imported; explicitly resolve/open a Library entry first.}}
            set key [list [dict get $reference library_id] [dict get $reference entry_id] [dict get $reference revision] [dict get $reference content_sha256]]
            if {$key in $seen} continue
            lappend seen $key;lappend references $reference
        }
        acquireReferences $w $references {Selected related Library entries}
    }
}
proc ::GX::LibraryBrowser::acquireReferences {w references scope} {
    variable states
    if {[llength $references]<1 || [llength $references]>100} {error {Explicitly select between 1 and 100 Library entries}}
    set queue {}
    foreach reference $references {
        domain $w detail [format {{"reference":%s}} [object $reference]]
        foreach key {library_id entry_id revision content_sha256} {if {![dict exists $reference $key] || [dict get $reference $key] eq {}} {error "Selection must pin exact Library entry $key"}}
        lappend queue [dict remove $reference label]
    }
    foreach form {acquireRepresentation acquireHandler acquireDestination} {catch {destroy $w.$form}}
    dict set states $w acquisition_scope $scope
    dict set states $w acquisition_queue $queue;dict set states $w acquisition_selections {};dict set states $w acquisition_reviews {}
    acquireNext $w
}
proc ::GX::LibraryBrowser::pinSummary {reference} {
    return "Library: [dict get $reference library_id]\nEntry: [dict get $reference entry_id]\nRevision: [dict get $reference revision]\nEntry content SHA256: [dict get $reference content_sha256]"
}
proc ::GX::LibraryBrowser::reviewSummary {window title value} {
    if {[string length $value]>262144} {error {Selection review exceeds its bounded display budget; review fewer entries}}
    ttk::labelframe $window.review -text $title -padding 4
    text $window.review.text -height 7 -width 1 -wrap word -yscrollcommand [list $window.review.scroll set]
    ttk::scrollbar $window.review.scroll -orient vertical -command [list $window.review.text yview]
    pack $window.review.scroll -side right -fill y;pack $window.review.text -fill both -expand 1
    $window.review.text insert 1.0 $value;$window.review.text configure -state disabled
    pack $window.review -side top -fill x -padx 8 -pady 4 -before $window.scroll
}
proc ::GX::LibraryBrowser::acquireNext {w} {
    variable states
    run $w {
        set queue [dict get $states $w acquisition_queue]
        if {$queue eq {}} {
            set fields [dict create session_path {type string label {Existing target Session path}} namespace {type string label {Destination Namespace (blank = root)}}]
            set session {};if {[info exists ::GX::currentSession]} {set session $::GX::currentSession}
            ::GX::uiFieldFormCreate $w.acquireDestination {Import reviewed selection to Session} $fields [dict create session_path $session namespace {}] [list ::GX::LibraryBrowser::acquireCommit $w] [dict get $::GX::LibraryBrowser::states $w owner]
            set summaries {};foreach review [dict get $states $w acquisition_reviews] {lappend summaries $review}
            reviewSummary $w.acquireDestination {Exact reviewed selection — destination below} "[join $summaries \n\n]\n\nBatch semantics: each explicitly reviewed Library entry uses its selected existing Acquisition Handler transaction. Outcomes are reported per entry; arbitrary related entries do not imply a Dataset Group. The Session path and Namespace below are the final publication destination."
            return
        }
        set reference [dict remove [lindex $queue 0] label]
        set detail [domain $w detail [format {{"reference":%s}} [object $reference]]]
        set choices {}
        if {[::GX::datasetPublicationV2DictDefault $detail content_contract {}] ne {}} {lappend choices {-1: structured record}}
        set n -1;foreach resource [dict get $detail resources] {incr n;if {[dict get $resource availability] eq {local}} {lappend choices "$n: [dict get $resource role]"}}
        if {$choices eq {}} {error {This selected entry has no locally available acquisition representation; select an actual linked record or file}}
        dict set states $w acquisition_reference $reference
        ::GX::uiFieldFormCreate $w.acquireRepresentation "[dict get $states $w acquisition_scope]: [dict get $reference library_id]/[dict get $reference entry_id]" [dict create representation [dict create type choice values $choices label Representation] dataset_id {type string label {Proposed Dataset ID}}] [dict create representation [lindex $choices 0] dataset_id [dict get $reference entry_id]] [list ::GX::LibraryBrowser::acquireRepresentation $w] [dict get $::GX::LibraryBrowser::states $w owner]
        set summary "[pinSummary $reference]\nRecord type: [dict get $detail record_type]\nStructured content contract: [::GX::datasetPublicationV2DictDefault $detail content_contract unavailable]"
        set n -1;foreach resource [dict get $detail resources] {incr n;append summary "\nResource $n: [dict get $resource role] • [dict get $resource availability] • [::GX::datasetPublicationV2DictDefault $resource media_type {}]\nResource original SHA256: [::GX::datasetPublicationV2DictDefault $resource sha256 unavailable]"}
        reviewSummary $w.acquireRepresentation {Pinned entry and original resources} $summary
    }
}
proc ::GX::LibraryBrowser::acquireRepresentation {w values} {
    variable states
    run $w {
        set index [lindex [split [dict get $values representation] :] 0]
        set selection [dict create reference [dict get $states $w acquisition_reference] resource_index $index dataset_id [dict get $values dataset_id]]
        set inspected [::GX::LibraryEntryAcquisitionDispatchAPIv1::inspectSelection $selection]
        set handlers [dict get $inspected compatible_handlers]
        if {$handlers eq {}} {error {No enabled compatible Acquisition Handler/Contract for the selected representation}}
        dict set selection expected_sha256 [dict get $inspected sha256]
        dict set states $w acquisition_current $selection
        set summary "[pinSummary [dict get $selection reference]]\nRepresentation: [dict get $values representation]\nProposed Dataset ID: [dict get $values dataset_id]\nSelected representation bytes SHA256: [dict get $inspected sha256]\nActual content contract: [dict get $inspected content_contract]\nMedia type: [dict get $inspected media_type]"
        dict set states $w acquisition_current_review $summary
        catch {destroy $w.acquireRepresentation}
        ::GX::uiFieldFormCreate $w.acquireHandler {Review Acquisition Handler} [dict create handler_id [dict create type choice values $handlers label {Installed compatible handler}]] [dict create handler_id [lindex $handlers 0]] [list ::GX::LibraryBrowser::acquireHandler $w] [dict get $::GX::LibraryBrowser::states $w owner]
        reviewSummary $w.acquireHandler {Exact representation — choose its handler below} "$summary\nRecognized compatible handlers: [join $handlers {, }]"
    }
}
proc ::GX::LibraryBrowser::acquireHandler {w values} {
    variable states
    run $w {
        set state [dict get $states $w]
        dict lappend state acquisition_selections [dict merge [dict get $state acquisition_current] $values]
        dict lappend state acquisition_reviews "[dict get $state acquisition_current_review]\nChosen Acquisition Handler: [dict get $values handler_id]"
        dict set state acquisition_queue [lrange [dict get $state acquisition_queue] 1 end]
        dict set states $w $state
        catch {destroy $w.acquireHandler}
        acquireNext $w
    }
}
proc ::GX::LibraryBrowser::acquireCommit {w values} {
    run $w {
        set selections [dict get $::GX::LibraryBrowser::states $w acquisition_selections]
        set receipt [::GX::LibraryEntryAcquisitionDispatchAPIv1::importSelected [dict get $values session_path] $selections [dict get $values namespace]]
        dict set ::GX::LibraryBrowser::states $w last_receipt $receipt
        catch {destroy $w.acquireDestination}
        status $w {Selected Acquisition finished. View last operation receipt for actual per-entry outcomes.}
    }
}

proc ::GX::LibraryBrowser::showReceipt {w} {
    run $w {
        if {![dict exists $::GX::LibraryBrowser::states $w last_receipt]} {error {No completed operation receipt in this Browser lifetime}}
        set view [inlineView $w receipt records {Actual Library operation receipt}]
        text $view.text -wrap word -width 1 -height 4 -yscrollcommand [list $view.y set]
        ttk::scrollbar $view.y -orient vertical -command [list $view.text yview]
        pack $view.y -side right -fill y;pack $view.text -fill both -expand 1
        $view.text insert end [dict get $::GX::LibraryBrowser::states $w last_receipt]
        $view.text configure -state disabled
        status $w {Read-only operation receipt opened.}
    }
}

proc ::GX::LibraryBrowser::sourceInspect {w} {
    variable states
    run $w {
        set chosen [[pageRoot $w sources].selection.tree selection]
        if {[llength $chosen]!=1} {error {Select one actual source record to inspect}}
        set row [lindex [dict get $states $w bundle entries] [expr {[lindex $chosen 0]-1}]]
        set entry [dict get $row entry]
        dict set states $w inspected_source_entry $entry
        set view [inlineView $w source_detail sources {Source record — read-through consultation}]
        ttk::label $view.title -text "[dict get $entry label] • [dict get $entry record_type]" -padding 10;pack $view.title -fill x
        ::GX::uiFieldComponentCreate $view.tabs tabs {} {} {};pack $view.tabs -fill both -expand 1
        ttk::frame $view.tabs.identity;$view.tabs add $view.tabs.identity -text {Fields and source}
        table $view.tabs.identity.values {field value};pack $view.tabs.identity.values -fill both -expand 1
        set definitions [dict get $states $w schemas record_types [dict get $entry record_type] fields]
        set n 0
        dict for {key value} [dict get $entry fields] {
            set definition [::GX::datasetPublicationV2DictDefault $definitions $key {}]
            if {[::GX::datasetPublicationV2DictDefault $definition editor {}] eq {table}} {
                set tab $view.tabs.typed[incr n];ttk::frame $tab;$view.tabs add $tab -text [::GX::datasetPublicationV2DictDefault $definition label $key]
                set columns [dict keys [dict get $definition columns]]
                table $tab.values $columns;pack $tab.values -fill both -expand 1
                foreach record $value {set cells {};foreach column $columns {lappend cells [::GX::datasetPublicationV2DictDefault $record $column {}]};$tab.values.tree insert {} end -values $cells}
            } else {$view.tabs.identity.values.tree insert {} end -values [list $key $value]}
        }
        dict for {key value} [dict get $entry provenance] {$view.tabs.identity.values.tree insert {} end -values [list provenance.$key $value]}
        ttk::frame $view.tabs.resources;$view.tabs add $view.tabs.resources -text {Actual source images and documents}
        table $view.tabs.resources.values {role availability url sha256};pack $view.tabs.resources.values -fill both -expand 1
        set n 0;foreach resource [dict get $entry resources] {$view.tabs.resources.values.tree insert {} end -id [incr n] -values [list [dict get $resource role] [dict get $resource availability] [::GX::datasetPublicationV2DictDefault $resource url {}] [::GX::datasetPublicationV2DictDefault $resource sha256 {}]]}
        ttk::frame $view.actions
        ttk::button $view.actions.image -text {View source image (memory only)} -command [list ::GX::LibraryBrowser::sourceImage $w]
        ttk::button $view.actions.document -text {Open original source document link} -command [list ::GX::LibraryBrowser::sourceDocument $w]
        ttk::button $view.actions.close -text Close -command [list destroy $view]
        pack $view.actions.image $view.actions.document $view.actions.close -side left -padx 6 -pady 6;pack $view.actions -fill x
    }
}
proc ::GX::LibraryBrowser::sourceImage {w} {
    variable states
    run $w {
        set entry [dict get $states $w inspected_source_entry]
        set options [format {{"transient_asset_entry_id":%s}} [str [dict get $entry entry_id]]]
        request $w content [list [dict get $states $w source_library] read_entry [dict create entry_id [dict get $states $w primary_source_entry] options_json $options]] image
    }
}
proc ::GX::LibraryBrowser::sourceDocument {w} {
    variable states
    run $w {
        set selected [[viewFor $w source_detail].tabs.resources.values.tree selection]
        if {[llength $selected]!=1} {error {Select one actual source document link}}
        set resource [lindex [dict get $states $w inspected_source_entry resources] [expr {[lindex $selected 0]-1}]]
        if {![dict exists $resource url] || ![string match https://* [dict get $resource url]]} {error {This resource has no HTTPS source document link}}
        externalOpen [dict get $resource url]
        status $w {Sent source document link to external handler.}
    }
}
proc ::GX::LibraryBrowser::localImage {w path} {
    variable states
    if {![catch {image create photo -file $path} image]} {return $image}
    set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime viewer retention_seconds 0]]
    set state [dict get $states $w];dict lappend state allocations $allocation;dict set states $w $state
    set artifact [::GX::datasetPreviewImageArtifact $path [dict get $allocation path] 1]
    if {![dict exists $artifact path]} {error {Configured image preview cannot display this local format}}
    return [image create photo -file [dict get $artifact path]]
}
proc ::GX::LibraryBrowser::sourceImageReply {w result} {
    variable states
    run $w {
        set images [::GX::datasetPublicationV2DictDefault [dict get $result payload] preview_assets {}]
        if {$images eq {}} {error {This source did not return a supported image preview}}
        set asset [lindex $images 0]
        set generation [dict get $states $w generation]
        set callback [list ::GX::LibraryBrowser::sourceImageConverted $w $generation [dict get $asset role] [dict get $asset sha256]]
        set request [::GX::datasetPreviewImageMemory [binary decode base64 [dict get $asset data_base64]] $callback]
        dict set states $w request $request
        status $w {Preparing bounded image preview in memory…}
    }
}
proc ::GX::LibraryBrowser::sourceImageConverted {w generation role originalSHA response} {
    variable states
    if {![dict exists $states $w] || [dict get $states $w generation]!=$generation} return
    dict set states $w request {}
    run $w {
        if {![dict get $response ok]} {error [dict get $response error]}
        set result [dict get $response result]
        if {[dict get $result original_sha256] ne $originalSHA} {error {Source image identity changed before display}}
        set view [inlineView $w source_image sources {Source image — transient memory, not saved}]
        set image [image create photo -data [binary decode base64 [dict get $result data_base64]]]
        imageDisplay $view $image
        ttk::label $view.source -text "$role • transient memory preview • original SHA256 $originalSHA" -wraplength 900 -padding 8;pack $view.source -fill x
        status $w {Source image displayed from memory. No API response, image or Library entry was saved.}
    }
}

proc ::GX::LibraryBrowser::forward {w} {
    variable states
    set state [dict get $states $w];set forward [dict get $state forward_history]
    if {$forward eq {}} return
    set old [dict get $state selected_reference]
    if {[inspect $w [lindex $forward end]] eq {1}} {set state [dict get $states $w];dict lappend state history $old;dict set state forward_history [lrange $forward 0 end-1];dict set states $w $state}
}
proc ::GX::LibraryBrowser::externalCandidate {w values} {
    variable states
    set state [dict get $states $w];set old [dict get $state selected_reference]
    if {[inspect $w [dict remove [dict get $state external_candidates [dict get $values candidate]] label]] eq {1}} {set state [dict get $states $w];dict lappend state history $old;dict set state forward_history {};dict set states $w $state}
}
proc ::GX::LibraryBrowser::relatedPage {w delta} {
    set offset [::GX::datasetPublicationV2DictDefault [dict get $::GX::LibraryBrowser::states $w] related_offset 0]
    relatedRefresh $w [expr {max(0,$offset+$delta)}]
}
proc ::GX::LibraryBrowser::relatedRefresh {w {offset 0}} {
    variable states
    run $w {
        set p [pageRoot $w records].detail.related
        set reference [dict get $states $w selected_reference]
        set relationType [$p.filters.type get];if {$relationType eq {All relation types}} {set relationType {}}
        set parameters [format {{"reference":%s,"direction":%s,"relation_type":%s,"source_id":%s,"offset":%d,"limit":100}} [object $reference] [str [$p.filters.direction get]] [str $relationType] [str [$p.filters.source get]] $offset]
        set result [domain $w related $parameters]
        dict set states $w relations [dict get $result records];dict set states $w related_offset $offset
        $p.values.tree delete [$p.values.tree children {}]
        set n 0;foreach edge [dict get $result records] {
            set direction [expr {[dict get $edge from_reference library_id] eq [dict get $reference library_id] && [dict get $edge from_reference entry_id] eq [dict get $reference entry_id]?{outgoing}:{incoming}}]
            $p.values.tree insert {} end -id [incr n] -values [relationCells $w $edge $direction]
        }
        status $w "[llength [dict get $result records]] / [dict get $result total] source-attributed relations • offset $offset • read-only traversal"
    }
}
