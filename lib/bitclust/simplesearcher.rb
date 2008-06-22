require 'bitclust/nameutils'
require 'bitclust/methodid'

module BitClust
  module SimpleSearcher
    include NameUtils

    module_function
    
    def search_pattern(db, pat)
      return [] if pat.empty?
      cname, type, mname = parse_method_spec_pattern(pat)
      ret = cs = ms = []
      if cname and not cname.empty?
        if mname
          ms = find_class_method(db, cname, type, mname)
          cs += find_class(db, cname + '::' + mname) if /\A[A-Z]/ =~ mname
        else
          cs = find_class(db, cname)
#          ms = find_methods(db, cname)        
        end
      elsif type == '$'
        ms = find_special_vars(db, mname)
      else
        ms = find_methods(db, mname)        
      end
      ms = ms.sort_by{|e| [e.library.name, e.klass.name] }
      cs = cs.sort_by{|e| [e.library.name] }
      cs + ms
    end

    def find_class(db, cname)
      db.classes.find_all{|c| /\b#{Regexp.escape(cname)}\w*\z/ =~ c.name }
    end
    
    def find_class_method(db, cname, type, mname)
      ret = []
      db.classes.each{|c|
        if /\b#{Regexp.escape(cname)}/ =~ c.name
          ret += c.methods.find_all{|m|
            m.names.any?{|n| /\A#{Regexp.escape(mname)}/ =~ n }
          }
        end
      }
      ret
    end

    def find_methods(db, mname)
      db.methods.find_all{|m|
        m.names.any?{|n| /\A#{Regexp.escape(mname)}/ =~ n }
      }
    end

    def find_special_vars(db, mname)
      db.get_class('Kernel').special_variables.find_all{|m|
        m.names.any?{|n| /\A#{Regexp.escape(mname)}/ =~ n }
      }
    end
    
    def parse_method_spec_pattern(pat)
      return pat, nil, nil if /\A[A-Z]\w*\z/ =~ pat
      _m, _t, _c = pat.reverse.split(/(::|[\#,]\.|\.[\#,]|[\#\.\,$])/, 2)
      c = _c.reverse if _c
      t = _t.tr(',', '#').sub(/\#\./, '.#') if _t
      m = _m.reverse
      return c, t, m
    end

  end
end
