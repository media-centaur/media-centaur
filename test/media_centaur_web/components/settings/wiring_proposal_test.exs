defmodule MediaCentaurWeb.Components.Settings.WiringProposalTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Settings.WiringProposal

  describe "change_summary/1" do
    test "names each changed field in the reader's words" do
      assert WiringProposal.change_summary([:prowlarr_url, :prowlarr_api_key]) ==
               "Changes: address, API key"

      assert WiringProposal.change_summary([
               :download_client_type,
               :download_client_username,
               :download_client_password
             ]) == "Changes: client, username, password"
    end
  end

  describe "error_message/1" do
    test "an unknown format names the format and says nothing changed" do
      message = WiringProposal.error_message({:unknown_format, 2})

      assert message =~ "format 2"
      assert message =~ "Nothing was changed"
    end

    test "every reason the reader can meet has a sentence" do
      for reason <- [
            :malformed,
            {:unsupported_client, "otherclient"},
            :writable_by_others,
            {:unreadable, :eacces}
          ] do
        assert WiringProposal.error_message(reason) =~ "prowlarr-stack"
      end
    end
  end
end
