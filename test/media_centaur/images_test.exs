defmodule MediaCentaur.ImagesTest do
  @moduledoc """
  Tests for the shared image download service.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Images

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
      body = :binary.copy("x", 2_000)
      stub_http_success(body)
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:ok, ^dest} = Images.download_raw("https://example.com/img.jpg", dest)
      assert File.read!(dest) == body
    end

    test "returns permanent error for empty body", %{tmp_dir: tmp_dir} do
      stub_http_success("")
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:error, :permanent, {:body_too_small, _url, 0}} =
               Images.download_raw("https://example.com/img.jpg", dest)

      refute File.exists?(dest)
    end

    test "rejects bodies below the 1024-byte floor (catches error envelopes / placeholder GIFs)",
         %{tmp_dir: tmp_dir} do
      stub_http_success(:binary.copy("x", 200))
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:error, :permanent, {:body_too_small, _url, 200}} =
               Images.download_raw("https://example.com/img.jpg", dest)

      refute File.exists?(dest)
    end

    test "accepts a body exactly at the floor", %{tmp_dir: tmp_dir} do
      body = :binary.copy("x", 1024)
      stub_http_success(body)
      dest = Path.join(tmp_dir, "test/poster.jpg")

      assert {:ok, ^dest} = Images.download_raw("https://example.com/img.jpg", dest)
      assert File.read!(dest) == body
    end

    test "creates destination directory", %{tmp_dir: tmp_dir} do
      stub_http_success(:binary.copy("d", 1500))
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

  describe "derivative/2" do
    setup %{tmp_dir: tmp_dir} do
      # Keep generated derivatives inside the test's tmp_dir (auto-cleaned)
      # via the same per-process override idiom the HTTP client uses.
      Process.put(:image_derivative_root, tmp_dir)

      master = Path.join(tmp_dir, "backdrop.jpg")
      {:ok, image} = Image.new(1200, 675, color: :red)
      {:ok, _} = Image.write(image, master, suffix: ".jpg", quality: 90)

      %{tmp_dir: tmp_dir, master: master}
    end

    defp master_with(tmp_dir, name, width, height, opts) do
      path = Path.join(tmp_dir, name)
      {:ok, image} = Image.new(width, height, Keyword.take(opts, [:color, :bands]))
      {:ok, _} = Image.write(image, path, Keyword.take(opts, [:suffix, :quality]))
      path
    end

    test "builds a downscaled JPEG derivative at the requested width", %{master: master} do
      assert {:ok, derivative} = Images.derivative(master, 480)
      assert derivative != master

      {:ok, image} = Image.open(derivative)
      {width, _height, _bands} = Image.shape(image)
      assert width == 480
    end

    test "snaps an off-ladder width UP to the next tier", %{master: master} do
      # 400 → 480; 500 → 640. Snapping bounds the number of cached variants
      # per image while still covering DPR-driven srcset requests.
      assert {:ok, d400} = Images.derivative(master, 400)
      assert {:ok, d500} = Images.derivative(master, 500)

      assert Image.open!(d400) |> Image.shape() |> elem(0) == 480
      assert Image.open!(d500) |> Image.shape() |> elem(0) == 640
    end

    test "never upscales — returns the master when it is already at/below the snapped width",
         %{tmp_dir: tmp_dir} do
      small = master_with(tmp_dir, "small.jpg", 300, 169, color: :green, suffix: ".jpg")

      # 300 snaps up to 320, but the master is only 300 wide — upscaling would
      # blur it, so the master is served unchanged.
      assert {:ok, ^small} = Images.derivative(small, 300)
    end

    test "returns the master when the requested width exceeds the ladder ceiling",
         %{master: master} do
      assert {:ok, ^master} = Images.derivative(master, 5000)
    end

    test "regenerates the derivative when the master is newer than the cache",
         %{master: master} do
      assert {:ok, derivative} = Images.derivative(master, 480)

      # Force the cache to look stale relative to its master.
      File.touch!(derivative, {{2000, 1, 1}, {0, 0, 0}})
      File.touch!(master, {{2030, 1, 1}, {0, 0, 0}})

      assert {:ok, ^derivative} = Images.derivative(master, 480)

      {:ok, %{mtime: mtime}} = File.stat(derivative)
      # A rebuild stamps the file ~now; the forced-stale 2000 mtime is gone.
      assert mtime > {{2001, 1, 1}, {0, 0, 0}}
    end

    test "preserves PNG format so transparent logos keep their alpha", %{tmp_dir: tmp_dir} do
      logo = master_with(tmp_dir, "logo.png", 1000, 250, color: :blue, suffix: ".png")

      assert {:ok, derivative} = Images.derivative(logo, 480)
      assert Path.extname(derivative) == ".png"
    end
  end

  describe "purge_derivatives_for/1" do
    setup %{tmp_dir: tmp_dir} do
      Process.put(:image_derivative_root, tmp_dir)
      master = Path.join(tmp_dir, "backdrop.jpg")
      {:ok, image} = Image.new(1200, 675, color: :red)
      {:ok, _} = Image.write(image, master, suffix: ".jpg", quality: 90)
      %{tmp_dir: tmp_dir, master: master}
    end

    test "deletes every cached derivative of a master and returns the count",
         %{master: master} do
      {:ok, d320} = Images.derivative(master, 320)
      {:ok, d480} = Images.derivative(master, 480)
      assert File.exists?(d320) and File.exists?(d480)

      assert Images.purge_derivatives_for(master) >= 2
      refute File.exists?(d320)
      refute File.exists?(d480)
    end

    test "is a no-op (count 0) when the master has no derivatives", %{master: master} do
      assert Images.purge_derivatives_for(master) == 0
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
