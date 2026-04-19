defmodule MediaCentarr.ImagesTest do
  @moduledoc """
  Tests for the shared image download service.
  """
  use ExUnit.Case, async: true

  alias MediaCentarr.Images

  @moduletag :tmp_dir

  # No setup needed — stubs are per-process (see helpers below), so they
  # auto-clean when the test process exits and don't stomp on sibling
  # async tests via the global Application env.

  describe "download/3 with resize" do
    setup %{tmp_dir: tmp_dir} do
      {:ok, large_image} = Image.new(2000, 3000, color: :red)
      {:ok, large_jpeg} = Image.write(large_image, :memory, suffix: ".jpg")

      {:ok, small_image} = Image.new(100, 100, color: :blue)
      {:ok, small_jpeg} = Image.write(small_image, :memory, suffix: ".jpg")

      %{tmp_dir: tmp_dir, large_jpeg: large_jpeg, small_jpeg: small_jpeg}
    end

    test "downloads and resizes to fit dimensions", %{tmp_dir: tmp_dir, large_jpeg: jpeg} do
      stub_http_success(jpeg)
      dest = Path.join(tmp_dir, "test/backdrop.jpg")

      assert {:ok, ^dest} =
               Images.download("https://example.com/img.jpg", dest, resize: {:fit, 1920, 1080})

      assert File.exists?(dest)
      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert width <= 1920
      assert height <= 1080
    end

    test "skips resize when image already within target", %{tmp_dir: tmp_dir, small_jpeg: jpeg} do
      stub_http_success(jpeg)
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:ok, ^dest} =
               Images.download("https://example.com/img.jpg", dest, resize: {:fit, 1120, 1680})

      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert width == 100
      assert height == 100
    end

    test "resizes by longest edge", %{tmp_dir: tmp_dir, large_jpeg: jpeg} do
      stub_http_success(jpeg)
      dest = Path.join(tmp_dir, "test/logo.jpg")

      assert {:ok, ^dest} =
               Images.download("https://example.com/img.jpg", dest, resize: {:longest_edge, 1440})

      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert max(width, height) <= 1440
    end

    test "creates destination directory", %{tmp_dir: tmp_dir, small_jpeg: jpeg} do
      stub_http_success(jpeg)
      dest = Path.join([tmp_dir, "deep", "nested", "img.jpg"])

      assert {:ok, ^dest} = Images.download("https://example.com/img.jpg", dest)
      assert File.exists?(dest)
    end
  end

  describe "download/3 without resize" do
    setup %{tmp_dir: tmp_dir} do
      {:ok, image} = Image.new(800, 600, color: :green)
      {:ok, jpeg} = Image.write(image, :memory, suffix: ".jpg")
      %{tmp_dir: tmp_dir, jpeg: jpeg}
    end

    test "writes image without resize when no option given", %{tmp_dir: tmp_dir, jpeg: jpeg} do
      stub_http_success(jpeg)
      dest = Path.join(tmp_dir, "test/raw.jpg")

      assert {:ok, ^dest} = Images.download("https://example.com/img.jpg", dest)

      {:ok, result} = Image.open(dest)
      {width, height, _} = Image.shape(result)
      assert width == 800
      assert height == 600
    end
  end

  describe "download_raw/2" do
    test "writes bytes directly without image processing", %{tmp_dir: tmp_dir} do
      stub_http_success("raw image bytes here")
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:ok, ^dest} = Images.download_raw("https://example.com/img.jpg", dest)
      assert File.read!(dest) == "raw image bytes here"
    end

    test "returns permanent error for empty body", %{tmp_dir: tmp_dir} do
      stub_http_success("")
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:error, :permanent, {:empty_body, _}} =
               Images.download_raw("https://example.com/img.jpg", dest)
    end

    test "creates destination directory", %{tmp_dir: tmp_dir} do
      stub_http_success("data")
      dest = Path.join([tmp_dir, "new", "dir", "img.jpg"])

      assert {:ok, ^dest} = Images.download_raw("https://example.com/img.jpg", dest)
      assert File.exists?(dest)
    end
  end

  describe "error handling" do
    test "HTTP 404 is permanent", %{tmp_dir: tmp_dir} do
      stub_http_error(404)
      dest = Path.join(tmp_dir, "test/img.jpg")

      assert {:error, :permanent, {:http_error, 404, _}} =
               Images.download("https://example.com/img.jpg", dest)
    end

    test "HTTP 500 is transient", %{tmp_dir: tmp_dir} do
      stub_http_error(500)
      dest = Path.join(tmp_dir, "test/img.jpg")

      assert {:error, :transient, {:http_error, 500, _}} =
               Images.download("https://example.com/img.jpg", dest)
    end

    test "connection failure is transient", %{tmp_dir: tmp_dir} do
      stub_http_connection_error(:timeout)
      dest = Path.join(tmp_dir, "test/img.jpg")

      assert {:error, :transient, {:download_failed, _, :timeout}} =
               Images.download("https://example.com/img.jpg", dest)
    end

    test "corrupt image data is permanent for download/3", %{tmp_dir: tmp_dir} do
      stub_http_success("not an image")
      dest = Path.join(tmp_dir, "test/img.jpg")

      assert {:error, :permanent, {:image_open_failed, _}} =
               Images.download("https://example.com/img.jpg", dest)
    end

    test "download_raw passes through HTTP errors", %{tmp_dir: tmp_dir} do
      stub_http_error(403)
      dest = Path.join(tmp_dir, "test/img.jpg")

      assert {:error, :permanent, {:http_error, 403, _}} =
               Images.download_raw("https://example.com/img.jpg", dest)
    end
  end

  # --- HTTP stub helpers ---

  # Per-process overrides — see `Images.http_client/0`. These don't
  # mutate `Application.env`, so async-true tests in this file and
  # siblings can stub independently without clobbering each other.

  defp stub_http_success(body) do
    Process.put(:image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:ok, %{status: 200, body: body}})
  end

  defp stub_http_error(status) do
    Process.put(:image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:ok, %{status: status, body: ""}})
  end

  defp stub_http_connection_error(reason) do
    Process.put(:image_http_client, __MODULE__.FakeClient)
    Process.put(:fake_http_response, {:error, reason})
  end

  defmodule FakeClient do
    @moduledoc false
    def get(_url), do: Process.get(:fake_http_response)
  end
end
