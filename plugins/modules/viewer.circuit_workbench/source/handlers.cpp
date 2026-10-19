void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.diagram_open(56);
        host.scientific_discover(29);
        host.text(1, "Circuit Workbench · canonical analysis, waveforms and Numeric");
        host.text(2, "Tools edits circuits. Simulation/Sweep runs through Jobs; Numeric provides RC/AC/interpolation. Waveforms uses canonical Datasets. View edits traces/panels and pane visibility; Source / netlist inspects the guarded deck. Admission is not completion.");
    }
    if (event.kind == gx::EventKind::invoke) {
        state.counter += 1;
        if (event.component == 3) {
            state.values[0] = host.numeric_exp(event.value);
            host.number(1, state.values[0]);
            host.text(2, "Public Numeric exp(0) SDK check only; this is not a circuit response validation.");
        }
        if (event.component == 11) { host.diagram_tool(56, "select"); host.text(1, "Select selected · inspect the actual schematic"); }
        if (event.component == 12) { host.diagram_tool(56, "wire"); host.text(1, "Wire selected · inspect the actual schematic"); }
        if (event.component == 13) { host.diagram_tool(56, "resistor"); host.text(1, "Resistor selected · inspect the actual schematic"); }
        if (event.component == 14) { host.diagram_tool(56, "capacitor"); host.text(1, "Capacitor selected · inspect the actual schematic"); }
        if (event.component == 15) { host.diagram_tool(56, "inductor"); host.text(1, "Inductor selected · inspect the actual schematic"); }
        if (event.component == 16) { host.diagram_tool(56, "voltage"); host.text(1, "Voltage selected · inspect the actual schematic"); }
        if (event.component == 17) { host.diagram_tool(56, "current"); host.text(1, "Current selected · inspect the actual schematic"); }
        if (event.component == 18) { host.diagram_tool(56, "ground"); host.text(1, "Ground selected · inspect the actual schematic"); }
        if (event.component == 19) { host.diagram_tool(56, "diode"); host.text(1, "Diode selected · inspect the actual schematic"); }
        if (event.component == 20) { host.diagram_tool(56, "npn"); host.text(1, "NPN selected · inspect the actual schematic"); }
        if (event.component == 21) { host.diagram_tool(56, "junction"); host.text(1, "Junction selected · inspect the actual schematic"); }
        if (event.component == 22) { host.diagram_tool(56, "label"); host.text(1, "Net label selected · inspect the actual schematic"); }
        if (event.component == 23) { host.diagram_tool(56, "pan"); host.text(1, "Pan selected · inspect the actual schematic"); }
        if (event.component == 24) { host.diagram_tool(56, "probe"); host.text(1, "Probe selected · inspect the actual schematic"); }
        if (event.component == 25) { host.diagram_command(56, "fit"); host.text(1, "Fit selected · inspect the actual schematic"); }
        if (event.component == 26) { host.diagram_command(56, "properties"); host.text(1, "Properties selected · inspect the actual schematic"); }
        if (event.component == 27) { host.diagram_command(56, "rotate"); host.text(1, "Rotate selected · inspect the actual schematic"); }
        if (event.component == 28) { host.diagram_command(56, "delete"); host.text(1, "Delete selected · inspect the actual schematic"); }
        if (event.component == 45 || event.component == 159) { host.scientific_prepare(56, 29); host.text(1, "Prepare requested · inspect genuine Jobs status"); }
        if (event.component == 46 || event.component == 160) { host.scientific_submit(29); host.text(1, "Submit requested · inspect genuine Jobs status"); }
        if (event.component == 47) { host.scientific_status(29); host.text(1, "Refresh status requested · inspect genuine Jobs status"); }
        if (event.component == 48) { host.scientific_cancel(29); host.text(1, "Cancel run(s) requested · inspect genuine Jobs status"); }
        if (event.component == 49) { host.scientific_reconnect(29); host.text(1, "Reconnect requested · inspect genuine Jobs status"); }
        if (event.component == 50) { host.scientific_log(29); host.text(1, "Read log requested · inspect genuine Jobs status"); }
        if (event.component == 51) { host.scientific_import(29, 44); host.text(1, "Publish Dataset requested · inspect genuine Jobs status"); }
        if (event.component == 52 || event.component == 158) { host.scientific_discover(29); host.text(1, "Discover nodes / axes requested · inspect genuine Jobs status"); }
        if (event.component == 62) { host.plot_discover(58); host.text(1, "Canonical variable discovery requested"); }
        if (event.component == 63) { host.plot_bind(57, 58); host.text(1, "Canonical waveform binding requested"); }
        if (event.component == 90) { host.numeric_discover(70); host.text(1, "Numeric discovery requested · inspect actual rows/units before changing count"); }
        if (event.component == 91) { host.numeric_evaluate(70); host.text(1, "Public Numeric evaluation requested · inspect the genuine result/error"); }
        if (event.component == 92) { host.numeric_statistics(70); host.text(1, "Public Numeric statistics requested · inspect validated fields"); }
        if (event.component == 93) { host.numeric_compare(70); host.text(1, "Public residual comparison requested · inspect original captured request"); }
        if (event.component == 94) { host.numeric_publish(70, 44); host.text(1, "Explicit reference publication requested · inspect canonical Dataset receipt"); }
        if (event.component == 113) { host.numeric_discover(101); host.text(1, "AC discovery requested · inspect actual split-complex Variables"); }
        if (event.component == 114) { host.numeric_evaluate(101); host.text(1, "Public AC projection requested · inspect stored units/result"); }
        if (event.component == 115) { host.numeric_statistics(101); host.text(1, "Projection statistics requested · inspect validated facts"); }
        if (event.component == 116) { host.numeric_publish(101, 44); host.text(1, "Explicit projection publication requested · plot canonical x/value"); }
        if (event.component == 133) { host.numeric_discover(117); host.text(1, "Interpolation discovery requested · inspect both canonical grids"); }
        if (event.component == 134) { host.numeric_evaluate(117); host.text(1, "Public interpolation requested · inspect exact source/query intervals"); }
        if (event.component == 135) { host.numeric_statistics(117); host.text(1, "Interpolated statistics requested · inspect validated facts"); }
        if (event.component == 136) { host.numeric_publish(117, 44); host.text(1, "Explicit interpolation publication requested · plot query x/value"); }
    }
}
