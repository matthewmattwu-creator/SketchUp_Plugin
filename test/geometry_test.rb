require 'minitest/autorun'
require_relative '../src/buildable_envelope/geometry'
class GeometryTest < Minitest::Test
  G = MattWu::BuildableEnvelope::Geometry
  RECT = [[0,0],[100,0],[100,60],[0,60]].freeze

  def test_rectangle_and_capacity
    cells = G.inset(RECT,[5,5,5,5])
    assert_in_delta 4500,G.area(cells),1.0e-5
    assert_in_delta 45000,G.area(cells)*(36/3.6).floor,1.0e-4
  end

  def test_different_edges
    assert_in_delta 90*52,G.area(G.inset(RECT,[2,3,6,7])),1.0e-5
  end

  def test_winding_and_zero
    assert_in_delta 6000,G.area(G.inset(RECT.reverse,[0,0,0,0])),1.0e-6
    assert_in_delta 4500,G.area(G.inset(RECT.reverse,[5,5,5,5])),1.0e-5
  end

  def test_excessive_setback
    assert_empty G.inset(RECT,[31,0,31,0])
    assert_empty G.inset(RECT,[100,100,100,100])
  end

  def test_invalid_inputs
    assert_raises(ArgumentError) { G.inset(RECT,[-1,0,0,0]) }
    assert_raises(ArgumentError) { G.inset(RECT,[0]) }
    assert_raises(ArgumentError) { G.inset(RECT,[Float::NAN,0,0,0]) }
    assert_raises(ArgumentError) { G.inset([[0,0],[5,5],[0,5],[5,0]],[0]*4) }
    assert_raises(ArgumentError) { G.inset([[0,0],[0,0],[5,5]],[0]*3) }
  end

  def test_concave_clearance
    poly = [[0,0],[40,0],[40,15],[15,15],[15,40],[0,40]]
    d = [2,3,2,4,3,2]
    cells = G.inset(poly,d)
    assert_operator G.area(cells),:>,0
    assert_operator G.area(cells),:<,G.signed_area(poly)
    cells.flatten(1).each do |p|
      poly.each_index do |i|
        assert_operator segment_distance(p,poly[i],poly[(i+1)%poly.length])+1.0e-5,:>=,d[i]
      end
    end
  end

  def test_narrow_neck_disconnects
    poly = [[0,0],[20,0],[20,8],[40,8],[40,0],[60,0],[60,20],[40,20],[40,12],[20,12],[20,20],[0,20]]
    cells = G.inset(poly,[3]*poly.length)
    assert_operator G.area(cells),:>,300
    assert cells.all? { |cell| cell.all? { |p| p[0] < 20 } || cell.all? { |p| p[0] > 40 } }
    assert cells.any? { |cell| cell.first[0] < 20 }
    assert cells.any? { |cell| cell.first[0] > 40 }
  end

  def test_convex_subtraction_conserves_area
    square = [[0,0],[10,0],[10,10],[0,10]]
    cutter = [[2,2],[8,2],[8,8],[2,8]]
    assert_in_delta 64,G.area(G.subtract(square,cutter)),1.0e-6
    assert_in_delta 100,G.area(G.subtract(square,[[20,20],[30,20],[30,30],[20,30]])),1.0e-6
  end

  def test_collinear_and_small_scale
    poly = [[0,0],[50,0],[100,0],[100,60],[0,60]]
    assert_in_delta 4500,G.area(G.inset(poly,[5]*5)),1.0e-5
    small = RECT.map { |p| p.map { |v| v/100.0 } }
    assert_in_delta 0.45,G.area(G.inset(small,[0.05]*4)),1.0e-6
  end

  def test_monotonic_area
    poly = [[0,0],[40,0],[40,15],[15,15],[15,40],[0,40]]
    areas = [0,1,2,4,8].map { |d| G.area(G.inset(poly,[d]*poly.length)) }
    areas.each_cons(2) { |a,b| assert_operator b,:<=,a+1.0e-6 }
  end

  def segment_distance(p,a,b)
    dx,dy = b[0]-a[0],b[1]-a[1]
    t = [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy),0].max,1].min
    Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
  end
