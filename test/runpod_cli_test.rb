# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "timeout"
require "uri"

class RunpodCliTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)

  def setup
    @tmp = Dir.mktmpdir("lme-runpod-cli-")
    @public_key = File.join(@tmp, "id_ed25519.pub")
    File.write(@public_key, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest cli@example\n")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_create_dry_run_is_read_only_and_prints_cost_before_any_paid_mutation
    requests = Queue.new
    server, thread = start_fake_runpod(requests)
    port = server.addr[1]
    env = {
      "RUNPOD_API_KEY" => "rpa_test_only",
      "RUNPOD_API_BASE_URL" => "http://127.0.0.1:#{port}/v2",
      "RUNPOD_MAX_FLEET_HOURLY_USD" => "3.00"
    }

    stdout, stderr, status = Open3.capture3(
      env,
      RbConfig.ruby,
      File.join(REPO_ROOT, "bin", "lme"),
      "runpod-create",
      "--workers", "5",
      "--dry-run",
      "--ssh-public-key", @public_key,
      chdir: REPO_ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "RunPod fleet preflight"
    assert_includes stdout, "Workers: 5"
    assert_includes stdout, "Projected fleet rate: $1.7500/hr"
    assert_includes stdout, "Projected 10-minute cost: $0.2917"
    assert_includes stdout, "Projected 30-minute cost: $0.8750"
    assert_includes stdout, "No pods have been created."
    assert_includes stdout, "Dry run PASS."

    received = 2.times.map { Timeout.timeout(2) { requests.pop } }
    assert_equal ["GET", "GET"], received.map { |r| r.fetch(:method) }
    assert_equal ["/v2/pods", "/v2/catalog/gpus"], received.map { |r| r.fetch(:path) }
    assert received.all? { |r| r.fetch(:authorization) == "Bearer rpa_test_only" }
  ensure
    server&.close
    thread&.join(2)
  end

  private

  def start_fake_runpod(requests)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      2.times do
        socket = server.accept
        request_line = socket.gets.to_s
        method, target, = request_line.split(" ")
        headers = {}
        while (line = socket.gets)
          break if line == "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.to_s.strip
        end
        uri = URI(target)
        requests << {
          method:,
          path: uri.path,
          query: uri.query,
          authorization: headers["authorization"]
        }

        body = if uri.path == "/v2/pods"
                 JSON.generate("pods" => [])
               else
                 JSON.generate(
                   "gpus" => [{
                     "id" => "NVIDIA A40",
                     "name" => "A40",
                     "memory" => 48,
                     "secure" => true,
                     "community" => true,
                     "price" => { "secure" => 0.44, "community" => 0.35 },
                     "maxCount" => { "secure" => 8, "community" => 8 },
                     "availability" => "HIGH"
                   }]
                 )
               end
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        socket.close
      end
    end
    [server, thread]
  end
end
