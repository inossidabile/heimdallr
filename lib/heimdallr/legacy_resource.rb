module Heimdallr
  #
  # @deprecated Will be removed ASAP. Please don't use it in favour of http://github.com/roundlake/heimdallr-resource/
  #
  # Heimdallr {LegacyResource} is a boilerplate for simple creation of REST endpoints, most of which are
  # quite similar and thus may share a lot of code.
  #
  # The minimal controller possible would be:
  #
  #     class MiceController < ApplicationController
  #       include Heimdallr::Resource
  #
  #       # Class Mouse must include Heimdallr::Model.
  #       resource_for :mouse
  #     end
  #
  # Resource is built with Convention over Configuration principle in mind; that is,
  # instead of providing complex configuration syntax, Resource consists of a lot of small, easy
  # to override methods. If some kind of default behavior is undesirable, then one can just override
  # the relative method in the particular controller or, say, define a module if the changes are
  # to be shared between several controllers. You are encouraged to explore the source of this class.
  #
  # Resource allows to perform efficient operations on collections of objects. The
  # {#create}, {#update} and {#destroy} actions accept both a single object/ID or an array of
  # objects/IDs. The cardinal _modus
  #
  # Resource expects a method named +security_context+ to be defined either in the controller itself
  # or, more conveniently, in any of its ancestors, likely +ApplicationController+. This method can
  # often be aliased to +current_user+.
  #
  # Resource only works with ActiveRecord.
  #
  # See also {Resource::ClassMethods}.
  module LegacyResource
    # @group Actions

    # +GET /resources+
    #
    # This action does nothing by itself, but it has a +load_all_resources+ filter attached.
    def index
      render_data
    end

    # +GET /resource/1+
    #
    # This action does nothing by itself, but it has a +load_one_resource+ filter attached.
    def show
      render_data
    end

    # +GET /resources/new+
    #
    # This action renders a JSON representation of fields whitelisted for creation.
    # It does not include any fixtures or validations.
    #
    # @example
    #   { 'fields': [ 'topic', 'content' ] }
    def new
      render :json => {
        :fields => model.restrictions(security_context).allowed_fields[:create]
      }
    end

    # +POST /resources+
    #
    # This action creates one or more records from the passed parameters.
    # It can accept both arrays of attribute hashes and single attribute hashes.
    #
    # After the creation, it calls {#render_data}.
    #
    # See also {#load_referenced_resources} and {#with_objects_from_params}.
    def create
      with_objects_from_params(replace: true) do |object, attributes|
        restricted_model.create(attributes)
      end

      render_data verify: true
    end

    # +GET /resources/1/edit+
    #
    # This action renders a JSON representation of fields whitelisted for updating.
    # See also {#new}.
    def edit
      render :json => {
        :fields => model.restrictions(security_context).allowed_fields[:update]
      }
    end

    # +PUT /resources/1,2+
    #
    # This action updates one or more records from the passed parameters.
    # It expects resource IDs to be passed comma-separated in <tt>params[:id]</tt>,
    # and expects them to be in the order corresponding to the order of actual
    # attribute hashes.
    #
    # After the updating, it calls {#render_data}.
    #
    # See also {#load_referenced_resources} and {#with_objects_from_params}.
    def update
      with_objects_from_params do |object, attributes|
        object.update_attributes attributes
      end

      render_data verify: true
    end

    # +DELETE /resources/1,2+
    #
    # This action destroys one or more records. It expects resource IDs to be passed
    # comma-separated in <tt>params[:id]</tt>.
    #
    # See also {#load_referenced_resources}.
    def destroy
      with_objects_from_params do |object, attributes|
        object.destroy
      end

      render :json => {}, :status => :ok
    end

    protected

    # @group Configuration

    # Return the associated model class.
    # @return [Class] associated model
    def model
      self.class.model
    end

    # Return the appropriately scoped model. By default this method
    # delegates to +self.model.scoped+; you may override it for nested
    # resources so that it would only return the nested set.
    #
    # For example, this code would not allow user to perform any actions
    # with a transaction from a wrong account, raising RecordNotFound
    # instead:
    #
    #     # transactions_controller.rb
    #     class TransactionsController < ApplicationController
    #       include Heimdallr::Resource
    #
    #       resource_for :transactions
    #
    #       protected
    #
    #       def scoped_model
    #         Account.find(params[:account_id]).transactions
    #       end
    #     end
    #
    #     # routes.rb
    #     Foo::Application.routes.draw do
    #       resources :accounts do
    #         resources :transactions
    #       end
    #     end
    #
    # @return ActiveRecord scope
    def scoped_model
      self.model.all
    end

    # Return the scoped and restricted model. By default this method
    # restricts the result of {#scoped_model} with +security_context+,
    # which is expected to be defined on this class or its ancestors.
    def restricted_model
      scoped_model.restrict(security_context, implicit: true)
    end

    # Loads all resources in the current scope to +@resources+.
    #
    # Is automatically applied to {#index}.
    def load_all_resources
      @multiple_resources = true
      @resources = restricted_model
    end

    # Loads several resources from the current scope, referenced by <code>params[:id]</code>
    # with a comma-separated string like "1,2,3", to +@resources+.
    #
    # Is automatically applied to {#show}, {#update} and {#destroy}.
    def load_referenced_resources
      if params[:id][0] == '*'
        @multiple_resources = true
        @resources = restricted_model.find(params[:id][1..-1].split(','))
      else
        @multiple_resources = false
        @resource  = restricted_model.find(params[:id])
      end
    end

    # Render a modified collection in {#create}, {#update} and similar actions.
    def render_data(options={})
      if @multiple_resources
        if options[:verify] && @resources.any?(&:invalid?)
          render :json => { errors: @resources.map(&:errors) }, :status => :unprocessable_entity
        else
          render :action => :index
        end
      else
        if options[:verify] && @resource.invalid?
          render :json => @resource.errors, :status => :unprocessable_entity
        else
          render :action => :show
        end
      end
    end

    # Fetch one or several objects passed in +params+ and yield them to a block,
    # wrapping everything in a transaction.
    #
    # @yield [attributes, index]
    # @yieldparam [Hash] attributes
    # @yieldparam [Integer] index
    def with_objects_from_params(options={})
      model.transaction do
        if @multiple_resources
          begin
            name = model.name.underscore.pluralize
            if params[name].is_a? Hash
              enumerator = params[name].keys.each
            else
              enumerator = params[name].each_index
            end

            result = enumerator.map do |index|
              yield(@resources[index.to_i], params[name][index])
            end
          ensure
            @resources = result if options[:replace]
          end
        else
          begin
            result = yield(@resource, params[model.name.underscore])
          ensure
            @resource  = result if options[:replace]
          end
        end
      end
    end

    extend ActiveSupport::Concern

    # Class methods for {Heimdallr::Resource}. See also +ActiveSupport::Concern+.
    module ClassMethods
      # Returns the attached model class.
      # @return [Class]
      attr_reader :model

      # Attaches this resource to a model.
      #
      # Note that ActiveSupport +before_filter+ _replaces_ the list of actions for specified
      # filter and not appends to it. For example, the following code will only run +filter_a+
      # when +bar+ action is invoked:
      #
      #     class FooController < ApplicationController
      #       before_filter :filter_a, :only => :foo
      #       before_filter :filter_a, :only => :bar
      #
      #       def foo; end
      #       def bar; end
      #     end
      #
      # For convenience, you can pass additional actions to register with default filters in
      # +options+. It is also possible to use +append_before_filter+.
      #
      # @param [Class] model an +ActiveRecord+-derived model class
      # @option options [Array<Symbol>] :index
      #   Additional actions to be covered by {Heimdallr::Resource#load_all_resources}.
      # @option options [Array<Symbol>] :member
      #   Additional actions to be covered by {Heimdallr::Resource#load_one_resource}.
      # @option options [Array<Symbol>] :collection
      #   Additional actions to be covered by {Heimdallr::Resource#load_referenced_resources}.
      def resource_for(model, options={})
        @model = model.to_s.camelize.constantize

        before_filter :load_all_resources,        only: [ :index ].concat(options[:all] || [])
        before_filter :load_referenced_resources, only: [ :show, :update, :destroy ].concat(options[:referenced] || [])
      end
    end
  end
end