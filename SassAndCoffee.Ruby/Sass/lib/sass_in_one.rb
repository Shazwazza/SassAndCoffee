dir = File.dirname(__FILE__)
$LOAD_PATH.unshift dir unless $LOAD_PATH.include?(dir)

# This is necessary to set so that the Haml code that tries to load Sass
# knows that Sass is indeed loading,
# even if there's some crazy autoload stuff going on.
SASS_BEGUN_TO_LOAD = true unless defined?(SASS_BEGUN_TO_LOAD)

require 'date'

# This is necessary for loading Sass when Haml is required in Rails 3.
# Once the split is complete, we can remove it.
#RG require File.dirname(__FILE__) + '/../sass'
#RG require 'erb'
require 'set'
require 'enumerator'
require 'stringio'
require 'rbconfig'
#RG require 'thread'

module Sass
  # The root directory of the Sass source tree.
  # This may be overridden by the package manager
  # if the lib directory is separated from the main source tree.
  # @api public
  ROOT_DIR = File.expand_path(File.join(__FILE__, "../../.."))
end

module Sass
  module Util
    # A map from sets to values.
    # A value is \{#\[]= set} by providing a set (the "set-set") and a value,
    # which is then recorded as corresponding to that set.
    # Values are \{#\[] accessed} by providing a set (the "get-set")
    # and returning all values that correspond to set-sets
    # that are subsets of the get-set.
    #
    # SubsetMap preserves the order of values as they're inserted.
    #
    # @example
    #   ssm = SubsetMap.new
    #   ssm[Set[1, 2]] = "Foo"
    #   ssm[Set[2, 3]] = "Bar"
    #   ssm[Set[1, 2, 3]] = "Baz"
    #
    #   ssm[Set[1, 2, 3]] #=> ["Foo", "Bar", "Baz"]
    class SubsetMap
      # Creates a new, empty SubsetMap.
      def initialize
        @hash = {}
        @vals = []
      end

      # Whether or not this SubsetMap has any key-value pairs.
      #
      # @return [Boolean]
      def empty?
        @hash.empty?
      end

      # Associates a value with a set.
      # When `set` or any of its supersets is accessed,
      # `value` will be among the values returned.
      #
      # Note that if the same `set` is passed to this method multiple times,
      # all given `value`s will be associated with that `set`.
      #
      # This runs in `O(n)` time, where `n` is the size of `set`.
      #
      # @param set [#to_set] The set to use as the map key. May not be empty.
      # @param value [Object] The value to associate with `set`.
      # @raise [ArgumentError] If `set` is empty.
      def []=(set, value)
        raise ArgumentError.new("SubsetMap keys may not be empty.") if set.empty?

        index = @vals.size
        @vals << value
        set.each do |k|
          @hash[k] ||= []
          @hash[k] << [set, set.to_set, index]
        end
      end

      # Returns all values associated with subsets of `set`.
      #
      # In the worst case, this runs in `O(m*max(n, log m))` time,
      # where `n` is the size of `set`
      # and `m` is the number of assocations in the map.
      # However, unless many keys in the map overlap with `set`,
      # `m` will typically be much smaller.
      #
      # @param set [Set] The set to use as the map key.
      # @return [Array<(Object, #to_set)>] An array of pairs,
      #   where the first value is the value associated with a subset of `set`,
      #   and the second value is that subset of `set`
      #   (or whatever `#to_set` object was used to set the value)
      #   This array is in insertion order.
      # @see #[]
      def get(set)
        res = set.map do |k|
          next unless subsets = @hash[k]
          subsets.map do |subenum, subset, index|
            next unless subset.subset?(set)
            [index, subenum]
          end
        end
        res = Sass::Util.flatten(res, 1)
        res.compact!
        res.uniq!
        res.sort!
        res.map! {|i, s| [@vals[i], s]}
        return res
      end

      # Same as \{#get}, but doesn't return the subsets of the argument
      # for which values were found.
      #
      # @param set [Set] The set to use as the map key.
      # @return [Array] The array of all values
      #   associated with subsets of `set`, in insertion order.
      # @see #get
      def [](set)
        get(set).map {|v, _| v}
      end

      # Iterates over each value in the subset map. Ignores keys completely. If
      # multiple keys have the same value, this will return them multiple times.
      #
      # @yield [Object] Each value in the map.
      def each_value
        @vals.each {|v| yield v}
      end
    end
  end
end

module Sass
  # A module containing various useful functions.
  module Util
    extend self

    # An array of ints representing the Ruby version number.
    # @api public
    RUBY_VERSION = ::RUBY_VERSION.split(".").map {|s| s.to_i}

    # The Ruby engine we're running under. Defaults to `"ruby"`
    # if the top-level constant is undefined.
    # @api public
    RUBY_ENGINE = defined?(::RUBY_ENGINE) ? ::RUBY_ENGINE : "ruby"

    # Returns the path of a file relative to the Sass root directory.
    #
    # @param file [String] The filename relative to the Sass root
    # @return [String] The filename relative to the the working directory
    def scope(file)
      File.join(Sass::ROOT_DIR, file)
    end

    # Converts an array of `[key, value]` pairs to a hash.
    #
    # @example
    #   to_hash([[:foo, "bar"], [:baz, "bang"]])
    #     #=> {:foo => "bar", :baz => "bang"}
    # @param arr [Array<(Object, Object)>] An array of pairs
    # @return [Hash] A hash
    def to_hash(arr)
      Hash[arr.compact]
    end

    # Maps the keys in a hash according to a block.
    #
    # @example
    #   map_keys({:foo => "bar", :baz => "bang"}) {|k| k.to_s}
    #     #=> {"foo" => "bar", "baz" => "bang"}
    # @param hash [Hash] The hash to map
    # @yield [key] A block in which the keys are transformed
    # @yieldparam key [Object] The key that should be mapped
    # @yieldreturn [Object] The new value for the key
    # @return [Hash] The mapped hash
    # @see #map_vals
    # @see #map_hash
    def map_keys(hash)
      to_hash(hash.map {|k, v| [yield(k), v]})
    end

    # Maps the values in a hash according to a block.
    #
    # @example
    #   map_values({:foo => "bar", :baz => "bang"}) {|v| v.to_sym}
    #     #=> {:foo => :bar, :baz => :bang}
    # @param hash [Hash] The hash to map
    # @yield [value] A block in which the values are transformed
    # @yieldparam value [Object] The value that should be mapped
    # @yieldreturn [Object] The new value for the value
    # @return [Hash] The mapped hash
    # @see #map_keys
    # @see #map_hash
    def map_vals(hash)
      to_hash(hash.map {|k, v| [k, yield(v)]})
    end

    # Maps the key-value pairs of a hash according to a block.
    #
    # @example
    #   map_hash({:foo => "bar", :baz => "bang"}) {|k, v| [k.to_s, v.to_sym]}
    #     #=> {"foo" => :bar, "baz" => :bang}
    # @param hash [Hash] The hash to map
    # @yield [key, value] A block in which the key-value pairs are transformed
    # @yieldparam [key] The hash key
    # @yieldparam [value] The hash value
    # @yieldreturn [(Object, Object)] The new value for the `[key, value]` pair
    # @return [Hash] The mapped hash
    # @see #map_keys
    # @see #map_vals
    def map_hash(hash)
      # Using &block here completely hoses performance on 1.8.
      to_hash(hash.map {|k, v| yield k, v})
    end

    # Computes the powerset of the given array.
    # This is the set of all subsets of the array.
    #
    # @example
    #   powerset([1, 2, 3]) #=>
    #     Set[Set[], Set[1], Set[2], Set[3], Set[1, 2], Set[2, 3], Set[1, 3], Set[1, 2, 3]]
    # @param arr [Enumerable]
    # @return [Set<Set>] The subsets of `arr`
    def powerset(arr)
      arr.inject([Set.new].to_set) do |powerset, el|
        new_powerset = Set.new
        powerset.each do |subset|
          new_powerset << subset
          new_powerset << subset + [el]
        end
        new_powerset
      end
    end

    # Restricts a number to falling within a given range.
    # Returns the number if it falls within the range,
    # or the closest value in the range if it doesn't.
    #
    # @param value [Numeric]
    # @param range [Range<Numeric>]
    # @return [Numeric]
    def restrict(value, range)
      [[value, range.first].max, range.last].min
    end

    # Concatenates all strings that are adjacent in an array,
    # while leaving other elements as they are.
    #
    # @example
    #   merge_adjacent_strings([1, "foo", "bar", 2, "baz"])
    #     #=> [1, "foobar", 2, "baz"]
    # @param arr [Array]
    # @return [Array] The enumerable with strings merged
    def merge_adjacent_strings(arr)
      # Optimize for the common case of one element
      return arr if arr.size < 2
      arr.inject([]) do |a, e|
        if e.is_a?(String)
          if a.last.is_a?(String)
            a.last << e
          else
            a << e.dup
          end
        else
          a << e
        end
        a
      end
    end

    # Intersperses a value in an enumerable, as would be done with `Array#join`
    # but without concatenating the array together afterwards.
    #
    # @param enum [Enumerable]
    # @param val
    # @return [Array]
    def intersperse(enum, val)
      enum.inject([]) {|a, e| a << e << val}[0...-1]
    end

    # Substitutes a sub-array of one array with another sub-array.
    #
    # @param ary [Array] The array in which to make the substitution
    # @param from [Array] The sequence of elements to replace with `to`
    # @param to [Array] The sequence of elements to replace `from` with
    def substitute(ary, from, to)
      res = ary.dup
      i = 0
      while i < res.size
        if res[i...i+from.size] == from
          res[i...i+from.size] = to
        end
        i += 1
      end
      res
    end

    # Destructively strips whitespace from the beginning and end
    # of the first and last elements, respectively,
    # in the array (if those elements are strings).
    #
    # @param arr [Array]
    # @return [Array] `arr`
    def strip_string_array(arr)
      arr.first.lstrip! if arr.first.is_a?(String)
      arr.last.rstrip! if arr.last.is_a?(String)
      arr
    end

    # Return an array of all possible paths through the given arrays.
    #
    # @param arrs [Array<Array>]
    # @return [Array<Arrays>]
    #
    # @example
    #   paths([[1, 2], [3, 4], [5]]) #=>
    #     # [[1, 3, 5],
    #     #  [2, 3, 5],
    #     #  [1, 4, 5],
    #     #  [2, 4, 5]]
    def paths(arrs)
      arrs.inject([[]]) do |paths, arr|
        flatten(arr.map {|e| paths.map {|path| path + [e]}}, 1)
      end
    end

    # Computes a single longest common subsequence for `x` and `y`.
    # If there are more than one longest common subsequences,
    # the one returned is that which starts first in `x`.
    #
    # @param x [Array]
    # @param y [Array]
    # @yield [a, b] An optional block to use in place of a check for equality
    #   between elements of `x` and `y`.
    # @yieldreturn [Object, nil] If the two values register as equal,
    #   this will return the value to use in the LCS array.
    # @return [Array] The LCS
    def lcs(x, y, &block)
      x = [nil, *x]
      y = [nil, *y]
      block ||= proc {|a, b| a == b && a}
      lcs_backtrace(lcs_table(x, y, &block), x, y, x.size-1, y.size-1, &block)
    end

    # Converts a Hash to an Array. This is usually identical to `Hash#to_a`,
    # with the following exceptions:
    #
    # * In Ruby 1.8, `Hash#to_a` is not deterministically ordered, but this is.
    # * In Ruby 1.9 when running tests, this is ordered in the same way it would
    #   be under Ruby 1.8 (sorted key order rather than insertion order).
    #
    # @param hash [Hash]
    # @return [Array]
    def hash_to_a(hash)
      return hash.to_a unless ruby1_8? || defined?(Test::Unit)
      return hash.sort_by {|k, v| k}
    end

    # Performs the equivalent of `enum.group_by.to_a`, but with a guaranteed
    # order. Unlike [#hash_to_a], the resulting order isn't sorted key order;
    # instead, it's the same order as `#group_by` has under Ruby 1.9 (key
    # appearance order).
    #
    # @param enum [Enumerable]
    # @return [Array<[Object, Array]>] An array of pairs.
    def group_by_to_a(enum, &block)
      return enum.group_by(&block).to_a unless ruby1_8?
      order = {}
      arr = []
	  #RG There is no group_by in iron monkey :-/ 
	  #RG This can be probably optimized by some Ruby guru
	  groupKeys = []
	  result = []
	  enum.each do |key|
	    res = block[key]
		unless order.include?(res)
			arr[order.size] = []
			groupKeys[order.size] = res
			order[res] = order.size
		end
		arr[order[res]] = arr[order[res]] + [ key ]
	  end
	  arr.each_with_index do |vals,key|
	    result[key] =  [groupKeys[key], vals]
	  end
	  result
      #RG enum.group_by do |e|
      #RG   res = block[e]
      #RG   unless order.include?(res)
      #RG     order[res] = order.size
      #RG   end
      #RG   res
      #RG end.each do |key, vals|
      #RG   arr[order[key]] = [key, vals]
      #RG end
      #RG arr
    end

    # Returns a sub-array of `minuend` containing only elements that are also in
    # `subtrahend`. Ensures that the return value has the same order as
    # `minuend`, even on Rubinius where that's not guaranteed by {Array#-}.
    #
    # @param minuend [Array]
    # @param subtrahend [Array]
    # @return [Array]
    def array_minus(minuend, subtrahend)
      return minuend - subtrahend unless rbx?
      set = Set.new(minuend) - subtrahend
      minuend.select {|e| set.include?(e)}
    end

    # Returns a string description of the character that caused an
    # `Encoding::UndefinedConversionError`.
    #
    # @param [Encoding::UndefinedConversionError]
    # @return [String]
    def undefined_conversion_error_char(e)
      # Rubinius (as of 2.0.0.rc1) pre-quotes the error character.
      return e.error_char if rbx?
      # JRuby (as of 1.7.2) doesn't have an error_char field on
      # Encoding::UndefinedConversionError.
      return e.error_char.dump unless jruby?
      e.message[/^"[^"]+"/] #"
    end

    # Asserts that `value` falls within `range` (inclusive), leaving
    # room for slight floating-point errors.
    #
    # @param name [String] The name of the value. Used in the error message.
    # @param range [Range] The allowed range of values.
    # @param value [Numeric, Sass::Script::Number] The value to check.
    # @param unit [String] The unit of the value. Used in error reporting.
    # @return [Numeric] `value` adjusted to fall within range, if it
    #   was outside by a floating-point margin.
    def check_range(name, range, value, unit='')
      grace = (-0.00001..0.00001)
      str = value.to_s
      value = value.value if value.is_a?(Sass::Script::Number)
      return value if range.include?(value)
      return range.first if grace.include?(value - range.first)
      return range.last if grace.include?(value - range.last)
      raise ArgumentError.new(
        "#{name} #{str} must be between #{range.first}#{unit} and #{range.last}#{unit}")
    end

    # Returns whether or not `seq1` is a subsequence of `seq2`. That is, whether
    # or not `seq2` contains every element in `seq1` in the same order (and
    # possibly more elements besides).
    #
    # @param seq1 [Array]
    # @param seq2 [Array]
    # @return [Boolean]
    def subsequence?(seq1, seq2)
      i = j = 0
      loop do
        return true if i == seq1.size
        return false if j == seq2.size
        i += 1 if seq1[i] == seq2[j]
        j += 1
      end
    end

    # Returns information about the caller of the previous method.
    #
    # @param entry [String] An entry in the `#caller` list, or a similarly formatted string
    # @return [[String, Fixnum, (String, nil)]] An array containing the filename, line, and method name of the caller.
    #   The method name may be nil
    def caller_info(entry = nil)
      # JRuby evaluates `caller` incorrectly when it's in an actual default argument.
      entry ||= caller[1]
      info = entry.scan(/^(.*?):(-?.*?)(?::.*`(.+)')?$/).first
      info[1] = info[1].to_i
      # This is added by Rubinius to designate a block, but we don't care about it.
      info[2].sub!(/ \{\}\Z/, '') if info[2]
      info
    end

    # Returns whether one version string represents a more recent version than another.
    #
    # @param v1 [String] A version string.
    # @param v2 [String] Another version string.
    # @return [Boolean]
    def version_gt(v1, v2)
      # Construct an array to make sure the shorter version is padded with nil
      Array.new([v1.length, v2.length].max).zip(v1.split("."), v2.split(".")) do |_, p1, p2|
        p1 ||= "0"
        p2 ||= "0"
        release1 = p1 =~ /^[0-9]+$/
        release2 = p2 =~ /^[0-9]+$/
        if release1 && release2
          # Integer comparison if both are full releases
          p1, p2 = p1.to_i, p2.to_i
          next if p1 == p2
          return p1 > p2
        elsif !release1 && !release2
          # String comparison if both are prereleases
          next if p1 == p2
          return p1 > p2
        else
          # If only one is a release, that one is newer
          return release1
        end
      end
    end

    # Returns whether one version string represents the same or a more
    # recent version than another.
    #
    # @param v1 [String] A version string.
    # @param v2 [String] Another version string.
    # @return [Boolean]
    def version_geq(v1, v2)
      version_gt(v1, v2) || !version_gt(v2, v1)
    end

    # Throws a NotImplementedError for an abstract method.
    #
    # @param obj [Object] `self`
    # @raise [NotImplementedError]
    def abstract(obj)
      raise NotImplementedError.new("#{obj.class} must implement ##{caller_info[2]}")
    end

    # Silence all output to STDERR within a block.
    #
    # @yield A block in which no output will be printed to STDERR
    def silence_warnings
      the_real_stderr, $stderr = $stderr, StringIO.new
      yield
    ensure
      $stderr = the_real_stderr
    end

    @@silence_warnings = false
    # Silences all Sass warnings within a block.
    #
    # @yield A block in which no Sass warnings will be printed
    def silence_sass_warnings
      old_level, Sass.logger.log_level = Sass.logger.log_level, :error
      yield
    ensure
      Sass.logger.log_level = old_level
    end

    # The same as `Kernel#warn`, but is silenced by \{#silence\_sass\_warnings}.
    #
    # @param msg [String]
    def sass_warn(msg)
      msg = msg + "\n" unless ruby1?
      Sass.logger.warn(msg)
    end

    ## Cross Rails Version Compatibility

    # Returns the root of the Rails application,
    # if this is running in a Rails context.
    # Returns `nil` if no such root is defined.
    #
    # @return [String, nil]
    def rails_root
      if defined?(::Rails.root)
        return ::Rails.root.to_s if ::Rails.root
        raise "ERROR: Rails.root is nil!"
      end
      return RAILS_ROOT.to_s if defined?(RAILS_ROOT)
      return nil
    end

    # Returns the environment of the Rails application,
    # if this is running in a Rails context.
    # Returns `nil` if no such environment is defined.
    #
    # @return [String, nil]
    def rails_env
      return ::Rails.env.to_s if defined?(::Rails.env)
      return RAILS_ENV.to_s if defined?(RAILS_ENV)
      return nil
    end

    # Returns whether this environment is using ActionPack
    # version 3.0.0 or greater.
    #
    # @return [Boolean]
    def ap_geq_3?
      ap_geq?("3.0.0.beta1")
    end

    # Returns whether this environment is using ActionPack
    # of a version greater than or equal to that specified.
    #
    # @param version [String] The string version number to check against.
    #   Should be greater than or equal to Rails 3,
    #   because otherwise ActionPack::VERSION isn't autoloaded
    # @return [Boolean]
    def ap_geq?(version)
      # The ActionPack module is always loaded automatically in Rails >= 3
      return false unless defined?(ActionPack) && defined?(ActionPack::VERSION) &&
        defined?(ActionPack::VERSION::STRING)

      version_geq(ActionPack::VERSION::STRING, version)
    end

    # Returns an ActionView::Template* class.
    # In pre-3.0 versions of Rails, most of these classes
    # were of the form `ActionView::TemplateFoo`,
    # while afterwards they were of the form `ActionView;:Template::Foo`.
    #
    # @param name [#to_s] The name of the class to get.
    #   For example, `:Error` will return `ActionView::TemplateError`
    #   or `ActionView::Template::Error`.
    def av_template_class(name)
      return ActionView.const_get("Template#{name}") if ActionView.const_defined?("Template#{name}")
      return ActionView::Template.const_get(name.to_s)
    end

    ## Cross-OS Compatibility

    # Whether or not this is running on Windows.
    #
    # @return [Boolean]
    def windows?
      RbConfig::CONFIG['host_os'] =~ /mswin|windows|mingw/i
    end

    # Whether or not this is running on IronRuby.
    #
    # @return [Boolean]
    def ironruby?
      RUBY_ENGINE == "ironruby"
    end

    # Whether or not this is running on Rubinius.
    #
    # @return [Boolean]
    def rbx?
      RUBY_ENGINE == "rbx"
    end

    # Whether or not this is running on JRuby.
    #
    # @return [Boolean]
    def jruby?
      RUBY_PLATFORM =~ /java/
    end

    # Returns an array of ints representing the JRuby version number.
    #
    # @return [Array<Fixnum>]
    def jruby_version
      $jruby_version ||= ::JRUBY_VERSION.split(".").map {|s| s.to_i}
    end

    # Like `Dir.glob`, but works with backslash-separated paths on Windows.
    #
    # @param path [String]
    def glob(path, &block)
      path = path.gsub('\\', '/') if windows?
      Dir.glob(path, &block)
    end

    # Prepare a value for a destructuring assignment (e.g. `a, b =
    # val`). This works around a performance bug when using
    # ActiveSupport, and only needs to be called when `val` is likely
    # to be `nil` reasonably often.
    #
    # See [this bug report](http://redmine.ruby-lang.org/issues/4917).
    #
    # @param val [Object]
    # @return [Object]
    def destructure(val)
      val || []
    end

    ## Cross-Ruby-Version Compatibility

    # Whether or not this is running under a Ruby version under 2.0.
    #
    # @return [Boolean]
    def ruby1?
      Sass::Util::RUBY_VERSION[0] <= 1
    end

    # Whether or not this is running under Ruby 1.8 or lower.
    #
    # Note that IronRuby counts as Ruby 1.8,
    # because it doesn't support the Ruby 1.9 encoding API.
    #
    # @return [Boolean]
    def ruby1_8?
      # IronRuby says its version is 1.9, but doesn't support any of the encoding APIs.
      # We have to fall back to 1.8 behavior.
      ironruby? || (Sass::Util::RUBY_VERSION[0] == 1 && Sass::Util::RUBY_VERSION[1] < 9)
    end

    # Whether or not this is running under Ruby 1.8.6 or lower.
    # Note that lower versions are not officially supported.
    #
    # @return [Boolean]
    def ruby1_8_6?
      ruby1_8? && Sass::Util::RUBY_VERSION[2] < 7
    end

    # Wehter or not this is running under JRuby 1.6 or lower.
    def jruby1_6?
      jruby? && jruby_version[0] == 1 && jruby_version[1] < 7
    end

    # Whether or not this is running under MacRuby.
    #
    # @return [Boolean]
    def macruby?
      RUBY_ENGINE == 'macruby'
    end

    # Checks that the encoding of a string is valid in Ruby 1.9
    # and cleans up potential encoding gotchas like the UTF-8 BOM.
    # If it's not, yields an error string describing the invalid character
    # and the line on which it occurrs.
    #
    # @param str [String] The string of which to check the encoding
    # @yield [msg] A block in which an encoding error can be raised.
    #   Only yields if there is an encoding error
    # @yieldparam msg [String] The error message to be raised
    # @return [String] `str`, potentially with encoding gotchas like BOMs removed
    def check_encoding(str)
      if ruby1_8?
        return str.gsub(/\A\xEF\xBB\xBF/, '') # Get rid of the UTF-8 BOM
      elsif str.valid_encoding?
        # Get rid of the Unicode BOM if possible
        if str.encoding.name =~ /^UTF-(8|16|32)(BE|LE)?$/
          return str.gsub(Regexp.new("\\A\uFEFF".encode(str.encoding.name)), '')
        else
          return str
        end
      end

      encoding = str.encoding
      newlines = Regexp.new("\r\n|\r|\n".encode(encoding).force_encoding("binary"))
      str.force_encoding("binary").split(newlines).each_with_index do |line, i|
        begin
          line.encode(encoding)
        rescue Encoding::UndefinedConversionError => e
          yield <<MSG.rstrip, i + 1
Invalid #{encoding.name} character #{undefined_conversion_error_char(e)}
MSG
        end
      end
      return str
    end

    # Like {\#check\_encoding}, but also checks for a `@charset` declaration
    # at the beginning of the file and uses that encoding if it exists.
    #
    # The Sass encoding rules are simple.
    # If a `@charset` declaration exists,
    # we assume that that's the original encoding of the document.
    # Otherwise, we use whatever encoding Ruby has.
    # Then we convert that to UTF-8 to process internally.
    # The UTF-8 end result is what's returned by this method.
    #
    # @param str [String] The string of which to check the encoding
    # @yield [msg] A block in which an encoding error can be raised.
    #   Only yields if there is an encoding error
    # @yieldparam msg [String] The error message to be raised
    # @return [(String, Encoding)] The original string encoded as UTF-8,
    #   and the source encoding of the string (or `nil` under Ruby 1.8)
    # @raise [Encoding::UndefinedConversionError] if the source encoding
    #   cannot be converted to UTF-8
    # @raise [ArgumentError] if the document uses an unknown encoding with `@charset`
    def check_sass_encoding(str, &block)
      return check_encoding(str, &block), nil if ruby1_8?
      # We allow any printable ASCII characters but double quotes in the charset decl
      bin = str.dup.force_encoding("BINARY")
      encoding = Sass::Util::ENCODINGS_TO_CHECK.find do |enc|
        re = Sass::Util::CHARSET_REGEXPS[enc]
        re && bin =~ re
      end
      charset, bom = $1, $2
      if charset
        charset = charset.force_encoding(encoding).encode("UTF-8")
        if endianness = encoding[/[BL]E$/]
          begin
            Encoding.find(charset + endianness)
            charset << endianness
          rescue ArgumentError # Encoding charset + endianness doesn't exist
          end
        end
        str.force_encoding(charset)
      elsif bom
        str.force_encoding(encoding)
      end

      str = check_encoding(str, &block)
      return str.encode("UTF-8"), str.encoding
    end

    unless ruby1_8?
      # @private
      def _enc(string, encoding)
        string.encode(encoding).force_encoding("BINARY")
      end

      # We could automatically add in any non-ASCII-compatible encodings here,
      # but there's not really a good way to do that
      # without manually checking that each encoding
      # encodes all ASCII characters properly,
      # which takes long enough to affect the startup time of the CLI.
      ENCODINGS_TO_CHECK = %w[UTF-8 UTF-16BE UTF-16LE UTF-32BE UTF-32LE]

      CHARSET_REGEXPS = Hash.new do |h, e|
        h[e] =
          begin
            # /\A(?:\uFEFF)?@charset "(.*?)"|\A(\uFEFF)/
            Regexp.new(/\A(?:#{_enc("\uFEFF", e)})?#{
              _enc('@charset "', e)}(.*?)#{_enc('"', e)}|\A(#{
              _enc("\uFEFF", e)})/)
          rescue Encoding::ConverterNotFoundError => _
            nil # JRuby on Java 5 doesn't support UTF-32
          rescue
            # /\A@charset "(.*?)"/
            Regexp.new(/\A#{_enc('@charset "', e)}(.*?)#{_enc('"', e)}/)
          end
      end
    end

    # Checks to see if a class has a given method.
    # For example:
    #
    #     Sass::Util.has?(:public_instance_method, String, :gsub) #=> true
    #
    # Method collections like `Class#instance_methods`
    # return strings in Ruby 1.8 and symbols in Ruby 1.9 and on,
    # so this handles checking for them in a compatible way.
    #
    # @param attr [#to_s] The (singular) name of the method-collection method
    #   (e.g. `:instance_methods`, `:private_methods`)
    # @param klass [Module] The class to check the methods of which to check
    # @param method [String, Symbol] The name of the method do check for
    # @return [Boolean] Whether or not the given collection has the given method
    def has?(attr, klass, method)
      klass.send("#{attr}s").include?(ruby1_8? ? method.to_s : method.to_sym)
    end

    # A version of `Enumerable#enum_with_index` that works in Ruby 1.8 and 1.9.
    #
    # @param enum [Enumerable] The enumerable to get the enumerator for
    # @return [Enumerator] The with-index enumerator
    def enum_with_index(enum)		
	  #RG find applied to the iterator doesn't get the proper index in IronRuby??
      #RG: ruby1_8? ? enum.enum_with_index : enum.each_with_index
	  #RG So instead we convert it to array of the pairs, this can be possibly done differently
	  #RG but seems to work
	  enum.each_with_index.map do |el,i|
		[el,i]
	  end
    end

    # A version of `Enumerable#enum_cons` that works in Ruby 1.8 and 1.9.
    #
    # @param enum [Enumerable] The enumerable to get the enumerator for
    # @param n [Fixnum] The size of each cons
    # @return [Enumerator] The consed enumerator
    def enum_cons(enum, n)
      ruby1_8? ? enum.enum_cons(n) : enum.each_cons(n)
    end

    # A version of `Enumerable#enum_slice` that works in Ruby 1.8 and 1.9.
    #
    # @param enum [Enumerable] The enumerable to get the enumerator for
    # @param n [Fixnum] The size of each slice
    # @return [Enumerator] The consed enumerator
    def enum_slice(enum, n)
      ruby1_8? ? enum.enum_slice(n) : enum.each_slice(n)
    end

    # Destructively removes all elements from an array that match a block, and
    # returns the removed elements.
    #
    # @param array [Array] The array from which to remove elements.
    # @yield [el] Called for each element.
    # @yieldparam el [*] The element to test.
    # @yieldreturn [Boolean] Whether or not to extract the element.
    # @return [Array] The extracted elements.
    def extract!(array)
      out = []
      array.reject! do |e|
        next false unless yield e
        out << e
        true
      end
      out
    end

    # Returns the ASCII code of the given character.
    #
    # @param c [String] All characters but the first are ignored.
    # @return [Fixnum] The ASCII code of `c`.
    def ord(c)
      ruby1_8? ? c[0] : c.ord
    end

    # Flattens the first `n` nested arrays in a cross-version manner.
    #
    # @param arr [Array] The array to flatten
    # @param n [Fixnum] The number of levels to flatten
    # @return [Array] The flattened array
    def flatten(arr, n)
      return arr.flatten(n) unless ruby1_8_6?
      return arr if n == 0
      arr.inject([]) {|res, e| e.is_a?(Array) ? res.concat(flatten(e, n - 1)) : res << e}
    end

    # Returns the hash code for a set in a cross-version manner.
    # Aggravatingly, this is order-dependent in Ruby 1.8.6.
    #
    # @param set [Set]
    # @return [Fixnum] The order-independent hashcode of `set`
    def set_hash(set)
      return set.hash unless ruby1_8_6?
      set.map {|e| e.hash}.uniq.sort.hash
    end

    # Tests the hash-equality of two sets in a cross-version manner.
    # Aggravatingly, this is order-dependent in Ruby 1.8.6.
    #
    # @param set1 [Set]
    # @param set2 [Set]
    # @return [Boolean] Whether or not the sets are hashcode equal
    def set_eql?(set1, set2)
      return set1.eql?(set2) unless ruby1_8_6?
      set1.to_a.uniq.sort_by {|e| e.hash}.eql?(set2.to_a.uniq.sort_by {|e| e.hash})
    end

    # Like `Object#inspect`, but preserves non-ASCII characters rather than escaping them under Ruby 1.9.2.
    # This is necessary so that the precompiled Haml template can be `#encode`d into `@options[:encoding]`
    # before being evaluated.
    #
    # @param obj {Object}
    # @return {String}
    def inspect_obj(obj)
      return obj.inspect unless version_geq(::RUBY_VERSION, "1.9.2")
      return ':' + inspect_obj(obj.to_s) if obj.is_a?(Symbol)
      return obj.inspect unless obj.is_a?(String)
      '"' + obj.gsub(/[\x00-\x7F]+/) {|s| s.inspect[1...-1]} + '"'
    end

    # Extracts the non-string vlaues from an array containing both strings and non-strings.
    # These values are replaced with escape sequences.
    # This can be undone using \{#inject\_values}.
    #
    # This is useful e.g. when we want to do string manipulation
    # on an interpolated string.
    #
    # The precise format of the resulting string is not guaranteed.
    # However, it is guaranteed that newlines and whitespace won't be affected.
    #
    # @param arr [Array] The array from which values are extracted.
    # @return [(String, Array)] The resulting string, and an array of extracted values.
    def extract_values(arr)
      values = []
      return arr.map do |e|
        next e.gsub('{', '{{') if e.is_a?(String)
        values << e
        next "{#{values.count - 1}}"
      end.join, values
    end

    # Undoes \{#extract\_values} by transforming a string with escape sequences
    # into an array of strings and non-string values.
    #
    # @param str [String] The string with escape sequences.
    # @param values [Array] The array of values to inject.
    # @return [Array] The array of strings and values.
    def inject_values(str, values)
      return [str.gsub('{{', '{')] if values.empty?
      # Add an extra { so that we process the tail end of the string
      result = (str + '{{').scan(/(.*?)(?:(\{\{)|\{(\d+)\})/m).map do |(pre, esc, n)|
        [pre, esc ? '{' : '', n ? values[n.to_i] : '']
      end.flatten(1)
      result[-2] = '' # Get rid of the extra {
      merge_adjacent_strings(result).reject {|s| s == ''}
    end

    # Allows modifications to be performed on the string form
    # of an array containing both strings and non-strings.
    #
    # @param arr [Array] The array from which values are extracted.
    # @yield [str] A block in which string manipulation can be done to the array.
    # @yieldparam str [String] The string form of `arr`.
    # @yieldreturn [String] The modified string.
    # @return [Array] The modified, interpolated array.
    def with_extracted_values(arr)
      str, vals = extract_values(arr)
      str = yield str
      inject_values(str, vals)
    end

    ## Static Method Stuff

    # The context in which the ERB for \{#def\_static\_method} will be run.
    class StaticConditionalContext
      # @param set [#include?] The set of variables that are defined for this context.
      def initialize(set)
        @set = set
      end

      # Checks whether or not a variable is defined for this context.
      #
      # @param name [Symbol] The name of the variable
      # @return [Boolean]
      def method_missing(name, *args, &block)
        super unless args.empty? && block.nil?
        @set.include?(name)
      end
    end

    # This creates a temp file and yields it for writing. When the
    # write is complete, the file is moved into the desired location.
    # The atomicity of this operation is provided by the filesystem's
    # rename operation.
    #
    # @param filename [String] The file to write to.
    # @yieldparam tmpfile [Tempfile] The temp file that can be written to.
    # @return The value returned by the block.
    def atomic_create_and_write_file(filename)
      require 'tempfile'
      tmpfile = Tempfile.new(File.basename(filename), File.dirname(filename))
      tmp_path = tmpfile.path
      tmpfile.binmode if tmpfile.respond_to?(:binmode)
      result = yield tmpfile
      File.rename tmpfile.path, filename
      result
    ensure
      # close and remove the tempfile if it still exists,
      # presumably due to an error during write
      tmpfile.close if tmpfile
      tmpfile.unlink if tmpfile
    end

    private

    # Calculates the memoization table for the Least Common Subsequence algorithm.
    # Algorithm from [Wikipedia](http://en.wikipedia.org/wiki/Longest_common_subsequence_problem#Computing_the_length_of_the_LCS)
    def lcs_table(x, y)
      c = Array.new(x.size) {[]}
      x.size.times {|i| c[i][0] = 0}
      y.size.times {|j| c[0][j] = 0}
      (1...x.size).each do |i|
        (1...y.size).each do |j|
          c[i][j] =
            if yield x[i], y[j]
              c[i-1][j-1] + 1
            else
              [c[i][j-1], c[i-1][j]].max
            end
        end
      end
      return c
    end

    # Computes a single longest common subsequence for arrays x and y.
    # Algorithm from [Wikipedia](http://en.wikipedia.org/wiki/Longest_common_subsequence_problem#Reading_out_an_LCS)
    def lcs_backtrace(c, x, y, i, j, &block)
      return [] if i == 0 || j == 0
      if v = yield(x[i], y[j])
        return lcs_backtrace(c, x, y, i-1, j-1, &block) << v
      end

      return lcs_backtrace(c, x, y, i, j-1, &block) if c[i][j-1] > c[i-1][j]
      return lcs_backtrace(c, x, y, i-1, j, &block)
    end
  end
end

require 'strscan'

if Sass::Util.ruby1_8?
  Sass::Util::MultibyteStringScanner = StringScanner
else
  if Sass::Util.rbx?
    # Rubinius's StringScanner class implements some of its methods in terms of
    # others, which causes us to double-count bytes in some cases if we do
    # straightforward inheritance. To work around this, we use a delegate class.
    require 'delegate'
    class Sass::Util::MultibyteStringScanner < DelegateClass(StringScanner)
      def initialize(str)
        super(StringScanner.new(str))
        @mb_pos = 0
        @mb_matched_size = nil
        @mb_last_pos = nil
      end

      def is_a?(klass)
        __getobj__.is_a?(klass) || super
      end
    end
  else
    class Sass::Util::MultibyteStringScanner < StringScanner
      def initialize(str)
        super
        @mb_pos = 0
        @mb_matched_size = nil
        @mb_last_pos = nil
      end
    end
  end

  # A wrapper of the native StringScanner class that works correctly with
  # multibyte character encodings. The native class deals only in bytes, not
  # characters, for methods like [#pos] and [#matched_size]. This class deals
  # only in characters, instead.
  class Sass::Util::MultibyteStringScanner
    def self.new(str)
      return StringScanner.new(str) if str.ascii_only?
      super
    end

    alias_method :byte_pos, :pos
    alias_method :byte_matched_size, :matched_size

    def check(pattern); _match super; end
    def check_until(pattern); _matched super; end
    def getch; _forward _match super; end
    def match?(pattern); _size check(pattern); end
    def matched_size; @mb_matched_size; end
    def peek(len); string[@mb_pos, len]; end
    alias_method :peep, :peek
    def pos; @mb_pos; end
    alias_method :pointer, :pos
    def rest_size; rest.size; end
    def scan(pattern); _forward _match super; end
    def scan_until(pattern); _forward _matched super; end
    def skip(pattern); _size scan(pattern); end
    def skip_until(pattern); _matched _size scan_until(pattern); end

    def get_byte
      raise "MultibyteStringScanner doesn't support #get_byte."
    end

    def getbyte
      raise "MultibyteStringScanner doesn't support #getbyte."
    end

    def pos=(n)
      @mb_last_pos = nil

      # We set position kind of a lot during parsing, so we want it to be as
      # efficient as possible. This is complicated by the fact that UTF-8 is a
      # variable-length encoding, so it's difficult to find the byte length that
      # corresponds to a given character length.
      #
      # Our heuristic here is to try to count the fewest possible characters. So
      # if the new position is close to the current one, just count the
      # characters between the two; if the new position is closer to the
      # beginning of the string, just count the characters from there.
      if @mb_pos - n < @mb_pos / 2
        # New position is close to old position
        byte_delta = @mb_pos > n ? -string[n...@mb_pos].bytesize : string[@mb_pos...n].bytesize
        super(byte_pos + byte_delta)
      else
        # New position is close to BOS
        super(string[0...n].bytesize)
      end
      @mb_pos = n
    end

    def reset
      @mb_pos = 0
      @mb_matched_size = nil
      @mb_last_pos = nil
      super
    end

    def scan_full(pattern, advance_pointer_p, return_string_p)
      res = _match super(pattern, advance_pointer_p, true)
      _forward res if advance_pointer_p
      return res if return_string_p
    end

    def search_full(pattern, advance_pointer_p, return_string_p)
      res = super(pattern, advance_pointer_p, true)
      _forward res if advance_pointer_p
      _matched((res if return_string_p))
    end

    def string=(str)
      @mb_pos = 0
      @mb_matched_size = nil
      @mb_last_pos = nil
      super
    end

    def terminate
      @mb_pos = string.size
      @mb_matched_size = nil
      @mb_last_pos = nil
      super
    end
    alias_method :clear, :terminate

    def unscan
      super
      @mb_pos = @mb_last_pos
      @mb_last_pos = @mb_matched_size = nil
    end

    private

    def _size(str)
      str && str.size
    end

    def _match(str)
      @mb_matched_size = str && str.size
      str
    end

    def _matched(res)
      _match matched
      res
    end

    def _forward(str)
      @mb_last_pos = @mb_pos
      @mb_pos += str.size if str
      str
    end
  end
end

module Sass
  # Handles Sass version-reporting.
  # Sass not only reports the standard three version numbers,
  # but its Git revision hash as well,
  # if it was installed from Git.
  module Version
    include Sass::Util

    # Returns a hash representing the version of Sass.
    # The `:major`, `:minor`, and `:teeny` keys have their respective numbers as Fixnums.
    # The `:name` key has the name of the version.
    # The `:string` key contains a human-readable string representation of the version.
    # The `:number` key is the major, minor, and teeny keys separated by periods.
    # The `:date` key, which is not guaranteed to be defined, is the [DateTime] at which this release was cut.
    # If Sass is checked out from Git, the `:rev` key will have the revision hash.
    # For example:
    #
    #     {
    #       :string => "2.1.0.9616393",
    #       :rev    => "9616393b8924ef36639c7e82aa88a51a24d16949",
    #       :number => "2.1.0",
    #       :date   => DateTime.parse("Apr 30 13:52:01 2009 -0700"),
    #       :major  => 2, :minor => 1, :teeny => 0
    #     }
    #
    # If a prerelease version of Sass is being used,
    # the `:string` and `:number` fields will reflect the full version
    # (e.g. `"2.2.beta.1"`), and the `:teeny` field will be `-1`.
    # A `:prerelease` key will contain the name of the prerelease (e.g. `"beta"`),
    # and a `:prerelease_number` key will contain the rerelease number.
    # For example:
    #
    #     {
    #       :string => "3.0.beta.1",
    #       :number => "3.0.beta.1",
    #       :date   => DateTime.parse("Mar 31 00:38:04 2010 -0700"),
    #       :major => 3, :minor => 0, :teeny => -1,
    #       :prerelease => "beta",
    #       :prerelease_number => 1
    #     }
    #
    # @return [{Symbol => String/Fixnum}] The version hash
    def version
      return @@version if defined?(@@version)

	  #RG numbers = File.read(scope('VERSION')).strip.split('.').
      numbers = '3.2.9'.strip.split('.').
        map {|n| n =~ /^[0-9]+$/ ? n.to_i : n}
      #RG name = File.read(scope('VERSION_NAME')).strip
      name = 'Media Mark'.strip
      @@version = {
        :major => numbers[0],
        :minor => numbers[1],
        :teeny => numbers[2],
        :name => name
      }

      if date = version_date
        @@version[:date] = date
      end

      if numbers[3].is_a?(String)
        @@version[:teeny] = -1
        @@version[:prerelease] = numbers[3]
        @@version[:prerelease_number] = numbers[4]
      end

      @@version[:number] = numbers.join('.')
      @@version[:string] = @@version[:number].dup

      if rev = revision_number
        @@version[:rev] = rev
        unless rev[0] == ?(
          @@version[:string] << "." << rev[0...7]
        end
      end

      @@version[:string] << " (#{name})"
      @@version
    end

    private

    def revision_number
      if File.exists?(scope('REVISION'))
        rev = File.read(scope('REVISION')).strip
        return rev unless rev =~ /^([a-f0-9]+|\(.*\))$/ || rev == '(unknown)'
      end

      return unless File.exists?(scope('.git/HEAD'))
      rev = File.read(scope('.git/HEAD')).strip
      return rev unless rev =~ /^ref: (.*)$/

      ref_name = $1
      ref_file = scope(".git/#{ref_name}")
      info_file = scope(".git/info/refs")
      return File.read(ref_file).strip if File.exists?(ref_file)
      return unless File.exists?(info_file)
      File.open(info_file) do |f|
        f.each do |l|
          sha, ref = l.strip.split("\t", 2)
          next unless ref == ref_name
          return sha
        end
      end
      return nil
    end

    def version_date
      return unless File.exists?(scope('VERSION_DATE'))
      return DateTime.parse(File.read(scope('VERSION_DATE')).strip)
    end
  end

  extend Sass::Version

  # A string representing the version of Sass.
  # A more fine-grained representation is available from Sass.version.
  # @api public
  VERSION = version[:string] unless defined?(Sass::VERSION)
end

# The module that contains everything Sass-related:
#
# * {Sass::Engine} is the class used to render Sass/SCSS within Ruby code.
# * {Sass::Plugin} is interfaces with web frameworks (Rails and Merb in particular).
# * {Sass::SyntaxError} is raised when Sass encounters an error.
# * {Sass::CSS} handles conversion of CSS to Sass.
#
# Also see the {file:SASS_REFERENCE.md full Sass reference}.
module Sass
  # The global load paths for Sass files. This is meant for plugins and
  # libraries to register the paths to their Sass stylesheets to that they may
  # be `@imported`. This load path is used by every instance of [Sass::Engine].
  # They are lower-precedence than any load paths passed in via the
  # {file:SASS_REFERENCE.md#load_paths-option `:load_paths` option}.
  #
  # If the `SASS_PATH` environment variable is set,
  # the initial value of `load_paths` will be initialized based on that.
  # The variable should be a colon-separated list of path names
  # (semicolon-separated on Windows).
  #
  # Note that files on the global load path are never compiled to CSS
  # themselves, even if they aren't partials. They exist only to be imported.
  #
  # @example
  #   Sass.load_paths << File.dirname(__FILE__ + '/sass')
  # @return [Array<String, Pathname, Sass::Importers::Base>]
  def self.load_paths
    @load_paths ||= ENV['SASS_PATH'] ?
      ENV['SASS_PATH'].split(Sass::Util.windows? ? ';' : ':') : []
  end

  # Compile a Sass or SCSS string to CSS.
  # Defaults to SCSS.
  #
  # @param contents [String] The contents of the Sass file.
  # @param options [{Symbol => Object}] An options hash;
  #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
  # @raise [Sass::SyntaxError] if there's an error in the document
  # @raise [Encoding::UndefinedConversionError] if the source encoding
  #   cannot be converted to UTF-8
  # @raise [ArgumentError] if the document uses an unknown encoding with `@charset`
  def self.compile(contents, options = {})
    options[:syntax] ||= :scss
    Engine.new(contents, options).to_css
  end

  # Compile a file on disk to CSS.
  #
  # @param filename [String] The path to the Sass, SCSS, or CSS file on disk.
  # @param options [{Symbol => Object}] An options hash;
  #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
  # @raise [Sass::SyntaxError] if there's an error in the document
  # @raise [Encoding::UndefinedConversionError] if the source encoding
  #   cannot be converted to UTF-8
  # @raise [ArgumentError] if the document uses an unknown encoding with `@charset`
  #
  # @overload compile_file(filename, options = {})
  #   Return the compiled CSS rather than writing it to a file.
  #
  #   @return [String] The compiled CSS.
  #
  # @overload compile_file(filename, css_filename, options = {})
  #   Write the compiled CSS to a file.
  #
  #   @param css_filename [String] The location to which to write the compiled CSS.
  def self.compile_file(filename, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    css_filename = args.shift
    result = Sass::Engine.for_file(filename, options).render
    if css_filename
      options[:css_filename] ||= css_filename
      open(css_filename,"w") {|css_file| css_file.write(result)}
      nil
    else
      result
    end
  end
end

module Sass::Logger

end

module Sass
  module Logger
    module LogLevel

      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
        def inherited(subclass)
          subclass.log_levels = subclass.superclass.log_levels.dup
        end

        def log_levels
          @log_levels ||= {}
        end

        def log_levels=(levels)
          @log_levels = levels
        end

        def log_level?(level, min_level)
          log_levels[level] >= log_levels[min_level]
        end

        def log_level(name, options = {})
          if options[:prepend]
            level = log_levels.values.min
            level = level.nil? ? 0 : level - 1
          else
            level = log_levels.values.max
            level = level.nil? ? 0 : level + 1
          end
          log_levels.update(name => level)
          define_logger(name)
        end

        def define_logger(name, options = {})
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{name}(message)
              #{options.fetch(:to, :log)}(#{name.inspect}, message)
            end
          RUBY
        end
      end
      
    end
  end
end 

class Sass::Logger::Base
  
  include Sass::Logger::LogLevel

  attr_accessor :log_level
  attr_accessor :disabled

  log_level :trace
  log_level :debug
  log_level :info
  log_level :warn
  log_level :error

  def initialize(log_level = :debug)
    self.log_level = log_level
  end

  def logging_level?(level)
    !disabled && self.class.log_level?(level, log_level)
  end

  def log(level, message)
    self._log(level, message) if logging_level?(level)
  end

  def _log(level, message)
    Kernel::warn(message)
  end

end

module Sass

  class << self
    attr_accessor :logger
  end

  self.logger = Sass::Logger::Base.new
end

require 'digest/sha1'

module Sass
  # Sass cache stores are in charge of storing cached information,
  # especially parse trees for Sass documents.
  #
  # User-created importers must inherit from {CacheStores::Base}.
  module CacheStores
  end
end

module Sass
  module CacheStores
    # An abstract base class for backends for the Sass cache.
    # Any key-value store can act as such a backend;
    # it just needs to implement the
    # \{#_store} and \{#_retrieve} methods.
    #
    # To use a cache store with Sass,
    # use the {file:SASS_REFERENCE.md#cache_store-option `:cache_store` option}.
    #
    # @abstract
    class Base
      # Store cached contents for later retrieval
      # Must be implemented by all CacheStore subclasses
      #
      # Note: cache contents contain binary data.
      #
      # @param key [String] The key to store the contents under
      # @param version [String] The current sass version.
      #                Cached contents must not be retrieved across different versions of sass.
      # @param sha [String] The sha of the sass source.
      #                Cached contents must not be retrieved if the sha has changed.
      # @param contents [String] The contents to store.
      def _store(key, version, sha, contents)
        raise "#{self.class} must implement #_store."
      end

      # Retrieved cached contents.
      # Must be implemented by all subclasses.
      # 
      # Note: if the key exists but the sha or version have changed,
      # then the key may be deleted by the cache store, if it wants to do so.
      #
      # @param key [String] The key to retrieve
      # @param version [String] The current sass version.
      #                Cached contents must not be retrieved across different versions of sass.
      # @param sha [String] The sha of the sass source.
      #                Cached contents must not be retrieved if the sha has changed.
      # @return [String] The contents that were previously stored.
      # @return [NilClass] when the cache key is not found or the version or sha have changed.
      def _retrieve(key, version, sha)
        raise "#{self.class} must implement #_retrieve."
      end

      # Store a {Sass::Tree::RootNode}.
      #
      # @param key [String] The key to store it under.
      # @param sha [String] The checksum for the contents that are being stored.
      # @param obj [Object] The object to cache.
      def store(key, sha, root)
        _store(key, Sass::VERSION, sha, Marshal.dump(root))
      rescue TypeError, LoadError => e
        Sass::Util.sass_warn "Warning. Error encountered while saving cache #{path_to(key)}: #{e}"
        nil
      end

      # Retrieve a {Sass::Tree::RootNode}.
      #
      # @param key [String] The key the root element was stored under.
      # @param sha [String] The checksum of the root element's content.
      # @return [Object] The cached object.
      def retrieve(key, sha)
        contents = _retrieve(key, Sass::VERSION, sha)
        Marshal.load(contents) if contents
      rescue EOFError, TypeError, ArgumentError, LoadError => e
        Sass::Util.sass_warn "Warning. Error encountered while reading cache #{path_to(key)}: #{e}"
        nil
      end

      # Return the key for the sass file.
      #
      # The `(sass_dirname, sass_basename)` pair
      # should uniquely identify the Sass document,
      # but otherwise there are no restrictions on their content.
      #
      # @param sass_dirname [String]
      #   The fully-expanded location of the Sass file.
      #   This corresponds to the directory name on a filesystem.
      # @param sass_basename [String] The name of the Sass file that is being referenced.
      #   This corresponds to the basename on a filesystem.
      def key(sass_dirname, sass_basename)
        dir = Digest::SHA1.hexdigest(sass_dirname)
        filename = "#{sass_basename}c"
        "#{dir}/#{filename}"
      end
    end
  end
end
require 'fileutils'

module Sass
  module CacheStores
    # A backend for the Sass cache using the filesystem.
    class Filesystem < Base
      # The directory where the cached files will be stored.
      #
      # @return [String]
      attr_accessor :cache_location

      # @param cache_location [String] see \{#cache\_location}
      def initialize(cache_location)
        @cache_location = cache_location
      end

      # @see Base#\_retrieve
      def _retrieve(key, version, sha)
        return unless File.readable?(path_to(key))
        File.open(path_to(key), "rb") do |f|
          if f.readline("\n").strip == version && f.readline("\n").strip == sha
            return f.read
          end
        end
        File.unlink path_to(key)
        nil
      rescue EOFError, TypeError, ArgumentError => e
        Sass::Util.sass_warn "Warning. Error encountered while reading cache #{path_to(key)}: #{e}"
      end

      # @see Base#\_store
      def _store(key, version, sha, contents)
        # return unless File.writable?(File.dirname(@cache_location))
        # return if File.exists?(@cache_location) && !File.writable?(@cache_location)
        compiled_filename = path_to(key)
        # return if File.exists?(File.dirname(compiled_filename)) && !File.writable?(File.dirname(compiled_filename))
        # return if File.exists?(compiled_filename) && !File.writable?(compiled_filename)
        FileUtils.mkdir_p(File.dirname(compiled_filename))
        Sass::Util.atomic_create_and_write_file(compiled_filename) do |f|
          f.puts(version)
          f.puts(sha)
          f.write(contents)
        end
      rescue Errno::EACCES
        #pass
      end

      private

      # Returns the path to a file for the given key.
      #
      # @param key [String]
      # @return [String] The path to the cache file.
      def path_to(key)
        key = key.gsub(/[<>:\\|?*%]/) {|c| "%%%03d" % Sass::Util.ord(c)}
        File.join(cache_location, key)
      end
    end
  end
end
module Sass
  module CacheStores
    # A backend for the Sass cache using in-process memory.
    class Memory < Base
      # Since the {Memory} store is stored in the Sass tree's options hash,
      # when the options get serialized as part of serializing the tree,
      # you get crazy exponential growth in the size of the cached objects
      # unless you don't dump the cache.
      #
      # @private
      def _dump(depth)
        ""
      end

      # If we deserialize this class, just make a new empty one.
      #
      # @private
      def self._load(repr)
        Memory.new
      end

      # Create a new, empty cache store.
      def initialize
        @contents = {}
      end

      # @see Base#retrieve
      def retrieve(key, sha)
        if @contents.has_key?(key)
          return unless @contents[key][:sha] == sha
          obj = @contents[key][:obj]
          obj.respond_to?(:deep_copy) ? obj.deep_copy : obj.dup
        end
      end

      # @see Base#store
      def store(key, sha, obj)
        @contents[key] = {:sha => sha, :obj => obj}
      end
      
      # Destructively clear the cache.
      def reset!
        @contents = {}
      end
    end
  end
end
module Sass
  module CacheStores
    # A meta-cache that chains multiple caches together.
    # Specifically:
    #
    # * All `#store`s are passed to all caches.
    # * `#retrieve`s are passed to each cache until one has a hit.
    # * When one cache has a hit, the value is `#store`d in all earlier caches.
    class Chain < Base
      # Create a new cache chaining the given caches.
      #
      # @param caches [Array<Sass::CacheStores::Base>] The caches to chain.
      def initialize(*caches)
        @caches = caches
      end

      # @see Base#store
      def store(key, sha, obj)
        @caches.each {|c| c.store(key, sha, obj)}
      end

      # @see Base#retrieve
      def retrieve(key, sha)
        @caches.each_with_index do |c, i|
          next unless obj = c.retrieve(key, sha)
          @caches[0...i].each {|prev| prev.store(key, sha, obj)}
          return obj
        end
        nil
      end
    end
  end
end
module Sass
  # A namespace for nodes in the Sass parse tree.
  #
  # The Sass parse tree has three states: dynamic, static Sass, and static CSS.
  #
  # When it's first parsed, a Sass document is in the dynamic state.
  # It has nodes for mixin definitions and `@for` loops and so forth,
  # in addition to nodes for CSS rules and properties.
  # Nodes that only appear in this state are called **dynamic nodes**.
  #
  # {Tree::Visitors::Perform} creates a static Sass tree, which is different.
  # It still has nodes for CSS rules and properties
  # but it doesn't have any dynamic-generation-related nodes.
  # The nodes in this state are in the same structure as the Sass document:
  # rules and properties are nested beneath one another.
  # Nodes that can be in this state or in the dynamic state
  # are called **static nodes**; nodes that can only be in this state
  # are called **solely static nodes**.
  #
  # {Tree::Visitors::Cssize} is then used to create a static CSS tree.
  # This is like a static Sass tree,
  # but the structure exactly mirrors that of the generated CSS.
  # Rules and properties can't be nested beneath one another in this state.
  #
  # Finally, {Tree::Visitors::ToCss} can be called on a static CSS tree
  # to get the actual CSS code as a string.
  module Tree
    # The abstract superclass of all parse-tree nodes.
    class Node
      include Enumerable

      # The child nodes of this node.
      #
      # @return [Array<Tree::Node>]
      attr_accessor :children

      # Whether or not this node has child nodes.
      # This may be true even when \{#children} is empty,
      # in which case this node has an empty block (e.g. `{}`).
      #
      # @return [Boolean]
      attr_accessor :has_children

      # The line of the document on which this node appeared.
      #
      # @return [Fixnum]
      attr_accessor :line

      # The name of the document on which this node appeared.
      #
      # @return [String]
      attr_writer :filename

      # The options hash for the node.
      # See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
      #
      # @return [{Symbol => Object}]
      attr_reader :options

      def initialize
        @children = []
      end

      # Sets the options hash for the node and all its children.
      #
      # @param options [{Symbol => Object}] The options
      # @see #options
      def options=(options)
        Sass::Tree::Visitors::SetOptions.visit(self, options)
      end

      # @private
      def children=(children)
        self.has_children ||= !children.empty?
        @children = children
      end

      # The name of the document on which this node appeared.
      #
      # @return [String]
      def filename
        @filename || (@options && @options[:filename])
      end

      # Appends a child to the node.
      #
      # @param child [Tree::Node, Array<Tree::Node>] The child node or nodes
      # @raise [Sass::SyntaxError] if `child` is invalid
      def <<(child)
        return if child.nil?
        if child.is_a?(Array)
          child.each {|c| self << c}
        else
          self.has_children = true
          @children << child
        end
      end

      # Compares this node and another object (only other {Tree::Node}s will be equal).
      # This does a structural comparison;
      # if the contents of the nodes and all the child nodes are equivalent,
      # then the nodes are as well.
      #
      # Only static nodes need to override this.
      #
      # @param other [Object] The object to compare with
      # @return [Boolean] Whether or not this node and the other object
      #   are the same
      # @see Sass::Tree
      def ==(other)
        self.class == other.class && other.children == children
      end

      # True if \{#to\_s} will return `nil`;
      # that is, if the node shouldn't be rendered.
      # Should only be called in a static tree.
      #
      # @return [Boolean]
      def invisible?; false; end

      # The output style. See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
      #
      # @return [Symbol]
      def style
        @options[:style]
      end

      # Computes the CSS corresponding to this static CSS tree.
      #
      # @return [String, nil] The resulting CSS
      # @see Sass::Tree
      def to_s
        Sass::Tree::Visitors::ToCss.visit(self)
      end

      # Returns a representation of the node for debugging purposes.
      #
      # @return [String]
      def inspect
        return self.class.to_s unless has_children
        "(#{self.class} #{children.map {|c| c.inspect}.join(' ')})"
      end

      # Iterates through each node in the tree rooted at this node
      # in a pre-order walk.
      #
      # @yield node
      # @yieldparam node [Node] a node in the tree
      def each
        yield self
        children.each {|c| c.each {|n| yield n}}
      end

      # Converts a node to Sass code that will generate it.
      #
      # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize})
      # @return [String] The Sass code corresponding to the node
      def to_sass(options = {})
        Sass::Tree::Visitors::Convert.visit(self, options, :sass)
      end

      # Converts a node to SCSS code that will generate it.
      #
      # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize})
      # @return [String] The Sass code corresponding to the node
      def to_scss(options = {})
        Sass::Tree::Visitors::Convert.visit(self, options, :scss)
      end

      # Return a deep clone of this node.
      # The child nodes are cloned, but options are not.
      #
      # @return [Node]
      def deep_copy
        Sass::Tree::Visitors::DeepCopy.visit(self)
      end

      # Whether or not this node bubbles up through RuleNodes.
      #
      # @return [Boolean]
      def bubbles?
        false
      end

      protected

      # @see Sass::Shared.balance
      # @raise [Sass::SyntaxError] if the brackets aren't balanced
      def balance(*args)
        res = Sass::Shared.balance(*args)
        return res if res
        raise Sass::SyntaxError.new("Unbalanced brackets.", :line => line)
      end
    end
  end
end
module Sass
  module Tree
    # A static node that is the root node of the Sass document.
    class RootNode < Node
      # The Sass template from which this node was created
      #
      # @param template [String]
      attr_reader :template

      # @param template [String] The Sass template from which this node was created
      def initialize(template)
        super()
        @template = template
      end

      # Runs the dynamic Sass code *and* computes the CSS for the tree.
      # @see #to_s
      def render
        Visitors::CheckNesting.visit(self)
        result = Visitors::Perform.visit(self)
        Visitors::CheckNesting.visit(result) # Check again to validate mixins
        result, extends = Visitors::Cssize.visit(result)
        Visitors::Extend.visit(result, extends)
        result.to_s
      end
    end
  end
end
require 'pathname'
require 'uri'

module Sass::Tree
  # A static node reprenting a CSS rule.
  #
  # @see Sass::Tree
  class RuleNode < Node
    # The character used to include the parent selector
    PARENT = '&'

    # The CSS selector for this rule,
    # interspersed with {Sass::Script::Node}s
    # representing `#{}`-interpolation.
    # Any adjacent strings will be merged together.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :rule

    # The CSS selector for this rule,
    # without any unresolved interpolation
    # but with parent references still intact.
    # It's only set once {Tree::Node#perform} has been called.
    #
    # @return [Selector::CommaSequence]
    attr_accessor :parsed_rules

    # The CSS selector for this rule,
    # without any unresolved interpolation or parent references.
    # It's only set once {Tree::Visitors::Cssize} has been run.
    #
    # @return [Selector::CommaSequence]
    attr_accessor :resolved_rules

    # How deep this rule is indented
    # relative to a base-level rule.
    # This is only greater than 0 in the case that:
    #
    # * This node is in a CSS tree
    # * The style is :nested
    # * This is a child rule of another rule
    # * The parent rule has properties, and thus will be rendered
    #
    # @return [Fixnum]
    attr_accessor :tabs

    # Whether or not this rule is the last rule in a nested group.
    # This is only set in a CSS tree.
    #
    # @return [Boolean]
    attr_accessor :group_end

    # The stack trace.
    # This is only readable in a CSS tree as it is written during the perform step
    # and only when the :trace_selectors option is set.
    #
    # @return [Array<String>]
    attr_accessor :stack_trace

    # @param rule [Array<String, Sass::Script::Node>]
    #   The CSS rule. See \{#rule}
    def initialize(rule)
      merged = Sass::Util.merge_adjacent_strings(rule)
      @rule = Sass::Util.strip_string_array(merged)
      @tabs = 0
      try_to_parse_non_interpolated_rules
      super()
    end

    # If we've precached the parsed selector, set the line on it, too.
    def line=(line)
      @parsed_rules.line = line if @parsed_rules
      super
    end

    # If we've precached the parsed selector, set the filename on it, too.
    def filename=(filename)
      @parsed_rules.filename = filename if @parsed_rules
      super
    end

    # Compares the contents of two rules.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] Whether or not this node and the other object
    #   are the same
    def ==(other)
      self.class == other.class && rule == other.rule && super
    end

    # Adds another {RuleNode}'s rules to this one's.
    #
    # @param node [RuleNode] The other node
    def add_rules(node)
      @rule = Sass::Util.strip_string_array(
        Sass::Util.merge_adjacent_strings(@rule + ["\n"] + node.rule))
      try_to_parse_non_interpolated_rules
    end

    # @return [Boolean] Whether or not this rule is continued on the next line
    def continued?
      last = @rule.last
      last.is_a?(String) && last[-1] == ?,
    end

    # A hash that will be associated with this rule in the CSS document
    # if the {file:SASS_REFERENCE.md#debug_info-option `:debug_info` option} is enabled.
    # This data is used by e.g. [the FireSass Firebug extension](https://addons.mozilla.org/en-US/firefox/addon/103988).
    #
    # @return [{#to_s => #to_s}]
    def debug_info
      {:filename => filename && ("file://" + URI.escape(filename)),
       :line => self.line}
    end

    # A rule node is invisible if it has only placeholder selectors.
    def invisible?
      resolved_rules.members.all? {|seq| seq.has_placeholder?}
    end

    private

    def try_to_parse_non_interpolated_rules
      if @rule.all? {|t| t.kind_of?(String)}
        # We don't use real filename/line info because we don't have it yet.
        # When we get it, we'll set it on the parsed rules if possible.
        parser = Sass::SCSS::StaticParser.new(@rule.join.strip, '', 1)
        @parsed_rules = parser.parse_selector rescue nil
      end
    end
  end
end

module Sass::Tree
  # A static node representing a Sass comment (silent or loud).
  #
  # @see Sass::Tree
  class CommentNode < Node
    # The text of the comment, not including `/*` and `*/`.
    # Interspersed with {Sass::Script::Node}s representing `#{}`-interpolation
    # if this is a loud comment.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :value

    # The text of the comment
    # after any interpolated SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_value

    # The type of the comment. `:silent` means it's never output to CSS,
    # `:normal` means it's output in every compile mode except `:compressed`,
    # and `:loud` means it's output even in `:compressed`.
    #
    # @return [Symbol]
    attr_accessor :type

    # @param value [Array<String, Sass::Script::Node>] See \{#value}
    # @param type [Symbol] See \{#type}
    def initialize(value, type)
      @value = Sass::Util.with_extracted_values(value) {|str| normalize_indentation str}
      @type = type
      super()
    end

    # Compares the contents of two comments.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] Whether or not this node and the other object
    #   are the same
    def ==(other)
      self.class == other.class && value == other.value && type == other.type
    end

    # Returns `true` if this is a silent comment
    # or the current style doesn't render comments.
    #
    # Comments starting with ! are never invisible (and the ! is removed from the output.)
    #
    # @return [Boolean]
    def invisible?
      case @type
      when :loud; false
      when :silent; true
      else; style == :compressed
      end
    end

    # Returns the number of lines in the comment.
    #
    # @return [Fixnum]
    def lines
      @value.inject(0) do |s, e|
        next s + e.count("\n") if e.is_a?(String)
        next s
      end
    end

    private

    def normalize_indentation(str)
      ind = str.split("\n").inject(str[/^[ \t]*/].split("")) do |pre, line|
        line[/^[ \t]*/].split("").zip(pre).inject([]) do |arr, (a, b)|
          break arr if a != b
          arr << a
        end
      end.join
      str.gsub(/^#{ind}/, '')
    end
  end
end
module Sass::Tree
  # A static node reprenting a CSS property.
  #
  # @see Sass::Tree
  class PropNode < Node
    # The name of the property,
    # interspersed with {Sass::Script::Node}s
    # representing `#{}`-interpolation.
    # Any adjacent strings will be merged together.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :name

    # The name of the property
    # after any interpolated SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_name

    # The value of the property.
    #
    # @return [Sass::Script::Node]
    attr_accessor :value

    # The value of the property
    # after any interpolated SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_value

    # How deep this property is indented
    # relative to a normal property.
    # This is only greater than 0 in the case that:
    #
    # * This node is in a CSS tree
    # * The style is :nested
    # * This is a child property of another property
    # * The parent property has a value, and thus will be rendered
    #
    # @return [Fixnum]
    attr_accessor :tabs

    # @param name [Array<String, Sass::Script::Node>] See \{#name}
    # @param value [Sass::Script::Node] See \{#value}
    # @param prop_syntax [Symbol] `:new` if this property uses `a: b`-style syntax,
    #   `:old` if it uses `:a b`-style syntax
    def initialize(name, value, prop_syntax)
      @name = Sass::Util.strip_string_array(
        Sass::Util.merge_adjacent_strings(name))
      @value = value
      @tabs = 0
      @prop_syntax = prop_syntax
      super()
    end

    # Compares the names and values of two properties.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] Whether or not this node and the other object
    #   are the same
    def ==(other)
      self.class == other.class && name == other.name && value == other.value && super
    end

    # Returns a appropriate message indicating how to escape pseudo-class selectors.
    # This only applies for old-style properties with no value,
    # so returns the empty string if this is new-style.
    #
    # @return [String] The message
    def pseudo_class_selector_message
      return "" if @prop_syntax == :new || !value.is_a?(Sass::Script::String) || !value.value.empty?
      "\nIf #{declaration.dump} should be a selector, use \"\\#{declaration}\" instead."
    end

    # Computes the Sass or SCSS code for the variable declaration.
    # This is like \{#to\_scss} or \{#to\_sass},
    # except it doesn't print any child properties or a trailing semicolon.
    #
    # @param opts [{Symbol => Object}] The options hash for the tree.
    # @param fmt [Symbol] `:scss` or `:sass`.
    def declaration(opts = {:old => @prop_syntax == :old}, fmt = :sass)
      name = self.name.map {|n| n.is_a?(String) ? n : "\#{#{n.to_sass(opts)}}"}.join
      if name[0] == ?:
        raise Sass::SyntaxError.new("The \"#{name}: #{self.class.val_to_sass(value, opts)}\" hack is not allowed in the Sass indented syntax")
      end

      old = opts[:old] && fmt == :sass
      initial = old ? ':' : ''
      mid = old ? '' : ':'
      "#{initial}#{name}#{mid} #{self.class.val_to_sass(value, opts)}".rstrip
    end

    # A property node is invisible if its value is empty.
    #
    # @return [Boolean]
    def invisible?
      resolved_value.empty?
    end

    private

    def check!
      if @options[:property_syntax] && @options[:property_syntax] != @prop_syntax
        raise Sass::SyntaxError.new(
          "Illegal property syntax: can't use #{@prop_syntax} syntax when :property_syntax => #{@options[:property_syntax].inspect} is set.")
      end
    end

    class << self
      # @private
      def val_to_sass(value, opts)
        val_to_sass_comma(value, opts).to_sass(opts)
      end

      private

      def val_to_sass_comma(node, opts)
        return node unless node.is_a?(Sass::Script::Operation)
        return val_to_sass_concat(node, opts) unless node.operator == :comma

        Sass::Script::Operation.new(
          val_to_sass_concat(node.operand1, opts),
          val_to_sass_comma(node.operand2, opts),
          node.operator)
      end

      def val_to_sass_concat(node, opts)
        return node unless node.is_a?(Sass::Script::Operation)
        return val_to_sass_div(node, opts) unless node.operator == :space

        Sass::Script::Operation.new(
          val_to_sass_div(node.operand1, opts),
          val_to_sass_concat(node.operand2, opts),
          node.operator)
      end

      def val_to_sass_div(node, opts)
        unless node.is_a?(Sass::Script::Operation) && node.operator == :div &&
            node.operand1.is_a?(Sass::Script::Number) &&
            node.operand2.is_a?(Sass::Script::Number) &&
            (!node.operand1.original || !node.operand2.original)
          return node
        end

        Sass::Script::String.new("(#{node.to_sass(opts)})")
      end

    end
  end
end
module Sass::Tree
  # A static node representing an unproccessed Sass `@`-directive.
  # Directives known to Sass, like `@for` and `@debug`,
  # are handled by their own nodes;
  # only CSS directives like `@media` and `@font-face` become {DirectiveNode}s.
  #
  # `@import` and `@charset` are special cases;
  # they become {ImportNode}s and {CharsetNode}s, respectively.
  #
  # @see Sass::Tree
  class DirectiveNode < Node
    # The text of the directive, `@` and all, with interpolation included.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :value

    # The text of the directive after any interpolated SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_value

    # @param value [Array<String, Sass::Script::Node>] See \{#value}
    def initialize(value)
      @value = value
      super()
    end

    # @param value [String] See \{#resolved_value}
    # @return [DirectiveNode]
    def self.resolved(value)
      node = new([value])
      node.resolved_value = value
      node
    end

    # @return [String] The name of the directive, including `@`.
    def name
      value.first.gsub(/ .*$/, '')
    end
  end
end
module Sass::Tree
  # A static node representing a `@media` rule.
  # `@media` rules behave differently from other directives
  # in that when they're nested within rules,
  # they bubble up to top-level.
  #
  # @see Sass::Tree
  class MediaNode < DirectiveNode
    # TODO: parse and cache the query immediately if it has no dynamic elements

    # The media query for this rule, interspersed with {Sass::Script::Node}s
    # representing `#{}`-interpolation. Any adjacent strings will be merged
    # together.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :query

    # The media query for this rule, without any unresolved interpolation. It's
    # only set once {Tree::Node#perform} has been called.
    #
    # @return [Sass::Media::QueryList]
    attr_accessor :resolved_query

    # @see RuleNode#tabs
    attr_accessor :tabs

    # @see RuleNode#group_end
    attr_accessor :group_end

    # @param query [Array<String, Sass::Script::Node>] See \{#query}
    def initialize(query)
      @query = query
      @tabs = 0
      super('')
    end

    # @see DirectiveNode#value
    def value; raise NotImplementedError; end

    # @see DirectiveNode#name
    def name; '@media'; end

    # @see DirectiveNode#resolved_value
    def resolved_value
      @resolved_value ||= "@media #{resolved_query.to_css}"
    end

    # True when the directive has no visible children.
    #
    # @return [Boolean]
    def invisible?
      children.all? {|c| c.invisible?}
    end

    # @see Node#bubbles?
    def bubbles?; true; end
  end
end
module Sass::Tree
  # A static node representing a `@supports` rule.
  # `@supports` rules behave differently from other directives
  # in that when they're nested within rules,
  # they bubble up to top-level.
  #
  # @see Sass::Tree
  class SupportsNode < DirectiveNode
    # The name, which may include a browser prefix.
    #
    # @return [String]
    attr_accessor :name

    # The supports condition.
    #
    # @return [Sass::Supports::Condition]
    attr_accessor :condition

    # @see RuleNode#tabs
    attr_accessor :tabs

    # @see RuleNode#group_end
    attr_accessor :group_end

    # @param condition [Sass::Supports::Condition] See \{#condition}
    def initialize(name, condition)
      @name = name
      @condition = condition
      @tabs = 0
      super('')
    end

    # @see DirectiveNode#value
    def value; raise NotImplementedError; end

    # @see DirectiveNode#resolved_value
    def resolved_value
      @resolved_value ||= "@#{name} #{condition.to_css}"
    end

    # True when the directive has no visible children.
    #
    # @return [Boolean]
    def invisible?
      children.all? {|c| c.invisible?}
    end

    # @see Node#bubbles?
    def bubbles?; true; end
  end
end
module Sass::Tree
  # A node representing an `@import` rule that's importing plain CSS.
  #
  # @see Sass::Tree
  class CssImportNode < DirectiveNode
    # The URI being imported, either as a plain string or an interpolated
    # script string.
    #
    # @return [String, Sass::Script::Node]
    attr_accessor :uri

    # The text of the URI being imported after any interpolated SassScript has
    # been resolved. Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_uri

    # The media query for this rule, interspersed with {Sass::Script::Node}s
    # representing `#{}`-interpolation. Any adjacent strings will be merged
    # together.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :query

    # The media query for this rule, without any unresolved interpolation. It's
    # only set once {Tree::Node#perform} has been called.
    #
    # @return [Sass::Media::QueryList]
    attr_accessor :resolved_query

    # @param uri [String, Sass::Script::Node] See \{#uri}
    # @param query [Array<String, Sass::Script::Node>] See \{#query}
    def initialize(uri, query = nil)
      @uri = uri
      @query = query
      super('')
    end

    # @param uri [String] See \{#resolved_uri}
    # @return [CssImportNode]
    def self.resolved(uri)
      node = new(uri)
      node.resolved_uri = uri
      node
    end

    # @see DirectiveNode#value
    def value; raise NotImplementedError; end

    # @see DirectiveNode#resolved_value
    def resolved_value
      @resolved_value ||=
        begin
          str = "@import #{resolved_uri}"
          str << " #{resolved_query.to_css}" if resolved_query
          str
        end
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing a variable definition.
    #
    # @see Sass::Tree
    class VariableNode < Node
      # The name of the variable.
      # @return [String]
      attr_reader :name

      # The parse tree for the variable value.
      # @return [Script::Node]
      attr_accessor :expr

      # Whether this is a guarded variable assignment (`!default`).
      # @return [Boolean]
      attr_reader :guarded

      # @param name [String] The name of the variable
      # @param expr [Script::Node] See \{#expr}
      # @param guarded [Boolean] See \{#guarded}
      def initialize(name, expr, guarded)
        @name = name
        @expr = expr
        @guarded = guarded
        super()
      end
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing a mixin definition.
    #
    # @see Sass::Tree
    class MixinDefNode < Node
      # The mixin name.
      # @return [String]
      attr_reader :name

      # The arguments for the mixin.
      # Each element is a tuple containing the variable for argument
      # and the parse tree for the default value of the argument.
      #
      # @return [Array<(Script::Node, Script::Node)>]
      attr_accessor :args

      # The splat argument for this mixin, if one exists.
      #
      # @return [Script::Node?]
      attr_accessor :splat

      # Whether the mixin uses `@content`. Set during the nesting check phase.
      # @return [Boolean]
      attr_accessor :has_content

      # @param name [String] The mixin name
      # @param args [Array<(Script::Node, Script::Node)>] See \{#args}
      # @param splat [Script::Node] See \{#splat}
      def initialize(name, args, splat)
        @name = name
        @args = args
        @splat = splat
        super()
      end
    end
  end
end

module Sass::Tree
  # A static node representing a mixin include.
  # When in a static tree, the sole purpose is to wrap exceptions
  # to add the mixin to the backtrace.
  #
  # @see Sass::Tree
  class MixinNode < Node
    # The name of the mixin.
    # @return [String]
    attr_reader :name

    # The arguments to the mixin.
    # @return [Array<Script::Node>]
    attr_accessor :args

    # A hash from keyword argument names to values.
    # @return [{String => Script::Node}]
    attr_accessor :keywords

    # The splat argument for this mixin, if one exists.
    #
    # @return [Script::Node?]
    attr_accessor :splat

    # @param name [String] The name of the mixin
    # @param args [Array<Script::Node>] See \{#args}
    # @param splat [Script::Node] See \{#splat}
    # @param keywords [{String => Script::Node}] See \{#keywords}
    def initialize(name, args, keywords, splat)
      @name = name
      @args = args
      @keywords = keywords
      @splat = splat
      super()
    end
  end
end

module Sass::Tree
  # A solely static node left over after a mixin include or @content has been performed.
  # Its sole purpose is to wrap exceptions to add to the backtrace.
  #
  # @see Sass::Tree
  class TraceNode < Node
    # The name of the trace entry to add.
    # @return [String]
    attr_reader :name

    # @param name [String] The name of the trace entry to add.
    def initialize(name)
      @name = name
      self.has_children = true
      super()
    end

    # Initializes this node from an existing node.
    # @param name [String] The name of the trace entry to add.
    # @param mixin [Node] The node to copy information from.
    # @return [TraceNode]
    def self.from_node(name, node)
      trace = new(name)
      trace.line = node.line
      trace.filename = node.filename
      trace.options = node.options
      trace
    end
  end
end
module Sass
  module Tree
    # A node representing the placement within a mixin of the include statement's content.
    #
    # @see Sass::Tree
    class ContentNode < Node
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing a function definition.
    #
    # @see Sass::Tree
    class FunctionNode < Node
      # The name of the function.
      # @return [String]
      attr_reader :name

      # The arguments to the function. Each element is a tuple
      # containing the variable for argument and the parse tree for
      # the default value of the argument
      #
      # @return [Array<Script::Node>]
      attr_accessor :args

      # The splat argument for this function, if one exists.
      #
      # @return [Script::Node?]
      attr_accessor :splat

      # @param name [String] The function name
      # @param args [Array<(Script::Node, Script::Node)>] The arguments for the function.
      # @param splat [Script::Node] See \{#splat}
      def initialize(name, args, splat)
        @name = name
        @args = args
        @splat = splat
        super()
      end
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing returning from a function.
    #
    # @see Sass::Tree
    class ReturnNode < Node
      # The expression to return.
      # @type [Script::Node]
      attr_accessor :expr

      # @param expr [Script::Node] The expression to return
      def initialize(expr)
        @expr = expr
        super()
      end
    end
  end
end

module Sass::Tree
  # A static node reprenting an `@extend` directive.
  #
  # @see Sass::Tree
  class ExtendNode < Node
    # The parsed selector after interpolation has been resolved.
    # Only set once {Tree::Visitors::Perform} has been run.
    #
    # @return [Selector::CommaSequence]
    attr_accessor :resolved_selector

    # The CSS selector to extend, interspersed with {Sass::Script::Node}s
    # representing `#{}`-interpolation.
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :selector

    # Whether the `@extend` is allowed to match no selectors or not.
    #
    # @return [Boolean]
    def optional?; @optional; end

    # @param selector [Array<String, Sass::Script::Node>]
    #   The CSS selector to extend,
    #   interspersed with {Sass::Script::Node}s
    #   representing `#{}`-interpolation.
    # @param optional [Boolean] See \{#optional}
    def initialize(selector, optional)
      @selector = selector
      @optional = optional
      super()
    end
  end
end

module Sass::Tree
  # A dynamic node representing a Sass `@if` statement.
  #
  # {IfNode}s are a little odd, in that they also represent `@else` and `@else if`s.
  # This is done as a linked list:
  # each {IfNode} has a link (\{#else}) to the next {IfNode}.
  #
  # @see Sass::Tree
  class IfNode < Node
    # The conditional expression.
    # If this is nil, this is an `@else` node, not an `@else if`.
    #
    # @return [Script::Expr]
    attr_accessor :expr

    # The next {IfNode} in the if-else list, or `nil`.
    #
    # @return [IfNode]
    attr_accessor :else

    # @param expr [Script::Expr] See \{#expr}
    def initialize(expr)
      @expr = expr
      @last_else = self
      super()
    end

    # Append an `@else` node to the end of the list.
    #
    # @param node [IfNode] The `@else` node to append
    def add_else(node)
      @last_else.else = node
      @last_else = node
    end

    def _dump(f)
      Marshal.dump([self.expr, self.else, self.children])
    end

    def self._load(data)
      expr, else_, children = Marshal.load(data)
      node = IfNode.new(expr)
      node.else = else_
      node.children = children
      node.instance_variable_set('@last_else',
        node.else ? node.else.instance_variable_get('@last_else') : node)
      node
    end
  end
end

module Sass::Tree
  # A dynamic node representing a Sass `@while` loop.
  #
  # @see Sass::Tree
  class WhileNode < Node
    # The parse tree for the continuation expression.
    # @return [Script::Node]
    attr_accessor :expr

    # @param expr [Script::Node] See \{#expr}
    def initialize(expr)
      @expr = expr
      super()
    end
  end
end

module Sass::Tree
  # A dynamic node representing a Sass `@for` loop.
  #
  # @see Sass::Tree
  class ForNode < Node
    # The name of the loop variable.
    # @return [String]
    attr_reader :var

    # The parse tree for the initial expression.
    # @return [Script::Node]
    attr_accessor :from

    # The parse tree for the final expression.
    # @return [Script::Node]
    attr_accessor :to

    # Whether to include `to` in the loop or stop just before.
    # @return [Boolean]
    attr_reader :exclusive

    # @param var [String] See \{#var}
    # @param from [Script::Node] See \{#from}
    # @param to [Script::Node] See \{#to}
    # @param exclusive [Boolean] See \{#exclusive}
    def initialize(var, from, to, exclusive)
      @var = var
      @from = from
      @to = to
      @exclusive = exclusive
      super()
    end
  end
end

module Sass::Tree
  # A dynamic node representing a Sass `@each` loop.
  #
  # @see Sass::Tree
  class EachNode < Node
    # The name of the loop variable.
    # @return [String]
    attr_reader :var

    # The parse tree for the list.
    # @param [Script::Node]
    attr_accessor :list

    # @param var [String] The name of the loop variable
    # @param list [Script::Node] The parse tree for the list
    def initialize(var, list)
      @var = var
      @list = list
      super()
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing a Sass `@debug` statement.
    #
    # @see Sass::Tree
    class DebugNode < Node
      # The expression to print.
      # @return [Script::Node] 
      attr_accessor :expr

      # @param expr [Script::Node] The expression to print
      def initialize(expr)
        @expr = expr
        super()
      end
    end
  end
end
module Sass
  module Tree
    # A dynamic node representing a Sass `@warn` statement.
    #
    # @see Sass::Tree
    class WarnNode < Node
      # The expression to print.
      # @return [Script::Node]
      attr_accessor :expr

      # @param expr [Script::Node] The expression to print
      def initialize(expr)
        @expr = expr
        super()
      end
    end
  end
end
module Sass
  module Tree
    # A static node that wraps the {Sass::Tree} for an `@import`ed file.
    # It doesn't have a functional purpose other than to add the `@import`ed file
    # to the backtrace if an error occurs.
    class ImportNode < RootNode
      # The name of the imported file as it appears in the Sass document.
      #
      # @return [String]
      attr_reader :imported_filename

      # Sets the imported file.
      attr_writer :imported_file

      # @param imported_filename [String] The name of the imported file
      def initialize(imported_filename)
        @imported_filename = imported_filename
        super(nil)
      end

      def invisible?; to_s.empty?; end

      # Returns the imported file.
      #
      # @return [Sass::Engine]
      # @raise [Sass::SyntaxError] If no file could be found to import.
      def imported_file
        @imported_file ||= import
      end

      # Returns whether or not this import should emit a CSS @import declaration
      #
      # @return [Boolean] Whether or not this is a simple CSS @import declaration.
      def css_import?
        if @imported_filename =~ /\.css$/
          @imported_filename
        elsif imported_file.is_a?(String) && imported_file =~ /\.css$/
          imported_file
        end
      end

      private

      def import
        paths = @options[:load_paths]

        if @options[:importer]
          f = @options[:importer].find_relative(
            @imported_filename, @options[:filename], options_for_importer)
          return f if f
        end

        paths.each do |p|
          if f = p.find(@imported_filename, options_for_importer)
            return f
          end
        end

        message = "File to import not found or unreadable: #{@imported_filename}.\n"
        if paths.size == 1
          message << "Load path: #{paths.first}"
        else
          message << "Load paths:\n  " << paths.join("\n  ")
        end
        raise SyntaxError.new(message)
      rescue SyntaxError => e
        raise SyntaxError.new(e.message, :line => self.line, :filename => @filename)
      end

      def options_for_importer
        @options.merge(:_line => line)
      end
    end
  end
end
module Sass::Tree
  # A static node representing an unproccessed Sass `@charset` directive.
  #
  # @see Sass::Tree
  class CharsetNode < Node
    # The name of the charset.
    #
    # @return [String]
    attr_accessor :name

    # @param name [String] see \{#name}
    def initialize(name)
      @name = name
      super()
    end

    # @see Node#invisible?
    def invisible?
      !Sass::Util.ruby1_8?
    end
  end
end
# Visitors are used to traverse the Sass parse tree.
# Visitors should extend {Visitors::Base},
# which provides a small amount of scaffolding for traversal.
module Sass::Tree::Visitors
  # The abstract base class for Sass visitors.
  # Visitors should extend this class,
  # then implement `visit_*` methods for each node they care about
  # (e.g. `visit_rule` for {RuleNode} or `visit_for` for {ForNode}).
  # These methods take the node in question as argument.
  # They may `yield` to visit the child nodes of the current node.
  #
  # *Note*: due to the unusual nature of {Sass::Tree::IfNode},
  # special care must be taken to ensure that it is properly handled.
  # In particular, there is no built-in scaffolding
  # for dealing with the return value of `@else` nodes.
  #
  # @abstract
  class Base
    # Runs the visitor on a tree.
    #
    # @param root [Tree::Node] The root node of the Sass tree.
    # @return [Object] The return value of \{#visit} for the root node.
    def self.visit(root)
      new.send(:visit, root)
    end

    protected

    # Runs the visitor on the given node.
    # This can be overridden by subclasses that need to do something for each node.
    #
    # @param node [Tree::Node] The node to visit.
    # @return [Object] The return value of the `visit_*` method for this node.
    def visit(node)
      method = "visit_#{node_name node}"
      if self.respond_to?(method, true)
        self.send(method, node) {visit_children(node)}
      else
        visit_children(node)
      end
    end

    # Visit the child nodes for a given node.
    # This can be overridden by subclasses that need to do something
    # with the child nodes' return values.
    #
    # This method is run when `visit_*` methods `yield`,
    # and its return value is returned from the `yield`.
    #
    # @param parent [Tree::Node] The parent node of the children to visit.
    # @return [Array<Object>] The return values of the `visit_*` methods for the children.
    def visit_children(parent)
      parent.children.map {|c| visit(c)}
    end

    NODE_NAME_RE = /.*::(.*?)Node$/

    # Returns the name of a node as used in the `visit_*` method.
    #
    # @param [Tree::Node] node The node.
    # @return [String] The name.
    def node_name(node)
      @@node_names ||= {}
      @@node_names[node.class.name] ||= node.class.name.gsub(NODE_NAME_RE, '\\1').downcase
    end

    # `yield`s, then runs the visitor on the `@else` clause if the node has one.
    # This exists to ensure that the contents of the `@else` clause get visited.
    def visit_if(node)
      yield
      visit(node.else) if node.else
      node
    end
  end
end
# A visitor for converting a dynamic Sass tree into a static Sass tree.
class Sass::Tree::Visitors::Perform < Sass::Tree::Visitors::Base
  # @param root [Tree::Node] The root node of the tree to visit.
  # @param environment [Sass::Environment] The lexical environment.
  # @return [Tree::Node] The resulting tree of static nodes.
  def self.visit(root, environment = Sass::Environment.new)
    new(environment).send(:visit, root)
  end

  # @api private
  def self.perform_arguments(callable, args, keywords, splat)
    desc = "#{callable.type.capitalize} #{callable.name}"
    downcase_desc = "#{callable.type} #{callable.name}"

    begin
      unless keywords.empty?
        unknown_args = Sass::Util.array_minus(keywords.keys,
          callable.args.map {|var| var.first.underscored_name})
        if callable.splat && unknown_args.include?(callable.splat.underscored_name)
          raise Sass::SyntaxError.new("Argument $#{callable.splat.name} of #{downcase_desc} cannot be used as a named argument.")
        elsif unknown_args.any?
          description = unknown_args.length > 1 ? 'the following arguments:' : 'an argument named'
          raise Sass::SyntaxError.new("#{desc} doesn't have #{description} #{unknown_args.map {|name| "$#{name}"}.join ', '}.")
        end
      end
    rescue Sass::SyntaxError => keyword_exception
    end

    # If there's no splat, raise the keyword exception immediately. The actual
    # raising happens in the ensure clause at the end of this function.
    return if keyword_exception && !callable.splat

    if args.size > callable.args.size && !callable.splat
      takes = callable.args.size
      passed = args.size
      raise Sass::SyntaxError.new(
        "#{desc} takes #{takes} argument#{'s' unless takes == 1} " +
        "but #{passed} #{passed == 1 ? 'was' : 'were'} passed.")
    end

    splat_sep = :comma
    if splat
      args += splat.to_a
      splat_sep = splat.separator if splat.is_a?(Sass::Script::List)
      # If the splat argument exists, there won't be any keywords passed in
      # manually, so we can safely overwrite rather than merge here.
      keywords = splat.keywords if splat.is_a?(Sass::Script::ArgList)
    end

    keywords = keywords.dup
    env = Sass::Environment.new(callable.environment)
    callable.args.zip(args[0...callable.args.length]) do |(var, default), value|
      if value && keywords.include?(var.underscored_name)
        raise Sass::SyntaxError.new("#{desc} was passed argument $#{var.name} both by position and by name.")
      end

      value ||= keywords.delete(var.underscored_name)
      value ||= default && default.perform(env)
      raise Sass::SyntaxError.new("#{desc} is missing argument #{var.inspect}.") unless value
      env.set_local_var(var.name, value)
    end

    if callable.splat
      rest = args[callable.args.length..-1]
      arg_list = Sass::Script::ArgList.new(rest, keywords.dup, splat_sep)
      arg_list.options = env.options
      env.set_local_var(callable.splat.name, arg_list)
    end

    yield env
  rescue Exception => e
  ensure
    # If there's a keyword exception, we don't want to throw it immediately,
    # because the invalid keywords may be part of a glob argument that should be
    # passed on to another function. So we only raise it if we reach the end of
    # this function *and* the keywords attached to the argument list glob object
    # haven't been accessed.
    #
    # The keyword exception takes precedence over any Sass errors, but not over
    # non-Sass exceptions.
    if keyword_exception &&
        !(arg_list && arg_list.keywords_accessed) &&
        (e.nil? || e.is_a?(Sass::SyntaxError))
      raise keyword_exception
    elsif e
      raise e
    end
  end

  protected

  def initialize(env)
    @environment = env
    # Stack trace information, including mixin includes and imports.
    @stack = []
  end

  # If an exception is raised, this adds proper metadata to the backtrace.
  def visit(node)
    super(node.dup)
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  # Keeps track of the current environment.
  def visit_children(parent)
    with_environment Sass::Environment.new(@environment, parent.options) do
      parent.children = super.flatten
      parent
    end
  end

  # Runs a block of code with the current environment replaced with the given one.
  #
  # @param env [Sass::Environment] The new environment for the duration of the block.
  # @yield A block in which the environment is set to `env`.
  # @return [Object] The return value of the block.
  def with_environment(env)
    old_env, @environment = @environment, env
    yield
  ensure
    @environment = old_env
  end

  # Sets the options on the environment if this is the top-level root.
  def visit_root(node)
    yield
  rescue Sass::SyntaxError => e
    e.sass_template ||= node.template
    raise e
  end

  # Removes this node from the tree if it's a silent comment.
  def visit_comment(node)
    return [] if node.invisible?
    node.resolved_value = run_interp_no_strip(node.value)
    node.resolved_value.gsub!(/\\([\\#])/, '\1')
    node
  end

  # Prints the expression to STDERR.
  def visit_debug(node)
    res = node.expr.perform(@environment)
    res = res.value if res.is_a?(Sass::Script::String)
    if node.filename
      Sass::Util.sass_warn "#{node.filename}:#{node.line} DEBUG: #{res}"
    else
      Sass::Util.sass_warn "Line #{node.line} DEBUG: #{res}"
    end
    []
  end

  # Runs the child nodes once for each value in the list.
  def visit_each(node)
    list = node.list.perform(@environment)

    with_environment Sass::Environment.new(@environment) do
      list.to_a.map do |v|
        @environment.set_local_var(node.var, v)
        node.children.map {|c| visit(c)}
      end.flatten
    end
  end

  # Runs SassScript interpolation in the selector,
  # and then parses the result into a {Sass::Selector::CommaSequence}.
  def visit_extend(node)
    parser = Sass::SCSS::StaticParser.new(run_interp(node.selector), node.filename, node.line)
    node.resolved_selector = parser.parse_selector
    node
  end

  # Runs the child nodes once for each time through the loop, varying the variable each time.
  def visit_for(node)
    from = node.from.perform(@environment)
    to = node.to.perform(@environment)
    from.assert_int!
    to.assert_int!

    to = to.coerce(from.numerator_units, from.denominator_units)
    range = Range.new(from.to_i, to.to_i, node.exclusive)

    with_environment Sass::Environment.new(@environment) do
      range.map do |i|
        @environment.set_local_var(node.var,
          Sass::Script::Number.new(i, from.numerator_units, from.denominator_units))
        node.children.map {|c| visit(c)}
      end.flatten
    end
  end

  # Loads the function into the environment.
  def visit_function(node)
    env = Sass::Environment.new(@environment, node.options)
    @environment.set_local_function(node.name,
      Sass::Callable.new(node.name, node.args, node.splat, env, node.children, !:has_content, "function"))
    []
  end

  # Runs the child nodes if the conditional expression is true;
  # otherwise, tries the else nodes.
  def visit_if(node)
    if node.expr.nil? || node.expr.perform(@environment).to_bool
      yield
      node.children
    elsif node.else
      visit(node.else)
    else
      []
    end
  end

  # Returns a static DirectiveNode if this is importing a CSS file,
  # or parses and includes the imported Sass file.
  def visit_import(node)
    if path = node.css_import?
      return Sass::Tree::CssImportNode.resolved("url(#{path})")
    end
    file = node.imported_file
    handle_import_loop!(node) if @stack.any? {|e| e[:filename] == file.options[:filename]}

    begin
      @stack.push(:filename => node.filename, :line => node.line)
      root = file.to_tree
      Sass::Tree::Visitors::CheckNesting.visit(root)
      node.children = root.children.map {|c| visit(c)}.flatten
      node
    rescue Sass::SyntaxError => e
      e.modify_backtrace(:filename => node.imported_file.options[:filename])
      e.add_backtrace(:filename => node.filename, :line => node.line)
      raise e
    end
  ensure
    @stack.pop unless path
  end

  # Loads a mixin into the environment.
  def visit_mixindef(node)
    env = Sass::Environment.new(@environment, node.options)
    @environment.set_local_mixin(node.name,
      Sass::Callable.new(node.name, node.args, node.splat, env, node.children, node.has_content, "mixin"))
    []
  end

  # Runs a mixin.
  def visit_mixin(node)
    include_loop = true
    handle_include_loop!(node) if @stack.any? {|e| e[:name] == node.name}
    include_loop = false

    @stack.push(:filename => node.filename, :line => node.line, :name => node.name)
    raise Sass::SyntaxError.new("Undefined mixin '#{node.name}'.") unless mixin = @environment.mixin(node.name)

    if node.children.any? && !mixin.has_content
      raise Sass::SyntaxError.new(%Q{Mixin "#{node.name}" does not accept a content block.})
    end

    args = node.args.map {|a| a.perform(@environment)}
    keywords = Sass::Util.map_hash(node.keywords) {|k, v| [k, v.perform(@environment)]}
    splat = node.splat.perform(@environment) if node.splat

    self.class.perform_arguments(mixin, args, keywords, splat) do |env|
      env.caller = Sass::Environment.new(@environment)
      env.content = node.children if node.has_children

      trace_node = Sass::Tree::TraceNode.from_node(node.name, node)
      with_environment(env) {trace_node.children = mixin.tree.map {|c| visit(c)}.flatten}
      trace_node
    end
  rescue Sass::SyntaxError => e
    unless include_loop
      e.modify_backtrace(:mixin => node.name, :line => node.line)
      e.add_backtrace(:line => node.line)
    end
    raise e
  ensure
    @stack.pop unless include_loop
  end

  def visit_content(node)
    return [] unless content = @environment.content
    @stack.push(:filename => node.filename, :line => node.line, :name => '@content')
    trace_node = Sass::Tree::TraceNode.from_node('@content', node)
    with_environment(@environment.caller) {trace_node.children = content.map {|c| visit(c.dup)}.flatten}
    trace_node
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:mixin => '@content', :line => node.line)
    e.add_backtrace(:line => node.line)
    raise e
  ensure
    @stack.pop if content
  end

  # Runs any SassScript that may be embedded in a property.
  def visit_prop(node)
    node.resolved_name = run_interp(node.name)
    val = node.value.perform(@environment)
    node.resolved_value = val.to_s
    yield
  end

  # Returns the value of the expression.
  def visit_return(node)
    throw :_sass_return, node.expr.perform(@environment)
  end

  # Runs SassScript interpolation in the selector,
  # and then parses the result into a {Sass::Selector::CommaSequence}.
  def visit_rule(node)
    rule = node.rule
    rule = rule.map {|e| e.is_a?(String) && e != ' ' ? e.strip : e} if node.style == :compressed
    parser = Sass::SCSS::StaticParser.new(run_interp(node.rule), node.filename, node.line)
    node.parsed_rules ||= parser.parse_selector
    if node.options[:trace_selectors]
      @stack.push(:filename => node.filename, :line => node.line)
      node.stack_trace = stack_trace
      @stack.pop
    end
    yield
  end

  # Loads the new variable value into the environment.
  def visit_variable(node)
    var = @environment.var(node.name)
    return [] if node.guarded && var && !var.null?
    val = node.expr.perform(@environment)
    @environment.set_var(node.name, val)
    []
  end

  # Prints the expression to STDERR with a stylesheet trace.
  def visit_warn(node)
    @stack.push(:filename => node.filename, :line => node.line)
    res = node.expr.perform(@environment)
    res = res.value if res.is_a?(Sass::Script::String)
    msg = "WARNING: #{res}\n         "
    msg << stack_trace.join("\n         ") << "\n"
    Sass::Util.sass_warn msg
    []
  ensure
    @stack.pop
  end

  # Runs the child nodes until the continuation expression becomes false.
  def visit_while(node)
    children = []
    with_environment Sass::Environment.new(@environment) do
      children += node.children.map {|c| visit(c)} while node.expr.perform(@environment).to_bool
    end
    children.flatten
  end

  def visit_directive(node)
    node.resolved_value = run_interp(node.value)
    yield
  end

  def visit_media(node)
    parser = Sass::SCSS::StaticParser.new(run_interp(node.query), node.filename, node.line)
    node.resolved_query ||= parser.parse_media_query_list
    yield
  end

  def visit_supports(node)
    node.condition = node.condition.deep_copy
    node.condition.perform(@environment)
    yield
  end

  def visit_cssimport(node)
    node.resolved_uri = run_interp([node.uri])
    if node.query
      parser = Sass::SCSS::StaticParser.new(run_interp(node.query), node.filename, node.line)
      node.resolved_query ||= parser.parse_media_query_list
    end
    yield
  end

  private

  def stack_trace
    trace = []
    stack = @stack.map {|e| e.dup}.reverse
    stack.each_cons(2) {|(e1, e2)| e1[:caller] = e2[:name]; [e1, e2]}
    stack.each_with_index do |entry, i|
      msg = "#{i == 0 ? "on" : "from"} line #{entry[:line]}"
      msg << " of #{entry[:filename] || "an unknown file"}"
      msg << ", in `#{entry[:caller]}'" if entry[:caller]
      trace << msg
    end
    trace
  end

  def run_interp_no_strip(text)
    text.map do |r|
      next r if r.is_a?(String)
      val = r.perform(@environment)
      # Interpolated strings should never render with quotes
      next val.value if val.is_a?(Sass::Script::String)
      val.to_s
    end.join
  end

  def run_interp(text)
    run_interp_no_strip(text).strip
  end

  def handle_include_loop!(node)
    msg = "An @include loop has been found:"
    content_count = 0
    mixins = @stack.reverse.map {|s| s[:name]}.compact.select do |s|
      if s == '@content'
        content_count += 1
        false
      elsif content_count > 0
        content_count -= 1
        false
      else
        true
      end
    end

    return unless mixins.include?(node.name)
    raise Sass::SyntaxError.new("#{msg} #{node.name} includes itself") if mixins.size == 1

    msg << "\n" << Sass::Util.enum_cons(mixins.reverse + [node.name], 2).map do |m1, m2|
      "    #{m1} includes #{m2}"
    end.join("\n")
    raise Sass::SyntaxError.new(msg)
  end

  def handle_import_loop!(node)
    msg = "An @import loop has been found:"
    files = @stack.map {|s| s[:filename]}.compact
    if node.filename == node.imported_file.options[:filename]
      raise Sass::SyntaxError.new("#{msg} #{node.filename} imports itself")
    end

    files << node.filename << node.imported_file.options[:filename]
    msg << "\n" << Sass::Util.enum_cons(files, 2).map do |m1, m2|
      "    #{m1} imports #{m2}"
    end.join("\n")
    raise Sass::SyntaxError.new(msg)
  end
end
# A visitor for converting a static Sass tree into a static CSS tree.
class Sass::Tree::Visitors::Cssize < Sass::Tree::Visitors::Base
  # @param root [Tree::Node] The root node of the tree to visit.
  # @return [(Tree::Node, Sass::Util::SubsetMap)] The resulting tree of static nodes
  #   *and* the extensions defined for this tree
  def self.visit(root); super; end

  protected

  # Returns the immediate parent of the current node.
  # @return [Tree::Node]
  attr_reader :parent

  def initialize
    @parent_directives = []
    @extends = Sass::Util::SubsetMap.new
  end

  # If an exception is raised, this adds proper metadata to the backtrace.
  def visit(node)
    super(node)
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  # Keeps track of the current parent node.
  def visit_children(parent)
    with_parent parent do
      parent.children = super.flatten
      parent
    end
  end

  MERGEABLE_DIRECTIVES = [Sass::Tree::MediaNode]

  # Runs a block of code with the current parent node
  # replaced with the given node.
  #
  # @param parent [Tree::Node] The new parent for the duration of the block.
  # @yield A block in which the parent is set to `parent`.
  # @return [Object] The return value of the block.
  def with_parent(parent)
    if parent.is_a?(Sass::Tree::DirectiveNode)
      if MERGEABLE_DIRECTIVES.any? {|klass| parent.is_a?(klass)}
        old_parent_directive = @parent_directives.pop
      end
      @parent_directives.push parent
    end

    old_parent, @parent = @parent, parent
    yield
  ensure
    @parent_directives.pop if parent.is_a?(Sass::Tree::DirectiveNode)
    @parent_directives.push old_parent_directive if old_parent_directive
    @parent = old_parent
  end

  # In Ruby 1.8, ensures that there's only one `@charset` directive
  # and that it's at the top of the document.
  #
  # @return [(Tree::Node, Sass::Util::SubsetMap)] The resulting tree of static nodes
  #   *and* the extensions defined for this tree
  def visit_root(node)
    yield

    if parent.nil?
      # In Ruby 1.9 we can make all @charset nodes invisible
      # and infer the final @charset from the encoding of the final string.
      if Sass::Util.ruby1_8?
        charset = node.children.find {|c| c.is_a?(Sass::Tree::CharsetNode)}
        node.children.reject! {|c| c.is_a?(Sass::Tree::CharsetNode)}
        node.children.unshift charset if charset
      end

      imports = Sass::Util.extract!(node.children) do |c|
        c.is_a?(Sass::Tree::DirectiveNode) && !c.is_a?(Sass::Tree::MediaNode) &&
          c.resolved_value =~ /^@import /i
      end
      charset_and_index = Sass::Util.ruby1_8? &&
        node.children.each_with_index.find {|c, _| c.is_a?(Sass::Tree::CharsetNode)}
      if charset_and_index && charset_and_index.respond_to?(:last)
        index = charset_and_index.last
        node.children = node.children[0..index] + imports + node.children[index+1..-1]
      else
        node.children = imports + node.children
      end
    end

    return node, @extends
  rescue Sass::SyntaxError => e
    e.sass_template ||= node.template
    raise e
  end

  # A simple struct wrapping up information about a single `@extend` instance. A
  # single [ExtendNode] can have multiple Extends if either the parent node or
  # the extended selector is a comma sequence.
  #
  # @attr extender [Sass::Selector::Sequence]
  #   The selector of the CSS rule containing the `@extend`.
  # @attr target [Array<Sass::Selector::Simple>] The selector being `@extend`ed.
  # @attr node [Sass::Tree::ExtendNode] The node that produced this extend.
  # @attr directives [Array<Sass::Tree::DirectiveNode>]
  #   The directives containing the `@extend`.
  # @attr result [Symbol]
  #   The result of this extend. One of `:not_found` (the target doesn't exist
  #   in the document), `:failed_to_unify` (the target exists but cannot be
  #   unified with the extender), or `:succeeded`.
  Extend = Struct.new(:extender, :target, :node, :directives, :result)

  # Registers an extension in the `@extends` subset map.
  def visit_extend(node)
    node.resolved_selector.members.each do |seq|
      if seq.members.size > 1
        raise Sass::SyntaxError.new("Can't extend #{seq.to_a.join}: can't extend nested selectors")
      end

      sseq = seq.members.first
      if !sseq.is_a?(Sass::Selector::SimpleSequence)
        raise Sass::SyntaxError.new("Can't extend #{seq.to_a.join}: invalid selector")
      elsif sseq.members.any? {|ss| ss.is_a?(Sass::Selector::Parent)}
        raise Sass::SyntaxError.new("Can't extend #{seq.to_a.join}: can't extend parent selectors")
      end

      sel = sseq.members
      parent.resolved_rules.members.each do |member|
        if !member.members.last.is_a?(Sass::Selector::SimpleSequence)
          raise Sass::SyntaxError.new("#{member} can't extend: invalid selector")
        end

        @extends[sel] = Extend.new(member, sel, node, @parent_directives.dup, :not_found)
      end
    end

    []
  end

  # Modifies exception backtraces to include the imported file.
  def visit_import(node)
    # Don't use #visit_children to avoid adding the import node to the list of parents.
    node.children.map {|c| visit(c)}.flatten
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.children.first.filename)
    e.add_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  # Bubbles the `@media` directive up through RuleNodes
  # and merges it with other `@media` directives.
  def visit_media(node)
    yield unless bubble(node)
    media = node.children.select {|c| c.is_a?(Sass::Tree::MediaNode)}
    node.children.reject! {|c| c.is_a?(Sass::Tree::MediaNode)}
    media = media.select {|n| n.resolved_query = n.resolved_query.merge(node.resolved_query)}
    (node.children.empty? ? [] : [node]) + media
  end

  # Bubbles the `@supports` directive up through RuleNodes.
  def visit_supports(node)
    yield unless bubble(node)
    node
  end

  # Asserts that all the traced children are valid in their new location.
  def visit_trace(node)
    # Don't use #visit_children to avoid adding the trace node to the list of parents.
    node.children.map {|c| visit(c)}.flatten
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:mixin => node.name, :filename => node.filename, :line => node.line)
    e.add_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  # Converts nested properties into flat properties
  # and updates the indentation of the prop node based on the nesting level.
  def visit_prop(node)
    if parent.is_a?(Sass::Tree::PropNode)
      node.resolved_name = "#{parent.resolved_name}-#{node.resolved_name}"
      node.tabs = parent.tabs + (parent.resolved_value.empty? ? 0 : 1) if node.style == :nested
    end

    yield

    result = node.children.dup
    if !node.resolved_value.empty? || node.children.empty?
      node.send(:check!)
      result.unshift(node)
    end

    result
  end

  # Resolves parent references and nested selectors,
  # and updates the indentation of the rule node based on the nesting level.
  def visit_rule(node)
    parent_resolved_rules = parent.is_a?(Sass::Tree::RuleNode) ? parent.resolved_rules : nil
    # It's possible for resolved_rules to be set if we've duplicated this node during @media bubbling
    node.resolved_rules ||= node.parsed_rules.resolve_parent_refs(parent_resolved_rules)

    yield

    rules = node.children.select {|c| c.is_a?(Sass::Tree::RuleNode) || c.bubbles?}
    props = node.children.reject {|c| c.is_a?(Sass::Tree::RuleNode) || c.bubbles? || c.invisible?}

    unless props.empty?
      node.children = props
      rules.each {|r| r.tabs += 1} if node.style == :nested
      rules.unshift(node)
    end

    rules.last.group_end = true unless parent.is_a?(Sass::Tree::RuleNode) || rules.empty?

    rules
  end

  private

  def bubble(node)
    return unless parent.is_a?(Sass::Tree::RuleNode)
    new_rule = parent.dup
    new_rule.children = node.children
    node.children = with_parent(node) {Array(visit(new_rule))}
    # If the last child is actually the end of the group,
    # the parent's cssize will set it properly
    node.children.last.group_end = false unless node.children.empty?
    true
  end
end
# A visitor for performing selector inheritance on a static CSS tree.
#
# Destructively modifies the tree.
class Sass::Tree::Visitors::Extend < Sass::Tree::Visitors::Base
  # Performs the given extensions on the static CSS tree based in `root`, then
  # validates that all extends matched some selector.
  #
  # @param root [Tree::Node] The root node of the tree to visit.
  # @param extends [Sass::Util::SubsetMap{Selector::Simple =>
  #                                       Sass::Tree::Visitors::Cssize::Extend}]
  #   The extensions to perform on this tree.
  # @return [Object] The return value of \{#visit} for the root node.
  def self.visit(root, extends)
    return if extends.empty?
    new(extends).send(:visit, root)
    check_extends_fired! extends
  end

  protected

  def initialize(extends)
    @parent_directives = []
    @extends = extends
  end

  # If an exception is raised, this adds proper metadata to the backtrace.
  def visit(node)
    super(node)
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  # Keeps track of the current parent directives.
  def visit_children(parent)
    @parent_directives.push parent if parent.is_a?(Sass::Tree::DirectiveNode)
    super
  ensure
    @parent_directives.pop if parent.is_a?(Sass::Tree::DirectiveNode)
  end

  # Applies the extend to a single rule's selector.
  def visit_rule(node)
    node.resolved_rules = node.resolved_rules.do_extend(@extends, @parent_directives)
  end

  private

  def self.check_extends_fired!(extends)
    extends.each_value do |ex|
      next if ex.result == :succeeded || ex.node.optional?
      warn = "\"#{ex.extender}\" failed to @extend \"#{ex.target.join}\"."
      reason =
        if ex.result == :not_found
          "The selector \"#{ex.target.join}\" was not found."
        else
          "No selectors matching \"#{ex.target.join}\" could be unified with \"#{ex.extender}\"."
        end

      Sass::Util.sass_warn <<WARN
WARNING on line #{ex.node.line}#{" of #{ex.node.filename}" if ex.node.filename}: #{warn}
  #{reason}
  This will be an error in future releases of Sass.
  Use "@extend #{ex.target.join} !optional" if the extend should be able to fail.
WARN
    end
  end
end
# A visitor for converting a Sass tree into a source string.
class Sass::Tree::Visitors::Convert < Sass::Tree::Visitors::Base
  # Runs the visitor on a tree.
  #
  # @param root [Tree::Node] The root node of the Sass tree.
  # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize}).
  # @param format [Symbol] `:sass` or `:scss`.
  # @return [String] The Sass or SCSS source for the tree.
  def self.visit(root, options, format)
    new(options, format).send(:visit, root)
  end

  protected

  def initialize(options, format)
    @options = options
    @format = format
    @tabs = 0
    # 2 spaces by default
    @tab_chars = @options[:indent] || "  "
  end

  def visit_children(parent)
    @tabs += 1
    return @format == :sass ? "\n" : " {}\n" if parent.children.empty?
    (@format == :sass ? "\n" : " {\n") + super.join.rstrip + (@format == :sass ? "\n" : "\n#{ @tab_chars * (@tabs-1)}}\n")
  ensure
    @tabs -= 1
  end

  # Ensures proper spacing between top-level nodes.
  def visit_root(node)
    Sass::Util.enum_cons(node.children + [nil], 2).map do |child, nxt|
      visit(child) +
        if nxt &&
            (child.is_a?(Sass::Tree::CommentNode) &&
              child.line + child.lines + 1 == nxt.line) ||
            (child.is_a?(Sass::Tree::ImportNode) && nxt.is_a?(Sass::Tree::ImportNode) &&
              child.line + 1 == nxt.line) ||
            (child.is_a?(Sass::Tree::VariableNode) && nxt.is_a?(Sass::Tree::VariableNode) &&
              child.line + 1 == nxt.line)
          ""
        else
          "\n"
        end
    end.join.rstrip + "\n"
  end

  def visit_charset(node)
    "#{tab_str}@charset \"#{node.name}\"#{semi}\n"
  end

  def visit_comment(node)
    value = interp_to_src(node.value)
    content = if @format == :sass
      content = value.gsub(/\*\/$/, '').rstrip
      if content =~ /\A[ \t]/
        # Re-indent SCSS comments like this:
        #     /* foo
        #   bar
        #       baz */
        content.gsub!(/^/, '   ')
        content.sub!(/\A([ \t]*)\/\*/, '/*\1')
      end

      content =
        unless content.include?("\n")
          content
        else
          content.gsub!(/\n( \*|\/\/)/, "\n  ")
          spaces = content.scan(/\n( *)/).map {|s| s.first.size}.min
          sep = node.type == :silent ? "\n//" : "\n *"
          if spaces >= 2
            content.gsub(/\n  /, sep)
          else
            content.gsub(/\n#{' ' * spaces}/, sep)
          end
        end

      content.gsub!(/\A\/\*/, '//') if node.type == :silent
      content.gsub!(/^/, tab_str)
      content.rstrip + "\n"
    else
      spaces = (@tab_chars * [@tabs - value[/^ */].size, 0].max)
      content = if node.type == :silent
        value.gsub(/^[\/ ]\*/, '//').gsub(/ *\*\/$/, '')
      else
        value
      end.gsub(/^/, spaces) + "\n"
      content
    end
    content
  end

  def visit_debug(node)
    "#{tab_str}@debug #{node.expr.to_sass(@options)}#{semi}\n"
  end

  def visit_directive(node)
    res = "#{tab_str}#{interp_to_src(node.value)}"
    res.gsub!(/^@import \#\{(.*)\}([^}]*)$/, '@import \1\2');
    return res + "#{semi}\n" unless node.has_children
    res + yield + "\n"
  end

  def visit_each(node)
    "#{tab_str}@each $#{dasherize(node.var)} in #{node.list.to_sass(@options)}#{yield}"
  end

  def visit_extend(node)
    "#{tab_str}@extend #{selector_to_src(node.selector).lstrip}#{semi}#{" !optional" if node.optional?}\n"
  end

  def visit_for(node)
    "#{tab_str}@for $#{dasherize(node.var)} from #{node.from.to_sass(@options)} " +
      "#{node.exclusive ? "to" : "through"} #{node.to.to_sass(@options)}#{yield}"
  end

  def visit_function(node)
    args = node.args.map do |v, d|
      d ? "#{v.to_sass(@options)}: #{d.to_sass(@options)}" : v.to_sass(@options)
    end.join(", ")
    if node.splat
      args << ", " unless node.args.empty?
      args << node.splat.to_sass(@options) << "..."
    end

    "#{tab_str}@function #{dasherize(node.name)}(#{args})#{yield}"
  end

  def visit_if(node)
    name =
      if !@is_else; "if"
      elsif node.expr; "else if"
      else; "else"
      end
    @is_else = false
    str = "#{tab_str}@#{name}"
    str << " #{node.expr.to_sass(@options)}" if node.expr
    str << yield
    @is_else = true
    str << visit(node.else) if node.else
    str
  ensure
    @is_else = false
  end

  def visit_import(node)
    quote = @format == :scss ? '"' : ''
    "#{tab_str}@import #{quote}#{node.imported_filename}#{quote}#{semi}\n"
  end

  def visit_media(node)
    "#{tab_str}@media #{media_interp_to_src(node.query)}#{yield}"
  end

  def visit_supports(node)
    "#{tab_str}@#{node.name} #{node.condition.to_src(@options)}#{yield}"
  end

  def visit_cssimport(node)
    if node.uri.is_a?(Sass::Script::Node)
      str = "#{tab_str}@import #{node.uri.to_sass(@options)}"
    else
      str = "#{tab_str}@import #{node.uri}"
    end
    str << " #{interp_to_src(node.query)}" unless node.query.empty?
    "#{str}#{semi}\n"
  end

  def visit_mixindef(node)
    args =
      if node.args.empty? && node.splat.nil?
        ""
      else
        str = '('
        str << node.args.map do |v, d|
          if d
            "#{v.to_sass(@options)}: #{d.to_sass(@options)}"
          else
            v.to_sass(@options)
          end
        end.join(", ")

        if node.splat
          str << ", " unless node.args.empty?
          str << node.splat.to_sass(@options) << '...'
        end

        str << ')'
      end

    "#{tab_str}#{@format == :sass ? '=' : '@mixin '}#{dasherize(node.name)}#{args}#{yield}"
  end

  def visit_mixin(node)
    arg_to_sass = lambda do |arg|
      sass = arg.to_sass(@options)
      sass = "(#{sass})" if arg.is_a?(Sass::Script::List) && arg.separator == :comma
      sass
    end

    unless node.args.empty? && node.keywords.empty? && node.splat.nil?
      args = node.args.map(&arg_to_sass).join(", ")
      keywords = Sass::Util.hash_to_a(node.keywords).
        map {|k, v| "$#{dasherize(k)}: #{arg_to_sass[v]}"}.join(', ')
      if node.splat
        splat = (args.empty? && keywords.empty?) ? "" : ", "
        splat = "#{splat}#{arg_to_sass[node.splat]}..."
      end
      arglist = "(#{args}#{', ' unless args.empty? || keywords.empty?}#{keywords}#{splat})"
    end
    "#{tab_str}#{@format == :sass ? '+' : '@include '}#{dasherize(node.name)}#{arglist}#{node.has_children ? yield : semi}\n"
  end

  def visit_content(node)
    "#{tab_str}@content#{semi}\n"
  end

  def visit_prop(node)
    res = tab_str + node.declaration(@options, @format)
    return res + semi + "\n" if node.children.empty?
    res + yield.rstrip + semi + "\n"
  end

  def visit_return(node)
    "#{tab_str}@return #{node.expr.to_sass(@options)}#{semi}\n"
  end

  def visit_rule(node)
    if @format == :sass
      name = selector_to_sass(node.rule)
      name = "\\" + name if name[0] == ?:
      name.gsub(/^/, tab_str) + yield
    elsif @format == :scss
      name = selector_to_scss(node.rule)
      res = name + yield
      if node.children.last.is_a?(Sass::Tree::CommentNode) && node.children.last.type == :silent
        res.slice!(-3..-1)
        res << "\n" << tab_str << "}\n"
      end
      res
    end
  end

  def visit_variable(node)
    "#{tab_str}$#{dasherize(node.name)}: #{node.expr.to_sass(@options)}#{' !default' if node.guarded}#{semi}\n"
  end

  def visit_warn(node)
    "#{tab_str}@warn #{node.expr.to_sass(@options)}#{semi}\n"
  end

  def visit_while(node)
    "#{tab_str}@while #{node.expr.to_sass(@options)}#{yield}"
  end

  private

  def interp_to_src(interp)
    interp.map do |r|
      next r if r.is_a?(String)
      "\#{#{r.to_sass(@options)}}"
    end.join
  end

  # Like interp_to_src, but removes the unnecessary `#{}` around the keys and
  # values in media expressions.
  def media_interp_to_src(interp)
    Sass::Util.enum_with_index(interp).map do |r, i|
      next r if r.is_a?(String)
      before, after = interp[i-1], interp[i+1]
      if before.is_a?(String) && after.is_a?(String) &&
          ((before[-1] == ?( && after[0] == ?:) ||
           (before =~ /:\s*/ && after[0] == ?)))
        r.to_sass(@options)
      else
        "\#{#{r.to_sass(@options)}}"
      end
    end.join
  end

  def selector_to_src(sel)
    @format == :sass ? selector_to_sass(sel) : selector_to_scss(sel)
  end

  def selector_to_sass(sel)
    sel.map do |r|
      if r.is_a?(String)
        r.gsub(/(,)?([ \t]*)\n\s*/) {$1 ? "#{$1}#{$2}\n" : " "}
      else
        "\#{#{r.to_sass(@options)}}"
      end
    end.join
  end

  def selector_to_scss(sel)
    interp_to_src(sel).gsub(/^[ \t]*/, tab_str).gsub(/[ \t]*$/, '')
  end

  def semi
    @format == :sass ? "" : ";"
  end

  def tab_str
    @tab_chars * @tabs
  end

  def dasherize(s)
    if @options[:dasherize]
      s.gsub('_', '-')
    else
      s
    end
  end
end
# A visitor for converting a Sass tree into CSS.
class Sass::Tree::Visitors::ToCss < Sass::Tree::Visitors::Base
  protected

  def initialize
    @tabs = 0
  end

  def visit(node)
    super
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  def with_tabs(tabs)
    old_tabs, @tabs = @tabs, tabs
    yield
  ensure
    @tabs = old_tabs
  end

  def visit_root(node)
    result = String.new
    node.children.each do |child|
      next if child.invisible?
      child_str = visit(child)
      result << child_str + (node.style == :compressed ? '' : "\n")
    end
    result.rstrip!
    return "" if result.empty?
    result << "\n"
    unless Sass::Util.ruby1_8? || result.ascii_only?
      if node.children.first.is_a?(Sass::Tree::CharsetNode)
        begin
          encoding = node.children.first.name
          # Default to big-endian encoding, because we have to decide somehow
          encoding << 'BE' if encoding =~ /\Autf-(16|32)\Z/i
          result = result.encode(Encoding.find(encoding))
        rescue EncodingError
        end
      end

      result = "@charset \"#{result.encoding.name}\";#{
        node.style == :compressed ? '' : "\n"
      }".encode(result.encoding) + result
    end
    result
  rescue Sass::SyntaxError => e
    e.sass_template ||= node.template
    raise e
  end

  def visit_charset(node)
    "@charset \"#{node.name}\";"
  end 

  def visit_comment(node)
    return if node.invisible?
    spaces = ('  ' * [@tabs - node.resolved_value[/^ */].size, 0].max)

    content = node.resolved_value.gsub(/^/, spaces)
    content.gsub!(%r{^(\s*)//(.*)$}) {|md| "#{$1}/*#{$2} */"} if node.type == :silent
    content.gsub!(/\n +(\* *(?!\/))?/, ' ') if (node.style == :compact || node.style == :compressed) && node.type != :loud
    content
  end

  def visit_directive(node)
    was_in_directive = @in_directive
    tab_str = '  ' * @tabs
    return tab_str + node.resolved_value + ";" unless node.has_children
    return tab_str + node.resolved_value + " {}" if node.children.empty?
    @in_directive = @in_directive || !node.is_a?(Sass::Tree::MediaNode)
    result = if node.style == :compressed
               "#{node.resolved_value}{"
             else
               "#{tab_str}#{node.resolved_value} {" + (node.style == :compact ? ' ' : "\n")
             end
    was_prop = false
    first = true
    node.children.each do |child|
      next if child.invisible?
      if node.style == :compact
        if child.is_a?(Sass::Tree::PropNode)
          with_tabs(first || was_prop ? 0 : @tabs + 1) {result << visit(child) << ' '}
        else
          result[-1] = "\n" if was_prop
          rendered = with_tabs(@tabs + 1) {visit(child).dup}
          rendered = rendered.lstrip if first
          result << rendered.rstrip + "\n"
        end
        was_prop = child.is_a?(Sass::Tree::PropNode)
        first = false
      elsif node.style == :compressed
        result << (was_prop ? ";" : "") << with_tabs(0) {visit(child)}
        was_prop = child.is_a?(Sass::Tree::PropNode)
      else
        result << with_tabs(@tabs + 1) {visit(child)} + "\n"
      end
    end
    result.rstrip + if node.style == :compressed
                      "}"
                    else
                      (node.style == :expanded ? "\n" : " ") + "}\n"
                    end
  ensure
    @in_directive = was_in_directive
  end

  def visit_media(node)
    str = with_tabs(@tabs + node.tabs) {visit_directive(node)}
    str.gsub!(/\n\Z/, '') unless node.style == :compressed || node.group_end
    str
  end

  def visit_supports(node)
    visit_media(node)
  end

  def visit_cssimport(node)
    visit_directive(node)
  end

  def visit_prop(node)
    return if node.resolved_value.empty?
    tab_str = '  ' * (@tabs + node.tabs)
    if node.style == :compressed
      "#{tab_str}#{node.resolved_name}:#{node.resolved_value}"
    else
      "#{tab_str}#{node.resolved_name}: #{node.resolved_value};"
    end
  end

  def visit_rule(node)
    with_tabs(@tabs + node.tabs) do
      rule_separator = node.style == :compressed ? ',' : ', '
      line_separator =
        case node.style
          when :nested, :expanded; "\n"
          when :compressed; ""
          else; " "
        end
      rule_indent = '  ' * @tabs
      per_rule_indent, total_indent = [:nested, :expanded].include?(node.style) ? [rule_indent, ''] : ['', rule_indent]

      joined_rules = node.resolved_rules.members.map do |seq|
        next if seq.has_placeholder?
        rule_part = seq.to_a.join
        if node.style == :compressed
          rule_part.gsub!(/([^,])\s*\n\s*/m, '\1 ')
          rule_part.gsub!(/\s*([,+>])\s*/m, '\1')
          rule_part.strip!
        end
        rule_part
      end.compact.join(rule_separator)

      joined_rules.sub!(/\A\s*/, per_rule_indent)
      joined_rules.gsub!(/\s*\n\s*/, "#{line_separator}#{per_rule_indent}")
      total_rule = total_indent << joined_rules

      to_return = ''
      old_spaces = '  ' * @tabs
      if node.style != :compressed
        if node.options[:debug_info] && !@in_directive
          to_return << visit(debug_info_rule(node.debug_info, node.options)) << "\n"
        elsif node.options[:trace_selectors]
          to_return << "#{old_spaces}/* "
          to_return << node.stack_trace.join("\n   #{old_spaces}")
          to_return << " */\n"
        elsif node.options[:line_comments]
          to_return << "#{old_spaces}/* line #{node.line}"

          if node.filename
            relative_filename = if node.options[:css_filename]
              begin
                Pathname.new(node.filename).relative_path_from(
                  Pathname.new(File.dirname(node.options[:css_filename]))).to_s
              rescue ArgumentError
                nil
              end
            end
            relative_filename ||= node.filename
            to_return << ", #{relative_filename}"
          end

          to_return << " */\n"
        end
      end

      if node.style == :compact
        properties = with_tabs(0) {node.children.map {|a| visit(a)}.join(' ')}
        to_return << "#{total_rule} { #{properties} }#{"\n" if node.group_end}"
      elsif node.style == :compressed
        properties = with_tabs(0) {node.children.map {|a| visit(a)}.join(';')}
        to_return << "#{total_rule}{#{properties}}"
      else
        properties = with_tabs(@tabs + 1) {node.children.map {|a| visit(a)}.join("\n")}
        end_props = (node.style == :expanded ? "\n" + old_spaces : ' ')
        to_return << "#{total_rule} {\n#{properties}#{end_props}}#{"\n" if node.group_end}"
      end

      to_return
    end
  end

  private

  def debug_info_rule(debug_info, options)
    node = Sass::Tree::DirectiveNode.resolved("@media -sass-debug-info")
    Sass::Util.hash_to_a(debug_info.map {|k, v| [k.to_s, v.to_s]}).each do |k, v|
      rule = Sass::Tree::RuleNode.new([""])
      rule.resolved_rules = Sass::Selector::CommaSequence.new(
        [Sass::Selector::Sequence.new(
            [Sass::Selector::SimpleSequence.new(
                [Sass::Selector::Element.new(k.to_s.gsub(/[^\w-]/, "\\\\\\0"), nil)],
                false)
            ])
        ])
      prop = Sass::Tree::PropNode.new([""], Sass::Script::String.new(''), :new)
      prop.resolved_name = "font-family"
      prop.resolved_value = Sass::SCSS::RX.escape_ident(v.to_s)
      rule << prop
      node << rule
    end
    node.options = options.merge(:debug_info => false, :line_comments => false, :style => :compressed)
    node
  end
end
# A visitor for copying the full structure of a Sass tree.
class Sass::Tree::Visitors::DeepCopy < Sass::Tree::Visitors::Base
  protected

  def visit(node)
    super(node.dup)
  end

  def visit_children(parent)
    parent.children = parent.children.map {|c| visit(c)}
    parent
  end

  def visit_debug(node)
    node.expr = node.expr.deep_copy
    yield
  end

  def visit_each(node)
    node.list = node.list.deep_copy
    yield
  end

  def visit_extend(node)
    node.selector = node.selector.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}
    yield
  end

  def visit_for(node)
    node.from = node.from.deep_copy
    node.to = node.to.deep_copy
    yield
  end

  def visit_function(node)
    node.args = node.args.map {|k, v| [k.deep_copy, v && v.deep_copy]}
    yield
  end

  def visit_if(node)
    node.expr = node.expr.deep_copy if node.expr
    node.else = visit(node.else) if node.else
    yield
  end

  def visit_mixindef(node)
    node.args = node.args.map {|k, v| [k.deep_copy, v && v.deep_copy]}
    yield
  end

  def visit_mixin(node)
    node.args = node.args.map {|a| a.deep_copy}
    node.keywords = Hash[node.keywords.map {|k, v| [k, v.deep_copy]}]
    yield
  end

  def visit_prop(node)
    node.name = node.name.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}
    node.value = node.value.deep_copy
    yield
  end

  def visit_return(node)
    node.expr = node.expr.deep_copy
    yield
  end

  def visit_rule(node)
    node.rule = node.rule.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}
    yield
  end

  def visit_variable(node)
    node.expr = node.expr.deep_copy
    yield
  end

  def visit_warn(node)
    node.expr = node.expr.deep_copy
    yield
  end

  def visit_while(node)
    node.expr = node.expr.deep_copy
    yield
  end

  def visit_directive(node)
    node.value = node.value.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}
    yield
  end

  def visit_media(node)
    node.query = node.query.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}
    yield
  end

  def visit_supports(node)
    node.condition = node.condition.deep_copy
    yield
  end
end
# A visitor for setting options on the Sass tree
class Sass::Tree::Visitors::SetOptions < Sass::Tree::Visitors::Base
  # @param root [Tree::Node] The root node of the tree to visit.
  # @param options [{Symbol => Object}] The options has to set.
  def self.visit(root, options); new(options).send(:visit, root); end

  protected

  def initialize(options)
    @options = options
  end

  def visit(node)
    node.instance_variable_set('@options', @options)
    super
  end

  def visit_debug(node)
    node.expr.options = @options
    yield
  end

  def visit_each(node)
    node.list.options = @options
    yield
  end

  def visit_extend(node)
    node.selector.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)}
    yield
  end

  def visit_for(node)
    node.from.options = @options
    node.to.options = @options
    yield
  end

  def visit_function(node)
    node.args.each do |k, v|
      k.options = @options
      v.options = @options if v
    end
    yield
  end

  def visit_if(node)
    node.expr.options = @options if node.expr
    visit(node.else) if node.else
    yield
  end

  def visit_import(node)
    # We have no good way of propagating the new options through an Engine
    # instance, so we just null it out. This also lets us avoid caching an
    # imported Engine along with the importing source tree.
    node.imported_file = nil
    yield
  end

  def visit_mixindef(node)
    node.args.each do |k, v|
      k.options = @options
      v.options = @options if v
    end
    yield
  end

  def visit_mixin(node)
    node.args.each {|a| a.options = @options}
    node.keywords.each {|k, v| v.options = @options}
    yield
  end

  def visit_prop(node)
    node.name.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)}
    node.value.options = @options
    yield
  end

  def visit_return(node)
    node.expr.options = @options
    yield
  end

  def visit_rule(node)
    node.rule.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)}
    yield
  end

  def visit_variable(node)
    node.expr.options = @options
    yield
  end

  def visit_warn(node)
    node.expr.options = @options
    yield
  end

  def visit_while(node)
    node.expr.options = @options
    yield
  end

  def visit_directive(node)
    node.value.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)}
    yield
  end

  def visit_media(node)
    node.query.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)}
    yield
  end

  def visit_cssimport(node)
    node.query.each {|c| c.options = @options if c.is_a?(Sass::Script::Node)} if node.query
    yield
  end

  def visit_supports(node)
    node.condition.options = @options
    yield
  end
end
# A visitor for checking that all nodes are properly nested.
class Sass::Tree::Visitors::CheckNesting < Sass::Tree::Visitors::Base
  protected

  def initialize
    @parents = []
  end

  def visit(node)
    if error = @parent && (
        try_send("invalid_#{node_name @parent}_child?", @parent, node) ||
        try_send("invalid_#{node_name node}_parent?", @parent, node))
      raise Sass::SyntaxError.new(error)
    end
    super
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  CONTROL_NODES = [Sass::Tree::EachNode, Sass::Tree::ForNode, Sass::Tree::IfNode,
    Sass::Tree::WhileNode, Sass::Tree::TraceNode]
  SCRIPT_NODES = [Sass::Tree::ImportNode] + CONTROL_NODES
  def visit_children(parent)
    old_parent = @parent
    @parent = parent unless is_any_of?(parent, SCRIPT_NODES) ||
      (parent.bubbles? && !old_parent.is_a?(Sass::Tree::RootNode))
    @parents.push parent
    super
  ensure
    @parent = old_parent
    @parents.pop
  end

  def visit_root(node)
    yield
  rescue Sass::SyntaxError => e
    e.sass_template ||= node.template
    raise e
  end

  def visit_import(node)
    yield
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.children.first.filename)
    e.add_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  def visit_mixindef(node)
    @current_mixin_def, old_mixin_def = node, @current_mixin_def
    yield
  ensure
    @current_mixin_def = old_mixin_def
  end

  def invalid_content_parent?(parent, child)
    if @current_mixin_def
      @current_mixin_def.has_content = true
      nil
    else
      "@content may only be used within a mixin."
    end
  end

  def invalid_charset_parent?(parent, child)
    "@charset may only be used at the root of a document." unless parent.is_a?(Sass::Tree::RootNode)
  end

  VALID_EXTEND_PARENTS = [Sass::Tree::RuleNode, Sass::Tree::MixinDefNode, Sass::Tree::MixinNode]
  def invalid_extend_parent?(parent, child)
    unless is_any_of?(parent, VALID_EXTEND_PARENTS)
      return "Extend directives may only be used within rules."
    end
  end

  INVALID_IMPORT_PARENTS = CONTROL_NODES +
    [Sass::Tree::MixinDefNode, Sass::Tree::MixinNode]
  def invalid_import_parent?(parent, child)
    unless (@parents.map {|p| p.class} & INVALID_IMPORT_PARENTS).empty?
      return "Import directives may not be used within control directives or mixins."
    end
    return if parent.is_a?(Sass::Tree::RootNode)
    return "CSS import directives may only be used at the root of a document." if child.css_import?
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => child.imported_file.options[:filename])
    e.add_backtrace(:filename => child.filename, :line => child.line)
    raise e
  end

  def invalid_mixindef_parent?(parent, child)
    unless (@parents.map {|p| p.class} & INVALID_IMPORT_PARENTS).empty?
      return "Mixins may not be defined within control directives or other mixins."
    end
  end

  def invalid_function_parent?(parent, child)
    unless (@parents.map {|p| p.class} & INVALID_IMPORT_PARENTS).empty?
      return "Functions may not be defined within control directives or other mixins."
    end
  end

  VALID_FUNCTION_CHILDREN = [
    Sass::Tree::CommentNode,  Sass::Tree::DebugNode, Sass::Tree::ReturnNode,
    Sass::Tree::VariableNode, Sass::Tree::WarnNode
  ] + CONTROL_NODES
  def invalid_function_child?(parent, child)
    unless is_any_of?(child, VALID_FUNCTION_CHILDREN)
      "Functions can only contain variable declarations and control directives."
    end
  end

  VALID_PROP_CHILDREN = [Sass::Tree::CommentNode, Sass::Tree::PropNode, Sass::Tree::MixinNode] + CONTROL_NODES
  def invalid_prop_child?(parent, child)
    unless is_any_of?(child, VALID_PROP_CHILDREN)
      "Illegal nesting: Only properties may be nested beneath properties."
    end
  end

  VALID_PROP_PARENTS = [Sass::Tree::RuleNode, Sass::Tree::PropNode,
                        Sass::Tree::MixinDefNode, Sass::Tree::DirectiveNode,
                        Sass::Tree::MixinNode]
  def invalid_prop_parent?(parent, child)
    unless is_any_of?(parent, VALID_PROP_PARENTS)
      "Properties are only allowed within rules, directives, mixin includes, or other properties." + child.pseudo_class_selector_message
    end
  end

  def invalid_return_parent?(parent, child)
    "@return may only be used within a function." unless parent.is_a?(Sass::Tree::FunctionNode)
  end

  private

  def is_any_of?(val, classes)
    for c in classes
      return true if val.is_a?(c)
    end
    return false
  end

  def try_send(method, *args)
    return unless respond_to?(method, true)
    send(method, *args)
  end
end

module Sass
  module Selector
    # The abstract superclass for simple selectors
    # (that is, those that don't compose multiple selectors).
    class Simple
      # The line of the Sass template on which this selector was declared.
      #
      # @return [Fixnum]
      attr_accessor :line

      # The name of the file in which this selector was declared,
      # or `nil` if it was not declared in a file (e.g. on stdin).
      #
      # @return [String, nil]
      attr_accessor :filename

      # Returns a representation of the node
      # as an array of strings and potentially {Sass::Script::Node}s
      # (if there's interpolation in the selector).
      # When the interpolation is resolved and the strings are joined together,
      # this will be the string representation of this node.
      #
      # @return [Array<String, Sass::Script::Node>]
      def to_a
        Sass::Util.abstract(self)
      end

      # Returns a string representation of the node.
      # This is basically the selector string.
      #
      # @return [String]
      def inspect
        to_a.map {|e| e.is_a?(Sass::Script::Node) ? "\#{#{e.to_sass}}" : e}.join
      end

      # @see \{#inspect}
      # @return [String]
      def to_s
        inspect
      end

      # Returns a hash code for this selector object.
      #
      # By default, this is based on the value of \{#to\_a},
      # so if that contains information irrelevant to the identity of the selector,
      # this should be overridden.
      #
      # @return [Fixnum]
      def hash
        @_hash ||= to_a.hash
      end

      # Checks equality between this and another object.
      #
      # By default, this is based on the value of \{#to\_a},
      # so if that contains information irrelevant to the identity of the selector,
      # this should be overridden.
      #
      # @param other [Object] The object to test equality against
      # @return [Boolean] Whether or not this is equal to `other`
      def eql?(other)
        other.class == self.class && other.hash == self.hash && other.to_a.eql?(to_a)
      end
      alias_method :==, :eql?

      # Unifies this selector with a {SimpleSequence}'s {SimpleSequence#members members array},
      # returning another `SimpleSequence` members array
      # that matches both this selector and the input selector.
      #
      # By default, this just appends this selector to the end of the array
      # (or returns the original array if this selector already exists in it).
      #
      # @param sels [Array<Simple>] A {SimpleSequence}'s {SimpleSequence#members members array}
      # @return [Array<Simple>, nil] A {SimpleSequence} {SimpleSequence#members members array}
      #   matching both `sels` and this selector,
      #   or `nil` if this is impossible (e.g. unifying `#foo` and `#bar`)
      # @raise [Sass::SyntaxError] If this selector cannot be unified.
      #   This will only ever occur when a dynamic selector,
      #   such as {Parent} or {Interpolation}, is used in unification.
      #   Since these selectors should be resolved
      #   by the time extension and unification happen,
      #   this exception will only ever be raised as a result of programmer error
      def unify(sels)
        return sels if sels.any? {|sel2| eql?(sel2)}
        sels_with_ix = Sass::Util.enum_with_index(sels)
        _, i =
          if self.is_a?(Pseudo) || self.is_a?(SelectorPseudoClass)
            sels_with_ix.find {|sel, _| sel.is_a?(Pseudo) && (sels.last.type == :element)}
          else
            sels_with_ix.find {|sel, _| sel.is_a?(Pseudo) || sel.is_a?(SelectorPseudoClass)}
          end
        return sels + [self] unless i
        return sels[0...i] + [self] + sels[i..-1]
      end

      protected

      # Unifies two namespaces,
      # returning a namespace that works for both of them if possible.
      #
      # @param ns1 [String, nil] The first namespace.
      #   `nil` means none specified, e.g. `foo`.
      #   The empty string means no namespace specified, e.g. `|foo`.
      #   `"*"` means any namespace is allowed, e.g. `*|foo`.
      # @param ns2 [String, nil] The second namespace. See `ns1`.
      # @return [Array(String or nil, Boolean)]
      #   The first value is the unified namespace, or `nil` for no namespace.
      #   The second value is whether or not a namespace that works for both inputs
      #   could be found at all.
      #   If the second value is `false`, the first should be ignored.
      def unify_namespaces(ns1, ns2)
        return nil, false unless ns1 == ns2 || ns1.nil? || ns1 == ['*'] || ns2.nil? || ns2 == ['*']
        return ns2, true if ns1 == ['*']
        return ns1, true if ns2 == ['*']
        return ns1 || ns2, true
      end
    end
  end
end
module Sass
  module Selector
    # The abstract parent class of the various selector sequence classes.
    #
    # All subclasses should implement a `members` method that returns an array
    # of object that respond to `#line=` and `#filename=`, as well as a `to_a`
    # method that returns an array of strings and script nodes.
    class AbstractSequence
      # The line of the Sass template on which this selector was declared.
      #
      # @return [Fixnum]
      attr_reader :line

      # The name of the file in which this selector was declared.
      #
      # @return [String, nil]
      attr_reader :filename

      # Sets the line of the Sass template on which this selector was declared.
      # This also sets the line for all child selectors.
      #
      # @param line [Fixnum]
      # @return [Fixnum]
      def line=(line)
        members.each {|m| m.line = line}
        @line = line
      end

      # Sets the name of the file in which this selector was declared,
      # or `nil` if it was not declared in a file (e.g. on stdin).
      # This also sets the filename for all child selectors.
      #
      # @param filename [String, nil]
      # @return [String, nil]
      def filename=(filename)
        members.each {|m| m.filename = filename}
        @filename = filename
      end

      # Returns a hash code for this sequence.
      #
      # Subclasses should define `#_hash` rather than overriding this method,
      # which automatically handles memoizing the result.
      #
      # @return [Fixnum]
      def hash
        @_hash ||= _hash
      end

      # Checks equality between this and another object.
      #
      # Subclasses should define `#_eql?` rather than overriding this method,
      # which handles checking class equality and hash equality.
      #
      # @param other [Object] The object to test equality against
      # @return [Boolean] Whether or not this is equal to `other`
      def eql?(other)
        other.class == self.class && other.hash == self.hash && _eql?(other)
      end
      alias_method :==, :eql?

      # Whether or not this selector sequence contains a placeholder selector.
      # Checks recursively.
      def has_placeholder?
        @has_placeholder ||=
          members.any? {|m| m.is_a?(AbstractSequence) ? m.has_placeholder? : m.is_a?(Placeholder)}
      end

      # Converts the selector into a string. This is the standard selector
      # string, along with any SassScript interpolation that may exist.
      #
      # @return [String]
      def to_s
        to_a.map {|e| e.is_a?(Sass::Script::Node) ? "\#{#{e.to_sass}}" : e}.join
      end

      # Returns the specificity of the selector as an integer. The base is given
      # by {Sass::Selector::SPECIFICITY_BASE}.
      #
      # @return [Fixnum]
      def specificity
        _specificity(members)
      end

      protected

      def _specificity(arr)
        spec = 0
        arr.map {|m| spec += m.is_a?(String) ? 0 : m.specificity}
        spec
      end
    end
  end
end
module Sass
  module Selector
    # A comma-separated sequence of selectors.
    class CommaSequence < AbstractSequence
      # The comma-separated selector sequences
      # represented by this class.
      #
      # @return [Array<Sequence>]
      attr_reader :members

      # @param seqs [Array<Sequence>] See \{#members}
      def initialize(seqs)
        @members = seqs
      end

      # Resolves the {Parent} selectors within this selector
      # by replacing them with the given parent selector,
      # handling commas appropriately.
      #
      # @param super_cseq [CommaSequence] The parent selector
      # @return [CommaSequence] This selector, with parent references resolved
      # @raise [Sass::SyntaxError] If a parent selector is invalid
      def resolve_parent_refs(super_cseq)
        if super_cseq.nil?
          if @members.any? do |sel|
              sel.members.any? do |sel_or_op|
                sel_or_op.is_a?(SimpleSequence) && sel_or_op.members.any? {|ssel| ssel.is_a?(Parent)}
              end
            end
            raise Sass::SyntaxError.new("Base-level rules cannot contain the parent-selector-referencing character '&'.")
          end
          return self
        end

        CommaSequence.new(
          super_cseq.members.map do |super_seq|
            @members.map {|seq| seq.resolve_parent_refs(super_seq)}
          end.flatten)
      end

      # Non-destrucively extends this selector with the extensions specified in a hash
      # (which should come from {Sass::Tree::Visitors::Cssize}).
      #
      # @todo Link this to the reference documentation on `@extend`
      #   when such a thing exists.
      #
      # @param extends [Sass::Util::SubsetMap{Selector::Simple =>
      #                                       Sass::Tree::Visitors::Cssize::Extend}]
      #   The extensions to perform on this selector
      # @param parent_directives [Array<Sass::Tree::DirectiveNode>]
      #   The directives containing this selector.
      # @return [CommaSequence] A copy of this selector,
      #   with extensions made according to `extends`
      def do_extend(extends, parent_directives)
        CommaSequence.new(members.map do |seq|
            extended = seq.do_extend(extends, parent_directives)
            # First Law of Extend: the result of extending a selector should
            # always contain the base selector.
            #
            # See https://github.com/nex3/sass/issues/324.
            extended.unshift seq unless seq.has_placeholder? || extended.include?(seq)
            extended
          end.flatten)
      end

      # Returns a string representation of the sequence.
      # This is basically the selector string.
      #
      # @return [String]
      def inspect
        members.map {|m| m.inspect}.join(", ")
      end

      # @see Simple#to_a
      def to_a
        arr = Sass::Util.intersperse(@members.map {|m| m.to_a}, ", ").flatten
        arr.delete("\n")
        arr
      end

      private

      def _hash
        members.hash
      end

      def _eql?(other)
        other.class == self.class && other.members.eql?(self.members)
      end
    end
  end
end
module Sass
  module Selector
    # An operator-separated sequence of
    # {SimpleSequence simple selector sequences}.
    class Sequence < AbstractSequence
      # Sets the line of the Sass template on which this selector was declared.
      # This also sets the line for all child selectors.
      #
      # @param line [Fixnum]
      # @return [Fixnum]
      def line=(line)
        members.each {|m| m.line = line if m.is_a?(SimpleSequence)}
        line
      end

      # Sets the name of the file in which this selector was declared,
      # or `nil` if it was not declared in a file (e.g. on stdin).
      # This also sets the filename for all child selectors.
      #
      # @param filename [String, nil]
      # @return [String, nil]
      def filename=(filename)
        members.each {|m| m.filename = filename if m.is_a?(SimpleSequence)}
        filename
      end

      # The array of {SimpleSequence simple selector sequences}, operators, and
      # newlines. The operators are strings such as `"+"` and `">"` representing
      # the corresponding CSS operators, or interpolated SassScript. Newlines
      # are also newline strings; these aren't semantically relevant, but they
      # do affect formatting.
      #
      # @return [Array<SimpleSequence, String|Array<Sass::Tree::Node, String>>]
      attr_reader :members

      # @param seqs_and_ops [Array<SimpleSequence, String|Array<Sass::Tree::Node, String>>] See \{#members}
      def initialize(seqs_and_ops)
        @members = seqs_and_ops
      end

      # Resolves the {Parent} selectors within this selector
      # by replacing them with the given parent selector,
      # handling commas appropriately.
      #
      # @param super_seq [Sequence] The parent selector sequence
      # @return [Sequence] This selector, with parent references resolved
      # @raise [Sass::SyntaxError] If a parent selector is invalid
      def resolve_parent_refs(super_seq)
        members = @members.dup
        nl = (members.first == "\n" && members.shift)
        unless members.any? do |seq_or_op|
            seq_or_op.is_a?(SimpleSequence) && seq_or_op.members.first.is_a?(Parent)
          end
          old_members, members = members, []
          members << nl if nl
          members << SimpleSequence.new([Parent.new], false)
          members += old_members
        end

        Sequence.new(
          members.map do |seq_or_op|
            next seq_or_op unless seq_or_op.is_a?(SimpleSequence)
            seq_or_op.resolve_parent_refs(super_seq)
          end.flatten)
      end

      # Non-destructively extends this selector with the extensions specified in a hash
      # (which should come from {Sass::Tree::Visitors::Cssize}).
      #
      # @overload def do_extend(extends, parent_directives)
      # @param extends [Sass::Util::SubsetMap{Selector::Simple =>
      #                                       Sass::Tree::Visitors::Cssize::Extend}]
      #   The extensions to perform on this selector
      # @param parent_directives [Array<Sass::Tree::DirectiveNode>]
      #   The directives containing this selector.
      # @return [Array<Sequence>] A list of selectors generated
      #   by extending this selector with `extends`.
      #   These correspond to a {CommaSequence}'s {CommaSequence#members members array}.
      # @see CommaSequence#do_extend
      def do_extend(extends, parent_directives, seen = Set.new)
        extended_not_expanded = members.map do |sseq_or_op|
          next [[sseq_or_op]] unless sseq_or_op.is_a?(SimpleSequence)
          extended = sseq_or_op.do_extend(extends, parent_directives, seen)
          choices = extended.map {|seq| seq.members}
          choices.unshift([sseq_or_op]) unless extended.any? {|seq| seq.superselector?(sseq_or_op)}
          choices
        end
        weaves = Sass::Util.paths(extended_not_expanded).map {|path| weave(path)}
        Sass::Util.flatten(trim(weaves), 1).map {|p| Sequence.new(p)}
      end

      # Returns whether or not this selector matches all elements
      # that the given selector matches (as well as possibly more).
      #
      # @example
      #   (.foo).superselector?(.foo.bar) #=> true
      #   (.foo).superselector?(.bar) #=> false
      #   (.bar .foo).superselector?(.foo) #=> false
      # @param sseq [SimpleSequence]
      # @return [Boolean]
      def superselector?(sseq)
        return false unless members.size == 1
        members.last.superselector?(sseq)
      end

      # @see Simple#to_a
      def to_a
        ary = @members.map {|seq_or_op| seq_or_op.is_a?(SimpleSequence) ? seq_or_op.to_a : seq_or_op}
        Sass::Util.intersperse(ary, " ").flatten.compact
      end

      # Returns a string representation of the sequence.
      # This is basically the selector string.
      #
      # @return [String]
      def inspect
        members.map {|m| m.inspect}.join(" ")
      end

      # Add to the {SimpleSequence#sources} sets of the child simple sequences.
      # This destructively modifies this sequence's members array, but not the
      # child simple sequences.
      #
      # @param sources [Set<Sequence>]
      def add_sources!(sources)
        members.map! {|m| m.is_a?(SimpleSequence) ? m.with_more_sources(sources) : m}
      end

      private

      # Conceptually, this expands "parenthesized selectors".
      # That is, if we have `.A .B {@extend .C}` and `.D .C {...}`,
      # this conceptually expands into `.D .C, .D (.A .B)`,
      # and this function translates `.D (.A .B)` into `.D .A .B, .A.D .B, .D .A .B`.
      #
      # @param path [Array<Array<SimpleSequence or String>>] A list of parenthesized selector groups.
      # @return [Array<Array<SimpleSequence or String>>] A list of fully-expanded selectors.
      def weave(path)
        # This function works by moving through the selector path left-to-right,
        # building all possible prefixes simultaneously. These prefixes are
        # `befores`, while the remaining parenthesized suffixes is `afters`.
        befores = [[]]
        afters = path.dup

        until afters.empty?
          current = afters.shift.dup
          last_current = [current.pop]
          befores = Sass::Util.flatten(befores.map do |before|
              next [] unless sub = subweave(before, current)
              sub.map {|seqs| seqs + last_current}
            end, 1)
        end
        return befores
      end

      # This interweaves two lists of selectors,
      # returning all possible orderings of them (including using unification)
      # that maintain the relative ordering of the input arrays.
      #
      # For example, given `.foo .bar` and `.baz .bang`,
      # this would return `.foo .bar .baz .bang`, `.foo .bar.baz .bang`,
      # `.foo .baz .bar .bang`, `.foo .baz .bar.bang`, `.foo .baz .bang .bar`,
      # and so on until `.baz .bang .foo .bar`.
      #
      # Semantically, for selectors A and B, this returns all selectors `AB_i`
      # such that the union over all i of elements matched by `AB_i X` is
      # identical to the intersection of all elements matched by `A X` and all
      # elements matched by `B X`. Some `AB_i` are elided to reduce the size of
      # the output.
      #
      # @param seq1 [Array<SimpleSequence or String>]
      # @param seq2 [Array<SimpleSequence or String>]
      # @return [Array<Array<SimpleSequence or String>>]
      def subweave(seq1, seq2)
        return [seq2] if seq1.empty?
        return [seq1] if seq2.empty?

        seq1, seq2 = seq1.dup, seq2.dup
        return unless init = merge_initial_ops(seq1, seq2)
        return unless fin = merge_final_ops(seq1, seq2)
        seq1 = group_selectors(seq1)
        seq2 = group_selectors(seq2)
        lcs = Sass::Util.lcs(seq2, seq1) do |s1, s2|
          next s1 if s1 == s2
          next unless s1.first.is_a?(SimpleSequence) && s2.first.is_a?(SimpleSequence)
          next s2 if parent_superselector?(s1, s2)
          next s1 if parent_superselector?(s2, s1)
        end

        diff = [[init]]
        until lcs.empty?
          diff << chunks(seq1, seq2) {|s| parent_superselector?(s.first, lcs.first)} << [lcs.shift]
          seq1.shift
          seq2.shift
        end
        diff << chunks(seq1, seq2) {|s| s.empty?}
        diff += fin.map {|sel| sel.is_a?(Array) ? sel : [sel]}
        diff.reject! {|c| c.empty?}

        Sass::Util.paths(diff).map {|p| p.flatten}.reject {|p| path_has_two_subjects?(p)}
      end

      # Extracts initial selector combinators (`"+"`, `">"`, `"~"`, and `"\n"`)
      # from two sequences and merges them together into a single array of
      # selector combinators.
      #
      # @param seq1 [Array<SimpleSequence or String>]
      # @param seq2 [Array<SimpleSequence or String>]
      # @return [Array<String>, nil] If there are no operators in the merged
      #   sequence, this will be the empty array. If the operators cannot be
      #   merged, this will be nil.
      def merge_initial_ops(seq1, seq2)
        ops1, ops2 = [], []
        ops1 << seq1.shift while seq1.first.is_a?(String)
        ops2 << seq2.shift while seq2.first.is_a?(String)

        newline = false
        newline ||= !!ops1.shift if ops1.first == "\n"
        newline ||= !!ops2.shift if ops2.first == "\n"

        # If neither sequence is a subsequence of the other, they cannot be
        # merged successfully
        lcs = Sass::Util.lcs(ops1, ops2)
        return unless lcs == ops1 || lcs == ops2
        return (newline ? ["\n"] : []) + (ops1.size > ops2.size ? ops1 : ops2)
      end

      # Extracts final selector combinators (`"+"`, `">"`, `"~"`) and the
      # selectors to which they apply from two sequences and merges them
      # together into a single array.
      #
      # @param seq1 [Array<SimpleSequence or String>]
      # @param seq2 [Array<SimpleSequence or String>]
      # @return [Array<SimpleSequence or String or
      #     Array<Array<SimpleSequence or String>>]
      #   If there are no trailing combinators to be merged, this will be the
      #   empty array. If the trailing combinators cannot be merged, this will
      #   be nil. Otherwise, this will contained the merged selector. Array
      #   elements are [Sass::Util#paths]-style options; conceptually, an "or"
      #   of multiple selectors.
      def merge_final_ops(seq1, seq2, res = [])
        ops1, ops2 = [], []
        ops1 << seq1.pop while seq1.last.is_a?(String)
        ops2 << seq2.pop while seq2.last.is_a?(String)

        # Not worth the headache of trying to preserve newlines here. The most
        # important use of newlines is at the beginning of the selector to wrap
        # across lines anyway.
        ops1.reject! {|o| o == "\n"}
        ops2.reject! {|o| o == "\n"}

        return res if ops1.empty? && ops2.empty?
        if ops1.size > 1 || ops2.size > 1
          # If there are multiple operators, something hacky's going on. If one
          # is a supersequence of the other, use that, otherwise give up.
          lcs = Sass::Util.lcs(ops1, ops2)
          return unless lcs == ops1 || lcs == ops2
          res.unshift(*(ops1.size > ops2.size ? ops1 : ops2).reverse)
          return res
        end

        # This code looks complicated, but it's actually just a bunch of special
        # cases for interactions between different combinators.
        op1, op2 = ops1.first, ops2.first
        if op1 && op2
          sel1 = seq1.pop
          sel2 = seq2.pop
          if op1 == '~' && op2 == '~'
            if sel1.superselector?(sel2)
              res.unshift sel2, '~'
            elsif sel2.superselector?(sel1)
              res.unshift sel1, '~'
            else
              merged = sel1.unify(sel2.members, sel2.subject?)
              res.unshift [
                [sel1, '~', sel2, '~'],
                [sel2, '~', sel1, '~'],
                ([merged, '~'] if merged)
              ].compact
            end
          elsif (op1 == '~' && op2 == '+') || (op1 == '+' && op2 == '~')
            if op1 == '~'
              tilde_sel, plus_sel = sel1, sel2
            else
              tilde_sel, plus_sel = sel2, sel1
            end

            if tilde_sel.superselector?(plus_sel)
              res.unshift plus_sel, '+'
            else
              merged = plus_sel.unify(tilde_sel.members, tilde_sel.subject?)
              res.unshift [
                [tilde_sel, '~', plus_sel, '+'],
                ([merged, '+'] if merged)
              ].compact
            end
          elsif op1 == '>' && %w[~ +].include?(op2)
            res.unshift sel2, op2
            seq1.push sel1, op1
          elsif op2 == '>' && %w[~ +].include?(op1)
            res.unshift sel1, op1
            seq2.push sel2, op2
          elsif op1 == op2
            return unless merged = sel1.unify(sel2.members, sel2.subject?)
            res.unshift merged, op1
          else
            # Unknown selector combinators can't be unified
            return
          end
          return merge_final_ops(seq1, seq2, res)
        elsif op1
          seq2.pop if op1 == '>' && seq2.last && seq2.last.superselector?(seq1.last)
          res.unshift seq1.pop, op1
          return merge_final_ops(seq1, seq2, res)
        else # op2
          seq1.pop if op2 == '>' && seq1.last && seq1.last.superselector?(seq2.last)
          res.unshift seq2.pop, op2
          return merge_final_ops(seq1, seq2, res)
        end
      end

      # Takes initial subsequences of `seq1` and `seq2` and returns all
      # orderings of those subsequences. The initial subsequences are determined
      # by a block.
      #
      # Destructively removes the initial subsequences of `seq1` and `seq2`.
      #
      # For example, given `(A B C | D E)` and `(1 2 | 3 4 5)` (with `|`
      # denoting the boundary of the initial subsequence), this would return
      # `[(A B C 1 2), (1 2 A B C)]`. The sequences would then be `(D E)` and
      # `(3 4 5)`.
      #
      # @param seq1 [Array]
      # @param seq2 [Array]
      # @yield [a] Used to determine when to cut off the initial subsequences.
      #   Called repeatedly for each sequence until it returns true.
      # @yieldparam a [Array] A final subsequence of one input sequence after
      #   cutting off some initial subsequence.
      # @yieldreturn [Boolean] Whether or not to cut off the initial subsequence
      #   here.
      # @return [Array<Array>] All possible orderings of the initial subsequences.
      def chunks(seq1, seq2)
        chunk1 = []
        chunk1 << seq1.shift until yield seq1
        chunk2 = []
        chunk2 << seq2.shift until yield seq2
        return [] if chunk1.empty? && chunk2.empty?
        return [chunk2] if chunk1.empty?
        return [chunk1] if chunk2.empty?
        [chunk1 + chunk2, chunk2 + chunk1]
      end

      # Groups a sequence into subsequences. The subsequences are determined by
      # strings; adjacent non-string elements will be put into separate groups,
      # but any element adjacent to a string will be grouped with that string.
      #
      # For example, `(A B "C" D E "F" G "H" "I" J)` will become `[(A) (B "C" D)
      # (E "F" G "H" "I" J)]`.
      #
      # @param seq [Array]
      # @return [Array<Array>]
      def group_selectors(seq)
        newseq = []
        tail = seq.dup
        until tail.empty?
          head = []
          begin
            head << tail.shift
          end while !tail.empty? && head.last.is_a?(String) || tail.first.is_a?(String)
          newseq << head
        end
        return newseq
      end

      # Given two selector sequences, returns whether `seq1` is a
      # superselector of `seq2`; that is, whether `seq1` matches every
      # element `seq2` matches.
      #
      # @param seq1 [Array<SimpleSequence or String>]
      # @param seq2 [Array<SimpleSequence or String>]
      # @return [Boolean]
      def _superselector?(seq1, seq2)
        seq1 = seq1.reject {|e| e == "\n"}
        seq2 = seq2.reject {|e| e == "\n"}
        # Selectors with leading or trailing operators are neither
        # superselectors nor subselectors.
        return if seq1.last.is_a?(String) || seq2.last.is_a?(String) ||
          seq1.first.is_a?(String) || seq2.first.is_a?(String)
        # More complex selectors are never superselectors of less complex ones
        return if seq1.size > seq2.size
        return seq1.first.superselector?(seq2.last) if seq1.size == 1

        _, si = Sass::Util.enum_with_index(seq2).find do |e, i|
          return if i == seq2.size - 1
          next if e.is_a?(String)
          seq1.first.superselector?(e)
        end
        return unless si

        if seq1[1].is_a?(String)
          return unless seq2[si+1].is_a?(String)
          # .foo ~ .bar is a superselector of .foo + .bar
          return unless seq1[1] == "~" ? seq2[si+1] != ">" : seq1[1] == seq2[si+1]
          return _superselector?(seq1[2..-1], seq2[si+2..-1])
        elsif seq2[si+1].is_a?(String)
          return unless seq2[si+1] == ">"
          return _superselector?(seq1[1..-1], seq2[si+2..-1])
        else
          return _superselector?(seq1[1..-1], seq2[si+1..-1])
        end
      end

      # Like \{#_superselector?}, but compares the selectors in the
      # context of parent selectors, as though they shared an implicit
      # base simple selector. For example, `B` is not normally a
      # superselector of `B A`, since it doesn't match `A` elements.
      # However, it is a parent superselector, since `B X` is a
      # superselector of `B A X`.
      #
      # @param seq1 [Array<SimpleSequence or String>]
      # @param seq2 [Array<SimpleSequence or String>]
      # @return [Boolean]
      def parent_superselector?(seq1, seq2)
        base = Sass::Selector::SimpleSequence.new([Sass::Selector::Placeholder.new('<temp>')], false)
        _superselector?(seq1 + [base], seq2 + [base])
      end

      # Removes redundant selectors from between multiple lists of
      # selectors. This takes a list of lists of selector sequences;
      # each individual list is assumed to have no redundancy within
      # itself. A selector is only removed if it's redundant with a
      # selector in another list.
      #
      # "Redundant" here means that one selector is a superselector of
      # the other. The more specific selector is removed.
      #
      # @param seqses [Array<Array<Array<SimpleSequence or String>>>]
      # @return [Array<Array<Array<SimpleSequence or String>>>]
      def trim(seqses)
        # Avoid truly horrific quadratic behavior. TODO: I think there
        # may be a way to get perfect trimming without going quadratic.
        return seqses if seqses.size > 100

        # Keep the results in a separate array so we can be sure we aren't
        # comparing against an already-trimmed selector. This ensures that two
        # identical selectors don't mutually trim one another.
        result = seqses.dup

        # This is n^2 on the sequences, but only comparing between
        # separate sequences should limit the quadratic behavior.
        seqses.each_with_index do |seqs1, i|
          result[i] = seqs1.reject do |seq1|
            max_spec = _sources(seq1).map {|seq| seq.specificity}.max || 0
            result.any? do |seqs2|
              next if seqs1.equal?(seqs2)
              # Second Law of Extend: the specificity of a generated selector
              # should never be less than the specificity of the extending
              # selector.
              #
              # See https://github.com/nex3/sass/issues/324.
              seqs2.any? {|seq2| _specificity(seq2) >= max_spec && _superselector?(seq2, seq1)}
            end
          end
        end
        result
      end

      def _hash
        members.reject {|m| m == "\n"}.hash
      end

      def _eql?(other)
        other.members.reject {|m| m == "\n"}.eql?(self.members.reject {|m| m == "\n"})
      end

      private

      def path_has_two_subjects?(path)
        subject = false
        path.each do |sseq_or_op|
          next unless sseq_or_op.is_a?(SimpleSequence)
          next unless sseq_or_op.subject?
          return true if subject
          subject = true
        end
        false
      end

      def _sources(seq)
        s = Set.new
        seq.map {|sseq_or_op| s.merge sseq_or_op.sources if sseq_or_op.is_a?(SimpleSequence)}
        s
      end

      def extended_not_expanded_to_s(extended_not_expanded)
        extended_not_expanded.map do |choices|
          choices = choices.map do |sel|
            next sel.first.to_s if sel.size == 1
            "#{sel.join ' '}"
          end
          next choices.first if choices.size == 1 && !choices.include?(' ')
          "(#{choices.join ', '})"
        end.join ' '
      end
    end
  end
end
module Sass
  module Selector
    # A unseparated sequence of selectors
    # that all apply to a single element.
    # For example, `.foo#bar[attr=baz]` is a simple sequence
    # of the selectors `.foo`, `#bar`, and `[attr=baz]`.
    class SimpleSequence < AbstractSequence
      # The array of individual selectors.
      #
      # @return [Array<Simple>]
      attr_accessor :members

      # The extending selectors that caused this selector sequence to be
      # generated. For example:
      #
      #     a.foo { ... }
      #     b.bar {@extend a}
      #     c.baz {@extend b}
      #
      # The generated selector `b.foo.bar` has `{b.bar}` as its `sources` set,
      # and the generated selector `c.foo.bar.baz` has `{b.bar, c.baz}` as its
      # `sources` set.
      #
      # This is populated during the {#do_extend} process.
      #
      # @return {Set<Sequence>}
      attr_accessor :sources

      # @see \{#subject?}
      attr_writer :subject

      # Returns the element or universal selector in this sequence,
      # if it exists.
      #
      # @return [Element, Universal, nil]
      def base
        @base ||= (members.first if members.first.is_a?(Element) || members.first.is_a?(Universal))
      end

      def pseudo_elements
        @pseudo_elements ||= (members - [base]).
          select {|sel| sel.is_a?(Pseudo) && sel.type == :element}
      end

      # Returns the non-base, non-pseudo-class selectors in this sequence.
      #
      # @return [Set<Simple>]
      def rest
        @rest ||= Set.new(members - [base] - pseudo_elements)
      end

      # Whether or not this compound selector is the subject of the parent
      # selector; that is, whether it is prepended with `$` and represents the
      # actual element that will be selected.
      #
      # @return [Boolean]
      def subject?
        @subject
      end

      # @param selectors [Array<Simple>] See \{#members}
      # @param subject [Boolean] See \{#subject?}
      # @param sources [Set<Sequence>]
      def initialize(selectors, subject, sources = Set.new)
        @members = selectors
        @subject = subject
        @sources = sources
      end

      # Resolves the {Parent} selectors within this selector
      # by replacing them with the given parent selector,
      # handling commas appropriately.
      #
      # @param super_seq [Sequence] The parent selector sequence
      # @return [Array<SimpleSequence>] This selector, with parent references resolved.
      #   This is an array because the parent selector is itself a {Sequence}
      # @raise [Sass::SyntaxError] If a parent selector is invalid
      def resolve_parent_refs(super_seq)
        # Parent selector only appears as the first selector in the sequence
        return [self] unless @members.first.is_a?(Parent)

        return super_seq.members if @members.size == 1
        unless super_seq.members.last.is_a?(SimpleSequence)
          raise Sass::SyntaxError.new("Invalid parent selector: " + super_seq.to_a.join)
        end

        super_seq.members[0...-1] +
          [SimpleSequence.new(super_seq.members.last.members + @members[1..-1], subject?)]
      end

      # Non-destrucively extends this selector with the extensions specified in a hash
      # (which should come from {Sass::Tree::Visitors::Cssize}).
      #
      # @overload def do_extend(extends, parent_directives)
      # @param extends [{Selector::Simple =>
      #                  Sass::Tree::Visitors::Cssize::Extend}]
      #   The extensions to perform on this selector
      # @param parent_directives [Array<Sass::Tree::DirectiveNode>]
      #   The directives containing this selector.
      # @return [Array<Sequence>] A list of selectors generated
      #   by extending this selector with `extends`.
      # @see CommaSequence#do_extend
      def do_extend(extends, parent_directives, seen = Set.new)
        Sass::Util.group_by_to_a(extends.get(members.to_set)) {|ex, _| ex.extender}.map do |seq, group|
          sels = group.map {|_, s| s}.flatten
          # If A {@extend B} and C {...},
          # seq is A, sels is B, and self is C

          self_without_sel = Sass::Util.array_minus(self.members, sels)
          group.each {|e, _| e.result = :failed_to_unify unless e.result == :succeeded}
          next unless unified = seq.members.last.unify(self_without_sel, subject?)
          group.each {|e, _| e.result = :succeeded}
          next if group.map {|e, _| check_directives_match!(e, parent_directives)}.none?
          new_seq = Sequence.new(seq.members[0...-1] + [unified])
          new_seq.add_sources!(sources + [seq])
          [sels, new_seq]
        end.compact.map do |sels, seq|
          seen.include?(sels) ? [] : seq.do_extend(extends, parent_directives, seen + [sels])
        end.flatten.uniq
      end

      # Unifies this selector with another {SimpleSequence}'s {SimpleSequence#members members array},
      # returning another `SimpleSequence`
      # that matches both this selector and the input selector.
      #
      # @param sels [Array<Simple>] A {SimpleSequence}'s {SimpleSequence#members members array}
      # @param subject [Boolean] Whether the {SimpleSequence} being merged is a subject.
      # @return [SimpleSequence, nil] A {SimpleSequence} matching both `sels` and this selector,
      #   or `nil` if this is impossible (e.g. unifying `#foo` and `#bar`)
      # @raise [Sass::SyntaxError] If this selector cannot be unified.
      #   This will only ever occur when a dynamic selector,
      #   such as {Parent} or {Interpolation}, is used in unification.
      #   Since these selectors should be resolved
      #   by the time extension and unification happen,
      #   this exception will only ever be raised as a result of programmer error
      def unify(sels, other_subject)
        return unless sseq = members.inject(sels) do |member, sel|
          return unless member
          sel.unify(member)
        end
        SimpleSequence.new(sseq, other_subject || subject?)
      end

      # Returns whether or not this selector matches all elements
      # that the given selector matches (as well as possibly more).
      #
      # @example
      #   (.foo).superselector?(.foo.bar) #=> true
      #   (.foo).superselector?(.bar) #=> false
      # @param sseq [SimpleSequence]
      # @return [Boolean]
      def superselector?(sseq)
        (base.nil? || base.eql?(sseq.base)) &&
          pseudo_elements.eql?(sseq.pseudo_elements) &&
          rest.subset?(sseq.rest)
      end

      # @see Simple#to_a
      def to_a
        res = @members.map {|sel| sel.to_a}.flatten
        res << '!' if subject?
        res
      end

      # Returns a string representation of the sequence.
      # This is basically the selector string.
      #
      # @return [String]
      def inspect
        members.map {|m| m.inspect}.join
      end

      # Return a copy of this simple sequence with `sources` merged into the
      # {#sources} set.
      #
      # @param sources [Set<Sequence>]
      # @return [SimpleSequence]
      def with_more_sources(sources)
        sseq = dup
        sseq.members = members.dup
        sseq.sources = self.sources | sources
        sseq
      end

      private

      def check_directives_match!(extend, parent_directives)
        dirs1 = extend.directives.map {|d| d.resolved_value}
        dirs2 = parent_directives.map {|d| d.resolved_value}
        return true if Sass::Util.subsequence?(dirs1, dirs2)

        Sass::Util.sass_warn <<WARNING
DEPRECATION WARNING on line #{extend.node.line}#{" of #{extend.node.filename}" if extend.node.filename}:
  @extending an outer selector from within #{extend.directives.last.name} is deprecated.
  You may only @extend selectors within the same directive.
  This will be an error in Sass 3.3.
  It can only work once @extend is supported natively in the browser.
WARNING
        return false
      end

      def _hash
        [base, Sass::Util.set_hash(rest)].hash
      end

      def _eql?(other)
        other.base.eql?(self.base) && other.pseudo_elements == pseudo_elements &&
          Sass::Util.set_eql?(other.rest, self.rest) && other.subject? == self.subject?
      end
    end
  end
end

module Sass
  # A namespace for nodes in the parse tree for selectors.
  #
  # {CommaSequence} is the toplevel seelctor,
  # representing a comma-separated sequence of {Sequence}s,
  # such as `foo bar, baz bang`.
  # {Sequence} is the next level,
  # representing {SimpleSequence}s separated by combinators (e.g. descendant or child),
  # such as `foo bar` or `foo > bar baz`.
  # {SimpleSequence} is a sequence of selectors that all apply to a single element,
  # such as `foo.bar[attr=val]`.
  # Finally, {Simple} is the superclass of the simplest selectors,
  # such as `.foo` or `#bar`.
  module Selector
    # The base used for calculating selector specificity. The spec says this
    # should be "sufficiently high"; it's extremely unlikely that any single
    # selector sequence will contain 1,000 simple selectors.
    #
    # @type [Fixnum]
    SPECIFICITY_BASE = 1_000

    # A parent-referencing selector (`&` in Sass).
    # The function of this is to be replaced by the parent selector
    # in the nested hierarchy.
    class Parent < Simple
      # @see Selector#to_a
      def to_a
        ["&"]
      end

      # Always raises an exception.
      #
      # @raise [Sass::SyntaxError] Parent selectors should be resolved before unification
      # @see Selector#unify
      def unify(sels)
        raise Sass::SyntaxError.new("[BUG] Cannot unify parent selectors.")
      end
    end

    # A class selector (e.g. `.foo`).
    class Class < Simple
      # The class name.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # @param name [Array<String, Sass::Script::Node>] The class name
      def initialize(name)
        @name = name
      end

      # @see Selector#to_a
      def to_a
        [".", *@name]
      end

      # @see AbstractSequence#specificity
      def specificity
        SPECIFICITY_BASE
      end
    end

    # An id selector (e.g. `#foo`).
    class Id < Simple
      # The id name.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # @param name [Array<String, Sass::Script::Node>] The id name
      def initialize(name)
        @name = name
      end

      # @see Selector#to_a
      def to_a
        ["#", *@name]
      end

      # Returns `nil` if `sels` contains an {Id} selector
      # with a different name than this one.
      #
      # @see Selector#unify
      def unify(sels)
        return if sels.any? {|sel2| sel2.is_a?(Id) && self.name != sel2.name}
        super
      end

      # @see AbstractSequence#specificity
      def specificity
        SPECIFICITY_BASE**2
      end
    end

    # A placeholder selector (e.g. `%foo`).
    # This exists to be replaced via `@extend`.
    # Rulesets using this selector will not be printed, but can be extended.
    # Otherwise, this acts just like a class selector.
    class Placeholder < Simple
      # The placeholder name.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # @param name [Array<String, Sass::Script::Node>] The placeholder name
      def initialize(name)
        @name = name
      end

      # @see Selector#to_a
      def to_a
        ["%", *@name]
      end

      # @see AbstractSequence#specificity
      def specificity
        SPECIFICITY_BASE
      end
    end

    # A universal selector (`*` in CSS).
    class Universal < Simple
      # The selector namespace.
      # `nil` means the default namespace,
      # `[""]` means no namespace,
      # `["*"]` means any namespace.
      #
      # @return [Array<String, Sass::Script::Node>, nil]
      attr_reader :namespace

      # @param namespace [Array<String, Sass::Script::Node>, nil] See \{#namespace}
      def initialize(namespace)
        @namespace = namespace
      end

      # @see Selector#to_a
      def to_a
        @namespace ? @namespace + ["|*"] : ["*"]
      end

      # Unification of a universal selector is somewhat complicated,
      # especially when a namespace is specified.
      # If there is no namespace specified
      # or any namespace is specified (namespace `"*"`),
      # then `sel` is returned without change
      # (unless it's empty, in which case `"*"` is required).
      #
      # If a namespace is specified
      # but `sel` does not specify a namespace,
      # then the given namespace is applied to `sel`,
      # either by adding this {Universal} selector
      # or applying this namespace to an existing {Element} selector.
      #
      # If both this selector *and* `sel` specify namespaces,
      # those namespaces are unified via {Simple#unify_namespaces}
      # and the unified namespace is used, if possible.
      #
      # @todo There are lots of cases that this documentation specifies;
      #   make sure we thoroughly test **all of them**.
      # @todo Keep track of whether a default namespace has been declared
      #   and handle namespace-unspecified selectors accordingly.
      # @todo If any branch of a CommaSequence ends up being just `"*"`,
      #   then all other branches should be eliminated
      #
      # @see Selector#unify
      def unify(sels)
        name =
          case sels.first
          when Universal; :universal
          when Element; sels.first.name
          else
            return [self] + sels unless namespace.nil? || namespace == ['*']
            return sels unless sels.empty?
            return [self]
          end

        ns, accept = unify_namespaces(namespace, sels.first.namespace)
        return unless accept
        [name == :universal ? Universal.new(ns) : Element.new(name, ns)] + sels[1..-1]
      end

      # @see AbstractSequence#specificity
      def specificity
        0
      end
    end

    # An element selector (e.g. `h1`).
    class Element < Simple
      # The element name.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # The selector namespace.
      # `nil` means the default namespace,
      # `[""]` means no namespace,
      # `["*"]` means any namespace.
      #
      # @return [Array<String, Sass::Script::Node>, nil]
      attr_reader :namespace

      # @param name [Array<String, Sass::Script::Node>] The element name
      # @param namespace [Array<String, Sass::Script::Node>, nil] See \{#namespace}
      def initialize(name, namespace)
        @name = name
        @namespace = namespace
      end

      # @see Selector#to_a
      def to_a
        @namespace ? @namespace + ["|"] + @name : @name
      end

      # Unification of an element selector is somewhat complicated,
      # especially when a namespace is specified.
      # First, if `sel` contains another {Element} with a different \{#name},
      # then the selectors can't be unified and `nil` is returned.
      #
      # Otherwise, if `sel` doesn't specify a namespace,
      # or it specifies any namespace (via `"*"`),
      # then it's returned with this element selector
      # (e.g. `.foo` becomes `a.foo` or `svg|a.foo`).
      # Similarly, if this selector doesn't specify a namespace,
      # the namespace from `sel` is used.
      #
      # If both this selector *and* `sel` specify namespaces,
      # those namespaces are unified via {Simple#unify_namespaces}
      # and the unified namespace is used, if possible.
      #
      # @todo There are lots of cases that this documentation specifies;
      #   make sure we thoroughly test **all of them**.
      # @todo Keep track of whether a default namespace has been declared
      #   and handle namespace-unspecified selectors accordingly.
      #
      # @see Selector#unify
      def unify(sels)
        case sels.first
        when Universal;
        when Element; return unless name == sels.first.name
        else return [self] + sels
        end

        ns, accept = unify_namespaces(namespace, sels.first.namespace)
        return unless accept
        [Element.new(name, ns)] + sels[1..-1]
      end

      # @see AbstractSequence#specificity
      def specificity
        1
      end
    end

    # Selector interpolation (`#{}` in Sass).
    class Interpolation < Simple
      # The script to run.
      #
      # @return [Sass::Script::Node]
      attr_reader :script

      # @param script [Sass::Script::Node] The script to run
      def initialize(script)
        @script = script
      end

      # @see Selector#to_a
      def to_a
        [@script]
      end

      # Always raises an exception.
      #
      # @raise [Sass::SyntaxError] Interpolation selectors should be resolved before unification
      # @see Selector#unify
      def unify(sels)
        raise Sass::SyntaxError.new("[BUG] Cannot unify interpolation selectors.")
      end
    end

    # An attribute selector (e.g. `[href^="http://"]`).
    class Attribute < Simple
      # The attribute name.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # The attribute namespace.
      # `nil` means the default namespace,
      # `[""]` means no namespace,
      # `["*"]` means any namespace.
      #
      # @return [Array<String, Sass::Script::Node>, nil]
      attr_reader :namespace

      # The matching operator, e.g. `"="` or `"^="`.
      #
      # @return [String]
      attr_reader :operator

      # The right-hand side of the operator.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :value

      # Flags for the attribute selector (e.g. `i`).
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :flags

      # @param name [Array<String, Sass::Script::Node>] The attribute name
      # @param namespace [Array<String, Sass::Script::Node>, nil] See \{#namespace}
      # @param operator [String] The matching operator, e.g. `"="` or `"^="`
      # @param value [Array<String, Sass::Script::Node>] See \{#value}
      # @param value [Array<String, Sass::Script::Node>] See \{#flags}
      def initialize(name, namespace, operator, value, flags)
        @name = name
        @namespace = namespace
        @operator = operator
        @value = value
        @flags = flags
      end

      # @see Selector#to_a
      def to_a
        res = ["["]
        res.concat(@namespace) << "|" if @namespace
        res.concat @name
        (res << @operator).concat @value if @value
        (res << " ").concat @flags if @flags
        res << "]"
      end

      # @see AbstractSequence#specificity
      def specificity
        SPECIFICITY_BASE
      end
    end

    # A pseudoclass (e.g. `:visited`) or pseudoelement (e.g. `::first-line`) selector.
    # It can have arguments (e.g. `:nth-child(2n+1)`).
    class Pseudo < Simple
      # Some psuedo-class-syntax selectors are actually considered
      # pseudo-elements and must be treated differently. This is a list of such
      # selectors
      #
      # @return [Array<String>]
      ACTUALLY_ELEMENTS = %w[after before first-line first-letter]

      # Like \{#type}, but returns the type of selector this looks like, rather
      # than the type it is semantically. This only differs from type for
      # selectors in \{ACTUALLY\_ELEMENTS}.
      #
      # @return [Symbol]
      attr_reader :syntactic_type

      # The name of the selector.
      #
      # @return [Array<String, Sass::Script::Node>]
      attr_reader :name

      # The argument to the selector,
      # or `nil` if no argument was given.
      #
      # This may include SassScript nodes that will be run during resolution.
      # Note that this should not include SassScript nodes
      # after resolution has taken place.
      #
      # @return [Array<String, Sass::Script::Node>, nil]
      attr_reader :arg

      # @param type [Symbol] See \{#type}
      # @param name [Array<String, Sass::Script::Node>] The name of the selector
      # @param arg [nil, Array<String, Sass::Script::Node>] The argument to the selector,
      #   or nil if no argument was given
      def initialize(type, name, arg)
        @syntactic_type = type
        @name = name
        @arg = arg
      end

      # The type of the selector. `:class` if this is a pseudoclass selector,
      # `:element` if it's a pseudoelement.
      #
      # @return [Symbol]
      def type
        ACTUALLY_ELEMENTS.include?(name.first) ? :element : syntactic_type
      end

      # @see Selector#to_a
      def to_a
        res = [syntactic_type == :class ? ":" : "::"] + @name
        (res << "(").concat(Sass::Util.strip_string_array(@arg)) << ")" if @arg
        res
      end

      # Returns `nil` if this is a pseudoelement selector
      # and `sels` contains a pseudoelement selector different than this one.
      #
      # @see Selector#unify
      def unify(sels)
        return if type == :element && sels.any? do |sel|
          sel.is_a?(Pseudo) && sel.type == :element &&
            (sel.name != self.name || sel.arg != self.arg)
        end
        super
      end

      # @see AbstractSequence#specificity
      def specificity
        type == :class ? SPECIFICITY_BASE : 1
      end
    end

    # A pseudoclass selector whose argument is itself a selector
    # (e.g. `:not(.foo)` or `:-moz-all(.foo, .bar)`).
    class SelectorPseudoClass < Simple
      # The name of the pseudoclass.
      #
      # @return [String]
      attr_reader :name

      # The selector argument.
      #
      # @return [Selector::Sequence]
      attr_reader :selector

      # @param [String] The name of the pseudoclass
      # @param [Selector::CommaSequence] The selector argument
      def initialize(name, selector)
        @name = name
        @selector = selector
      end

      # @see Selector#to_a
      def to_a
        [":", @name, "("] + @selector.to_a + [")"]
      end

      # @see AbstractSequence#specificity
      def specificity
        SPECIFICITY_BASE
      end
    end
  end
end

module Sass
  # The lexical environment for SassScript.
  # This keeps track of variable, mixin, and function definitions.
  #
  # A new environment is created for each level of Sass nesting.
  # This allows variables to be lexically scoped.
  # The new environment refers to the environment in the upper scope,
  # so it has access to variables defined in enclosing scopes,
  # but new variables are defined locally.
  #
  # Environment also keeps track of the {Engine} options
  # so that they can be made available to {Sass::Script::Functions}.
  class Environment
    # The enclosing environment,
    # or nil if this is the global environment.
    #
    # @return [Environment]
    attr_reader :parent
    attr_reader :options
    attr_writer :caller
    attr_writer :content

    # @param options [{Symbol => Object}] The options hash. See
    #   {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    # @param parent [Environment] See \{#parent}
    def initialize(parent = nil, options = nil)
      @parent = parent
      @options = options || (parent && parent.options) || {}
    end

    # The environment of the caller of this environment's mixin or function.
    # @return {Environment?}
    def caller
      @caller || (@parent && @parent.caller)
    end

    # The content passed to this environmnet. This is naturally only set
    # for mixin body environments with content passed in.
    # @return {Environment?}
    def content
      @content || (@parent && @parent.content)
    end

    private

    class << self
      private
      UNDERSCORE, DASH = '_', '-'

      # Note: when updating this,
      # update sass/yard/inherited_hash.rb as well.
      def inherited_hash(name)
        class_eval <<RUBY, __FILE__, __LINE__ + 1
          def #{name}(name)
            _#{name}(name.tr(UNDERSCORE, DASH))
          end

          def _#{name}(name)
            (@#{name}s && @#{name}s[name]) || @parent && @parent._#{name}(name)
          end
          protected :_#{name}

          def set_#{name}(name, value)
            name = name.tr(UNDERSCORE, DASH)
            @#{name}s[name] = value unless try_set_#{name}(name, value)
          end

          def try_set_#{name}(name, value)
            @#{name}s ||= {}
            if @#{name}s.include?(name)
              @#{name}s[name] = value
              true
            elsif @parent
              @parent.try_set_#{name}(name, value)
            else
              false
            end
          end
          protected :try_set_#{name}

          def set_local_#{name}(name, value)
            @#{name}s ||= {}
            @#{name}s[name.tr(UNDERSCORE, DASH)] = value
          end
RUBY
      end
    end

    # variable
    # Script::Literal
    inherited_hash :var
    # mixin
    # Sass::Callable
    inherited_hash :mixin
    # function
    # Sass::Callable
    inherited_hash :function
  end
end
module Sass::Script
  # The abstract superclass for SassScript parse tree nodes.
  #
  # Use \{#perform} to evaluate a parse tree.
  class Node
    # The options hash for this node.
    #
    # @return [{Symbol => Object}]
    attr_reader :options

    # The line of the document on which this node appeared.
    #
    # @return [Fixnum]
    attr_accessor :line

    # Sets the options hash for this node,
    # as well as for all child nodes.
    # See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    #
    # @param options [{Symbol => Object}] The options
    def options=(options)
      @options = options
      children.each do |c|
        if c.is_a? Hash
          c.values.each {|v| v.options = options }
        else
          c.options = options
        end
      end
    end

    # Evaluates the node.
    #
    # \{#perform} shouldn't be overridden directly;
    # instead, override \{#\_perform}.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Literal] The SassScript object that is the value of the SassScript
    def perform(environment)
      _perform(environment)
    rescue Sass::SyntaxError => e
      e.modify_backtrace(:line => line)
      raise e
    end

    # Returns all child nodes of this node.
    #
    # @return [Array<Node>]
    def children
      Sass::Util.abstract(self)
    end

    # Returns the text of this SassScript expression.
    #
    # @return [String]
    def to_sass(opts = {})
      Sass::Util.abstract(self)
    end

    # Returns a deep clone of this node.
    # The child nodes are cloned, but options are not.
    #
    # @return [Node]
    def deep_copy
      Sass::Util.abstract(self)
    end

    protected

    # Converts underscores to dashes if the :dasherize option is set.
    def dasherize(s, opts)
      if opts[:dasherize]
        s.gsub(/_/,'-')
      else
        s
      end
    end

    # Evaluates this node.
    # Note that all {Literal} objects created within this method
    # should have their \{#options} attribute set, probably via \{#opts}.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Literal] The SassScript object that is the value of the SassScript
    # @see #perform
    def _perform(environment)
      Sass::Util.abstract(self)
    end

    # Sets the \{#options} field on the given literal and returns it
    #
    # @param literal [Literal]
    # @return [Literal]
    def opts(literal)
      literal.options = options
      literal
    end
  end
end
module Sass
  module Script
    # A SassScript parse node representing a variable.
    class Variable < Node
      # The name of the variable.
      #
      # @return [String]
      attr_reader :name

      # The underscored name of the variable.
      #
      # @return [String]
      attr_reader :underscored_name

      # @param name [String] See \{#name}
      def initialize(name)
        @name = name
        @underscored_name = name.gsub(/-/,"_")
        super()
      end

      # @return [String] A string representation of the variable
      def inspect(opts = {})
        "$#{dasherize(name, opts)}"
      end
      alias_method :to_sass, :inspect

      # Returns an empty array.
      #
      # @return [Array<Node>] empty
      # @see Node#children
      def children
        []
      end

      # @see Node#deep_copy
      def deep_copy
        dup
      end

      protected

      # Evaluates the variable.
      #
      # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
      # @return [Literal] The SassScript object that is the value of the variable
      # @raise [Sass::SyntaxError] if the variable is undefined
      def _perform(environment)
        raise SyntaxError.new("Undefined variable: \"$#{name}\".") unless val = environment.var(name)
        if val.is_a?(Number)
          val = val.dup
          val.original = nil
        end
        return val
      end
    end
  end
end
module Sass::Script
  # Methods in this module are accessible from the SassScript context.
  # For example, you can write
  #
  #     $color: hsl(120deg, 100%, 50%)
  #
  # and it will call {Sass::Script::Functions#hsl}.
  #
  # The following functions are provided:
  #
  # *Note: These functions are described in more detail below.*
  #
  # ## RGB Functions
  #
  # \{#rgb rgb($red, $green, $blue)}
  # : Creates a {Color} from red, green, and blue values.
  #
  # \{#rgba rgba($red, $green, $blue, $alpha)}
  # : Creates a {Color} from red, green, blue, and alpha values.
  #
  # \{#red red($color)}
  # : Gets the red component of a color.
  #
  # \{#green green($color)}
  # : Gets the green component of a color.
  #
  # \{#blue blue($color)}
  # : Gets the blue component of a color.
  #
  # \{#mix mix($color-1, $color-2, \[$weight\])}
  # : Mixes two colors together.
  #
  # ## HSL Functions
  #
  # \{#hsl hsl($hue, $saturation, $lightness)}
  # : Creates a {Color} from hue, saturation, and lightness values.
  #
  # \{#hsla hsla($hue, $saturation, $lightness, $alpha)}
  # : Creates a {Color} from hue, saturation, lightness, and alpha
  #   values.
  #
  # \{#hue hue($color)}
  # : Gets the hue component of a color.
  #
  # \{#saturation saturation($color)}
  # : Gets the saturation component of a color.
  #
  # \{#lightness lightness($color)}
  # : Gets the lightness component of a color.
  #
  # \{#adjust_hue adjust-hue($color, $degrees)}
  # : Changes the hue of a color.
  #
  # \{#lighten lighten($color, $amount)}
  # : Makes a color lighter.
  #
  # \{#darken darken($color, $amount)}
  # : Makes a color darker.
  #
  # \{#saturate saturate($color, $amount)}
  # : Makes a color more saturated.
  #
  # \{#desaturate desaturate($color, $amount)}
  # : Makes a color less saturated.
  #
  # \{#grayscale grayscale($color)}
  # : Converts a color to grayscale.
  #
  # \{#complement complement($color)}
  # : Returns the complement of a color.
  #
  # \{#invert invert($color)}
  # : Returns the inverse of a color.
  #
  # ## Opacity Functions
  #
  # \{#alpha alpha($color)} / \{#opacity opacity($color)}
  # : Gets the alpha component (opacity) of a color.
  #
  # \{#rgba rgba($color, $alpha)}
  # : Changes the alpha component for a color.
  #
  # \{#opacify opacify($color, $amount)} / \{#fade_in fade-in($color, $amount)}
  # : Makes a color more opaque.
  #
  # \{#transparentize transparentize($color, $amount)} / \{#fade_out fade-out($color, $amount)}
  # : Makes a color more transparent.
  #
  # ## Other Color Functions
  #
  # \{#adjust_color adjust-color($color, \[$red\], \[$green\], \[$blue\], \[$hue\], \[$saturation\], \[$lightness\], \[$alpha\])}
  # : Increases or decreases one or more components of a color.
  #
  # \{#scale_color scale-color($color, \[$red\], \[$green\], \[$blue\], \[$saturation\], \[$lightness\], \[$alpha\])}
  # : Fluidly scales one or more properties of a color.
  #
  # \{#change_color change-color($color, \[$red\], \[$green\], \[$blue\], \[$hue\], \[$saturation\], \[$lightness\], \[$alpha\])}
  # : Changes one or more properties of a color.
  #
  # \{#ie_hex_str ie-hex-str($color)}
  # : Converts a color into the format understood by IE filters.
  #
  # ## String Functions
  #
  # \{#unquote unquote($string)}
  # : Removes quotes from a string.
  #
  # \{#quote quote($string)}
  # : Adds quotes to a string.
  #
  # ## Number Functions
  #
  # \{#percentage percentage($value)}
  # : Converts a unitless number to a percentage.
  #
  # \{#round round($value)}
  # : Rounds a number to the nearest whole number.
  #
  # \{#ceil ceil($value)}
  # : Rounds a number up to the next whole number.
  #
  # \{#floor floor($value)}
  # : Rounds a number down to the previous whole number.
  #
  # \{#abs abs($value)}
  # : Returns the absolute value of a number.
  #
  # \{#min min($numbers...)\}
  # : Finds the minimum of several numbers.
  #
  # \{#max max($numbers...)\}
  # : Finds the maximum of several numbers.
  #
  # ## List Functions {#list-functions}
  #
  # \{#length length($list)}
  # : Returns the length of a list.
  #
  # \{#nth nth($list, $n)}
  # : Returns a specific item in a list.
  #
  # \{#join join($list1, $list2, \[$separator\])}
  # : Joins together two lists into one.
  #
  # \{#append append($list1, $val, \[$separator\])}
  # : Appends a single value onto the end of a list.
  #
  # \{#zip zip($lists...)}
  # : Combines several lists into a single multidimensional list.
  #
  # \{#index index($list, $value)}
  # : Returns the position of a value within a list.
  #
  # ## Introspection Functions
  #
  # \{#type_of type-of($value)}
  # : Returns the type of a value.
  #
  # \{#unit unit($number)}
  # : Returns the unit(s) associated with a number.
  #
  # \{#unitless unitless($number)}
  # : Returns whether a number has units.
  #
  # \{#comparable comparable($number-1, $number-2)}
  # : Returns whether two numbers can be added, subtracted, or compared.
  #
  # ## Miscellaneous Functions
  #
  # \{#if if($condition, $if-true, $if-false)}
  # : Returns one of two values, depending on whether or not `$condition` is
  #   true.
  #
  # ## Adding Custom Functions
  #
  # New Sass functions can be added by adding Ruby methods to this module.
  # For example:
  #
  #     module Sass::Script::Functions
  #       def reverse(string)
  #         assert_type string, :String
  #         Sass::Script::String.new(string.value.reverse)
  #       end
  #       declare :reverse, :args => [:string]
  #     end
  #
  # Calling {declare} tells Sass the argument names for your function.
  # If omitted, the function will still work, but will not be able to accept keyword arguments.
  # {declare} can also allow your function to take arbitrary keyword arguments.
  #
  # There are a few things to keep in mind when modifying this module.
  # First of all, the arguments passed are {Sass::Script::Literal} objects.
  # Literal objects are also expected to be returned.
  # This means that Ruby values must be unwrapped and wrapped.
  #
  # Most Literal objects support the {Sass::Script::Literal#value value} accessor
  # for getting their Ruby values.
  # Color objects, though, must be accessed using {Sass::Script::Color#rgb rgb},
  # {Sass::Script::Color#red red}, {Sass::Script::Color#blue green}, or {Sass::Script::Color#blue blue}.
  #
  # Second, making Ruby functions accessible from Sass introduces the temptation
  # to do things like database access within stylesheets.
  # This is generally a bad idea;
  # since Sass files are by default only compiled once,
  # dynamic code is not a great fit.
  #
  # If you really, really need to compile Sass on each request,
  # first make sure you have adequate caching set up.
  # Then you can use {Sass::Engine} to render the code,
  # using the {file:SASS_REFERENCE.md#custom-option `options` parameter}
  # to pass in data that {EvaluationContext#options can be accessed}
  # from your Sass functions.
  #
  # Within one of the functions in this module,
  # methods of {EvaluationContext} can be used.
  #
  # ### Caveats
  #
  # When creating new {Literal} objects within functions,
  # be aware that it's not safe to call {Literal#to_s #to_s}
  # (or other methods that use the string representation)
  # on those objects without first setting {Node#options= the #options attribute}.
  module Functions
    @signatures = {}

    # A class representing a Sass function signature.
    #
    # @attr args [Array<Symbol>] The names of the arguments to the function.
    # @attr var_args [Boolean] Whether the function takes a variable number of arguments.
    # @attr var_kwargs [Boolean] Whether the function takes an arbitrary set of keyword arguments.
    Signature = Struct.new(:args, :var_args, :var_kwargs)

    # Declare a Sass signature for a Ruby-defined function.
    # This includes the names of the arguments,
    # whether the function takes a variable number of arguments,
    # and whether the function takes an arbitrary set of keyword arguments.
    #
    # It's not necessary to declare a signature for a function.
    # However, without a signature it won't support keyword arguments.
    #
    # A single function can have multiple signatures declared
    # as long as each one takes a different number of arguments.
    # It's also possible to declare multiple signatures
    # that all take the same number of arguments,
    # but none of them but the first will be used
    # unless the user uses keyword arguments.
    #
    # @example
    #   declare :rgba, [:hex, :alpha]
    #   declare :rgba, [:red, :green, :blue, :alpha]
    #   declare :accepts_anything, [], :var_args => true, :var_kwargs => true
    #   declare :some_func, [:foo, :bar, :baz], :var_kwargs => true
    #
    # @param method_name [Symbol] The name of the method
    #   whose signature is being declared.
    # @param args [Array<Symbol>] The names of the arguments for the function signature.
    # @option options :var_args [Boolean] (false)
    #   Whether the function accepts a variable number of (unnamed) arguments
    #   in addition to the named arguments.
    # @option options :var_kwargs [Boolean] (false)
    #   Whether the function accepts other keyword arguments
    #   in addition to those in `:args`.
    #   If this is true, the Ruby function will be passed a hash from strings
    #   to {Sass::Script::Literal}s as the last argument.
    #   In addition, if this is true and `:var_args` is not,
    #   Sass will ensure that the last argument passed is a hash.
    def self.declare(method_name, args, options = {})
      @signatures[method_name] ||= []
      @signatures[method_name] << Signature.new(
        args.map {|s| s.to_s},
        options[:var_args],
        options[:var_kwargs])
    end

    # Determine the correct signature for the number of arguments
    # passed in for a given function.
    # If no signatures match, the first signature is returned for error messaging.
    #
    # @param method_name [Symbol] The name of the Ruby function to be called.
    # @param arg_arity [Number] The number of unnamed arguments the function was passed.
    # @param kwarg_arity [Number] The number of keyword arguments the function was passed.
    #
    # @return [{Symbol => Object}, nil]
    #   The signature options for the matching signature,
    #   or nil if no signatures are declared for this function. See {declare}.
    def self.signature(method_name, arg_arity, kwarg_arity)
      return unless @signatures[method_name]
      @signatures[method_name].each do |signature|
        return signature if signature.args.size == arg_arity + kwarg_arity
        next unless signature.args.size < arg_arity + kwarg_arity

        # We have enough args.
        # Now we need to figure out which args are varargs
        # and if the signature allows them.
        t_arg_arity, t_kwarg_arity = arg_arity, kwarg_arity
        if signature.args.size > t_arg_arity
          # we transfer some kwargs arity to args arity
          # if it does not have enough args -- assuming the names will work out.
          t_kwarg_arity -= (signature.args.size - t_arg_arity)
          t_arg_arity = signature.args.size
        end

        if (  t_arg_arity == signature.args.size ||   t_arg_arity > signature.args.size && signature.var_args  ) &&
           (t_kwarg_arity == 0                   || t_kwarg_arity > 0                   && signature.var_kwargs)
          return signature
        end
      end
      @signatures[method_name].first
    end

    # The context in which methods in {Script::Functions} are evaluated.
    # That means that all instance methods of {EvaluationContext}
    # are available to use in functions.
    class EvaluationContext
      include Functions

      # The options hash for the {Sass::Engine} that is processing the function call
      #
      # @return [{Symbol => Object}]
      attr_reader :options

      # @param options [{Symbol => Object}] See \{#options}
      def initialize(options)
        @options = options
      end

      # Asserts that the type of a given SassScript value
      # is the expected type (designated by a symbol).
      #
      # Valid types are `:Bool`, `:Color`, `:Number`, and `:String`.
      # Note that `:String` will match both double-quoted strings
      # and unquoted identifiers.
      #
      # @example
      #   assert_type value, :String
      #   assert_type value, :Number
      # @param value [Sass::Script::Literal] A SassScript value
      # @param type [Symbol] The name of the type the value is expected to be
      # @param name [String, Symbol, nil] The name of the argument.
      def assert_type(value, type, name = nil)
        return if value.is_a?(Sass::Script.const_get(type))
        err = "#{value.inspect} is not a #{type.to_s.downcase}"
        err = "$#{name.to_s.gsub('_', '-')}: " + err if name
        raise ArgumentError.new(err)
      end
    end

    class << self
      # Returns whether user function with a given name exists.
      #
      # @param function_name [String]
      # @return [Boolean]
      alias_method :callable?, :public_method_defined?

      private
      def include(*args)
        r = super
        # We have to re-include ourselves into EvaluationContext to work around
        # an icky Ruby restriction.
        EvaluationContext.send :include, self
        r
      end
    end

    # Creates a {Color} object from red, green, and blue values.
    #
    # @see #rgba
    # @overload rgb($red, $green, $blue)
    # @param $red [Number] The amount of red in the color. Must be between 0 and
    #   255 inclusive, or between `0%` and `100%` inclusive
    # @param $green [Number] The amount of green in the color. Must be between 0
    #   and 255 inclusive, or between `0%` and `100%` inclusive
    # @param $blue [Number] The amount of blue in the color. Must be between 0
    #   and 255 inclusive, or between `0%` and `100%` inclusive
    # @return [Color]
    # @raise [ArgumentError] if any parameter is the wrong type or out of bounds
    def rgb(red, green, blue)
      assert_type red, :Number, :red
      assert_type green, :Number, :green
      assert_type blue, :Number, :blue

      Color.new([[red, :red], [green, :green], [blue, :blue]].map do |(c, name)|
          v = c.value
          if c.numerator_units == ["%"] && c.denominator_units.empty?
            v = Sass::Util.check_range("$#{name}: Color value", 0..100, c, '%')
            v * 255 / 100.0
          else
            Sass::Util.check_range("$#{name}: Color value", 0..255, c)
          end
        end)
    end
    declare :rgb, [:red, :green, :blue]

    # Creates a {Color} from red, green, blue, and alpha values.
    # @see #rgb
    #
    # @overload rgba($red, $green, $blue, $alpha)
    #   @param $red [Number] The amount of red in the color. Must be between 0
    #     and 255 inclusive
    #   @param $green [Number] The amount of green in the color. Must be between
    #     0 and 255 inclusive
    #   @param $blue [Number] The amount of blue in the color. Must be between 0
    #     and 255 inclusive
    #   @param $alpha [Number] The opacity of the color. Must be between 0 and 1
    #     inclusive
    #   @return [Color]
    #   @raise [ArgumentError] if any parameter is the wrong type or out of
    #     bounds
    #
    # @overload rgba($color, $alpha)
    #   Sets the opacity of an existing color.
    #
    #   @example
    #     rgba(#102030, 0.5) => rgba(16, 32, 48, 0.5)
    #     rgba(blue, 0.2)    => rgba(0, 0, 255, 0.2)
    #
    #   @param $color [Color] The color whose opacity will be changed.
    #   @param $alpha [Number] The new opacity of the color. Must be between 0
    #     and 1 inclusive
    #   @return [Color]
    #   @raise [ArgumentError] if `$alpha` is out of bounds or either parameter
    #     is the wrong type
    def rgba(*args)
      case args.size
      when 2
        color, alpha = args

        assert_type color, :Color, :color
        assert_type alpha, :Number, :alpha

        Sass::Util.check_range('Alpha channel', 0..1, alpha)
        color.with(:alpha => alpha.value)
      when 4
        red, green, blue, alpha = args
        rgba(rgb(red, green, blue), alpha)
      else
        raise ArgumentError.new("wrong number of arguments (#{args.size} for 4)")
      end
    end
    declare :rgba, [:red, :green, :blue, :alpha]
    declare :rgba, [:color, :alpha]

    # Creates a {Color} from hue, saturation, and lightness values. Uses the
    # algorithm from the [CSS3 spec][].
    #
    # [CSS3 spec]: http://www.w3.org/TR/css3-color/#hsl-color
    #
    # @see #hsla
    # @overload hsl($hue, $saturation, $lightness)
    # @param $hue [Number] The hue of the color. Should be between 0 and 360
    #   degrees, inclusive
    # @param $saturation [Number] The saturation of the color. Must be between
    #   `0%` and `100%`, inclusive
    # @param $lightness [Number] The lightness of the color. Must be between
    #   `0%` and `100%`, inclusive
    # @return [Color]
    # @raise [ArgumentError] if `$saturation` or `$lightness` are out of bounds
    #   or any parameter is the wrong type
    def hsl(hue, saturation, lightness)
      hsla(hue, saturation, lightness, Number.new(1))
    end
    declare :hsl, [:hue, :saturation, :lightness]

    # Creates a {Color} from hue, saturation, lightness, and alpha
    # values. Uses the algorithm from the [CSS3 spec][].
    #
    # [CSS3 spec]: http://www.w3.org/TR/css3-color/#hsl-color
    #
    # @see #hsl
    # @overload hsla($hue, $saturation, $lightness, $alpha)
    # @param $hue [Number] The hue of the color. Should be between 0 and 360
    #   degrees, inclusive
    # @param $saturation [Number] The saturation of the color. Must be between
    #   `0%` and `100%`, inclusive
    # @param $lightness [Number] The lightness of the color. Must be between
    #   `0%` and `100%`, inclusive
    # @param $alpha [Number] The opacity of the color. Must be between 0 and 1,
    #   inclusive
    # @return [Color]
    # @raise [ArgumentError] if `$saturation`, `$lightness`, or `$alpha` are out
    #   of bounds or any parameter is the wrong type
    def hsla(hue, saturation, lightness, alpha)
      assert_type hue, :Number, :hue
      assert_type saturation, :Number, :saturation
      assert_type lightness, :Number, :lightness
      assert_type alpha, :Number, :alpha

      Sass::Util.check_range('Alpha channel', 0..1, alpha)

      h = hue.value
      s = Sass::Util.check_range('Saturation', 0..100, saturation, '%')
      l = Sass::Util.check_range('Lightness', 0..100, lightness, '%')

      Color.new(:hue => h, :saturation => s, :lightness => l, :alpha => alpha.value)
    end
    declare :hsla, [:hue, :saturation, :lightness, :alpha]

    # Gets the red component of a color. Calculated from HSL where necessary via
    # [this algorithm][hsl-to-rgb].
    #
    # [hsl-to-rgb]: http://www.w3.org/TR/css3-color/#hsl-color
    #
    # @overload red($color)
    # @param $color [Color]
    # @return [Number] The red component, between 0 and 255 inclusive
    # @raise [ArgumentError] if `$color` isn't a color
    def red(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.red)
    end
    declare :red, [:color]

    # Gets the green component of a color. Calculated from HSL where necessary
    # via [this algorithm][hsl-to-rgb].
    #
    # [hsl-to-rgb]: http://www.w3.org/TR/css3-color/#hsl-color
    #
    # @overload green($color)
    # @param $color [Color]
    # @return [Number] The green component, between 0 and 255 inclusive
    # @raise [ArgumentError] if `$color` isn't a color
    def green(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.green)
    end
    declare :green, [:color]

    # Gets the blue component of a color. Calculated from HSL where necessary
    # via [this algorithm][hsl-to-rgb].
    #
    # [hsl-to-rgb]: http://www.w3.org/TR/css3-color/#hsl-color
    #
    # @overload blue($color)
    # @param $color [Color]
    # @return [Number] The blue component, between 0 and 255 inclusive
    # @raise [ArgumentError] if `$color` isn't a color
    def blue(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.blue)
    end
    declare :blue, [:color]

    # Returns the hue component of a color. See [the CSS3 HSL
    # specification][hsl]. Calculated from RGB where necessary via [this
    # algorithm][rgb-to-hsl].
    #
    # [hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    # [rgb-to-hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    #
    # @overload hue($color)
    # @param $color [Color]
    # @return [Number] The hue component, between 0deg and 360deg
    # @raise [ArgumentError] if `$color` isn't a color
    def hue(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.hue, ["deg"])
    end
    declare :hue, [:color]

    # Returns the saturation component of a color. See [the CSS3 HSL
    # specification][hsl]. Calculated from RGB where necessary via [this
    # algorithm][rgb-to-hsl].
    #
    # [hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    # [rgb-to-hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    #
    # @overload saturation($color)
    # @param $color [Color]
    # @return [Number] The saturation component, between 0% and 100%
    # @raise [ArgumentError] if `$color` isn't a color
    def saturation(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.saturation, ["%"])
    end
    declare :saturation, [:color]

    # Returns the lightness component of a color. See [the CSS3 HSL
    # specification][hsl]. Calculated from RGB where necessary via [this
    # algorithm][rgb-to-hsl].
    #
    # [hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    # [rgb-to-hsl]: http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
    #
    # @overload lightness($color)
    # @param $color [Color]
    # @return [Number] The lightness component, between 0% and 100%
    # @raise [ArgumentError] if `$color` isn't a color
    def lightness(color)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.lightness, ["%"])
    end
    declare :lightness, [:color]

    # Returns the alpha component (opacity) of a color. This is 1 unless
    # otherwise specified.
    #
    # This function also supports the proprietary Microsoft `alpha(opacity=20)`
    # syntax as a special case.
    #
    # @overload alpha($color)
    # @param $color [Color]
    # @return [Number] The alpha component, between 0 and 1
    # @raise [ArgumentError] if `$color` isn't a color
    def alpha(*args)
      if args.all? do |a|
          a.is_a?(Sass::Script::String) && a.type == :identifier &&
            a.value =~ /^[a-zA-Z]+\s*=/
        end
        # Support the proprietary MS alpha() function
        return Sass::Script::String.new("alpha(#{args.map {|a| a.to_s}.join(", ")})")
      end

      raise ArgumentError.new("wrong number of arguments (#{args.size} for 1)") if args.size != 1

      assert_type args.first, :Color, :color
      Sass::Script::Number.new(args.first.alpha)
    end
    declare :alpha, [:color]

    # Returns the alpha component (opacity) of a color. This is 1 unless
    # otherwise specified.
    #
    # @overload opacity($color)
    # @param $color [Color]
    # @return [Number] The alpha component, between 0 and 1
    # @raise [ArgumentError] if `$color` isn't a color
    def opacity(color)
      return Sass::Script::String.new("opacity(#{color})") if color.is_a?(Sass::Script::Number)
      assert_type color, :Color, :color
      Sass::Script::Number.new(color.alpha)
    end
    declare :opacity, [:color]

    # Makes a color more opaque. Takes a color and a number between 0 and 1, and
    # returns a color with the opacity increased by that amount.
    #
    # @see #transparentize
    # @example
    #   opacify(rgba(0, 0, 0, 0.5), 0.1) => rgba(0, 0, 0, 0.6)
    #   opacify(rgba(0, 0, 17, 0.8), 0.2) => #001
    # @overload opacify($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to increase the opacity by, between 0
    #   and 1
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def opacify(color, amount)
      _adjust(color, amount, :alpha, 0..1, :+)
    end
    declare :opacify, [:color, :amount]

    alias_method :fade_in, :opacify
    declare :fade_in, [:color, :amount]

    # Makes a color more transparent. Takes a color and a number between 0 and
    # 1, and returns a color with the opacity decreased by that amount.
    #
    # @see #opacify
    # @example
    #   transparentize(rgba(0, 0, 0, 0.5), 0.1) => rgba(0, 0, 0, 0.4)
    #   transparentize(rgba(0, 0, 0, 0.8), 0.2) => rgba(0, 0, 0, 0.6)
    # @overload transparentize($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to decrease the opacity by, between 0
    #   and 1
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def transparentize(color, amount)
      _adjust(color, amount, :alpha, 0..1, :-)
    end
    declare :transparentize, [:color, :amount]

    alias_method :fade_out, :transparentize
    declare :fade_out, [:color, :amount]

    # Makes a color lighter. Takes a color and a number between `0%` and `100%`,
    # and returns a color with the lightness increased by that amount.
    #
    # @see #darken
    # @example
    #   lighten(hsl(0, 0%, 0%), 30%) => hsl(0, 0, 30)
    #   lighten(#800, 20%) => #e00
    # @overload lighten($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to increase the lightness by, between
    #   `0%` and `100%`
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def lighten(color, amount)
      _adjust(color, amount, :lightness, 0..100, :+, "%")
    end
    declare :lighten, [:color, :amount]

    # Makes a color darker. Takes a color and a number between 0% and 100%, and
    # returns a color with the lightness decreased by that amount.
    #
    # @see #lighten
    # @example
    #   darken(hsl(25, 100%, 80%), 30%) => hsl(25, 100%, 50%)
    #   darken(#800, 20%) => #200
    # @overload darken($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to dencrease the lightness by, between
    #   `0%` and `100%`
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def darken(color, amount)
      _adjust(color, amount, :lightness, 0..100, :-, "%")
    end
    declare :darken, [:color, :amount]

    # Makes a color more saturated. Takes a color and a number between 0% and
    # 100%, and returns a color with the saturation increased by that amount.
    #
    # @see #desaturate
    # @example
    #   saturate(hsl(120, 30%, 90%), 20%) => hsl(120, 50%, 90%)
    #   saturate(#855, 20%) => #9e3f3f
    # @overload saturate($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to increase the saturation by, between
    #   `0%` and `100%`
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def saturate(color, amount = nil)
      # Support the filter effects definition of saturate.
      # https://dvcs.w3.org/hg/FXTF/raw-file/tip/filters/index.html
      return Sass::Script::String.new("saturate(#{color})") if amount.nil?
      _adjust(color, amount, :saturation, 0..100, :+, "%")
    end
    declare :saturate, [:color, :amount]
    declare :saturate, [:amount]

    # Makes a color less saturated. Takes a color and a number between 0% and
    # 100%, and returns a color with the saturation decreased by that value.
    #
    # @see #saturate
    # @example
    #   desaturate(hsl(120, 30%, 90%), 20%) => hsl(120, 10%, 90%)
    #   desaturate(#855, 20%) => #726b6b
    # @overload desaturate($color, $amount)
    # @param $color [Color]
    # @param $amount [Number] The amount to decrease the saturation by, between
    #   `0%` and `100%`
    # @return [Color]
    # @raise [ArgumentError] if `$amount` is out of bounds, or either parameter
    #   is the wrong type
    def desaturate(color, amount)
      _adjust(color, amount, :saturation, 0..100, :-, "%")
    end
    declare :desaturate, [:color, :amount]

    # Changes the hue of a color. Takes a color and a number of degrees (usually
    # between `-360deg` and `360deg`), and returns a color with the hue rotated
    # along the color wheel by that amount.
    #
    # @example
    #   adjust-hue(hsl(120, 30%, 90%), 60deg) => hsl(180, 30%, 90%)
    #   adjust-hue(hsl(120, 30%, 90%), 060deg) => hsl(60, 30%, 90%)
    #   adjust-hue(#811, 45deg) => #886a11
    # @overload adjust_hue($color, $degrees)
    # @param $color [Color]
    # @param $degrees [Number] The number of degrees to rotate the hue
    # @return [Color]
    # @raise [ArgumentError] if either parameter is the wrong type
    def adjust_hue(color, degrees)
      assert_type color, :Color, :color
      assert_type degrees, :Number, :degrees
      color.with(:hue => color.hue + degrees.value)
    end
    declare :adjust_hue, [:color, :degrees]

    # Converts a color into the format understood by IE filters.
    #
    # @example
    #   ie-hex-str(#abc) => #FFAABBCC
    #   ie-hex-str(#3322BB) => #FF3322BB
    #   ie-hex-str(rgba(0, 255, 0, 0.5)) => #8000FF00
    # @overload ie_hex_str($color)
    # @param $color [Color]
    # @return [String] The IE-formatted string representation of the color
    # @raise [ArgumentError] if `$color` isn't a color
    def ie_hex_str(color)
      assert_type color, :Color, :color
      alpha = (color.alpha * 255).round.to_s(16).rjust(2, '0')
      Sass::Script::String.new("##{alpha}#{color.send(:hex_str)[1..-1]}".upcase)
    end
    declare :ie_hex_str, [:color]

    # Increases or decreases one or more properties of a color. This can change
    # the red, green, blue, hue, saturation, value, and alpha properties. The
    # properties are specified as keyword arguments, and are added to or
    # subtracted from the color's current value for that property.
    #
    # All properties are optional. You can't specify both RGB properties
    # (`$red`, `$green`, `$blue`) and HSL properties (`$hue`, `$saturation`,
    # `$value`) at the same time.
    #
    # @example
    #   adjust-color(#102030, $blue: 5) => #102035
    #   adjust-color(#102030, $red: -5, $blue: 5) => #0b2035
    #   adjust-color(hsl(25, 100%, 80%), $lightness: -30%, $alpha: -0.4) => hsla(25, 100%, 50%, 0.6)
    # @overload adjust_color($color, [$red], [$green], [$blue], [$hue], [$saturation], [$lightness], [$alpha])
    # @param $color [Color]
    # @param $red [Number] The adjustment to make on the red component, between
    #   -255 and 255 inclusive
    # @param $green [Number] The adjustment to make on the green component,
    #   between -255 and 255 inclusive
    # @param $blue [Number] The adjustment to make on the blue component, between
    #   -255 and 255 inclusive
    # @param $hue [Number] The adjustment to make on the hue component, in
    #   degrees
    # @param $saturation [Number] The adjustment to make on the saturation
    #   component, between `-100%` and `100%` inclusive
    # @param $lightness [Number] The adjustment to make on the lightness
    #   component, between `-100%` and `100%` inclusive
    # @param $alpha [Number] The adjustment to make on the alpha component,
    #   between -1 and 1 inclusive
    # @return [Color]
    # @raise [ArgumentError] if any parameter is the wrong type or out-of
    #   bounds, or if RGB properties and HSL properties are adjusted at the
    #   same time
    def adjust_color(color, kwargs)
      assert_type color, :Color, :color
      with = Sass::Util.map_hash({
          "red" => [-255..255, ""],
          "green" => [-255..255, ""],
          "blue" => [-255..255, ""],
          "hue" => nil,
          "saturation" => [-100..100, "%"],
          "lightness" => [-100..100, "%"],
          "alpha" => [-1..1, ""]
        }) do |name, (range, units)|

        next unless val = kwargs.delete(name)
        assert_type val, :Number, name
        Sass::Util.check_range("$#{name}: Amount", range, val, units) if range
        adjusted = color.send(name) + val.value
        adjusted = [0, Sass::Util.restrict(adjusted, range)].max if range
        [name.to_sym, adjusted]
      end

      unless kwargs.empty?
        name, val = kwargs.to_a.first
        raise ArgumentError.new("Unknown argument $#{name} (#{val})")
      end

      color.with(with)
    end
    declare :adjust_color, [:color], :var_kwargs => true

    # Fluidly scales one or more properties of a color. Unlike
    # \{#adjust_color adjust-color}, which changes a color's properties by fixed
    # amounts, \{#scale_color scale-color} fluidly changes them based on how
    # high or low they already are. That means that lightening an already-light
    # color with \{#scale_color scale-color} won't change the lightness much,
    # but lightening a dark color by the same amount will change it more
    # dramatically. This has the benefit of making `scale-color($color, ...)`
    # have a similar effect regardless of what `$color` is.
    #
    # For example, the lightness of a color can be anywhere between `0%` and
    # `100%`. If `scale-color($color, $lightness: 40%)` is called, the resulting
    # color's lightness will be 40% of the way between its original lightness
    # and 100. If `scale-color($color, $lightness: -40%)` is called instead, the
    # lightness will be 40% of the way between the original and 0.
    #
    # This can change the red, green, blue, saturation, value, and alpha
    # properties. The properties are specified as keyword arguments. All
    # arguments should be percentages between `0%` and `100%`.
    #
    # All properties are optional. You can't specify both RGB properties
    # (`$red`, `$green`, `$blue`) and HSL properties (`$saturation`, `$value`)
    # at the same time.
    #
    # @example
    #   scale-color(hsl(120, 70%, 80%), $lightness: 50%) => hsl(120, 70%, 90%)
    #   scale-color(rgb(200, 150%, 170%), $green: -40%, $blue: 70%) => rgb(200, 90, 229)
    #   scale-color(hsl(200, 70%, 80%), $saturation: -90%, $alpha: -30%) => hsla(200, 7%, 80%, 0.7)
    # @overload scale_color($color, [$red], [$green], [$blue], [$saturation], [$lightness], [$alpha])
    # @param $color [Color]
    # @param $red [Number]
    # @param $green [Number]
    # @param $blue [Number]
    # @param $saturation [Number]
    # @param $lightness [Number]
    # @param $alpha [Number]
    # @return [Color]
    # @raise [ArgumentError] if any parameter is the wrong type or out-of
    #   bounds, or if RGB properties and HSL properties are adjusted at the
    #   same time
    def scale_color(color, kwargs)
      assert_type color, :Color, :color
      with = Sass::Util.map_hash({
          "red" => 255,
          "green" => 255,
          "blue" => 255,
          "saturation" => 100,
          "lightness" => 100,
          "alpha" => 1
        }) do |name, max|

        next unless val = kwargs.delete(name)
        assert_type val, :Number, name
        if !(val.numerator_units == ['%'] && val.denominator_units.empty?)
          raise ArgumentError.new("$#{name}: Amount #{val} must be a % (e.g. #{val.value}%)")
        else
          Sass::Util.check_range("$#{name}: Amount", -100..100, val, '%')
        end

        current = color.send(name)
        scale = val.value/100.0
        diff = scale > 0 ? max - current : current
        [name.to_sym, current + diff*scale]
      end

      unless kwargs.empty?
        name, val = kwargs.to_a.first
        raise ArgumentError.new("Unknown argument $#{name} (#{val})")
      end

      color.with(with)
    end
    declare :scale_color, [:color], :var_kwargs => true

    # Changes one or more properties of a color. This can change the red, green,
    # blue, hue, saturation, value, and alpha properties. The properties are
    # specified as keyword arguments, and replace the color's current value for
    # that property.
    #
    # All properties are optional. You can't specify both RGB properties
    # (`$red`, `$green`, `$blue`) and HSL properties (`$hue`, `$saturation`,
    # `$value`) at the same time.
    #
    # @example
    #   change-color(#102030, $blue: 5) => #102005
    #   change-color(#102030, $red: 120, $blue: 5) => #782005
    #   change-color(hsl(25, 100%, 80%), $lightness: 40%, $alpha: 0.8) => hsla(25, 100%, 40%, 0.8)
    # @overload change_color($color, [$red], [$green], [$blue], [$hue], [$saturation], [$lightness], [$alpha])
    # @param $color [Color]
    # @param $red [Number] The new red component for the color, within 0 and 255
    #   inclusive
    # @param $green [Number] The new green component for the color, within 0 and
    #   255 inclusive
    # @param $blue [Number] The new blue component for the color, within 0 and
    #   255 inclusive
    # @param $hue [Number] The new hue component for the color, in degrees
    # @param $saturation [Number] The new saturation component for the color,
    #   between `0%` and `100%` inclusive
    # @param $lightness [Number] The new lightness component for the color,
    #   within `0%` and `100%` inclusive
    # @param $alpha [Number] The new alpha component for the color, within 0 and
    #   1 inclusive
    # @return [Color]
    # @raise [ArgumentError] if any parameter is the wrong type or out-of
    #   bounds, or if RGB properties and HSL properties are adjusted at the
    #   same time
    def change_color(color, kwargs)
      assert_type color, :Color, :color
      with = Sass::Util.map_hash(%w[red green blue hue saturation lightness alpha]) do |name, max|
        next unless val = kwargs.delete(name)
        assert_type val, :Number, name
        [name.to_sym, val.value]
      end

      unless kwargs.empty?
        name, val = kwargs.to_a.first
        raise ArgumentError.new("Unknown argument $#{name} (#{val})")
      end

      color.with(with)
    end
    declare :change_color, [:color], :var_kwargs => true

    # Mixes two colors together. Specifically, takes the average of each of the
    # RGB components, optionally weighted by the given percentage. The opacity
    # of the colors is also considered when weighting the components.
    #
    # The weight specifies the amount of the first color that should be included
    # in the returned color. The default, `50%`, means that half the first color
    # and half the second color should be used. `25%` means that a quarter of
    # the first color and three quarters of the second color should be used.
    #
    # @example
    #   mix(#f00, #00f) => #7f007f
    #   mix(#f00, #00f, 25%) => #3f00bf
    #   mix(rgba(255, 0, 0, 0.5), #00f) => rgba(63, 0, 191, 0.75)
    # @overload mix($color-1, $color-2, $weight: 50%)
    # @param $color-1 [Color]
    # @param $color-2 [Color]
    # @param $weight [Number] The relative weight of each color. Closer to `0%`
    #   gives more weight to `$color`, closer to `100%` gives more weight to
    #   `$color2`
    # @return [Color]
    # @raise [ArgumentError] if `$weight` is out of bounds or any parameter is
    #   the wrong type
    def mix(color_1, color_2, weight = Number.new(50))
      assert_type color_1, :Color, :color_1
      assert_type color_2, :Color, :color_2
      assert_type weight, :Number, :weight

      Sass::Util.check_range("Weight", 0..100, weight, '%')

      # This algorithm factors in both the user-provided weight (w) and the
      # difference between the alpha values of the two colors (a) to decide how
      # to perform the weighted average of the two RGB values.
      #
      # It works by first normalizing both parameters to be within [-1, 1],
      # where 1 indicates "only use color_1", -1 indicates "only use color_2", and
      # all values in between indicated a proportionately weighted average.
      #
      # Once we have the normalized variables w and a, we apply the formula
      # (w + a)/(1 + w*a) to get the combined weight (in [-1, 1]) of color_1.
      # This formula has two especially nice properties:
      #
      #   * When either w or a are -1 or 1, the combined weight is also that number
      #     (cases where w * a == -1 are undefined, and handled as a special case).
      #
      #   * When a is 0, the combined weight is w, and vice versa.
      #
      # Finally, the weight of color_1 is renormalized to be within [0, 1]
      # and the weight of color_2 is given by 1 minus the weight of color_1.
      p = (weight.value/100.0).to_f
      w = p*2 - 1
      a = color_1.alpha - color_2.alpha

      w1 = (((w * a == -1) ? w : (w + a)/(1 + w*a)) + 1)/2.0
      w2 = 1 - w1

      rgb = color_1.rgb.zip(color_2.rgb).map {|v1, v2| v1*w1 + v2*w2}
      alpha = color_1.alpha*p + color_2.alpha*(1-p)
      Color.new(rgb + [alpha])
    end
    declare :mix, [:color_1, :color_2]
    declare :mix, [:color_1, :color_2, :weight]

    # Converts a color to grayscale. This is identical to `desaturate(color,
    # 100%)`.
    #
    # @see #desaturate
    # @overload grayscale($color)
    # @param $color [Color]
    # @return [Color]
    # @raise [ArgumentError] if `$color` isn't a color
    def grayscale(color)
      return Sass::Script::String.new("grayscale(#{color})") if color.is_a?(Sass::Script::Number)
      desaturate color, Number.new(100)
    end
    declare :grayscale, [:color]

    # Returns the complement of a color. This is identical to `adjust-hue(color,
    # 180deg)`.
    #
    # @see #adjust_hue #adjust-hue
    # @overload complement($color)
    # @param $color [Color]
    # @return [Color]
    # @raise [ArgumentError] if `$color` isn't a color
    def complement(color)
      adjust_hue color, Number.new(180)
    end
    declare :complement, [:color]

    # Returns the inverse (negative) of a color. The red, green, and blue values
    # are inverted, while the opacity is left alone.
    #
    # @overload invert($color)
    # @param $color [Color]
    # @return [Color]
    # @raise [ArgumentError] if `$color` isn't a color
    def invert(color)
      return Sass::Script::String.new("invert(#{color})") if color.is_a?(Sass::Script::Number)

      assert_type color, :Color, :color
      color.with(
        :red => (255 - color.red),
        :green => (255 - color.green),
        :blue => (255 - color.blue))
    end
    declare :invert, [:color]

    # Removes quotes from a string. If the string is already unquoted, this will
    # return it unmodified.
    #
    # @see #quote
    # @example
    #   unquote("foo") => foo
    #   unquote(foo) => foo
    # @overload unquote($string)
    # @param $string [String]
    # @return [String]
    # @raise [ArgumentError] if `$string` isn't a string
    def unquote(string)
      if string.is_a?(Sass::Script::String)
        Sass::Script::String.new(string.value, :identifier)
      else
        string
      end
    end
    declare :unquote, [:string]

    # Add quotes to a string if the string isn't quoted,
    # or returns the same string if it is.
    #
    # @see #unquote
    # @example
    #   quote("foo") => "foo"
    #   quote(foo) => "foo"
    # @overload quote($string)
    # @param $string [String]
    # @return [String]
    # @raise [ArgumentError] if `$string` isn't a string
    def quote(string)
      assert_type string, :String, :string
      Sass::Script::String.new(string.value, :string)
    end
    declare :quote, [:string]

    # Returns the type of a value.
    #
    # @example
    #   type-of(100px)  => number
    #   type-of(asdf)   => string
    #   type-of("asdf") => string
    #   type-of(true)   => bool
    #   type-of(#fff)   => color
    #   type-of(blue)   => color
    # @overload type_of($value)
    # @param $value [Literal] The value to inspect
    # @return [String] The unquoted string name of the value's type
    def type_of(value)
      Sass::Script::String.new(value.class.name.gsub(/Sass::Script::/,'').downcase)
    end
    declare :type_of, [:value]

    # Returns the unit(s) associated with a number. Complex units are sorted in
    # alphabetical order by numerator and denominator.
    #
    # @example
    #   unit(100) => ""
    #   unit(100px) => "px"
    #   unit(3em) => "em"
    #   unit(10px * 5em) => "em*px"
    #   unit(10px * 5em / 30cm / 1rem) => "em*px/cm*rem"
    # @overload unit($number)
    # @param $number [Number]
    # @return [String] The unit(s) of the number, as a quoted string
    # @raise [ArgumentError] if `$number` isn't a number
    def unit(number)
      assert_type number, :Number, :number
      Sass::Script::String.new(number.unit_str, :string)
    end
    declare :unit, [:number]

    # Returns whether a number has units.
    #
    # @example
    #   unitless(100) => true
    #   unitless(100px) => false
    # @overload unitless($number)
    # @param $number [Number]
    # @return [Bool]
    # @raise [ArgumentError] if `$number` isn't a number
    def unitless(number)
      assert_type number, :Number, :number
      Sass::Script::Bool.new(number.unitless?)
    end
    declare :unitless, [:number]

    # Returns whether two numbers can added, subtracted, or compared.
    #
    # @example
    #   comparable(2px, 1px) => true
    #   comparable(100px, 3em) => false
    #   comparable(10cm, 3mm) => true
    # @overload comparable($number-1, $number-2)
    # @param $number-1 [Number]
    # @param $number-2 [Number]
    # @return [Bool]
    # @raise [ArgumentError] if either parameter is the wrong type
    def comparable(number_1, number_2)
      assert_type number_1, :Number, :number_1
      assert_type number_2, :Number, :number_2
      Sass::Script::Bool.new(number_1.comparable_to?(number_2))
    end
    declare :comparable, [:number_1, :number_2]

    # Converts a unitless number to a percentage.
    #
    # @example
    #   percentage(0.2) => 20%
    #   percentage(100px / 50px) => 200%
    # @overload percentage($value)
    # @param $value [Number]
    # @return [Number]
    # @raise [ArgumentError] if `$value` isn't a unitless number
    def percentage(value)
      unless value.is_a?(Sass::Script::Number) && value.unitless?
        raise ArgumentError.new("$value: #{value.inspect} is not a unitless number")
      end
      Sass::Script::Number.new(value.value * 100, ['%'])
    end
    declare :percentage, [:value]

    # Rounds a number to the nearest whole number.
    #
    # @example
    #   round(10.4px) => 10px
    #   round(10.6px) => 11px
    # @overload round($value)
    # @param $value [Number]
    # @return [Number]
    # @raise [ArgumentError] if `$value` isn't a number
    def round(value)
      numeric_transformation(value) {|n| n.round}
    end
    declare :round, [:value]

    # Rounds a number up to the next whole number.
    #
    # @example
    #   ceil(10.4px) => 11px
    #   ceil(10.6px) => 11px
    # @overload ceil($value)
    # @param $value [Number]
    # @return [Number]
    # @raise [ArgumentError] if `$value` isn't a number
    def ceil(value)
      numeric_transformation(value) {|n| n.ceil}
    end
    declare :ceil, [:value]

    # Rounds a number down to the previous whole number.
    #
    # @example
    #   floor(10.4px) => 10px
    #   floor(10.6px) => 10px
    # @overload floor($value)
    # @param $value [Number]
    # @return [Number]
    # @raise [ArgumentError] if `$value` isn't a number
    def floor(value)
      numeric_transformation(value) {|n| n.floor}
    end
    declare :floor, [:value]

    # Returns the absolute value of a number.
    #
    # @example
    #   abs(10px) => 10px
    #   abs(-10px) => 10px
    # @overload abs($value)
    # @param $value [Number]
    # @return [Number]
    # @raise [ArgumentError] if `$value` isn't a number
    def abs(value)
      numeric_transformation(value) {|n| n.abs}
    end
    declare :abs, [:value]

    # Finds the minimum of several numbers. This function takes any number of
    # arguments.
    #
    # @example
    #   min(1px, 4px) => 1px
    #   min(5em, 3em, 4em) => 3em
    # @overload min($numbers...)
    # @param $numbers [[Number]]
    # @return [Number]
    # @raise [ArgumentError] if any argument isn't a number, or if not all of
    #   the arguments have comparable units
    def min(*numbers)
      numbers.each {|n| assert_type n, :Number}
      numbers.inject {|min, num| min.lt(num).to_bool ? min : num}
    end
    declare :min, [], :var_args => :true

    # Finds the maximum of several numbers. This function takes any number of
    # arguments.
    #
    # @example
    #   max(1px, 4px) => 4px
    #   max(5em, 3em, 4em) => 5em
    # @overload max($numbers...)
    # @param $numbers [[Number]]
    # @return [Number]
    # @raise [ArgumentError] if any argument isn't a number, or if not all of
    #   the arguments have comparable units
    def max(*values)
      values.each {|v| assert_type v, :Number}
      values.inject {|max, val| max.gt(val).to_bool ? max : val}
    end
    declare :max, [], :var_args => :true

    # Return the length of a list.
    #
    # @example
    #   length(10px) => 1
    #   length(10px 20px 30px) => 3
    # @overload length($list)
    # @param $list [Literal]
    # @return [Number]
    def length(list)
      Sass::Script::Number.new(list.to_a.size)
    end
    declare :length, [:list]

    # Gets the nth item in a list.
    #
    # Note that unlike some languages, the first item in a Sass list is number
    # 1, the second number 2, and so forth.
    #
    # @example
    #   nth(10px 20px 30px, 1) => 10px
    #   nth((Helvetica, Arial, sans-serif), 3) => sans-serif
    # @overload nth($list, $n)
    # @param $list [Literal]
    # @param $n [Number] The index of the item to get
    # @return [Literal]
    # @raise [ArgumentError] if `$n` isn't an integer between 1 and the length
    #   of `$list`
    def nth(list, n)
      assert_type n, :Number, :n
      if !n.int?
        raise ArgumentError.new("List index #{n} must be an integer")
      elsif n.to_i < 1
        raise ArgumentError.new("List index #{n} must be greater than or equal to 1")
      elsif list.to_a.size == 0
        raise ArgumentError.new("List index is #{n} but list has no items")
      elsif n.to_i > (size = list.to_a.size)
        raise ArgumentError.new("List index is #{n} but list is only #{size} item#{'s' if size != 1} long")
      end

      list.to_a[n.to_i - 1]
    end
    declare :nth, [:list, :n]

    # Joins together two lists into one.
    #
    # Unless `$separator` is passed, if one list is comma-separated and one is
    # space-separated, the first parameter's separator is used for the resulting
    # list. If both lists have fewer than two items, spaces are used for the
    # resulting list.
    #
    # @example
    #   join(10px 20px, 30px 40px) => 10px 20px 30px 40px
    #   join((blue, red), (#abc, #def)) => blue, red, #abc, #def
    #   join(10px, 20px) => 10px 20px
    #   join(10px, 20px, comma) => 10px, 20px
    #   join((blue, red), (#abc, #def), space) => blue red #abc #def
    # @overload join($list1, $list2, $separator: auto)
    # @param $list1 [Literal]
    # @param $list2 [Literal]
    # @param $separator [String] The list separator to use. If this is `comma`
    #   or `space`, that separator will be used. If this is `auto` (the
    #   default), the separator is determined as explained above.
    # @return [List]
    def join(list1, list2, separator = Sass::Script::String.new("auto"))
      assert_type separator, :String, :separator
      unless %w[auto space comma].include?(separator.value)
        raise ArgumentError.new("Separator name must be space, comma, or auto")
      end
      sep1 = list1.separator if list1.is_a?(Sass::Script::List) && !list1.value.empty?
      sep2 = list2.separator if list2.is_a?(Sass::Script::List) && !list2.value.empty?
      Sass::Script::List.new(
        list1.to_a + list2.to_a,
        if separator.value == 'auto'
          sep1 || sep2 || :space
        else
          separator.value.to_sym
        end)
    end
    declare :join, [:list1, :list2]
    declare :join, [:list1, :list2, :separator]

    # Appends a single value onto the end of a list.
    #
    # Unless the `$separator` argument is passed, if the list had only one item,
    # the resulting list will be space-separated.
    #
    # @example
    #   append(10px 20px, 30px) => 10px 20px 30px
    #   append((blue, red), green) => blue, red, green
    #   append(10px 20px, 30px 40px) => 10px 20px (30px 40px)
    #   append(10px, 20px, comma) => 10px, 20px
    #   append((blue, red), green, space) => blue red green
    # @overload append($list, $val, $separator: auto)
    # @param $list [Literal]
    # @param $val [Literal]
    # @param $separator [String] The list separator to use. If this is `comma`
    #   or `space`, that separator will be used. If this is `auto` (the
    #   default), the separator is determined as explained above.
    # @return [List]
    def append(list, val, separator = Sass::Script::String.new("auto"))
      assert_type separator, :String, :separator
      unless %w[auto space comma].include?(separator.value)
        raise ArgumentError.new("Separator name must be space, comma, or auto")
      end
      sep = list.separator if list.is_a?(Sass::Script::List)
      Sass::Script::List.new(
        list.to_a + [val],
        if separator.value == 'auto'
          sep || :space
        else
          separator.value.to_sym
        end)
    end
    declare :append, [:list, :val]
    declare :append, [:list, :val, :separator]

    # Combines several lists into a single multidimensional list. The nth value
    # of the resulting list is a space separated list of the source lists' nth
    # values.
    #
    # The length of the resulting list is the length of the
    # shortest list.
    #
    # @example
    #   zip(1px 1px 3px, solid dashed solid, red green blue)
    #   => 1px solid red, 1px dashed green, 3px solid blue
    # @overload zip($lists...)
    # @param $lists [[Literal]]
    # @return [List]
    def zip(*lists)
      length = nil
      values = []
      lists.each do |list|
        array = list.to_a
        values << array.dup
        length = length.nil? ? array.length : [length, array.length].min
      end
      values.each do |value|
        value.slice!(length)
      end
      new_list_value = values.first.zip(*values[1..-1])
      List.new(new_list_value.map{|list| List.new(list, :space)}, :comma)
    end
    declare :zip, [], :var_args => true


    # Returns the position of a value within a list. If the value isn't found,
    # returns false instead.
    #
    # Note that unlike some languages, the first item in a Sass list is number
    # 1, the second number 2, and so forth.
    #
    # @example
    #   index(1px solid red, solid) => 2
    #   index(1px solid red, dashed) => false
    # @overload index($list, $value)
    # @param $list [Literal]
    # @param $value [Literal]
    # @return [Number, Bool] The 1-based index of `$value` in `$list`, or
    #   `false`
    def index(list, value)
      index = list.to_a.index {|e| e.eq(value).to_bool }
      if index
        Number.new(index + 1)
      else
        Bool.new(false)
      end
    end
    declare :index, [:list, :value]

    # Returns one of two values, depending on whether or not `$condition` is
    # true. Just like in `@if`, all values other than `false` and `null` are
    # considered to be true.
    #
    # @example
    #   if(true, 1px, 2px) => 1px
    #   if(false, 1px, 2px) => 2px
    # @overload if($condition, $if-true, $if-false)
    # @param $condition [Literal] Whether the `$if-true` or `$if-false` will be
    #   returned
    # @param $if-true [Literal]
    # @param $if-false [Literal]
    # @return [Literal] `$if-true` or `$if-false`
    def if(condition, if_true, if_false)
      if condition.to_bool
        if_true
      else
        if_false
      end
    end
    declare :if, [:condition, :if_true, :if_false]

    # This function only exists as a workaround for IE7's [`content: counter`
    # bug][bug]. It works identically to any other plain-CSS function, except it
    # avoids adding spaces between the argument commas.
    #
    # [bug]: http://jes.st/2013/ie7s-css-breaking-content-counter-bug/
    #
    # @example
    #   counter(item, ".") => counter(item,".")
    # @overload counter($args...)
    # @return [String]
    def counter(*args)
      Sass::Script::String.new("counter(#{args.map {|a| a.to_s(options)}.join(',')})")
    end
    declare :counter, [], :var_args => true

    # This function only exists as a workaround for IE7's [`content: counters`
    # bug][bug]. It works identically to any other plain-CSS function, except it
    # avoids adding spaces between the argument commas.
    #
    # [bug]: http://jes.st/2013/ie7s-css-breaking-content-counter-bug/
    #
    # @example
    #   counters(item, ".") => counters(item,".")
    # @overload counters($args...)
    # @return [String]
    def counters(*args)
      Sass::Script::String.new("counters(#{args.map {|a| a.to_s(options)}.join(',')})")
    end
    declare :counters, [], :var_args => true

    private

    # This method implements the pattern of transforming a numeric value into
    # another numeric value with the same units.
    # It yields a number to a block to perform the operation and return a number
    def numeric_transformation(value)
      assert_type value, :Number, :value
      Sass::Script::Number.new(yield(value.value), value.numerator_units, value.denominator_units)
    end

    def _adjust(color, amount, attr, range, op, units = "")
      assert_type color, :Color, :color
      assert_type amount, :Number, :amount
      Sass::Util.check_range('Amount', range, amount, units)

      # TODO: is it worth restricting here,
      # or should we do so in the Color constructor itself,
      # and allow clipping in rgb() et al?
      color.with(attr => Sass::Util.restrict(
          color.send(attr).send(op, amount.value), range))
    end
  end
end

module Sass
  module Script
    # A SassScript parse node representing a function call.
    #
    # A function call either calls one of the functions in {Script::Functions},
    # or if no function with the given name exists
    # it returns a string representation of the function call.
    class Funcall < Node
      # The name of the function.
      #
      # @return [String]
      attr_reader :name

      # The arguments to the function.
      #
      # @return [Array<Script::Node>]
      attr_reader :args

      # The keyword arguments to the function.
      #
      # @return [{String => Script::Node}]
      attr_reader :keywords

      # The splat argument for this function, if one exists.
      #
      # @return [Script::Node?]
      attr_accessor :splat

      # @param name [String] See \{#name}
      # @param args [Array<Script::Node>] See \{#args}
      # @param splat [Script::Node] See \{#splat}
      # @param keywords [{String => Script::Node}] See \{#keywords}
      def initialize(name, args, keywords, splat)
        @name = name
        @args = args
        @keywords = keywords
        @splat = splat
        super()
      end

      # @return [String] A string representation of the function call
      def inspect
        args = @args.map {|a| a.inspect}.join(', ')
        keywords = Sass::Util.hash_to_a(@keywords).
            map {|k, v| "$#{k}: #{v.inspect}"}.join(', ')
        if self.splat
          splat = (args.empty? && keywords.empty?) ? "" : ", "
          splat = "#{splat}#{self.splat.inspect}..."
        end
        "#{name}(#{args}#{', ' unless args.empty? || keywords.empty?}#{keywords}#{splat})"
      end

      # @see Node#to_sass
      def to_sass(opts = {})
        arg_to_sass = lambda do |arg|
          sass = arg.to_sass(opts)
          sass = "(#{sass})" if arg.is_a?(Sass::Script::List) && arg.separator == :comma
          sass
        end

        args = @args.map(&arg_to_sass).join(', ')
        keywords = Sass::Util.hash_to_a(@keywords).
          map {|k, v| "$#{dasherize(k, opts)}: #{arg_to_sass[v]}"}.join(', ')
        if self.splat
          splat = (args.empty? && keywords.empty?) ? "" : ", "
          splat = "#{splat}#{arg_to_sass[self.splat]}..."
        end
        "#{dasherize(name, opts)}(#{args}#{', ' unless args.empty? || keywords.empty?}#{keywords}#{splat})"
      end

      # Returns the arguments to the function.
      #
      # @return [Array<Node>]
      # @see Node#children
      def children
        res = @args + @keywords.values
        res << @splat if @splat
        res
      end

      # @see Node#deep_copy
      def deep_copy
        node = dup
        node.instance_variable_set('@args', args.map {|a| a.deep_copy})
        node.instance_variable_set('@keywords', Hash[keywords.map {|k, v| [k, v.deep_copy]}])
        node
      end

      protected

      # Evaluates the function call.
      #
      # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
      # @return [Literal] The SassScript object that is the value of the function call
      # @raise [Sass::SyntaxError] if the function call raises an ArgumentError
      def _perform(environment)
        args = @args.map {|a| a.perform(environment)}
        splat = @splat.perform(environment) if @splat
        if fn = environment.function(@name)
          keywords = Sass::Util.map_hash(@keywords) {|k, v| [k, v.perform(environment)]}
          return perform_sass_fn(fn, args, keywords, splat)
        end

        ruby_name = @name.tr('-', '_')
        args = construct_ruby_args(ruby_name, args, splat, environment)

        unless Functions.callable?(ruby_name)
          opts(to_literal(args))
        else
          opts(Functions::EvaluationContext.new(environment.options).send(ruby_name, *args))
        end
      rescue ArgumentError => e
        message = e.message

        # If this is a legitimate Ruby-raised argument error, re-raise it.
        # Otherwise, it's an error in the user's stylesheet, so wrap it.
        if Sass::Util.rbx?
          # Rubinius has a different error report string than vanilla Ruby. It
          # also doesn't put the actual method for which the argument error was
          # thrown in the backtrace, nor does it include `send`, so we look for
          # `_perform`.
          if e.message =~ /^method '([^']+)': given (\d+), expected (\d+)/
            error_name, given, expected = $1, $2, $3
            raise e if error_name != ruby_name || e.backtrace[0] !~ /:in `_perform'$/
            message = "wrong number of arguments (#{given} for #{expected})"
          end
        elsif Sass::Util.jruby?
          if Sass::Util.jruby1_6?
            should_maybe_raise = e.message =~ /^wrong number of arguments \((\d+) for (\d+)\)/ &&
              # The one case where JRuby does include the Ruby name of the function
              # is manually-thrown ArgumentErrors, which are indistinguishable from
              # legitimate ArgumentErrors. We treat both of these as
              # Sass::SyntaxErrors even though it can hide Ruby errors.
              e.backtrace[0] !~ /:in `(block in )?#{ruby_name}'$/
          else
            should_maybe_raise = e.message =~ /^wrong number of arguments calling `[^`]+` \((\d+) for (\d+)\)/
            given, expected = $1, $2
          end

          if should_maybe_raise
            # JRuby 1.7 includes __send__ before send and _perform.
            trace = e.backtrace.dup
            raise e if !Sass::Util.jruby1_6? && trace.shift !~ /:in `__send__'$/

            # JRuby (as of 1.7.2) doesn't put the actual method
            # for which the argument error was thrown in the backtrace, so we
            # detect whether our send threw an argument error.
            if !(trace[0] =~ /:in `send'$/ && trace[1] =~ /:in `_perform'$/)
              raise e
            elsif !Sass::Util.jruby1_6?
              # JRuby 1.7 doesn't use standard formatting for its ArgumentErrors.
              message = "wrong number of arguments (#{given} for #{expected})"
            end
          end
        elsif e.message =~ /^wrong number of arguments \(\d+ for \d+\)/ &&
            e.backtrace[0] !~ /:in `(block in )?#{ruby_name}'$/
          raise e
        end
        raise Sass::SyntaxError.new("#{message} for `#{name}'")
      end

      # This method is factored out from `_perform` so that compass can override
      # it with a cross-browser implementation for functions that require vendor prefixes
      # in the generated css.
      def to_literal(args)
        Script::String.new("#{name}(#{args.join(', ')})")
      end

      private

      def construct_ruby_args(name, args, splat, environment)
        args += splat.to_a if splat

        # If variable arguments were passed, there won't be any explicit keywords.
        if splat.is_a?(Sass::Script::ArgList)
          kwargs_size = splat.keywords.size
          splat.keywords_accessed = false
        else
          kwargs_size = @keywords.size
        end

        unless signature = Functions.signature(name.to_sym, args.size, kwargs_size)
          return args if @keywords.empty?
          raise Sass::SyntaxError.new("Function #{name} doesn't support keyword arguments")
        end
        keywords = splat.is_a?(Sass::Script::ArgList) ? splat.keywords :
          Sass::Util.map_hash(@keywords) {|k, v| [k, v.perform(environment)]}

        # If the user passes more non-keyword args than the function expects,
        # but it does expect keyword args, Ruby's arg handling won't raise an error.
        # Since we don't want to make functions think about this,
        # we'll handle it for them here.
        if signature.var_kwargs && !signature.var_args && args.size > signature.args.size
          raise Sass::SyntaxError.new(
            "#{args[signature.args.size].inspect} is not a keyword argument for `#{name}'")
        elsif keywords.empty?
          return args 
        end

        args = args + signature.args[args.size..-1].map do |argname|
          if keywords.has_key?(argname)
            keywords.delete(argname)
          else
            raise Sass::SyntaxError.new("Function #{name} requires an argument named $#{argname}")
          end
        end

        if keywords.size > 0
          if signature.var_kwargs
            args << keywords
          else
            argname = keywords.keys.sort.first
            if signature.args.include?(argname)
              raise Sass::SyntaxError.new("Function #{name} was passed argument $#{argname} both by position and by name")
            else
              raise Sass::SyntaxError.new("Function #{name} doesn't have an argument named $#{argname}")
            end
          end
        end

        args
      end

      def perform_sass_fn(function, args, keywords, splat)
        Sass::Tree::Visitors::Perform.perform_arguments(function, args, keywords, splat) do |env|
          val = catch :_sass_return do
            function.tree.each {|c| Sass::Tree::Visitors::Perform.visit(c, env)}
            raise Sass::SyntaxError.new("Function #{@name} finished without @return")
          end
          val
        end
      end
    end
  end
end
module Sass::Script
  # The abstract superclass for SassScript objects.
  #
  # Many of these methods, especially the ones that correspond to SassScript operations,
  # are designed to be overridden by subclasses which may change the semantics somewhat.
  # The operations listed here are just the defaults.
  class Literal < Node

module Sass::Script
  # A SassScript object representing a number.
  # SassScript numbers can have decimal values,
  # and can also have units.
  # For example, `12`, `1px`, and `10.45em`
  # are all valid values.
  #
  # Numbers can also have more complex units, such as `1px*em/in`.
  # These cannot be inputted directly in Sass code at the moment.
  class Number < Literal
    # The Ruby value of the number.
    #
    # @return [Numeric]
    attr_reader :value

    # A list of units in the numerator of the number.
    # For example, `1px*em/in*cm` would return `["px", "em"]`
    # @return [Array<String>] 
    attr_reader :numerator_units

    # A list of units in the denominator of the number.
    # For example, `1px*em/in*cm` would return `["in", "cm"]`
    # @return [Array<String>]
    attr_reader :denominator_units

    # The original representation of this number.
    # For example, although the result of `1px/2px` is `0.5`,
    # the value of `#original` is `"1px/2px"`.
    #
    # This is only non-nil when the original value should be used as the CSS value,
    # as in `font: 1px/2px`.
    #
    # @return [Boolean, nil]
    attr_accessor :original

    def self.precision
      @precision ||= 5
    end

    # Sets the number of digits of precision
    # For example, if this is `3`,
    # `3.1415926` will be printed as `3.142`.
    def self.precision=(digits)
      @precision = digits.round
      @precision_factor = 10.0**@precision
    end

    # the precision factor used in numeric output
    # it is derived from the `precision` method.
    def self.precision_factor
      @precision_factor ||= 10.0**precision
    end

    # Handles the deprecation warning for the PRECISION constant
    # This can be removed in 3.2.
    def self.const_missing(const)
      if const == :PRECISION
        Sass::Util.sass_warn("Sass::Script::Number::PRECISION is deprecated and will be removed in a future release. Use Sass::Script::Number.precision_factor instead.")
        const_set(:PRECISION, self.precision_factor)
      else
        super
      end
    end

    # Used so we don't allocate two new arrays for each new number.
    NO_UNITS  = []

    # @param value [Numeric] The value of the number
    # @param numerator_units [Array<String>] See \{#numerator\_units}
    # @param denominator_units [Array<String>] See \{#denominator\_units}
    def initialize(value, numerator_units = NO_UNITS, denominator_units = NO_UNITS)
      super(value)
      @numerator_units = numerator_units
      @denominator_units = denominator_units
      normalize!
    end

    # The SassScript `+` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Adds the two numbers together, converting units if possible.
    #
    # {Color}
    # : Adds this number to each of the RGB color channels.
    #
    # {Literal}
    # : See {Literal#plus}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Literal] The result of the operation
    # @raise [Sass::UnitConversionError] if `other` is a number with incompatible units
    def plus(other)
      if other.is_a? Number
        operate(other, :+)
      elsif other.is_a?(Color)
        other.plus(self)
      else
        super
      end
    end

    # The SassScript binary `-` operation (e.g. `$a - $b`).
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Subtracts this number from the other, converting units if possible.
    #
    # {Literal}
    # : See {Literal#minus}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Literal] The result of the operation
    # @raise [Sass::UnitConversionError] if `other` is a number with incompatible units
    def minus(other)
      if other.is_a? Number
        operate(other, :-)
      else
        super
      end
    end

    # The SassScript unary `+` operation (e.g. `+$a`).
    #
    # @return [Number] The value of this number
    def unary_plus
      self
    end

    # The SassScript unary `-` operation (e.g. `-$a`).
    #
    # @return [Number] The negative value of this number
    def unary_minus
      Number.new(-value, @numerator_units, @denominator_units)
    end

    # The SassScript `*` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Multiplies the two numbers together, converting units appropriately.
    #
    # {Color}
    # : Multiplies each of the RGB color channels by this number.
    #
    # @param other [Number, Color] The right-hand side of the operator
    # @return [Number, Color] The result of the operation
    # @raise [NoMethodError] if `other` is an invalid type
    def times(other)
      if other.is_a? Number
        operate(other, :*)
      elsif other.is_a? Color
        other.times(self)
      else
        raise NoMethodError.new(nil, :times)
      end
    end

    # The SassScript `/` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Divides this number by the other, converting units appropriately.
    #
    # {Literal}
    # : See {Literal#div}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Literal] The result of the operation
    def div(other)
      if other.is_a? Number
        res = operate(other, :/)
        if self.original && other.original
          res.original = "#{self.original}/#{other.original}"
        end
        res
      else
        super
      end
    end

    # The SassScript `%` operation.
    #
    # @param other [Number] The right-hand side of the operator
    # @return [Number] This number modulo the other
    # @raise [NoMethodError] if `other` is an invalid type
    # @raise [Sass::UnitConversionError] if `other` has any units
    def mod(other)
      if other.is_a?(Number)
        unless other.unitless?
          raise Sass::UnitConversionError.new("Cannot modulo by a number with units: #{other.inspect}.")
        end
        operate(other, :%)
      else
        raise NoMethodError.new(nil, :mod)
      end
    end

    # The SassScript `==` operation.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Boolean] Whether this number is equal to the other object
    def eq(other)
      return Sass::Script::Bool.new(false) unless other.is_a?(Sass::Script::Number)
      this = self
      begin
        if unitless?
          this = this.coerce(other.numerator_units, other.denominator_units)
        else
          other = other.coerce(@numerator_units, @denominator_units)
        end
      rescue Sass::UnitConversionError
        return Sass::Script::Bool.new(false)
      end

      Sass::Script::Bool.new(this.value == other.value)
    end

    # The SassScript `>` operation.
    #
    # @param other [Number] The right-hand side of the operator
    # @return [Boolean] Whether this number is greater than the other
    # @raise [NoMethodError] if `other` is an invalid type
    def gt(other)
      raise NoMethodError.new(nil, :gt) unless other.is_a?(Number)
      operate(other, :>)
    end

    # The SassScript `>=` operation.
    #
    # @param other [Number] The right-hand side of the operator
    # @return [Boolean] Whether this number is greater than or equal to the other
    # @raise [NoMethodError] if `other` is an invalid type
    def gte(other)
      raise NoMethodError.new(nil, :gte) unless other.is_a?(Number)
      operate(other, :>=)
    end

    # The SassScript `<` operation.
    #
    # @param other [Number] The right-hand side of the operator
    # @return [Boolean] Whether this number is less than the other
    # @raise [NoMethodError] if `other` is an invalid type
    def lt(other)
      raise NoMethodError.new(nil, :lt) unless other.is_a?(Number)
      operate(other, :<)
    end

    # The SassScript `<=` operation.
    #
    # @param other [Number] The right-hand side of the operator
    # @return [Boolean] Whether this number is less than or equal to the other
    # @raise [NoMethodError] if `other` is an invalid type
    def lte(other)
      raise NoMethodError.new(nil, :lte) unless other.is_a?(Number)
      operate(other, :<=)
    end

    # @return [String] The CSS representation of this number
    # @raise [Sass::SyntaxError] if this number has units that can't be used in CSS
    #   (e.g. `px*in`)
    def to_s(opts = {})
      return original if original
      raise Sass::SyntaxError.new("#{inspect} isn't a valid CSS value.") unless legal_units?
      inspect
    end

    # Returns a readable representation of this number.
    #
    # This representation is valid CSS (and valid SassScript)
    # as long as there is only one unit.
    #
    # @return [String] The representation
    def inspect(opts = {})
      value = self.class.round(self.value)
      unitless? ? value.to_s : "#{value}#{unit_str}"
    end
    alias_method :to_sass, :inspect

    # @return [Fixnum] The integer value of the number
    # @raise [Sass::SyntaxError] if the number isn't an integer
    def to_i
      super unless int?
      return value
    end

    # @return [Boolean] Whether or not this number is an integer.
    def int?
      value % 1 == 0.0
    end

    # @return [Boolean] Whether or not this number has no units.
    def unitless?
      @numerator_units.empty? && @denominator_units.empty?
    end

    # @return [Boolean] Whether or not this number has units that can be represented in CSS
    #   (that is, zero or one \{#numerator\_units}).
    def legal_units?
      (@numerator_units.empty? || @numerator_units.size == 1) && @denominator_units.empty?
    end

    # Returns this number converted to other units.
    # The conversion takes into account the relationship between e.g. mm and cm,
    # as well as between e.g. in and cm.
    #
    # If this number has no units, it will simply return itself
    # with the given units.
    #
    # An incompatible coercion, e.g. between px and cm, will raise an error.
    #
    # @param num_units [Array<String>] The numerator units to coerce this number into.
    #   See {\#numerator\_units}
    # @param den_units [Array<String>] The denominator units to coerce this number into.
    #   See {\#denominator\_units}
    # @return [Number] The number with the new units
    # @raise [Sass::UnitConversionError] if the given units are incompatible with the number's
    #   current units
    def coerce(num_units, den_units)
      Number.new(if unitless?
                   self.value
                 else
                   self.value * coercion_factor(@numerator_units, num_units) /
                     coercion_factor(@denominator_units, den_units)
                 end, num_units, den_units)
    end

    # @param other [Number] A number to decide if it can be compared with this number.
    # @return [Boolean] Whether or not this number can be compared with the other.
    def comparable_to?(other)
      begin
        operate(other, :+)
        true
      rescue Sass::UnitConversionError
        false
      end
    end

    # Returns a human readable representation of the units in this number.
    # For complex units this takes the form of:
    # numerator_unit1 * numerator_unit2 / denominator_unit1 * denominator_unit2
    # @return [String] a string that represents the units in this number
    def unit_str
      rv = @numerator_units.sort.join("*")
      if @denominator_units.any?
        rv << "/"
        rv << @denominator_units.sort.join("*")
      end
      rv
    end

    private

    # @private
    def self.round(num)
      if num.is_a?(Float) && (num.infinite? || num.nan?)
        num
      elsif num % 1 == 0.0
        num.to_i
      else
        ((num * self.precision_factor).round / self.precision_factor).to_f
      end
    end

    OPERATIONS = [:+, :-, :<=, :<, :>, :>=]

    def operate(other, operation)
      this = self
      if OPERATIONS.include?(operation)
        if unitless?
          this = this.coerce(other.numerator_units, other.denominator_units)
        else
          other = other.coerce(@numerator_units, @denominator_units)
        end
      end
      # avoid integer division
      value = (:/ == operation) ? this.value.to_f : this.value
      result = value.send(operation, other.value)

      if result.is_a?(Numeric)
        Number.new(result, *compute_units(this, other, operation))
      else # Boolean op
        Bool.new(result)
      end
    end

    def coercion_factor(from_units, to_units)
      # get a list of unmatched units
      from_units, to_units = sans_common_units(from_units, to_units)

      if from_units.size != to_units.size || !convertable?(from_units | to_units)
        raise Sass::UnitConversionError.new("Incompatible units: '#{from_units.join('*')}' and '#{to_units.join('*')}'.")
      end

      from_units.zip(to_units).inject(1) {|m,p| m * conversion_factor(p[0], p[1]) }
    end

    def compute_units(this, other, operation)
      case operation
      when :*
        [this.numerator_units + other.numerator_units, this.denominator_units + other.denominator_units]
      when :/
        [this.numerator_units + other.denominator_units, this.denominator_units + other.numerator_units]
      else  
        [this.numerator_units, this.denominator_units]
      end
    end

    def normalize!
      return if unitless?
      @numerator_units, @denominator_units = sans_common_units(@numerator_units, @denominator_units)

      @denominator_units.each_with_index do |d, i|
        if convertable?(d) && (u = @numerator_units.detect(&method(:convertable?)))
          @value /= conversion_factor(d, u)
          @denominator_units.delete_at(i)
          @numerator_units.delete_at(@numerator_units.index(u))
        end
      end
    end

    # A hash of unit names to their index in the conversion table
    CONVERTABLE_UNITS = {"in" => 0,        "cm" => 1,    "pc" => 2,    "mm" => 3,   "pt" => 4,  "px" => 5    }
    CONVERSION_TABLE = [[ 1,                2.54,         6,            25.4,        72        , 96          ], # in
                        [ nil,              1,            2.36220473,   10,          28.3464567, 37.795275591], # cm
                        [ nil,              nil,          1,            4.23333333,  12        , 16          ], # pc
                        [ nil,              nil,          nil,          1,           2.83464567, 3.7795275591], # mm
                        [ nil,              nil,          nil,          nil,         1         , 1.3333333333], # pt
                        [ nil,              nil,          nil,          nil,         nil       , 1           ]] # px

    def conversion_factor(from_unit, to_unit)
      res = CONVERSION_TABLE[CONVERTABLE_UNITS[from_unit]][CONVERTABLE_UNITS[to_unit]]
      return 1.0 / conversion_factor(to_unit, from_unit) if res.nil?
      res
    end

    def convertable?(units)
      Array(units).all? {|u| CONVERTABLE_UNITS.include?(u)}
    end

    def sans_common_units(units1, units2)
      units2 = units2.dup
      # Can't just use -, because we want px*px to coerce properly to px*mm
      return units1.map do |u|
        next u unless j = units2.index(u)
        units2.delete_at(j)
        nil
      end.compact, units2
    end
  end
end

module Sass::Script
  # A SassScript object representing a CSS color.
  #
  # A color may be represented internally as RGBA, HSLA, or both.
  # It's originally represented as whatever its input is;
  # if it's created with RGB values, it's represented as RGBA,
  # and if it's created with HSL values, it's represented as HSLA.
  # Once a property is accessed that requires the other representation --
  # for example, \{#red} for an HSL color --
  # that component is calculated and cached.
  #
  # The alpha channel of a color is independent of its RGB or HSL representation.
  # It's always stored, as 1 if nothing else is specified.
  # If only the alpha channel is modified using \{#with},
  # the cached RGB and HSL values are retained.
  class Color < Literal
    class << self; include Sass::Util; end

    # A hash from color names to `[red, green, blue]` value arrays.
    COLOR_NAMES = map_vals({
        'aliceblue' => 0xf0f8ff,
        'antiquewhite' => 0xfaebd7,
        'aqua' => 0x00ffff,
        'aquamarine' => 0x7fffd4,
        'azure' => 0xf0ffff,
        'beige' => 0xf5f5dc,
        'bisque' => 0xffe4c4,
        'black' => 0x000000,
        'blanchedalmond' => 0xffebcd,
        'blue' => 0x0000ff,
        'blueviolet' => 0x8a2be2,
        'brown' => 0xa52a2a,
        'burlywood' => 0xdeb887,
        'cadetblue' => 0x5f9ea0,
        'chartreuse' => 0x7fff00,
        'chocolate' => 0xd2691e,
        'coral' => 0xff7f50,
        'cornflowerblue' => 0x6495ed,
        'cornsilk' => 0xfff8dc,
        'crimson' => 0xdc143c,
        'cyan' => 0x00ffff,
        'darkblue' => 0x00008b,
        'darkcyan' => 0x008b8b,
        'darkgoldenrod' => 0xb8860b,
        'darkgray' => 0xa9a9a9,
        'darkgrey' => 0xa9a9a9,
        'darkgreen' => 0x006400,
        'darkkhaki' => 0xbdb76b,
        'darkmagenta' => 0x8b008b,
        'darkolivegreen' => 0x556b2f,
        'darkorange' => 0xff8c00,
        'darkorchid' => 0x9932cc,
        'darkred' => 0x8b0000,
        'darksalmon' => 0xe9967a,
        'darkseagreen' => 0x8fbc8f,
        'darkslateblue' => 0x483d8b,
        'darkslategray' => 0x2f4f4f,
        'darkslategrey' => 0x2f4f4f,
        'darkturquoise' => 0x00ced1,
        'darkviolet' => 0x9400d3,
        'deeppink' => 0xff1493,
        'deepskyblue' => 0x00bfff,
        'dimgray' => 0x696969,
        'dimgrey' => 0x696969,
        'dodgerblue' => 0x1e90ff,
        'firebrick' => 0xb22222,
        'floralwhite' => 0xfffaf0,
        'forestgreen' => 0x228b22,
        'fuchsia' => 0xff00ff,
        'gainsboro' => 0xdcdcdc,
        'ghostwhite' => 0xf8f8ff,
        'gold' => 0xffd700,
        'goldenrod' => 0xdaa520,
        'gray' => 0x808080,
        'green' => 0x008000,
        'greenyellow' => 0xadff2f,
        'honeydew' => 0xf0fff0,
        'hotpink' => 0xff69b4,
        'indianred' => 0xcd5c5c,
        'indigo' => 0x4b0082,
        'ivory' => 0xfffff0,
        'khaki' => 0xf0e68c,
        'lavender' => 0xe6e6fa,
        'lavenderblush' => 0xfff0f5,
        'lawngreen' => 0x7cfc00,
        'lemonchiffon' => 0xfffacd,
        'lightblue' => 0xadd8e6,
        'lightcoral' => 0xf08080,
        'lightcyan' => 0xe0ffff,
        'lightgoldenrodyellow' => 0xfafad2,
        'lightgreen' => 0x90ee90,
        'lightgray' => 0xd3d3d3,
        'lightgrey' => 0xd3d3d3,
        'lightpink' => 0xffb6c1,
        'lightsalmon' => 0xffa07a,
        'lightseagreen' => 0x20b2aa,
        'lightskyblue' => 0x87cefa,
        'lightslategray' => 0x778899,
        'lightslategrey' => 0x778899,
        'lightsteelblue' => 0xb0c4de,
        'lightyellow' => 0xffffe0,
        'lime' => 0x00ff00,
        'limegreen' => 0x32cd32,
        'linen' => 0xfaf0e6,
        'magenta' => 0xff00ff,
        'maroon' => 0x800000,
        'mediumaquamarine' => 0x66cdaa,
        'mediumblue' => 0x0000cd,
        'mediumorchid' => 0xba55d3,
        'mediumpurple' => 0x9370db,
        'mediumseagreen' => 0x3cb371,
        'mediumslateblue' => 0x7b68ee,
        'mediumspringgreen' => 0x00fa9a,
        'mediumturquoise' => 0x48d1cc,
        'mediumvioletred' => 0xc71585,
        'midnightblue' => 0x191970,
        'mintcream' => 0xf5fffa,
        'mistyrose' => 0xffe4e1,
        'moccasin' => 0xffe4b5,
        'navajowhite' => 0xffdead,
        'navy' => 0x000080,
        'oldlace' => 0xfdf5e6,
        'olive' => 0x808000,
        'olivedrab' => 0x6b8e23,
        'orange' => 0xffa500,
        'orangered' => 0xff4500,
        'orchid' => 0xda70d6,
        'palegoldenrod' => 0xeee8aa,
        'palegreen' => 0x98fb98,
        'paleturquoise' => 0xafeeee,
        'palevioletred' => 0xdb7093,
        'papayawhip' => 0xffefd5,
        'peachpuff' => 0xffdab9,
        'peru' => 0xcd853f,
        'pink' => 0xffc0cb,
        'plum' => 0xdda0dd,
        'powderblue' => 0xb0e0e6,
        'purple' => 0x800080,
        'red' => 0xff0000,
        'rosybrown' => 0xbc8f8f,
        'royalblue' => 0x4169e1,
        'saddlebrown' => 0x8b4513,
        'salmon' => 0xfa8072,
        'sandybrown' => 0xf4a460,
        'seagreen' => 0x2e8b57,
        'seashell' => 0xfff5ee,
        'sienna' => 0xa0522d,
        'silver' => 0xc0c0c0,
        'skyblue' => 0x87ceeb,
        'slateblue' => 0x6a5acd,
        'slategray' => 0x708090,
        'slategrey' => 0x708090,
        'snow' => 0xfffafa,
        'springgreen' => 0x00ff7f,
        'steelblue' => 0x4682b4,
        'tan' => 0xd2b48c,
        'teal' => 0x008080,
        'thistle' => 0xd8bfd8,
        'tomato' => 0xff6347,
        'turquoise' => 0x40e0d0,
        'violet' => 0xee82ee,
        'wheat' => 0xf5deb3,
        'white' => 0xffffff,
        'whitesmoke' => 0xf5f5f5,
        'yellow' => 0xffff00,
        'yellowgreen' => 0x9acd32
      }) {|color| (0..2).map {|n| color >> (n << 3) & 0xff}.reverse}

    # A hash from `[red, green, blue]` value arrays to color names.
    COLOR_NAMES_REVERSE = map_hash(hash_to_a(COLOR_NAMES)) {|k, v| [v, k]}

    # Constructs an RGB or HSL color object,
    # optionally with an alpha channel.
    # 
    # The RGB values must be between 0 and 255.
    # The saturation and lightness values must be between 0 and 100.
    # The alpha value must be between 0 and 1.
    #
    # @raise [Sass::SyntaxError] if any color value isn't in the specified range
    #
    # @overload initialize(attrs)
    #   The attributes are specified as a hash.
    #   This hash must contain either `:hue`, `:saturation`, and `:value` keys,
    #   or `:red`, `:green`, and `:blue` keys.
    #   It cannot contain both HSL and RGB keys.
    #   It may also optionally contain an `:alpha` key.
    #
    #   @param attrs [{Symbol => Numeric}] A hash of color attributes to values
    #   @raise [ArgumentError] if not enough attributes are specified,
    #     or both RGB and HSL attributes are specified
    #
    # @overload initialize(rgba)
    #   The attributes are specified as an array.
    #   This overload only supports RGB or RGBA colors.
    #
    #   @param rgba [Array<Numeric>] A three- or four-element array
    #     of the red, green, blue, and optionally alpha values (respectively)
    #     of the color
    #   @raise [ArgumentError] if not enough attributes are specified
    def initialize(attrs, allow_both_rgb_and_hsl = false)
      super(nil)

      if attrs.is_a?(Array)
        unless (3..4).include?(attrs.size)
          raise ArgumentError.new("Color.new(array) expects a three- or four-element array")
        end

        red, green, blue = attrs[0...3].map {|c| c.to_i}
        @attrs = {:red => red, :green => green, :blue => blue}
        @attrs[:alpha] = attrs[3] ? attrs[3].to_f : 1
      else
        attrs = attrs.reject {|k, v| v.nil?}
        hsl = [:hue, :saturation, :lightness] & attrs.keys
        rgb = [:red, :green, :blue] & attrs.keys
        if !allow_both_rgb_and_hsl && !hsl.empty? && !rgb.empty?
          raise ArgumentError.new("Color.new(hash) may not have both HSL and RGB keys specified")
        elsif hsl.empty? && rgb.empty?
          raise ArgumentError.new("Color.new(hash) must have either HSL or RGB keys specified")
        elsif !hsl.empty? && hsl.size != 3
          raise ArgumentError.new("Color.new(hash) must have all three HSL values specified")
        elsif !rgb.empty? && rgb.size != 3
          raise ArgumentError.new("Color.new(hash) must have all three RGB values specified")
        end

        @attrs = attrs
        @attrs[:hue] %= 360 if @attrs[:hue]
        @attrs[:alpha] ||= 1
      end

      [:red, :green, :blue].each do |k|
        next if @attrs[k].nil?
        @attrs[k] = @attrs[k].to_i
        Sass::Util.check_range("#{k.to_s.capitalize} value", 0..255, @attrs[k])
      end

      [:saturation, :lightness].each do |k|
        next if @attrs[k].nil?
        value = Number.new(@attrs[k], ['%']) # Get correct unit for error messages
        @attrs[k] = Sass::Util.check_range("#{k.to_s.capitalize}", 0..100, value, '%')
      end

      @attrs[:alpha] = Sass::Util.check_range("Alpha channel", 0..1, @attrs[:alpha])
    end

    # The red component of the color.
    #
    # @return [Fixnum]
    def red
      hsl_to_rgb!
      @attrs[:red]
    end

    # The green component of the color.
    #
    # @return [Fixnum]
    def green
      hsl_to_rgb!
      @attrs[:green]
    end

    # The blue component of the color.
    #
    # @return [Fixnum]
    def blue
      hsl_to_rgb!
      @attrs[:blue]
    end

    # The hue component of the color.
    #
    # @return [Numeric]
    def hue
      rgb_to_hsl!
      @attrs[:hue]
    end

    # The saturation component of the color.
    #
    # @return [Numeric]
    def saturation
      rgb_to_hsl!
      @attrs[:saturation]
    end

    # The lightness component of the color.
    #
    # @return [Numeric]
    def lightness
      rgb_to_hsl!
      @attrs[:lightness]
    end

    # The alpha channel (opacity) of the color.
    # This is 1 unless otherwise defined.
    #
    # @return [Fixnum]
    def alpha
      @attrs[:alpha]
    end

    # Returns whether this color object is translucent;
    # that is, whether the alpha channel is non-1.
    #
    # @return [Boolean]
    def alpha?
      alpha < 1
    end

    # Returns the red, green, and blue components of the color.
    #
    # @return [Array<Fixnum>] A frozen three-element array of the red, green, and blue
    #   values (respectively) of the color
    def rgb
      [red, green, blue].freeze
    end

    # Returns the hue, saturation, and lightness components of the color.
    #
    # @return [Array<Fixnum>] A frozen three-element array of the
    #   hue, saturation, and lightness values (respectively) of the color
    def hsl
      [hue, saturation, lightness].freeze
    end

    # The SassScript `==` operation.
    # **Note that this returns a {Sass::Script::Bool} object,
    # not a Ruby boolean**.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Bool] True if this literal is the same as the other,
    #   false otherwise
    def eq(other)
      Sass::Script::Bool.new(
        other.is_a?(Color) && rgb == other.rgb && alpha == other.alpha)
    end

    # Returns a copy of this color with one or more channels changed.
    # RGB or HSL colors may be changed, but not both at once.
    #
    # For example:
    #
    #     Color.new([10, 20, 30]).with(:blue => 40)
    #       #=> rgb(10, 40, 30)
    #     Color.new([126, 126, 126]).with(:red => 0, :green => 255)
    #       #=> rgb(0, 255, 126)
    #     Color.new([255, 0, 127]).with(:saturation => 60)
    #       #=> rgb(204, 51, 127)
    #     Color.new([1, 2, 3]).with(:alpha => 0.4)
    #       #=> rgba(1, 2, 3, 0.4)
    #
    # @param attrs [{Symbol => Numeric}]
    #   A map of channel names (`:red`, `:green`, `:blue`,
    #   `:hue`, `:saturation`, `:lightness`, or `:alpha`) to values
    # @return [Color] The new Color object
    # @raise [ArgumentError] if both RGB and HSL keys are specified
    def with(attrs)
      attrs = attrs.reject {|k, v| v.nil?}
      hsl = !([:hue, :saturation, :lightness] & attrs.keys).empty?
      rgb = !([:red, :green, :blue] & attrs.keys).empty?
      if hsl && rgb
        raise ArgumentError.new("Cannot specify HSL and RGB values for a color at the same time")
      end

      if hsl
        [:hue, :saturation, :lightness].each {|k| attrs[k] ||= send(k)}
      elsif rgb
        [:red, :green, :blue].each {|k| attrs[k] ||= send(k)}
      else
        # If we're just changing the alpha channel,
        # keep all the HSL/RGB stuff we've calculated
        attrs = @attrs.merge(attrs)
      end
      attrs[:alpha] ||= alpha

      Color.new(attrs, :allow_both_rgb_and_hsl)
    end

    # The SassScript `+` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Adds the number to each of the RGB color channels.
    #
    # {Color}
    # : Adds each of the RGB color channels together.
    #
    # {Literal}
    # : See {Literal#plus}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Color] The resulting color
    # @raise [Sass::SyntaxError] if `other` is a number with units
    def plus(other)
      if other.is_a?(Sass::Script::Number) || other.is_a?(Sass::Script::Color)
        piecewise(other, :+)
      else
        super
      end
    end

    # The SassScript `-` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Subtracts the number from each of the RGB color channels.
    #
    # {Color}
    # : Subtracts each of the other color's RGB color channels from this color's.
    #
    # {Literal}
    # : See {Literal#minus}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Color] The resulting color
    # @raise [Sass::SyntaxError] if `other` is a number with units
    def minus(other)
      if other.is_a?(Sass::Script::Number) || other.is_a?(Sass::Script::Color)
        piecewise(other, :-)
      else
        super
      end
    end

    # The SassScript `*` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Multiplies the number by each of the RGB color channels.
    #
    # {Color}
    # : Multiplies each of the RGB color channels together.
    #
    # @param other [Number, Color] The right-hand side of the operator
    # @return [Color] The resulting color
    # @raise [Sass::SyntaxError] if `other` is a number with units
    def times(other)
      if other.is_a?(Sass::Script::Number) || other.is_a?(Sass::Script::Color)
        piecewise(other, :*)
      else
        raise NoMethodError.new(nil, :times)
      end
    end

    # The SassScript `/` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Divides each of the RGB color channels by the number.
    #
    # {Color}
    # : Divides each of this color's RGB color channels by the other color's.
    #
    # {Literal}
    # : See {Literal#div}.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Color] The resulting color
    # @raise [Sass::SyntaxError] if `other` is a number with units
    def div(other)
      if other.is_a?(Sass::Script::Number) || other.is_a?(Sass::Script::Color)
        piecewise(other, :/)
      else
        super
      end
    end

    # The SassScript `%` operation.
    # Its functionality depends on the type of its argument:
    #
    # {Number}
    # : Takes each of the RGB color channels module the number.
    #
    # {Color}
    # : Takes each of this color's RGB color channels modulo the other color's.
    #
    # @param other [Number, Color] The right-hand side of the operator
    # @return [Color] The resulting color
    # @raise [Sass::SyntaxError] if `other` is a number with units
    def mod(other)
      if other.is_a?(Sass::Script::Number) || other.is_a?(Sass::Script::Color)
        piecewise(other, :%)
      else
        raise NoMethodError.new(nil, :mod)
      end
    end

    # Returns a string representation of the color.
    # This is usually the color's hex value,
    # but if the color has a name that's used instead.
    #
    # @return [String] The string representation
    def to_s(opts = {})
      return rgba_str if alpha?
      return smallest if options[:style] == :compressed
      return COLOR_NAMES_REVERSE[rgb] if COLOR_NAMES_REVERSE[rgb]
      hex_str
    end
    alias_method :to_sass, :to_s

    # Returns a string representation of the color.
    #
    # @return [String] The hex value
    def inspect
      alpha? ? rgba_str : hex_str
    end

    private

    def smallest
      small_hex_str = hex_str.gsub(/^#(.)\1(.)\2(.)\3$/, '#\1\2\3')
      return small_hex_str unless (color = COLOR_NAMES_REVERSE[rgb]) &&
        color.size <= small_hex_str.size
      return color
    end

    def rgba_str
      split = options[:style] == :compressed ? ',' : ', '
      "rgba(#{rgb.join(split)}#{split}#{Number.round(alpha)})"
    end

    def hex_str
      red, green, blue = rgb.map { |num| num.to_s(16).rjust(2, '0') }
      "##{red}#{green}#{blue}"
    end

    def piecewise(other, operation)
      other_num = other.is_a? Number
      if other_num && !other.unitless?
        raise Sass::SyntaxError.new("Cannot add a number with units (#{other}) to a color (#{self}).") 
      end

      result = []
      for i in (0...3)
        res = rgb[i].send(operation, other_num ? other.value : other.rgb[i])
        result[i] = [ [res, 255].min, 0 ].max
      end

      if !other_num && other.alpha != alpha
        raise Sass::SyntaxError.new("Alpha channels must be equal: #{self} #{operation} #{other}")
      end

      with(:red => result[0], :green => result[1], :blue => result[2])
    end

    def hsl_to_rgb!
      return if @attrs[:red] && @attrs[:blue] && @attrs[:green]

      h = @attrs[:hue] / 360.0
      s = @attrs[:saturation] / 100.0
      l = @attrs[:lightness] / 100.0

      # Algorithm from the CSS3 spec: http://www.w3.org/TR/css3-color/#hsl-color.
      m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s
      m1 = l * 2 - m2
      @attrs[:red], @attrs[:green], @attrs[:blue] = [
        hue_to_rgb(m1, m2, h + 1.0/3),
        hue_to_rgb(m1, m2, h),
        hue_to_rgb(m1, m2, h - 1.0/3)
      ].map {|c| (c * 0xff).round}
    end

    def hue_to_rgb(m1, m2, h)
      h += 1 if h < 0
      h -= 1 if h > 1
      return m1 + (m2 - m1) * h * 6 if h * 6 < 1
      return m2 if h * 2 < 1
      return m1 + (m2 - m1) * (2.0/3 - h) * 6 if h * 3 < 2
      return m1
    end

    def rgb_to_hsl!
      return if @attrs[:hue] && @attrs[:saturation] && @attrs[:lightness]
      r, g, b = [:red, :green, :blue].map {|k| @attrs[k] / 255.0}

      # Algorithm from http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_RGB_to_HSL_or_HSV
      max = [r, g, b].max
      min = [r, g, b].min
      d = max - min

      h =
        case max
        when min; 0
        when r; 60 * (g-b)/d
        when g; 60 * (b-r)/d + 120
        when b; 60 * (r-g)/d + 240
        end

      l = (max + min)/2.0

      s =
        if max == min
          0
        elsif l < 0.5
          d/(2*l)
        else
          d/(2 - 2*l)
        end

      @attrs[:hue] = h % 360
      @attrs[:saturation] = s * 100
      @attrs[:lightness] = l * 100
    end
  end
end

module Sass::Script
  # A SassScript object representing a boolean (true or false) value.
  class Bool < Literal
    # The Ruby value of the boolean.
    #
    # @return [Boolean]
    attr_reader :value
    alias_method :to_bool, :value

    # @return [String] "true" or "false"
    def to_s(opts = {})
      @value.to_s
    end
    alias_method :to_sass, :to_s
  end
end

module Sass::Script
  # A SassScript object representing a null value.
  class Null < Literal
    # Creates a new null literal.
    def initialize
      super nil
    end

    # @return [Boolean] `false` (the Ruby boolean value)
    def to_bool
      false
    end

    # @return [Boolean] `true`
    def null?
      true
    end

    # @return [String] '' (An empty string)
    def to_s(opts = {})
      ''
    end

    def to_sass(opts = {})
      'null'
    end

    # Returns a string representing a null value.
    #
    # @return [String]
    def inspect
      'null'
    end
  end
end
module Sass::Script
  # A SassScript object representing a CSS list.
  # This includes both comma-separated lists and space-separated lists.
  class List < Literal
    # The Ruby array containing the contents of the list.
    #
    # @return [Array<Literal>]
    attr_reader :value
    alias_method :children, :value
    alias_method :to_a, :value

    # The operator separating the values of the list.
    # Either `:comma` or `:space`.
    #
    # @return [Symbol]
    attr_reader :separator

    # Creates a new list.
    #
    # @param value [Array<Literal>] See \{#value}
    # @param separator [String] See \{#separator}
    def initialize(value, separator)
      super(value)
      @separator = separator
    end

    # @see Node#deep_copy
    def deep_copy
      node = dup
      node.instance_variable_set('@value', value.map {|c| c.deep_copy})
      node
    end

    # @see Node#eq
    def eq(other)
      Sass::Script::Bool.new(
        other.is_a?(List) && self.value == other.value &&
        self.separator == other.separator)
    end

    # @see Node#to_s
    def to_s(opts = {})
      raise Sass::SyntaxError.new("() isn't a valid CSS value.") if value.empty?
      return value.reject {|e| e.is_a?(Null) || e.is_a?(List) && e.value.empty?}.map {|e| e.to_s(opts)}.join(sep_str)
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      return "()" if value.empty?
      precedence = Sass::Script::Parser.precedence_of(separator)
      value.reject {|e| e.is_a?(Null)}.map do |v|
        if v.is_a?(List) && Sass::Script::Parser.precedence_of(v.separator) <= precedence ||
            separator == :space && v.is_a?(UnaryOperation) && (v.operator == :minus || v.operator == :plus)
          "(#{v.to_sass(opts)})"
        else
          v.to_sass(opts)
        end
      end.join(sep_str(nil))
    end

    # @see Node#inspect
    def inspect
      "(#{to_sass})"
    end

    protected

    # @see Node#_perform
    def _perform(environment)
      list = Sass::Script::List.new(
        value.map {|e| e.perform(environment)},
        separator)
      list.options = self.options
      list
    end

    private

    def sep_str(opts = self.options)
      return ' ' if separator == :space
      return ',' if opts && opts[:style] == :compressed
      return ', '
    end
  end
end
module Sass::Script
  # A SassScript object representing a variable argument list. This works just
  # like a normal list, but can also contain keyword arguments.
  #
  # The keyword arguments attached to this list are unused except when this is
  # passed as a glob argument to a function or mixin.
  class ArgList < List
    # Whether \{#keywords} has been accessed. If so, we assume that all keywords
    # were valid for the function that created this ArgList.
    #
    # @return [Boolean]
    attr_accessor :keywords_accessed

    # Creates a new argument list.
    #
    # @param value [Array<Literal>] See \{List#value}.
    # @param keywords [Hash<String, Literal>] See \{#keywords}
    # @param separator [String] See \{List#separator}.
    def initialize(value, keywords, separator)
      super(value, separator)
      @keywords = keywords
    end

    # The keyword arguments attached to this list.
    #
    # @return [Hash<String, Literal>]
    def keywords
      @keywords_accessed = true
      @keywords
    end

    # @see Node#children
    def children
      super + @keywords.values
    end

    # @see Node#deep_copy
    def deep_copy
      node = super
      node.instance_variable_set('@keywords',
        Sass::Util.map_hash(@keywords) {|k, v| [k, v.deep_copy]})
      node
    end

    protected

    # @see Node#_perform
    def _perform(environment)
      self
    end
  end
end

    # Returns the Ruby value of the literal.
    # The type of this value varies based on the subclass.
    #
    # @return [Object]
    attr_reader :value

    # Creates a new literal.
    #
    # @param value [Object] The object for \{#value}
    def initialize(value = nil)
      @value = value
      super()
    end

    # Returns an empty array.
    #
    # @return [Array<Node>] empty
    # @see Node#children
    def children
      []
    end

    # @see Node#deep_copy
    def deep_copy
      dup
    end

    # Returns the options hash for this node.
    #
    # @return [{Symbol => Object}]
    # @raise [Sass::SyntaxError] if the options hash hasn't been set.
    #   This should only happen when the literal was created
    #   outside of the parser and \{#to\_s} was called on it
    def options
      opts = super
      return opts if opts
      raise Sass::SyntaxError.new(<<MSG)
The #options attribute is not set on this #{self.class}.
  This error is probably occurring because #to_s was called
  on this literal within a custom Sass function without first
  setting the #option attribute.
MSG
    end

    # The SassScript `==` operation.
    # **Note that this returns a {Sass::Script::Bool} object,
    # not a Ruby boolean**.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Bool] True if this literal is the same as the other,
    #   false otherwise
    def eq(other)
      Sass::Script::Bool.new(self.class == other.class && self.value == other.value)
    end

    # The SassScript `!=` operation.
    # **Note that this returns a {Sass::Script::Bool} object,
    # not a Ruby boolean**.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Bool] False if this literal is the same as the other,
    #   true otherwise
    def neq(other)
      Sass::Script::Bool.new(!eq(other).to_bool)
    end

    # The SassScript `==` operation.
    # **Note that this returns a {Sass::Script::Bool} object,
    # not a Ruby boolean**.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Bool] True if this literal is the same as the other,
    #   false otherwise
    def unary_not
      Sass::Script::Bool.new(!to_bool)
    end

    # The SassScript `=` operation
    # (used for proprietary MS syntax like `alpha(opacity=20)`).
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing both literals
    #   separated by `"="`
    def single_eq(other)
      Sass::Script::String.new("#{self.to_s}=#{other.to_s}")
    end

    # The SassScript `+` operation.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing both literals
    #   without any separation
    def plus(other)
      if other.is_a?(Sass::Script::String)
        return Sass::Script::String.new(self.to_s + other.value, other.type)
      end
      Sass::Script::String.new(self.to_s + other.to_s)
    end

    # The SassScript `-` operation.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing both literals
    #   separated by `"-"`
    def minus(other)
      Sass::Script::String.new("#{self.to_s}-#{other.to_s}")
    end

    # The SassScript `/` operation.
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing both literals
    #   separated by `"/"`
    def div(other)
      Sass::Script::String.new("#{self.to_s}/#{other.to_s}")
    end

    # The SassScript unary `+` operation (e.g. `+$a`).
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing the literal
    #   preceded by `"+"`
    def unary_plus
      Sass::Script::String.new("+#{self.to_s}")
    end

    # The SassScript unary `-` operation (e.g. `-$a`).
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing the literal
    #   preceded by `"-"`
    def unary_minus
      Sass::Script::String.new("-#{self.to_s}")
    end

    # The SassScript unary `/` operation (e.g. `/$a`).
    #
    # @param other [Literal] The right-hand side of the operator
    # @return [Script::String] A string containing the literal
    #   preceded by `"/"`
    def unary_div
      Sass::Script::String.new("/#{self.to_s}")
    end

    # @return [String] A readable representation of the literal
    def inspect
      value.inspect
    end

    # @return [Boolean] `true` (the Ruby boolean value)
    def to_bool
      true
    end

    # Compares this object with another.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] Whether or not this literal is equivalent to `other`
    def ==(other)
      eq(other).to_bool
    end

    # @return [Fixnum] The integer value of this literal
    # @raise [Sass::SyntaxError] if this literal isn't an integer
    def to_i
      raise Sass::SyntaxError.new("#{self.inspect} is not an integer.")
    end

    # @raise [Sass::SyntaxError] if this literal isn't an integer
    def assert_int!; to_i; end

    # Returns the value of this literal as a list.
    # Single literals are considered the same as single-element lists.
    #
    # @return [Array<Literal>] The of this literal as a list
    def to_a
      [self]
    end

    # Returns the string representation of this literal
    # as it would be output to the CSS document.
    #
    # @return [String]
    def to_s(opts = {})
      raise Sass::SyntaxError.new("[BUG] All subclasses of Sass::Literal must implement #to_s.")
    end
    alias_method :to_sass, :to_s

    # Returns whether or not this object is null.
    #
    # @return [Boolean] `false`
    def null?
      false
    end

    protected

    # Evaluates the literal.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Literal] This literal
    def _perform(environment)
      self
    end
  end
end

module Sass::Script
  # A SassScript object representing a CSS string *or* a CSS identifier.
  class String < Literal
    # The Ruby value of the string.
    #
    # @return [String]
    attr_reader :value

    # Whether this is a CSS string or a CSS identifier.
    # The difference is that strings are written with double-quotes,
    # while identifiers aren't.
    #
    # @return [Symbol] `:string` or `:identifier`
    attr_reader :type

    # Creates a new string.
    #
    # @param value [String] See \{#value}
    # @param type [Symbol] See \{#type}
    def initialize(value, type = :identifier)
      super(value)
      @type = type
    end

    # @see Literal#plus
    def plus(other)
      other_str = other.is_a?(Sass::Script::String) ? other.value : other.to_s
      Sass::Script::String.new(self.value + other_str, self.type)
    end

    # @see Node#to_s
    def to_s(opts = {})
      if @type == :identifier
        return @value.gsub(/\n\s*/, " ")
      end

      return "\"#{value.gsub('"', "\\\"")}\"" if opts[:quote] == %q{"}
      return "'#{value.gsub("'", "\\'")}'" if opts[:quote] == %q{'}
      return "\"#{value}\"" unless value.include?('"')
      return "'#{value}'" unless value.include?("'")
      "\"#{value.gsub('"', "\\\"")}\"" #'
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      to_s
    end
  end
end
module Sass::Script
  # A SassScript parse node representing a unary operation,
  # such as `-$b` or `not true`.
  #
  # Currently only `-`, `/`, and `not` are unary operators.
  class UnaryOperation < Node
    # @return [Symbol] The operation to perform
    attr_reader :operator

    # @return [Script::Node] The parse-tree node for the object of the operator
    attr_reader :operand

    # @param operand [Script::Node] See \{#operand}
    # @param operator [Symbol] See \{#operator}
    def initialize(operand, operator)
      @operand = operand
      @operator = operator
      super()
    end

    # @return [String] A human-readable s-expression representation of the operation
    def inspect
      "(#{@operator.inspect} #{@operand.inspect})"
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      operand = @operand.to_sass(opts)
      if @operand.is_a?(Operation) ||
          (@operator == :minus &&
           (operand =~ Sass::SCSS::RX::IDENT) == 0)
        operand = "(#{@operand.to_sass(opts)})"
      end
      op = Lexer::OPERATORS_REVERSE[@operator]
      op + (op =~ /[a-z]/ ? " " : "") + operand
    end

    # Returns the operand of the operation.
    #
    # @return [Array<Node>]
    # @see Node#children
    def children
      [@operand]
    end

    # @see Node#deep_copy
    def deep_copy
      node = dup
      node.instance_variable_set('@operand', @operand.deep_copy)
      node
    end

    protected

    # Evaluates the operation.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Literal] The SassScript object that is the value of the operation
    # @raise [Sass::SyntaxError] if the operation is undefined for the operand
    def _perform(environment)
      operator = "unary_#{@operator}"
      literal = @operand.perform(environment)
      literal.send(operator)
    rescue NoMethodError => e
      raise e unless e.name.to_s == operator.to_s
      raise Sass::SyntaxError.new("Undefined unary operation: \"#{@operator} #{literal}\".")
    end
  end
end
module Sass::Script
  # A SassScript object representing `#{}` interpolation outside a string.
  #
  # @see StringInterpolation
  class Interpolation < Node
    # Interpolation in a property is of the form `before #{mid} after`.
    #
    # @param before [Node] The SassScript before the interpolation
    # @param mid [Node] The SassScript within the interpolation
    # @param after [Node] The SassScript after the interpolation
    # @param wb [Boolean] Whether there was whitespace between `before` and `#{`
    # @param wa [Boolean] Whether there was whitespace between `}` and `after`
    # @param originally_text [Boolean]
    #   Whether the original format of the interpolation was plain text,
    #   not an interpolation.
    #   This is used when converting back to SassScript.
    def initialize(before, mid, after, wb, wa, originally_text = false)
      @before = before
      @mid = mid
      @after = after
      @whitespace_before = wb
      @whitespace_after = wa
      @originally_text = originally_text
    end

    # @return [String] A human-readable s-expression representation of the interpolation
    def inspect
      "(interpolation #{@before.inspect} #{@mid.inspect} #{@after.inspect})"
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      res = ""
      res << @before.to_sass(opts) if @before
      res << ' ' if @before && @whitespace_before
      res << '#{' unless @originally_text
      res << @mid.to_sass(opts)
      res << '}' unless @originally_text
      res << ' ' if @after && @whitespace_after
      res << @after.to_sass(opts) if @after
      res
    end

    # Returns the three components of the interpolation, `before`, `mid`, and `after`.
    #
    # @return [Array<Node>]
    # @see #initialize
    # @see Node#children
    def children
      [@before, @mid, @after].compact
    end

    # @see Node#deep_copy
    def deep_copy
      node = dup
      node.instance_variable_set('@before', @before.deep_copy) if @before
      node.instance_variable_set('@mid', @mid.deep_copy)
      node.instance_variable_set('@after', @after.deep_copy) if @after
      node
    end

    protected

    # Evaluates the interpolation.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Sass::Script::String] The SassScript string that is the value of the interpolation
    def _perform(environment)
      res = ""
      res << @before.perform(environment).to_s if @before
      res << " " if @before && @whitespace_before
      val = @mid.perform(environment)
      res << (val.is_a?(Sass::Script::String) ? val.value : val.to_s)
      res << " " if @after && @whitespace_after
      res << @after.perform(environment).to_s if @after
      opts(Sass::Script::String.new(res))
    end
  end
end
module Sass::Script
  # A SassScript object representing `#{}` interpolation within a string.
  #
  # @see Interpolation
  class StringInterpolation < Node
    # Interpolation in a string is of the form `"before #{mid} after"`,
    # where `before` and `after` may include more interpolation.
    #
    # @param before [Node] The string before the interpolation
    # @param mid [Node] The SassScript within the interpolation
    # @param after [Node] The string after the interpolation
    def initialize(before, mid, after)
      @before = before
      @mid = mid
      @after = after
    end

    # @return [String] A human-readable s-expression representation of the interpolation
    def inspect
      "(string_interpolation #{@before.inspect} #{@mid.inspect} #{@after.inspect})"
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      # We can get rid of all of this when we remove the deprecated :equals context
      # XXX CE: It's gone now but I'm not sure what can be removed now.
      before_unquote, before_quote_char, before_str = parse_str(@before.to_sass(opts))
      after_unquote, after_quote_char, after_str = parse_str(@after.to_sass(opts))
      unquote = before_unquote || after_unquote ||
        (before_quote_char && !after_quote_char && !after_str.empty?) ||
        (!before_quote_char && after_quote_char && !before_str.empty?)
      quote_char =
        if before_quote_char && after_quote_char && before_quote_char != after_quote_char
          before_str.gsub!("\\'", "'")
          before_str.gsub!('"', "\\\"")
          after_str.gsub!("\\'", "'")
          after_str.gsub!('"', "\\\"")
          '"'
        else
          before_quote_char || after_quote_char
        end

      res = ""
      res << 'unquote(' if unquote
      res << quote_char if quote_char
      res << before_str
      res << '#{' << @mid.to_sass(opts) << '}'
      res << after_str
      res << quote_char if quote_char
      res << ')' if unquote
      res
    end

    # Returns the three components of the interpolation, `before`, `mid`, and `after`.
    #
    # @return [Array<Node>]
    # @see #initialize
    # @see Node#children
    def children
      [@before, @mid, @after].compact
    end

    # @see Node#deep_copy
    def deep_copy
      node = dup
      node.instance_variable_set('@before', @before.deep_copy) if @before
      node.instance_variable_set('@mid', @mid.deep_copy)
      node.instance_variable_set('@after', @after.deep_copy) if @after
      node
    end

    protected

    # Evaluates the interpolation.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Sass::Script::String] The SassScript string that is the value of the interpolation
    def _perform(environment)
      res = ""
      before = @before.perform(environment)
      res << before.value
      mid = @mid.perform(environment)
      res << (mid.is_a?(Sass::Script::String) ? mid.value : mid.to_s)
      res << @after.perform(environment).value
      opts(Sass::Script::String.new(res, before.type))
    end

    private

    def parse_str(str)
      case str
      when /^unquote\((["'])(.*)\1\)$/
        return true, $1, $2
      when '""'
        return false, nil, ""
      when /^(["'])(.*)\1$/
        return false, $1, $2
      else
        return false, nil, str
      end
    end
  end
end

module Sass::Script
  # A SassScript parse node representing a binary operation,
  # such as `$a + $b` or `"foo" + 1`.
  class Operation < Node
    attr_reader :operand1
    attr_reader :operand2
    attr_reader :operator

    # @param operand1 [Script::Node] The parse-tree node
    #   for the right-hand side of the operator
    # @param operand2 [Script::Node] The parse-tree node
    #   for the left-hand side of the operator
    # @param operator [Symbol] The operator to perform.
    #   This should be one of the binary operator names in {Lexer::OPERATORS}
    def initialize(operand1, operand2, operator)
      @operand1 = operand1
      @operand2 = operand2
      @operator = operator
      super()
    end

    # @return [String] A human-readable s-expression representation of the operation
    def inspect
      "(#{@operator.inspect} #{@operand1.inspect} #{@operand2.inspect})"
    end

    # @see Node#to_sass
    def to_sass(opts = {})
      o1 = operand_to_sass @operand1, :left, opts
      o2 = operand_to_sass @operand2, :right, opts
      sep =
        case @operator
        when :comma; ", "
        when :space; " "
        else; " #{Lexer::OPERATORS_REVERSE[@operator]} "
        end
      "#{o1}#{sep}#{o2}"
    end

    # Returns the operands for this operation.
    #
    # @return [Array<Node>]
    # @see Node#children
    def children
      [@operand1, @operand2]
    end

    # @see Node#deep_copy
    def deep_copy
      node = dup
      node.instance_variable_set('@operand1', @operand1.deep_copy)
      node.instance_variable_set('@operand2', @operand2.deep_copy)
      node
    end

    protected

    # Evaluates the operation.
    #
    # @param environment [Sass::Environment] The environment in which to evaluate the SassScript
    # @return [Literal] The SassScript object that is the value of the operation
    # @raise [Sass::SyntaxError] if the operation is undefined for the operands
    def _perform(environment)
      literal1 = @operand1.perform(environment)

      # Special-case :and and :or to support short-circuiting.
      if @operator == :and
        return literal1.to_bool ? @operand2.perform(environment) : literal1
      elsif @operator == :or
        return literal1.to_bool ? literal1 : @operand2.perform(environment)
      end

      literal2 = @operand2.perform(environment)

      if (literal1.is_a?(Null) || literal2.is_a?(Null)) && @operator != :eq && @operator != :neq
        raise Sass::SyntaxError.new("Invalid null operation: \"#{literal1.inspect} #{@operator} #{literal2.inspect}\".")
      end

      begin
        opts(literal1.send(@operator, literal2))
      rescue NoMethodError => e
        raise e unless e.name.to_s == @operator.to_s
        raise Sass::SyntaxError.new("Undefined operation: \"#{literal1} #{@operator} #{literal2}\".")
      end
    end

    private

    def operand_to_sass(op, side, opts)
      return "(#{op.to_sass(opts)})" if op.is_a?(List)
      return op.to_sass(opts) unless op.is_a?(Operation)

      pred = Sass::Script::Parser.precedence_of(@operator)
      sub_pred = Sass::Script::Parser.precedence_of(op.operator)
      assoc = Sass::Script::Parser.associative?(@operator)
      return "(#{op.to_sass(opts)})" if sub_pred < pred ||
        (side == :right && sub_pred == pred && !assoc)
      op.to_sass(opts)
    end
  end
end
module Sass
  module SCSS
    # A module containing regular expressions used
    # for lexing tokens in an SCSS document.
    # Most of these are taken from [the CSS3 spec](http://www.w3.org/TR/css3-syntax/#lexical),
    # although some have been modified for various reasons.
    module RX
      # Takes a string and returns a CSS identifier
      # that will have the value of the given string.
      #
      # @param str [String] The string to escape
      # @return [String] The escaped string
      def self.escape_ident(str)
        return "" if str.empty?
        return "\\#{str}" if str == '-' || str == '_'
        out = ""
        value = str.dup
        out << value.slice!(0...1) if value =~ /^[-_]/
        if value[0...1] =~ NMSTART
          out << value.slice!(0...1)
        else
          out << escape_char(value.slice!(0...1))
        end
        out << value.gsub(/[^a-zA-Z0-9_-]/) {|c| escape_char c}
        return out
      end

      # Escapes a single character for a CSS identifier.
      #
      # @param c [String] The character to escape. Should have length 1
      # @return [String] The escaped character
      # @private
      def self.escape_char(c)
        return "\\%06x" % Sass::Util.ord(c) unless c =~ /[ -\/:-~]/
        return "\\#{c}"
      end

      # Creates a Regexp from a plain text string,
      # escaping all significant characters.
      #
      # @param str [String] The text of the regexp
      # @param flags [Fixnum] Flags for the created regular expression
      # @return [Regexp]
      # @private
      def self.quote(str, flags = 0)
        Regexp.new(Regexp.quote(str), flags)
      end

      H        = /[0-9a-fA-F]/
      NL       = /\n|\r\n|\r|\f/
      UNICODE  = /\\#{H}{1,6}[ \t\r\n\f]?/
      s = if Sass::Util.ruby1_8?
            '\200-\377'
          elsif Sass::Util.macruby?
            '\u0080-\uD7FF\uE000-\uFFFD\U00010000-\U0010FFFF'
          else
            '\u{80}-\u{D7FF}\u{E000}-\u{FFFD}\u{10000}-\u{10FFFF}'
          end
      NONASCII = /[#{s}]/
      ESCAPE   = /#{UNICODE}|\\[ -~#{s}]/
      NMSTART  = /[_a-zA-Z]|#{NONASCII}|#{ESCAPE}/
      NMCHAR   = /[a-zA-Z0-9_-]|#{NONASCII}|#{ESCAPE}/
      STRING1  = /\"((?:[^\n\r\f\\"]|\\#{NL}|#{ESCAPE})*)\"/
      STRING2  = /\'((?:[^\n\r\f\\']|\\#{NL}|#{ESCAPE})*)\'/

      IDENT    = /-?#{NMSTART}#{NMCHAR}*/
      NAME     = /#{NMCHAR}+/
      NUM      = /[0-9]+|[0-9]*\.[0-9]+/
      STRING   = /#{STRING1}|#{STRING2}/
      URLCHAR  = /[#%&*-~]|#{NONASCII}|#{ESCAPE}/
      URL      = /(#{URLCHAR}*)/
      W        = /[ \t\r\n\f]*/
      VARIABLE = /(\$)(#{Sass::SCSS::RX::IDENT})/

      # This is more liberal than the spec's definition,
      # but that definition didn't work well with the greediness rules
      RANGE    = /(?:#{H}|\?){1,6}/

      ##

      S = /[ \t\r\n\f]+/

      COMMENT = /\/\*[^*]*\*+(?:[^\/][^*]*\*+)*\//
      SINGLE_LINE_COMMENT = /\/\/.*(\n[ \t]*\/\/.*)*/

      CDO            = quote("<!--")
      CDC            = quote("-->")
      INCLUDES       = quote("~=")
      DASHMATCH      = quote("|=")
      PREFIXMATCH    = quote("^=")
      SUFFIXMATCH    = quote("$=")
      SUBSTRINGMATCH = quote("*=")

      HASH = /##{NAME}/

      IMPORTANT = /!#{W}important/i
      DEFAULT = /!#{W}default/i

      NUMBER = /#{NUM}(?:#{IDENT}|%)?/

      URI = /url\(#{W}(?:#{STRING}|#{URL})#{W}\)/i
      FUNCTION = /#{IDENT}\(/

      UNICODERANGE = /u\+(?:#{H}{1,6}-#{H}{1,6}|#{RANGE})/i

      # Defined in http://www.w3.org/TR/css3-selectors/#lex
      PLUS = /#{W}\+/
      GREATER = /#{W}>/
      TILDE = /#{W}~/
      NOT = quote(":not(", Regexp::IGNORECASE)

      # Defined in https://developer.mozilla.org/en/CSS/@-moz-document as a
      # non-standard version of http://www.w3.org/TR/css3-conditional/
      URL_PREFIX = /url-prefix\(#{W}(?:#{STRING}|#{URL})#{W}\)/i
      DOMAIN = /domain\(#{W}(?:#{STRING}|#{URL})#{W}\)/i

      # Custom
      HEXCOLOR = /\#[0-9a-fA-F]+/
      INTERP_START = /#\{/
      ANY = /:(-[-\w]+-)?any\(/i
      OPTIONAL = /!#{W}optional/i

      IDENT_HYPHEN_INTERP = /-(#\{)/
      STRING1_NOINTERP = /\"((?:[^\n\r\f\\"#]|#(?!\{)|\\#{NL}|#{ESCAPE})*)\"/
      STRING2_NOINTERP = /\'((?:[^\n\r\f\\'#]|#(?!\{)|\\#{NL}|#{ESCAPE})*)\'/
      STRING_NOINTERP = /#{STRING1_NOINTERP}|#{STRING2_NOINTERP}/

      STATIC_COMPONENT = /#{IDENT}|#{STRING_NOINTERP}|#{HEXCOLOR}|[+-]?#{NUMBER}|\!important/i
      STATIC_VALUE = /#{STATIC_COMPONENT}(\s*[\s,\/]\s*#{STATIC_COMPONENT})*([;}])/i
      STATIC_SELECTOR = /(#{NMCHAR}|[ \t]|[,>+*]|[:#.]#{NMSTART}){0,50}([{])/i
    end
  end
end

module Sass
  module Script
    # The lexical analyzer for SassScript.
    # It takes a raw string and converts it to individual tokens
    # that are easier to parse.
    class Lexer
      include Sass::SCSS::RX

      # A struct containing information about an individual token.
      #
      # `type`: \[`Symbol`\]
      # : The type of token.
      #
      # `value`: \[`Object`\]
      # : The Ruby object corresponding to the value of the token.
      #
      # `line`: \[`Fixnum`\]
      # : The line of the source file on which the token appears.
      #
      # `offset`: \[`Fixnum`\]
      # : The number of bytes into the line the SassScript token appeared.
      #
      # `pos`: \[`Fixnum`\]
      # : The scanner position at which the SassScript token appeared.
      Token = Struct.new(:type, :value, :line, :offset, :pos)

      # The line number of the lexer's current position.
      #
      # @return [Fixnum]
      attr_reader :line

      # The number of bytes into the current line
      # of the lexer's current position.
      #
      # @return [Fixnum]
      attr_reader :offset

      # A hash from operator strings to the corresponding token types.
      OPERATORS = {
        '+' => :plus,
        '-' => :minus,
        '*' => :times,
        '/' => :div,
        '%' => :mod,
        '=' => :single_eq,
        ':' => :colon,
        '(' => :lparen,
        ')' => :rparen,
        ',' => :comma,
        'and' => :and,
        'or' => :or,
        'not' => :not,
        '==' => :eq,
        '!=' => :neq,
        '>=' => :gte,
        '<=' => :lte,
        '>' => :gt,
        '<' => :lt,
        '#{' => :begin_interpolation,
        '}' => :end_interpolation,
        ';' => :semicolon,
        '{' => :lcurly,
        '...' => :splat,
      }

      OPERATORS_REVERSE = Sass::Util.map_hash(OPERATORS) {|k, v| [v, k]}

      TOKEN_NAMES = Sass::Util.map_hash(OPERATORS_REVERSE) {|k, v| [k, v.inspect]}.merge({
          :const => "variable (e.g. $foo)",
          :ident => "identifier (e.g. middle)",
          :bool => "boolean (e.g. true, false)",
        })

      # A list of operator strings ordered with longer names first
      # so that `>` and `<` don't clobber `>=` and `<=`.
      OP_NAMES = OPERATORS.keys.sort_by {|o| -o.size}

      # A sub-list of {OP_NAMES} that only includes operators
      # with identifier names.
      IDENT_OP_NAMES = OP_NAMES.select {|k, v| k =~ /^\w+/}

      # A hash of regular expressions that are used for tokenizing.
      REGULAR_EXPRESSIONS = {
        :whitespace => /\s+/,
        :comment => COMMENT,
        :single_line_comment => SINGLE_LINE_COMMENT,
        :variable => /(\$)(#{IDENT})/,
        :ident => /(#{IDENT})(\()?/,
        :number => /(-)?(?:(\d*\.\d+)|(\d+))([a-zA-Z%]+)?/,
        :color => HEXCOLOR,
        :bool => /(true|false)\b/,
        :null => /null\b/,
        :ident_op => %r{(#{Regexp.union(*IDENT_OP_NAMES.map{|s| Regexp.new(Regexp.escape(s) + "(?!#{NMCHAR}|\Z)")})})},
        :op => %r{(#{Regexp.union(*OP_NAMES)})},
      }

      class << self
        private
        def string_re(open, close)
          /#{open}((?:\\.|\#(?!\{)|[^#{close}\\#])*)(#{close}|#\{)/
        end
      end

      # A hash of regular expressions that are used for tokenizing strings.
      #
      # The key is a `[Symbol, Boolean]` pair.
      # The symbol represents which style of quotation to use,
      # while the boolean represents whether or not the string
      # is following an interpolated segment.
      STRING_REGULAR_EXPRESSIONS = {
        [:double, false] => string_re('"', '"'),
        [:single, false] => string_re("'", "'"),
        [:double, true] => string_re('', '"'),
        [:single, true] => string_re('', "'"),
        [:uri, false] => /url\(#{W}(#{URLCHAR}*?)(#{W}\)|#\{)/,
        [:uri, true] => /(#{URLCHAR}*?)(#{W}\)|#\{)/,
        # Defined in https://developer.mozilla.org/en/CSS/@-moz-document as a
        # non-standard version of http://www.w3.org/TR/css3-conditional/
        [:url_prefix, false] => /url-prefix\(#{W}(#{URLCHAR}*?)(#{W}\)|#\{)/,
        [:url_prefix, true] => /(#{URLCHAR}*?)(#{W}\)|#\{)/,
        [:domain, false] => /domain\(#{W}(#{URLCHAR}*?)(#{W}\)|#\{)/,
        [:domain, true] => /(#{URLCHAR}*?)(#{W}\)|#\{)/,
      }

      # @param str [String, StringScanner] The source text to lex
      # @param line [Fixnum] The line on which the SassScript appears.
      #   Used for error reporting
      # @param offset [Fixnum] The number of characters in on which the SassScript appears.
      #   Used for error reporting
      # @param options [{Symbol => Object}] An options hash;
      #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
      def initialize(str, line, offset, options)
        @scanner = str.is_a?(StringScanner) ? str : Sass::Util::MultibyteStringScanner.new(str)
        @line = line
        @offset = offset
        @options = options
        @interpolation_stack = []
        @prev = nil
      end

      # Moves the lexer forward one token.
      #
      # @return [Token] The token that was moved past
      def next
        @tok ||= read_token
        @tok, tok = nil, @tok
        @prev = tok
        return tok
      end

      # Returns whether or not there's whitespace before the next token.
      #
      # @return [Boolean]
      def whitespace?(tok = @tok)
        if tok
          @scanner.string[0...tok.pos] =~ /\s\Z/
        else
          @scanner.string[@scanner.pos, 1] =~ /^\s/ ||
            @scanner.string[@scanner.pos - 1, 1] =~ /\s\Z/
        end
      end

      # Returns the next token without moving the lexer forward.
      #
      # @return [Token] The next token
      def peek
        @tok ||= read_token
      end

      # Rewinds the underlying StringScanner
      # to before the token returned by \{#peek}.
      def unpeek!
        @scanner.pos = @tok.pos if @tok
      end

      # @return [Boolean] Whether or not there's more source text to lex.
      def done?
        whitespace unless after_interpolation? && @interpolation_stack.last
        @scanner.eos? && @tok.nil?
      end

      # @return [Boolean] Whether or not the last token lexed was `:end_interpolation`.
      def after_interpolation?
        @prev && @prev.type == :end_interpolation
      end

      # Raise an error to the effect that `name` was expected in the input stream
      # and wasn't found.
      #
      # This calls \{#unpeek!} to rewind the scanner to immediately after
      # the last returned token.
      #
      # @param name [String] The name of the entity that was expected but not found
      # @raise [Sass::SyntaxError]
      def expected!(name)
        unpeek!
        Sass::SCSS::Parser.expected(@scanner, name, @line)
      end

      # Records all non-comment text the lexer consumes within the block
      # and returns it as a string.
      #
      # @yield A block in which text is recorded
      # @return [String]
      def str
        old_pos = @tok ? @tok.pos : @scanner.pos
        yield
        new_pos = @tok ? @tok.pos : @scanner.pos
        @scanner.string[old_pos...new_pos]
      end

      private

      def read_token
        return if done?
        return unless value = token
        type, val, size = value
        size ||= @scanner.matched_size

        val.line = @line if val.is_a?(Script::Node)
        Token.new(type, val, @line,
          current_position - size, @scanner.pos - size)
      end

      def whitespace
        nil while scan(REGULAR_EXPRESSIONS[:whitespace]) ||
          scan(REGULAR_EXPRESSIONS[:comment]) ||
          scan(REGULAR_EXPRESSIONS[:single_line_comment])
      end

      def token
        if after_interpolation? && (interp_type = @interpolation_stack.pop)
          return string(interp_type, true)
        end

        variable || string(:double, false) || string(:single, false) || number ||
          color || bool || null || string(:uri, false) || raw(UNICODERANGE) ||
          special_fun || special_val || ident_op || ident || op
      end

      def variable
        _variable(REGULAR_EXPRESSIONS[:variable])
      end

      def _variable(rx)
        return unless scan(rx)

        [:const, @scanner[2]]
      end

      def ident
        return unless scan(REGULAR_EXPRESSIONS[:ident])
        [@scanner[2] ? :funcall : :ident, @scanner[1]]
      end

      def string(re, open)
        return unless scan(STRING_REGULAR_EXPRESSIONS[[re, open]])
        if @scanner[2] == '#{' #'
          @scanner.pos -= 2 # Don't actually consume the #{
          @interpolation_stack << re
        end
        str =
          if re == :uri
            Script::String.new("#{'url(' unless open}#{@scanner[1]}#{')' unless @scanner[2] == '#{'}")
          else
            Script::String.new(@scanner[1].gsub(/\\(['"]|\#\{)/, '\1'), :string)
          end
        [:string, str]
      end

      def number
        return unless scan(REGULAR_EXPRESSIONS[:number])
        value = @scanner[2] ? @scanner[2].to_f : @scanner[3].to_i
        value = -value if @scanner[1]
        [:number, Script::Number.new(value, Array(@scanner[4]))]
      end

      def color
        return unless s = scan(REGULAR_EXPRESSIONS[:color])
        raise Sass::SyntaxError.new(<<MESSAGE.rstrip) unless s.size == 4 || s.size == 7
Colors must have either three or six digits: '#{s}'
MESSAGE
        value = s.scan(/^#(..?)(..?)(..?)$/).first.
          map {|num| num.ljust(2, num).to_i(16)}
        [:color, Script::Color.new(value)]
      end

      def bool
        return unless s = scan(REGULAR_EXPRESSIONS[:bool])
        [:bool, Script::Bool.new(s == 'true')]
      end

      def null
        return unless scan(REGULAR_EXPRESSIONS[:null])
        [:null, Script::Null.new]
      end

      def special_fun
        return unless str1 = scan(/((-[\w-]+-)?(calc|element)|expression|progid:[a-z\.]*)\(/i)
        str2, _ = Sass::Shared.balance(@scanner, ?(, ?), 1)
        c = str2.count("\n")
        old_line = @line
        old_offset = @offset
        @line += c
        @offset = (c == 0 ? @offset + str2.size : str2[/\n(.*)/, 1].size)
        [:special_fun,
          Sass::Util.merge_adjacent_strings(
            [str1] + Sass::Engine.parse_interp(str2, old_line, old_offset, @options)),
          str1.size + str2.size]
      end

      def special_val
        return unless scan(/!important/i)
        [:string, Script::String.new("!important")]
      end

      def ident_op
        return unless op = scan(REGULAR_EXPRESSIONS[:ident_op])
        [OPERATORS[op]]
      end

      def op
        return unless op = scan(REGULAR_EXPRESSIONS[:op])
        @interpolation_stack << nil if op == :begin_interpolation
        [OPERATORS[op]]
      end

      def raw(rx)
        return unless val = scan(rx)
        [:raw, val]
      end

      def scan(re)
        return unless str = @scanner.scan(re)
        c = str.count("\n")
        @line += c
        @offset = (c == 0 ? @offset + str.size : str[/\n(.*)/, 1].size)
        str
      end

      def current_position
        @offset + 1
      end
    end
  end
end

module Sass
  module Script
    # The parser for SassScript.
    # It parses a string of code into a tree of {Script::Node}s.
    class Parser
      # The line number of the parser's current position.
      #
      # @return [Fixnum]
      def line
        @lexer.line
      end

      # @param str [String, StringScanner] The source text to parse
      # @param line [Fixnum] The line on which the SassScript appears.
      #   Used for error reporting
      # @param offset [Fixnum] The number of characters in on which the SassScript appears.
      #   Used for error reporting
      # @param options [{Symbol => Object}] An options hash;
      #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
      def initialize(str, line, offset, options = {})
        @options = options
        @lexer = lexer_class.new(str, line, offset, options)
      end

      # Parses a SassScript expression within an interpolated segment (`#{}`).
      # This means that it stops when it comes across an unmatched `}`,
      # which signals the end of an interpolated segment,
      # it returns rather than throwing an error.
      #
      # @return [Script::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse_interpolated
        expr = assert_expr :expr
        assert_tok :end_interpolation
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression.
      #
      # @return [Script::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse
        expr = assert_expr :expr
        assert_done
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression,
      # ending it when it encounters one of the given identifier tokens.
      #
      # @param [#include?(String)] A set of strings that delimit the expression.
      # @return [Script::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse_until(tokens)
        @stop_at = tokens
        expr = assert_expr :expr
        assert_done
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a mixin include.
      #
      # @return [(Array<Script::Node>, {String => Script::Node}, Script::Node)]
      #   The root nodes of the positional arguments, keyword arguments, and
      #   splat argument. Keyword arguments are in a hash from names to values.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_mixin_include_arglist
        args, keywords = [], {}
        if try_tok(:lparen)
          args, keywords, splat = mixin_arglist || [[], {}]
          assert_tok(:rparen)
        end
        assert_done

        args.each {|a| a.options = @options}
        keywords.each {|k, v| v.options = @options}
        splat.options = @options if splat
        return args, keywords, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a mixin definition.
      #
      # @return [(Array<Script::Node>, Script::Node)]
      #   The root nodes of the arguments, and the splat argument.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_mixin_definition_arglist
        args, splat = defn_arglist!(false)
        assert_done

        args.each do |k, v|
          k.options = @options
          v.options = @options if v
        end
        splat.options = @options if splat
        return args, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a function definition.
      #
      # @return [(Array<Script::Node>, Script::Node)]
      #   The root nodes of the arguments, and the splat argument.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_function_definition_arglist
        args, splat = defn_arglist!(true)
        assert_done

        args.each do |k, v|
          k.options = @options
          v.options = @options if v
        end
        splat.options = @options if splat
        return args, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parse a single string value, possibly containing interpolation.
      # Doesn't assert that the scanner is finished after parsing.
      #
      # @return [Script::Node] The root node of the parse tree.
      # @raise [Sass::SyntaxError] if the string isn't valid SassScript
      def parse_string
        unless (peek = @lexer.peek) &&
            (peek.type == :string ||
            (peek.type == :funcall && peek.value.downcase == 'url'))
          lexer.expected!("string")
        end

        expr = assert_expr :funcall
        expr.options = @options
        @lexer.unpeek!
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression.
      #
      # @overload parse(str, line, offset, filename = nil)
      # @return [Script::Node] The root node of the parse tree
      # @see Parser#initialize
      # @see Parser#parse
      def self.parse(*args)
        new(*args).parse
      end

      PRECEDENCE = [
        :comma, :single_eq, :space, :or, :and,
        [:eq, :neq],
        [:gt, :gte, :lt, :lte],
        [:plus, :minus],
        [:times, :div, :mod],
      ]

      ASSOCIATIVE = [:plus, :times]

      class << self
        # Returns an integer representing the precedence
        # of the given operator.
        # A lower integer indicates a looser binding.
        #
        # @private
        def precedence_of(op)
          PRECEDENCE.each_with_index do |e, i|
            return i if Array(e).include?(op)
          end
          raise "[BUG] Unknown operator #{op}"
        end

        # Returns whether or not the given operation is associative.
        #
        # @private
        def associative?(op)
          ASSOCIATIVE.include?(op)
        end

        private

        # Defines a simple left-associative production.
        # name is the name of the production,
        # sub is the name of the production beneath it,
        # and ops is a list of operators for this precedence level
        def production(name, sub, *ops)
          class_eval <<RUBY, __FILE__, __LINE__ + 1
            def #{name}
              interp = try_ops_after_interp(#{ops.inspect}, #{name.inspect}) and return interp
              return unless e = #{sub}
              while tok = try_tok(#{ops.map {|o| o.inspect}.join(', ')})
                if interp = try_op_before_interp(tok, e)
                  return interp unless other_interp = try_ops_after_interp(#{ops.inspect}, #{name.inspect}, interp)
                  return other_interp
                end

                line = @lexer.line
                e = Operation.new(e, assert_expr(#{sub.inspect}), tok.type)
                e.line = line
              end
              e
            end
RUBY
        end

        def unary(op, sub)
          class_eval <<RUBY, __FILE__, __LINE__ + 1
            def unary_#{op}
              return #{sub} unless tok = try_tok(:#{op})
              interp = try_op_before_interp(tok) and return interp
              line = @lexer.line 
              op = UnaryOperation.new(assert_expr(:unary_#{op}), :#{op})
              op.line = line
              op
            end
RUBY
        end
      end

      private

      # @private
      def lexer_class; Lexer; end

      def expr
        line = @lexer.line
        return unless e = interpolation
        list = node(List.new([e], :comma), line)
        while tok = try_tok(:comma)
          if interp = try_op_before_interp(tok, list)
            return interp unless other_interp = try_ops_after_interp([:comma], :expr, interp)
            return other_interp
          end
          list.value << assert_expr(:interpolation)
        end
        list.value.size == 1 ? list.value.first : list
      end

      production :equals, :interpolation, :single_eq

      def try_op_before_interp(op, prev = nil)
        return unless @lexer.peek && @lexer.peek.type == :begin_interpolation
        wb = @lexer.whitespace?(op)
        str = Script::String.new(Lexer::OPERATORS_REVERSE[op.type])
        str.line = @lexer.line
        interp = Script::Interpolation.new(prev, str, nil, wb, !:wa, :originally_text)
        interp.line = @lexer.line
        interpolation(interp)
      end

      def try_ops_after_interp(ops, name, prev = nil)
        return unless @lexer.after_interpolation?
        return unless op = try_tok(*ops)
        interp = try_op_before_interp(op, prev) and return interp

        wa = @lexer.whitespace?
        str = Script::String.new(Lexer::OPERATORS_REVERSE[op.type])
        str.line = @lexer.line
        interp = Script::Interpolation.new(prev, str, assert_expr(name), !:wb, wa, :originally_text)
        interp.line = @lexer.line
        return interp
      end

      def interpolation(first = space)
        e = first
        while interp = try_tok(:begin_interpolation)
          wb = @lexer.whitespace?(interp)
          line = @lexer.line
          mid = parse_interpolated
          wa = @lexer.whitespace?
          e = Script::Interpolation.new(e, mid, space, wb, wa)
          e.line = line
        end
        e
      end

      def space
        line = @lexer.line
        return unless e = or_expr
        arr = [e]
        while e = or_expr
          arr << e
        end
        arr.size == 1 ? arr.first : node(List.new(arr, :space), line)
      end

      production :or_expr, :and_expr, :or
      production :and_expr, :eq_or_neq, :and
      production :eq_or_neq, :relational, :eq, :neq
      production :relational, :plus_or_minus, :gt, :gte, :lt, :lte
      production :plus_or_minus, :times_div_or_mod, :plus, :minus
      production :times_div_or_mod, :unary_plus, :times, :div, :mod

      unary :plus, :unary_minus
      unary :minus, :unary_div
      unary :div, :unary_not # For strings, so /foo/bar works
      unary :not, :ident

      def ident
        return funcall unless @lexer.peek && @lexer.peek.type == :ident
        return if @stop_at && @stop_at.include?(@lexer.peek.value)

        name = @lexer.next
        if color = Color::COLOR_NAMES[name.value.downcase]
          return node(Color.new(color))
        end
        node(Script::String.new(name.value, :identifier))
      end

      def funcall
        return raw unless tok = try_tok(:funcall)
        args, keywords, splat = fn_arglist || [[], {}]
        assert_tok(:rparen)
        node(Script::Funcall.new(tok.value, args, keywords, splat))
      end

      def defn_arglist!(must_have_parens)
        if must_have_parens
          assert_tok(:lparen)
        else
          return [], nil unless try_tok(:lparen)
        end
        return [], nil if try_tok(:rparen)

        res = []
        splat = nil
        must_have_default = false
        loop do
          c = assert_tok(:const)
          var = Script::Variable.new(c.value)
          if try_tok(:colon)
            val = assert_expr(:space)
            must_have_default = true
          elsif must_have_default
            raise SyntaxError.new("Required argument #{var.inspect} must come before any optional arguments.")
          elsif try_tok(:splat)
            splat = var
            break
          end
          res << [var, val]
          break unless try_tok(:comma)
        end
        assert_tok(:rparen)
        return res, splat
      end

      def fn_arglist
        arglist(:equals, "function argument")
      end

      def mixin_arglist
        arglist(:interpolation, "mixin argument")
      end

      def arglist(subexpr, description)
        return unless e = send(subexpr)

        args = []
        keywords = {}
        loop do
          if @lexer.peek && @lexer.peek.type == :colon
            name = e
            @lexer.expected!("comma") unless name.is_a?(Variable)
            assert_tok(:colon)
            value = assert_expr(subexpr, description)

            if keywords[name.underscored_name]
              raise SyntaxError.new("Keyword argument \"#{name.to_sass}\" passed more than once")
            end

            keywords[name.underscored_name] = value
          else
            if !keywords.empty?
              raise SyntaxError.new("Positional arguments must come before keyword arguments.")
            end

            return args, keywords, e if try_tok(:splat)
            args << e
          end

          return args, keywords unless try_tok(:comma)
          e = assert_expr(subexpr, description)
        end
      end

      def raw
        return special_fun unless tok = try_tok(:raw)
        node(Script::String.new(tok.value))
      end

      def special_fun
        return paren unless tok = try_tok(:special_fun)
        first = node(Script::String.new(tok.value.first))
        Sass::Util.enum_slice(tok.value[1..-1], 2).inject(first) do |l, (i, r)|
          Script::Interpolation.new(
            l, i, r && node(Script::String.new(r)),
            false, false)
        end
      end

      def paren
        return variable unless try_tok(:lparen)
        was_in_parens = @in_parens
        @in_parens = true
        line = @lexer.line
        e = expr
        assert_tok(:rparen)
        return e || node(List.new([], :space), line)
      ensure
        @in_parens = was_in_parens
      end

      def variable
        return string unless c = try_tok(:const)
        node(Variable.new(*c.value))
      end

      def string
        return number unless first = try_tok(:string)
        return first.value unless try_tok(:begin_interpolation)
        line = @lexer.line
        mid = parse_interpolated
        last = assert_expr(:string)
        interp = StringInterpolation.new(first.value, mid, last)
        interp.line = line
        interp
      end

      def number
        return literal unless tok = try_tok(:number)
        num = tok.value
        num.original = num.to_s unless @in_parens
        num
      end

      def literal
        (t = try_tok(:color, :bool, :null)) && (return t.value)
      end

      # It would be possible to have unified #assert and #try methods,
      # but detecting the method/token difference turns out to be quite expensive.

      EXPR_NAMES = {
        :string => "string",
        :default => "expression (e.g. 1px, bold)",
        :mixin_arglist => "mixin argument",
        :fn_arglist => "function argument",
      }

      def assert_expr(name, expected = nil)
        (e = send(name)) && (return e)
        @lexer.expected!(expected || EXPR_NAMES[name] || EXPR_NAMES[:default])
      end

      def assert_tok(*names)
        (t = try_tok(*names)) && (return t)
        @lexer.expected!(names.map {|tok| Lexer::TOKEN_NAMES[tok] || tok}.join(" or "))
      end

      def try_tok(*names)
        peeked =  @lexer.peek
        peeked && names.include?(peeked.type) && @lexer.next
      end

      def assert_done
        return if @lexer.done?
        @lexer.expected!(EXPR_NAMES[:default])
      end

      def node(node, line = @lexer.line)
        node.line = line
        node
      end
    end
  end
end

module Sass
  # SassScript is code that's embedded in Sass documents
  # to allow for property values to be computed from variables.
  #
  # This module contains code that handles the parsing and evaluation of SassScript.
  module Script
    # The regular expression used to parse variables.
    MATCH = /^\$(#{Sass::SCSS::RX::IDENT})\s*:\s*(.+?)(!(?i:default))?$/

    # The regular expression used to validate variables without matching.
    VALIDATE = /^\$#{Sass::SCSS::RX::IDENT}$/

    # Parses a string of SassScript
    #
    # @param value [String] The SassScript
    # @param line [Fixnum] The number of the line on which the SassScript appeared.
    #   Used for error reporting
    # @param offset [Fixnum] The number of characters in on `line` that the SassScript started.
    #   Used for error reporting
    # @param options [{Symbol => Object}] An options hash;
    #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
    # @return [Script::Node] The root node of the parse tree
    def self.parse(value, line, offset, options = {})
      Parser.parse(value, line, offset, options)
    rescue Sass::SyntaxError => e
      e.message << ": #{value.inspect}." if e.message == "SassScript error"
      e.modify_backtrace(:line => line, :filename => options[:filename])
      raise e
    end

  end
end
module Sass
  module SCSS
    # A mixin for subclasses of {Sass::Script::Lexer}
    # that makes them usable by {SCSS::Parser} to parse SassScript.
    # In particular, the lexer doesn't support `!` for a variable prefix.
    module ScriptLexer
      private

      def variable
        return [:raw, "!important"] if scan(Sass::SCSS::RX::IMPORTANT)
        _variable(Sass::SCSS::RX::VARIABLE)
      end
    end
  end
end
module Sass
  module SCSS
    # A mixin for subclasses of {Sass::Script::Parser}
    # that makes them usable by {SCSS::Parser} to parse SassScript.
    # In particular, the parser won't raise an error
    # when there's more content in the lexer once lexing is done.
    # In addition, the parser doesn't support `!` for a variable prefix.
    module ScriptParser
      private

      # @private
      def lexer_class
        klass = Class.new(super)
        klass.send(:include, ScriptLexer)
        klass
      end

      # Instead of raising an error when the parser is done,
      # rewind the StringScanner so that it hasn't consumed the final token.
      def assert_done
        @lexer.unpeek!
      end
    end
  end
end

module Sass
  module SCSS
    # The parser for SCSS.
    # It parses a string of code into a tree of {Sass::Tree::Node}s.
    class Parser
      # @param str [String, StringScanner] The source document to parse.
      #   Note that `Parser` *won't* raise a nice error message if this isn't properly parsed;
      #   for that, you should use the higher-level {Sass::Engine} or {Sass::CSS}.
      # @param filename [String] The name of the file being parsed. Used for warnings.
      # @param line [Fixnum] The line on which the source string appeared,
      #   if it's part of another document.
      def initialize(str, filename, line = 1)
        @template = str
        @filename = filename
        @line = line
        @strs = []
      end

      # Parses an SCSS document.
      #
      # @return [Sass::Tree::RootNode] The root node of the document tree
      # @raise [Sass::SyntaxError] if there's a syntax error in the document
      def parse
        init_scanner!
        root = stylesheet
        expected("selector or at-rule") unless @scanner.eos?
        root
      end

      # Parses an identifier with interpolation.
      # Note that this won't assert that the identifier takes up the entire input string;
      # it's meant to be used with `StringScanner`s as part of other parsers.
      #
      # @return [Array<String, Sass::Script::Node>, nil]
      #   The interpolated identifier, or nil if none could be parsed
      def parse_interp_ident
        init_scanner!
        interp_ident
      end

      # Parses a media query list.
      #
      # @return [Sass::Media::QueryList] The parsed query list
      # @raise [Sass::SyntaxError] if there's a syntax error in the query list,
      #   or if it doesn't take up the entire input string.
      def parse_media_query_list
        init_scanner!
        ql = media_query_list
        expected("media query list") unless @scanner.eos?
        ql
      end

      # Parses a supports query condition.
      #
      # @return [Sass::Supports::Condition] The parsed condition
      # @raise [Sass::SyntaxError] if there's a syntax error in the condition,
      #   or if it doesn't take up the entire input string.
      def parse_supports_condition
        init_scanner!
        condition = supports_condition
        expected("supports condition") unless @scanner.eos?
        condition
      end

      private

      include Sass::SCSS::RX

      def init_scanner!
        @scanner =
          if @template.is_a?(StringScanner)
            @template
          else
            Sass::Util::MultibyteStringScanner.new(@template.gsub("\r", ""))
          end
      end

      def stylesheet
        node = node(Sass::Tree::RootNode.new(@scanner.string))
        block_contents(node, :stylesheet) {s(node)}
      end

      def s(node)
        while tok(S) || tok(CDC) || tok(CDO) || (c = tok(SINGLE_LINE_COMMENT)) || (c = tok(COMMENT))
          next unless c
          process_comment c, node
          c = nil
        end
        true
      end

      def ss
        nil while tok(S) || tok(SINGLE_LINE_COMMENT) || tok(COMMENT)
        true
      end

      def ss_comments(node)
        while tok(S) || (c = tok(SINGLE_LINE_COMMENT)) || (c = tok(COMMENT))
          next unless c
          process_comment c, node
          c = nil
        end

        true
      end

      def whitespace
        return unless tok(S) || tok(SINGLE_LINE_COMMENT) || tok(COMMENT)
        ss
      end

      def process_comment(text, node)
        silent = text =~ /^\/\//
        loud = !silent && text =~ %r{^/[/*]!}
        line = @line - text.count("\n")

        if silent
          value = [text.sub(/^\s*\/\//, '/*').gsub(/^\s*\/\//, ' *') + ' */']
        else
          value = Sass::Engine.parse_interp(text, line, @scanner.pos - text.size, :filename => @filename)
          value.unshift(@scanner.
            string[0...@scanner.pos].
            reverse[/.*?\*\/(.*?)($|\Z)/, 1].
            reverse.gsub(/[^\s]/, ' '))
        end

        type = if silent then :silent elsif loud then :loud else :normal end
        comment = Sass::Tree::CommentNode.new(value, type)
        comment.line = line
        node << comment
      end

      DIRECTIVES = Set[:mixin, :include, :function, :return, :debug, :warn, :for,
        :each, :while, :if, :else, :extend, :import, :media, :charset, :content,
        :_moz_document]

      PREFIXED_DIRECTIVES = Set[:supports]

      def directive
        return unless tok(/@/)
        name = tok!(IDENT)
        ss

        if dir = special_directive(name)
          return dir
        elsif dir = prefixed_directive(name)
          return dir
        end

        # Most at-rules take expressions (e.g. @import),
        # but some (e.g. @page) take selector-like arguments.
        # Some take no arguments at all.
        val = expr || selector
        val = val ? ["@#{name} "] + Sass::Util.strip_string_array(val) : ["@#{name}"]
        directive_body(val)
      end

      def directive_body(value)
        node = node(Sass::Tree::DirectiveNode.new(value))

        if tok(/\{/)
          node.has_children = true
          block_contents(node, :directive)
          tok!(/\}/)
        end

        node
      end

      def special_directive(name)
        sym = name.gsub('-', '_').to_sym
        DIRECTIVES.include?(sym) && send("#{sym}_directive")
      end

      def prefixed_directive(name)
        sym = name.gsub(/^-[a-z0-9]+-/i, '').gsub('-', '_').to_sym
        PREFIXED_DIRECTIVES.include?(sym) && send("#{sym}_directive", name)
      end

      def mixin_directive
        name = tok! IDENT
        args, splat = sass_script(:parse_mixin_definition_arglist)
        ss
        block(node(Sass::Tree::MixinDefNode.new(name, args, splat)), :directive)
      end

      def include_directive
        name = tok! IDENT
        args, keywords, splat = sass_script(:parse_mixin_include_arglist)
        ss
        include_node = node(Sass::Tree::MixinNode.new(name, args, keywords, splat))
        if tok?(/\{/)
          include_node.has_children = true
          block(include_node, :directive)
        else
          include_node
        end
      end

      def content_directive
        ss
        node(Sass::Tree::ContentNode.new)
      end

      def function_directive
        name = tok! IDENT
        args, splat = sass_script(:parse_function_definition_arglist)
        ss
        block(node(Sass::Tree::FunctionNode.new(name, args, splat)), :function)
      end

      def return_directive
        node(Sass::Tree::ReturnNode.new(sass_script(:parse)))
      end

      def debug_directive
        node(Sass::Tree::DebugNode.new(sass_script(:parse)))
      end

      def warn_directive
        node(Sass::Tree::WarnNode.new(sass_script(:parse)))
      end

      def for_directive
        tok!(/\$/)
        var = tok! IDENT
        ss

        tok!(/from/)
        from = sass_script(:parse_until, Set["to", "through"])
        ss

        @expected = '"to" or "through"'
        exclusive = (tok(/to/) || tok!(/through/)) == 'to'
        to = sass_script(:parse)
        ss

        block(node(Sass::Tree::ForNode.new(var, from, to, exclusive)), :directive)
      end

      def each_directive
        tok!(/\$/)
        var = tok! IDENT
        ss

        tok!(/in/)
        list = sass_script(:parse)
        ss

        block(node(Sass::Tree::EachNode.new(var, list)), :directive)
      end

      def while_directive
        expr = sass_script(:parse)
        ss
        block(node(Sass::Tree::WhileNode.new(expr)), :directive)
      end

      def if_directive
        expr = sass_script(:parse)
        ss
        node = block(node(Sass::Tree::IfNode.new(expr)), :directive)
        pos = @scanner.pos
        line = @line
        ss

        else_block(node) ||
          begin
            # Backtrack in case there are any comments we want to parse
            @scanner.pos = pos
            @line = line
            node
          end
      end

      def else_block(node)
        return unless tok(/@else/)
        ss
        else_node = block(
          Sass::Tree::IfNode.new((sass_script(:parse) if tok(/if/))),
          :directive)
        node.add_else(else_node)
        pos = @scanner.pos
        line = @line
        ss

        else_block(node) ||
          begin
            # Backtrack in case there are any comments we want to parse
            @scanner.pos = pos
            @line = line
            node
          end
      end

      def else_directive
        err("Invalid CSS: @else must come after @if")
      end

      def extend_directive
        selector = expr!(:selector_sequence)
        optional = tok(OPTIONAL)
        ss
        node(Sass::Tree::ExtendNode.new(selector, !!optional))
      end

      def import_directive
        values = []

        loop do
          values << expr!(:import_arg)
          break if use_css_import?
          break unless tok(/,/)
          ss
        end

        return values
      end

      def import_arg
        line = @line
        return unless (str = tok(STRING)) || (uri = tok?(/url\(/i))
        if uri
          str = sass_script(:parse_string)
          media = media_query_list
          ss
          return node(Tree::CssImportNode.new(str, media.to_a))
        end

        path = @scanner[1] || @scanner[2]
        ss

        media = media_query_list
        if path =~ /^(https?:)?\/\// || media || use_css_import?
          node = Sass::Tree::CssImportNode.new(str, media.to_a)
        else
          node = Sass::Tree::ImportNode.new(path.strip)
        end
        node.line = line
        node
      end

      def use_css_import?; false; end

      def media_directive
        block(node(Sass::Tree::MediaNode.new(expr!(:media_query_list).to_a)), :directive)
      end

      # http://www.w3.org/TR/css3-mediaqueries/#syntax
      def media_query_list
        return unless query = media_query
        queries = [query]

        ss
        while tok(/,/)
          ss; queries << expr!(:media_query)
        end
        ss

        Sass::Media::QueryList.new(queries)
      end

      def media_query
        if ident1 = interp_ident
          ss
          ident2 = interp_ident
          ss
          if ident2 && ident2.length == 1 && ident2[0].is_a?(String) && ident2[0].downcase == 'and'
            query = Sass::Media::Query.new([], ident1, [])
          else
            if ident2
              query = Sass::Media::Query.new(ident1, ident2, [])
            else
              query = Sass::Media::Query.new([], ident1, [])
            end
            return query unless tok(/and/i)
            ss
          end
        end

        if query
          expr = expr!(:media_expr)
        else
          return unless expr = media_expr
        end
        query ||= Sass::Media::Query.new([], [], [])
        query.expressions << expr

        ss
        while tok(/and/i)
          ss; query.expressions << expr!(:media_expr)
        end

        query
      end

      def media_expr
        interp = interpolation and return interp
        return unless tok(/\(/)
        res = ['(']
        ss
        res << sass_script(:parse)

        if tok(/:/)
          res << ': '
          ss
          res << sass_script(:parse)
        end
        res << tok!(/\)/)
        ss
        res
      end

      def charset_directive
        tok! STRING
        name = @scanner[1] || @scanner[2]
        ss
        node(Sass::Tree::CharsetNode.new(name))
      end

      # The document directive is specified in
      # http://www.w3.org/TR/css3-conditional/, but Gecko allows the
      # `url-prefix` and `domain` functions to omit quotation marks, contrary to
      # the standard.
      #
      # We could parse all document directives according to Mozilla's syntax,
      # but if someone's using e.g. @-webkit-document we don't want them to
      # think WebKit works sans quotes.
      def _moz_document_directive
        res = ["@-moz-document "]
        loop do
          res << str{ss} << expr!(:moz_document_function)
          break unless c = tok(/,/)
          res << c
        end
        directive_body(res.flatten)
      end

      def moz_document_function
        return unless val = interp_uri || _interp_string(:url_prefix) ||
          _interp_string(:domain) || function(!:allow_var) || interpolation
        ss
        val
      end

      # http://www.w3.org/TR/css3-conditional/
      def supports_directive(name)
        condition = expr!(:supports_condition)
        node = node(Sass::Tree::SupportsNode.new(name, condition))

        tok!(/\{/)
        node.has_children = true
        block_contents(node, :directive)
        tok!(/\}/)

        node
      end

      def supports_condition
        supports_negation || supports_operator || supports_interpolation
      end

      def supports_negation
        return unless tok(/not/i)
        ss
        Sass::Supports::Negation.new(expr!(:supports_condition_in_parens))
      end

      def supports_operator
        return unless cond = supports_condition_in_parens
        return cond unless op = tok(/and|or/i)
        begin
          ss
          cond = Sass::Supports::Operator.new(
            cond, expr!(:supports_condition_in_parens), op)
        end while op = tok(/and|or/i)
        cond
      end

      def supports_condition_in_parens
        interp = supports_interpolation and return interp
        return unless tok(/\(/); ss
        if cond = supports_condition
          tok!(/\)/); ss
          cond
        else
          name = sass_script(:parse)
          tok!(/:/); ss
          value = sass_script(:parse)
          tok!(/\)/); ss
          Sass::Supports::Declaration.new(name, value)
        end
      end

      def supports_declaration_condition
        return unless tok(/\(/); ss
        supports_declaration_body
      end

      def supports_interpolation
        return unless interp = interpolation
        ss
        Sass::Supports::Interpolation.new(interp)
      end

      def variable
        return unless tok(/\$/)
        name = tok!(IDENT)
        ss; tok!(/:/); ss

        expr = sass_script(:parse)
        guarded = tok(DEFAULT)
        node(Sass::Tree::VariableNode.new(name, expr, guarded))
      end

      def operator
        # Many of these operators (all except / and ,)
        # are disallowed by the CSS spec,
        # but they're included here for compatibility
        # with some proprietary MS properties
        str {ss if tok(/[\/,:.=]/)}
      end

      def ruleset
        return unless rules = selector_sequence
        block(node(Sass::Tree::RuleNode.new(rules.flatten.compact)), :ruleset)
      end

      def block(node, context)
        node.has_children = true
        tok!(/\{/)
        block_contents(node, context)
        tok!(/\}/)
        node
      end

      # A block may contain declarations and/or rulesets
      def block_contents(node, context)
        block_given? ? yield : ss_comments(node)
        node << (child = block_child(context))
        while tok(/;/) || has_children?(child)
          block_given? ? yield : ss_comments(node)
          node << (child = block_child(context))
        end
        node
      end

      def block_child(context)
        return variable || directive if context == :function
        return variable || directive || ruleset if context == :stylesheet
        variable || directive || declaration_or_ruleset
      end

      def has_children?(child_or_array)
        return false unless child_or_array
        return child_or_array.last.has_children if child_or_array.is_a?(Array)
        return child_or_array.has_children
      end

      # This is a nasty hack, and the only place in the parser
      # that requires a large amount of backtracking.
      # The reason is that we can't figure out if certain strings
      # are declarations or rulesets with fixed finite lookahead.
      # For example, "foo:bar baz baz baz..." could be either a property
      # or a selector.
      #
      # To handle this, we simply check if it works as a property
      # (which is the most common case)
      # and, if it doesn't, try it as a ruleset.
      #
      # We could eke some more efficiency out of this
      # by handling some easy cases (first token isn't an identifier,
      # no colon after the identifier, whitespace after the colon),
      # but I'm not sure the gains would be worth the added complexity.
      def declaration_or_ruleset
        old_use_property_exception, @use_property_exception =
          @use_property_exception, false
        decl_err = catch_error do
          decl = declaration
          unless decl && decl.has_children
            # We want an exception if it's not there,
            # but we don't want to consume if it is
            tok!(/[;}]/) unless tok?(/[;}]/)
          end
          return decl
        end

        ruleset_err = catch_error {return ruleset}
        rethrow(@use_property_exception ? decl_err : ruleset_err)
      ensure
        @use_property_exception = old_use_property_exception
      end

      def selector_sequence
        if sel = tok(STATIC_SELECTOR, true)
          return [sel]
        end

        rules = []
        return unless v = selector
        rules.concat v

        ws = ''
        while tok(/,/)
          ws << str {ss}
          if v = selector
            rules << ',' << ws
            rules.concat v
            ws = ''
          end
        end
        rules
      end

      def selector
        return unless sel = _selector
        sel.to_a
      end

      def selector_comma_sequence
        return unless sel = _selector
        selectors = [sel]
        ws = ''
        while tok(/,/)
          ws << str{ss}
          if sel = _selector
            selectors << sel
            selectors[-1] = Selector::Sequence.new(["\n"] + selectors.last.members) if ws.include?("\n")
            ws = ''
          end
        end
        Selector::CommaSequence.new(selectors)
      end

      def _selector
        # The combinator here allows the "> E" hack
        return unless val = combinator || simple_selector_sequence
        nl = str{ss}.include?("\n")
        res = []
        res << val
        res << "\n" if nl

        while val = combinator || simple_selector_sequence
          res << val
          res << "\n" if str{ss}.include?("\n")
        end
        Selector::Sequence.new(res.compact)
      end

      def combinator
        tok(PLUS) || tok(GREATER) || tok(TILDE) || reference_combinator
      end

      def reference_combinator
        return unless tok(/\//)
        res = ['/']
        ns, name = expr!(:qualified_name)
        res << ns << '|' if ns
        res << name << tok!(/\//)
        res = res.flatten
        res = res.join '' if res.all? {|e| e.is_a?(String)}
        res
      end

      def simple_selector_sequence
        # Returning expr by default allows for stuff like
        # http://www.w3.org/TR/css3-animations/#keyframes-
        return expr(!:allow_var) unless e = element_name || id_selector ||
          class_selector || placeholder_selector || attrib || pseudo ||
          parent_selector || interpolation_selector
        res = [e]

        # The tok(/\*/) allows the "E*" hack
        while v = id_selector || class_selector || placeholder_selector || attrib ||
            pseudo || interpolation_selector ||
            (tok(/\*/) && Selector::Universal.new(nil))
          res << v
        end

        pos = @scanner.pos
        line = @line
        if sel = str? {simple_selector_sequence}
          @scanner.pos = pos
          @line = line
          begin
            # If we see "*E", don't force a throw because this could be the
            # "*prop: val" hack.
            expected('"{"') if res.length == 1 && res[0].is_a?(Selector::Universal)
            throw_error {expected('"{"')}
          rescue Sass::SyntaxError => e
            e.message << "\n\n\"#{sel}\" may only be used at the beginning of a compound selector."
            raise e
          end
        end

        Selector::SimpleSequence.new(res, tok(/!/))
      end

      def parent_selector
        return unless tok(/&/)
        Selector::Parent.new
      end

      def class_selector
        return unless tok(/\./)
        @expected = "class name"
        Selector::Class.new(merge(expr!(:interp_ident)))
      end

      def id_selector
        return unless tok(/#(?!\{)/)
        @expected = "id name"
        Selector::Id.new(merge(expr!(:interp_name)))
      end

      def placeholder_selector
        return unless tok(/%/)
        @expected = "placeholder name"
        Selector::Placeholder.new(merge(expr!(:interp_ident)))
      end

      def element_name
        ns, name = Sass::Util.destructure(qualified_name(:allow_star_name))
        return unless ns || name

        if name == '*'
          Selector::Universal.new(merge(ns))
        else
          Selector::Element.new(merge(name), merge(ns))
        end
      end

      def qualified_name(allow_star_name=false)
        return unless name = interp_ident || tok(/\*/) || (tok?(/\|/) && "")
        return nil, name unless tok(/\|/)

        return name, expr!(:interp_ident) unless allow_star_name
        @expected = "identifier or *"
        return name, interp_ident || tok!(/\*/)
      end

      def interpolation_selector
        return unless script = interpolation
        Selector::Interpolation.new(script)
      end

      def attrib
        return unless tok(/\[/)
        ss
        ns, name = attrib_name!
        ss

        if op = tok(/=/) ||
            tok(INCLUDES) ||
            tok(DASHMATCH) ||
            tok(PREFIXMATCH) ||
            tok(SUFFIXMATCH) ||
            tok(SUBSTRINGMATCH)
          @expected = "identifier or string"
          ss
          val = interp_ident || expr!(:interp_string)
          ss
        end
        flags = interp_ident || interp_string
        tok!(/\]/)

        Selector::Attribute.new(merge(name), merge(ns), op, merge(val), merge(flags))
      end

      def attrib_name!
        if name_or_ns = interp_ident
          # E, E|E
          if tok(/\|(?!=)/)
            ns = name_or_ns
            name = interp_ident
          else
            name = name_or_ns
          end
        else
          # *|E or |E
          ns = [tok(/\*/) || ""]
          tok!(/\|/)
          name = expr!(:interp_ident)
        end
        return ns, name
      end

      def pseudo
        return unless s = tok(/::?/)
        @expected = "pseudoclass or pseudoelement"
        name = expr!(:interp_ident)
        if tok(/\(/)
          ss
          arg = expr!(:pseudo_arg)
          while tok(/,/)
            arg << ',' << str{ss}
            arg.concat expr!(:pseudo_arg)
          end
          tok!(/\)/)
        end
        Selector::Pseudo.new(s == ':' ? :class : :element, merge(name), merge(arg))
      end

      def pseudo_arg
        # In the CSS spec, every pseudo-class/element either takes a pseudo
        # expression or a selector comma sequence as an argument. However, we
        # don't want to have to know which takes which, so we handle both at
        # once.
        #
        # However, there are some ambiguities between the two. For instance, "n"
        # could start a pseudo expression like "n+1", or it could start a
        # selector like "n|m". In order to handle this, we must regrettably
        # backtrack.
        expr, sel = nil, nil
        pseudo_err = catch_error do
          expr = pseudo_expr
          next if tok?(/[,)]/)
          expr = nil
          expected '")"'
        end

        return expr if expr
        sel_err = catch_error {sel = selector}
        return sel if sel
        rethrow pseudo_err if pseudo_err
        rethrow sel_err if sel_err
        return
      end

      def pseudo_expr
        return unless e = tok(PLUS) || tok(/[-*]/) || tok(NUMBER) ||
          interp_string || tok(IDENT) || interpolation
        res = [e, str{ss}]
        while e = tok(PLUS) || tok(/[-*]/) || tok(NUMBER) ||
            interp_string || tok(IDENT) || interpolation
          res << e << str{ss}
        end
        res
      end

      def declaration
        # This allows the "*prop: val", ":prop: val", and ".prop: val" hacks
        if s = tok(/[:\*\.]|\#(?!\{)/)
          @use_property_exception = s !~ /[\.\#]/
          name = [s, str{ss}, *expr!(:interp_ident)]
        else
          return unless name = interp_ident
          name = [name] if name.is_a?(String)
        end
        if comment = tok(COMMENT)
          name << comment
        end
        ss

        tok!(/:/)
        space, value = value!
        ss
        require_block = tok?(/\{/)

        node = node(Sass::Tree::PropNode.new(name.flatten.compact, value, :new))

        return node unless require_block
        nested_properties! node, space
      end

      def value!
        space = !str {ss}.empty?
        @use_property_exception ||= space || !tok?(IDENT)

        return true, Sass::Script::String.new("") if tok?(/\{/)
        # This is a bit of a dirty trick:
        # if the value is completely static,
        # we don't parse it at all, and instead return a plain old string
        # containing the value.
        # This results in a dramatic speed increase.
        if val = tok(STATIC_VALUE, true)
          return space, Sass::Script::String.new(val.strip)
        end
        return space, sass_script(:parse)
      end

      def nested_properties!(node, space)
        err(<<MESSAGE) unless space
Invalid CSS: a space is required between a property and its definition
when it has other properties nested beneath it.
MESSAGE

        @use_property_exception = true
        @expected = 'expression (e.g. 1px, bold) or "{"'
        block(node, :property)
      end

      def expr(allow_var = true)
        return unless t = term(allow_var)
        res = [t, str{ss}]

        while (o = operator) && (t = term(allow_var))
          res << o << t << str{ss}
        end

        res.flatten
      end

      def term(allow_var)
        if e = tok(NUMBER) ||
            interp_uri ||
            function(allow_var) ||
            interp_string ||
            tok(UNICODERANGE) ||
            interp_ident ||
            tok(HEXCOLOR) ||
            (allow_var && var_expr)
          return e
        end

        return unless op = tok(/[+-]/)
        @expected = "number or function"
        return [op, tok(NUMBER) || function(allow_var) ||
          (allow_var && var_expr) || expr!(:interpolation)]
      end

      def function(allow_var)
        return unless name = tok(FUNCTION)
        if name == "expression(" || name == "calc("
          str, _ = Sass::Shared.balance(@scanner, ?(, ?), 1)
          [name, str]
        else
          [name, str{ss}, expr(allow_var), tok!(/\)/)]
        end
      end

      def var_expr
        return unless tok(/\$/)
        line = @line
        var = Sass::Script::Variable.new(tok!(IDENT))
        var.line = line
        var
      end

      def interpolation
        return unless tok(INTERP_START)
        sass_script(:parse_interpolated)
      end

      def interp_string
        _interp_string(:double) || _interp_string(:single)
      end

      def interp_uri
        _interp_string(:uri)
      end

      def _interp_string(type)
        return unless start = tok(Sass::Script::Lexer::STRING_REGULAR_EXPRESSIONS[[type, false]])
        res = [start]

        mid_re = Sass::Script::Lexer::STRING_REGULAR_EXPRESSIONS[[type, true]]
        # @scanner[2].empty? means we've started an interpolated section
        while @scanner[2] == '#{'
          @scanner.pos -= 2 # Don't consume the #{
          res.last.slice!(-2..-1)
          res << expr!(:interpolation) << tok(mid_re)
        end
        res
      end

      def interp_ident(start = IDENT)
        return unless val = tok(start) || interpolation || tok(IDENT_HYPHEN_INTERP, true)
        res = [val]
        while val = tok(NAME) || interpolation
          res << val
        end
        res
      end

      def interp_ident_or_var
        (id = interp_ident) and return id
        (var = var_expr) and return [var]
      end

      def interp_name
        interp_ident NAME
      end

      def str
        @strs.push ""
        yield
        @strs.last
      ensure
        @strs.pop
      end

      def str?
        pos = @scanner.pos
        line = @line
        @strs.push ""
        throw_error {yield} && @strs.last
      rescue Sass::SyntaxError
        @scanner.pos = pos
        @line = line
        nil
      ensure
        @strs.pop
      end

      def node(node)
        node.line = @line
        node
      end

      @sass_script_parser = Class.new(Sass::Script::Parser)
      @sass_script_parser.send(:include, ScriptParser)
      # @private
      def self.sass_script_parser; @sass_script_parser; end

      def sass_script(*args)
        parser = self.class.sass_script_parser.new(@scanner, @line,
          @scanner.pos - (@scanner.string[0...@scanner.pos].rindex("\n") || 0))
        result = parser.send(*args)
        unless @strs.empty?
          # Convert to CSS manually so that comments are ignored.
          src = result.to_sass
          @strs.each {|s| s << src}
        end
        @line = parser.line
        result
      rescue Sass::SyntaxError => e
        throw(:_sass_parser_error, true) if @throw_error
        raise e
      end

      def merge(arr)
        arr && Sass::Util.merge_adjacent_strings([arr].flatten)
      end

      EXPR_NAMES = {
        :media_query => "media query (e.g. print, screen, print and screen)",
        :media_query_list => "media query (e.g. print, screen, print and screen)",
        :media_expr => "media expression (e.g. (min-device-width: 800px))",
        :pseudo_arg => "expression (e.g. fr, 2n+1)",
        :interp_ident => "identifier",
        :interp_name => "identifier",
        :qualified_name => "identifier",
        :expr => "expression (e.g. 1px, bold)",
        :_selector => "selector",
        :selector_comma_sequence => "selector",
        :simple_selector_sequence => "selector",
        :import_arg => "file to import (string or url())",
        :moz_document_function => "matching function (e.g. url-prefix(), domain())",
        :supports_condition => "@supports condition (e.g. (display: flexbox))",
        :supports_condition_in_parens => "@supports condition (e.g. (display: flexbox))",
      }

      TOK_NAMES = Sass::Util.to_hash(
        Sass::SCSS::RX.constants.map {|c| [Sass::SCSS::RX.const_get(c), c.downcase]}).
        merge(IDENT => "identifier", /[;}]/ => '";"')

      def tok?(rx)
        @scanner.match?(rx)
      end

      def expr!(name)
        (e = send(name)) && (return e)
        expected(EXPR_NAMES[name] || name.to_s)
      end

      def tok!(rx)
        (t = tok(rx)) && (return t)
        name = TOK_NAMES[rx]

        unless name
          # Display basic regexps as plain old strings
          string = rx.source.gsub(/\\(.)/, '\1')
          name = rx.source == Regexp.escape(string) ? string.inspect : rx.inspect
        end

        expected(name)
      end

      def expected(name)
        throw(:_sass_parser_error, true) if @throw_error
        self.class.expected(@scanner, @expected || name, @line)
      end

      def err(msg)
        throw(:_sass_parser_error, true) if @throw_error
        raise Sass::SyntaxError.new(msg, :line => @line)
      end

      def throw_error
        old_throw_error, @throw_error = @throw_error, false
        yield
      ensure
        @throw_error = old_throw_error
      end

      def catch_error(&block)
        old_throw_error, @throw_error = @throw_error, true
        pos = @scanner.pos
        line = @line
        expected = @expected
        if catch(:_sass_parser_error) {yield; false}
          @scanner.pos = pos
          @line = line
          @expected = expected
          {:pos => pos, :line => line, :expected => @expected, :block => block}
        end
      ensure
        @throw_error = old_throw_error
      end

      def rethrow(err)
        if @throw_error
          throw :_sass_parser_error, err
        else
          @scanner = Sass::Util::MultibyteStringScanner.new(@scanner.string)
          @scanner.pos = err[:pos]
          @line = err[:line]
          @expected = err[:expected]
          err[:block].call
        end
      end

      # @private
      def self.expected(scanner, expected, line)
        pos = scanner.pos

        after = scanner.string[0...pos]
        # Get rid of whitespace between pos and the last token,
        # but only if there's a newline in there
        after.gsub!(/\s*\n\s*$/, '')
        # Also get rid of stuff before the last newline
        after.gsub!(/.*\n/, '')
        after = "..." + after[-15..-1] if after.size > 18

        was = scanner.rest.dup
        # Get rid of whitespace between pos and the next token,
        # but only if there's a newline in there
        was.gsub!(/^\s*\n\s*/, '')
        # Also get rid of stuff after the next newline
        was.gsub!(/\n.*/, '')
        was = was[0...15] + "..." if was.size > 18

        raise Sass::SyntaxError.new(
          "Invalid CSS after \"#{after}\": expected #{expected}, was \"#{was}\"",
          :line => line)
      end

      # Avoid allocating lots of new strings for `#tok`.
      # This is important because `#tok` is called all the time.
      NEWLINE = "\n"

      def tok(rx, last_group_lookahead = false)
        res = @scanner.scan(rx)
        if res
          # This fixes https://github.com/nex3/sass/issues/104, which affects
          # Ruby 1.8.7 and REE. This fix is to replace the ?= zero-width
          # positive lookahead operator in the Regexp (which matches without
          # consuming the matched group), with a match that does consume the
          # group, but then rewinds the scanner and removes the group from the
          # end of the matched string. This fix makes the assumption that the
          # matched group will always occur at the end of the match.
		  if  last_group_lookahead 
			#RG IronRuby has the negative group index code wrong, so use regexp on 
			#RG the matched text to get the last group
			lastgroup = rx.match( @scanner.matched )[-1]
			if lastgroup
			  @scanner.pos -= lastgroup.length
			  res.slice!(-lastgroup.length..-1)
			end
          end
          @line += res.count(NEWLINE)
          @expected = nil
          if !@strs.empty? && rx != COMMENT && rx != SINGLE_LINE_COMMENT
            @strs.each {|s| s << res}
          end
          res
        end
      end
    end
  end
end
module Sass
  module Script
    # This is a subclass of {Lexer} for use in parsing plain CSS properties.
    #
    # @see Sass::SCSS::CssParser
    class CssLexer < Lexer
      private

      def token
        important || super
      end

      def string(re, *args)
        if re == :uri
          return unless uri = scan(URI)
          return [:string, Script::String.new(uri)]
        end

        return unless scan(STRING)
        [:string, Script::String.new((@scanner[1] || @scanner[2]).gsub(/\\(['"])/, '\1'), :string)]
      end

      def important
        return unless s = scan(IMPORTANT)
        [:raw, s]
      end
    end
  end
end

module Sass
  module Script
    # This is a subclass of {Parser} for use in parsing plain CSS properties.
    #
    # @see Sass::SCSS::CssParser
    class CssParser < Parser
      private

      # @private
      def lexer_class; CssLexer; end

      # We need a production that only does /,
      # since * and % aren't allowed in plain CSS
      production :div, :unary_plus, :div

      def string
        return number unless tok = try_tok(:string)
        return tok.value unless @lexer.peek && @lexer.peek.type == :begin_interpolation
      end

      # Short-circuit all the SassScript-only productions
      alias_method :interpolation, :space
      alias_method :or_expr, :div
      alias_method :unary_div, :ident
      alias_method :paren, :string
    end
  end
end

module Sass
  module SCSS
    # A parser for a static SCSS tree.
    # Parses with SCSS extensions, like nested rules and parent selectors,
    # but without dynamic SassScript.
    # This is useful for e.g. \{#parse\_selector parsing selectors}
    # after resolving the interpolation.
    class StaticParser < Parser
      # Parses the text as a selector.
      #
      # @param filename [String, nil] The file in which the selector appears,
      #   or nil if there is no such file.
      #   Used for error reporting.
      # @return [Selector::CommaSequence] The parsed selector
      # @raise [Sass::SyntaxError] if there's a syntax error in the selector
      def parse_selector
        init_scanner!
        seq = expr!(:selector_comma_sequence)
        expected("selector") unless @scanner.eos?
        seq.line = @line
        seq.filename = @filename
        seq
      end

      private

      def moz_document_function
        return unless val = tok(URI) || tok(URL_PREFIX) || tok(DOMAIN) ||
          function(!:allow_var)
        ss
        [val]
      end

      def variable; nil; end
      def script_value; nil; end
      def interpolation; nil; end
      def var_expr; nil; end
      def interp_string; s = tok(STRING) and [s]; end
      def interp_uri; s = tok(URI) and [s]; end
      def interp_ident(ident = IDENT); s = tok(ident) and [s]; end
      def use_css_import?; true; end

      def special_directive(name)
        return unless %w[media import charset -moz-document].include?(name)
        super
      end

      @sass_script_parser = Class.new(Sass::Script::CssParser)
      @sass_script_parser.send(:include, ScriptParser)
    end
  end
end

module Sass
  module SCSS
    # This is a subclass of {Parser} which only parses plain CSS.
    # It doesn't support any Sass extensions, such as interpolation,
    # parent references, nested selectors, and so forth.
    # It does support all the same CSS hacks as the SCSS parser, though.
    class CssParser < StaticParser
      private

      def placeholder_selector; nil; end
      def parent_selector; nil; end
      def interpolation; nil; end
      def use_css_import?; true; end

      def block_child(context)
        case context
        when :ruleset
          declaration
        when :stylesheet
          directive || ruleset
        when :directive
          directive || declaration_or_ruleset
        end
      end

      def nested_properties!(node, space)
        expected('expression (e.g. 1px, bold)');
      end

      @sass_script_parser = Class.new(Sass::Script::CssParser)
      @sass_script_parser.send(:include, ScriptParser)
    end
  end
end

module Sass
  # SCSS is the CSS syntax for Sass.
  # It parses into the same syntax tree as Sass,
  # and generates the same sort of output CSS.
  #
  # This module contains code for the parsing of SCSS.
  # The evaluation is handled by the broader {Sass} module.
  module SCSS; end
end
module Sass
  # An exception class that keeps track of
  # the line of the Sass template it was raised on
  # and the Sass file that was being parsed (if applicable).
  #
  # All Sass errors are raised as {Sass::SyntaxError}s.
  #
  # When dealing with SyntaxErrors,
  # it's important to provide filename and line number information.
  # This will be used in various error reports to users, including backtraces;
  # see \{#sass\_backtrace} for details.
  #
  # Some of this information is usually provided as part of the constructor.
  # New backtrace entries can be added with \{#add\_backtrace},
  # which is called when an exception is raised between files (e.g. with `@import`).
  #
  # Often, a chunk of code will all have similar backtrace information -
  # the same filename or even line.
  # It may also be useful to have a default line number set.
  # In those situations, the default values can be used
  # by omitting the information on the original exception,
  # and then calling \{#modify\_backtrace} in a wrapper `rescue`.
  # When doing this, be sure that all exceptions ultimately end up
  # with the information filled in.
  class SyntaxError < StandardError
    # The backtrace of the error within Sass files.
    # This is an array of hashes containing information for a single entry.
    # The hashes have the following keys:
    #
    # `:filename`
    # : The name of the file in which the exception was raised,
    #   or `nil` if no filename is available.
    #
    # `:mixin`
    # : The name of the mixin in which the exception was raised,
    #   or `nil` if it wasn't raised in a mixin.
    #
    # `:line`
    # : The line of the file on which the error occurred. Never nil.
    #
    # This information is also included in standard backtrace format
    # in the output of \{#backtrace}.
    #
    # @return [Aray<{Symbol => Object>}]
    attr_accessor :sass_backtrace

    # The text of the template where this error was raised.
    #
    # @return [String]
    attr_accessor :sass_template

    # @param msg [String] The error message
    # @param attrs [{Symbol => Object}] The information in the backtrace entry.
    #   See \{#sass\_backtrace}
    def initialize(msg, attrs = {})
      @message = msg
      @sass_backtrace = []
      add_backtrace(attrs)
    end

    # The name of the file in which the exception was raised.
    # This could be `nil` if no filename is available.
    #
    # @return [String, nil]
    def sass_filename
      sass_backtrace.first[:filename]
    end

    # The name of the mixin in which the error occurred.
    # This could be `nil` if the error occurred outside a mixin.
    #
    # @return [Fixnum]
    def sass_mixin
      sass_backtrace.first[:mixin]
    end

    # The line of the Sass template on which the error occurred.
    #
    # @return [Fixnum]
    def sass_line
      sass_backtrace.first[:line]
    end

    # Adds an entry to the exception's Sass backtrace.
    #
    # @param attrs [{Symbol => Object}] The information in the backtrace entry.
    #   See \{#sass\_backtrace}
    def add_backtrace(attrs)
      sass_backtrace << attrs.reject {|k, v| v.nil?}
    end

    # Modify the top Sass backtrace entries
    # (that is, the most deeply nested ones)
    # to have the given attributes.
    #
    # Specifically, this goes through the backtrace entries
    # from most deeply nested to least,
    # setting the given attributes for each entry.
    # If an entry already has one of the given attributes set,
    # the pre-existing attribute takes precedence
    # and is not used for less deeply-nested entries
    # (even if they don't have that attribute set).
    #
    # @param attrs [{Symbol => Object}] The information to add to the backtrace entry.
    #   See \{#sass\_backtrace}
    def modify_backtrace(attrs)
      attrs = attrs.reject {|k, v| v.nil?}
      # Move backwards through the backtrace
      (0...sass_backtrace.size).to_a.reverse.each do |i|
        entry = sass_backtrace[i]
        sass_backtrace[i] = attrs.merge(entry)
        attrs.reject! {|k, v| entry.include?(k)}
        break if attrs.empty?
      end
    end

    # @return [String] The error message
    def to_s
      @message
    end

    # Returns the standard exception backtrace,
    # including the Sass backtrace.
    #
    # @return [Array<String>]
    def backtrace
      return nil if super.nil?
      return super if sass_backtrace.all? {|h| h.empty?}
      sass_backtrace.map do |h|
        "#{h[:filename] || "(sass)"}:#{h[:line]}" +
          (h[:mixin] ? ":in `#{h[:mixin]}'" : "")
      end + super
    end

    # Returns a string representation of the Sass backtrace.
    #
    # @param default_filename [String] The filename to use for unknown files
    # @see #sass_backtrace
    # @return [String]
    def sass_backtrace_str(default_filename = "an unknown file")
      lines = self.message.split("\n")
      msg = lines[0] + lines[1..-1].
        map {|l| "\n" + (" " * "Syntax error: ".size) + l}.join
      "Syntax error: #{msg}" +
        Sass::Util.enum_with_index(sass_backtrace).map do |entry, i|
        "\n        #{i == 0 ? "on" : "from"} line #{entry[:line]}" +
          " of #{entry[:filename] || default_filename}" +
          (entry[:mixin] ? ", in `#{entry[:mixin]}'" : "")
      end.join
    end

    class << self
      # Returns an error report for an exception in CSS format.
      #
      # @param e [Exception]
      # @param options [{Symbol => Object}] The options passed to {Sass::Engine#initialize}
      # @return [String] The error report
      # @raise [Exception] `e`, if the
      #   {file:SASS_REFERENCE.md#full_exception-option `:full_exception`} option
      #   is set to false.
      def exception_to_css(e, options)
        raise e unless options[:full_exception]

        header = header_string(e, options)

        <<END
/*
#{header.gsub("*/", "*\\/")}

Backtrace:\n#{e.backtrace.join("\n").gsub("*/", "*\\/")}
*/
body:before {
  white-space: pre;
  font-family: monospace;
  content: "#{header.gsub('"', '\"').gsub("\n", '\\A ')}"; }
END
      end

      private

      def header_string(e, options)
        unless e.is_a?(Sass::SyntaxError) && e.sass_line && e.sass_template
          return "#{e.class}: #{e.message}"
        end

        line_offset = options[:line] || 1
        line_num = e.sass_line + 1 - line_offset
        min = [line_num - 6, 0].max
        section = e.sass_template.rstrip.split("\n")[min ... line_num + 5]
        return e.sass_backtrace_str if section.nil? || section.empty?

        e.sass_backtrace_str + "\n\n" + Sass::Util.enum_with_index(section).
          map {|line, i| "#{line_offset + min + i}: #{line}"}.join("\n")
      end
    end
  end

  # The class for Sass errors that are raised due to invalid unit conversions
  # in SassScript.
  class UnitConversionError < SyntaxError; end
end
module Sass
  # Sass importers are in charge of taking paths passed to `@import`
  # and finding the appropriate Sass code for those paths.
  # By default, this code is always loaded from the filesystem,
  # but importers could be added to load from a database or over HTTP.
  #
  # Each importer is in charge of a single load path
  # (or whatever the corresponding notion is for the backend).
  # Importers can be placed in the {file:SASS_REFERENCE.md#load_paths-option `:load_paths` array}
  # alongside normal filesystem paths.
  #
  # When resolving an `@import`, Sass will go through the load paths
  # looking for an importer that successfully imports the path.
  # Once one is found, the imported file is used.
  #
  # User-created importers must inherit from {Importers::Base}.
  module Importers
  end
end

module Sass
  module Importers
    # The abstract base class for Sass importers.
    # All importers should inherit from this.
    #
    # At the most basic level, an importer is given a string
    # and must return a {Sass::Engine} containing some Sass code.
    # This string can be interpreted however the importer wants;
    # however, subclasses are encouraged to use the URI format
    # for pathnames.
    #
    # Importers that have some notion of "relative imports"
    # should take a single load path in their constructor,
    # and interpret paths as relative to that.
    # They should also implement the \{#find\_relative} method.
    #
    # Importers should be serializable via `Marshal.dump`.
    # In addition to the standard `_dump` and `_load` methods,
    # importers can define `_before_dump`, `_after_dump`, `_around_dump`,
    # and `_after_load` methods as per {Sass::Util#dump} and {Sass::Util#load}.
    #
    # @abstract
    class Base

      # Find a Sass file relative to another file.
      # Importers without a notion of "relative paths"
      # should just return nil here.
      #
      # If the importer does have a notion of "relative paths",
      # it should ignore its load path during this method.
      #
      # See \{#find} for important information on how this method should behave.
      #
      # The `:filename` option passed to the returned {Sass::Engine}
      # should be of a format that could be passed to \{#find}.
      #
      # @param uri [String] The URI to import. This is not necessarily relative,
      #   but this method should only return true if it is.
      # @param base [String] The base filename. If `uri` is relative,
      #   it should be interpreted as relative to `base`.
      #   `base` is guaranteed to be in a format importable by this importer.
      # @param options [{Symbol => Object}] Options for the Sass file
      #   containing the `@import` that's currently being resolved.
      # @return [Sass::Engine, nil] An Engine containing the imported file,
      #   or nil if it couldn't be found or was in the wrong format.
      def find_relative(uri, base, options)
        Sass::Util.abstract(self)
      end

      # Find a Sass file, if it exists.
      #
      # This is the primary entry point of the Importer.
      # It corresponds directly to an `@import` statement in Sass.
      # It should do three basic things:
      #
      # * Determine if the URI is in this importer's format.
      #   If not, return nil.
      # * Determine if the file indicated by the URI actually exists and is readable.
      #   If not, return nil.
      # * Read the file and place the contents in a {Sass::Engine}.
      #   Return that engine.
      #
      # If this importer's format allows for file extensions,
      # it should treat them the same way as the default {Filesystem} importer.
      # If the URI explicitly has a `.sass` or `.scss` filename,
      # the importer should look for that exact file
      # and import it as the syntax indicated.
      # If it doesn't exist, the importer should return nil.
      #
      # If the URI doesn't have either of these extensions,
      # the importer should look for files with the extensions.
      # If no such files exist, it should return nil.
      #
      # The {Sass::Engine} to be returned should be passed `options`,
      # with a few modifications. `:syntax` should be set appropriately,
      # `:filename` should be set to `uri`,
      # and `:importer` should be set to this importer.
      #
      # @param uri [String] The URI to import.
      # @param options [{Symbol => Object}] Options for the Sass file
      #   containing the `@import` that's currently being resolved.
      #   This is safe for subclasses to modify destructively.
      #   Callers should only pass in a value they don't mind being destructively modified.
      # @return [Sass::Engine, nil] An Engine containing the imported file,
      #   or nil if it couldn't be found or was in the wrong format.
      def find(uri, options)
        Sass::Util.abstract(self)
      end

      # Returns the time the given Sass file was last modified.
      #
      # If the given file has been deleted or the time can't be accessed
      # for some other reason, this should return nil.
      #
      # @param uri [String] The URI of the file to check.
      #   Comes from a `:filename` option set on an engine returned by this importer.
      # @param options [{Symbol => Objet}] Options for the Sass file
      #   containing the `@import` currently being checked.
      # @return [Time, nil]
      def mtime(uri, options)
        Sass::Util.abstract(self)
      end

      # Get the cache key pair for the given Sass URI.
      # The URI need not be checked for validity.
      #
      # The only strict requirement is that the returned pair of strings
      # uniquely identify the file at the given URI.
      # However, the first component generally corresponds roughly to the directory,
      # and the second to the basename, of the URI.
      #
      # Note that keys must be unique *across importers*.
      # Thus it's probably a good idea to include the importer name
      # at the beginning of the first component.
      #
      # @param uri [String] A URI known to be valid for this importer.
      # @param options [{Symbol => Object}] Options for the Sass file
      #   containing the `@import` currently being checked.
      # @return [(String, String)] The key pair which uniquely identifies
      #   the file at the given URI.
      def key(uri, options)
        Sass::Util.abstract(self)
      end

      # A string representation of the importer.
      # Should be overridden by subclasses.
      #
      # This is used to help debugging,
      # and should usually just show the load path encapsulated by this importer.
      #
      # @return [String]
      def to_s
        Sass::Util.abstract(self)
      end
    end
  end
end

      

module Sass
  module Importers
    # The default importer, used for any strings found in the load path.
    # Simply loads Sass files from the filesystem using the default logic.
    class Filesystem < Base

      attr_accessor :root

      # Creates a new filesystem importer that imports files relative to a given path.
      #
      # @param root [String] The root path.
      #   This importer will import files relative to this path.
      def initialize(root)
        @root = File.expand_path(root)
        @same_name_warnings = Set.new
      end

      # @see Base#find_relative
      def find_relative(name, base, options)
        _find(File.dirname(base), name, options)
      end

      # @see Base#find
      def find(name, options)
        _find(@root, name, options)
      end

      # @see Base#mtime
      def mtime(name, options)
        file, _ = Sass::Util.destructure(find_real_file(@root, name, options))
        File.mtime(file) if file
      rescue Errno::ENOENT
        nil
      end

      # @see Base#key
      def key(name, options)
        [self.class.name + ":" + File.dirname(File.expand_path(name)),
          File.basename(name)]
      end

      # @see Base#to_s
      def to_s
        @root
      end

      def hash
        @root.hash
      end

      def eql?(other)
        root.eql?(other.root)
      end

      protected

      # If a full uri is passed, this removes the root from it
      # otherwise returns the name unchanged
      def remove_root(name)
        if name.index(@root + "/") == 0
          name[(@root.length + 1)..-1]
        else
          name
        end
      end

      # A hash from file extensions to the syntaxes for those extensions.
      # The syntaxes must be `:sass` or `:scss`.
      #
      # This can be overridden by subclasses that want normal filesystem importing
      # with unusual extensions.
      #
      # @return [{String => Symbol}]
      def extensions
        {'sass' => :sass, 'scss' => :scss}
      end

      # Given an `@import`ed path, returns an array of possible
      # on-disk filenames and their corresponding syntaxes for that path.
      #
      # @param name [String] The filename.
      # @return [Array(String, Symbol)] An array of pairs.
      #   The first element of each pair is a filename to look for;
      #   the second element is the syntax that file would be in (`:sass` or `:scss`).
      def possible_files(name)
        name = escape_glob_characters(name)
        dirname, basename, extname = split(name)
        sorted_exts = extensions.sort
        syntax = extensions[extname]

        if syntax
          ret = [["#{dirname}/{_,}#{basename}.#{extensions.invert[syntax]}", syntax]]
        else
          ret = sorted_exts.map {|ext, syn| ["#{dirname}/{_,}#{basename}.#{ext}", syn]}
        end

        # JRuby chokes when trying to import files from JARs when the path starts with './'.
        ret.map {|f, s| [f.sub(%r{^\./}, ''), s]}
      end

      def escape_glob_characters(name)
        name.gsub(/[\*\[\]\{\}\?]/) do |char|
          "\\#{char}"
        end
      end

      REDUNDANT_DIRECTORY = %r{#{Regexp.escape(File::SEPARATOR)}\.#{Regexp.escape(File::SEPARATOR)}}
      # Given a base directory and an `@import`ed name,
      # finds an existant file that matches the name.
      #
      # @param dir [String] The directory relative to which to search.
      # @param name [String] The filename to search for.
      # @return [(String, Symbol)] A filename-syntax pair.
      def find_real_file(dir, name, options)
        # on windows 'dir' can be in native File::ALT_SEPARATOR form
        dir = dir.gsub(File::ALT_SEPARATOR, File::SEPARATOR) unless File::ALT_SEPARATOR.nil?

        found = possible_files(remove_root(name)).map do |f, s|
          path = (dir == "." || Pathname.new(f).absolute?) ? f : "#{dir}/#{f}"
          Dir[path].map do |full_path|
            full_path.gsub!(REDUNDANT_DIRECTORY, File::SEPARATOR)
            [full_path, s]
          end
        end
        found = Sass::Util.flatten(found, 1)
        return if found.empty?

        if found.size > 1 && !@same_name_warnings.include?(found.first.first)
          found.each {|(f, _)| @same_name_warnings << f}
          relative_to = Pathname.new(dir)
          if options[:_line]
            # If _line exists, we're here due to an actual import in an
            # import_node and we want to print a warning for a user writing an
            # ambiguous import.
            candidates = found.map {|(f, _)| "    " + Pathname.new(f).relative_path_from(relative_to).to_s}.join("\n")
            Sass::Util.sass_warn <<WARNING
WARNING: On line #{options[:_line]}#{" of #{options[:filename]}" if options[:filename]}:
  It's not clear which file to import for '@import "#{name}"'.
  Candidates:
#{candidates}
  For now I'll choose #{File.basename found.first.first}.
  This will be an error in future versions of Sass.
WARNING
          else
            # Otherwise, we're here via StalenessChecker, and we want to print a
            # warning for a user running `sass --watch` with two ambiguous files.
            candidates = found.map {|(f, _)| "    " + File.basename(f)}.join("\n")
            Sass::Util.sass_warn <<WARNING
WARNING: In #{File.dirname(name)}:
  There are multiple files that match the name "#{File.basename(name)}":
#{candidates}
WARNING
          end
        end
        found.first
      end

      # Splits a filename into three parts, a directory part, a basename, and an extension
      # Only the known extensions returned from the extensions method will be recognized as such.
      def split(name)
        extension = nil
        dirname, basename = File.dirname(name), File.basename(name)
        if basename =~ /^(.*)\.(#{extensions.keys.map{|e| Regexp.escape(e)}.join('|')})$/
          basename = $1
          extension = $2
        end
        [dirname, basename, extension]
      end

      private

      def _find(dir, name, options)
        full_filename, syntax = Sass::Util.destructure(find_real_file(dir, name, options))
        return unless full_filename && File.readable?(full_filename)

        options[:syntax] = syntax
        options[:filename] = full_filename
        options[:importer] = self
        Sass::Engine.new(File.read(full_filename), options)
      end

      def join(base, path)
        Pathname.new(base).join(path).to_s
      end
    end
  end
end
module Sass
  # This module contains functionality that's shared between Haml and Sass.
  module Shared
    extend self

    # Scans through a string looking for the interoplation-opening `#{`
    # and, when it's found, yields the scanner to the calling code
    # so it can handle it properly.
    #
    # The scanner will have any backslashes immediately in front of the `#{`
    # as the second capture group (`scan[2]`),
    # and the text prior to that as the first (`scan[1]`).
    #
    # @yieldparam scan [StringScanner] The scanner scanning through the string
    # @return [String] The text remaining in the scanner after all `#{`s have been processed
    def handle_interpolation(str)
      scan = Sass::Util::MultibyteStringScanner.new(str)
      yield scan while scan.scan(/(.*?)(\\*)\#\{/m)
      scan.rest
    end

    # Moves a scanner through a balanced pair of characters.
    # For example:
    #
    #     Foo (Bar (Baz bang) bop) (Bang (bop bip))
    #     ^                       ^
    #     from                    to
    #
    # @param scanner [StringScanner] The string scanner to move
    # @param start [Character] The character opening the balanced pair.
    #   A `Fixnum` in 1.8, a `String` in 1.9
    # @param finish [Character] The character closing the balanced pair.
    #   A `Fixnum` in 1.8, a `String` in 1.9
    # @param count [Fixnum] The number of opening characters matched
    #   before calling this method
    # @return [(String, String)] The string matched within the balanced pair
    #   and the rest of the string.
    #   `["Foo (Bar (Baz bang) bop)", " (Bang (bop bip))"]` in the example above.
    def balance(scanner, start, finish, count = 0)
      str = ''
      scanner = Sass::Util::MultibyteStringScanner.new(scanner) unless scanner.is_a? StringScanner
      regexp = Regexp.new("(.*?)[\\#{start.chr}\\#{finish.chr}]", Regexp::MULTILINE)
      while scanner.scan(regexp)
        str << scanner.matched
        count += 1 if scanner.matched[-1] == start
        count -= 1 if scanner.matched[-1] == finish
        return [str.strip, scanner.rest] if count == 0
      end
    end

    # Formats a string for use in error messages about indentation.
    #
    # @param indentation [String] The string used for indentation
    # @param was [Boolean] Whether or not to add `"was"` or `"were"`
    #   (depending on how many characters were in `indentation`)
    # @return [String] The name of the indentation (e.g. `"12 spaces"`, `"1 tab"`)
    def human_indentation(indentation, was = false)
      if !indentation.include?(?\t)
        noun = 'space'
      elsif !indentation.include?(?\s)
        noun = 'tab'
      else
        return indentation.inspect + (was ? ' was' : '')
      end

      singular = indentation.length == 1
      if was
        was = singular ? ' was' : ' were'
      else
        was = ''
      end

      "#{indentation.length} #{noun}#{'s' unless singular}#{was}"
    end
  end
end
# A namespace for the `@media` query parse tree.
module Sass::Media
  # A comma-separated list of queries.
  #
  #   media_query [ ',' S* media_query ]*
  class QueryList
    # The queries contained in this list.
    #
    # @return [Array<Query>]
    attr_accessor :queries

    # @param queries [Array<Query>] See \{#queries}
    def initialize(queries)
      @queries = queries
    end

    # Merges this query list with another. The returned query list
    # queries for the intersection between the two inputs.
    #
    # Both query lists should be resolved.
    #
    # @param other [QueryList]
    # @return [QueryList?] The merged list, or nil if there is no intersection.
    def merge(other)
      new_queries = queries.map {|q1| other.queries.map {|q2| q1.merge(q2)}}.flatten.compact
      return if new_queries.empty?
      QueryList.new(new_queries)
    end

    # Returns the CSS for the media query list.
    #
    # @return [String]
    def to_css
      queries.map {|q| q.to_css}.join(', ')
    end

    # Returns the Sass/SCSS code for the media query list.
    #
    # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize}).
    # @return [String]
    def to_src(options)
      queries.map {|q| q.to_src(options)}.join(', ')
    end

    # Returns a representation of the query as an array of strings and
    # potentially {Sass::Script::Node}s (if there's interpolation in it). When
    # the interpolation is resolved and the strings are joined together, this
    # will be the string representation of this query.
    #
    # @return [Array<String, Sass::Script::Node>]
    def to_a
      Sass::Util.intersperse(queries.map {|q| q.to_a}, ', ').flatten
    end

    # Returns a deep copy of this query list and all its children.
    #
    # @return [QueryList]
    def deep_copy
      QueryList.new(queries.map {|q| q.deep_copy})
    end
  end

  # A single media query.
  #
  #   [ [ONLY | NOT]? S* media_type S* | expression ] [ AND S* expression ]*
  class Query
    # The modifier for the query.
    #
    # When parsed as Sass code, this contains strings and SassScript nodes. When
    # parsed as CSS, it contains a single string (accessible via
    # \{#resolved_modifier}).
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :modifier

    # The type of the query (e.g. `"screen"` or `"print"`).
    #
    # When parsed as Sass code, this contains strings and SassScript nodes. When
    # parsed as CSS, it contains a single string (accessible via
    # \{#resolved_type}).
    #
    # @return [Array<String, Sass::Script::Node>]
    attr_accessor :type

    # The trailing expressions in the query.
    #
    # When parsed as Sass code, each expression contains strings and SassScript
    # nodes. When parsed as CSS, each one contains a single string.
    #
    # @return [Array<Array<String, Sass::Script::Node>>]
    attr_accessor :expressions

    # @param modifier [Array<String, Sass::Script::Node>] See \{#modifier}
    # @param type [Array<String, Sass::Script::Node>] See \{#type}
    # @param expressions [Array<Array<String, Sass::Script::Node>>] See \{#expressions}
    def initialize(modifier, type, expressions)
      @modifier = modifier
      @type = type
      @expressions = expressions
    end

    # See \{#modifier}.
    # @return [String]
    def resolved_modifier
      # modifier should contain only a single string
      modifier.first || ''
    end

    # See \{#type}.
    # @return [String]
    def resolved_type
      # type should contain only a single string
      type.first || ''
    end

    # Merges this query with another. The returned query queries for
    # the intersection between the two inputs.
    #
    # Both queries should be resolved.
    #
    # @param other [Query]
    # @return [Query?] The merged query, or nil if there is no intersection.
    def merge(other)
      m1, t1 = resolved_modifier.downcase, resolved_type.downcase
      m2, t2 = other.resolved_modifier.downcase, other.resolved_type.downcase
      t1 = t2 if t1.empty?
      t2 = t1 if t2.empty?
      if ((m1 == 'not') ^ (m2 == 'not'))
        return if t1 == t2
        type = m1 == 'not' ? t2 : t1
        mod = m1 == 'not' ? m2 : m1
      elsif m1 == 'not' && m2 == 'not'
        # CSS has no way of representing "neither screen nor print"
        return unless t1 == t2
        type = t1
        mod = 'not'
      elsif t1 != t2
        return
      else # t1 == t2, neither m1 nor m2 are "not"
        type = t1
        mod = m1.empty? ? m2 : m1
      end
      return Query.new([mod], [type], other.expressions + expressions)
    end

    # Returns the CSS for the media query.
    #
    # @return [String]
    def to_css
      css = ''
      css << resolved_modifier
      css << ' ' unless resolved_modifier.empty?
      css << resolved_type
      css << ' and ' unless resolved_type.empty? || expressions.empty?
      css << expressions.map do |e|
        # It's possible for there to be script nodes in Expressions even when
        # we're converting to CSS in the case where we parsed the document as
        # CSS originally (as in css_test.rb).
        e.map {|c| c.is_a?(Sass::Script::Node) ? c.to_sass : c.to_s}.join
      end.join(' and ')
      css
    end

    # Returns the Sass/SCSS code for the media query.
    #
    # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize}).
    # @return [String]
    def to_src(options)
      src = ''
      src << Sass::Media._interp_to_src(modifier, options)
      src << ' ' unless modifier.empty?
      src << Sass::Media._interp_to_src(type, options)
      src << ' and ' unless type.empty? || expressions.empty?
      src << expressions.map do |e|
        Sass::Media._interp_to_src(e, options)
      end.join(' and ')
      src
    end

    # @see \{MediaQuery#to\_a}
    def to_a
      res = []
      res += modifier
      res << ' ' unless modifier.empty?
      res += type
      res << ' and ' unless type.empty? || expressions.empty?
      res += Sass::Util.intersperse(expressions, ' and ').flatten
      res
    end

    # Returns a deep copy of this query and all its children.
    #
    # @return [Query]
    def deep_copy
      Query.new(
        modifier.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c},
        type.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c},
        expressions.map {|e| e.map {|c| c.is_a?(Sass::Script::Node) ? c.deep_copy : c}})
    end
  end

  # Converts an interpolation array to source.
  #
  # @param [Array<String, Sass::Script::Node>] The interpolation array to convert.
  # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize}).
  # @return [String]
  def self._interp_to_src(interp, options)
    interp.map do |r|
      next r if r.is_a?(String)
      "\#{#{r.to_sass(options)}}"
    end.join
  end
end
# A namespace for the `@supports` condition parse tree.
module Sass::Supports
  # The abstract superclass of all Supports conditions.
  class Condition
    # Runs the SassScript in the supports condition.
    #
    # @param env [Sass::Environment] The environment in which to run the script.
    def perform(environment); Sass::Util.abstract(self); end

    # Returns the CSS for this condition.
    #
    # @return [String]
    def to_css; Sass::Util.abstract(self); end

    # Returns the Sass/CSS code for this condition.
    #
    # @param options [{Symbol => Object}] An options hash (see {Sass::CSS#initialize}).
    # @return [String]
    def to_src(options); Sass::Util.abstract(self); end

    # Returns a deep copy of this condition and all its children.
    #
    # @return [Condition]
    def deep_copy; Sass::Util.abstract(self); end

    # Sets the options hash for the script nodes in the supports condition.
    #
    # @param options [{Symbol => Object}] The options has to set.
    def options=(options); Sass::Util.abstract(self); end
  end

  # An operator condition (e.g. `CONDITION1 and CONDITION2`).
  class Operator < Condition
    # The left-hand condition.
    #
    # @return [Sass::Supports::Condition]
    attr_accessor :left

    # The right-hand condition.
    #
    # @return [Sass::Supports::Condition]
    attr_accessor :right

    # The operator ("and" or "or").
    #
    # @return [String]
    attr_accessor :op

    def initialize(left, right, op)
      @left = left
      @right = right
      @op = op
    end

    def perform(env)
      @left.perform(env)
      @right.perform(env)
    end

    def to_css
      "#{left_parens @left.to_css} #{op} #{right_parens @right.to_css}"
    end

    def to_src(options)
      "#{left_parens @left.to_src(options)} #{op} #{right_parens @right.to_src(options)}"
    end

    def deep_copy
      copy = dup
      copy.left = @left.deep_copy
      copy.right = @right.deep_copy
      copy
    end

    def options=(options)
      @left.options = options
      @right.options = options
    end

    private

    def left_parens(str)
      return "(#{str})" if @left.is_a?(Negation)
      return str
    end

    def right_parens(str)
      return "(#{str})" if @right.is_a?(Negation) || @right.is_a?(Operator)
      return str
    end
  end

  # A negation condition (`not CONDITION`).
  class Negation < Condition
    # The condition being negated.
    #
    # @return [Sass::Supports::Condition]
    attr_accessor :condition

    def initialize(condition)
      @condition = condition
    end

    def perform(env)
      @condition.perform(env)
    end

    def to_css
      "not #{parens @condition.to_css}"
    end

    def to_src(options)
      "not #{parens @condition.to_src(options)}"
    end

    def deep_copy
      copy = dup
      copy.condition = condition.deep_copy
      copy
    end

    def options=(options)
      condition.options = options
    end

    private

    def parens(str)
      return "(#{str})" if @condition.is_a?(Negation) || @condition.is_a?(Operator)
      return str
    end
  end

  # A declaration condition (e.g. `(feature: value)`).
  class Declaration < Condition
    # The feature name.
    #
    # @param [Sass::Script::Node]
    attr_accessor :name

    # The name of the feature after any SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_name

    # The feature value.
    #
    # @param [Sass::Script::Node]
    attr_accessor :value

    # The value of the feature after any SassScript has been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_value

    def initialize(name, value)
      @name = name
      @value = value
    end

    def perform(env)
      @resolved_name = name.perform(env)
      @resolved_value = value.perform(env)
    end

    def to_css
      "(#{@resolved_name}: #{@resolved_value})"
    end

    def to_src(options)
      "(#{@name.to_sass(options)}: #{@value.to_sass(options)})"
    end

    def deep_copy
      copy = dup
      copy.name = @name.deep_copy
      copy.value = @value.deep_copy
      copy
    end

    def options=(options)
      @name.options = options
      @value.options = options
    end
  end

  # An interpolation condition (e.g. `#{$var}`).
  class Interpolation < Condition
    # The SassScript expression in the interpolation.
    #
    # @param [Sass::Script::Node]
    attr_accessor :value

    # The value of the expression after it's been resolved.
    # Only set once \{Tree::Visitors::Perform} has been run.
    #
    # @return [String]
    attr_accessor :resolved_value

    def initialize(value)
      @value = value
    end

    def perform(env)
      val = value.perform(env)
      @resolved_value = val.is_a?(Sass::Script::String) ? val.value : val.to_s
    end

    def to_css
      @resolved_value
    end

    def to_src(options)
      "\#{#{@value.to_sass(options)}}"
    end

    def deep_copy
      copy = dup
      copy.value = @value.deep_copy
      copy
    end

    def options=(options)
      @value.options = options
    end
  end
end

module Sass

  # A Sass mixin or function.
  #
  # `name`: `String`
  # : The name of the mixin/function.
  #
  # `args`: `Array<(Script::Node, Script::Node)>`
  # : The arguments for the mixin/function.
  #   Each element is a tuple containing the variable node of the argument
  #   and the parse tree for the default value of the argument.
  #
  # `splat`: `Script::Node?`
  # : The variable node of the splat argument for this callable, or null.
  #
  # `environment`: {Sass::Environment}
  # : The environment in which the mixin/function was defined.
  #   This is captured so that the mixin/function can have access
  #   to local variables defined in its scope.
  #
  # `tree`: `Array<Tree::Node>`
  # : The parse tree for the mixin/function.
  #
  # `has_content`: `Boolean`
  # : Whether the callable accepts a content block.
  #
  # `type`: `String`
  # : The user-friendly name of the type of the callable.
  Callable = Struct.new(:name, :args, :splat, :environment, :tree, :has_content, :type)

  # This class handles the parsing and compilation of the Sass template.
  # Example usage:
  #
  #     template = File.load('stylesheets/sassy.sass')
  #     sass_engine = Sass::Engine.new(template)
  #     output = sass_engine.render
  #     puts output
  class Engine
    include Sass::Util

    # A line of Sass code.
    #
    # `text`: `String`
    # : The text in the line, without any whitespace at the beginning or end.
    #
    # `tabs`: `Fixnum`
    # : The level of indentation of the line.
    #
    # `index`: `Fixnum`
    # : The line number in the original document.
    #
    # `offset`: `Fixnum`
    # : The number of bytes in on the line that the text begins.
    #   This ends up being the number of bytes of leading whitespace.
    #
    # `filename`: `String`
    # : The name of the file in which this line appeared.
    #
    # `children`: `Array<Line>`
    # : The lines nested below this one.
    #
    # `comment_tab_str`: `String?`
    # : The prefix indentation for this comment, if it is a comment.
    class Line < Struct.new(:text, :tabs, :index, :offset, :filename, :children, :comment_tab_str)
      def comment?
        text[0] == COMMENT_CHAR && (text[1] == SASS_COMMENT_CHAR || text[1] == CSS_COMMENT_CHAR)
      end
    end

    # The character that begins a CSS property.
    PROPERTY_CHAR  = ?:

    # The character that designates the beginning of a comment,
    # either Sass or CSS.
    COMMENT_CHAR = ?/

    # The character that follows the general COMMENT_CHAR and designates a Sass comment,
    # which is not output as a CSS comment.
    SASS_COMMENT_CHAR = ?/

    # The character that indicates that a comment allows interpolation
    # and should be preserved even in `:compressed` mode.
    SASS_LOUD_COMMENT_CHAR = ?!

    # The character that follows the general COMMENT_CHAR and designates a CSS comment,
    # which is embedded in the CSS document.
    CSS_COMMENT_CHAR = ?*

    # The character used to denote a compiler directive.
    DIRECTIVE_CHAR = ?@

    # Designates a non-parsed rule.
    ESCAPE_CHAR    = ?\\

    # Designates block as mixin definition rather than CSS rules to output
    MIXIN_DEFINITION_CHAR = ?=

    # Includes named mixin declared using MIXIN_DEFINITION_CHAR
    MIXIN_INCLUDE_CHAR    = ?+

    # The regex that matches and extracts data from
    # properties of the form `:name prop`.
    PROPERTY_OLD = /^:([^\s=:"]+)\s*(?:\s+|$)(.*)/

    # The default options for Sass::Engine.
    # @api public
    DEFAULT_OPTIONS = {
      :style => :nested,
      :load_paths => ['.'],
      :cache => true,
      :cache_location => './.sass-cache',
      :syntax => :sass,
      :filesystem_importer => Sass::Importers::Filesystem
    }.freeze

    # Converts a Sass options hash into a standard form, filling in
    # default values and resolving aliases.
    #
    # @param options [{Symbol => Object}] The options hash;
    #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
    # @return [{Symbol => Object}] The normalized options hash.
    # @private
    def self.normalize_options(options)
      options = DEFAULT_OPTIONS.merge(options.reject {|k, v| v.nil?})

      # If the `:filename` option is passed in without an importer,
      # assume it's using the default filesystem importer.
      options[:importer] ||= options[:filesystem_importer].new(".") if options[:filename]

      # Tracks the original filename of the top-level Sass file
      options[:original_filename] ||= options[:filename]

      options[:cache_store] ||= Sass::CacheStores::Chain.new(
        Sass::CacheStores::Memory.new, Sass::CacheStores::Filesystem.new(options[:cache_location]))
      # Support both, because the docs said one and the other actually worked
      # for quite a long time.
      options[:line_comments] ||= options[:line_numbers]

      options[:load_paths] = (options[:load_paths] + Sass.load_paths).map do |p|
        next p unless p.is_a?(String) || (defined?(Pathname) && p.is_a?(Pathname))
        options[:filesystem_importer].new(p.to_s)
      end

      # Backwards compatibility
      options[:property_syntax] ||= options[:attribute_syntax]
      case options[:property_syntax]
      when :alternate; options[:property_syntax] = :new
      when :normal; options[:property_syntax] = :old
      end

      options
    end

    # Returns the {Sass::Engine} for the given file.
    # This is preferable to Sass::Engine.new when reading from a file
    # because it properly sets up the Engine's metadata,
    # enables parse-tree caching,
    # and infers the syntax from the filename.
    #
    # @param filename [String] The path to the Sass or SCSS file
    # @param options [{Symbol => Object}] The options hash;
    #   See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    # @return [Sass::Engine] The Engine for the given Sass or SCSS file.
    # @raise [Sass::SyntaxError] if there's an error in the document.
    def self.for_file(filename, options)
      had_syntax = options[:syntax]

      if had_syntax
        # Use what was explicitly specificed
      elsif filename =~ /\.scss$/
        options.merge!(:syntax => :scss)
      elsif filename =~ /\.sass$/
        options.merge!(:syntax => :sass)
      end

      Sass::Engine.new(File.read(filename), options.merge(:filename => filename))
    end

    # The options for the Sass engine.
    # See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    #
    # @return [{Symbol => Object}]
    attr_reader :options

    # Creates a new Engine. Note that Engine should only be used directly
    # when compiling in-memory Sass code.
    # If you're compiling a single Sass file from the filesystem,
    # use \{Sass::Engine.for\_file}.
    # If you're compiling multiple files from the filesystem,
    # use {Sass::Plugin}.
    #
    # @param template [String] The Sass template.
    #   This template can be encoded using any encoding
    #   that can be converted to Unicode.
    #   If the template contains an `@charset` declaration,
    #   that overrides the Ruby encoding
    #   (see {file:SASS_REFERENCE.md#encodings the encoding documentation})
    # @param options [{Symbol => Object}] An options hash.
    #   See {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    # @see {Sass::Engine.for_file}
    # @see {Sass::Plugin}
    def initialize(template, options={})
      @options = self.class.normalize_options(options)
      @template = template
    end

    # Render the template to CSS.
    #
    # @return [String] The CSS
    # @raise [Sass::SyntaxError] if there's an error in the document
    # @raise [Encoding::UndefinedConversionError] if the source encoding
    #   cannot be converted to UTF-8
    # @raise [ArgumentError] if the document uses an unknown encoding with `@charset`
    def render
      return _render unless @options[:quiet]
      Sass::Util.silence_sass_warnings {_render}
    end
    alias_method :to_css, :render

    # Parses the document into its parse tree. Memoized.
    #
    # @return [Sass::Tree::Node] The root of the parse tree.
    # @raise [Sass::SyntaxError] if there's an error in the document
    def to_tree
      @tree ||= @options[:quiet] ?
        Sass::Util.silence_sass_warnings {_to_tree} :
        _to_tree
    end

    # Returns the original encoding of the document,
    # or `nil` under Ruby 1.8.
    #
    # @return [Encoding, nil]
    # @raise [Encoding::UndefinedConversionError] if the source encoding
    #   cannot be converted to UTF-8
    # @raise [ArgumentError] if the document uses an unknown encoding with `@charset`
    def source_encoding
      check_encoding!
      @original_encoding
    end

    # Gets a set of all the documents
    # that are (transitive) dependencies of this document,
    # not including the document itself.
    #
    # @return [[Sass::Engine]] The dependency documents.
    def dependencies
      _dependencies(Set.new, engines = Set.new)
      Sass::Util.array_minus(engines, [self])
    end

    # Helper for \{#dependencies}.
    #
    # @private
    def _dependencies(seen, engines)
      return if seen.include?(key = [@options[:filename], @options[:importer]])
      seen << key
      engines << self
      to_tree.grep(Tree::ImportNode) do |n|
        next if n.css_import?
        n.imported_file._dependencies(seen, engines)
      end
    end

    private

    def _render
      rendered = _to_tree.render
      return rendered if ruby1_8?
      begin
        # Try to convert the result to the original encoding,
        # but if that doesn't work fall back on UTF-8
        rendered = rendered.encode(source_encoding)
      rescue EncodingError
      end
      rendered.gsub(Regexp.new('\A@charset "(.*?)"'.encode(source_encoding)),
        "@charset \"#{source_encoding.name}\"".encode(source_encoding))
    end

    def _to_tree
      if (@options[:cache] || @options[:read_cache]) &&
          @options[:filename] && @options[:importer]
        key = sassc_key
        sha = Digest::SHA1.hexdigest(@template)

        if root = @options[:cache_store].retrieve(key, sha)
          root.options = @options
          return root
        end
      end

      check_encoding!

      if @options[:syntax] == :scss
        root = Sass::SCSS::Parser.new(@template, @options[:filename]).parse
      else
        root = Tree::RootNode.new(@template)
        append_children(root, tree(tabulate(@template)).first, true)
      end

      root.options = @options
      if @options[:cache] && key && sha
        begin
          old_options = root.options
          root.options = {}
          @options[:cache_store].store(key, sha, root)
        ensure
          root.options = old_options
        end
      end
      root
    rescue SyntaxError => e
      e.modify_backtrace(:filename => @options[:filename], :line => @line)
      e.sass_template = @template
      raise e
    end

    def sassc_key
      @options[:cache_store].key(*@options[:importer].key(@options[:filename], @options))
    end

    def check_encoding!
      return if @checked_encoding
      @checked_encoding = true
      @template, @original_encoding = check_sass_encoding(@template) do |msg, line|
        raise Sass::SyntaxError.new(msg, :line => line)
      end
    end

    def tabulate(string)
      tab_str = nil
      comment_tab_str = nil
      first = true
      lines = []
      string.gsub(/\r\n|\r|\n/, "\n").scan(/^[^\n]*?$/).each_with_index do |line, index|
        index += (@options[:line] || 1)
        if line.strip.empty?
          lines.last.text << "\n" if lines.last && lines.last.comment?
          next
        end

        line_tab_str = line[/^\s*/]
        unless line_tab_str.empty?
          if tab_str.nil?
            comment_tab_str ||= line_tab_str
            next if try_comment(line, lines.last, "", comment_tab_str, index)
            comment_tab_str = nil
          end

          tab_str ||= line_tab_str

          raise SyntaxError.new("Indenting at the beginning of the document is illegal.",
            :line => index) if first

          raise SyntaxError.new("Indentation can't use both tabs and spaces.",
            :line => index) if tab_str.include?(?\s) && tab_str.include?(?\t)
        end
        first &&= !tab_str.nil?
        if tab_str.nil?
          lines << Line.new(line.strip, 0, index, 0, @options[:filename], [])
          next
        end

        comment_tab_str ||= line_tab_str
        if try_comment(line, lines.last, tab_str * lines.last.tabs, comment_tab_str, index)
          next
        else
          comment_tab_str = nil
        end

        line_tabs = line_tab_str.scan(tab_str).size
        if tab_str * line_tabs != line_tab_str
          message = <<END.strip.gsub("\n", ' ')
Inconsistent indentation: #{Sass::Shared.human_indentation line_tab_str, true} used for indentation,
but the rest of the document was indented using #{Sass::Shared.human_indentation tab_str}.
END
          raise SyntaxError.new(message, :line => index)
        end

        lines << Line.new(line.strip, line_tabs, index, tab_str.size, @options[:filename], [])
      end
      lines
    end

    def try_comment(line, last, tab_str, comment_tab_str, index)
      return unless last && last.comment?
      # Nested comment stuff must be at least one whitespace char deeper
      # than the normal indentation
      return unless line =~ /^#{tab_str}\s/
      unless line =~ /^(?:#{comment_tab_str})(.*)$/
        raise SyntaxError.new(<<MSG.strip.gsub("\n", " "), :line => index)
Inconsistent indentation:
previous line was indented by #{Sass::Shared.human_indentation comment_tab_str},
but this line was indented by #{Sass::Shared.human_indentation line[/^\s*/]}.
MSG
      end

      last.comment_tab_str ||= comment_tab_str
      last.text << "\n" << line
      true
    end

    def tree(arr, i = 0)
      return [], i if arr[i].nil?

      base = arr[i].tabs
      nodes = []
      while (line = arr[i]) && line.tabs >= base
        if line.tabs > base
          raise SyntaxError.new("The line was indented #{line.tabs - base} levels deeper than the previous line.",
            :line => line.index) if line.tabs > base + 1

          nodes.last.children, i = tree(arr, i)
        else
          nodes << line
          i += 1
        end
      end
      return nodes, i
    end

    def build_tree(parent, line, root = false)
      @line = line.index
      node_or_nodes = parse_line(parent, line, root)

      Array(node_or_nodes).each do |node|
        # Node is a symbol if it's non-outputting, like a variable assignment
        next unless node.is_a? Tree::Node

        node.line = line.index
        node.filename = line.filename

        append_children(node, line.children, false)
      end

      node_or_nodes
    end

    def append_children(parent, children, root)
      continued_rule = nil
      continued_comment = nil
      children.each do |line|
        child = build_tree(parent, line, root)

        if child.is_a?(Tree::RuleNode)
          if child.continued? && child.children.empty?
            if continued_rule
              continued_rule.add_rules child
            else
              continued_rule = child
            end
            next
          elsif continued_rule
            continued_rule.add_rules child
            continued_rule.children = child.children
            continued_rule, child = nil, continued_rule
          end
        elsif continued_rule
          continued_rule = nil
        end

        if child.is_a?(Tree::CommentNode) && child.type == :silent
          if continued_comment &&
              child.line == continued_comment.line +
              continued_comment.lines + 1
            continued_comment.value += ["\n"] + child.value
            next
          end

          continued_comment = child
        end

        check_for_no_children(child)
        validate_and_append_child(parent, child, line, root)
      end

      parent
    end

    def validate_and_append_child(parent, child, line, root)
      case child
      when Array
        child.each {|c| validate_and_append_child(parent, c, line, root)}
      when Tree::Node
        parent << child
      end
    end

    def check_for_no_children(node)
      return unless node.is_a?(Tree::RuleNode) && node.children.empty?
      Sass::Util.sass_warn(<<WARNING.strip)
WARNING on line #{node.line}#{" of #{node.filename}" if node.filename}:
This selector doesn't have any properties and will not be rendered.
WARNING
    end

    def parse_line(parent, line, root)
      case line.text[0]
      when PROPERTY_CHAR
        if line.text[1] == PROPERTY_CHAR ||
            (@options[:property_syntax] == :new &&
             line.text =~ PROPERTY_OLD && $2.empty?)
          # Support CSS3-style pseudo-elements,
          # which begin with ::,
          # as well as pseudo-classes
          # if we're using the new property syntax
          Tree::RuleNode.new(parse_interp(line.text))
        else
          name, value = line.text.scan(PROPERTY_OLD)[0]
          raise SyntaxError.new("Invalid property: \"#{line.text}\".",
            :line => @line) if name.nil? || value.nil?
          parse_property(name, parse_interp(name), value, :old, line)
        end
      when ?$
        parse_variable(line)
      when COMMENT_CHAR
        parse_comment(line)
      when DIRECTIVE_CHAR
        parse_directive(parent, line, root)
      when ESCAPE_CHAR
        Tree::RuleNode.new(parse_interp(line.text[1..-1]))
      when MIXIN_DEFINITION_CHAR
        parse_mixin_definition(line)
      when MIXIN_INCLUDE_CHAR
        if line.text[1].nil? || line.text[1] == ?\s
          Tree::RuleNode.new(parse_interp(line.text))
        else
          parse_mixin_include(line, root)
        end
      else
        parse_property_or_rule(line)
      end
    end

    def parse_property_or_rule(line)
      scanner = Sass::Util::MultibyteStringScanner.new(line.text)
      hack_char = scanner.scan(/[:\*\.]|\#(?!\{)/)
      parser = Sass::SCSS::Parser.new(scanner, @options[:filename], @line)

      unless res = parser.parse_interp_ident
        return Tree::RuleNode.new(parse_interp(line.text))
      end
      res.unshift(hack_char) if hack_char
      if comment = scanner.scan(Sass::SCSS::RX::COMMENT)
        res << comment
      end

      name = line.text[0...scanner.pos]
      if scanner.scan(/\s*:(?:\s|$)/)
        parse_property(name, res, scanner.rest, :new, line)
      else
        res.pop if comment
        Tree::RuleNode.new(res + parse_interp(scanner.rest))
      end
    end

    def parse_property(name, parsed_name, value, prop, line)
      if value.strip.empty?
        expr = Sass::Script::String.new("")
      else
        expr = parse_script(value, :offset => line.offset + line.text.index(value))
      end
      node = Tree::PropNode.new(parse_interp(name), expr, prop)
      if value.strip.empty? && line.children.empty?
        raise SyntaxError.new(
          "Invalid property: \"#{node.declaration}\" (no value)." +
          node.pseudo_class_selector_message)
      end

      node
    end

    def parse_variable(line)
      name, value, default = line.text.scan(Script::MATCH)[0]
      raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath variable declarations.",
        :line => @line + 1) unless line.children.empty?
      raise SyntaxError.new("Invalid variable: \"#{line.text}\".",
        :line => @line) unless name && value

      expr = parse_script(value, :offset => line.offset + line.text.index(value))

      Tree::VariableNode.new(name, expr, default)
    end

    def parse_comment(line)
      if line.text[1] == CSS_COMMENT_CHAR || line.text[1] == SASS_COMMENT_CHAR
        silent = line.text[1] == SASS_COMMENT_CHAR
        loud = !silent && line.text[2] == SASS_LOUD_COMMENT_CHAR
        if silent
          value = [line.text]
        else
          value = self.class.parse_interp(line.text, line.index, line.offset, :filename => @filename)
        end
        value = with_extracted_values(value) do |str|
          str = str.gsub(/^#{line.comment_tab_str}/m, '')[2..-1] # get rid of // or /*
          format_comment_text(str, silent)
        end
        type = if silent then :silent elsif loud then :loud else :normal end
        Tree::CommentNode.new(value, type)
      else
        Tree::RuleNode.new(parse_interp(line.text))
      end
    end

    def parse_directive(parent, line, root)
      directive, whitespace, value = line.text[1..-1].split(/(\s+)/, 2)
      offset = directive.size + whitespace.size + 1 if whitespace

      # If value begins with url( or ",
      # it's a CSS @import rule and we don't want to touch it.
      case directive
      when 'import'
        parse_import(line, value, offset)
      when 'mixin'
        parse_mixin_definition(line)
      when 'content'
        parse_content_directive(line)
      when 'include'
        parse_mixin_include(line, root)
      when 'function'
        parse_function(line, root)
      when 'for'
        parse_for(line, root, value)
      when 'each'
        parse_each(line, root, value)
      when 'else'
        parse_else(parent, line, value)
      when 'while'
        raise SyntaxError.new("Invalid while directive '@while': expected expression.") unless value
        Tree::WhileNode.new(parse_script(value, :offset => offset))
      when 'if'
        raise SyntaxError.new("Invalid if directive '@if': expected expression.") unless value
        Tree::IfNode.new(parse_script(value, :offset => offset))
      when 'debug'
        raise SyntaxError.new("Invalid debug directive '@debug': expected expression.") unless value
        raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath debug directives.",
          :line => @line + 1) unless line.children.empty?
        offset = line.offset + line.text.index(value).to_i
        Tree::DebugNode.new(parse_script(value, :offset => offset))
      when 'extend'
        raise SyntaxError.new("Invalid extend directive '@extend': expected expression.") unless value
        raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath extend directives.",
          :line => @line + 1) unless line.children.empty?
        optional = !!value.gsub!(/\s+#{Sass::SCSS::RX::OPTIONAL}$/, '')
        offset = line.offset + line.text.index(value).to_i
        Tree::ExtendNode.new(parse_interp(value, offset), optional)
      when 'warn'
        raise SyntaxError.new("Invalid warn directive '@warn': expected expression.") unless value
        raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath warn directives.",
          :line => @line + 1) unless line.children.empty?
        offset = line.offset + line.text.index(value).to_i
        Tree::WarnNode.new(parse_script(value, :offset => offset))
      when 'return'
        raise SyntaxError.new("Invalid @return: expected expression.") unless value
        raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath return directives.",
          :line => @line + 1) unless line.children.empty?
        offset = line.offset + line.text.index(value).to_i
        Tree::ReturnNode.new(parse_script(value, :offset => offset))
      when 'charset'
        name = value && value[/\A(["'])(.*)\1\Z/, 2] #"
        raise SyntaxError.new("Invalid charset directive '@charset': expected string.") unless name
        raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath charset directives.",
          :line => @line + 1) unless line.children.empty?
        Tree::CharsetNode.new(name)
      when 'media'
        parser = Sass::SCSS::Parser.new(value, @options[:filename], @line)
        Tree::MediaNode.new(parser.parse_media_query_list.to_a)
      else
        unprefixed_directive = directive.gsub(/^-[a-z0-9]+-/i, '')
        if unprefixed_directive == 'supports'
          parser = Sass::SCSS::Parser.new(value, @options[:filename], @line)
          return Tree::SupportsNode.new(directive, parser.parse_supports_condition)
        end

        Tree::DirectiveNode.new(
          value.nil? ? ["@#{directive}"] : ["@#{directive} "] + parse_interp(value, offset))
      end
    end

    def parse_for(line, root, text)
      var, from_expr, to_name, to_expr = text.scan(/^([^\s]+)\s+from\s+(.+)\s+(to|through)\s+(.+)$/).first

      if var.nil? # scan failed, try to figure out why for error message
        if text !~ /^[^\s]+/
          expected = "variable name"
        elsif text !~ /^[^\s]+\s+from\s+.+/
          expected = "'from <expr>'"
        else
          expected = "'to <expr>' or 'through <expr>'"
        end
        raise SyntaxError.new("Invalid for directive '@for #{text}': expected #{expected}.")
      end
      raise SyntaxError.new("Invalid variable \"#{var}\".") unless var =~ Script::VALIDATE

      var = var[1..-1]
      parsed_from = parse_script(from_expr, :offset => line.offset + line.text.index(from_expr))
      parsed_to = parse_script(to_expr, :offset => line.offset + line.text.index(to_expr))
      Tree::ForNode.new(var, parsed_from, parsed_to, to_name == 'to')
    end

    def parse_each(line, root, text)
      var, list_expr = text.scan(/^([^\s]+)\s+in\s+(.+)$/).first

      if var.nil? # scan failed, try to figure out why for error message
        if text !~ /^[^\s]+/
          expected = "variable name"
        elsif text !~ /^[^\s]+\s+from\s+.+/
          expected = "'in <expr>'"
        end
        raise SyntaxError.new("Invalid for directive '@each #{text}': expected #{expected}.")
      end
      raise SyntaxError.new("Invalid variable \"#{var}\".") unless var =~ Script::VALIDATE

      var = var[1..-1]
      parsed_list = parse_script(list_expr, :offset => line.offset + line.text.index(list_expr))
      Tree::EachNode.new(var, parsed_list)
    end

    def parse_else(parent, line, text)
      previous = parent.children.last
      raise SyntaxError.new("@else must come after @if.") unless previous.is_a?(Tree::IfNode)

      if text
        if text !~ /^if\s+(.+)/
          raise SyntaxError.new("Invalid else directive '@else #{text}': expected 'if <expr>'.")
        end
        expr = parse_script($1, :offset => line.offset + line.text.index($1))
      end

      node = Tree::IfNode.new(expr)
      append_children(node, line.children, false)
      previous.add_else node
      nil
    end

    def parse_import(line, value, offset)
      raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath import directives.",
        :line => @line + 1) unless line.children.empty?

      scanner = Sass::Util::MultibyteStringScanner.new(value)
      values = []

      loop do
        unless node = parse_import_arg(scanner, offset + scanner.pos)
          raise SyntaxError.new("Invalid @import: expected file to import, was #{scanner.rest.inspect}",
            :line => @line)
        end
        values << node
        break unless scanner.scan(/,\s*/)
      end

      if scanner.scan(/;/)
        raise SyntaxError.new("Invalid @import: expected end of line, was \";\".",
          :line => @line)
      end

      return values
    end

    def parse_import_arg(scanner, offset)
      return if scanner.eos?

      if scanner.match?(/url\(/i)
        script_parser = Sass::Script::Parser.new(scanner, @line, offset, @options)
        str = script_parser.parse_string
        media_parser = Sass::SCSS::Parser.new(scanner, @options[:filename], @line)
        media = media_parser.parse_media_query_list
        return Tree::CssImportNode.new(str, media.to_a)
      end

      unless str = scanner.scan(Sass::SCSS::RX::STRING)
        return Tree::ImportNode.new(scanner.scan(/[^,;]+/))
      end

      val = scanner[1] || scanner[2]
      scanner.scan(/\s*/)
      if !scanner.match?(/[,;]|$/)
        media_parser = Sass::SCSS::Parser.new(scanner, @options[:filename], @line)
        media = media_parser.parse_media_query_list
        Tree::CssImportNode.new(str || uri, media.to_a)
      elsif val =~ /^(https?:)?\/\//
        Tree::CssImportNode.new("url(#{val})")
      else
        Tree::ImportNode.new(val)
      end
    end

    MIXIN_DEF_RE = /^(?:=|@mixin)\s*(#{Sass::SCSS::RX::IDENT})(.*)$/
    def parse_mixin_definition(line)
      name, arg_string = line.text.scan(MIXIN_DEF_RE).first
      raise SyntaxError.new("Invalid mixin \"#{line.text[1..-1]}\".") if name.nil?

      offset = line.offset + line.text.size - arg_string.size
      args, splat = Script::Parser.new(arg_string.strip, @line, offset, @options).
        parse_mixin_definition_arglist
      Tree::MixinDefNode.new(name, args, splat)
    end

    CONTENT_RE = /^@content\s*(.+)?$/
    def parse_content_directive(line)
      trailing = line.text.scan(CONTENT_RE).first.first
      raise SyntaxError.new("Invalid content directive. Trailing characters found: \"#{trailing}\".") unless trailing.nil?
      raise SyntaxError.new("Illegal nesting: Nothing may be nested beneath @content directives.",
        :line => line.index + 1) unless line.children.empty?
      Tree::ContentNode.new
    end

    MIXIN_INCLUDE_RE = /^(?:\+|@include)\s*(#{Sass::SCSS::RX::IDENT})(.*)$/
    def parse_mixin_include(line, root)
      name, arg_string = line.text.scan(MIXIN_INCLUDE_RE).first
      raise SyntaxError.new("Invalid mixin include \"#{line.text}\".") if name.nil?

      offset = line.offset + line.text.size - arg_string.size
      args, keywords, splat = Script::Parser.new(arg_string.strip, @line, offset, @options).
        parse_mixin_include_arglist
      Tree::MixinNode.new(name, args, keywords, splat)
    end

    FUNCTION_RE = /^@function\s*(#{Sass::SCSS::RX::IDENT})(.*)$/
    def parse_function(line, root)
      name, arg_string = line.text.scan(FUNCTION_RE).first
      raise SyntaxError.new("Invalid function definition \"#{line.text}\".") if name.nil?

      offset = line.offset + line.text.size - arg_string.size
      args, splat = Script::Parser.new(arg_string.strip, @line, offset, @options).
        parse_function_definition_arglist
      Tree::FunctionNode.new(name, args, splat)
    end

    def parse_script(script, options = {})
      line = options[:line] || @line
      offset = options[:offset] || 0
      Script.parse(script, line, offset, @options)
    end

    def format_comment_text(text, silent)
      content = text.split("\n")

      if content.first && content.first.strip.empty?
        removed_first = true
        content.shift
      end

      return silent ? "//" : "/* */" if content.empty?
      content.last.gsub!(%r{ ?\*/ *$}, '')
      content.map! {|l| l.gsub!(/^\*( ?)/, '\1') || (l.empty? ? "" : " ") + l}
      content.first.gsub!(/^ /, '') unless removed_first
      if silent
        "//" + content.join("\n//")
      else
        # The #gsub fixes the case of a trailing */
        "/*" + content.join("\n *").gsub(/ \*\Z/, '') + " */"
      end
    end

    def parse_interp(text, offset = 0)
      self.class.parse_interp(text, @line, offset, :filename => @filename)
    end

    # It's important that this have strings (at least)
    # at the beginning, the end, and between each Script::Node.
    #
    # @private
    def self.parse_interp(text, line, offset, options)
      res = []
      rest = Sass::Shared.handle_interpolation text do |scan|
        escapes = scan[2].size
        res << scan.matched[0...-2 - escapes]
        if escapes % 2 == 1
          res << "\\" * (escapes - 1) << '#{'
        else
          res << "\\" * [0, escapes - 1].max
          res << Script::Parser.new(
            scan, line, offset + scan.pos - scan.matched_size, options).
            parse_interpolated
        end
      end
      res << rest
    end
  end
end