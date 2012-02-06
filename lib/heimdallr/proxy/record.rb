module Heimdallr
  # A security-aware proxy for individual records. This class validates all the
  # method calls and either forwards them to the encapsulated object or raises
  # an exception.
  #
  # The #touch method call isn't considered a security threat and as such, it is
  # forwarded to the underlying object directly.
  class Proxy::Record
    # Create a record proxy.
    # @param context security context
    # @param object  proxified record
    def initialize(context, record)
      @context, @record = context, record

      @restrictions = @record.class.restrictions(context)
    end

    # @method decrement(field, by=1)
    # @macro [new] delegate
    #   Delegates to the corresponding method of underlying object.
    delegate :decrement, :to => :@record

    # @method increment(field, by=1)
    # @macro delegate
    delegate :increment, :to => :@record

    # @method toggle(field)
    # @macro delegate
    delegate :toggle, :to => :@record

    # @method touch(field)
    # @macro delegate
    # This method does not modify any fields except for the timestamp itself
    # and thus is not considered as a potential security threat.
    delegate :touch, :to => :@record

    # A proxy for +attributes+ method which removes all attributes
    # without +:view+ permission.
    def attributes
      @restrictions.filter_attributes(:view, @record.attributes)
    end

    # A proxy for +update_attributes+ method which removes all attributes
    # without +:update+ permission and invokes +#save+.
    #
    # @raise [Heimdallr::PermissionError]
    def update_attributes(attributes, options={})
      @record.with_transaction_returning_status do
        @record.assign_attributes(attributes, options)
        self.save
      end
    end

    # A proxy for +update_attributes!+ method which removes all attributes
    # without +:update+ permission and invokes +#save!+.
    #
    # @raise [Heimdallr::PermissionError]
    def update_attributes(attributes, options={})
      @record.with_transaction_returning_status do
        @record.assign_attributes(attributes, options)
        self.save!
      end
    end

    # A proxy for +save+ method which verifies all of the dirty attributes to
    # be valid for current security context.
    #
    # @raise [Heimdallr::PermissionError]
    def save(options={})
      check_save_options options

      check_attributes do
        @record.save(options)
      end
    end

    # A proxy for +save+ method which verifies all of the dirty attributes to
    # be valid for current security context and mandates the current record
    # to be valid.
    #
    # @raise [Heimdallr::PermissionError]
    # @raise [ActiveRecord::RecordInvalid]
    # @raise [ActiveRecord::RecordNotSaved]
    def save!(options={})
      check_save_options options

      check_attributes do
        @record.save!(options)
      end
    end

    [:delete, :destroy].each do |method|
      class_eval(<<-EOM, __FILE__, __LINE__)
      def #{method}
        scope = @restrictions.request_scope(:delete)
        if scope.where({ @record.primary_key => @record.to_key }).count != 0
          @record.#{method}
        end
      end
      EOM
    end

    # Records cannot be restricted twice.
    #
    # @raise [RuntimeError]
    def restrict(context)
      raise RuntimeError, "Records cannot be restricted twice"
    end

    # A whitelisting dispatcher for attribute-related method calls.
    # Every unknown method is first normalized (that is, stripped of its +?+ or +=+
    # suffix). Then, if the normalized form is whitelisted, it is passed to the
    # underlying object as-is. Otherwise, an exception is raised.
    #
    # If the underlying object is an instance of ActiveRecord, then all association
    # accesses are resolved and proxified automatically.
    #
    # Note that only the attribute and collection getters and setters are
    # dispatched through this method. Every other model method should be defined
    # as an instance method of this class in order to work.
    #
    # @raise [Heimdallr::PermissionError] when a non-whitelisted method is accessed
    # @raise [Heimdallr::InsecureOperationError] when an insecure association is about
    #   to be fetched
    def method_missing(method, *args, &block)
      suffix = method.to_s[-1]
      if %w(? = !).include? suffix
        normalized_method = method[0..-2].to_sym
      else
        normalized_method = method
        suffix = nil
      end

      if defined?(ActiveRecord) && @record.is_a?(ActiveRecord::Base) &&
          association = @record.class.reflect_on_association(method)
        referenced = @record.send(method, *args)

        if referenced.respond_to? :restrict
          referenced.restrict(@context)
        elsif Heimdallr.allow_insecure_associations
          referenced
        else
          raise Heimdallr::InsecureOperationError,
              "Attempt to fetch insecure association #{method}. Try #insecure."
        end
      elsif @record.respond_to? method
        if [nil, '?'].include?(suffix) &&
             @restrictions.allowed_fields[:view].include?(normalized_method)
          # Reading an attribute
          @record.send method, *args, &block
        elsif suffix == '='
          @record.send method, *args
        else
          raise Heimdallr::PermissionError,
              "Non-whitelisted method #{method} is called for #{@record.inspect} on #{@action}."
        end
      else
        super
      end
    end

    # Return the underlying object.
    #
    # @return [ActiveRecord::Base]
    def insecure
      @record
    end

    # Describes the proxy and proxified object.
    #
    # @return [String]
    def inspect
      "#<Heimdallr::Proxy(#{@action}): #{@record.inspect}>"
    end

    # Return the associated security metadata. The returned hash will contain keys
    # +:context+ and +:object+, corresponding to the parameters in
    # {#initialize}.
    #
    # Such a name was deliberately selected for this method in order to reduce namespace
    # pollution.
    #
    # @return [Hash]
    def reflect_on_security
      {
        context: @context,
        object:  @record
      }
    end

    protected

    # Raises an exception if any of the changed attributes are not valid
    # for the current security context.
    #
    # @raise [Heimdallr::PermissionError]
    def check_attributes
      @record.errors.clear

      if @record.new_record?
        action = :create
      else
        action = :update
      end

      fixtures   = @restrictions.fixtures[action]
      validators = @restrictions.validators[action]

      @record.changed.each do |attribute|
        value = @record.send attribute

        if fixtures.has_key? attribute
          if fixtures[attribute] != value
            raise Heimdallr::PermissionError,
                "Attribute #{attribute} value (#{value}) is not equal to a fixture (#{fixtures[attribute]})"
          end
        end
      end

      @record.heimdallr_validators = validators

      yield
    ensure
      @record.heimdallr_validators = nil
    end

    # Raises an exception if any of the +options+ intended for use in +save+
    # methods are potentially unsafe.
    def check_save_options(options)
      if options[:validate] == false
        raise Heimdallr::InsecureOperationError,
            "Saving while omitting validation would omit security validations too"
      end
    end
  end
end