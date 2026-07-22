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
# Singleton methods and module functions (full_name holding a literal "."/
# ".#"/"?.", e.g. "File.open", "Kernel.#open", "Kernel?.open" -- see #250)
# additionally carry a +match_name+: full_name with "?." folded to ".#" and
# every "." turned into "::". This mirrors the "." -> "::" rewrite the
# vendored Aliki ranker's parseQuery() applies to the *query* text (RDoc's
# own full_names use "::" for class methods), so search_init.js/search_page.js
# can feature-detect-wrap computeScore() to compare like-for-like without
# ever touching the displayed full_name. See bitclust#279.
#
#   { name:, full_name:, type:, path:, match_name: }
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

    # Doc pages (manual/doc/**/*.md) are prose, so language keywords such as
    # "defined?", "undef" or "alias" (see rurema/doctree#2352) are never
    # indexed as a class/method/library. They do, however, live at their own
    # {#id}-anchored heading within a doc page (e.g. spec/def.md's "defined?"
    # section). Rather than hardcoding a keyword list, scan every doc page for
    # ATX headings carrying an explicit {#id} anchor -- the same anchors
    # [ref:d:...] cross references already rely on -- and index each one
    # individually so a keyword search can jump straight to its section.
    # Headings without an explicit anchor aren't linkable, so they are
    # skipped; a "# comment" that happens to open a line inside a fenced code
    # block is not a heading at all, so fenced regions are skipped wholesale.
    ANCHORED_HEADING_RE = /\A(\#{1,6})[ \t]+(.*?)(?:[ \t]+\{#([\w-]+)\})?[ \t]*\z/.freeze
    FENCE_START_RE = /\A`{3,}/.freeze

    def initialize(suffix: '.html', fs_casesensitive: false)
      @suffix = suffix
      @fs_casesensitive = fs_casesensitive
    end

    # Builds the search index as an array of entry hashes.
    # +db+ is a MethodDatabase; +fdb+ is an optional FunctionDatabase (C API).
    def build_index(db, fdb = nil)
      index = [] #: Array[entry]
      index.concat(class_entries(db))
      index.concat(method_entries(db))
      index.concat(library_entries(db))
      index.concat(document_entries(db))
      index.concat(document_heading_entries(db))
      index.concat(function_entries(fdb)) if fdb
      index
    end

    # Serializes the index as an Aliki-compatible +search_data.js+ body.
    def to_js(db, fdb = nil)
      "var search_data = #{JSON.generate(index: build_index(db, fdb))};"
    end

    # Merges per-version indexes (an array of [version, index] pairs) into a
    # single index whose entries carry a +versions+ array, for the standalone
    # cross-version search page. Entries are considered the same when all of
    # name/full_name/type/path match. Versions are sorted numerically ("3.10"
    # sorts after "3.4"), and entry order is the first appearance while
    # scanning versions in ascending order — independent of the caller's
    # argument order, so the generated file diffs stay stable.
    def self.merge(version_indexes)
      merged = {} #: Hash[Array[String?], merged_entry]
      sorted = version_indexes.sort_by { |version, _| Gem::Version.new(version) }
      sorted.each do |version, index|
        index.each do |e|
          key = e.values_at(:name, :full_name, :type, :path)
          entry = (merged[key] ||= e.merge(versions: []))
          entry[:versions] << version
        end
      end
      merged.values
    end

    # Serializes a merged multi-version index as a +search_data.js+ body.
    def self.merged_js(version_indexes)
      "var search_data = #{JSON.generate(index: merge(version_indexes))};"
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
      seen = {} #: Hash[String, bool]
      result = [] #: Array[entry]
      db.methods.each do |entry|
        next if entry.undefined?

        type = TYPENAME_TO_SEARCH_TYPE[entry.typename]
        next unless type

        cname = entry.klass.name
        # bitclust#250: 検索結果に出る表示ラベル(name/full_name)は 4.0
        # 以降のドキュメントでは module function を "?." で表示する。path
        # は識別子なので typechar(常に不変)のまま
        tmark = entry.display_typemark
        tchar = entry.typechar
        entry.names.each do |mname|
          path = "method/#{encode(cname)}/#{tchar}/#{encode(mname)}#{@suffix}"
          next if seen[path]

          seen[path] = true
          if tmark == '$'
            # A special variable has no owning class to qualify it; its "$"
            # sigil is the only thing distinguishing it, so keep it in +name+
            # too (not just +full_name+) or a "$;"-style query can't match it.
            name = full_name = tmark + mname
            result << { name: name, full_name: full_name, type: type, path: path }
          else
            name = mname
            full_name = cname + tmark + mname
            item = { name: name, full_name: full_name, type: type, path: path } #: entry
            if tmark.include?('.')
              # bitclust#279: singleton methods (".") and module functions
              # (".#"/"?.") keep a literal "." in full_name for display, but
              # the vendored ranker's parseQuery() rewrites every "." in the
              # *query* to "::". match_name is the same rewrite applied to
              # this entry, so the search_init.js/search_page.js computeScore
              # wrap can compare like-for-like. See the file header comment.
              item[:match_name] = full_name.gsub('?.', '.#').gsub('.', '::')
            end
            result << item
          end
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

    # One entry per {#id}-anchored heading found in a doc page's body, so
    # that e.g. "defined?" or "alias" (headings inside spec/def.md) surface
    # directly instead of only the whole "クラス／メソッドの定義" page. See
    # ANCHORED_HEADING_RE above for why this only looks at doc pages (prose,
    # not method/class references) and only at explicitly anchored headings.
    def document_heading_entries(db)
      seen = {} #: Hash[String, bool]
      result = [] #: Array[entry]
      db.docs.each do |doc|
        source = doc.source
        next unless source
        page_title = (doc.title && !doc.title.empty?) ? doc.title : doc.name
        base_path = "doc/#{encode(doc.name)}#{@suffix}"
        each_anchored_heading(source) do |label, id|
          path = "#{base_path}##{id}"
          next if seen[path]

          seen[path] = true
          result << {
            name:      label,
            full_name: "#{label} (#{page_title})",
            type:      'heading',
            path:      path,
          }
        end
      end
      result
    end

    # Yields [label, id] for each ATX heading in +source+ that carries an
    # explicit {#id} anchor, skipping the contents of fenced code blocks
    # (```lang ... ```) so an in-sample "# comment" line can never be
    # mistaken for a heading.
    def each_anchored_heading(source)
      fence = nil #: Integer?
      source.each_line do |raw|
        line = raw.chomp
        if fence
          # Matches MDCompiler#code_fence's own terminator: the closing fence
          # must be exactly as long as the opening one.
          fence = nil if /\A`{#{fence}}[ \t]*\z/ =~ line
          next
        end
        if m = FENCE_START_RE.match(line)
          fence = (m[0] || raise).size
          next
        end
        next unless m = ANCHORED_HEADING_RE.match(line)

        id = m[3] or next
        yield clean_heading_label(m[2] || raise), id
      end
    end

    # Headings may carry inline Markdown (code spans, escaped punctuation);
    # strip that down to plain text for the index entry.
    def clean_heading_label(label)
      label.gsub(/`([^`]*)`/, '\1').gsub(/\\(.)/, '\1')
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
