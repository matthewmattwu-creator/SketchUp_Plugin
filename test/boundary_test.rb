require 'minitest/autorun'
require_relative '../src/buildable_envelope/boundary'
class BoundaryTest < Minitest::Test
  B = MattWu::BuildableEnvelope::Boundary
  G = MattWu::BuildableEnvelope::Geometry
  def square(x,y,size,z=0)
    [[x,y,z],[x+size,y,z],[x+size,y+size,z],[x,y+size,z]]
  end
  def test_native_vertices_and_coordinates_are_preserved
    points = square(1_000_000,2_000_000,10)
    points.insert(1,[1_000_000.123456,2_000_000,0])
    copy = Marshal.load(Marshal.dump(points))
    result = B.build(points)
    assert_equal copy,points
    assert_equal copy,result[:source_points]
    assert_equal 5,result[:points].length
    result[:points].each { |p| assert copy.any? { |q| (p[0]+result[:origin][0]-q[0]).abs < 1e-9 && (p[1]+result[:origin][1]-q[1]).abs < 1e-9 } }
  end
  def test_dense_boundary_is_not_simplified_during_recognition
    points = 720.times.map { |i| a=i*Math::PI/360; [50*Math.cos(a),50*Math.sin(a),0] }
    assert_equal 720,B.build(points)[:points].length
  end
  def test_reversed_and_rotated_ring_has_stable_edge_numbering
    points = square(100,200,10)
    assert_equal B.build(points)[:points],B.build(points.reverse.rotate(2))[:points]
    assert_equal B.build(points)[:origin],B.build(points.reverse.rotate(2))[:origin]
  end
  def test_hole_is_classified_without_filling
    regions = B.regions([square(2,2,6).reverse,square(0,0,10)])
    assert_equal 1,regions.length
    assert_equal 1,regions.first[:holes].length
    assert_in_delta 64,regions.first[:area],1e-9
  end
  def test_island_and_disjoint_parcel
    regions = B.regions([square(3,3,2),square(20,0,5),square(2,2,6),square(0,0,10)])
    assert_equal [4,25,64],regions.map { |r| r[:area] }.sort
    assert_equal [0,0,1],regions.map { |r| r[:holes].length }.sort
  end
  def test_same_xy_at_different_elevations_is_not_a_hole
    assert_equal 2,B.regions([square(0,0,10),square(2,2,5,5)]).length
  end
  def test_crossing_touching_and_duplicate_rings_are_rejected
    [square(8,8,5),square(10,0,5),square(0,0,10).reverse].each do |ring|
      assert_raises(ArgumentError) { B.regions([square(0,0,10),ring]) }
    end
  end
  def test_invalid_coordinates_and_non_horizontal_ring
    assert_raises(ArgumentError) { B.build([[0,0,0],[1,0,Float::NAN],[0,1,0]]) }
    points = square(0,0,10); points.last[2]=1
    assert_raises(ArgumentError) { B.build(points) }
  end
  def test_consecutive_backtracking_is_rejected
    assert_raises(ArgumentError) { B.build([[0,0,0],[10,0,0],[5,0,0],[10,10,0],[0,10,0]]) }
  end
  def test_open_component_does_not_remove_valid_cycle
    vertices = { a:[0,0,0],b:[10,0,0],c:[10,10,0],d:[0,10,0],e:[20,0,0],f:[21,0,0] }
    loops,errors = B.cycles(vertices,[[:c,:d],[:a,:b],[:e,:f],[:d,:a],[:b,:c]])
    assert_equal 1,loops.length
    assert_equal 1,errors.length
    assert_match(/开口端点 2/,errors.first)
    assert_equal 100,B.regions(loops).first[:area]
  end
  def test_close_but_distinct_endpoints_are_not_snapped
    vertices = { a:[0,0,0],b:[10,0,0],c:[10,10,0],d:[0,10,0],e:[0,0.000001,0] }
    loops,errors = B.cycles(vertices,[[:a,:b],[:b,:c],[:c,:d],[:d,:e]])
    assert_empty loops
    assert_equal 1,errors.length
  end
  def test_fork_and_duplicate_edges_are_not_repaired
    vertices = { a:[0,0,0],b:[10,0,0],c:[10,10,0],d:[0,10,0] }
    [ [[:a,:b],[:b,:c],[:c,:d],[:d,:a],[:a,:c]],
      [[:a,:b],[:b,:c],[:c,:d],[:d,:a],[:a,:b]] ].each do |edges|
      loops,errors = B.cycles(vertices,edges)
      assert_empty loops
      assert_match(/分叉顶点 2/,errors.first)
    end
  end
  def test_clearance_check_rejects_under_setback_and_outside
    poly = square(0,0,10).map { |p| p[0,2] }
    assert B.verify_outlines!([[[2,2],[8,2],[8,8],[2,8]]],poly,[2]*4)
    assert_raises(ArgumentError) { B.verify_outlines!([[[1,1],[9,1],[9,9],[1,9]]],poly,[2]*4) }
    assert_raises(ArgumentError) { B.verify_outlines!([[[-1,2],[8,2],[8,8],[-1,8]]],poly,[0]*4) }
  end
  def test_zero_setback_matches_dense_rectangle_without_extra_margin
    poly = [[0,0],[5,0],[10,0],[10,5],[10,10],[5,10],[0,10],[0,5]]
    outlines = G.boundaries(G.inset(poly,[0]*8))
    assert_in_delta 100,G.area(outlines),1e-9
    assert B.verify_outlines!(outlines,poly,[0]*8)
  end
  def test_dense_rectangle_default_has_exact_clearance
    poly = []
    corners = [[0,0],[20,0],[20,20],[0,20]]
    corners.each_index do |i|
      a,b = corners[i],corners[(i+1)%4]
      51.times { |j| t=j/51.0; poly << [a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])] }
    end
    cells = G.inset(poly,[2]*poly.length)
    assert_in_delta 256,G.area(cells),0.001
    assert B.verify_outlines!(G.boundaries(cells),poly,[2]*poly.length)
  end
end
