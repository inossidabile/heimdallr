require "heimdallr"
require "active_record"
require "sqlite3"
require "logger"
require "uri"

ROOT = File.join(File.dirname(__FILE__), '..')

ActiveRecord::Base.logger = Logger.new('tmp/debug.log')
ActiveRecord::Base.configurations = YAML::load(IO.read('tmp/database.yml'))
ActiveRecord::Base.establish_connection('test')

ActiveRecord::Base.connection.create_table(:users) do |t|
  t.boolean     :admin
end

ActiveRecord::Base.connection.create_table(:articles) do |t|
  t.belongs_to  :owner
  t.text        :content
  t.integer     :secrecy_level
  t.timestamps
end