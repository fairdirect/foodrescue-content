#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Gem includes. See Gemfile.
require 'docopt'
require 'parslet'
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
#   http://docopt.org/
# Library docs:
#   https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Import the Open Food Facts category taxonomy into a SQLite3 database.

The script reads a file given by INFILE and writes the converted data to a SQLite3 database 
given by DBFILE. DBFILE will be created if it does not exist. INFILE must be in the Open Food Facts 
category taxonomy file format, as seen here: 
https://github.com/openfoodfacts/openfoodfacts-server/blob/master/taxonomies/categories.txt

Currently, only the following information is converted into SQLite3 format:

1. first category name in English
2. hierarchy information about parent categories

Usage:
  #{__FILE__} [options] INFILE DBFILE
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  -h, --help                     Show this screen.
  -v, --version                  Show version.

DOCOPT


# Parser for Open Food Facts category hierarchy definition files.
# 
# TODO Adapt the parser to also understand the (slightly different) categories.result.txt file. Changes:
#   There can be a space after the "<" sign indicating a parent category. There can be a space after the property marker.
# 
# Data example:
#   https://github.com/openfoodfacts/openfoodfacts-server/blob/master/taxonomies/categories.txt
#   https://github.com/openfoodfacts/openfoodfacts-server/blob/master/taxonomies/categories.result.txt (later)
# Parser library docs:
#   https://github.com/kschiess/parslet
#   https://kschiess.github.io/parslet
class CatHierarchyParser < Parslet::Parser

  # Characters
  rule(:space) { match('\s').repeat(1) }
  rule(:less) { str('<') }
  rule(:colon) { str(':') }
  rule(:comma) { str(',') }
  rule(:hash) { str('#') }
  rule(:underscore) { str('_') }
  rule(:dash) { str('-') }
  rule(:newline) { str("\n") }
  rule(:lowercase) { match('[a-z]') }
  rule(:uppercase) { match('[A-Z]') }
  rule(:digits) { match('[0-9]') }
  
  # Small things
  rule(:singlevalue) { match('[^\n]').repeat(1) }
  rule(:value) { match('[^,\n]').repeat(1) }
  rule(:values) { space.maybe >> value.as(:value) >> (comma >> values).repeat(0) }
  # ISO 3166-1 alpha-2 country code.
  # See: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  rule(:country_code) { uppercase.repeat(2,2) }
  # ISO 639-1 (two letter) or ISO 639-3 (three letter) language code.
  # See https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
  rule(:lang_code) { lowercase.repeat(2,3) }
  # Language tag.
  # See: https://en.wikipedia.org/wiki/Language_localisation#Language_tags_and_codes
  # Command to see all available :lang_tag literals in a file:
  #   grep --extended-regexp --only-matching --no-filename "^[a-z]{2,3}-[A-Z]{2,2}:|^[a-z]{2,3}:" file.txt | sort -u | less
  rule(:lang_tag) { lang_code >> (dash >> country_code).maybe }
  rule(:property_name) { (lowercase | digits) >> (lowercase | digits | underscore).repeat(1) }

  # Lines and blocks
  rule(:blank_line) { newline }
  rule(:blank_lines) { blank_line.repeat(1) }
  rule(:comment_line) { hash >> space.maybe >> singlevalue >> newline }
  rule(:comment_lines) { comment_line.repeat(1) }
  rule(:synonym_line) { str('synonyms') >> colon >> lang_tag.as(:lang) >> colon >> values.as(:synonyms) >> newline }
  rule(:synonym_lines) { comment_lines.maybe >> synonym_line >> (synonym_line | comment_line).repeat(0) }
  rule(:stopword_line) { str('stopwords') >> colon >> lang_tag.as(:lang) >> colon >> values.as(:stopwords) >> newline }
  rule(:stopword_lines) { comment_lines.maybe >> stopword_line >> (stopword_line | comment_line).repeat(0) }
  rule(:parent_line) { less >> lang_tag.as(:lang) >> colon >> value.as(:cat_name) >> newline }
  rule(:parent_lines) { comment_lines.maybe >> parent_line >> (parent_line | comment_line).repeat(0) }
  rule(:name_line) { lang_tag.as(:lang) >> colon >> values.as(:cat_names) >> newline }
  rule(:name_lines) { comment_lines.maybe >> name_line >> (name_line | comment_line).repeat(0) }
  rule(:property_line) { property_name.as(:name) >> colon >> (lang_tag.as(:lang) >> colon).maybe >> singlevalue.as(:value) >> newline }
  rule(:property_lines) { comment_lines.maybe >> property_line >> (property_line | comment_line).repeat(0) }
  rule(:category_lines) { parent_lines.maybe.as(:parents) >> name_lines.as(:names) >> property_lines.maybe.as(:properties) }
  # 
  # In the :block rule, "| comment_lines" must come last. Parslet is a PEG type parser generator, which does not tolerate 
  # ambiguity. So it will apply the first match from a rule, rather than be aware of more than one parallel matching possibility. 
  # If the first match is the simpler possibility, the parser will throw an error when it does not apply further down the line, 
  # and will not try the more complex possibility afterwards. So instead, the simplest possibility has to come last. This way, 
  # a comment line at the start of the block is first interpreted as a non-comment block, and only if not possible, as a comment 
  # block.
  rule(:block) { synonym_lines.as(:synonym_block) | stopword_lines.as(:stopword_block) | category_lines.as(:category_block) | comment_lines }
  rule(:file) { block >> (blank_lines >> block).repeat(0) >> blank_lines.maybe }

  root(:file)
end


# Open the specified file if possible. Raise ValueError if not.
def test_and_open(path)
  unless File.exists?(path) && File.file?(path) && File.readable?(path) then
    raise ValueError("%s is not a file or not accessible" % path)
  end

  File.open(path,'r')
