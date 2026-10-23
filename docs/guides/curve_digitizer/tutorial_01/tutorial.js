"use strict";
// Reader-owned reading reminders only. No application calls or scientific state.
(() => {
  const key = "gx210-reading:" + document.title;
  let marks = {};
  try { marks = JSON.parse(localStorage.getItem(key) || "{}"); } catch (_) {}
  if (!marks || typeof marks !== "object" || Array.isArray(marks)) marks = {};
  const status = document.getElementById("reading-status");
  const buttons = [];
  function render() {
    buttons.forEach(([id, button]) => {
      button.textContent = marks[id] ? "Read — clear reminder" : "Mark this step as read";
      button.setAttribute("aria-pressed", marks[id] ? "true" : "false");
    });
    if (status) status.textContent = "Reading reminders only; all actual execution outcomes are recorded separately in step-outcomes.json.";
    try { localStorage.setItem(key, JSON.stringify(marks)); } catch (_) {}
  }
  document.querySelectorAll("section[data-step]").forEach(section => {
    const id = section.dataset.step;
    const button = document.createElement("button");
    button.type = "button"; button.className = "read-button";
    button.setAttribute("aria-label", "Reading reminder for step " + id);
    button.addEventListener("click", () => { marks[id] = !marks[id]; render(); });
    section.append(button); buttons.push([id, button]);
  });
  const reset = document.getElementById("reset-reading");
  if (reset) reset.addEventListener("click", () => { marks = {}; render(); });
  render();
})();
