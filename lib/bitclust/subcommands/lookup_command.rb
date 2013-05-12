require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class LookupCommand < Subcommand
      def initialize
        super
        @format = :text
        @type = nil
        @key = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} lookup (--library|--class|--method|--function) [--html] <key>"
        @parser.on('--library=NAME', 'Lookup library.') {|name|
          @type = :library
          @key = name
        }
        @parser.on('--class=NAME', 'Lookup class.') {|name|
          @type = :class
          @key = name
        }
        @parser.on('--method=NAME', 'Lookup method.') {|name|
          @type = :method
          @key = name
        }
        @parser.on('--function=NAME', 'Lookup function. (C API)') {|name|
          @type = :function
          @key = name
        }
        @parser.on('--html', 'Show result in HTML.') {
          @format = :html
        }
      end

      def parse(argv)
        super
        unless @type
          error "one of --library/--class/--method/--function is required"
        end
        unless argv.empty?
          error "too many arguments"
        end
      end

      def exec(argv, options)
        super
        entry = fetch_entry(@db, @type, @key)
        puts fill_template(get_template(@type, @format), entry)
      end

      def fetch_entry(db, type, key)
        case type
        when :library
          db.fetch_library(key)
        when :class
          db.fetch_class(key)
        when :method
          db.fetch_method(MethodSpec.parse(key))
        when :function
          db.fetch_function(key)
        else
          raise "must not happen: #{type.inspect}"
        end
      end

      def fill_template(template, entry)
        ERB.new(template).result(binding())
      end

      def get_template(type, format)
        template = TEMPLATE[type][format]
        TextUtils.unindent_block(template.lines).join('')
      end

      TEMPLATE = {
        :library => {
          :text => <<-End,
           type: library
           name: <%= entry.name %>
           classes: <%= entry.classes.map {|c| c.name }.sort.join(', ') %>
           methods: <%= entry.methods.map {|m| m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
          :html => <<-End
           <dl>
           <dt>type</dt><dd>library</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>classes</dt><dd><%= entry.classes.map {|c| c.name }.sort.join(', ') %></dd>
           <dt>methods</dt><dd><%= entry.methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
        },
        :class   => {
          :text => <<-End,
           type: class
           name: <%= entry.name %>
           library: <%= entry.library.name %>
           singleton_methods: <%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %>
           instance_methods: <%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %>
           constants: <%= entry.constants.map {|m| m.name }.sort.join(', ') %>
           special_variables: <%= entry.special_variables.map {|m| '$' + m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
          :html => <<-End
           <dl>
           <dt>type</dt><dd>class</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           <dt>singleton_methods</dt><dd><%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %></dd>
           <dt>instance_methods</dt><dd><%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
        },
        :method  => {
          :text => <<-End,
           type: <%= entry.type %>
           name: <%= entry.name %>
           names: <%= entry.names.sort.join(', ') %>
           visibility: <%= entry.visibility %>
           kind: <%= entry.kind %>
           library: <%= entry.library.name %>

           <%= entry.source %>
           End
          :html => <<-End
           <dl>
           <dt>type</dt><dd><%= entry.type %></dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>names</dt><dd><%= entry.names.sort.join(', ') %></dd>
           <dt>visibility</dt><dd><%= entry.visibility %></dd>
           <dt>kind</dt><dd><%= entry.kind %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
        },
        :function => {
          :text => <<-End,
           kind: <%= entry.kind %>
           header: <%= entry.header %>
           filename: <%= entry.filename %>

           <%= entry.source %>
           End
          :html => <<-End
           <dl>
           <dt>kind</dt><dd><%= entry.kind %></dd>
           <dt>header</dt><dd><%= entry.header %></dd>
           <dt>filename</dt><dd><%= entry.filename %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
        }
      }

      def compile_rd(src)
        umap = URLMapper.new(:base_url => 'http://example.com',
                             :cgi_url  => 'http://example.com/view')
        compiler = RDCompiler.new(umap, 2)
        compiler.compile(src)
      end
    end
  end
end
