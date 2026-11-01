# Modules page

Open **Modules** in the main window. Cards use the installed registry's groups, stacked independently in each column to avoid gaps beside longer groups. At ordinary desktop widths two columns share the space. Larger fonts and narrower windows use one column when the names and controls need more room. Use the wheel or the scrollbar to reach further groups; keyboard focus also reveals controls through the shared UI Field scroll host.

Each row shows its registered name, a switch, its explicit state and **Help**. ON/OFF and CORE / ON/OFF are Session choices. **Always available** services have a checked, disabled switch. CORE package protection does not make every CORE analysis permanently ON. Green and gray supplement the text.

Changing a switch calls the ordinary module activation API. If a disabled prerequisite or an enabled direct dependent may be affected, a confirmation names those related modules. **Cancel** keeps the canonical flags and resets the switch. After acceptance, the feedback line reports the selected module and all actual related flag changes. An activation error reports the current canonical state; a later display refresh error is identified separately and does not claim the activation was undone.

An installed update reported by the public runtime service as requiring restart adds **Restart required** below the activation state. This is a package runtime condition, separate from the Session switch. Use the existing Plugin Manager for package updates.

**Help** opens that module's declared manual in the existing independent CORE manual window. Several different module manuals can remain open; Help does not embed documentation into this page. Missing manuals are reported by the documentation owner. The official registry and Configuration retain stable IDs, versions and metadata.

Select a name or focus its switch to select the target for the existing runtime reset tool. Reset is a separate operation with its own confirmation. No reset is performed when changing a switch.
