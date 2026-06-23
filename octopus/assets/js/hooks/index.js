import PixelsHook from "./pixels";
import ProximityChartHook from "./proximity_chart";
import { CodeEditorHook } from "../../../deps/live_monaco_editor/priv/static/live_monaco_editor.esm";

// Copies the text in the button's data-dump attribute to the clipboard.
// The copy runs synchronously inside the click handler so the browser's
// transient user activation is still valid (clipboard writes fail otherwise).
// A fire-and-forget event is also pushed so the server logs the dump.
const CopyDump = {
  mounted() {
    this.el.addEventListener("click", () => {
      const btn = this.el;
      copyText(btn.dataset.dump || "").then(
        () => flash(btn, "✓ Copied!"),
        () => flash(btn, "✗ Failed"),
      );

      const snapId = btn.dataset.snapId;
      this.pushEvent("copy_dump", snapId ? { snap_id: snapId } : {});
    });
  },
};

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text);
  }

  return new Promise((resolve, reject) => {
    const el = document.createElement("textarea");
    el.value = text;
    el.style.cssText = "position:fixed;top:0;left:0;opacity:0";
    document.body.appendChild(el);
    el.focus();
    el.select();
    let ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (_) {}
    document.body.removeChild(el);
    ok ? resolve() : reject();
  });
}

function flash(btn, message) {
  const original = btn.textContent;
  btn.textContent = message;
  setTimeout(() => {
    btn.textContent = original;
  }, 2000);
}

export const Hooks = {
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
  CopyDump: CopyDump,
};
