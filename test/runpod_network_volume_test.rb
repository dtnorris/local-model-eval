# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "uri"
require_relative "../lib/local_model_evaluation/runpod_client"
require_relative "../lib/local_model_evaluation/runpod_fleet"

class RunpodNetworkVolumeTest < Minitest::Test
  Response = Struct.new(:status, :body, keyword_init: true)

  class FakeClient
    attr_reader :created_bodies, :deleted_ids

    def initialize
      @created_bodies = []
      @deleted_ids = []
    end

    def list_pods
      []
    end

    def get_network_volume(id)
      {
        "id" => id,
        "name" => "af-models",
        "size" => 200,
        "dataCenterId" => "US-KS-2",
        "volumeType" => "STANDARD"
      }
    end

    def list_data_centers(include_gpu_availability:)
      raise "GPU availability expansion required" unless include_gpu_availability

      [{
        "id" => "US-KS-2",
        "gpuAvailability" => [{
          "id" => "NVIDIA A40",
          "name" => "A40",
          "availability" => "HIGH"
        }]
      }]
    end

    def list_gpu_types(cloud:, count:)
      raise "expected SECURE" unless cloud == "SECURE"
      raise "expected one GPU" unless count == 1

      [{
        "id" => "NVIDIA A40",
        "name" => "A40",
        "memory" => 48,
        "community" => true,
        "secure" => true,
        "availability" => "HIGH",
        "price" => { "community" => 0.35, "secure" => 0.44 }
      }]
    end

    def create_pod(body)
      @created_bodies << Marshal.load(Marshal.dump(body))
      { "id" => "pod_network" }
    end

    def get_pod(id)
      {
        "id" => id,
        "name" => "af-lme-burst-1",
        "status" => "RUNNING",
        "cloud" => "SECURE",
        "dataCenterId" => "US-KS-2",
        "gpu" => { "id" => "NVIDIA A40", "count" => 1 },
        "cost" => 0.44,
        "runtime" => {
          "ports" => [{
            "private" => 22,
            "public" => 22022,
            "type" => "tcp",
            "ip" => "198.51.100.22"
          }]
        }
      }
    end

    def delete_pod(id)
      @deleted_ids << id
      { "id" => id, "status" => "TERMINATED" }
    end
  end

  def test_client_uses_v2_network_volume_and_datacenter_paths
    seen = []
    transport = lambda do |request|
      seen << request
      body = case request.fetch(:uri).path
             when "/v2/network-volumes/vol_models"
               JSON.generate(
                 "id" => "vol_models",
                 "name" => "af-models",
                 "size" => 200,
                 "dataCenterId" => "US-KS-2"
               )
             when "/v2/catalog/datacenters"
               JSON.generate("dataCenters" => [])
             else
               raise "unexpected path: #{request.fetch(:uri).path}"
             end
      Response.new(status: 200, body:)
    end

    client = LocalModelEvaluation::RunpodClient.new(api_key: "rpa_test", transport:)
    assert_equal "vol_models", client.get_network_volume("vol_models").fetch("id")
    assert_equal [], client.list_data_centers(include_gpu_availability: true)

    assert_equal "/v2/network-volumes/vol_models", seen.fetch(0).fetch(:uri).path
    assert_equal "/v2/catalog/datacenters", seen.fetch(1).fetch(:uri).path
    query = URI.decode_www_form(seen.fetch(1).fetch(:uri).query).to_h
    assert_equal "GPU_AVAILABILITY", query.fetch("include")
  end

  def test_network_volume_requires_secure_cloud_before_paid_creation
    fleet, client = build_fleet

    error = assert_raises(LocalModelEvaluation::RunpodFleet::Error) do
      fleet.preflight(
        worker_count: 1,
        cloud: "COMMUNITY",
        network_volume_id: "vol_models"
      )
    end

    assert_includes error.message, "require SECURE cloud"
    assert_empty client.created_bodies
  end

  def test_network_volume_preflight_pins_datacenter_and_create_uses_network_mount
    fleet, client = build_fleet
    preflight = fleet.preflight(
      worker_count: 1,
      cloud: "SECURE",
      network_volume_id: "vol_models"
    )

    assert_equal "vol_models", preflight.network_volume_id
    assert_equal "US-KS-2", preflight.data_center_id
    assert_equal "HIGH", preflight.availability

    workers = fleet.create(
      worker_count: 1,
      cloud: "SECURE",
      network_volume_id: "vol_models",
      ssh_public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest test@example",
      preflight:
    )

    assert_equal 1, workers.length
    body = client.created_bodies.fetch(0)
    assert_equal ["US-KS-2"], body.fetch("dataCenterIds")
    assert_equal(
      { "network" => [{ "volumeId" => "vol_models", "path" => "/workspace" }] },
      body.fetch("mounts")
    )
  end

  private

  def build_fleet
    tmp = Dir.mktmpdir("lme-network-volume-")
    @tmpdirs ||= []
    @tmpdirs << tmp
    env_path = File.join(tmp, ".env")
    File.write(env_path, "RUNPOD_API_KEY=rpa_test\n")
    client = FakeClient.new
    fleet = LocalModelEvaluation::RunpodFleet.new(
      client:,
      env_path:,
      sleeper: ->(_seconds) {},
      clock: -> { 0.0 },
      state_root: File.join(tmp, "state")
    )
    [fleet, client]
  end

  def teardown
    Array(@tmpdirs).each { |path| FileUtils.remove_entry(path) if File.exist?(path) }
  end
end
