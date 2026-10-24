# GUI_UPDATE_SCHEDULER_API_v1

Opt-in, trusted Tcl/Tk host API introduced in DEV111-P012. Loaded by the normal
CORE bootstrap and discoverable through `workbenchExtensionCoreApis` /
`workbenchExtensionRequireApi`. `::GX::guiUpdateSchedulerApiInfo` describes it.
Sourcing the implementation does not load Tk; creating an instance requires Tk.
No Native2D, Plot, Dataset, Session or input-device dependency exists.

The caller processes every accepted input and updates its authoritative model
immediately. CORE schedules a no-argument Tcl command prefix that presents the
**latest** caller-owned state. Requests carry no model snapshots or device events.
Use separate instances for independent components; this is not a transaction or
scientific computation service. Adoption changes no other Viewer.

## Operations

All commands below belong to `::GX`.

| Operation | Contract |
|---|---|
| `guiUpdateSchedulerApiInfo` | Return public API identification and operations. |
| `guiUpdateSchedulerCreate owner callback ?options?` | Existing Tk widget, no-argument update command prefix, optional options dictionary. Return unique opaque handle. Capture owner incarnation and attach a private Destroy bindtag. |
| `guiUpdateSchedulerConfigure handle options` | Validate/merge dictionary, end adaptation and reschedule pending work using the new policy; return resulting options. |
| `guiUpdateSchedulerRequest handle ?activity?` | Mark latest state pending; return 1, or 0 if the owner/guard invalidates the instance. Hint is `auto` (default), `normal`, or `intensive`. |
| `guiUpdateSchedulerFlush handle` | Present pending state now, without ending adaptation; return 1 if work was pending, otherwise 0. Explicitly bypasses the cadence. |
| `guiUpdateSchedulerFinish handle` | End intensive activity, clear its observation window, restore normal policy, flush pending final state. Same return convention as Flush. |
| `guiUpdateSchedulerCancel handle` | Discard pending requests and activity timers, restore normal mode, keep instance. Idempotent for disposed handles. |
| `guiUpdateSchedulerDispose handle` | Cancel timers, remove bindtag and release retained callbacks/owner. Idempotent. |
| `guiUpdateSchedulerDescribe handle` | Diagnostic dictionary: owner, config, pending/running/force, mode, last_update (elapsed-clock milliseconds), requests, updates (attempts), failures, mode_changes, last_error. No scientific state. |

Except Cancel/Dispose, an unknown/disposed handle is an error. A guard failure
invalidates and disposes the instance; the caller should clear its retained handle
when its context changes. Owner-widget destruction disposes automatically.

## Options and timing

| Key | Default | Meaning |
|---|---:|---|
| `policy` | `coalesced` | `coalesced` or `adaptive`. Default never reduces frequency. |
| `normal_ms` | 16 | Delay from first pending request. Later requests share that frame. |
| `adaptive_ms` | 100 | Minimum intended callback-start interval in reduced mode, at least normal_ms. This is configurable per component, not a global frame rate. |
| `activity_window_ms` | 80 | Rolling observation window for request activity. |
| `rapid_count` | 8 | Requests within that window needed to enter reduced mode, 2..512. |
| `quiet_ms` | 80 | Time since last **qualifying intensive activity** before ending adaptation. Slowing activity also recovers; ordinary requests do not perpetually extend reduced mode. |
| `guard` | empty | Optional no-argument prefix returning a boolean. False, invalid boolean or failure disposes the instance before dispatch. Pure validity checks only. |
| `error_callback` | empty | Optional prefix receiving `handle message options` for update errors. Otherwise Tcl/Tk receives the original error, including for synchronous Flush. |

Timing values accept integer milliseconds 1..60000. Options are Tcl dictionaries,
not dash-prefixed Tk options. Invalid options change nothing.

In adaptive policy `auto` measures generic request arrivals. `intensive` lets an
owner declare activity without a device-specific representation; it is ignored
by coalesced policy. `normal` resets activity and requests a normal frame.
Entering reduced mode moves an already queued normal frame to the reduced-mode
deadline. Subsequent requests do not debounce that frame indefinitely. The first
frame of a new instance has no previous start to limit. Long rendering/event-loop
work may delay callbacks; this API is not a real-time deadline guarantee.

An event-driven quiet timer restores normal mode and synchronizes a pending final
state immediately, without waiting for another input. That final synchronization
(and explicit Flush/Finish) may be sooner than adaptive_ms after a previous frame.
Automatic final synchronization occurs **after leaving reduced mode**. There is
one frame timer and, while adaptation is active, one activity-settlement timer.
No polling or background Tk thread is used.

