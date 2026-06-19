# frozen_string_literal: true
#
# bitclust/search_index_generator.rb
#
# Builds a client-side search index compatible with RDoc's Aliki theme.
#
# The index is a flat array of entries:
#
#   { name:, full_name:, type:, path: }
#
# serialized as a JavaScript assignment so it can be loaded over file://
# without tripping the browser's CORS check on JSON files:
#
#   var search_data = { "index": [ ... ] };
#
# This mirrors the static layout produced by StatichtmlCommand so that the
# +path+ of each entry points at the file actually generated there.
#

require 'json'
require 'bitclust/nameutils'

module BitClust
  class SearchIndexGenerator
    include NameUtils

    # Maps BitClust method typenames onto the type vocabulary understood by
    # Aliki's searcher (class/module/constant/class_method/instance_method).
    # Module functions are callable as singleton methods, so they are indexed
    # as class methods; special variables have no Aliki equivalent and keep
    # their own label (the searcher only uses the type for ranking).
    TYPENAME_TO_SEARCH_TYPE = {
      singleton_method: 'class_method',
      module_function:  'class_method',
      instance_method:  'instance_method',
      constant:         'constant',
      special_variable: 'variable',
    }.freeze

    def initialize(suffix: '.html', fs_casesensitive: false)
      @suffix = suffix
      @fs_casesensitive = fs_casesensitive
    end

    # Builds the search index as an array of entry hashes.
    # +db+ is a MethodDatabase; +fdb+ is an optional FunctionDatabase (C API).
    def build_index(db, fdb = nil)
      index = []
      index.concat(class_entries(db))
      index.concat(method_entries(db))
      index.concat(library_entries(db))
      index.concat(document_entries(db))
      index.concat(function_entries(fdb)) if fdb
      index
    end

    # Serializes the index as an Aliki-compatible +search_data.js+ body.
    def to_js(db, fdb = nil)
      "var search_data = #{JSON.generate(index: build_index(db, fdb))};"
    end

    private

    def class_entries(db)
      db.classes.sort.reject(&:dummy?).map do |c|
        {
          name:      c.name,
          full_name: c.name,
          type:      c.type.to_s,
          path:      "class/#{encode(c.name)}#{@suffix}",
        }
      end
    end

    def method_entries(db)
      seen = {}
      result = []
      db.methods.each do |entry|
        next if entry.undefined?

        type = TYPENAME_TO_SEARCH_TYPE[entry.typename]
        next unless type

        cname = entry.klass.name
        tmark = entry.typemark
        tchar = entry.typechar
        entry.names.each do |mname|
          path = "method/#{encode(cname)}/#{tchar}/#{encode(mname)}#{@suffix}"
          next if seen[path]

          seen[path] = true
          full_name = (tmark == '$' ? '' : cname) + tmark + mname
          result << { name: mname, full_name: full_name, type: type, path: path }
        end
      end
      result
    end

    def library_entries(db)
      db.libraries.sort.map do |lib|
        {
          name:      lib.name,
          full_name: lib.name,
          type:      'library',
          path:      "library/#{encode(lib.name)}#{@suffix}",
        }
      end
    end

    def document_entries(db)
      db.docs.map do |doc|
        slug  = doc.name
        title = doc.title
        # Prose pages are identified by a Japanese title, so index the title
        # (for human queries) together with the slug (for identifier queries).
        label = (title && !title.empty? && title != slug) ? "#{title} (#{slug})" : slug
        {
          name:      label,
          full_name: label,
          type:      'document',
          path:      "doc/#{encode(slug)}#{@suffix}",
        }
      end
    end

    def function_entries(fdb)
      fdb.functions.sort.map do |func|
        {
          name:      func.name,
          full_name: func.name,
          type:      'function',
          path:      "function/#{func.name}#{@suffix}",
        }
      end
    end

    def encode(str)
      @fs_casesensitive ? encodename_url(str) : encodename_fs(str)
    end
  end
end
