require 'minitest/autorun'
require_relative '../src/buildable_envelope/solid_check'

class SolidCheckTest < Minitest::Test
  CHECK = MattWu::BuildableEnvelope::SolidCheck

  class LegacyGroup
    attr_reader :definition, :calls
    def initialize(result)
      @definition = Object.new # 2023-2026.1: no definition manifold? method
      @result = result
      @calls = 0
    end
    def manifold?
      @calls += 1
      @result
    end
  end

  class ModernGroup
    attr_reader :definition
    def initialize(result)
      @definition = Struct.new(:result) do
        def manifold?
          result
        end
      end.new(result)
    end
    def manifold?
      raise 'Should prefer supported definition API'
    end
  end

  def test_2023_2024_2025_and_2026_early_use_group_api
    [2023,2024,2025,2026].each do |_year|
      group = LegacyGroup.new(true)
      assert CHECK.closed?(group)
      assert_equal 1,group.calls
    end
  end

  def test_legacy_non_closed_body_remains_rejected
    group = LegacyGroup.new(false)
    refute CHECK.closed?(group)
    assert_equal 1,group.calls
  end

  def test_2026_2_prefers_definition_api
    assert CHECK.closed?(ModernGroup.new(true))
  end

  def test_modern_non_closed_body_remains_rejected
    refute CHECK.closed?(ModernGroup.new(false))
  end

  def test_missing_api_is_not_treated_as_a_solid
    group = Struct.new(:definition).new(Object.new)
    assert_raises(ArgumentError) { CHECK.closed?(group) }
  end

  def test_runtime_calls_the_tested_compatibility_helper
    source = File.read(File.expand_path('../src/buildable_envelope/main.rb',__dir__))
    assert_includes source,"SolidCheck.closed?(body)"
    refute_includes source,"body.definition.manifold?"
    assert_includes source,"require_relative 'solid_check'"
  end
end
