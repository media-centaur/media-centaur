/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "core-no-app-imports",
      comment: "Framework core must not import from the app layer",
      severity: "error",
      from: {
        path: "^assets/js/input/core",
        pathNot: "__tests__",
      },
      to: {
        path: "^assets/js/input/(?!core)",
      },
    },
    {
      name: "no-unreachable-from-app",
      comment:
        "Dead JS: a module no longer reached from the app.js entry point. " +
        "`no-orphans` cannot see this — a module's own test imports it, so it " +
        "is never orphaned. Reachability is what catches a hook whose last " +
        "registration was deleted (assets/js/hooks/console.js, v1.32.0). " +
        "Delete the module, or wire it back up.",
      severity: "error",
      from: { path: "^assets/js/app\\.js$" },
      to: {
        path: "^assets/js/",
        pathNot: "(__tests__|test_support|\\.test\\.js$)",
        reachable: false,
      },
    },
  ],
}
