require "active_record"
require "sqlite3"
require "logger"
require "mongoid"
require "uri"

require "heimdallr" # need to require heimdallr after ORMs for orm_adapter to work

ROOT = File.join(File.dirname(__FILE__), '..')
