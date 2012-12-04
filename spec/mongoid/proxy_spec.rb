require 'spec_helper'
require 'mongoid/models'

require 'proxy_examples'

if ENV['ENABLE_MONGO']
  describe Heimdallr::Proxy do
    context 'with Mongoid' do
      run_specs(Mongoid::User, Mongoid::Article, Mongoid::DontSave)

      context 'with subclass' do
        run_specs(Mongoid::User, Mongoid::SubArticle, Mongoid::DontSave)
      end
    end
  end
end
