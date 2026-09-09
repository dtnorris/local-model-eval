# frozen_string_literal: true
require_relative 'test_helper'
require 'open3'
require 'json'
require_relative '../lib/production_backlog_runtime_contract'

class AdventureIngestRunnerTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  def setup
    @root = Dir.mktmpdir('ingest-runner-routing')
    FileUtils.mkdir_p([File.join(@root, 'bin'), File.join(@root, 'lib')])
    %w[run_production_backlog.sh lib/batch_failure_policy.sh lib/production_backlog_runtime_contract.rb].each do |path|
      FileUtils.cp(File.join(ROOT, path), File.join(@root, path))
    end
    executable('bin/preflight-production-backlog-sources', "#!/bin/sh\nexit 0\n")
    executable('bin/classify-production-failure', "#!/bin/sh\nexit 1\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def executable(path, text)
    File.write(File.join(@root, path), text)
    FileUtils.chmod(0o755, File.join(@root, path))
  end

  def queue(contract, manifests = [])
    path = File.join(@root, 'production_backlog/production-backlog-020')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'snapshot.yml'), YAML.dump('contract_type' => contract))
    File.write(File.join(path, 'run_order.txt'), manifests.join("\n") + "\n")
    path
  end

  def run_queue(path)
    Open3.capture3({'LME_REPO' => @root, 'AF_LLM_MAX_TOKENS' => '99999'}, 'bash', File.join(@root, 'run_production_backlog.sh'), path)
  end

  def test_future_ingest_and_all_existing_contract_routes
    {'adventure_ingest_v1' => 'bin/verify-production-backlog',
     'ee_local_qualified_v1' => 'verify_production_backlog_ee.sh',
     'gmbs_local_qualified_v1' => 'verify_production_backlog_gmbs.sh',
     'gmpb_local_qualified_v1' => 'verify_production_backlog_gmpb.sh',
     'seriousness_local_qualified_v1' => 'verify_production_backlog_seriousness.sh',
     'other' => 'verify_production_backlog.sh'}.each do |contract, script|
      executable(script, "#!/bin/sh\nprintf '%s' '#{script}' > routed\nexit 1\n")
      _out, _err, status = run_queue(queue(contract))
      refute status.success?
      assert_equal script, File.read(File.join(@root, 'routed'))
    end
  end

  def test_future_runtime_amendment_is_exact_and_does_not_leak
    executable('bin/verify-production-backlog', "#!/bin/sh\nexit 0\n")
    executable('verify_production_backlog.sh', "#!/bin/sh\nexit 0\n")
    executable('bin/lme', <<~'SCRIPT')
      #!/usr/bin/env ruby
      require 'yaml'
      require 'json'
      require 'fileutils'
      abort 'only fixture run allowed' unless ARGV.shift == 'run'
      data = YAML.safe_load_file(ARGV.fetch(0))
      File.open('dispatch.jsonl', 'a') { |f| f.puts JSON.dump([data['dimension'], ENV['AF_LLM_MAX_TOKENS']]) }
      dir = File.join('output', data.fetch('name'), 'runs', 'fixture')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'metadata.json'), JSON.dump('status' => 'complete'))
    SCRIPT
    core = ProductionBacklogRuntimeContract::QWEN35_CORE_DIMENSIONS
    excluded = ['Exploration Emphasis', 'GM Preparation Burden', 'Seriousness', 'Levels', 'GM Beginner Suitability', '# of Sessions']
    dimensions = core + excluded
    paths = dimensions.each_with_index.map do |dimension, index|
      path = "experiments/case-#{index}.yml"
      FileUtils.mkdir_p(File.join(@root, 'experiments'))
      File.write(File.join(@root, path), YAML.dump('name' => "case-#{index}", 'dimension' => dimension, 'models' => ['qwen'],
                                                'production_contract' => {'contract_type' => 'adventure_ingest_v1'}))
      path
    end
    out, err, status = run_queue(queue('adventure_ingest_v1', paths))
    assert status.success?, out + err
    calls = File.readlines(File.join(@root, 'dispatch.jsonl')).map { |line| JSON.parse(line) }
    assert_equal core.map { |d| [d, '8192'] } + excluded.map { |d| [d, nil] }, calls
    FileUtils.rm_rf(File.join(@root, 'output'))
    File.write(File.join(@root, 'dispatch.jsonl'), '')
    out, err, status = run_queue(queue('unrelated', paths.take(1)))
    assert status.success?, out + err
    assert_equal [[core.first, nil]], File.readlines(File.join(@root, 'dispatch.jsonl')).map { |line| JSON.parse(line) }
  end
end
