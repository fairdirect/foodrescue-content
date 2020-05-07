#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Suppress depreciation warnings from the awesome_print gem.
# TODO: Fix the gem, then remove this.
$VERBOSE = nil

# Gem includes. See Gemfile.
require 'docopt'
require "sqlite3"
require 'awesome_print'
require 'csv'


#############################################################################
# UTILITIES

version = '0.1'

# Command line documentation that's also the spec for a command line parser.
# 
# Format specs: http://docopt.org/
# Library docs: https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Export ID, category and names of the FoodKeeper database to CSV.

The CSV output can then be used for mapping FoodKeeper products comfortably to Open Food Facts 
categories. It contains an empty column "Open Food Facts Categories" for that purpose.

Usage:
    #{__FILE__} DBFILE CSVFILE
    #{__FILE__} -h | --help
    #{__FILE__} -v | --version

Options:
    -h, --help                     Show this screen.
    -v, --version                  Show version.

DOCOPT

# ## Table structure of the FoodKeeper App database
#
# @see frc-import-foodkeeper.rb
# 
# ## Column structure of the PRODUCTS table in the FoodKeeper App database
#
# @see frc-import-foodkeeper.rb


#############################################################################
# MAIN PROGRAM

# Argument parsing.
begin
    args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
    $stderr.puts e.message
    exit -1
end

# Convert FoodKeeper product SQLite3 database records to CSV records.
begin
    db = SQLite3::Database.new args['DBFILE'], { results_as_hash: true }

    csv_headers = [ 
        'Product ID', 
        'FoodKeeper Category', 
        'FoodKeeper Subcategory', 
        'Product Name', 
        'Product Subtitle', 
        'Open Food Facts Categories'
    ]
    csv = CSV.open args['CSVFILE'], "wb", { headers: csv_headers, write_headers: true }

    # Load each FoodKeeper product (in English) and convert it to a CSV entry.
    query = "
        SELECT PRODUCTS.ID, Category_Name, Subcategory_Name, Name, Name_subtitle 
        FROM PRODUCTS 
            INNER JOIN FOOD_CATEGORY ON PRODUCTS.Category_ID = FOOD_CATEGORY.ID 
        ORDER BY Category_Name, Subcategory_Name, Name, Name_subtitle
    "
    db.execute(query) do |product|
        csv << product
                    .slice('ID', 'Category_Name', 'Subcategory_Name', 'Name', 'Name_subtitle')
                    .values
                    .append('') # The unfilled "Open Food Facts Categories" column.
    end
rescue ArgumentError => e
    $stderr.puts e.message
    $stderr.puts e.backtrace
    exit -1
ensure
    db.close if db
    csv.close if csv
end
