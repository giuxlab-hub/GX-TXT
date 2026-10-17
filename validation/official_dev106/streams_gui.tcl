proc streamsAudit {} {
    set text "Unicode Ω α é 漢字\n[string repeat {αβΩ line 1234
} 9000]"
    set code "import sys\nprint([list $text], end='')\nprint('stderr separate Ω', file=sys.stderr)\n"
    # Python literals are generated without executing source text or a shell.
    set code "import sys\nsys.stdout.write('[string map [list \\ \\\\ ' \\' \n \\n \r \\r] $text]')\nsys.stderr.write('stderr separate Ω\\n')\n"
    ::GX::scriptRegistrySave session unicode_output_final {Unicode output fixture} $code {language Python}
    set job [::GX::scriptJobSubmit session:unicode_output_final {}];set id [dict get $job id]
    set job [::GX::scriptJobWait $id 90];gcheck {[dict get $job state] eq {COMPLETED}} unicode_job_completed
    set w [::GX::scriptJobDetailsWindow $id]
    guiWait {$::GX::scriptJobDetail($w,record) ne {}}
    set ::GX::scriptJobDetail($w,streamLabel) {Program output};::GX::scriptJobDetailSourceChanged $w
    ::GX::scriptJobDetailCopyFull $w;guiWait {![info exists ::GX::scriptJobDetail($w,transfer)]}
    set ::clipboardExpected $text
    set command [list [::GX::runtimeToolRequired python] -c {import tkinter,json; r=tkinter.Tk();r.withdraw();print(json.dumps({'ok':True,'result':r.clipboard_get()},ensure_ascii=False));r.destroy()}]
    # Existing managed request protocol is Tcl; independent paste process writes an exact UTF-8 file instead.
    set paste [file join $::out independent-paste.txt]
    set command [list [::GX::runtimeToolRequired python] -c {import tkinter,sys;from pathlib import Path;r=tkinter.Tk();r.withdraw();Path(sys.argv[1]).write_text(r.clipboard_get(),encoding='utf-8');r.destroy();print('ok 1 result pasted')} $paste]
    ::GX::scriptJobAsync $command {} {apply {{r} {set ::pasteReceipt $r}}}
    guiWait {[info exists ::pasteReceipt]}
    set f [open $paste];fconfigure $f -encoding utf-8;set pasted [read $f];close $f
    gcheck {$pasted eq $text} independent_clipboard_full_unicode
    set export [file join $::out exact-output.txt];::GX::scriptJobDetailTransfer $w $export;guiWait {![info exists ::GX::scriptJobDetail($w,transfer)]}
    set f [open $export rb];set bytes [read $f];close $f
    gcheck {$bytes eq [encoding convertto utf-8 $text]} exact_atomic_export_bytes
    auditCapture $w output_streams
    record workspace_gui [dict create status PASS session $::GX::currentSession unicode_bytes [string length $bytes]]
}
if {[catch {streamsAudit} failure options]} {record streams_gui_failure [dict get $options -errorinfo]}