end

class BoundaryPrismTest < Minitest::Test
  G = MattWu::BuildableEnvelope::Geometry

  def test_rectangle_is_one_clean_four_vertex_outline
    poly = [[0,0],[100,0],[100,60],[0,60]]
    outlines = G.boundaries(G.inset(poly,[5]*4))
    assert_equal 1,outlines.length
    assert_equal 4,outlines.first.length
    assert_in_delta 4500,G.area(outlines),1.0e-5
    assert_closed_prism(outlines.first,36)
  end

  def test_t_junctions_cancel_and_collinear_edges_simplify
    cells = [
      [[0,0],[10,0],[10,10],[0,10]],
      [[10,0],[20,0],[20,5],[10,5]],
      [[10,5],[20,5],[20,10],[10,10]]
    ]
    outlines = G.boundaries(cells)
    assert_equal 1,outlines.length
    assert_equal 4,outlines.first.length
    assert_in_delta 200,G.area(outlines),1.0e-6
    assert_closed_prism(outlines.first,12)
  end

  def test_concave_outline_and_caps
    poly = [[0,0],[40,0],[40,15],[15,15],[15,40],[0,40]]
    [0,2,4].each do |d|
      cells = G.inset(poly,[d]*poly.length)
      outlines = G.boundaries(cells)
      assert_equal 1,outlines.length
      assert_in_delta G.area(cells),G.area(outlines),0.001
      outlines.each { |outline| assert_closed_prism(outline,30) }
    end
  end

  def test_split_ranges_are_independent_solids
    poly = [[0,0],[20,0],[20,8],[40,8],[40,0],[60,0],[60,20],[40,20],[40,12],[20,12],[20,20],[0,20]]
    cells = G.inset(poly,[3]*poly.length)
    outlines = G.boundaries(cells)
    assert_equal 2,outlines.length
    assert_in_delta G.area(cells),G.area(outlines),0.001
    outlines.each { |outline| assert_closed_prism(outline,36) }
  end

  def test_collinear_cad_source_outputs_rectangle
    poly = [[0,0],[50,0],[100,0],[100,60],[0,60]]
    outlines = G.boundaries(G.inset(poly,[5]*5))
    assert_equal 4,outlines.first.length
    assert_in_delta 4500,G.area(outlines),1.0e-5
  end

  def test_small_model_outline
    poly = [[0,0],[1,0],[1,0.6],[0,0.6]]
    outlines = G.boundaries(G.inset(poly,[0.05]*4))
    assert_equal 4,outlines.first.length
    assert_closed_prism(outlines.first,0.36)
  end

  def test_no_buildable_range_has_no_shell
    assert_empty G.boundaries([])
  end

  def test_near_identical_partition_vertices_weld
    cells = [[[0,0],[10,0],[10,10],[0,10]],[[10+1.0e-8,0],[20,0],[20,10],[10+1.0e-8,10]]]
    outlines = G.boundaries(cells)
    assert_equal 1,outlines.length
    assert_equal 4,outlines.first.length
    assert_in_delta 200,G.area(outlines),1.0e-5
  end

  def assert_closed_prism(outline,height)
    mesh = G.prism(outline,height)
    directed = Hash.new(0)
    mesh[:faces].each do |face|
      face.each_index do |i|
        a,b = face[i],face[(i+1)%face.length]
        directed[[a,b]] += 1
      end
    end
    directed.each { |(a,b),count| assert_equal count,directed[[b,a]] }
    assert directed.values.all? { |v| v == 1 }
    volume = mesh[:faces].sum do |face|
      a = mesh[:points][face.first]
      (1...face.length-1).sum do |i|
        b,c = mesh[:points][face[i]],mesh[:points][face[i+1]]
        (a[0]*(b[1]*c[2]-b[2]*c[1])+
         a[1]*(b[2]*c[0]-b[0]*c[2])+
         a[2]*(b[0]*c[1]-b[1]*c[0]))/6.0
      end
    end
    assert_in_delta G.signed_area(outline)*height,volume,0.001
  end
end
