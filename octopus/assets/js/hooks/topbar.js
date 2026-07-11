export function currentTheme() {
  const consoleTheme = localStorage.getItem("console-theme");
  if (consoleTheme === "light" || consoleTheme === "dark") return consoleTheme;

  const theme = localStorage.getItem("theme");
  if (theme === "light" || theme === "dark") return theme;

  const htmlTheme = document.documentElement.getAttribute("data-theme");
  return htmlTheme === "dark" ? "dark" : "light";
}

export function applyTheme(theme) {
  if (theme !== "light" && theme !== "dark") return;

  document.documentElement.setAttribute("data-theme", theme);
  localStorage.setItem("theme", theme);
  localStorage.setItem("console-theme", theme);

  const consoleInner = document.querySelector("#console-page [data-theme]");
  if (consoleInner) consoleInner.setAttribute("data-theme", theme);
}

export function themeIcon(theme) {
  return theme === "dark" ? "☀" : "☾";
}

export const TopBar = {
  mounted() {
    applyTheme(currentTheme());
    this.syncThemeIcon();
    this.syncSimLayoutIcon();

    this.el.addEventListener("click", (event) => {
      const button = event.target.closest("[data-action]");
      if (!button || !this.el.contains(button)) return;

      if (button.dataset.action === "toggle-theme") {
        event.preventDefault();
        const next = currentTheme() === "dark" ? "light" : "dark";
        applyTheme(next);
        this.syncThemeIcon();

        if (this.el.dataset.foyer === "true") {
          this.pushEvent("set_console_theme", { theme: next });
        }
      }

      if (button.dataset.action === "toggle-sim-layout") {
        event.preventDefault();
        if (this.el.dataset.foyer === "true") {
          this.pushEvent("toggle_sim_layout", {});
        }
      }
    });
  },

  updated() {
    this.syncThemeIcon();
    this.syncSimLayoutIcon();
  },

  syncThemeIcon() {
    const icon = this.el.querySelector("[data-theme-icon]");
    if (icon) icon.textContent = themeIcon(currentTheme());
  },

  syncSimLayoutIcon() {
    const page = document.getElementById("console-page");
    const icon = this.el.querySelector("[data-sim-layout-icon]");
    if (!page || !icon) return;
    icon.textContent = page.dataset.simLayout === "left" ? "↑" : "←";
  },
};