end


# Transform a nested Object / Hash / Array structure to a nested Hash / Array structure.
# 
# @param obj [Array<...>|Hash<...>|Object]  The data structure to transform.
# @return  The transformed data structure, containing references to any unmodified object from the 
# original data structure.
def to_hash_recursive(obj)

  # Array to Array.
  return obj.collect { |v| to_hash_recursive(v) } if obj.is_a? Array

  # Object and Hash to Hash. (Hash#to_hash returns self. There is no Array#to_hash.)
  return obj.to_hash.transform_values { |v| to_hash_recursive(v) } if obj.respond_to?(:to_hash)

  # pp 'DEBUG: ', obj.to_s, ' is a ', obj.class

  # Nil to Nil.
  return nil if obj.nil?

  # Certain objects to String.
  return obj.to_s if obj.is_a? Parslet::Slice

  # Everything else verbatim.
  return obj
end


# Wrap the given object into an array, except it is an array already.
# 
# Note that the result of wrapping `nil` is `[]` and not `[nil]` because iterating over no value should not 
# execute anything.
# 
# TODO The name is not great, as wrapping is not done always but conditionally.
# 
# @param obj [mixed]  An Object, Hash, Array or nil.
# @return The wrapped object.
def wrap_in_array(obj)
  return [] if obj.nil?
  return [obj] unless obj.is_a? Array
  return obj
end


# Perform global substitutions on the given text to fix known issues with the OFF categories.txt file.
def fix_taxonomy_text(text)
  text
    .gsub(/^nl_be:/, 'nl-BE:')
    .gsub(/^stopwords:nl_be:/, 'stopwords:nl-BE:')
    .gsub(/^el, el:/, 'el:')
    .gsub("<it:Colli Tortonesi\n\n", "\n\n\n")
    .gsub('<fr:Champagnes extra dry', 'fr:Champagnes extra dry')
    .gsub('<fr:Champagnes secs', 'fr:Champagnes secs')
    .gsub('<fr:Champagnes demi-secs', 'fr:Champagnes demi-secs')
    .gsub('<fr:Champagnes doux', 'fr:Champagnes doux')
    .gsub('<fr:Champagnes blancs de blancs, Blancs de blancs, Blanc de blancs', 
      'fr:Champagnes blancs de blancs, Blancs de blancs, Blanc de blancs')
    .gsub('<fr:Champagnes blancs de noirs, Blancs de noirs, Blanc de noirs', 
      'fr:Champagnes blancs de noirs, Blancs de noirs, Blanc de noirs')
    .gsub(/^"en:/, 'en:')
    .gsub(/^Country:en:/, 'country:en:')
    .gsub(/^<:Nuts/, '<en:Nuts')
    .gsub(/^nl:Bosbestaart\nn:Bosbessentaarten/, 'nl:Bosbestaart, Bosbessentaarten')
    .gsub('nl:Forelterinnes, Forelterrine,', 'nl:Forelterinnes, Forelterrine')
end


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


# (2) Parse categories.txt into an in-memory data structure.
# ----------------------------------------------------------

taxonomy_file = test_and_open(args['INFILE'])
taxonomy_text = taxonomy_file.read
taxonomy_file.close

# Fix known issues in the Open Food Facts categories.txt file.
taxonomy_text = fix_taxonomy_text(taxonomy_text)

# Parse the file.
parser = CatHierarchyParser.new

begin
  taxonomy = parser.parse(taxonomy_text)
rescue Parslet::ParseFailed => failure
  puts failure.parse_failure_cause.ascii_tree
end


# (3) Simplify the intermediate tree generated by parsing.
# --------------------------------------------------------

# Convert from Parslet::* objects to a nested Hash-and-Arrays structure.
# (Parslet objects are structured like Hashes, but do not support all its methods which we'll need later.)
taxonomy = to_hash_recursive(taxonomy)

# TODO: Simplify the taxonomy data structure. Namely: taxonomy[i][:category_block][:parents] and 
# taxonomy[i][:category_block][:names] should have a structure of [ {lang: …, name: …}, … ].
# 
# This cannot be directly done in the parser as everything it should recognize has to have a name there. That's why the 
# parser output is called "intermediate tree", needing further adjustments.

# Normalize the hash structure so that all repeatable hashes are enclosed in arrays to be iterable.
# @see CatDatabase#write_cat_names  Documents the resulting data structure.
taxonomy.map! do |block|

  if block.key?(:category_block) then
    block[:category_block][:parents]    = wrap_in_array(block[:category_block][:parents])
    block[:category_block][:names]      = wrap_in_array(block[:category_block][:names])
    block[:category_block][:names].map! { |elem| elem[:cat_names] = wrap_in_array(elem[:cat_names]); elem }
    block[:category_block][:properties] = wrap_in_array(block[:category_block][:properties])
  end

  # TODO (later): Do the equivalent for synonym blocks and stopword blocks. With the current dataset, all of them have at least two 
  # elements so no wrapping is needed, but this is not guaranteed for the future.

  block
end


# (4) Save category names and parents to a SQLite database.
# ---------------------------------------------------------

begin

  # Database connection.
  db = FoodRescueDatabase.new args['DBFILE']
  db.prepare_category_tables

  # Write categories to SQLite.
  taxonomy.each do |block| 
    db.add_category(block[:category_block]) if block.key?(:category_block)
  end

  # Write category hierarchy to SQLite.
  # (Referencing a parent category requires all categories exist, so we need this second phase.)
  taxonomy.each do |block| 
    db.add_category_parents(block[:category_block]) if block.key?(:category_block)
  end

rescue ArgumentError => e
  puts e.message
ensure
  db.close if db
end
