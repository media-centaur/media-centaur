defmodule MediaCentaur.Acquisition.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.IncidentContext

  @client_fault {:fault, :download_client_unreachable, :warning, %{}}
  @client_auth_fault {:fault, :download_client_auth_failed, :error, %{}}
  @search_fault {:fault, :search_indexers_unavailable, :warning, %{}}

  describe "worst/1" do
    test "all healthy is :ok" do
      assert IncidentContext.worst([:ok, :ok]) == :ok
    end

    test "a single fault wins over :ok" do
      assert IncidentContext.worst([:ok, @search_fault]) == @search_fault
      assert IncidentContext.worst([@client_fault, :ok]) == @client_fault
    end

    test "an error outranks a warning regardless of order" do
      assert IncidentContext.worst([@client_fault, @client_auth_fault]) == @client_auth_fault
      assert IncidentContext.worst([@client_auth_fault, @search_fault]) == @client_auth_fault
    end

    test "equal severity keeps the first probe's fault" do
      assert IncidentContext.worst([@client_fault, @search_fault]) == @client_fault
    end
  end
end
