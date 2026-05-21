defmodule MediaCentarr.Playback.LanguagePolicyTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Playback.LanguagePolicy
  alias MediaCentarr.Settings

  describe "defaults/0" do
    test "returns built-in defaults that match the documented policy" do
      defaults = LanguagePolicy.defaults()

      assert defaults.understood_languages == ["eng"]
      assert defaults.audio_priority == ["original", "understood", "any"]
      assert defaults.subtitles_when == "when_audio_not_understood"
      assert defaults.subtitles_language == "understood"
      assert defaults.subtitles_variant == "standard"
      assert defaults.forced_subs == "fill_gaps"
    end
  end

  describe "load/0" do
    test "returns built-in defaults when no Settings entry exists" do
      assert LanguagePolicy.load() == LanguagePolicy.defaults()
    end

    test "returns the persisted policy when a Settings entry exists" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LanguagePolicy.settings_key(),
          value: %{
            "understood_languages" => ["eng", "spa", "fra"],
            "audio_priority" => ["understood", "original", "any"],
            "subtitles_when" => "always",
            "subtitles_language" => "audio_language",
            "subtitles_variant" => "sdh_preferred",
            "forced_subs" => "never"
          }
        })

      policy = LanguagePolicy.load()

      assert policy.understood_languages == ["eng", "spa", "fra"]
      assert policy.audio_priority == ["understood", "original", "any"]
      assert policy.subtitles_when == "always"
      assert policy.subtitles_language == "audio_language"
      assert policy.subtitles_variant == "sdh_preferred"
      assert policy.forced_subs == "never"
    end

    test "falls back to per-field defaults for keys missing from a partial Settings value" do
      # User has saved a partial policy — only changed understood_languages.
      # Missing fields must fall back to the defaults so the policy is always
      # complete and the resolver never has to handle nil/absent fields.
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LanguagePolicy.settings_key(),
          value: %{"understood_languages" => ["spa"]}
        })

      policy = LanguagePolicy.load()

      assert policy.understood_languages == ["spa"]
      assert policy.audio_priority == ["original", "understood", "any"]
      assert policy.subtitles_when == "when_audio_not_understood"
      assert policy.forced_subs == "fill_gaps"
    end

    test "ignores invalid value types (non-string in lists, non-string scalars)" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LanguagePolicy.settings_key(),
          value: %{
            "understood_languages" => ["eng", 42, nil, "spa"],
            "subtitles_when" => 123
          }
        })

      policy = LanguagePolicy.load()

      assert policy.understood_languages == ["eng", "spa"]
      assert policy.subtitles_when == "when_audio_not_understood"
    end
  end

  describe "save/1" do
    test "persists a %LanguagePolicy{} as a Settings entry" do
      policy = %LanguagePolicy{
        understood_languages: ["eng", "spa"],
        audio_priority: ["original", "understood", "any"],
        subtitles_when: "always",
        subtitles_language: "understood",
        subtitles_variant: "standard",
        forced_subs: "fill_gaps"
      }

      assert {:ok, _entry} = LanguagePolicy.save(policy)
      assert LanguagePolicy.load() == policy
    end

    test "accepts a plain string-keyed map (as produced by a form submit)" do
      attrs = %{
        "understood_languages" => ["spa"],
        "audio_priority" => ["understood", "original", "any"],
        "subtitles_when" => "off",
        "subtitles_language" => "understood",
        "subtitles_variant" => "standard",
        "forced_subs" => "never"
      }

      assert {:ok, _} = LanguagePolicy.save(attrs)

      reloaded = LanguagePolicy.load()
      assert reloaded.understood_languages == ["spa"]
      assert reloaded.subtitles_when == "off"
    end

    test "broadcasts a :setting_changed event on the settings_updates topic" do
      :ok = Settings.subscribe()

      assert {:ok, _} = LanguagePolicy.save(LanguagePolicy.defaults())

      assert_receive {:setting_changed, "playback.tracks", value} when is_map(value)
    end

    test "updates the existing entry in place across multiple saves" do
      {:ok, _} = LanguagePolicy.save(LanguagePolicy.defaults())
      {:ok, _} = LanguagePolicy.save(%LanguagePolicy{understood_languages: ["spa"]})

      assert Repo.aggregate(Settings.Entry, :count) == 1
      assert LanguagePolicy.load().understood_languages == ["spa"]
    end
  end

  describe "to_map/1 and default_map/0" do
    test "default_map/0 returns the string-keyed default shape" do
      assert LanguagePolicy.default_map() == %{
               "understood_languages" => ["eng"],
               "audio_priority" => ["original", "understood", "any"],
               "subtitles_when" => "when_audio_not_understood",
               "subtitles_language" => "understood",
               "subtitles_variant" => "standard",
               "forced_subs" => "fill_gaps"
             }
    end

    test "to_map/1 round-trips through from_map (via save + load)" do
      policy = %LanguagePolicy{
        understood_languages: ["jpn", "eng"],
        audio_priority: ["any", "original", "understood"],
        subtitles_when: "always",
        subtitles_language: "audio_language",
        subtitles_variant: "sdh_preferred",
        forced_subs: "always"
      }

      {:ok, _} = LanguagePolicy.save(policy)
      assert LanguagePolicy.load() == policy
    end
  end
end
