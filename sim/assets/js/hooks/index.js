import * as pixels from "./pixels.js";

export const Hooks = {
  Pixels: {
    mounted() {
      const pixelImageUrl = this.el.dataset.pixelImageUrl;
      const id = this.el.id;
      pixels.setup.bind(this)(id, this.el, pixelImageUrl);
    },
  },
};
