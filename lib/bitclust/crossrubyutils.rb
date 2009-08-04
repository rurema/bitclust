#
# bitclust/crossrubyutils.rb
#
# Copyright (c) 2006 Minero Aoki
#

module BitClust

  module CrossRubyUtils

    private

    def print_crossruby_table(&block)
      print_table(*build_crossruby_table(&block))
    end

    def print_table(vers, table)
      thcols = ([20] + table.keys.map {|s| s.size }).max
      print_record thcols, '', vers.map {|ver| version_id(ver) }
      crossrubyutils_sort_entries(table.keys).each do |c|
        print_record thcols, c, vers.map {|ver| table[c][ver] ? 'o' : '-' }
      end
    end

    def crossrubyutils_sort_entries(ents)
      ents.sort
    end

    def print_record(thcols, th, tds)
      printf "%-#{thcols}s ", th
      puts tds.map {|td| '%4s' % td }.join('')
    end

    def version_id(ver)
      ver.split[1].tr('.', '')
    end

    def get_ruby(version)      
      forall_ruby(ENV['PATH']) do |ruby, |
        v = `#{ruby} -e 'print RUBY_VERSION'`
        patch = `#{ruby} -e 'print RUBY_PATCHLEVEL if defined? RUBY_PATCHLEVEL'`
        if version == v or ( version == v.succ and patch == '5000')
          return ruby
        end
      end
      return nil
    end
    
    def build_crossruby_table
      ENV.delete 'RUBYOPT'
      ENV.delete 'RUBYLIB'
      vers = []
      table = {}
      forall_ruby(ENV['PATH']) do |ruby, ver|
        puts "#{version_id(ver)}: #{ver}" if @verbose
        vers.push ver
        yield(ruby).each do |c|
          (table[c] ||= {})[ver] = true
        end
      end
      return vers, table
    end

    def forall_ruby(path, &block)
      rubys(path)\
          .map {|ruby| [ruby, `#{ruby} --version`] }\
          .sort_by {|ruby, verstr| verstr }\
          .each(&block)
    end

    def rubys(path)
      parse_PATH(path).map {|bindir|
        Dir.glob("#{bindir}/ruby-[12t]*").map {|path| File.basename(path) }
      }\
      .flatten.uniq + ['ruby']
    end

    def parse_PATH(str)
      str.split(':').map {|path| path.empty? ? '.' : path }
    end

  end

end
