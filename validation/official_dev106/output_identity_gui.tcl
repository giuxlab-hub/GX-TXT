proc outputIdentityAudit {} {
    set w .scriptJobDetail1;set id $::GX::scriptJobDetail($w,id)
    toplevel .primary_probe;text .primary_probe.text -exportselection 1 -height 2 -width 30;pack .primary_probe.text
    .primary_probe.text insert end PRIMARY_SENTINEL_ONLY
    .primary_probe.text tag add sel 1.0 end-1c
    selection own -selection PRIMARY .primary_probe.text
    set ::GX::scriptJobDetail($w,streamLabel) {Program output};::GX::scriptJobDetailSourceChanged $w
    ::GX::scriptJobDetailCopyFull $w;guiWait {![info exists ::GX::scriptJobDetail($w,transfer)]}
    set path [file join $::out independent-native-paste.txt];set primary [file join $::out independent-primary.txt]
    set code {import sys,tkinter;from pathlib import Path;r=tkinter.Tk();r.title('Independent native clipboard paste verification');r.geometry('680x240+900+700');t=tkinter.Text(r,exportselection=False);t.pack(fill='both',expand=True);r.update();p=r.selection_get(selection='PRIMARY');t.focus_force();t.event_generate('<<Paste>>');r.update();Path(sys.argv[1]).write_text(t.get('1.0','end-1c'),encoding='utf-8');Path(sys.argv[2]).write_text(p,encoding='utf-8');r.after(150,r.destroy);r.mainloop();print('ok 1 result pasted')}
    unset -nocomplain ::nativePaste
    ::GX::scriptJobAsync [list [::GX::runtimeToolRequired python] -c $code $path $primary] {} {apply {{r} {set ::nativePaste $r}}}
    guiWait {[info exists ::nativePaste]}
    set fd [open $primary];set p [read $fd];close $fd
    gcheck {$p eq {PRIMARY_SENTINEL_ONLY}} native_primary_distinct
    gcheck {[::GX::sha256File $path] eq [::GX::sha256File [file join $::out exact-output.txt]]} independent_actual_paste_full_bytes
    destroy .primary_probe
    foreach {label role dataset} {{Program output} stdout gui_program_output {Diagnostic log} diagnostics gui_diagnostic_log} {
        set ::GX::scriptJobDetail($w,streamLabel) $label;::GX::scriptJobDetailSourceChanged $w
        if {$role eq {diagnostics}} {
            set export [file join $::out diagnostic-only.txt];::GX::scriptJobDetailTransfer $w $export;guiWait {![info exists ::GX::scriptJobDetail($w,transfer)]}
            set page [::GX::scriptJobStreamRead $id diagnostics]
            set f [open $export rb];set raw [read $f];close $f
            gcheck {[dict get $page eof] && $raw eq [binary decode base64 [dict get $page content_base64]]} genuine_diagnostic_export_exact
        }
        $w.actions.publish invoke
        $w.publish.id delete 0 end;$w.publish.id insert 0 $dataset
        $w.publish.apply invoke
        gcheck {![winfo exists $w.publish] && [::GX::datasetField $dataset id {}] eq $dataset} gui_explicit_publish_$role
        set canonical [::GX::datasetResolvePath $::GX::currentSession $dataset]
        if {$role eq {stdout}} {set expected [file join $::out exact-output.txt]} else {set expected [file join $::out diagnostic-only.txt]}
        gcheck {[::GX::sha256File $canonical] eq [::GX::sha256File $expected]} gui_published_exact_$role
    }
    set before [::GX::datasetRegistryIds];set hash [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession gui_diagnostic_log]]
    $w.actions.publish invoke;$w.publish.id delete 0 end;$w.publish.id insert 0 gui_diagnostic_log;$w.publish.apply invoke
    gcheck {[winfo exists $w.publish] && [string match {Publication failed:*} $::GX::scriptJobDetail($w,status)] && [::GX::datasetRegistryIds] eq $before && [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession gui_diagnostic_log]] eq $hash} duplicate_gui_stream_publication_refused
    ::GX::uiFieldDialogClose $w.publish
    record output_identity_gui [dict create status PASS job_id $id actual_native_paste_sha256 [::GX::sha256File $path] primary_text $p stdout_dataset gui_program_output diagnostic_dataset gui_diagnostic_log diagnostic_sha256 $hash]
}
if {[catch {outputIdentityAudit} reason options]} {record output_identity_failure [dict get $options -errorinfo]}
