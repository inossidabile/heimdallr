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
          @restrictions = Evaluator.new(self, &block)
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
    end

    # Return a secure proxy object for this record.
    #
    # @return [Record::Proxy]
    def restrict(context, action)
      Record::Proxy.new(context, self)
    end

    # @api private
    #
    # An internal attribute to store the Heimdallr security validators for
    # the context in which this object is currently being saved.
    attr_accessor :heimdallr_validators

    def self.included(klass)
      klass.const_eval do
        validates_with Heimdallr::Validator
      end
    end
  end
end