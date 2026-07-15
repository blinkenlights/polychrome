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

// Keeps a range slider and its companion number input in sync, and mirrors
// number-input edits (typing + spinner arrows) back onto the range so the
// range's phx-change reaches the server. The number input has no name, so
// without this it never updates anything server-side.
function npsParseNumber(raw) {
  const cleaned = String(raw)
    .replace(/^[×x]\s*/, "")
    .trim();
  return Number(cleaned);
}

function npsClamp(num, min, max) {
  return Math.min(Math.max(num, min), max);
}

function npsFormatRaw(value, step) {
  const num = Number(value);
  if (!Number.isFinite(num)) return "";
  const stepNum = Number(step);
  if (Number.isInteger(stepNum) && stepNum >= 1) return String(Math.round(num));
  if (Math.abs(stepNum) >= 0.1) return num.toFixed(1);
  return String(Math.round(num * 100) / 100);
}

function npsSyncNumberFromRange(hook) {
  if (!hook.number) return;
  hook.number.value = npsFormatRaw(hook.range.value, hook.el.dataset.step);
}

function npsSyncRangeFromNumber(hook) {
  if (!hook.range || !hook.number) return;
  let num = npsParseNumber(hook.number.value);
  if (!Number.isFinite(num)) {
    npsSyncNumberFromRange(hook);
    return;
  }
  num = npsClamp(num, Number(hook.el.dataset.min), Number(hook.el.dataset.max));
  hook.range.value = String(num);
  const displayStep =
    Number(hook.numberStep) >= 1 ? hook.numberStep : hook.el.dataset.step;
  hook.number.value = npsFormatRaw(num, displayStep);
  hook.range.dispatchEvent(new Event("input", { bubbles: true }));
  hook.range.dispatchEvent(new Event("change", { bubbles: true }));
}

const NowPlayingSlider = {
  mounted() {
    this.bindElements();
    this.onRangeInput = () => npsSyncNumberFromRange(this);
    this.onNumberInput = () => npsSyncRangeFromNumber(this);
    this.range.addEventListener("input", this.onRangeInput);
    this.number.addEventListener("input", this.onNumberInput);
    this.number.addEventListener("change", this.onNumberInput);
    this.onRangeInput();
  },
  updated() {
    this.bindElements();
    if (!this.range) return;
    this.numberStep =
      this.number?.getAttribute("step") || this.el.dataset.step;
    if (
      document.activeElement === this.range ||
      document.activeElement === this.number
    )
      return;
    this.range.value = this.el.dataset.value;
    npsSyncNumberFromRange(this);
  },
  destroyed() {
    if (this.range && this.onRangeInput) {
      this.range.removeEventListener("input", this.onRangeInput);
    }
    if (this.number && this.onNumberInput) {
      this.number.removeEventListener("input", this.onNumberInput);
      this.number.removeEventListener("change", this.onNumberInput);
    }
  },
  bindElements() {
    this.range = this.el.querySelector('input[type="range"]');
    this.number = this.el.querySelector("[data-number-input]");
    this.numberStep =
      this.number?.getAttribute("step") || this.el.dataset.step;
  },
};

// Drag handle for resizing the embedded simulator preview panel.
//
// Two instances are used:
//   data-direction="vertical"   — horizontal bar below #sim-preview (top layout)
//   data-direction="horizontal" — vertical strip on right edge of #sim-preview (left layout)
//
// CSS (in manager_live.ex) shows/hides each handle based on the current layout.
// #sim-preview carries phx-update="ignore" so LiveView never resets its inline
// style, which means the JS-set dimensions persist across server re-renders.
const SimResize = {
  mounted() {
    const simPreview = document.getElementById("sim-preview");
    const consolePage = document.getElementById("console-page");
    if (!simPreview || !consolePage) return;

    const dir = this.el.dataset.direction || "vertical";
    const STORAGE_KEY =
      dir === "vertical" ? "sim-preview-height" : "sim-preview-width";
    const MIN_PX = dir === "vertical" ? 80 : 120;

    const isLeftLayout = () => consolePage.dataset.simLayout === "left";

    const restoreSize = () => {
      const saved = Number(localStorage.getItem(STORAGE_KEY));
      if (saved > MIN_PX) {
        if (dir === "vertical") {
          simPreview.style.height = saved + "px";
        } else {
          simPreview.style.width = saved + "px";
        }
      }
    };

    // On mount, apply saved size only when this handle's direction is active.
    if (
      (dir === "vertical" && !isLeftLayout()) ||
      (dir === "horizontal" && isLeftLayout())
    ) {
      restoreSize();
    }

    // When the layout toggles, clear the stale dimension and restore the
    // correct one for the new layout. Both hook instances receive this event;
    // each clears the dimension it previously managed.
    this.handleEvent("store-console-sim-layout", ({ layout }) => {
      const nowLeft = layout === "left";
      if (dir === "vertical") {
        simPreview.style.height = "";
        if (!nowLeft) restoreSize();
      } else {
        simPreview.style.width = "";
        if (nowLeft) restoreSize();
      }
    });

    this._onPointerDown = (e) => {
      // Each handle only acts when its layout direction is active.
      if (dir === "vertical" && isLeftLayout()) return;
      if (dir === "horizontal" && !isLeftLayout()) return;

      e.preventDefault();

      if (dir === "vertical") {
        const consoleTop = consolePage.getBoundingClientRect().top;
        const maxPx = window.innerHeight - consoleTop - 80;

        const onMove = (ev) => {
          const h = Math.max(MIN_PX, Math.min(maxPx, ev.clientY - consoleTop));
          simPreview.style.height = h + "px";
        };

        const onUp = () => {
          document.removeEventListener("pointermove", onMove);
          document.removeEventListener("pointerup", onUp);
          const h = parseInt(simPreview.style.height, 10);
          if (h > 0) localStorage.setItem(STORAGE_KEY, String(h));
        };

        document.addEventListener("pointermove", onMove);
        document.addEventListener("pointerup", onUp);
      } else {
        // Horizontal: drag left/right to change the width of #sim-preview.
        const startX = e.clientX;
        const startW = simPreview.getBoundingClientRect().width;
        const maxW = Math.min(window.innerWidth * 0.65, 700);

        const onMove = (ev) => {
          const w = Math.max(MIN_PX, Math.min(maxW, startW + (ev.clientX - startX)));
          simPreview.style.width = w + "px";
        };

        const onUp = () => {
          document.removeEventListener("pointermove", onMove);
          document.removeEventListener("pointerup", onUp);
          const w = parseInt(simPreview.style.width, 10);
          if (w > 0) localStorage.setItem(STORAGE_KEY, String(w));
        };

        document.addEventListener("pointermove", onMove);
        document.addEventListener("pointerup", onUp);
      }
    };

    this.el.addEventListener("pointerdown", this._onPointerDown);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this._onPointerDown);
  },
};

export const Hooks = {
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
  CopyDump: CopyDump,
  ConsoleTheme: ConsoleTheme,
  NowPlayingSlider: NowPlayingSlider,
  RadarManualPointer: RadarManualPointer,
  SimResize: SimResize,
  TopBar,
};
