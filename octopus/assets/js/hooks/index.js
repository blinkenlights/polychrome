import Pixels3dHook from "./pixels3d";
import Pixels3dAframeHook from "./pixels3d_aframe";
import PixelsHook from "./pixels";
import ProximityChartHook from "./proximity_chart";
import { CodeEditorHook } from "../../../deps/live_monaco_editor/priv/static/live_monaco_editor.esm";

export const Hooks = {
  Pixels3d: Pixels3dHook,
  Pixels3dAframe: Pixels3dAframeHook,
  Pixels: PixelsHook,
  ProximityChart: ProximityChartHook,
  CodeEditorHook: CodeEditorHook,
};
