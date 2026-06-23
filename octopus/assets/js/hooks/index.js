import Pixels3dHook from "./pixels3d";
import Pixels3dAframeHook from "./pixels3daframe";
import PixelsHook from "./pixels";
import ProximityChartHook from "./proximity_chart";
import { CodeEditorHook } from "../../../deps/live_monaco_editor/priv/static/live_monaco_editor.esm";

const ClipboardCopy = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text }) => {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).catch(() => execCommandFallback(text));
      } else {
        execCommandFallback(text);
      }
    });
  }
};

function execCommandFallback(text) {
  const el = document.createElement("textarea");
  el.value = text;
  el.style.position = "fixed";
  el.style.opacity = "0";
  document.body.appendChild(el);
  el.focus();
  el.select();
  try { document.execCommand("copy"); } catch (_) {}
  document.body.removeChild(el);
}

export const Hooks = {
  Pixels3d: Pixels3dHook,
  Pixels3dAframe: Pixels3dAframeHook,
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
  ClipboardCopy: ClipboardCopy,
};
