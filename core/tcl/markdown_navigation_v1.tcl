# SPDX-License-Identifier: GPL-3.0-or-later
# Subordinate of the one GX-Markup renderer. UI lifetimes, never a source store.
namespace eval ::GX::MarkupNavigation {variable views {};variable status;array set status {}}
proc ::GX::_markdownLinkDecode {value} {
    set bytes {};set length [string length $value]
    for {set i 0} {$i<$length} {incr i} {
        set character [string index $value $i]
        if {$character eq {%}} {
            set hex [string range $value [expr {$i+1}] [expr {$i+2}]]
            if {![regexp {^[0-9A-Fa-f]{2}$} $hex]} {error {Malformed percent encoding in document link}}
            append bytes [binary decode hex $hex];incr i 2
        } else {append bytes [encoding convertto utf-8 $character]}
    }
    documentUtf8Prefix $bytes [string length $bytes]
    set decoded [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $decoded] ne $bytes || [regexp {[\x00-\x1f\x7f%]} $decoded]} {error {Unsafe or multiply encoded document link}}
    return $decoded
}
proc ::GX::_markdownLinkTarget {target} {
    if {$target eq {} || [string bytelength $target]>4096 || [regexp {[\x00-\x1f\x7f]} $target]} {error {Document link is empty or oversized}}
    if {[regexp {^https?://[^[:space:]]+$} $target]} {return [dict create kind external url $target]}
    set target [_markdownLinkDecode $target]
    if {[regexp {^[A-Za-z][A-Za-z0-9+.-]*:} $target] || [regexp {[\\:?]} $target] || [string match {/*} $target]} {error {Unsupported or unsafe document link scheme/path}}
    set parts [split $target #]
    if {[llength $parts]>2} {error {Document link contains multiple fragments}}
    lassign $parts relative fragment
    if {$fragment ne {} && (![regexp {^[[:alnum:]_-]+$} $fragment] || [string bytelength $fragment]>2048)} {error {Unsupported or unsafe heading fragment}}
    if {$relative eq {} && $fragment eq {}} {error {Document link has no destination}}
    return [dict create kind [expr {$relative eq {}?{anchor}:{relative}}] relative $relative fragment [string tolower $fragment]]
}
proc ::GX::_markdownContainedFile {root sourceRelative relative {canonicalComponents 0}} {
    if {$root eq {} || [file pathtype $root] ne {absolute} || ![file isdirectory $root]} {error {No authenticated document root is available}}
    if {[file pathtype $relative] ne {relative} || [regexp {[\\:\x00\r\n]} $relative]} {error {Expected a root-scoped relative document path}}
    set parts [expr {$sourceRelative eq {}?{}:[lrange [split $sourceRelative /] 0 end-1]}]
    foreach part [split $relative /] {
        if {$part eq {.}} continue
        if {$part eq {..}} {
            if {![llength $parts]} {error {Document link escapes its authorized root}}
            set parts [lrange $parts 0 end-1];continue
        }
        if {$part eq {} || (!$canonicalComponents && [string index $part 0] eq {.})} {error {Hidden or ambiguous document paths are unsupported}}
        lappend parts $part
    }
    if {![llength $parts]} {error {Document link does not name a file}}
    # Walk the declared root as well as every destination component. Normalizing
    # first would hide an intermediate symlink, including one back into the root.
    set path {}
    foreach part [file split $root] {
        set path [file join $path $part]
        file lstat $path info
        if {$info(type) ne {directory}} {error {Document root must use real directories without symlinks}}
    }
    foreach part $parts {
        set path [file join $path $part]
        if {[catch {file lstat $path info}]} {error {Linked document is missing}}
        if {$info(type) eq {link}} {error {Document links cannot follow symlinks}}
    }
    if {$info(type) ne {file} || ![file readable $path]} {error {Linked document is not a readable regular file}}
    set actual [file normalize $path];set root [file normalize $root]
    if {[string first "$root/" $actual]!=0} {error {Linked document left its authorized root}}
    return $actual
}
proc ::GX::_markdownNavigationReadFile {path} {
    if {[file size $path]>4194304} {error {Linked Markdown exceeds the 4 MiB document bound}}
    set before [sha256File $path]
    set file [open $path rb]
    try {set bytes [read $file 4194305]} finally {close $file}
    if {[string length $bytes]>4194304 || [string first \x00 $bytes]>=0} {error {Linked Markdown is oversized or contains NUL}}
    documentUtf8Prefix $bytes [string length $bytes]
    if {[sha256File $path] ne $before} {error {Linked document changed during verification}}
    return $before
}
proc ::GX::markdownNavigationContext {kind identity {options {}}} {
    if {[catch {dict size $options}] || [string bytelength $options]>8192} {error {Invalid Markdown navigation options}}
    foreach key [dict keys $options] {
        if {$key ni {open_command status_command}} {error {Unknown Markdown navigation option}}
        set callback [dict get $options $key]
        if {$callback ne {} && (![llength $callback] || ![llength [info commands [lindex $callback 0]]])} {error {Navigation callbacks require a trusted live host command}}
    }
    set context [dict create schema gxtxt.markdown.navigation.v1 kind $kind id $identity options $options]
    switch -- $kind {
        documentation {
            set entry [documentationBrowserResolve $identity]
            if {[dict get $entry format] ne {markdown}} {error {Markdown navigation requires an indexed Markdown source}}
            set path [dict get $entry path];set owner [dict get $entry owner]
            set publicRoot [file normalize [file join $::GX::scriptDir docs]]
            if {[string first "$publicRoot/" $path]==0} {
                set root $publicRoot;set scope public_framework_documentation
            } elseif {[moduleField $owner descriptor {}] ne {}} {
                set root [file normalize [file dirname [moduleField $owner descriptor]]]
                if {[string first "$root/" $path]!=0} {
                    # Authenticated standalone documentation packages already
                    # have a manifest-checked asset root, not a guessed path.
                    if {![dict exists $entry manifest_sha256]} {error {No declared documentation root for this source}}
                    set root [dict get $entry asset_root]
                }
                set scope declared_module_documentation
            } else {error {No authenticated documentation owner/root is available}}
            set relative [string range $path [expr {[string length $root]+1}] end]
            set path [_markdownContainedFile $root {} $relative]
            set sha [_markdownNavigationReadFile $path]
            if {$sha ne [dict get $entry source_sha256]} {error {Documentation source identity changed}}
            dict set context root $root;dict set context relative $relative;dict set context scope $scope
            dict set context identity [list $identity $owner [dict get $entry version] $sha [datasetPublicationV2DictDefault $entry manifest_sha256 {}]]
        }
        dataset {
            if {[datasetDocumentKind $identity] ne {markdown}} {error {Choose a canonical Markdown Dataset}}
            set session [_interactiveDocumentRequireSession]
            set description [datasetDocumentDescribe $identity]
            set path [dict get [sessionInspectionDatasetPayload $identity] path]
            set root [file normalize $session]
            if {[string first "$root/" $path]!=0} {error {Canonical Markdown has no local Session document root}}
            set relative [string range $path [expr {[string length $root]+1}] end]
            # A registered canonical payload may legitimately have hidden path
            # components. Its exact Dataset identity is the authority; this
            # exception never applies to Documentation or Session file browsing.
            set path [_markdownContainedFile $root {} $relative 1]
            if {[_markdownNavigationReadFile $path] ne [dict get $description sha256]} {error {Canonical document SHA changed}}
            dict set context root $root;dict set context relative $relative
            dict set context identity [list [dict get $description session] [dict get $description revision] [dict get $description sha256]]
        }
        session_file {
            set session [_interactiveDocumentRequireSession];set token [interactiveDocumentSessionToken]
            if {![info exists ::GX::ui(sessionFileTree)] || ![winfo exists $::GX::ui(sessionFileTree)] || ![$::GX::ui(sessionFileTree) exists f:$identity]} {error {The source is not registered in the current Session Files browser}}
            set root [file normalize $session];set path [_markdownContainedFile $root {} $identity]
            if {[string tolower [file extension $path]] ni {.md .markdown} || ![sessionFileExplorerAllowed $path]} {error {Session navigation requires an authorized Markdown file}}
            sessionFileExplorerRelative $path
            dict set context root $root;dict set context relative $identity
            dict set context identity [list $token $identity [_markdownNavigationReadFile $path]]
        }
        default {error {No trusted Markdown link context is available}}
    }
    return $context
}
proc ::GX::_markdownNavigationContextCheck {context} {
    if {[catch {dict size $context}] || ![dict exists $context schema] || [dict get $context schema] ne {gxtxt.markdown.navigation.v1}} {error {No trusted Markdown link base is available}}
    if {[dict get $context kind] eq {unavailable}} {error "Document link base unavailable: [dict get $context diagnostic]"}
    set actual [markdownNavigationContext [dict get $context kind] [dict get $context id] [dict get $context options]]
    if {[dict get $actual identity] ne [dict get $context identity]} {error {Document source, revision or Session changed; reopen before following links}}
    return $actual
}
proc ::GX::_markdownNavigationResolve {context target} {
    set context [_markdownNavigationContextCheck $context]
    set path [_markdownContainedFile [dict get $context root] [dict get $context relative] [dict get $target relative] [expr {[dict get $context kind] eq {dataset}}]]
    set extension [string tolower [file extension $path]]
    if {[dict get $context kind] ne {documentation} && $extension ni {.md .markdown}} {error {Relative links require a canonical or authorized Markdown document}}
    switch -- [dict get $context kind] {
        documentation {
            if {$extension ni {.md .markdown .txt .html .htm}} {error {This file type is outside the documentation viewer contract}}
            set id {}
            dict for {candidate entry} $::GX::documentationBrowserEntries {
                if {[dict get $entry path] eq $path} {set id $candidate;break}
            }
            if {$id eq {}} {
                if {[dict get $context scope] ne {public_framework_documentation}} {error {The target is not declared public module documentation}}
                set id linked:markdown:[sha256File $path]
                documentationBrowserAdd $id {Linked document} [file tail $path] linked $path framework $::GX::version
            }
            set entry [documentationBrowserResolve $id]
            if {$extension in {.md .markdown}} {set sha [_markdownNavigationReadFile $path]} else {set sha [sha256File $path]}
            if {$sha ne [dict get $entry source_sha256]} {error {Linked documentation identity changed}}
            return [dict create kind documentation id $id path $path owner [dict get $entry owner] source_sha256 $sha fragment [dict get $target fragment]]
        }
        dataset {
            set found {}
            foreach id [datasetRegistryIds] {
                if {[datasetField $id contract {}] ne {document.text} || [datasetDocumentKind $id] ne {markdown}} continue
                if {![catch {set payload [sessionInspectionDatasetPayload $id]}] && [dict get $payload path] eq $path} {set found $id;break}
            }
            if {$found eq {}} {error {Relative target is not a registered canonical Markdown Dataset}}
            set read [datasetDocumentRead $found 4194304]
            if {![dict get $read complete]} {error {Linked canonical Markdown exceeds the document bound}}
            return [dict create kind dataset id $found source_sha256 [dict get $read sha256] revision [datasetRevisionToken $found] session [interactiveDocumentSessionToken] fragment [dict get $target fragment]]
        }
        session_file {
            set relative [sessionFileExplorerRelative $path]
            if {![$::GX::ui(sessionFileTree) exists f:$relative] || ![sessionFileExplorerAllowed $path]} {error {Linked file is not registered in the current Session Files browser}}
            return [dict create kind session_file id $relative source_sha256 [_markdownNavigationReadFile $path] session [interactiveDocumentSessionToken] fragment [dict get $target fragment]]
        }
    }
}
proc ::GX::markupNavigationBegin {w context} {
    variable ::GX::MarkupNavigation::views
    if {$context ne {} && ([catch {dict size $context}] || ![dict exists $context options] || [catch {dict size [dict get $context options]}])} {error {Markdown navigation context must come from an authorized host}}
    foreach tag [$w tag names] {if {[string match gx_link_* $tag]} {$w tag delete $tag}}
    foreach mark [$w mark names] {if {[string match gx_md_anchor_* $mark]} {$w mark unset $mark}}
    dict set views $w [dict create window_id [winfo id $w] context $context anchors {} links {} focused {} pressed {}]
    set ::GX::MarkupNavigation::status($w) {}
    $w configure -takefocus 1
    if {[llength [info commands ::GX::uiTextEditingAttach]]} {uiTextEditingAttach [winfo toplevel $w] [list $w]}
    set tag GXMarkdownNavigation:$w
    if {$tag ni [bindtags $w]} {bindtags $w [linsert [bindtags $w] 1 $tag]}
    bind $tag <Destroy> [list ::GX::_markupNavigationDestroyed $w %W]
    bind $tag <ButtonPress-1> [list ::GX::_markupNavigationPress $w %x %y %s]
    bind $tag <ButtonRelease-1> [list ::GX::_markupNavigationRelease $w %x %y]
    bind $tag <Tab> "[list ::GX::_markupNavigationFocus $w 1];break"
    bind $tag <Shift-Tab> "[list ::GX::_markupNavigationFocus $w -1];break"
    foreach sequence {<Return> <KP_Enter>} {bind $tag $sequence "[list ::GX::_markupNavigationEnter $w];break"}
    $w tag configure gx_link_focus -background #d9eaff
}
proc ::GX::_markupNavigationDestroyed {w actual} {
    if {$w ne $actual} return
    if {[dict exists $::GX::MarkupNavigation::views $w]} {dict unset ::GX::MarkupNavigation::views $w}
    unset -nocomplain ::GX::MarkupNavigation::status($w)
    set tag GXMarkdownNavigation:$w
    foreach event [bind $tag] {bind $tag $event {}}
}
proc ::GX::_markupNavigationRetire {w} {
    if {[winfo exists $w]} {
        set tag GXMarkdownNavigation:$w
        set index [lsearch -exact [bindtags $w] $tag]
        if {$index>=0} {bindtags $w [lreplace [bindtags $w] $index $index]}
        foreach name [$w tag names] {if {[string match gx_link_* $name]} {$w tag delete $name}}
        foreach name [$w mark names] {if {[string match gx_md_anchor_* $name]} {$w mark unset $name}}
    }
    _markupNavigationDestroyed $w $w
}
proc ::GX::_markupNavigationView {w} {
    if {![winfo exists $w] || ![dict exists $::GX::MarkupNavigation::views $w] || [dict get $::GX::MarkupNavigation::views $w window_id] ne [winfo id $w]} {error {Markdown presentation lifetime ended}}
    return [dict get $::GX::MarkupNavigation::views $w]
}
proc ::GX::markupNavigationInspect {w} {
    set view [_markupNavigationView $w]
    return [dict create anchors [dict get $view anchors] links [dict get $view links] focused [dict get $view focused] status $::GX::MarkupNavigation::status($w)]
}
proc ::GX::markupNavigationHeading {w heading index} {
    set slug [string tolower [string trim $heading]]
    regsub -all {[^[:alnum:]_[:space:]-]} $slug {} slug
    regsub -all {[_[:space:]-]+} $slug {-} slug
    set slug [string trim $slug -];if {$slug eq {}} {set slug section}
    set candidate $slug;set n 0
    while {[dict exists $::GX::MarkupNavigation::views $w anchors $candidate]} {set candidate $slug-[incr n]}
    set mark gx_md_anchor_[dict size [dict get $::GX::MarkupNavigation::views $w anchors]]
    $w mark set $mark $index;$w mark gravity $mark left
    dict set ::GX::MarkupNavigation::views $w anchors $candidate [dict create mark $mark title $heading]
    return $candidate
}
proc ::GX::markupNavigationLinkInsert {w label target} {
    if {![dict exists $::GX::MarkupNavigation::views $w]} {markupNavigationBegin $w {}}
    set n [dict size [dict get $::GX::MarkupNavigation::views $w links]]
    set tag gx_link_$n
    $w tag configure $tag -foreground #0645ad -underline 1
    dict set ::GX::MarkupNavigation::views $w links $tag $target
    $w insert end $label $tag
}
proc ::GX::_markupNavigationAt {w x y} {
    set view [_markupNavigationView $w]
    foreach tag [$w tag names @$x,$y] {if {[dict exists $view links $tag]} {return $tag}}
    return {}
}
proc ::GX::_markupNavigationPress {w x y state} {
    if {[catch {set tag [_markupNavigationAt $w $x $y]}]} return
    dict set ::GX::MarkupNavigation::views $w pressed [list $tag $x $y $state]
    dict set ::GX::MarkupNavigation::views $w focused {}
    $w tag remove gx_link_focus 1.0 end
}
proc ::GX::_markupNavigationRelease {w x y} {
    if {[catch {set view [_markupNavigationView $w]}] || [dict get $view pressed] eq {}} return
    lassign [dict get $view pressed] tag sx sy state
    dict set ::GX::MarkupNavigation::views $w pressed {}
    # Native Text bindings keep selection/copy. Only a same-link non-drag
    # release activates; pressing a link is never itself navigation authority.
    if {$tag eq {} || ($state & 1) || hypot($x-$sx,$y-$sy)>4 || [_markupNavigationAt $w $x $y] ne $tag || [llength [$w tag ranges sel]]} return
    _markupNavigationActivate $w [dict get $view links $tag]
}
proc ::GX::_markupNavigationFocus {w direction} {
    set view [_markupNavigationView $w];set links [dict keys [dict get $view links]]
    set at [lsearch -exact $links [dict get $view focused]]
    set next [expr {$at<0?($direction>0?0:[llength $links]-1):$at+$direction}]
    if {$next<0 || $next>=[llength $links]} {
        set other [expr {$direction>0?[tk_focusNext $w]:[tk_focusPrev $w]}]
        if {$other ne {}} {focus $other}
        dict set ::GX::MarkupNavigation::views $w focused {};return
    }
    set tag [lindex $links $next];set range [$w tag ranges $tag]
    $w tag remove gx_link_focus 1.0 end;$w tag add gx_link_focus {*}$range
    $w mark set insert [lindex $range 0];$w see insert;focus $w
    dict set ::GX::MarkupNavigation::views $w focused $tag
}
proc ::GX::_markupNavigationEnter {w} {
    set view [_markupNavigationView $w];set tag [dict get $view focused]
    if {$tag ne {} && [dict exists $view links $tag]} {_markupNavigationActivate $w [dict get $view links $tag]}
}
proc ::GX::_markupNavigationStatus {w message} {
    set ::GX::MarkupNavigation::status($w) $message
    set context [dict get [_markupNavigationView $w] context]
    if {[dict exists $context options status_command] && [dict get $context options status_command] ne {}} {
        catch {{*}[dict get $context options status_command] $message}
    }
    if {[winfo exists $w]} {event generate $w <<GXMarkdownNavigation>> -data $message}
}
proc ::GX::markupNavigationAnchor {w fragment} {
    set view [_markupNavigationView $w]
    set fragment [string tolower $fragment]
    if {![dict exists $view anchors $fragment]} {error "Heading anchor unavailable: #$fragment"}
    set item [dict get $view anchors $fragment]
    $w mark set insert [dict get $item mark];$w yview [dict get $item mark];focus $w
    _markupNavigationStatus $w "Heading: [dict get $item title] (#$fragment)"
    return [dict create status navigated kind anchor fragment $fragment index [$w index [dict get $item mark]]]
}
proc ::GX::_markdownNavigationDefaultOpen {destination} {
    switch -- [dict get $destination kind] {
        dataset {
            set w [datasetDocumentOpen [dict get $destination id]]
            if {[llength $w]==1 && [winfo exists $w.content] && [winfo class $w.content] eq {Text}} {return [dict create widget $w.content]}
            return {}
        }
        session_file {
            set tree $::GX::ui(sessionFileTree);set id f:[dict get $destination id]
            $tree selection set $id;$tree focus $id;$tree see $id
            sessionFileExplorerOpenSelected
            return [dict create widget $::GX::ui(sessionFileText)]
        }
        documentation {
            if {[moduleField [dict get $destination owner] descriptor {}] ne {}} {
                set w [documentationBrowserOpenReferenceWindow [dict get $destination path] [dict get $destination owner]]
                return [dict create widget $w.body.text]
            }
            documentationBrowserShow [dict get $destination id]
            return [dict create widget .top.nb.help.right.text]
        }
    }
}
proc ::GX::markupNavigationFollow {w target} {
    try {
        set view [_markupNavigationView $w];set parsed [_markdownLinkTarget $target]
        if {[dict get $parsed kind] eq {external}} {markupOpenWebLink [dict get $parsed url];return [dict create status opened kind external]}
        set context [dict get $view context]
        if {$context ne {}} {set context [_markdownNavigationContextCheck $context]}
        if {[dict get $parsed kind] eq {anchor}} {return [markupNavigationAnchor $w [dict get $parsed fragment]]}
        set destination [_markdownNavigationResolve $context $parsed]
        set callback [datasetPublicationV2DictDefault [dict get $context options] open_command {}]
        if {$callback eq {}} {set opened [_markdownNavigationDefaultOpen $destination]} else {set opened [{*}$callback $destination]}
        set fragment [dict get $destination fragment]
        if {$fragment ne {} && ![datasetPublicationV2DictDefault $opened anchor_handled 0]} {
            if {![dict exists $opened widget]} {error {Document opened through its configured association; no shared heading surface is available}}
            markupNavigationAnchor [dict get $opened widget] $fragment
        }
        _markupNavigationStatus $w "Opened linked document: [dict get $destination id]"
        return [dict create status navigated destination $destination]
    } on error {message options} {
        if {[winfo exists $w] && [dict exists $::GX::MarkupNavigation::views $w]} {_markupNavigationStatus $w $message}
        return [dict create status refused message $message]
    }
}
proc ::GX::_markupNavigationActivate {w target} {
    set result [markupNavigationFollow $w $target]
    if {[dict get $result status] ne {refused}} return
    set context [dict get [_markupNavigationView $w] context]
    if {![dict exists $context options status_command] || [dict get $context options status_command] eq {}} {
        # Existing hosts bind their non-modal status. A bare renderer still
        # reports a real refusal visibly instead of silently doing nothing.
        tk_messageBox -parent [winfo toplevel $w] -icon info -title {Document link} -message [dict get $result message]
    }
}
