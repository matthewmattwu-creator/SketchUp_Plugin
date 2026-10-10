# encoding: UTF-8
require_relative 'geometry'
module MattWu
  module BuildableEnvelope
    # Recognition only: never snap, simplify, bridge gaps, or change source entities.
    module Boundary
      extend self
      def canonical(poly)
        oriented = Geometry.signed_area(poly) < 0 ? poly.reverse : poly.dup
        oriented.rotate(oriented.each_index.min_by { |i| oriented[i] })
      end

      def point_inside?(p, poly)
        hit = false
        poly.each_index do |i|
          a,b = poly[i],poly[(i+1)%poly.length]
          if p[0] >= [a[0],b[0]].min-Geometry::EPS && p[0] <= [a[0],b[0]].max+Geometry::EPS &&
            p[1] >= [a[1],b[1]].min-Geometry::EPS && p[1] <= [a[1],b[1]].max+Geometry::EPS
            return true if Geometry.on_segment?(p,a,b)
          end
          if (a[1]>p[1]) != (b[1]>p[1])
            hit = !hit if p[0] < a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1]).to_f
          end
        end
        hit
      end

      def build(points)
        unless points.is_a?(Array) && points.length >= 3 &&
          points.all? { |p| p.is_a?(Array) && p.length == 3 && p.all? { |v| v.is_a?(Numeric) && v.finite? } }
          raise ArgumentError, '红线必须包含至少三个有限三维坐标'
        end
        origin = points.min
        raise ArgumentError, '仅支持水平红线，标高误差不得超过 1 毫米' if points.any? { |p| (p[2]-origin[2]).abs > 0.001 }
        poly = points.map { |p| [p[0]-origin[0],p[1]-origin[1]] }
        Geometry.validate(poly)
        { points: canonical(poly), origin: origin.dup, source_points: points.map(&:dup) }
      end

      # Classify all non-touching closed loops by containment depth.
      # Even depths are parcels/islands; direct odd children are their holes.
      def regions(loops)
        built = loops.map { |points| build(points) }
        return [] if built.empty?
        anchor = built.first[:origin]
        polys = built.map { |b| b[:points].map { |p| [p[0]+b[:origin][0]-anchor[0],p[1]+b[:origin][1]-anchor[1]] } }
        parents = Array.new(built.length)
        built.each_index do |i|
          built.each_index do |j|
            next unless j > i
            next if (built[i][:origin][2]-built[j][:origin][2]).abs > 0.001
            a,b = polys[i],polys[j]
            touching = a.each_index.any? do |ai|
              b.each_index.any? { |bi| Geometry.intersects?(a[ai],a[(ai+1)%a.length],b[bi],b[(bi+1)%b.length]) }
            end
            raise ArgumentError, '闭合红线相交、重复或接触，无法唯一确定外环和内孔' if touching
          end
          containers = built.each_index.select do |j|
            j != i && (built[i][:origin][2]-built[j][:origin][2]).abs <= 0.001 &&
              point_inside?(polys[i].first,polys[j])
          end
          parents[i] = containers.min_by { |j| Geometry.signed_area(polys[j]).abs }
        end
        depths = built.each_index.map do |i|
          depth, cursor = 0,parents[i]
          until cursor.nil?
            depth += 1
            raise ArgumentError, '红线嵌套关系异常' if depth > built.length
            cursor = parents[cursor]
          end
          depth
        end
        built.each_index.select { |i| depths[i].even? }.map do |i|
          b = built[i]
          holes = built.each_index.select { |j| parents[j] == i }.map do |j|
            canonical(polys[j].map { |p| [p[0]+anchor[0]-b[:origin][0],p[1]+anchor[1]-b[:origin][1]] })
          end
          b.merge(source_rings: [loops[i]] + built.each_index.select { |j| parents[j] == i }.map { |j| loops[j] },
            holes: holes.sort_by(&:first), area: Geometry.signed_area(b[:points]).abs -
            holes.sum { |h| Geometry.signed_area(h).abs })
        end.sort_by { |b| b[:origin] }
      end

      # Independent check against every original segment, in meters.
      def verify_outlines!(outlines, poly, setbacks)
        raise ArgumentError, '退线数量必须与原红线边数一致' unless setbacks.length == poly.length
        tolerance = 1.0e-6
        source_bounds = poly.each_index.map do |j|
          c,d = poly[j],poly[(j+1)%poly.length]
          [[c[0],d[0]].min,[c[0],d[0]].max,[c[1],d[1]].min,[c[1],d[1]].max]
        end
        outlines.each do |outline|
          Geometry.validate(outline)
          outline.each_index do |i|
            a,b = outline[i],outline[(i+1)%outline.length]
            [a,b,[(a[0]+b[0])/2.0,(a[1]+b[1])/2.0]].each do |p|
              raise ArgumentError, '结果超出原红线，已取消此地块' unless point_inside?(p,poly)
            end
            # A segment can exit through a concave vertex without a strict
            # crossing. Check intervals split at every source vertex on it.
            dx,dy = b[0]-a[0],b[1]-a[1]
            length2 = (dx*dx+dy*dy).to_f
            cuts = [0.0,1.0]
            bounds = [[a[0],b[0]].min,[a[0],b[0]].max,[a[1],b[1]].min,[a[1],b[1]].max]
            poly.each do |p|
              next if p[0] < bounds[0]-Geometry::EPS || p[0] > bounds[1]+Geometry::EPS ||
                p[1] < bounds[2]-Geometry::EPS || p[1] > bounds[3]+Geometry::EPS
              next unless Geometry.on_segment?(p,a,b)
              cuts << [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length2,0.0].max,1.0].min
            end
            cuts.uniq.sort.each_cons(2) do |first,last|
              t = (first+last)/2.0
              unless point_inside?([a[0]+t*dx,a[1]+t*dy],poly)
                raise ArgumentError, '结果边穿越原红线凹口，已取消此地块'
              end
            end
            poly.each_index do |j|
              sb = source_bounds[j]
              clearance = setbacks[j]+tolerance
              # Disjoint expanded boxes prove adequate distance; only nearby
              # original segments need exact crossing and distance calculations.
              next if bounds[1]+clearance < sb[0] || sb[1]+clearance < bounds[0] ||
                bounds[3]+clearance < sb[2] || sb[3]+clearance < bounds[2]
              c,d = poly[j],poly[(j+1)%poly.length]
              x,y,u,v = Geometry.cross(a,b,c),Geometry.cross(a,b,d),Geometry.cross(c,d,a),Geometry.cross(c,d,b)
              if x*y < 0 && u*v < 0
                raise ArgumentError, '结果边穿越原红线，已取消此地块'
              end
              minimum = if Geometry.intersects?(a,b,c,d)
                0.0
              else
                [Geometry.segment_distance(a,c,d),Geometry.segment_distance(b,c,d),
                 Geometry.segment_distance(c,a,b),Geometry.segment_distance(d,a,b)].min
              end
              if minimum+tolerance < setbacks[j]
                raise ArgumentError, '结果不满足原始边段退线，已取消此地块'
              end
            end
          end
        end
        true
      end

      # Use topological vertex identity; visually close endpoints stay distinct.
      # A bad connected component must not discard another valid closed parcel.
      def cycles(vertices, edges)
        adjacency = Hash.new { |h,k| h[k] = [] }
        edges.each_with_index { |(a,b),i| adjacency[a] << i; adjacency[b] << i }
        remaining = (0...edges.length).to_a
        loops, errors = [],[]
        until remaining.empty?
          pending = [remaining.first]
          component = []
          until pending.empty?
            index = pending.pop
            next if component.include?(index)
            component << index
            edges[index].each { |v| pending.concat(adjacency[v] - component) }
          end
          remaining -= component
          ids = component.flat_map { |i| edges[i] }.uniq
          bad = ids.reject { |id| adjacency[id].length == 2 }
          unless bad.empty?
            open = bad.count { |id| adjacency[id].length == 1 }
            branch = bad.count { |id| adjacency[id].length > 2 }
            errors << "红线连通部分未闭合或分叉（开口端点 #{open}，分叉顶点 #{branch}）；未自动补线"
            next
          end
          start = ids.min_by { |id| vertices.fetch(id) }
          edge = adjacency[start].min_by { |i| vertices.fetch((edges[i] - [start]).first || start) }
          current, points, visited = start,[],[]
          loop do
            raise ArgumentError, '红线连接异常' if visited.include?(edge)
            points << vertices.fetch(current).dup
            visited << edge
            a,b = edges[edge]
            current = a == current ? b : a
            break if current == start
            edge = (adjacency[current] - visited).first
            raise ArgumentError, '红线连接异常' unless edge
          end
          loops << points
        end
        [loops,errors]
      end
    end
  end
end
