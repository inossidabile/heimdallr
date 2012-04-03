require "heimdallr"
require "active_record"
require "sqlite3"
require "logger"
require "uri"

ROOT = File.join(File.dirname(__FILE__), '..')

ActiveRecord::Base.logger = Logger.new('tmp/debug.log')
ActiveRecord::Base.configurations = YAML::load(IO.read('tmp/database.yml'))
ActiveRecord::Base.establish_connection('test')

RSpec.configure do |config|
  # See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
end
