defmodule MediaCentaur.Acquisition.ViewModels.RejectionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.Rejection

  describe "label/1" do
    test "every reason an assessment can give has words" do
      for reason <- [:red_flag, :excluded, :identity, :published_early, :quality] do
        assert is_binary(Rejection.label(reason))
      end
    end
  end

  describe "summary/1" do
    test "nothing left out says nothing" do
      assert Rejection.summary([]) == nil
    end

    test "one reason reads as one sentence, singular or plural" do
      assert Rejection.summary(identity: 1) ==
               "1 other release was found and left out: it didn't match this title."

      assert Rejection.summary(identity: 3) ==
               "3 other releases were found and left out: they didn't match this title."
    end

    test "several reasons are counted each, in the order given" do
      assert Rejection.summary(excluded: 1, identity: 9, published_early: 2) ==
               "12 other releases were found and left out: 1 you already tried, " <>
                 "9 didn't match this title, 2 posted before it was released."
    end
  end
end
