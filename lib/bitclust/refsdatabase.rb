
module BitClust
  class RefsDatabase
    def self.load(s)
      if s.respond_to?(:to_str)
        buf = File.read(s.to_str)
      elsif s.respond_to?(:to_io)
        buf = s.to_io.read
      else
        buf = s.read
      end

      refs = self.new
      buf.each_line{|l|
        if /((?:\\,|[^,])+),((?:\\,|[^,])+),((?:\\,|[^,])+),((?:\\,|[^,])+)\n/ =~ l
          type, id, linkid, desc = [$1, $2, $3, $4].map{|e| e.gsub(/\\(.)/){|s| $1 == ',' ? ',' : s } }
          refs[type, id, linkid] = desc          
        end
      }
      refs
    end
    
    def initialize
      @h = {}
    end

    def []=(type, mid, linkid, desc)
      @h[[type.to_s, mid, linkid]] = desc
    end

    def [](type, mid, linkid)
      @h[[type.to_s, mid, linkid]]
    end

    def save(s)
      if s.respond_to?(:to_str)
        path = s.to_str
        io = File.open(path, 'w')
      elsif s.respond_to?(:to_io)
        io = s.to_io
      else
        io = s
      end

      @h.each{|k, v|
        io.write(  [k, v].flatten.map{|e| e.gsub(/,/, '\\,') }.join(',') + "\n" )
      }
    end

    def extract(entry)      
      entry.source.each_line{|l|
        if /\A={1,4}\[a:(\w+)\] *(.*)\n/ =~ l
          entry.labels.each{|name|
            self[entry.class.type_id, name, $1] = $2
          }
        end
      }
    end
  end
end
