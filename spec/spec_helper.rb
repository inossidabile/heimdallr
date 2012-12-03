require "active_record"
require "logger"
require "uri"
require "pry"

require RUBY_PLATFORM =~ /java/ ? "activerecord-jdbc-adapter" : "sqlite3"

require "heimdallr" # need to require heimdallr after ORMs for orm_adapter to work

ROOT = File.join(File.dirname(__FILE__), '..')
