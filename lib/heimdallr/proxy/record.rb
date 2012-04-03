module Heimdallr
  # A security-aware proxy for individual records. This class validates all the
  # method calls and either forwards them to the encapsulated object or raises
  # an exception.
  #
  # The #touch method call isn't considered a security threat and as such, it is
  # forwarded to the underlying object directly.
  #
  # Record proxies can be of two types, implicit and explicit. Implicit proxies
  # return +nil+ on access to methods forbidden by the current security context;
  # explicit proxies raise an {Heimdallr::PermissionError} instead.
  class Proxy::Record
    # Create a record proxy.
    #
    # @param context  security context
    # @param object   proxified record
    # @option options [Boolean] implicit proxy type
    def initialize(context, record, options={})
      @context, @record, @options = context, record, options

      @restrictions = @record.class.restrictions(context, record)
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
      @record.attributes.tap do |attributes|
        attributes.keys.each do |key|
          unless @restrictions.allowed_fields[:view].include? key.to_sym
            attributes[key] = nil
          end
        end
      end
    end

    # A proxy for +update_attributes+ method.
    # See also {#save}.
    #
    # @raise [Heimdallr::PermissionError]
    def update_attributes(attributes, options={})
      @record.with_transaction_returning_status do
        @record.assign_attributes(attributes, options)
        save
      end
    end

    # A proxy for +update_attributes!+ method.
    # See also {#save!}.
    #
    # @raise [Heimdallr::PermissionError]
    def update_attributes!(attributes, options={})
      @record.with_transaction_returning_status do
        @record.assign_attributes(attributes, options)
        save!
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
        if scope.where({ @record.class.primary_key => @record.to_key }).any?
          @record.#{method}
        else
          raise PermissionError, "Deletion is forbidden"
        end
      end
      EOM
    end

    # @method valid?
    # @macro delegate
    delegate :valid?, :to => :@record

    # @method invalid?
    # @macro delegate
    delegate :invalid?, :to => :@record

    # @method errors
    # @macro delegate
    delegate :errors, :to => :@record

    # @method assign_attributes
    # @macro delegate
    delegate :assign_attributes, :to => :@record

    # @method attributes=
    # @macro delegate
    delegate :attributes=, :to => :@record

    # Class name of the underlying model.
    # @return [String]
    def class_name
      @record.class.name
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

      if (defined?(ActiveRecord) && @record.is_a?(ActiveRecord::Reflection) &&
          association = @record.class.reflect_on_association(method)) ||
         (!@record.class.heimdallr_relations.nil? &&
          @record.class.heimdallr_relations.include?(normalized_method))
        referenced = @record.send(method, *args)

        if referenced.nil?
          nil
        elsif referenced.respond_to? :restrict
          referenced.restrict(@context, @options)
        elsif Heimdallr.allow_insecure_associations
          referenced
        else
          raise Heimdallr::InsecureOperationError,
              "Attempt to fetch insecure association #{method}. Try #insecure"
        end
      elsif @record.respond_to? method
        if [nil, '?'].include?(suffix)
          if @restrictions.allowed_fields[:view].include?(normalized_method)
            @record.send method, *args, &block
          elsif @options[:implicit]
            nil
          else
            raise Heimdallr::PermissionError, "Attempt to fetch non-whitelisted attribute #{method}"
          end
        elsif suffix == '='
          @record.send method, *args
        else
          raise Heimdallr::PermissionError,
              "Non-whitelisted method #{method} is called for #{@record.inspect} "
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

    # Return an implicit variant of this proxy.
    #
    # @return [Heimdallr::Proxy::Record]
    def implicit
      Proxy::Record.new(@context, @record, @options.merge(implicit: true))
    end

    # Return an explicit variant of this proxy.
    #
    # @return [Heimdallr::Proxy::Record]
    def explicit
      Proxy::Record.new(@context, @record, @options.merge(implicit: false))
    end

    # Describes the proxy and proxified object.
    #
    # @return [String]
    def inspect
      "#<Heimdallr::Proxy::Record: #{@record.inspect}>"
    end

    # Return the associated security metadata. The returned hash will contain keys
    # +:context+, +:record+, +:options+, corresponding to the parameters in
    # {#initialize}, and +:model+, representing the model class.
    #
    # Such a name was deliberately selected for this method in order to reduce namespace
    # pollution.
    #
    # @return [Hash]
    def reflect_on_security
      {
        model:   @record.class,
        context: @context,
        record:  @record,
        options: @options
      }.merge(@restrictions.reflection)
    end

    def creatable?
      @restrictions.can? :create
    end

    def modifiable?
      @restrictions.can? :update
    end

    def destroyable?
      scope = @restrictions.request_scope(:delete)
      scope.where({ @record.class.primary_key => @record.to_key }).any?
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

      allowed_fields = @restrictions.allowed_fields[action]
      fixtures       = @restrictions.fixtures[action]
      validators     = @restrictions.validators[action]

      @record.changed.map(&:to_sym).each do |attribute|
        value = @record.send attribute

        if fixtures.has_key? attribute
          if fixtures[attribute] != value
            raise Heimdallr::PermissionError,
                "Attribute #{attribute} value (#{value}) is not equal to a fixture (#{fixtures[attribute]})"
          end
        elsif !allowed_fields.include? attribute
          raise Heimdallr::PermissionError,
              "Attribute #{attribute} is not allowed to change"
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

      if @record.new_record?
        unless @restrictions.can? :create
          raise Heimdallr::InsecureOperationError,
              "Creating was not explicitly allowed"
        end
      else
        unless @restrictions.can? :update
          raise Heimdallr::InsecureOperationError,
              "Updating was not explicitly allowed"
        end
      end
    end
  end
end