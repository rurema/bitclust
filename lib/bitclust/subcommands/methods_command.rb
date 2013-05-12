require 'pathname'
require 'optparse'

require 'bitclust'
require 'bitclust/crossrubyutils'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class MethodsCommand < Subcommand
      include CrossRubyUtils

      def initialize
        super
        @requires = []
        @verbose = false
        @version = RUBY_VERSION
        @mode = :list
        @target = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <classname>"
        @parser.on('-r LIB', 'Requires library LIB') {|lib|
          @requires.push lib
        }
        @parser.on('-v', '--verbose', "Prints each ruby's version") {
          @verbose = true
        }
        @parser.on('--diff=RDFILE', 'RD file name') {|path|
          @mode = :diff
          @target = path
        }
        @parser.on('-c', '') {
          @content = true
          require 'bitclust/ridatabase'
        }
        @parser.on('--ruby=[VER]', "The version of Ruby interpreter"){|version|
          @version = version
        }
        @parser.on('--ri-database', 'The path of ri database'){|path|
          @ri_path = path
        }
      end

      def parse(argv)
        super
        option_error("wrong number of arguments") unless argv.size == 1
      end

      def exec(argv, options)
        classname = argv[0]
        case @mode
        when :list
          print_crossruby_table {|ruby| defined_methods(ruby, classname) }
        when :diff
          unless ruby = get_ruby(@version)
            raise "Not found Ruby interpreter of the given version"
          end
          keys = defined_methods(ruby, classname)
          lib = RRDParser.parse_stdlib_file(@target, { 'version' => @version })
          c = lib.fetch_class(classname)
          list0 = lib.classes.find_all{|c0| /\A#{classname}\b/o =~ c0.name }
          list0 = c.entries + list0
          list = list0.map {|ent| ent.labels.map {|n| expand_mf(n) } }.flatten
          if @content
            ri = @ri_path ? RiDatabase.open(@ri_path, nil) : RiDatabase.open_system_db
            ri.current_class = c.name
            mthds = ( ri.singleton_methods + ri.instance_methods )
            fmt = Formatter.new
            (keys - list).sort.each do |name|
              mthd = mthds.find{|m| name == m.fullname }
              if mthd
                puts fmt.method_info(mthd.entry)
              else
                name = name.sub(/\A\w+#/, '')
                puts "--- #{name}\n\#@todo\n\n"
              end
            end
          else
            (keys - list).sort.each do |name|
              puts "-#{name}"
            end
            (list - keys).sort.each do |name|
              puts "+#{name}"
            end
          end
        else
          raise "must not happen: #{mode.inspect}"
        end
      end

      def expand_mf(n)
        if /\.\#/ =~ n
          [n.sub(/\.\#/, '.'), n.sub(/\.\#/, '#')]
        else
          n
        end
      end

      def crossrubyutils_sort_entries(ents)
        ents.sort_by {|m| m_order(m) }
      end

      ORDER = { '.' => 1, '#' => 2, '::' => 3 }

      def m_order(m)
        m, t, c = *m.reverse.split(/(\#|\.|::)/, 2)
        [ORDER[t] || 0, m.reverse]
      end

      def defined_methods(ruby, classname)
        req = @requires.map {|lib| "-r#{lib}" }.join(' ')
        avoid_tracer = ""
        avoid_tracer = "Tracer.off" if @requires.include?("tracer")
        case classname
        when 'Object'
          script = <<-SCRIPT
            c = #{classname}
            c.singleton_methods(false).each do |m|
              puts "#{classname}.\#{m}"
            end
            c.instance_methods(true).each do |m|
              puts "#{classname}\\#\#{m}"
            end
          SCRIPT
        when 'Kernel'
          script = <<-SCRIPT
            c = #{classname}
            c.singleton_methods(true).each do |m|
              puts "#{classname}.\#{m}"
            end
            ( c.private_instance_methods(false) && c.methods(false) ).each do |m|
              puts "#{classname}\\#\#{m}"
            end
            Object::constants.delete_if{|c| cl = Object.const_get(c).class; cl == Class or cl == Module }.each do |m|
              puts "#{classname}::\#{m}"
            end
            global_variables.each do |m|
              puts "#{classname}\#{m}"
            end
          SCRIPT
        else
          script = <<-SCRIPT
            #{avoid_tracer}
            c = #{classname}
            c.singleton_methods(false).each do |m|
              puts "#{classname}.\#{m}"
            end
            c.instance_methods(false).each do |m|
              puts "#{classname}\\#\#{m}"
            end
            c.ancestors.map {|mod| mod.constants }.inject {|r,n| r-n }.each do |m|
              puts "#{classname}::\#{m}"
            end
          SCRIPT
        end
        `#{ruby} #{req} -e '#{script}'`.split
      end
    end
  end
end
