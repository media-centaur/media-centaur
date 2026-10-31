defmodule MediaCentaurWeb.PairingHTML do
  @moduledoc """
  The pairing page's one template (`PairingController`): a glass card in
  the root layout, no shell — the device is not admitted yet. Composed
  from the kit: `input/1` for the two fields, `button/1` for Pair. The
  reason a `POST` failed renders as that field's error. While remote
  players is off (ADR-081) the card is the feature's off state with no
  form: the flag is the host's to set.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Features
  alias MediaCentaurWeb.Components.FeatureOff

  attr :name, :string, required: true, doc: "the device name the form carries, kept across a miss"

  attr :players_on?, :boolean,
    required: true,
    doc: "whether remote players is on (ADR-081); off, the card says so and offers no form"

  attr :reason, :atom,
    required: true,
    values: [nil, :invalid_code, :name_required, :name_too_long],
    doc: "why the last offer failed; nil on first render"

  def pair(assigns) do
    ~H"""
    <main class="page-side-dim-calm flex min-h-[calc(100*var(--pvh))] items-center justify-center p-6">
      <div :if={!@players_on?} class="glass-surface w-full max-w-md rounded-xl p-6">
        <FeatureOff.feature_off id="pairing-off" feature={Features.get(:players)} action?={false}>
          Turn it on under Settings → Feature flags on the computer running Media Centaur, then pair this device.
        </FeatureOff.feature_off>
      </div>
      <div :if={@players_on?} class="glass-surface w-full max-w-md space-y-5 rounded-xl p-6">
        <div class="space-y-1">
          <h1 class="text-xl font-semibold">Pair this device</h1>
          <p class="text-base-content/70">
            On the computer running Media Centaur, open Settings → Players and start pairing. Enter the code it shows, and a name for this device.
          </p>
        </div>
        <.form for={%{}} as={:pairing} action={~p"/pair"} class="space-y-4">
          <.input
            type="text"
            name="pairing[name]"
            label="Device name"
            value={@name}
            errors={name_errors(@reason)}
            maxlength={MediaCentaur.DisplayName.max_length()}
            autocomplete="off"
            placeholder="Living room TV"
          />
          <.input
            type="text"
            name="pairing[code]"
            label="Code"
            value=""
            errors={code_errors(@reason)}
            maxlength="6"
            autocomplete="one-time-code"
            class="w-full input font-mono tracking-widest"
          />
          <.button type="submit" variant="primary">Pair</.button>
        </.form>
      </div>
    </main>
    """
  end

  defp name_errors(:name_required), do: ["Enter a name for this device."]

  defp name_errors(:name_too_long),
    do: ["Keep the name under #{MediaCentaur.DisplayName.max_length() + 1} characters."]

  defp name_errors(_reason), do: []

  defp code_errors(:invalid_code),
    do: ["That code isn't open. Start pairing again in Settings → Players and enter the new code."]

  defp code_errors(_reason), do: []
end
