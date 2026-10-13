# GUI Appearance — Configuration API v1

Configuration → Appearance is the rightmost Configuration subtab, after all
existing pages (including Installation Identity). It uses the existing
`configurationFields/Get/Set/Validate/Save` authority and `configuration.ini`
user scope. No visual preferences are written into a Session manifest.

| Field | Default | Supported values / effect |
|---|---|---|
| `ui.theme` | `system` | System/default or a theme enumerated by the actual `ttk::style theme names` interpreter |
| `ui.font_family` | `system` | System/default or an installed proportional GUI family from `font families` |
| `ui.font_size` | `system` | System/default or 8–24 points; named-font relative sizes retained |
| `ui.x11_popup_repair_enabled` | `1` | Boolean; only HC-Consult/VcXsrv X11 servers qualify |
| `ui.x11_popup_repair_delay_ms` | `150` | Integer 25–2000 ms after popup mapping; shortcuts 150/300/500 |

Choose settings, then **Save user defaults**. Themes and fonts take effect on
restarting GX-TXT, before theme-dependent widgets, custom styles and native hosts
are built. Existing windows keep their appearance. Tk theme switching loses
per-theme custom selection styles; startup-only application also avoids changing
font geometry under an active native 2D/3D embed. No restart is initiated for you.
**Revert unsaved appearance** restores the last saved choices without changing
other edits. **Restore appearance defaults** stages only these five declared
defaults; Save is still required. Current effective appearance reports actual
active theme/Tk/named fonts/scaling, separately from pending or saved preferences.
An unavailable saved theme falls back to the interpreter's original theme and
shows a nonfatal warning. A missing saved font family similarly retains defaults.
Invalid delay/size rejects Save and preserves the previous good configuration.
For large fonts or narrow windows, focus a notebook and use Left/Right to cycle
its pages when their tab labels extend beyond the visible strip.

Tk named fonts are the presentation authority: proportional GUI families change
where widgets already use those fonts. TkHeadingFont's weight is retained;
TkFixedFont keeps its monospace family. Size adjusts relative named-font sizes.
Explicit module/editor fonts and PDF/figure output fonts are not changed. Themes
style ttk widgets, including their state/focus/selection/disabled presentation;
classic Tk text/canvas colors and scientific graphics are not a complete dark mode.

Excluded controls: arbitrary global colors need coherent classic/ttk/canvas state
coverage that this framework does not own centrally; private widget padding and
icon scaling use widget/asset-specific geometry; canvas styles can express
scientific semantics and belong to their existing owners. Tk display scaling is
reported but not editable: native embed sizing/HiDPI and explicitly sized assets
cannot be proved consistently rescaled by one lifecycle-safe framework control.
No numerical coordinates, plotting colors, scientific Viewers configuration,
rendering, Dataset schema, Session data or export fonts are restyled here.

Popup recovery changes apply after Save immediately. Disable the checkbox and
Save to suppress new notifications, cancel pending timers, and avoid loading the
optional helper on a disabled startup. A library already loaded in a running
process is retained safely; its callback checks policy again before every request.
On the recognized server each map replaces any prior timer for that popup. Unmap
or Destroy cancels it. At execution, mapped existence and enabled/server policy
are checked before the unchanged native complete-root-rectangle XDamage request.
Normal Xorg and non-X11 retain standard Tk behavior with no recovery binding/load.
A missing optional helper/dependency or failed request is diagnosed in Appearance
and does not stop GUI startup. Status distinguishes active, disabled, not applicable
and native helper unavailable. 150 ms is the dev089 tested initial baseline, not
a universal minimum or a guarantee that more delay is better. No invisible-pixel
detection, periodic redraw or server/desktop/infrastructure changes are introduced.

Host APIs `uiAppearanceInitialize`, `uiAppearanceEffective` and
`uiFieldComboboxStatus` live in the existing shared GUI-field owner. They do not
provide scientific/script operations; no Script Bridge counterpart is appropriate.
Configuration remains the sole preference authority. Native2D's existing theme,
TkDefaultFont and scaling layout signatures are unchanged. The native popup C ABI and full-rectangle damage mechanism are unchanged.
The helper now checks XDamage 1.1/XFixes 2.0 at load, failing nonfatally through
the Tcl policy owner if those optional server extensions are unavailable.
