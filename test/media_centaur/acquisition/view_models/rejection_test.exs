defmodule MediaCentaur.Acquisition.ViewModels.RejectionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.Rejection

  describe "label/1" do
    test "every reason an assessment can give has words" do
      for reason <- MediaCentaur.Search.Assessment.reasons() do
        assert is_binary(Rejection.label(reason))
        assert is_binary(Rejection.summary([{reason, 1}]))
        assert is_binary(Rejection.summary([{reason, 2}]))
        assert is_binary(Rejection.breakdown([{reason, 2}, {:red_flag, 1}]))
      end
    end
  end

  describe "breakdown/1" do
    test "nothing rejected says nothing" do
      assert Rejection.breakdown([]) == nil
    end

    test "counts each reason, in the order given" do
      assert Rejection.breakdown(identity: 9, coverage: 3, red_flag: 1) ==
               "9 didn't match this title, 3 had other episodes, 1 flagged suspicious."
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
