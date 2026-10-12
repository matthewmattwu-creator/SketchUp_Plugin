require 'minitest/autorun'
require 'json'
require_relative '../src/buildable_envelope/boundary'
class OffsetFixtureTest < Minitest::Test
  B = MattWu::BuildableEnvelope::Boundary
  G = MattWu::BuildableEnvelope::Geometry
  def test_js_results_against_original_segments_in_ruby
    path = File.expand_path('../tmp/offset-fixtures.json',__dir__)
    skip 'Run node test/offset_engine_test.js first for cross-language verification' unless File.file?(path)
    fixtures=JSON.parse(File.read(path))
    assert_equal 18,fixtures.length
    fixtures.each do |item|
      begin
        assert B.verify_outlines!(item['outlines'],item['points'],item['setbacks']),item['name']
      rescue ArgumentError => error
        raise ArgumentError, item['name'] + ': ' + error.message
      end
      assert_operator G.area(item['outlines']),:<=,G.signed_area(item['points']).abs+0.001,item['name']
      item['outlines'].each do |outline|
        mesh=G.prism(outline,36.0)
        assert_equal outline.length+2,mesh[:faces].length,item['name']
      end
    end
  end
end
