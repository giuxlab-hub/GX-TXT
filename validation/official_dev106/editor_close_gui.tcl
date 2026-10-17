proc editorMenu {w label} {
    foreach row [widgets $w] {lassign $row path class text;if {$class ne {Menu}} continue;set end [$path index end];if {$end eq {none}} continue;for {set i 0} {$i<=$end} {incr i} {if {[$path type $i] eq {command} && [$path entrycget $i -label] eq $label} {return [$path invoke $i]}}}
    error "Actual editor menu command missing: $label"
}
proc editorModalTrace {command operation} {incr ::editorModalCount;record editor_modal_$::editorModalCount $command}
proc editorCancelModal {} {
    foreach row [widgets] {set button [lindex $row 0];if {[string match *.__tk__messagebox.cancel $button]} {set dialog [winfo toplevel $button];capture $dialog actual_dirty_cancel_dialog;$button invoke;return}}
    after 70 editorCancelModal
}
proc editorCloseAudit {} {
    set ::editorModalCount 0;trace add execution ::tk_messageBox enter editorModalTrace
    foreach language {Python Octave} {
        upvar #0 ::GX::${language}ScriptEditorUI::ui ed
        ::GX::${language}ScriptEditorUI::_recomputeDirty;gcheck {!$ed(modified)} ${language}_populated_clean_before_close
        set metadata [::GX::scriptRegistryDescribe $ed(currentId)];set path [dict get $metadata source_path];set sha [::GX::sha256File $path]
        set w $ed(window);editorMenu $w Close
        gcheck {![winfo exists $w] && $::editorModalCount==0 && [::GX::sha256File $path] eq $sha} ${language}_populated_menu_close_no_prompt
    }
    set ::GX::cfg(output_root) [file join $::out Sessions];::GX::createNewSession editor_close_pristine
    foreach language {Python Octave} {
        set lower [string tolower $language]
        for {set pass 0} {$pass<2} {incr pass} {
            ::GX::${language}ScriptEditorUI::open
            upvar #0 ::GX::${language}ScriptEditorUI::ui ed
            set w $ed(window)
            after 700 {set ::editorIdle 1};vwait ::editorIdle
            ::GX::${language}ScriptEditorUI::_recomputeDirty
            gcheck {!$ed(modified) && [::GX::scriptRegistryList session] eq {}} ${lower}_pristine_idle_clean_$pass
            if {$pass==0} {editorMenu $w Close} else {raise $w;focus -force $w;update;exec xdotool key --clearmodifiers alt+F4;guiWait {![winfo exists $w]}}
            gcheck {![winfo exists $w] && $::editorModalCount==0} ${lower}_pristine_real_close_no_modal_$pass
        }
    }
    foreach language {Python Octave} {
        set lower [string tolower $language]
        ::GX::${language}ScriptEditorUI::open;upvar #0 ::GX::${language}ScriptEditorUI::ui ed
        set w $ed(window);set original [$ed(text) get 1.0 end-1c];set previous $::editorModalCount
        $ed(text) insert end {# real unsaved edit};update;::GX::${language}ScriptEditorUI::_recomputeDirty
        gcheck {$ed(modified)} ${lower}_real_change_dirty
        after 250 editorCancelModal;editorMenu $w Close
        gcheck {[winfo exists $w] && $ed(modified) && $::editorModalCount==$previous+1} ${lower}_actual_one_modal_cancel_preserves_edit
        $ed(text) edit undo;update;::GX::${language}ScriptEditorUI::_recomputeDirty
        gcheck {!$ed(modified) && [$ed(text) get 1.0 end-1c] eq $original} ${lower}_undo_after_cancel_exact_clean
        editorMenu $w Close
        gcheck {![winfo exists $w] && $::editorModalCount==$previous+1} ${lower}_clean_close_no_extra_modal
    }
    # One explicit saved revision in each actual editor; no execution.
    foreach language {Python Octave} {
        set lower [string tolower $language]
        ::GX::${language}ScriptEditorUI::open;upvar #0 ::GX::${language}ScriptEditorUI::ui ed
        set w $ed(window)
        $w.p.center.props.ie delete 0 end;$w.p.center.props.ie insert 0 saved_$lower
        $ed(text) insert end "\n# explicitly saved revision\n"
        editorMenu $w Save
        ::GX::${language}ScriptEditorUI::_recomputeDirty
        gcheck {!$ed(modified) && $ed(currentId) eq "session:saved_$lower"} ${lower}_actual_gui_save_clean
        set metadata [::GX::scriptRegistryDescribe $ed(currentId)];set sha [dict get $metadata sha256]
        editorMenu $w Close;::GX::${language}ScriptEditorUI::open
        ::GX::${language}ScriptEditorUI::_loadDocument session:saved_$lower
        upvar #0 ::GX::${language}ScriptEditorUI::ui ed
        ::GX::${language}ScriptEditorUI::_recomputeDirty
        gcheck {!$ed(modified) && $ed(currentSha) eq $sha && [::GX::sha256File [dict get $metadata source_path]] eq $sha} ${lower}_saved_reopen_sha_clean
        editorMenu $ed(window) Close
    }
    trace remove execution ::tk_messageBox enter editorModalTrace
    record editor_close_gui [dict create status PASS real_dirty_modals $::editorModalCount expected 2 pristine_close_methods {FileMenu DebianAltF4} saved_scripts [::GX::scriptRegistryList session]]
}
if {[catch {editorCloseAudit} reason options]} {catch {trace remove execution ::tk_messageBox enter editorModalTrace};record editor_close_failure [dict get $options -errorinfo]}
