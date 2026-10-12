require 'minitest/autorun'
require_relative 'selection_test'
require_relative '../src/buildable_envelope/cad_import'
class CadSummaryTest < Minitest::Test
  C=MattWu::BuildableEnvelope::CadImport
  Layer=Struct.new(:name)
  Definition=Struct.new(:entities)
  Bounds=Struct.new(:width,:height,:depth)
  class Block < Sketchup::ComponentInstance
    attr_reader :definition
    def initialize(entities);@definition=Definition.new(entities);end
    def layer;Layer.new('红线');end
  end
  def test_counts_nested_edges_faces_and_unique_tags
    helper=SelectionTest.new('test_face_and_selected_border_are_not_duplicated')
    face,edges=helper.face_with_edges
    (edges+[face]).each { |entity| entity.define_singleton_method(:layer){Layer.new('红线')} }
    instance=Struct.new(:definition,:bounds).new(Definition.new([Block.new(edges+[face])]),Bounds.new(100/0.0254,60/0.0254,0))
    info=C.summary(instance)
    assert_equal 4,info[:counts][:edges]
    assert_equal 1,info[:counts][:faces]
    assert_equal 1,info[:counts][:components]
    assert_equal ['红线'],info[:tags]
    assert_in_delta 100,info[:width],1e-8
    assert_in_delta 60,info[:height],1e-8
    refute info[:truncated]
  end
  def test_deep_metadata_is_partial_instead_of_import_failure
    child=[];22.times{child=[Block.new(child)]}
    instance=Struct.new(:definition,:bounds).new(Definition.new(child),Bounds.new(1,1,0))
    info=C.summary(instance)
    assert info[:truncated]
    assert_operator info[:counts][:components],:>,0
  end
end
