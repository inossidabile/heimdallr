module Heimdallr
  # Evaluator is a DSL for managing permissions on records with the field granularity.
  # It works by evaluating a block of code within a given <em>security context</em>.
  #
  # The default resolution is to forbid everything--that is, Heimdallr security policy
  # is whitelisting safe actions, not blacklisting unsafe ones. This is by design
  # and is not going to change.
  #
  # The field +#id+ is whitelisted by default.
  #
  # The DSL consists of three functions: {#scope}, {#can} and {#cannot}.
  class Evaluator
    attr_reader :allowed_fields, :fixtures, :validators

    # Create a new Evaluator for the +ActiveRecord+-derived class +model_class+,
    # and use +block+ to infer restrictions for any security context passed.
    def initialize(model_class, block)
      @model_class, @block = model_class, block

      @scopes         = {}
      @allowed_fields = {}
      @validators     = {}
      @fixtures       = {}
    end

    # @group DSL

    # Define a scope. A special +:fetch+ scope is applied to any other scope
    # automatically.
    #
    # @overload scope(name, block)
    #   This form accepts an explicit lambda.
    #
    #   @example
    #       scope :fetch, -> { where(:protected => false) }
    #
    # @overload scope(name)
    #   This form accepts an implicit lambda.
    #
    #   @example
    #       scope :fetch do |user|
    #         if user.manager?
    #           scoped
    #         else
    #           where(:invisible => false)
    #         end
    #       end
    def scope(name, explicit_block, &implicit_block)
      @scopes[name] = explicit_block || implicit_block
    end

    # Define allowed operations for action(s).
    #
    # The +fields+ parameter accepts both Arrays and Hashes.
    # * If an +Array+ is passed, then all fields present in the array are whitelised.
    # * If a +Hash+ is passed, then all fields present as hash keys are whitelisted, and:
    #   1. If a corresponding value is a +Hash+, it will be processed as a security
    #      validator. Security validators make records invalid when they are saved through
    #      a {Proxy::Record}.
    #   2. If the corresponding value is any other object, it will be added as a security
    #      fixture. Fixtures are merged when objects are created through restricted scopes,
    #      and cause exceptions to be raised when a record is saved, even through the +#save+
    #      method.
    #
    # @example Array of fields
    #   can :view, [:title, :content]
    #
    # @example Fixtures
    #   can :create, { owner: current_user }
    #
    # @example Validations
    #   can [:create, :update], { priority: { inclusion: 1..10 } }
    #
    # @param [Symbol, Array<Symbol>] actions one or more action names
    # @param [Hash<Hash, Object>] fields field restrictions
    def can(actions, fields=@model_class.attribute_names)
      Array(actions).map(&:to_sym).each do |action|
        case fields
        when Hash # a list of validations
          @allowed_fields[action] += fields.keys.map(&:to_sym)
          @validators[action]     += create_validators(fields)

          fixtures = extract_fixtures(fields)
          @fixtures[action] = @fixtures[action].merge fixtures
          @allowed_fields[action] -= fixtures.keys

        else # an array or a field name
          @allowed_fields[action] += Array(fields).map(&:to_sym)
        end
      end
    end

    # Revoke a permission on fields.
    #
    # @todo Revoke validating restrictions.
    # @param [Symbol, Array<Symbol>] actions one or more action names
    # @param [Array<Symbol>] fields field list
    def cannot(actions, fields)
      Array(actions).map(&:to_sym).each do |action|
        @allowed_fields[action] -= fields.map(&:to_sym)
        @fixtures.delete_at *fields
      end
    end

    # @endgroup

    # Request a scope. Returns +nil+ if it does not exist.
    #
    # @param scope name of the scope
    # @param basic_scope the scope to which scope +name+ will be applied. Defaults to +:fetch+.
    #
    # @return +ActiveRecord+ scope or +nil+
    def request_scope(name=:fetch, basic_scope=nil)
      if name == :fetch && basic_scope.nil?
        @model_class.instance_exec(&@scopes[:fetch])
      elsif @scopes.has_key?(name)
        (basic_scope || request_scope(:fetch)).instance_exec(&@scopes[name])
      else
        nil
      end
    end

    # Compute the restrictions for a given +context+. Invokes a +block+ passed to the
    # +initialize+ once.
    #
    # @raise [RuntimeError] if the evaluated block did not define a set of valid restrictions
    def evaluate(context)
      if context != @last_context
        @scopes         = {}
        @allowed_fields = Hash.new { [] }
        @validators     = Hash.new { [] }
        @fixtures       = Hash.new { {} }

        @allowed_fields[:view] += [ :id ]

        instance_exec context, &@block

        unless @scopes[:fetch]
          raise RuntimeError, "A :fetch scope must be defined"
        end

        @allowed_fields.each do |action, fields|
          fields.uniq!
        end

        [@scopes, @allowed_fields, @validators, @fixtures].
              map(&:freeze)

        @last_context = context
      end

      self
    end

    protected

    # Create validators for +fields+ in +ActiveModel::Validations+-like way.
    #
    # @return [Array<ActiveModel::Validator>]
    def create_validators(fields)
      validators = []

      fields.each do |attribute, validations|
        next unless validations.is_a? Hash

        validations.each do |key, options|
          key = "#{key.to_s.camelize}Validator"

          begin
            validator = key.include?('::') ? key.constantize : ActiveModel::Validations.const_get(key)
          rescue NameError
            raise ArgumentError, "Unknown validator: '#{key}'"
          end

          validators << validator.new(_parse_validates_options(options).merge(:attributes => [ attribute ]))
        end
      end

      validators
    end

    # Collects fixtures from the +fields+ definition.
    def extract_fixtures(fields)
      fixtures = {}

      fields.each do |attribute, options|
        next if options.is_a? Hash

        fixtures[attribute.to_sym] = options
      end

      fixtures
    end

    private

    # Monkey-copied from ActiveRecord.
    def _parse_validates_options(options)
      case options
      when TrueClass
        {}
      when Hash
        options
      when Range, Array
        { :in => options }
      else
        { :with => options }
      end
    end
  end
end