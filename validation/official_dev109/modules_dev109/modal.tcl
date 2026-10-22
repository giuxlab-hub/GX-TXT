proc dependencyDialog {choice name {remaining 100}} {
    set modal .__tk__messagebox
    if {![winfo exists $modal] || ![winfo ismapped $modal]} {
        if {$remaining>0} {after 50 [list dependencyDialog $choice $name [expr {$remaining-1}]];return}
        set ::dialogFailure {Expected mapped dependency confirmation};return
    }
    record ${name}_dialog [dict create title [wm title $modal] widgets [widgets $modal] states [::GX::moduleCardsEnabledSnapshot]]
    capture $modal ${name}_dialog
    exec xdotool windowfocus --sync [winfo id $modal]
    exec xdotool key --clearmodifiers [expr {$choice eq {cancel}?{Escape}:{alt+o}}]
    set ::dialogObserved 1
}
