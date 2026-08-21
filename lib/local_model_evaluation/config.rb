# frozen_string_literal: true

require "yaml"

module LocalModelEvaluation
  class Config
    ENV_PATTERN = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/

    def self.load_yaml(path)
      raw = File.read(path)
      expanded = raw.gsub(ENV_PATTERN) do
        name = Regexp.last_match(1)
        default = Regexp.last_match(2)
        value = ENV[name]
        if value.nil? || value.empty?
          raise KeyError, "environment variable #{name} is not set" if default.nil?
          default
        else
          value
        end
      end
      YAML.safe_load(expanded, aliases: false) || {}
    end
  end
end
