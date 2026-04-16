defmodule MediaCentarr.Pipeline.ImageProcessorTest do
  @moduledoc """
  Unit tests for ImageProcessor — pure-function download + resize module.

  Uses `Image.new!/2` to generate test images in memory, then verifies
  resize behavior, format detection, skip-if-small logic, and error handling.
  """
  use ExUnit.Case, async: true

  alias MediaCentarr.Pipeline.ImageProcessor

  @moduletag :tmp_dir

  # ---------------------------------------------------------------------------
  # output_extension/1
  # ---------------------------------------------------------------------------

  describe "output_extension/1" do
    test "logos use png" do
      assert ImageProcessor.output_extension("logo") == "png"
    end

    test "posters use jpg" do
      assert ImageProcessor.output_extension("poster") == "jpg"
    end

    test "backdrops use jpg" do
      assert ImageProcessor.output_extension("backdrop") == "jpg"
    end

    test "thumbs use jpg" do
      assert ImageProcessor.output_extension("thumb") == "jpg"
    end
  end

  # ---------------------------------------------------------------------------
  # download_and_resize/3 with stubbed HTTP
  # ---------------------------------------------------------------------------

  describe "download_and_resize/3" do
    setup %{tmp_dir: tmp_dir} do
      # Generate a large test image (2000x3000) as JPEG binary
      {:ok, large_image} = Image.new(2000, 3000, color: :red)
      {:ok, large_jpeg} = Image.write(large_image, :memory, suffix: ".jpg")

      # Generate a small test image (100x100) as JPEG binary
      {:ok, small_image} = Image.new(100, 100, color: :blue)
      {:ok, small_jpeg} = Image.write(small_image, :memory, suffix: ".jpg")

      # Generate a large PNG for logo tests (2000x1000)
      {:ok, large_logo} = Image.new(2000, 1000, color: :green)
      {:ok, large_png} = Image.write(large_logo, :memory, suffix: ".png")

      %{
        tmp_dir: tmp_dir,
        large_jpeg: large_jpeg,
        small_jpeg: small_jpeg,
        large_png: large_png
      }
    end

    test "resizes a large poster to spec", %{tmp_dir: tmp_dir, large_jpeg: jpeg} do
      stub_http_success(jpeg)

      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert :ok =
               ImageProcessor.download_and_resize(
                 "https://example.com/poster.jpg",
                 "poster",
                 dest
               )

      assert File.exists?(dest)
      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      # 2000x3000 poster should be resized to fit within 1120x1680
      assert width <= 1120
      assert height <= 1680
    end

    test "skips resize for images already within target", %{tmp_dir: tmp_dir, small_jpeg: jpeg} do
      stub_http_success(jpeg)

      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert :ok =
               ImageProcessor.download_and_resize(
                 "https://example.com/poster.jpg",
                 "poster",
                 dest
               )

      assert File.exists?(dest)
      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      # 100x100 is already within 1120x1680 — should not be upscaled
      assert width == 100
      assert height == 100
    end

    test "resizes thumb correctly", %{tmp_dir: tmp_dir, large_jpeg: jpeg} do
      stub_http_success(jpeg)

      dest = Path.join(tmp_dir, "episode-id/thumb.jpg")

      assert :ok =
               ImageProcessor.download_and_resize("https://example.com/thumb.jpg", "thumb", dest)

      assert File.exists?(dest)
      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert width <= 480
      assert height <= 270
    end

    test "resizes logo to longest edge 1440", %{tmp_dir: tmp_dir, large_png: png} do
      stub_http_success(png)

      dest = Path.join(tmp_dir, "entity-id/logo.png")

      assert :ok =
               ImageProcessor.download_and_resize("https://example.com/logo.png", "logo", dest)

      assert File.exists?(dest)
      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert max(width, height) <= 1440
    end

    test "returns permanent error for HTTP 404", %{tmp_dir: tmp_dir} do
      stub_http_error(404)

      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :permanent, {:http_error, 404, _}} =
               ImageProcessor.download_and_resize(
                 "https://example.com/missing.jpg",
                 "poster",
                 dest
               )
    end

    test "returns transient error for HTTP 500", %{tmp_dir: tmp_dir} do
      stub_http_error(500)

      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :transient, {:http_error, 500, _}} =
               ImageProcessor.download_and_resize(
                 "https://example.com/poster.jpg",
                 "poster",
                 dest
               )
    end

    test "returns transient error for connection failure", %{tmp_dir: tmp_dir} do
      stub_http_connection_error(:timeout)

      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :transient, {:download_failed, _, :timeout}} =
               ImageProcessor.download_and_resize(
                 "https://example.com/poster.jpg",
                 "poster",
                 dest
               )
    end

    test "creates destination directory if needed", %{tmp_dir: tmp_dir, small_jpeg: jpeg} do
      stub_http_success(jpeg)

      nested_dest = Path.join([tmp_dir, "deep", "nested", "dir", "poster.jpg"])

      assert :ok =
               ImageProcessor.download_and_resize(
                 "https://example.com/poster.jpg",
                 "poster",
                 nested_dest
               )

      assert File.exists?(nested_dest)
    end
  end

  # ---------------------------------------------------------------------------
  # Error categorization
  # ---------------------------------------------------------------------------

  describe "error categorization" do
    test "403 is permanent", %{tmp_dir: tmp_dir} do
      stub_http_error(403)
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :permanent, {:http_error, 403, _}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end

    test "410 is permanent", %{tmp_dir: tmp_dir} do
      stub_http_error(410)
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :permanent, {:http_error, 410, _}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end

    test "429 is transient", %{tmp_dir: tmp_dir} do
      stub_http_error(429)
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :transient, {:http_error, 429, _}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end

    test "502 is transient", %{tmp_dir: tmp_dir} do
      stub_http_error(502)
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :transient, {:http_error, 502, _}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end

    test "connection failure is transient", %{tmp_dir: tmp_dir} do
      stub_http_connection_error(:econnrefused)
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :transient, {:download_failed, _, :econnrefused}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end

    test "corrupt image data is permanent", %{tmp_dir: tmp_dir} do
      stub_http_success("not an image")
      dest = Path.join(tmp_dir, "entity-id/poster.jpg")

      assert {:error, :permanent, {:image_open_failed, _}} =
               ImageProcessor.download_and_resize("https://example.com/x.jpg", "poster", dest)
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP stub helpers
  # ---------------------------------------------------------------------------

  defp stub_http_success(body) do
    Application.put_env(:media_centarr, :image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:ok, %{status: 200, body: body}})
  end

  defp stub_http_error(status) do
    Application.put_env(:media_centarr, :image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:ok, %{status: status, body: ""}})
  end

  defp stub_http_connection_error(reason) do
    Application.put_env(:media_centarr, :image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:error, reason})
  end

  defmodule FakeClient do
    @moduledoc false
    def get(_url) do
      Process.get(:fake_http_response)
    end
  end
end
