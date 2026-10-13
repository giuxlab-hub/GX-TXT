# Ticino Valley 3D Cartography Demo — GX-TXT external module

This independent GX-TXT plugin consumes the four CSV datasets produced by the `GX-TXT Geospatial Examples 1.0.0` Session Generator Library. It does not modify GX-TXT or install into the framework when merely stored in `current/plugins/`.

It produces a numeric report and nine editable public Plot.dataset views: 3D terrain, river, settlements, terrain colored by population density, four CORINE land-cover fraction maps, and an explicitly **synthetic** hydraulic demonstration. Each layer is separate so its color scale and axis controls remain correct. It uses only canonical GX-TXT Dataset/Analysis Sources at runtime. The plugin contains no bundled geographic data and requires no network access.

Report means use the runtime-advertised public `math.numeric` reduction API. Terrain and hydraulic values remain unchanged.

Package ID: `demo.geospatial.ticino_valley_3d`, version 2.0.0. Code license: GPL-3.0-or-later. See `MANUAL.md` for setup, scientific meaning and cautions.
