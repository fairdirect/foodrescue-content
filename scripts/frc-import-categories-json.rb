#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Gem includes. See Gemfile.
require 'docopt'
require 'json_schemer'
require "sqlite3"
require 'awesome_print'

# Local, non-gem includes.
require_relative 'food_rescue_database'


#############################################################################
# UTILITIES

version = '0.1'

# Command line documentation that's also the spec for a command line parser.
# 
# Format specs:
#     http://docopt.org/
# Library docs:
#     https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Import Open Food Facts JSON API content about categories into a SQLite3 database.

The script reads a file given by INFILE and writes the converted data to a SQLite3 database 
given by DBFILE. DBFILE must contain a table "categories" with a column "product_count". 
INFILE must be in the format in which categories are described by the Open Food Facts JSON API, as seen here: 
https://world.openfoodfacts.org/category/categories

Currently, only the following information is converted into SQLite3 format:

1. product counts per category

Usage:
    #{__FILE__} [options] INFILE DBFILE
    #{__FILE__} -h | --help
    #{__FILE__} -v | --version

Options:
    -h, --help                      Show this screen.
    -v, --version                   Show version.

DOCOPT


# Open the specified file if possible. Raise ValueError if not.
def test_and_open(path)
    unless File.exists?(path) && File.file?(path) && File.readable?(path) then
        raise ValueError("%s is not a file or not accessible" % path)
    end
  
    File.open(path,'r')
end
  

# JSON Schema Draft 7 for Open Food Facts category data JSON files.
# 
# Data example:
#     https://world.openfoodfacts.org/category/categories
# JSON Schema specs: 
#     https://json-schema.org/draft/2019-09/json-schema-core.html
# Library docs:
#     https://github.com/davishmcclurg/json_schemer
# How to create this schema:
#     1. Create a short example JSON file with example data.
#     2. Use https://www.jsonschema.net/home to convert to a JSON Schema in JSON.
#     3. Use https://codepen.io/jakealbaugh/full/WrLmyG to convert the JSON to a Ruby hash.
#     4. Make sure the schema does not use Ruby symbols as hash keys, as that woul lead to JSONSchemer::InvalidSymbolKey later.
#     5. Remove unnecessary parts and add missing parts (here for "sameAs").
schema = { 
    '$schema' => 'http://json-schema.org/draft-07/schema#',
    'type' => 'object', 
    'required' => [ 'count', 'tags' ],
    'properties' => {
        'count' => {
            '$id' => '#/properties/count', 
            'type' => 'integer'
        },
        'tags' => {
            '$id' => '#/properties/tags', 
            'type' => 'array', 
            'items' => {
                '$id' => '#/properties/tags/items', 
                'type' => 'object', 
                'additionalProperties' => true,
                'required' => [ 'url', 'id', 'name', 'known', 'products' ],
                'properties' => {
                    'url' => {
                        '$id' => '#/properties/tags/items/properties/url', 
                        'type' => 'string'
                    },
                    'id' => {
                        '$id' => '#/properties/tags/items/properties/id', 
                        'type' => 'string'
                    },
                    'name' => {
                        '$id' => '#/properties/tags/items/properties/name', 
                        'type' => 'string'
                    },
                    'known' => {
                        '$id' => '#/properties/tags/items/properties/known', 
                        'type' => 'integer'
                    },
                    'products': {
                        '$id': '#/properties/tags/items/properties/products', 
                        'type': 'integer'
                    },
                    'sameAs' => {
                        '$id' => '#/properties/tags/items/properties/sameAs', 
                        'type' => 'array',
                        'items' => [{
                            # In JSON Schema, a one-elememt array of hashes limits the number of allowed array elements to "1". 
                            # See: https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.3.1.1
                            '$id' => '#/properties/tags/items/properties/sameAs/items', 
                            'type' => 'string'
                        }]
                    }
                }
            }
        }
    }
}
  

#############################################################################
# MAIN PROGRAM

# (1) Set up.
# ----------------------------------------------------------

# Argument parsing.
begin
    args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
    puts e.message
    exit
end


# (2) Read the JSON input file into a nested Hash-and-Arrays data structure.
# --------------------------------------------------------------------------

schemer = JSONSchemer.schema(schema)
json_file = test_and_open(args['INFILE'])

json = JSON.parse(json_file.read)

# Validate the JSON file against a schema.
# TODO (later): Switch the following to validate() and show the error if there is one.
raise ("%s does not contain a valid JSON file" % path) unless schemer.valid?(json)

json_file.close

# puts "DEBUG: data as read from JSON (excerpt):"
# ap json, {limit: true}

# TODO: Convert json so that Ruby symbols can be used as Hash keys, not only strings like now.


# (3) Import categories that are not present in the Open Food Facts taxonomy (categories.txt).
# --------------------------------------------------------------------------------------------

# TODO


# (4) Export product count information from the JSON file to the SQLite database.
# -------------------------------------------------------------------------------

begin

    db = FoodRescueDatabase.new args['DBFILE']

    json['tags'].each do |cat|
        # For now, we do not import non-taxonomy (known == 0) categories. 
        # So for speed, no need to even consider them when importing product counts.
        if cat['known']
            # puts "DEBUG: Going to add product_count of #{cat['products']} for '#{cat['name']}'"
            db.add_product_count(cat['name'], cat['products']) 
        end
    end

rescue ArgumentError => e
    puts e.message
ensure
    db.close if db
end
