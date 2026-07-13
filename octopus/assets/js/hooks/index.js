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
  NowPlayingSlider: NowPlayingSlider,
  TopBar,
};
