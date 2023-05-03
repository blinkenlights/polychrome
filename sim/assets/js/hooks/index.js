import * as pixels from "./pixels.js";

export const Hooks = {
  Pixels: {
    mounted() {
      const pixelImageUrl = this.el.dataset.pixelImageUrl;
      pixels.setup.bind(this)(this.el, pixelImageUrl);
    },
  },
};
