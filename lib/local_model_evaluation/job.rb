# frozen_string_literal: true

require "digest"

module LocalModelEvaluation
  Job = Struct.new(:id, :model_alias, :ollama_model, :adventure, :replicate, :planned_worker, keyword_init: true) do
    def self.build(model_alias:, ollama_model:, adventure:, replicate:, planned_worker: nil)
      identity = [model_alias, ollama_model, adventure, replicate, planned_worker || "pool"].join("|")
      id = Digest::SHA256.hexdigest(identity)[0, 16]
      new(id:, model_alias:, ollama_model:, adventure:, replicate:, planned_worker:)
    end
  end
end
