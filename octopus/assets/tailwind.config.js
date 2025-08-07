// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: ["./js/**/*.js", "../lib/*_web.ex", "../lib/*_web/**/*.*ex"],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/typography"),
    require("daisyui"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ])
    ),
  ],
  // daisyUI config (optional - has a default config)
  daisyui: {
    themes: [
      {
        light: {
          "primary": "#FD4F00",
          "primary-focus": "#E5450B",
          "primary-content": "#FFFFFF",
          "secondary": "#6366F1",
          "secondary-focus": "#4F46E5",
          "secondary-content": "#FFFFFF",
          "accent": "#37CDBE",
          "neutral": "#3D4451",
          "base-100": "#FFFFFF",
          "base-200": "#F2F2F2",
          "base-300": "#E5E6E6",
          "base-content": "#1F2937",
        },
        dark: {
          "primary": "#FD4F00",
          "primary-focus": "#E5450B",
          "primary-content": "#FFFFFF",
          "secondary": "#6366F1",
          "secondary-focus": "#4F46E5",
          "secondary-content": "#FFFFFF",
          "accent": "#37CDBE",
          "neutral": "#191D24",
          "base-100": "#1F2937",
          "base-200": "#191D24",
          "base-300": "#15191E",
          "base-content": "#F3F4F6",
        },
      },
    ],
    base: true,
    styled: true,
    utils: true,
    prefix: "",
    logs: true,
    themeRoot: ":root",
  },
};
