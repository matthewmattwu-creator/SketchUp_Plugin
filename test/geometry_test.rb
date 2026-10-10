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
