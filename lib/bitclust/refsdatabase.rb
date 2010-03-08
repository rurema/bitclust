#
# bitclust/refsdatabase.rb
#
# This program is free software.
# You can distribute this program under the Ruby License.
#

module BitClust
  class RefsDatabase
    def self.load(src)
      if src.respond_to?(:to_str)
        buf = fopen(src.to_str, 'r:EUC-JP'){|f| f.read}
      elsif src.respond_to?(:to_io)
        buf = src.to_io.read
      else
        buf = src.read
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
        io = fopen(path, 'w:EUC-JP')
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
        if /\A={1,4}\[a:(\w+)\] *(.*)/ =~ l
          entry.labels.each{|name|
            self[entry.class.type_id, name, $1] = $2
          }
        end
      }
    end
  end
end
