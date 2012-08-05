require 'spec_helper'
require 'active_record/models'

require 'proxy_examples'

describe Heimdallr::Proxy do
  context 'with ActiveRecord' do
    run_specs(ActiveRecord::User, ActiveRecord::Article, ActiveRecord::DontSave)
  end
end
