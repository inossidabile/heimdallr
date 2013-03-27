module Heimdallr
  # A security-aware proxy for +ActiveRecord+ scopes. This class validates all the
  # method calls and either forwards them to the encapsulated scope or raises
  # an exception.
  #
  # There are two kinds of collection proxies, explicit and implicit, which instantiate
  # the corresponding types of record proxies. See also {Proxy::Record}.
  class Proxy::Collection
    include Enumerable

    # Create a collection proxy.
    #
    # The +scope+ is expected to be already restricted with +:fetch+ scope.
    #
    # @param context  security context
    # @param scope    proxified scope
    # @option options [Boolean] implicit proxy type
    def initialize(context, scope, options={})
      @context, @scope, @options = context, scope, options

      @restrictions = @scope.restrictions(context)
      @options[:eager_loaded] ||= {}
    end

    # Collections cannot be restricted with different context or options.
    #
    # @return self
    # @raise [RuntimeError]
    def restrict(context, options=nil)
      if @context == context && options.nil?
        self
      else
        raise RuntimeError, "Heimdallr proxies cannot be restricted with nonmatching context or options"
      end
    end

    # @private
    # @macro [attach] delegate_as_constructor
    #   A proxy for +$1+ method which adds fixtures to the attribute list and
    #   returns a restricted record.
    def self.delegate_as_constructor(name, method)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(attributes={})
        record = @restrictions.request_scope(:fetch).new.restrict(@context, options_with_escape)
        record.#{method}(attributes.merge(@restrictions.fixtures[:create]))
        record
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_scope
    #   A proxy for +$1+ method which returns a restricted scope.
    def self.delegate_as_scope(name, conversion=false)
      conversion = conversion ? "set = set.send(:#{conversion})" : ''

      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        set = @scope.#{name}(*args); #{conversion}
        Proxy::Collection.new(@context, set, options_with_escape)
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_destroyer
    #   A proxy for +$1+ method which works on a +:delete+ scope.
    def self.delegate_as_destroyer(name)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        @restrictions.request_scope(:delete, @scope).#{name}(*args)
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_record
    #   A proxy for +$1+ method which returns a restricted record.
    def self.delegate_as_record(name)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        @scope.#{name}(*args).restrict(@context, options_with_eager_load)
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_records
    #   A proxy for +$1+ method which returns an array of restricted records.
    def self.delegate_as_records(name, conversion=false)
      conversion = conversion ? "set = set.send(:#{conversion})" : ''

      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        set = @scope.#{name}(*args); #{conversion}

        set.map do |element|
          element.restrict(@context, options_with_eager_load)
        end
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_value
    #   A proxy for +$1+ method which returns a raw value.
    def self.delegate_as_value(name)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        @scope.#{name}(*args)
      end
      EOM
    end

    delegate_as_constructor :build,   :assign_attributes
    delegate_as_constructor :new,     :assign_attributes
    delegate_as_constructor :create,  :update_attributes
    delegate_as_constructor :create!, :update_attributes!

    delegate_as_scope :scoped
    delegate_as_scope :uniq
    delegate_as_scope :where
    delegate_as_scope :joins
    delegate_as_scope :lock
    delegate_as_scope :limit
    delegate_as_scope :offset
    delegate_as_scope :order
    delegate_as_scope :reorder
    delegate_as_scope :reverse_order
    delegate_as_scope :extending

    delegate_as_value :klass
    delegate_as_value :model_name
    delegate_as_value :empty?
    delegate_as_value :any?
    delegate_as_value :many?
    delegate_as_value :include?
    delegate_as_value :exists?
    delegate_as_value :size
    delegate_as_value :length

    delegate_as_value :calculate
    delegate_as_value :count
    delegate_as_value :average
    delegate_as_value :sum
    delegate_as_value :maximum
    delegate_as_value :minimum
    delegate_as_value :pluck

    delegate_as_destroyer :delete
    delegate_as_destroyer :delete_all
    delegate_as_destroyer :destroy
    delegate_as_destroyer :destroy_all

    delegate_as_record  :first
    delegate_as_record  :first!
    delegate_as_record  :last
    delegate_as_record  :last!

    delegate_as_records :all
    delegate_as_records :to_a
    delegate_as_records :to_ary

    # A proxy for +includes+ which adds Heimdallr conditions for eager loaded
    # associations.
    def includes(*associations)
      # Normalize association list to strict nested hash.
      normalize = ->(list) {
        if list.is_a? Array
          list.map(&normalize).reduce(:merge)
        elsif list.is_a? Symbol
          { list => {} }
        elsif list.is_a? Hash
          hash = {}
          list.each do |key, value|
            hash[key] = normalize.(value)
          end
          hash
        end
      }
      associations = normalize.(associations)

      current_scope = @scope.includes(associations)

      add_conditions = ->(associations, scope) {
        associations.each do |association, nested|
          reflection = scope.reflect_on_association(association)
          if reflection && !reflection.options[:polymorphic]
            associated_klass = reflection.klass

            if associated_klass.respond_to? :restrict
              nested_scope = associated_klass.restrictions(@context).request_scope(:fetch)

              where_values = nested_scope.where_values
              if where_values.any?
                current_scope = current_scope.where(*where_values)
              end

              add_conditions.(nested, associated_klass)
            end
          end
        end
      }

      unless Heimdallr.skip_eager_condition_injection
        add_conditions.(associations, current_scope)
      end

      options = @options.merge(eager_loaded:
        @options[:eager_loaded].merge(associations))

      Proxy::Collection.new(@context, current_scope, options)
    end

    # A proxy for +find+ which restricts the returned record or records.
    #
    # @return [Proxy::Record, Array<Proxy::Record>]
    def find(*args)
      result = @scope.find(*args)

      if result.is_a? Enumerable
        result.map do |element|
          element.restrict(@context, options_with_eager_load)
        end
      else
        result.restrict(@context, options_with_eager_load)
      end
    end

    # A proxy for +each+ which restricts the yielded records.
    #
    # @yield [record]
    # @yieldparam [Proxy::Record] record
    def each
      @scope.each do |record|
        yield record.restrict(@context, options_with_eager_load)
      end
    end

    # Wraps a scope or a record in a corresponding proxy.
    def method_missing(method, *args)
      if method =~ /^find_all_by/
        @scope.send(method, *args).map do |element|
          element.restrict(@context, options_with_escape)
        end
      elsif method =~ /^find_by/
        @scope.send(method, *args).restrict(@context, options_with_escape)
      elsif @scope.heimdallr_scopes && @scope.heimdallr_scopes.include?(method)
        Proxy::Collection.new(@context, @scope.send(method, *args), options_with_escape)
      elsif @scope.respond_to? method
        raise InsecureOperationError,
            "Potentially insecure method #{method} was called"
      else
        super
      end
    end

    def respond_to?(method)
      super                                                                 ||
      method =~ /^find_(all_)?_by/                                          ||
      (@scope.heimdallr_scopes && @scope.heimdallr_scopes.include?(method)) ||
      @scope.respond_to?(method)
    end

    # Return the underlying scope.
    #
    # @return ActiveRecord scope
    def insecure
      @scope
    end

    # Insecurely taps method saving restricted context for the result
    # Method (or block) is supposed to return proper relation
    #
    # @return [Proxy::Collection]
    def insecurely(*args, &block)
      if block_given?
        result = yield @scope
      else
        method = args.shift
        result = @scope.send method, *args
      end

      Proxy::Collection.new(@context, result, options_with_escape)
    end

    # Describes the proxy and proxified scope.
    #
    # @return [String]
    def inspect
      "#<Heimdallr::Proxy::Collection: #{@scope.to_sql}>"
    end

    # Return the associated security metadata. The returned hash will contain keys
    # +:context+, +:scope+ and +:options+, corresponding to the parameters in
    # {#initialize}, +:model+ and +:restrictions+, representing the model class.
    #
    # Such a name was deliberately selected for this method in order to reduce namespace
    # pollution.
    #
    # @return [Hash]
    def reflect_on_security
      {
        model:        @scope,
        context:      @context,
        scope:        @scope,
        options:      @options,
        restrictions: @restrictions,
      }.merge(@restrictions.reflection)
    end

    def creatable?
      @restrictions.can? :create
    end

    private

    # Return options hash to pass to children proxies.
    # Currently this checks only eagerly loaded collections, which
    # shouldn't be passed around blindly.
    def options_with_escape
      @options.reject { |k,v| k == :eager_loaded }
    end

    def options_with_eager_load
      @options
    end
  end
end