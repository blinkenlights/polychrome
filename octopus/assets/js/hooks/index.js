import * as pixels from "./pixels";
import { CodeEditorHook } from "../../../deps/live_monaco_editor/priv/static/live_monaco_editor.esm"

export const Hooks = {
  Pixels: {
    mounted() {
      pixels.setup.bind(this)(this.el);
    },
  },
  CodeEditorHook: CodeEditorHook

};
