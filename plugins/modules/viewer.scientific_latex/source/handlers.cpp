// Author-owned event dispatch. CORE owns source, assets, compilation and PDF.
// No source bytes, filesystem destinations or executable choices enter C++.
// Installed GUI/scientific acceptance is a separate recorded gate.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.tex_command(14, "refresh");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    switch (event.component) {
    case 23: host.tex_command(14, "new"); break;
    case 24: host.tex_command(14, "open"); break;
    case 25: host.tex_command(14, "save"); break;
    case 26: host.tex_command(14, "build"); break;
    case 27: host.tex_command(14, "rebuild"); break;
    case 28: host.tex_command(14, "cancel"); break;
    case 29: host.tex_command(14, "import_assets"); break;
    case 30: host.tex_command(14, "export_tex"); break;
    case 31: host.tex_command(14, "export_pdf"); break;
    case 32: host.tex_command(14, "export_assets"); break;
    case 33: host.tex_command(14, "refresh"); break;
    case 34: host.tex_command(14, "preview"); break;
    case 35: host.tex_command(14, "import_source"); break;
    case 36: host.tex_command(14, "diagnostic_open"); break;
    case 39: host.tex_command(14, "remove_asset"); break;
    default: break;
    }
}
