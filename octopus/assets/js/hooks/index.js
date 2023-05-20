import * as pixels from "./pixels";

export const Hooks = {
  Pixels: {
    mounted() {
      pixels.setup.bind(this)(this.el);
    },
  },
};
