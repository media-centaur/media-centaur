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
  ],
}
