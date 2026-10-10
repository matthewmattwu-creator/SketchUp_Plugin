require 'minitest/autorun'
# Small API doubles test extraction, not SketchUp's actual face/extrusion kernel.
$LOADED_FEATURES << 'sketchup.rb' unless $LOADED_FEATURES.include?('sketchup.rb')
def file_loaded?(_path); true; end
module Sketchup
  class Face
    attr_reader :loops, :outer_loop
    def initialize(loops); @loops=loops; @outer_loop=loops.first; end
  end
  class Edge
    attr_reader :start, :faces
    define_method(:end) { @finish }
    def initialize(a,b,faces=[]); @start=a; @finish=b; @faces=faces; end
    def vertices; [@start,@finish]; end
  end
  class Group; end
  class ComponentInstance; end
end
require_relative '../src/buildable_envelope/main'
class SelectionTest < Minitest::Test
  Plugin = MattWu::BuildableEnvelope
  Point = Struct.new(:x,:y,:z) do
    def transform(t); self.class.new(x+t[0],y+t[1],z+t[2]); end
  end
  Vertex = Struct.new(:position)
  Ring = Struct.new(:vertices)
  def ring(x,y,size)
    Ring.new([[x,y],[x+size,y],[x+size,y+size],[x,y+size]].map { |a,b| Vertex.new(Point.new(a/0.0254,b/0.0254,0)) })
  end
  def face_with_edges
    outer = ring(0,0,10)
    face = Sketchup::Face.new([outer])
    edges = outer.vertices.each_index.map { |i| Sketchup::Edge.new(outer.vertices[i],outer.vertices[(i+1)%4],[face]) }
    [face,edges]
  end
  def extract(entities,t=[0,0,0])
    results,errors=[],[]
    Plugin.scan(entities,t,'测试',results,errors)
    assert_empty errors
    results
  end
  def test_face_and_selected_border_are_not_duplicated
    face,edges=face_with_edges
    assert_equal 1,extract([face]+edges).length
  end
  def test_selected_closed_edges_on_existing_face_are_recognized
    _face,edges=face_with_edges
    result = extract(edges).first
    assert_equal 4,result[:points].length
    assert_in_delta 100,result[:area],1e-8
  end
  def test_face_hole_is_extracted_and_retained_in_signature
    face=Sketchup::Face.new([ring(0,0,10),ring(2,2,6)])
    result=extract([face]).first
    assert_equal 1,result[:holes].length
    assert_in_delta 64,result[:area],1e-8
    before=Plugin.signature([result])
    changed=Marshal.load(Marshal.dump(result))
    changed[:source_rings][1][0][2] += 0.0001
    refute_equal before,Plugin.signature([changed])
  end
  def test_world_transform_is_applied_before_local_origin
    face,_edges=face_with_edges
    result=extract([face],[100/0.0254,200/0.0254,0]).first
    assert_in_delta 100,result[:origin][0],1e-8
    assert_in_delta 200,result[:origin][1],1e-8
    assert_in_delta 100,result[:area],1e-8
  end
end

class UniformOffsetIntegrationTest < Minitest::Test
  P = MattWu::BuildableEnvelope
  def source; {points:[[0.0,0.0],[20.0,0.0],[20.0,10.0],[0.0,10.0]]}; end
  def input(outlines)
    {'offset_result'=>{'outlines'=>outlines,'method'=>'parallel-miter'}}
  end
  def test_accepts_verified_uniform_offset_without_cell_fragmentation
    outlines,method=P.prepared_outlines(source,[2.0]*4,input([[[2.0,2.0],[18.0,2.0],[18.0,8.0],[2.0,8.0]]]))
    assert_equal 1,outlines.length
    assert_equal '尖角平行偏移',method
  end
  def test_rejects_under_setback_result
    assert_raises(ArgumentError){P.prepared_outlines(source,[2.0]*4,input([[[1.0,1.0],[19.0,1.0],[19.0,9.0],[1.0,9.0]]]))}
  end
  def test_rejects_uniform_engine_result_for_variable_edge_parameters
    assert_raises(ArgumentError){P.prepared_outlines(source,[2,3,2,2],input([]))}
  end
  def test_empty_result_means_no_buildable_area
    outlines,_method=P.prepared_outlines(source,[50]*4,input([]))
    assert_empty outlines
  end
end

class VariableOffsetIntegrationTest < Minitest::Test
  P = MattWu::BuildableEnvelope
  def source; {points:[[0.0,0.0],[20.0,0.0],[20.0,10.0],[0.0,10.0]]}; end
  def input(outline)
    {'offset_result'=>{'outlines'=>[outline],'method'=>'segment-clearance'}}
  end
  def test_accepts_each_sides_own_clearance
    outlines,method=P.prepared_outlines(source,[2,4,3,1],input([[1.0001,2.0001],[15.9999,2.0001],[15.9999,6.9999],[1.0001,6.9999]]))
    assert_equal '逐组最短退距圆角',method
    assert_in_delta 75,MattWu::BuildableEnvelope::Geometry.area(outlines),0.01
  end
  def test_rejects_sides_mapped_to_wrong_distances
    assert_raises(ArgumentError){P.prepared_outlines(source,[4,2,3,1],input([[1.0001,2.0001],[15.9999,2.0001],[15.9999,6.9999],[1.0001,6.9999]]))}
  end
  def test_no_legacy_cell_fragmentation_fallback_when_result_missing
    assert_raises(ArgumentError){P.prepared_outlines(source,[2,4,3,1],{})}
  end
end
