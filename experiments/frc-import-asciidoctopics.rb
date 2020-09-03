#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Suppress depreciation warnings from the awesome_print gem.
# @todo Fix the gem, then remove this.
$VERBOSE = nil

# Gem includes. See Gemfile.
require 'docopt'
require "sqlite3"
require 'awesome_print'

# Local, non-gem includes.
require_relative '../lib/topic'


#############################################################################
# UTILITIES

version = '0.1'

# Command line documentation that's also the spec for a command line parser.
# 
# Format specs: http://docopt.org/
# Library docs: https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Imports topics in AsciiDoctor files into the Food Rescue Content SQLite3 database.

The topics can be in plain AsciiDoc format or the (extended but compatible) Asciidoctor format.

THIS SCRIPT IS NOT YET COMPLETE.

Usage:
  #{__FILE__} TOPICFILE.. DBFILE
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  -h, --help                     Show this screen.
  -v, --version                  Show version.

DOCOPT


#############################################################################
# MAIN PROGRAM

# @todo Complete the implementation dependencies to make this script functional: FoodRescue::Topic#initialize, 
#   FoodRescue::Topic#to_sqlite.

# Argument parsing.
begin
  args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
  $stderr.puts e.message
  exit -1
end

begin
  # Open the database connection.
  db = FoodRescue::Database.new args['DBFILE']
  
  # Import the topic files one by one.
  args['TOPICFILE'].each do |topicfile|
    topic = FoodRescue::Topic.new(topicfile)
    topic.to_sqlite(db)
  end
rescue ArgumentError => e
  $stderr.puts e.message
  $stderr.puts e.backtrace
  exit -1
ensure
  db.close if file_db
end
