module Heimdallr
  # Heimdallr is attached to your models by including the module and defining the
  # restrictions in your classes.
  #
  #     class Article < ActiveRecord::Base
  #       include Heimdallr::Model
  #
  #       restrict do |context|
  #         # ...
  #       end
  #     end
  #
  # {Heimdallr::Model} should be included prior to any other modules, as it may omit
  # some named scopes defined by those if it is not.
  #
  # @todo Improve description
  module Model
    extend ActiveSupport::Concern

    # Class methods for {Heimdallr::Model}. See also +ActiveSupport::Concern+.
    module ClassMethods
      # @overload restrict
      #   Define restrictions for a model with a DSL. See {Model} overview
      #   for DSL documentation.
      #
      #   @yield A passed block is executed in the context of a new {Evaluator}.
      #
      # @overload restrict(context, action=:view)
      #   Return a secure collection object for the current scope.
      #
      #   @param [Object] context security context
      #   @param [Symbol] action  kind of actions which will be performed
      #   @return [Proxy::Collection]
      def restrict(context=nil, &block)
        if block
          @restrictions = Evaluator.new(self, block)
        else
          Proxy::Collection.new(context, restrictions(context).request_scope)
        end
      end

      # Evaluate the restrictions for a given +context+.
      #
      # @return [Evaluator]
      def restrictions(context)
        @restrictions.evaluate(context)
      end

      # @api private
      #
      # An internal attribute to store the list of user-defined name scopes.
      # It is required because ActiveRecord does not provide any introspection for
      # named scopes.
      attr_accessor :heimdallr_scopes

      # An interceptor for named scopes which adds them to {#heimdallr_scopes} list.
      def scope(name, *args)
        self.heimdallr_scopes ||= []
        self.heimdallr_scopes.push name

        super
      end
    end

    # Return a secure proxy object for this record.
    #
    # @return [Record::Proxy]
    def restrict(context)
      Proxy::Record.new(context, self)
    end

    # @api private
    #
    # An internal attribute to store the Heimdallr security validators for
    # the context in which this object is currently being saved.
    attr_accessor :heimdallr_validators

    # @api private
    #
    # An internal method to run Heimdallr security validators, when applicable.
    def heimdallr_validations
      validates_with Heimdallr::Validator
    end

    def self.included(klass)
      klass.class_eval do
        validate :heimdallr_validations
      end
    end
  end
end