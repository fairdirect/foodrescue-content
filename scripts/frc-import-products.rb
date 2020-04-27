#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Gem includes. See Gemfile.
require 'docopt'
require "csv"
require "sqlite3"

# Local, non-gem includes.
require_relative 'food_rescue_database'
require_relative 'utils'


#############################################################################
# UTILITIES

version = '0.1'

# Command line documentation that's also the spec for a command line parser.
# 
# Format specs:
#   http://docopt.org/
# Library docs:
#   https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Import Open Food Facts products from CSV into a SQLite3 database.

The script reads all CSV entries from INFILE and writes the converted data to the SQLite3 database 
DBFILE. It expects table categories to exist (with columns name and lang) and will add some more tables.

Currently, only the following data is imported:

1. barcode number (formally GTIN, a superset of EAN, ISBN and various UPCs)
2. category memberships

Products without categories are not imported.

Usage:
    #{__FILE__} [options] INFILE DBFILE
    #{__FILE__} -h | --help
    #{__FILE__} -v | --version

Options:
    -c, --continue      Import the data into existing database tables.
    -h, --help          Show this screen.
    -v, --version       Show version.

DOCOPT


#############################################################################
# MAIN PROGRAM

# (1) Set up.
# ----------------------------------------------------------

# Argument parsing.
begin
    args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
    puts e.message
end


# (2) Import products.
# ----------------------------------------------------------

begin
    db = FoodRescueDatabase.new args['DBFILE']
    db.prepare_product_tables(args['--continue'])

    # To keep the memory footprint small, read one line at a time with CSV.foreach().
    # See: "Processing large CSV files with Ruby", https://dalibornasevic.com/posts/68
    CSV.foreach(args['INFILE'], { headers: true }) do |record|
      
        code = Integer(record['code'], 10) # Interpret as base-10 integer. Otherwise leading zeroes would be an octal literal.
        countries = if record['countries_en'].nil?  then [] else record['countries_en'].split(',') end
        categories = if record['categories_en'].nil? then [] else record['categories_en'].split(',') end

        # Transform categories array to array of {lang: '…', name: '…'} elements. Default language is English.
        categories = categories.filter_map do |cat|
            # Ignore categories given as a category tag (such as "fr:test-tag") rather than the full name.
            # TODO (later): Also process tag-type categories. It requires adding the category tags to the database.
            #     But, the cleaner option is to remove the (inconsistent) use of category tags from the OFF CSV file.
            #
            # NOTE: Category names in the Open Food Facts CSV export may have a language prefix ("fr:") but do not 
            # have a language tag ("fr-BE:") prefix. The latter only appears in the Open Food Facts category taxonomy.
            next if /^[a-z][a-z]:[a-z-]+$/.match?(cat)

            if match = /^([a-z][a-z]):(.+)$/.match(cat)
                lang, name = match.captures
            else 
                lang = 'en'
                name = cat
            end

            { lang: lang, name: name }
        end

        db.add_product code, categories, countries
    end
rescue => e
    puts "ERROR: ".in_red + e.message
ensure
    db.close if db
end
