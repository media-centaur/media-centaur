// ErrorReport — opens a prefilled GitHub issue URL in a new tab.
//
// Listens for `error_reports:open_issue` events pushed by StatusLive and
// opens the URL in a new tab. The hook is attached to a stable element on
// /status (the error summary card).
//
// Expected shape:
//   <div id="error-summary-card" phx-hook="ErrorReport" ...>...</div>
//
// LiveView pushes: {url: "https://github.com/..."}

export const ErrorReport = {
  mounted() {
    this.handleEvent("error_reports:open_issue", ({url}) => {
      window.open(url, "_blank", "noopener")
    })
  }
}
