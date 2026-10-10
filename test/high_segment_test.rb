require 'minitest/autorun'
require_relative '../src/buildable_envelope/geometry'

class HighSegmentTest < Minitest::Test
  G = MattWu::BuildableEnvelope::Geometry
  def crescent(segments)
    # Crescent bounded by two circular arcs meeting at the tips.
    outer = (0..segments).map do |i|
      a = Math::PI + Math::PI*i/segments
      [50*Math.cos(a),50*Math.sin(a)]
    end
    inner = (0..segments).map do |i|
      a = Math::PI*i/segments
      [-50*Math.cos(a),-25*Math.sin(a)]
    end
    # Return inner arc from right tip to left tip, avoiding repeated tips.
    outer + inner.reverse[1...-1]
  end

  def inside?(p,poly)
    hit = false
    poly.each_index do |i|
      a,b = poly[i],poly[(i+1)%poly.length]
      return true if G.on_segment?(p,a,b)
      if (a[1]>p[1]) != (b[1]>p[1])
        hit = !hit if p[0] < a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1])
      end
    end
    hit
  end

  def test_crescent_more_than_200_source_edges
    poly = crescent(180)
    assert_operator poly.length,:>,200
    G.validate(poly)
    simplified,distances,margin = G.prepare_boundary(poly,[2]*poly.length)
    assert_operator simplified.length,:<,poly.length
    assert_in_delta 0.01,margin,1.0e-10
    assert distances.all? { |d| (d-2.01).abs < 1.0e-10 }
    cells = G.inset(poly,[2]*poly.length,approximate: true)
    assert_operator G.area(cells),:>,0
    outlines = G.boundaries(cells)
    assert_equal 1,outlines.length
    assert_in_delta G.area(cells),G.area(outlines),0.001
    # Samples must stay inside the exact input and at least 2 m from every source edge.
    samples = outlines.flatten(1)
    samples.each do |p|
      assert inside?(p,poly)
      minimum = poly.each_index.map { |i| G.segment_distance(p,poly[i],poly[(i+1)%poly.length]) }.min
      assert_operator minimum+1.0e-5,:>=,2
    end
  end

  def test_parameter_change_vertices_are_preserved
    poly = crescent(180)
    distances = Array.new(poly.length,2.0)
    distances[37] = 4.0
    simplified,values,_margin = G.prepare_boundary(poly,distances)
    assert_includes simplified,poly[37]
    assert_includes simplified,poly[38]
    i = simplified.index(poly[37])
    assert_in_delta 4.01,values[i],1.0e-10
  end

  def test_dense_collinear_cad_rectangle
    poly = []
    corners = [[0,0],[100,0],[100,60],[0,60]]
    corners.each_index do |i|
      a,b = corners[i],corners[(i+1)%4]
      100.times { |j| t=j/100.0; poly << [a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])] }
    end
    cells = G.inset(poly,[5]*poly.length,approximate: true)
    assert_in_delta (100-10.02)*(60-10.02),G.area(cells),0.001
    assert_equal 4,G.boundaries(cells).first.length
  end

  def test_original_segment_simplification_error_is_bounded
    poly = crescent(240)
    simplified,_distances,_margin = G.prepare_boundary(poly,[3]*poly.length)
    poly.each do |p|
      nearest = simplified.each_index.map { |i| G.segment_distance(p,simplified[i],simplified[(i+1)%simplified.length]) }.min
      assert_operator nearest,:<=,G::CURVE_TOLERANCE+1.0e-6
    end
  end

  def test_large_boundary_limit_has_explicit_error
    assert_raises(ArgumentError) { G.validate(Array.new(5001) { |i| [i.to_f,0.0] }) }
  end
end

class CurveNumericalToleranceTest < Minitest::Test
  G = MattWu::BuildableEnvelope::Geometry

  def test_sub_tolerance_void_is_not_a_building_hole
    square = [[0,0],[10,0],[10,10],[0,10]]
    void = [[5,5],[5.00001,5],[5.00001,5.00001],[5,5.00001]]
    cells = G.subtract(square,void)
    outline = G.boundaries(cells)
    assert_equal 1,outline.length
    assert_equal 4,outline.first.length
    assert_in_delta 100,G.area(outline),G::AREA_EPS
  end

  def test_real_hole_is_still_rejected
    square = [[0,0],[10,0],[10,10],[0,10]]
    hole = [[4,4],[6,4],[6,6],[4,6]]
    assert_raises(ArgumentError) { G.boundaries(G.subtract(square,hole)) }
  end
end
