# Projects GUI

GX-TXT 0.9.7.68 adds a **Projects** notebook tab immediately after **Experiment**. The tab is a GUI projection of the existing Project API v1 introduced in GX-TXT 0.9.7.66; it does not introduce a second Project backend.

The tab provides:

- the persistent Project list;
- selected Project name, ID, description, tags, creation time and update time;
- Project creation and editing through the existing Project metadata dialogs;
- **Open / Select** to associate the current Experiment with the selected Project;
- the Experiments belonging to the selected Project;
- navigation to an Experiment Session when its recorded path is available;
- explicit Experiment detachment without deleting any Session or scientific data.

Project membership remains a logical relationship. Projects do not move Sessions and do not duplicate RAW sources, canonical Datasets, analyses, plots or Viewer state.
