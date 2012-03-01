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
    end

    # Collections cannot be restricted twice.
    #
    # @raise [RuntimeError]
    def restrict(*args)
      raise RuntimeError, "Collections cannot be restricted twice"
    end

    # @private
    # @macro [attach] delegate_as_constructor
    #   A proxy for +$1+ method which adds fixtures to the attribute list and
    #   returns a restricted record.
    def self.delegate_as_constructor(name, method)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(attributes={})
        record = @restrictions.request_scope(:fetch).new.restrict(@context, @options)
        record.#{method}(attributes.merge(@restrictions.fixtures[:create]))
        record
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_scope
    #   A proxy for +$1+ method which returns a restricted scope.
    def self.delegate_as_scope(name)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        Proxy::Collection.new(@context, @scope.#{name}(*args), @options)
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
        @scope.#{name}(*args).restrict(@context, @options)
      end
      EOM
    end

    # @private
    # @macro [attach] delegate_as_records
    #   A proxy for +$1+ method which returns an array of restricted records.
    def self.delegate_as_records(name)
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{name}(*args)
        @scope.#{name}(*args).map do |element|
          element.restrict(@context, @options)
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
    delegate_as_scope :includes
    delegate_as_scope :eager_load
    delegate_as_scope :preload
    delegate_as_scope :lock
    delegate_as_scope :limit
    delegate_as_scope :offset
    delegate_as_scope :order
    delegate_as_scope :reorder
    delegate_as_scope :reverse_order
    delegate_as_scope :extending

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

    # A proxy for +find+ which restricts the returned record or records.
    #
    # @return [Proxy::Record, Array<Proxy::Record>]
    def find(*args)
      result = @scope.find(*args)

      if result.is_a? Enumerable
        result.map do |element|
          element.restrict(@context, @options)
        end
      else
        result.restrict(@context, @options)
      end
    end

    # A proxy for +each+ which restricts the yielded records.
    #
    # @yield [record]
    # @yieldparam [Proxy::Record] record
    def each
      @scope.each do |record|
        yield record.restrict(@context, @options)
      end
    end

    # Wraps a scope or a record in a corresponding proxy.
    def method_missing(method, *args)
      if method =~ /^find_all_by/
        @scope.send(method, *args).map do |element|
          element.restrict(@context, @options)
        end
      elsif method =~ /^find_by/
        @scope.send(method, *args).restrict(@context, @options)
      elsif @scope.heimdallr_scopes && @scope.heimdallr_scopes.include?(method)
        Proxy::Collection.new(@context, @scope.send(method, *args), @options)
      elsif @scope.respond_to? method
        raise InsecureOperationError,
            "Potentially insecure method #{method} was called"
      else
        super
      end
    end

    # Return the underlying scope.
    #
    # @return ActiveRecord scope
    def insecure
      @scope
    end

    # Describes the proxy and proxified scope.
    #
    # @return [String]
    def inspect
      "#<Heimdallr::Proxy::Collection: #{@scope.to_sql}>"
    end

    # Return the associated security metadata. The returned hash will contain keys
    # +:context+, +:scope+ and +:options+, corresponding to the parameters in
    # {#initialize}, and +:model+, representing the model class.
    #
    # Such a name was deliberately selected for this method in order to reduce namespace
    # pollution.
    #
    # @return [Hash]
    def reflect_on_security
      {
        model:   @scope,
        context: @context,
        scope:   @scope,
        options: @options
      }
    end
  end
end