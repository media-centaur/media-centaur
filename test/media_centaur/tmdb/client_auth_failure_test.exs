defmodule MediaCentaur.TMDB.ClientAuthFailureTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Client

  describe "auth_failure?/1" do
    test "401 and 403 are the rejected-key statuses" do
      assert Client.auth_failure?({:http_error, 401, %{}})
      assert Client.auth_failure?({:http_error, 403, %{}})
    end

    test "anything else is not" do
      refute Client.auth_failure?({:http_error, 500, %{}})
      refute Client.auth_failure?(:timeout)
    end
  end
end
