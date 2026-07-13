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

export const Hooks = {
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
  CopyDump: CopyDump,
  ConsoleTheme: ConsoleTheme,
  RadarManualPointer: RadarManualPointer,
  TopBar,
};
