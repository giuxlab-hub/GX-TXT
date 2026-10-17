# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildModulesPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Module catalog: scheda separata e scalabile a decine di moduli.
    set f .top.nb.modules
    grid columnconfigure $f 0 -weight 3
    grid columnconfigure $f 1 -weight 2
    grid rowconfigure $f 3 -weight 1
    ttk::frame $f.header
    grid $f.header -row 0 -column 0 -columnspan 2 -sticky ew
    grid columnconfigure $f.header 0 -weight 1
    ttk::frame $f.filters
    set ::GX::moduleCoreFilter All
    if {$::GX::moduleKindFilter ni {All Analysis}} {set ::GX::moduleKindFilter All}
    if {$::GX::moduleGroupFilter ni [linsert [::GX::moduleGroups] 0 All]} {set ::GX::moduleGroupFilter All}
    ttk::label $f.filters.sl -text "Search"
    ttk::entry $f.filters.search -textvariable ::GX::moduleSearch -width 18
    ttk::label $f.filters.kl -text "Type"
    ttk::combobox $f.filters.kind -textvariable ::GX::moduleKindFilter -values {All Analysis} -state readonly -width 16
    ttk::label $f.filters.gl -text "Group"
    ttk::combobox $f.filters.group -textvariable ::GX::moduleGroupFilter -values [linsert [::GX::moduleGroups] 0 All] -state readonly -width 20
    ttk::combobox $f.filters.core -textvariable ::GX::moduleCoreFilter -values {All CORE Non-CORE} -state readonly -width 9
    ttk::button $f.filters.go -text "Filter" -command ::GX::refreshModuleCatalog
    pack $f.filters.sl $f.filters.search $f.filters.kl $f.filters.kind $f.filters.gl $f.filters.group $f.filters.core $f.filters.go -side left -padx 3
    ttk::frame $f.quick
    foreach {key label id} {plot Plot plot.dataset octave {Script Octave} analysis.octave_script python {Script Python} analysis.python_script} {
        set ui(moduleQuick,$id) [moduleIsEnabled $id]
        ttk::checkbutton $f.quick.$key -text $label -variable ::GX::ui(moduleQuick,$id) -command [list ::GX::moduleQuickSet $id]
        pack $f.quick.$key -side left -padx 4
    }
    # Two independent grid cells keep quick controls to the right of filters.
    grid $f.filters -in $f.header -row 0 -column 0 -sticky w -padx 5 -pady 5
    grid $f.quick -in $f.header -row 0 -column 1 -sticky e -padx 5 -pady 5
    bind $f <Configure> [list ::GX::modulesFiltersFit $f %w]
    bind $f.filters.search <KeyRelease> {::GX::refreshModuleCatalog}
    foreach name {kind group core} {bind $f.filters.$name <<ComboboxSelected>> {::GX::refreshModuleCatalog}}

    ttk::frame $f.buttons
    ttk::menubutton $f.buttons.state -text "Module State" -menu $f.buttons.state.menu
    menu $f.buttons.state.menu -tearoff 0
    $f.buttons.state.menu add command -label Enable -command [list ::GX::setSelectedModuleState 1]
    $f.buttons.state.menu add command -label Disable -command [list ::GX::setSelectedModuleState 0]
    $f.buttons.state.menu add command -label Toggle -command ::GX::toggleSelectedModule
    ttk::menubutton $f.buttons.runtime -text Runtime -menu $f.buttons.runtime.menu
    menu $f.buttons.runtime.menu -tearoff 0
    $f.buttons.runtime.menu add command -label "Reset Module Runtime…" -command ::GX::resourceLifecycleModuleResetSelected
    ttk::menubutton $f.buttons.tools -text Tools -menu $f.buttons.tools.menu
    menu $f.buttons.tools.menu -tearoff 0
    $f.buttons.tools.menu add command -label "Script Module Builder…" -command ::GX::scriptModuleBuilderOpen
    ttk::button $f.buttons.help -text "Module help..." -command ::GX::showSelectedModuleHelp
    ttk::label $f.buttons.note -text "Select modules for Analysis. Installed plugins: Configuration → Modules."
    pack $f.buttons.state $f.buttons.runtime $f.buttons.tools $f.buttons.help $f.buttons.note -side left -padx 4
    grid $f.buttons -row 1 -column 0 -columnspan 2 -sticky w -padx 5 -pady 3

    ttk::treeview $f.tree -columns {state kind ver id} -show {tree headings} -selectmode browse
    $f.tree heading #0 -text "Group / module"
    $f.tree column #0 -width 390 -stretch 1
    foreach {c title width stretch} {state "Status" 105 0 kind "Type" 125 0 ver "Ver." 65 0 id "Stable ID" 210 0} {
        $f.tree heading $c -text $title
        $f.tree column $c -width $width -stretch $stretch
    }
    ttk::scrollbar $f.sy -orient vertical -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.sy set]
    text $f.details -wrap word -state disabled
    ttk::scrollbar $f.dy -orient vertical -command [list $f.details yview]
    $f.details configure -yscrollcommand [list $f.dy set]
    # Catalogo e dettagli devono condividere la stessa riga espandibile.
    # In v0.3.4 il treeview era accidentalmente in riga 3 mentre i dettagli
    # erano in riga 2 (l'unica con peso): il catalogo veniva quindi schiacciato
    # sul fondo della scheda.
    grid $f.tree -row 3 -column 0 -sticky nsew -padx {5 0} -pady 5
    grid $f.sy -row 3 -column 0 -sticky nse -pady 5
    grid $f.details -row 3 -column 1 -sticky nsew -padx {8 0} -pady 5
    grid $f.dy -row 3 -column 1 -sticky nse -pady 5
    set ui(moduleTree) $f.tree
    set ui(moduleDetails) $f.details
    bind $f.tree <<TreeviewSelect>> {::GX::refreshModuleDetails}
    bind $f.tree <Double-1> {::GX::toggleSelectedModule}
    menu $f.context -tearoff 0
    foreach {label command} {Enable {::GX::setSelectedModuleState 1} Disable {::GX::setSelectedModuleState 0} Toggle ::GX::toggleSelectedModule} {
        $f.context add command -label $label -command $command
    }
    bind $f.tree <Button-3> [list ::GX::moduleContextMenu %x %y %X %Y]


}
