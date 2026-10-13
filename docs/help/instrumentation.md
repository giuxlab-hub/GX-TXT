# Instrumentation

Add only instruments actually used in the experiment. Keep instrument identity, configuration and notes with the Session. The Instrument Library stores reusable definitions and documentation; a Session records the instrument information selected for that experiment.

Scientific notes use UTF-8 GX-Markup / Markdown source. The View/Edit component supports multiline editing, preview, undo, scrolling and wrap control.

## Working in a Session

Select **Instrumentation** in the Session navigator. Choose an instrument in the
left browser to edit its existing configuration in the right canvas. The browser
shows its stable ID and enabled state. **Use in experiment** enables/disables the
instance; **Remove** uses the established removal action.

Use **Instruments → Add Instrument…** to choose an installed Instrument Module and
create a Session instance. **Instruments → Open Library…** shows the reusable
Instrument Library inside the right canvas. Its **Add to Experiment** creates the
same historical linked snapshot as before. **Close** returns to the selected Session
instrument. Library metadata and notes continue to use their existing editors.

Instrument and section selection, and opening/closing the Library, retain pending
Session edits. **Session → Save configuration** saves live instrument fields and
edited instrument notes. When leaving a Session, choose Save, Discard or Cancel;
Cancel keeps the current Session and drafts. Closing edited instrument notes or
removing an instrument also protects pending notes. A real Session change closes old
instrument notes windows so their callbacks cannot affect the destination Session.

Whole Session **Export Session…** and **Import Session…** are under **Tools**, beside
the existing Session action providers. Save your edits before exporting. Portable
Library-entry import/export remain in the Library toolbar and use their original
format. The Library remains independent user state; a Session stores a snapshot.
