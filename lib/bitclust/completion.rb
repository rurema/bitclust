#
# bitclust/completion.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  module Completion

    private

    #
    # Completion Search
    #

    def _search_classes(pattern)
      expand_ic(classes(), pattern)
    end

    def _search_methods(pattern)
      case
      when pattern.empty?
        recordclass = SearchResult::Record
        SearchResult.new(self, pattern, classes(),
            methods().map {|m| s = m.spec; recordclass.new(s, s, m) })
      when pattern.special_variable?
        c = fetch_class('Kernel')
        SearchResult.new(self, pattern, [c], search_svar(c, pattern.method))
      when pattern.class?
        search_methods_from_cname(pattern)
      else
        case
        when pattern.klass && pattern.method
GC.disable; x =
          search_methods_from_cname_mname(pattern)
GC.enable; GC.start; x
        when pattern.method
          search_methods_from_mname(pattern)
        when pattern.klass && pattern.type
          search_methods_from_cname(pattern)
        when pattern.type
          raise 'type only search is not supportted yet'
        else
          raise 'must not happen'
        end
      end
    end

    def _search_functions(pattern)
      expand_ic(functions(), pattern)
    end

    def search_svar(c, pattern)
      expand(c.special_variables, pattern)\
          .map {|m| SearchResult::Record.new(self, m.spec, m.spec, m) }
    end

    def search_methods_from_cname(pattern)
      cs = expand_ic(classes(), pattern.klass)
      return SearchResult.new(self, pattern, [], []) if cs.empty?
      recs = cs.map {|c|
        c.entries.map {|m|
          if not pattern.type or m.typemark == pattern.type
            s = m.spec
            SearchResult::Record.new(s, s, m)
          else
            nil
          end
        }.compact
      }.flatten
      SearchResult.new(self, pattern, cs, recs)
    end

    def mspec_from_cref_mname(cref, name)
      m = /\A(#{NameUtils::CLASS_PATH_RE})(#{NameUtils::TYPEMARK_RE})\Z/.match(cref)
      MethodSpec.new(m[1], m[2], name)
    end

    def search_methods_from_mname(pattern)
#timer_init
      names = expand_name_narrow(method_names(), pattern.method)
#split_time "m expandN (#{names.size})"
      records = names.map {|name|
        spec = MethodSpec.new(nil, pattern.type, name)
        crefs = mname2crefs_narrow(name)
#split_time "c expand  (#{crefs.size})"
        crefs.map {|cref|
          spec = mspec_from_cref_mname(classid2name(cref), name)
          SearchResult::Record.new(self, spec, spec)
        }
      }.flatten
      SearchResult.new(self, pattern, [], records)
    end

    def search_methods_from_cname_mname(pattern)
#timer_init
      recs = try(typechars(pattern.type, pattern.method)) {|ts|
        expand_method_name(pattern.klass, ts, pattern.method)
      }
      SearchResult.new(self, pattern, recs.map {|rec| rec.class_name }, recs)
    end

    def expand_method_name(c, ts, m)
      names_w = expand_name_wide(method_names(), m)
      return [] if names_w.empty?
#split_time "m expandW (#{names_w.size})"
      names_n = squeeze_names(names_w, m)
#split_time "m squeeze (#{names_n.size})"
      if names_n.empty?
        recs = make_cm_combination(c, ts, names_w)
        nclass = count_class(recs)
#split_time "c expandW (#{nclass}c x #{$cm_comb_m}m -> #{recs.size})"
      else
        recs = make_cm_combination(c, ts, names_n)
        nclass = count_class(recs)
#split_time "c expandN (#{nclass}c x #{$cm_comb_m}m -> #{recs.size})"
        if recs.empty?
          recs = make_cm_combination(c, ts, names_w)
          nclass = count_class(recs)
#split_time "c expandW (#{nclass}c x #{$cm_comb_m}m -> #{recs.size})"
        end
      end
      return [] if recs.empty?
      urecs = nclass > 50 ? recs : unify_entries(recs)
#split_time "unify     (#{urecs.size})"
      urecs
    end

    def timer_init
      @ts = [Time.now]
    end

    def split_time(msg)
      @ts.push Time.now
      $stderr.puts "#{@ts.size - 1}: #{'%.3f' % (@ts[-1] - @ts[-2])}: #{msg}"
    end

    def count_class(recs)
      recs.map {|rec| rec.class_name }.uniq.size
    end

    def make_cm_combination(cpat, ts, mnames)
      result = []
$cm_comb_m = 0
      mnames.each do |m|
        crefs = expand_name_narrow(mname2crefs_wide(m), cpat, ts)
        next if crefs.empty?
$cm_comb_m += 1
        crefs.each do |ref|
          spec = MethodSpec.new(classid2name(ref.chop), ref[-1,1], m)
          result.push SearchResult::Record.new(self, spec)
        end
      end
      result
    end

    def try(candidates)
      candidates.each do |c|
        result = yield c
        return result unless result.empty?
      end
      []
    end

    def typechars(type, mpattern)
      if type                     then [type]
      elsif /\A[A-Z]/ =~ mpattern then [':', '.#']
      else                             ['.#', ':']
      end
    end

    def unify_entries(ents)
      h = {}
      ents.each do |ent|
        if ent0 = h[ent]
          ent0.merge ent
        else
          h[ent] = ent
        end
      end
      h.values
    end

    # Case-insensitive search.  Optimized for constant search.
    def expand_ic(xs, pattern)
      re1 = /\A#{Regexp.quote(pattern)}/i
      result1 = xs.select {|x| x.name_match?(re1) }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = /\A#{Regexp.quote(pattern)}\z/i
      result2 = result1.select {|x| x.name_match?(re2) }
      return result1 if result2.empty?
      return result2 if result2.size == 1   # no mean
      result2
    end

    def expand(xs, pattern)
      re1 = /\A#{Regexp.quote(pattern)}/i
      result1 = xs.select {|x| x.name_match?(re1) }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = /\A#{Regexp.quote(pattern)}\z/i
      result2 = result1.select {|x| x.name_match?(re2) }
      return result1 if result2.empty?
      return result2 if result2.size == 1
      result3 = result2.select {|x| x.name?(pattern) }
      return result2 if result3.empty?
      return result3 if result3.size == 1   # no mean
      result3
    end

    # list up all matched items (without squeezing)
    def expand_name_wide(names, pattern)
      re1 = /\A#{Regexp.quote(pattern)}/i
      names.grep(re1)
    end

    # list up matched items (with squeezing)
    def expand_name_narrow(names, pattern, suffixes = nil)
      re1 = /\A#{Regexp.quote(pattern)}/i
      result1 = names.grep(re1)
      return [] if result1.empty?
      return result1 if result1.size == 1
      squeeze_names(result1, pattern, suffixes)
    end

    # squeeze result of #expand_name_wide
    def squeeze_names(result1, pattern, suffixes = nil)
      regexps =
        [
         /\A#{Regexp.quote(pattern)}.*#{suffix_pattern(suffixes)}\z/i,
         /\A#{Regexp.quote(pattern)}#{suffix_pattern(suffixes)}\z/i,
         /\A#{Regexp.quote(pattern)}#{suffix_pattern(suffixes)}\z/,
        ]
      result = result1
      regexps.each do |re|
        new_result = result.grep(re)
        return result if new_result.empty?
        return new_result if new_result.size == 1
        result = new_result
      end
      return result
    end

    def suffix_pattern(suffixes)
      return '' unless suffixes
      "[#{Regexp.quote(suffixes)}]"
    end

    #
    # Index
    #

    def save_completion_index
      save_class_index
      save_method_index
      save_method_index_narrow
    end

    def intern_classname(name)
      intern_table()[name]
    end

    def intern_table
      @intern_table ||= 
          begin
            h = {}
            classnametable().each do |id, names|
              names.each do |n|
                h[n] = id
              end
            end
            h
          end
    end

    def save_class_index
      atomic_write_open('class/=index') {|f|
        classes().each do |c|
          #f.puts "#{c.id}\t#{c.names.join(' ')}"  # FIXME: support class alias
          f.puts "#{c.id}\t#{c.name}"
        end
      }
    end

    def classnametable
      @classnametable ||=
          begin
            h = {}
            foreach_line('class/=index') do |line|
              id, *names = line.split
              h[id] = names
            end
            h
          rescue Errno::ENOENT
            {}
          end
    end

    def save_method_index_narrow
      index =
          begin
            h = {}
            classes().each do |c|
              c.entries.each do |m|
                ref = c.id + m.typemark
                m.names.each do |name|
                  (h[name] ||= []).push ref
                end
              end
            end
            h
          end
      atomic_write_open('method/=sindex') {|f|
        index.keys.sort.each do |name|
          f.puts "#{name}\t#{index[name].join(' ')}"
        end
      }
    end

    def method_index_small
      @method_index_small ||=
          begin
            h = {}
            foreach_line('method/=sindex') do |line|
              name, *crefs = line.split(nil)
              h[name] = crefs
            end
            h
          end
    end

    # canonical class name, no inheritance
    def mname2crefs_narrow(name)
      method_index_small()[name]
    end

    def save_method_index
      index =
          begin
            h = {}
            classes().each do |c|
              [ ['#', c._imap.keys],
                ['.', c._smap.keys],
                [':', c._cmap.keys] ].each do |t, names|
                ref = c.id + t
                names.each do |name|
                  (h[name] ||= []).push ref
                end
              end
            end
            h
          end
      atomic_write_open('method/=index') {|f|
        index.keys.sort.each do |name|
          f.puts "#{name}\t#{index[name].join(' ')}"
        end
      }
    end

    def method_names
      @method_names ||= method_index_0().keys
    end

    # includes class aliases, includes inherited methods
    def mname2crefs_wide(name)
      tbl = classnametable()
      mname2crefs_0(name).map {|ref|
        tbl[ref.chop].map {|c| c + ref[-1,1] }
      }.flatten
    end

    def mname2crefs_0(name)
      crefs = (@method_index ||= {})[name]
      return crefs if crefs
      crefsstr = method_index_0()[name] or return nil
      @method_index[name] = crefsstr.split(nil)
    end

    def method_index_0
      @method_index_0 ||=
          begin
            h = {}
            foreach_line('method/=index') do |line|
              name, cnames = line.split(nil, 2)
              h[name] = cnames
            end
            h
          end
    end

  end


  class SearchResult

    def SearchResult.empty(db, pattern)
      new(db, pattern, [], [])
    end

    def initialize(db, pattern, classes, records)
      @database = db
      @pattern = pattern
      @classes = classes
      @records = records
    end

    attr_reader :database
    attr_reader :pattern
    attr_reader :classes
    attr_reader :records

    def inspect
      "\#<BitClust::SearchResult @pattern=#{@pattern.inspect} @classes=#{@classes.inspect} @database=#{@database.inspect} @records=[#{record.inspect}, ...] >"
    end

    def fail?
      @records.empty?
    end

    def success?
      not @records.empty?
    end

    def determined?
      @records.size == 1
    end

    def name
      @records.first.name
    end

    def names
      @records.map {|rec| rec.names }.flatten
    end

    def record
      @records.first
    end

    def each_record(&block)
      @records.sort.each(&block)
    end

    class Record
      def initialize(db, spec, origin = nil, entry = nil)
        @db = db
        @specs = [spec]
        @origin = origin
        @entry = entry
      end

      attr_writer :db
      attr_reader :specs

      def origin
        @origin ||=
            begin
              spec = @specs.first
              c = @db.fetch_class(spec.klass)
              MethodSpec.parse(c.match_entry(spec.type, spec.method))
            end
      end

      def idstring
        origin().to_s
      end

      def entry
        @entry ||= @db.get_method(origin())
      end

      def name
        names().first
      end

      def names
        @specs.map {|spec| spec.display_name }
      end

      def class_name
        @specs.first.klass
      end

      def method_name
        @specs.first.method
      end

      def original_name
        @idstring
      end

      def ==(other)
        @idstring == other.idstring
      end

      alias eql? ==

      def hash
        @hash ||= idstring().hash
      end

      def <=>(other)
        entry() <=> other.entry
      end

      def merge(other)
        @specs |= other.specs
      end

      def inherited_method?
        not @specs.any? {|spec| spec.klass == origin().klass }
      end
    end

  end

end
