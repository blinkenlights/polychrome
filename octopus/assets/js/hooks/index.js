import PixelsHook from "./pixels";
import ProximityChartHook from "./proximity_chart";
import { TopBar } from "./topbar";
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

// Cursor-driven mock object placement for the radar view. While active
// (data-active="true"), pointer motion over the radar SVG is reported to the
// server as viewBox coordinates (0..1000), which the LiveView maps into world
// meters to drive a single tracked object. Updates are throttled to keep the
// message rate modest, with a trailing send so the final position isn't lost.
const RadarManualPointer = {
  mounted() {
    this._pending = null;
    this._lastSent = 0;
    this._timer = null;

    this._flush = () => {
      this._timer = null;
      if (!this._pending) return;
      this._lastSent = performance.now();
      this.pushEvent("manual_point", this._pending);
      this._pending = null;
    };

    this._move = (e) => {
      if (this.el.dataset.active !== "true") return;
      const rect = this.el.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return;

      const x = ((e.clientX - rect.left) / rect.width) * 1000;
      const y = ((e.clientY - rect.top) / rect.height) * 1000;
      this._pending = {
        x: Math.max(0, Math.min(1000, x)),
        y: Math.max(0, Math.min(1000, y)),
      };

      const elapsed = performance.now() - this._lastSent;
      if (elapsed >= 40) {
        this._flush();
      } else if (this._timer === null) {
        this._timer = setTimeout(this._flush, 40 - elapsed);
      }
    };

    this._leave = () => {
      if (this.el.dataset.active !== "true") return;
      if (this._timer !== null) {
        clearTimeout(this._timer);
        this._timer = null;
      }
      this._pending = null;
      this.pushEvent("manual_clear", {});
    };

    this.el.addEventListener("pointermove", this._move);
    this.el.addEventListener("pointerleave", this._leave);
  },

  destroyed() {
    this.el.removeEventListener("pointermove", this._move);
    this.el.removeEventListener("pointerleave", this._leave);
    if (this._timer !== null) clearTimeout(this._timer);
  },
};

const ConsoleTheme = {
  mounted() {
    const saved = localStorage.getItem("console-theme");
    if (saved === "light" || saved === "dark") {
      this.pushEvent("set_console_theme", { theme: saved });
    }

    const savedLayout = localStorage.getItem("console-sim-layout");
    if (savedLayout === "top" || savedLayout === "left") {
      this.pushEvent("set_sim_layout", { layout: savedLayout });
    }

    this.handleEvent("store-console-theme", ({ theme }) => {
      localStorage.setItem("console-theme", theme);
    });

    this.handleEvent("store-console-sim-layout", ({ layout }) => {
      localStorage.setItem("console-sim-layout", layout);
    });

    this.syncScrollLock();
  },

  updated() {
    this.syncScrollLock();
  },

  destroyed() {
    this.unlockScroll();
  },

  syncScrollLock() {
    if (this.el.dataset.simPreview === "true") {
      document.documentElement.classList.add("overflow-hidden");
      document.body.classList.add("overflow-hidden");
    } else {
      this.unlockScroll();
    }
  },

  unlockScroll() {
    document.documentElement.classList.remove("overflow-hidden");
    document.body.classList.remove("overflow-hidden");
  },
};

export const Hooks = {
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
  CopyDump: CopyDump,
  ConsoleTheme: ConsoleTheme,
  RadarManualPointer: RadarManualPointer,
  TopBar,
};
