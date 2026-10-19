# Standard text editing belongs to the focused widget, never to a viewer action.
# Optional Tk support for UI_FIELD_API_v1. No global bindings or shortcut registry.
namespace eval ::GX::UiTextEditing {variable last {}}
proc ::GX::uiTextEditingAttach {window widgets} {
    foreach widget $widgets {
        if {![winfo exists $widget] || [winfo toplevel $widget] ne $window || [winfo class $widget] ni {Text Entry TEntry TCombobox Spinbox TSpinbox}} {error {Text editing requires a text control in the owning window}}
        set tag GXTextEditing:$widget
        if {$tag in [bindtags $widget]} continue
        bindtags $widget [linsert [bindtags $widget] 1 $tag]
        bind $tag <FocusIn> [list ::GX::_uiTextEditingRemember $window $widget]
        bind $tag <Control-a> "[list ::GX::uiTextEdit $window select_all]; break"
        bind $tag <Control-A> "[list ::GX::uiTextEdit $window select_all]; break"
        if {[winfo class $widget] eq "Text"} {
            bind $tag <<Paste>> "[list ::GX::uiTextEdit $window paste]; break"
            bind $tag <Control-z> "[list ::GX::uiTextEdit $window undo]; break"
            bind $tag <Control-y> "[list ::GX::uiTextEdit $window redo]; break"
            bind $tag <Control-Shift-Z> "[list ::GX::uiTextEdit $window redo]; break"
        }
        bind $tag <Destroy> [list ::GX::_uiTextEditingForget $window $widget $tag]
    }
}
proc ::GX::_uiTextEditingRemember {window widget} {dict set ::GX::UiTextEditing::last $window $widget}
proc ::GX::_uiTextEditingForget {window widget tag} {
    foreach sequence [bind $tag] {bind $tag $sequence {}}
    if {[dict exists $::GX::UiTextEditing::last $window] && [dict get $::GX::UiTextEditing::last $window] eq $widget} {dict unset ::GX::UiTextEditing::last $window}
}
proc ::GX::uiTextEditTarget {window} {
    set widget [focus -displayof $window]
    if {$widget eq {} || ([winfo exists $widget] && [winfo class $widget] in {Menu Menubutton TMenubutton})} {
        if {[dict exists $::GX::UiTextEditing::last $window]} {set widget [dict get $::GX::UiTextEditing::last $window]}
    }
    if {$widget eq {} || ![winfo exists $widget] || [winfo toplevel $widget] ne $window || "GXTextEditing:$widget" ni [bindtags $widget]} {return {}}
    return $widget
}
proc ::GX::uiTextEditCan {window operation} {
    set widget [uiTextEditTarget $window]
    if {$widget eq {}} {return 0}
    set text [expr {[winfo class $widget] eq "Text"}]
    set state [$widget cget -state]
    if {$state eq "disabled"} {return 0}
    if {$operation in {cut paste undo redo} && $state ne "normal"} {return 0}
    switch -- $operation {
        undo - redo {return [expr {$text && [$widget cget -undo] && [$widget edit can$operation]}]}
        copy - cut {
            if {$text} {return [expr {[llength [$widget tag ranges sel]]>0}]}
            return [$widget selection present]
        }
        select_all - paste {return 1}
        default {error "Unknown text editing operation: $operation"}
    }
}
proc ::GX::uiTextEdit {window operation} {
    if {![uiTextEditCan $window $operation]} {return 0}
    set widget [uiTextEditTarget $window]
    focus $widget
    switch -- $operation {
        select_all {
            if {[winfo class $widget] eq "Text"} {
                $widget tag add sel 1.0 end-1c
                $widget mark set insert end-1c
            } else {$widget selection range 0 end; $widget icursor end}
        }
        undo - redo {$widget edit $operation}
        cut {event generate $widget <<Cut>>}
        copy {event generate $widget <<Copy>>}
        paste {
            if {[winfo class $widget] eq "Text"} {
                # Tk's local `clipboard get` decodes independent 4000-byte
                # chunks and can split UTF-8 scalars. Tk's normal selection
                # helper requests UTF8_STRING with its platform fallback.
                if {[catch {::tk::GetSelection $widget CLIPBOARD} content]} {return 0}
                # Tk's X11 Text class inserts after a selection by default.
                # Editors require replacement as one local undo transaction.
                set separators [$widget cget -autoseparators]
                $widget edit separator
                $widget configure -autoseparators 0
                try {
                    if {[llength [$widget tag ranges sel]]} {
                        $widget replace sel.first sel.last $content
                        $widget tag remove sel 1.0 end
                    } else {$widget insert insert $content}
                } finally {$widget edit separator; $widget configure -autoseparators $separators}
            } else {event generate $widget <<Paste>>}
        }
    }
    return 1
}