A callback may request another update: the dirty flag is cleared before dispatch
and a new request schedules a later callback. Flush/Finish from inside a running
callback never invokes it recursively. A callback may dispose its instance.
An update failure clears pending work and adaptation, records the failure and
releases the running flag; subsequent requests remain possible. It does not
retry the failed rendering or alter scientific state.

## Generic adoption

```tcl
# Viewer/component has already created its widget and owns its state and renderer.
set scheduler [::GX::guiUpdateSchedulerCreate $frame \
    [list ::MyViewer::presentLatest $view] \
    [dict create policy adaptive normal_ms 12 adaptive_ms 40 \
        activity_window_ms 60 rapid_count 6 quiet_ms 70 \
        guard [list ::MyViewer::contextStillCurrent $view $revision]]]

# Any repeated interaction: update the model through its existing owner first.
::MyViewer::applyAcceptedChange $view $change
::GX::guiUpdateSchedulerRequest $scheduler

# Optional explicit interaction boundary; otherwise activity settles automatically.
::GX::guiUpdateSchedulerFinish $scheduler
# On document/session replacement, use the caller's existing lifecycle notification.
::GX::guiUpdateSchedulerDispose $scheduler
```

The callback takes no extra arguments: capture the required owner in its command
prefix. Do not pass stale geometry snapshots as callback state. Keep rendering
bounded and avoid nested `update` event loops in callbacks. On Session or model
replacement the caller disposes/cancels through its existing lifecycle and can
supply a revision guard; CORE does not interpret Session structures. Multiple
instances may share an owner widget without sharing timing or pending state.

## First production integration: Curve Workbench

Only wheel redraw requests opt in. Each accepted wheel event still executes the
original immediate Native2D zoom, with unchanged factor and cursor position.
Normal requests retain 16ms scheduling; eight requests within 80ms identify unusually
rapid activity, then reduced frames use 100ms spacing (maximum intended 10/s).
The threshold distinguishes the measured ordinary 85–90ms input from measured
rapid approximately 4ms input. These are component policy values, not input
semantics in CORE. The existing 350ms persistence debounce is unchanged.

Normal drag/pan/selection requests retain their existing local 16ms scheduling.
A pending frame is transferred when switching between wheel and normal owners:
the previous queue is cancelled, the latest state belongs to the new queue. They
never hold competing pending redraws. Transform rendering stays under its existing
owner. Session invalidation and normal close explicitly dispose the scheduler;
Canvas destruction and the existing window/Session guard provide fallback cleanup.
Other production Viewers and public scientific APIs are unchanged.

Limits: callbacks run serially in the GUI loop; expensive rendering cannot be
preempted. Requests coalesce presentations, not accepted scientific operations.
Only wheel zoom is integrated in P012; future consumers choose their own policies.

## DEV111-P014 CORE performance profiles

Create/Configure additionally accepts `profile custom|global`. Default `custom`
retains the original independent `adaptive_ms` contract. `global` subscribes the
instance to the persistent CORE Appearance choice `ui.graphics_profile`:
Low(default)=200ms/5FPS, Medium=100ms/10FPS, Fast=50ms/20FPS during intensive mode.
`guiUpdateSchedulerGraphicsPolicy` returns `{profile NAME adaptive_ms INTERVAL}`.
Each instance retains its own pending state and activity thresholds. Its normal
interval remains authoritative if longer than the chosen global limit.

Settings change live after Save without changing model state. Dispose removes
the Configuration subscription. Reduced deadlines now use the microsecond
callback-admission timestamp and upward rounding to Tk's millisecond timer,
avoiding a frame arriving early because the previous timestamp was truncated.
Describe also exposes `last_update_us`; `last_update` remains milliseconds.
Normal coalescing and automatic/explicit final synchronization retain their
existing semantics. Final synchronization occurs after leaving reduced mode and
may be sooner than the intensive interval, as before.

Workbench2.21.13 is the first global-profile consumer for viewport wheel, pan,
resize and shared viewport-control updates. Every accepted scientific input is
still processed by its original owner. Pan release finishes pending presentation;
semantic point/geometry interactions retain their original scheduling. The
retained Native2D Cairo presenter is a separate optional CORE host facility,
`NATIVE2D_GRID_PRESENTER_API_v1`; no Native2D dependency enters this scheduler.
