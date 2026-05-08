defmodule MediaCentarr.Acquisition.CancelReasons do
  @moduledoc """
  The closed set of strings stored in `acquisition_grabs.cancelled_reason`
  and surfaced in pursuit timeline events.

  Inline string literals at call sites drift — different pages have used
  different reasons for the same action ("user_disabled" vs "user_request"
  for a manual cancel). This module is the single source of truth.

  | constant            | meaning                                                |
  |---------------------|--------------------------------------------------------|
  | `user_disabled`     | user clicked cancel on the activity row                |
  | `user_request`      | user clicked cancel on the pursuit detail page         |
  | `item_removed`      | the tracked item was untracked from release tracking   |
  | `in_library`        | the file already arrived (release became `in_library`) |
  | `identity_mismatch` | the arrived file did not match the pursuit's grab      |
  | `abandoned`         | max snooze attempts reached without a grab             |
  | `zero_seeders`      | sustained zero-seeders signal confirmed                |
  | `stall`             | sustained stall signal confirmed                       |
  """

  @user_disabled "user_disabled"
  @user_request "user_request"
  @item_removed "item_removed"
  @in_library "in_library"
  @identity_mismatch "identity_mismatch"
  @abandoned "abandoned"
  @zero_seeders "zero_seeders"
  @stall "stall"

  @all [
    @user_disabled,
    @user_request,
    @item_removed,
    @in_library,
    @identity_mismatch,
    @abandoned,
    @zero_seeders,
    @stall
  ]

  @type t :: String.t()

  @spec user_disabled() :: t()
  def user_disabled, do: @user_disabled

  @spec user_request() :: t()
  def user_request, do: @user_request

  @spec item_removed() :: t()
  def item_removed, do: @item_removed

  @spec in_library() :: t()
  def in_library, do: @in_library

  @spec identity_mismatch() :: t()
  def identity_mismatch, do: @identity_mismatch

  @spec abandoned() :: t()
  def abandoned, do: @abandoned

  @spec zero_seeders() :: t()
  def zero_seeders, do: @zero_seeders

  @spec stall() :: t()
  def stall, do: @stall

  @doc "Returns every recognised cancel reason string."
  @spec all() :: [t()]
  def all, do: @all

  @doc "True when `value` is one of the recognised reasons."
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @all
end
