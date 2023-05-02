import * as pixels from "./pixels.js";

export const Hooks = {
  Pixels: {
    mounted() {
      pixels.setup.bind(this)(this.el);
    },
  },
};
