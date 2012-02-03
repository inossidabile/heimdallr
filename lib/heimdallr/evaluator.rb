module Heimdallr
  # Evaluator is a DSL for managing permissions on records with the field granularity.
  # It works by evaluating a block of code on a given _security context_.
  #
  # The default action is to forbid everything--that is, Heimdallr security policy
  # is whitelisting safe actions, not blacklisting unsafe ones. This is by design
  # and is not going to change.
  #
  # The DSL mainly consists of two functions, can and cannot
  class Evaluator
    attr_reader :whitelist, :validations

    # Create a new Evaluator for the ActiveModel-descending class +model_class+,
    # and use +block+ to infer restrictions for any security context passed.
    def initialize(model_class, block)
      @model_class, @block = model_class, block

      @whitelist = @validations = nil
      @last_context = nil
    end


    def can(actions, fields=@model_class.attribute_names)
      actions = Array(actions)

      case fields
      when Hash # a list of validations
        actions.each do |action|
          @whitelist[action]   += fields.keys
          @validations[action] += make_validators(fields)
        end

      else # an array or a field name
        actions.each do |action|
          @whitelist[action] += Array(fields)
        end
      end
    end

    def cannot(actions, fields)
      actions = Array(actions)

      actions.each do |action|
        @whitelist[action] -= fields
      end
    end

    def evaluate(context)
      if context != @last_context
        @whitelist   = Hash.new { [] }
        @validations = Hash.new { [] }

        instance_exec context, &block

        @whitelist.freeze
        @validations.freeze

        @last_context = context
      end

      self
    end

    def validate(action, record)
      @validations[action].each do |validator|
        validator.validate(record)
      end
    end

    protected

    def make_validators(fields)
      validators = []

      fields.each do |attribute, validations|
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

    def _parse_validates_options(options) #:nodoc:
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