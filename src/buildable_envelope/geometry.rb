# encoding: UTF-8
# Pure Ruby; coordinates and setbacks in meters. No SketchUp dependency.
module MattWu
  module BuildableEnvelope
    module Geometry
      extend self
      EPS = 1.0e-7
      AREA_EPS = 1.0e-8
      MAX_CELLS = 5000
      ARC_SEGMENTS = 64

      def cross(a, b, c)
        (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])
      end

      def signed_area(poly)
        poly.each_index.sum do |i|
          a, b = poly[i], poly[(i+1)%poly.length]
          a[0]*b[1]-b[0]*a[1]
        end / 2.0
      end

      def distance(a, b)
        Math.hypot(a[0]-b[0], a[1]-b[1])
      end

      def clean(poly)
        out = []
        poly.each { |p| out << p if out.empty? || distance(out.last, p) > EPS }
        out.pop if out.length > 1 && distance(out.first, out.last) <= EPS
        out
      end

      def on_segment?(p, a, b)
        cross(a,b,p).abs <= EPS * [distance(a,b),1.0].max &&
          p[0] >= [a[0],b[0]].min-EPS && p[0] <= [a[0],b[0]].max+EPS &&
          p[1] >= [a[1],b[1]].min-EPS && p[1] <= [a[1],b[1]].max+EPS
      end

      def intersects?(a,b,c,d)
        x, y, u, v = cross(a,b,c),cross(a,b,d),cross(c,d,a),cross(c,d,b)
        return true if x*y < 0 && u*v < 0
        on_segment?(c,a,b) || on_segment?(d,a,b) ||
          on_segment?(a,c,d) || on_segment?(b,c,d)
      end

      def validate(poly)
        raise ArgumentError, '至少需要三条边' if poly.length < 3
        raise ArgumentError, '边界坐标无效' unless poly.flatten.all? { |v| v.is_a?(Numeric) && v.finite? }
        raise ArgumentError, '地块边数超过 200，请先简化 CAD 边界' if poly.length > 200
        n = poly.length
        n.times do |i|
          raise ArgumentError, '存在零长度边' if distance(poly[i],poly[(i+1)%n]) <= EPS
          ((i+1)...n).each do |j|
            next if j == i+1 || (i == 0 && j == n-1)
            raise ArgumentError, '边界自交或重复接触' if intersects?(poly[i],poly[(i+1)%n],poly[j],poly[(j+1)%n])
          end
        end
        raise ArgumentError, '地块面积过小' if signed_area(poly).abs <= AREA_EPS
      end

      def inside_triangle?(p,a,b,c)
        cross(a,b,p) >= -EPS && cross(b,c,p) >= -EPS && cross(c,a,p) >= -EPS
      end

      def triangulate(poly)
        work = signed_area(poly) < 0 ? poly.reverse : poly.dup
        # Remove collinear vertices only for triangulation; setback edge numbering is retained.
        loop do
          index = work.each_index.find do |i|
            cross(work[(i-1)%work.length],work[i],work[(i+1)%work.length]).abs <= EPS &&
              on_segment?(work[i],work[(i-1)%work.length],work[(i+1)%work.length])
          end
          break unless index && work.length > 3
          work.delete_at(index)
        end
        cells = []
        while work.length > 3
          index = work.each_index.find do |i|
            a,b,c = work[(i-1)%work.length],work[i],work[(i+1)%work.length]
            cross(a,b,c) > EPS && work.each_index.none? do |j|
              next false if [i,(i-1)%work.length,(i+1)%work.length].include?(j)
              inside_triangle?(work[j],a,b,c)
            end
          end
          raise ArgumentError, '边界无法可靠三角化，请检查 CAD' unless index
          cells << [work[(index-1)%work.length],work[index],work[(index+1)%work.length]]
          work.delete_at(index)
        end
        cells << work
        cells
      end

      # Partition by a directed line. The first output lies to its left.
      def split(poly,a,b)
        left, right = [], []
        length = distance(a,b)
        poly.each_index do |i|
          p,q = poly[i],poly[(i+1)%poly.length]
          dp,dq = cross(a,b,p)/length,cross(a,b,q)/length
          dp = 0.0 if dp.abs < EPS
          dq = 0.0 if dq.abs < EPS
          left << p if dp >= 0
          right << p if dp <= 0
          if dp*dq < 0
            t = dp/(dp-dq)
            hit = [p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])]
            left << hit
            right << hit
          end
        end
        [left,right].map do |part|
          part = clean(part)
          part.length >= 3 && signed_area(part).abs > AREA_EPS ? part : []
        end
      end

      # Subtract a convex CCW cutter, yielding disjoint convex pieces.
      def subtract(poly,cutter)
        pending, kept = poly, []
        cutter.each_index do |i|
          break if pending.empty?
          pending, outside = split(pending,cutter[i],cutter[(i+1)%cutter.length])
          kept << outside unless outside.empty?
        end
        kept
      end

      def overlaps_bounds?(a,b)
        [0,1].all? do |axis|
          a.map { |p| p[axis] }.min <= b.map { |p| p[axis] }.max+EPS &&
            b.map { |p| p[axis] }.min <= a.map { |p| p[axis] }.max+EPS
        end
      end

      def disk(center,radius)
        # Circumscribed polygon: never grants extra buildable area inside the clearance circle.
        r = radius/Math.cos(Math::PI/ARC_SEGMENTS)
        ARC_SEGMENTS.times.map do |i|
          angle = 2*Math::PI*i/ARC_SEGMENTS
          [center[0]+r*Math.cos(angle),center[1]+r*Math.sin(angle)]
        end
      end

      def inset(poly, setbacks)
        validate(poly)
        raise ArgumentError, '退线数量必须与边数一致' unless setbacks.length == poly.length
        raise ArgumentError, '退线须为非负有限数值' unless setbacks.all? { |v| v.is_a?(Numeric) && v.finite? && v >= 0 }
        cells = triangulate(poly)
        cutters = []
        poly.each_index do |i|
          a,b,d = poly[i],poly[(i+1)%poly.length],setbacks[i]
          next if d <= 0
          length = distance(a,b)
          nx,ny = -(b[1]-a[1])/length*d,(b[0]-a[0])/length*d
          cutters << [[a[0]-nx,a[1]-ny],[b[0]-nx,b[1]-ny],
                      [b[0]+nx,b[1]+ny],[a[0]+nx,a[1]+ny]]
        end
        poly.each_index do |i|
          previous = (i-1)%poly.length
          following = (i+1)%poly.length
          a,b,c = poly[previous],poly[i],poly[following]
          straight = cross(a,b,c).abs <= EPS &&
            (b[0]-a[0])*(c[0]-b[0])+(b[1]-a[1])*(c[1]-b[1]) > 0
          # Adjacent equal-width strips already cover a collinear vertex disk.
          # Omitting it prevents approximation dents along CAD-split straight edges.
          next if straight && (setbacks[i]-setbacks[previous]).abs <= EPS
          radius = [setbacks[i],setbacks[previous]].max
          cutters << disk(poly[i],radius) if radius > 0
        end
        cutters.each do |cutter|
          cells = cells.flat_map { |cell| overlaps_bounds?(cell,cutter) ? subtract(cell,cutter) : [cell] }
          raise ArgumentError, '几何过于复杂，请简化地块或分批生成' if cells.length > MAX_CELLS
          break if cells.empty?
        end
        cells
      end

      def area(cells)
        cells.sum { |cell| signed_area(cell).abs }
      end
    end
  end
end
