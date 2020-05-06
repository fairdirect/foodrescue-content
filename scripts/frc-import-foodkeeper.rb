#!/usr/bin/env ruby
# NOTE: Above shebang selects the first Ruby found in $PATH and is standard practice to work with 
# multiple installed versions and version switchers like chruby; see https://stackoverflow.com/a/2792076

# Suppress depreciation warnings from the awesome_print gem.
# TODO: Fix the gem, then remove this.
$VERBOSE = nil

# Stdlib includes.
# require 'dir'

# Gem includes. See Gemfile.
require 'docopt'
require "sqlite3"
require 'awesome_print'
require 'ox'
require 'ap'

# Local, non-gem includes.
require_relative '../lib/food_rescue_topic'


#############################################################################
# UTILITIES

version = '0.1'

# Command line documentation that's also the spec for a command line parser.
# 
# Format specs: http://docopt.org/
# Library docs: https://github.com/docopt/docopt.rb
doc = <<DOCOPT
Converts the content from the USDA FoodKeeper Android app to DocBook 5.1 XML format.

The script reads the FoodKeeper database from DBFILE and writes its output XML files 
to files named PREFIXnnnn.xml, where nnnn is a 4-digit, zero-padded number. The 
convention for PREFIX is to include the author, here: "topic-foodkeeper-". If files 
with PREFIX exist, this script will refuse to run.

Full process to convert FoodKeeper data:

1. Obtain the .apk file of FoodKeeper on your desktop computer. The FoodKeeper app 
   is linked from the FoodKeeper website (https://www.foodsafety.gov/keep-food-safe/foodkeeper-app).
   A good, cross-platform option is using Raccoon (https://raccoon.onyxbits.de/).
2. Install apktool: `sudo apt install apktool`
3. Use apktool to decode (unzip and decompile) the APK package: 
   apktool decode gov.usda.fsis.foodkeeper2-46.apk
4. Get the database out of the decoded files:
   cp gov.usda.fsis.foodkeeper2-46/assets/databases/foodkeeper.db FoodKeeper.sqlite3
5. Run this script to convert database contents to knowledge items in DocBook format:
   frc-createcontent-foodkeeper.rb FoodKeeper.sqlite3

Usage:
  #{__FILE__} DBFILE PREFIX
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  -h, --help                     Show this screen.
  -v, --version                  Show version.

DOCOPT

# ## Structure of the FoodKeeper app database
#
# * **FOOD_CATEGORY, FOOD_CATEGORY_ES, FOOD_CATEGORY_PT.** The 25 main and sub categories 
#   of food found on the app's start screen. Not all categories have sub-categories, but if 
#   one has them, then products can not be in the main category.
# * **PRODUCTS, PRODUCTS_ES, PRODUCTS_PT.** The main table with all storage durations 
#   and instructions for 396 products. Products are rather types of products, defined by 
#   column "Name" for the general type and "Name_subtitle" for an optional specification, 
#   esp. used where "Name" is identical for several products. There are three columns per 
#   storage estimation, with suffixes _Min, _Max and _Metric. The last one contains the 
#   unit (weeks, days etc.) as text. There is one table per language, where all tips and other 
#   texts are translated and all numbers appear redundantly. Translation is complete. 
# * **COOKING_METHODS, COOKING_METHODS_ES, COOKING_METHODS_PT.** Cooking instructions for 
#   89 products. Could be part of PRODUCTS since it's a 1:1 relation. One table per language, 
#   but only the "Cooking_Method" column is really a free-text field that needs translation.
# * **COOKING_TIPS, COOKING_TIPS_ES, COOKING_TIPS_PT.** 93 cooking tips including a free-text 
#   column, a safe minimum temperature (in Fahrenheit), and a rest time. Some tips are 
#   identical because this table is not normalized.
# * **FAVORITE_PRODUCTS.** The user's heart-marked products in the app. Not relevant.
# * **SEARCH_HISTORY.** The user's search history in the app. Not relevant.
# * **RECALLS.** Product recalls. Not relevant here.
# 
# ## Other observations about the FoodKeeper app
# 
# * The app is 94 MiB in size and basically all of that is consumed by high-dpi stock images 
#   in PNG format (!), used in the app in the background.
# * The database is only 280 kiB, and even that contains redundancy due to the way how 
#   translations, cooking methods and cooking tips are saved. And because each column has a 
#   SQLite3 ROWID column. 120 kiB would be achievable easily.
# 
# ## Remaining work for future extensions
# 
# TODO (later): Refactor code in this script into a class FoodKeeperDatabase, stored in the 
# same file in this script (because it is not re-usable).
# 
# TODO (later): Normalize the column names in the FoodKeeper database: suffix `_tips` should become 
# `_Tips` everywhere in table `PRODUCTS`.
# 
# TODO (later): Also include downloading the FoodKeeper .apk file from Google Play, using 
# a command line interface to Raccoon or similar.
#
# TODO (later): Also include extracting the FoodKeeper database from the .apk file. 
# Probably, a simple unzip command (of only the SQLite database) will be sufficient, with no 
# need for apktool.
#
# TODO (later): As an alternative to the above, include a SQL command dump of the 
# FoodKeeper database into the Git repository, and enable this script to read it as an 
# alternative to being provided a binary SQLite database file. The SQL dump format is 
# better manageable for Git.


# Create and populate a database table with a mapping between FoodKeeper products and 
# Open Food Facts categories.
# 
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
def create_categories_mapping(db)
    # Let the OS sync write operations to the database file when it wants rather than after each command.
    # Because "commits can be orders of magnitude faster with synchronous OFF" as per 
    # https://sqlite.org/pragma.html#pragma_synchronous and we don't care that the database might become 
    # corrupted on power outage. Because it can be simply generated anew by running the import scripts again.
    db.execute "PRAGMA synchronous = OFF"

    db.execute("
        CREATE TABLE OFF_CATEGORY (
            Product_ID    INTEGER,
            Name          TEXT,
            PRIMARY KEY   (Product_ID, Name)
        );
    ")

    # Insert some dummy data for now.
    # TODO: Provide the real data.
    db.execute('SELECT ID FROM PRODUCTS') do |row|
        db.execute('INSERT INTO OFF_CATEGORY VALUES (?, ?)', [ row['ID'], 'Bee products' ])
        db.execute('INSERT INTO OFF_CATEGORY VALUES (?, ?)', [ row['ID'], 'Beverages' ])
    end

    # Restore synchronous operation, which was disabled at the start of the method.
    db.execute "PRAGMA synchronous = ON"
end


# Determine the Open Food Facts categories for this FoodKeeper product.
# 
# The mapping conveniently relies on a table `OFF_CATEGORY` that has to be added to the FoodKeeper 
# database and populated before calling. See #off_categories_data().
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product for which 
#   to determine the OFF categories.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [Array<String>]  The OFF categories, using their full English names. Only when no English 
#   name is available, a name in a different language would be used, with a two-letter language 
#   prefix such as "fr:French Category Name Here".
def off_categories(product_id, db)
    db
        .execute('SELECT Name FROM OFF_CATEGORY WHERE Product_ID = ?', [ product_id ])
        .collect { |row| row['Name'] }
end


# Create a basic topic and fill in the values common for all FoodKeeper topics.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [FoodRescueTopic]  The basic topic that has been created.
def basic_topic(product_id, db)
    topic = FoodRescueTopic.new

    topic.author= { include_from: 'author_foodkeeper.xml' }

    # As of 2020-05-02, the topic's version date is the "Updated" date of the FoodKeeper app on Google Play.
    # The website notes however " Date Last Reviewed: April 26, 2019", so might contain more recent 
    # updates. See https://www.foodsafety.gov/keep-food-safe/foodkeeper-app
    topic.edition= Date.parse('2017-11-14')

    # Fill the topic's Open Food Facts categories.
    topic.off_categories= off_categories(product_id, db)

    # No abstract by default because FoodKeeper topics are very short already.
    # Of course the value can be overwritten as needed after this function returned.
    topic.abstract= '' 

    topic.literature_used= [ 'USDA-1' ]

    topic.bibliography= { include_from: 'bibliography.xml' }

    return topic
end

# Render the specified product's shelf life into a string like "6-9 Months".
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param field_prefix [String]  The prefix of the FoodKeeper database columns (in table PRODUCTS) to 
#   use when rendering the shelf life string. For example, `Pantry`.
# @return [String]  The shelf life string.
def shelf_life(product_id, db, field_prefix)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    fields = product.select { |k,v| k.match(/^#{field_prefix}_(Min|Max|Metric)$/) }

    min_duration = product["#{field_prefix}_Min"]
    max_duration = product["#{field_prefix}_Max"]
    duration_metric = product["#{field_prefix}_Metric"]

    text_after = 
        case field_prefix
        when 'Pantry';                      'in the pantry, whether package is sealed or not'
        when 'DOP_Pantry';                  'in the pantry, if the package is still sealed'
        when 'Pantry_After_Opening';        'in the pantry, after opening the package'
        when 'Refrigerate';                 'in the fridge, whether package is sealed or not'
        when 'DOP_Refrigerate';             'in the fridge, if the package is still sealed'
        when 'Refrigerate_After_Opening';   'in the fridge, after opening the package'
        when 'Refrigerate_After_Thawing';   'in the fridge, after thawing the item'
        when 'Freeze';                      'in the freezer, whether package is sealed or not'
        when 'DOP_Freeze';                  'in the freezer, if the package is still sealed'
        end

    if min_duration == max_duration
        "#{min_duration} #{duration_metric} #{text_after}"
    else
        "#{min_duration}–#{max_duration} #{duration_metric} #{text_after}"
    end
end


# Render the specified product's storage tips into a string.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param field_prefix [String]  The column prefix specifying the type of shelflife in the FoodKeeper 
#   database, table `PRODUCTS`. For example, `Pantry`.
# @return [String]  The storage tips string, which can be the empty string.
def storage_tips(product_id, db, field_prefix)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    # The suffix should be "_Tips" everywhere, but there are mistakes in the DB column names. So:
    field_name = field_prefix + (if field_prefix.include?('Freeze') then '_Tips' else '_tips' end)

    return '' if product[field_name].nil?
    return '. ' + product[field_name] + '.'
end


# Generate a list of storage instructions in XML for the specified product.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param storage_type [Symbol]  The storage type to generate instructions for. Any of `pantry`, `refrigerate`, `freeze`.
#   If omitted, instructions for all storage types are included.
# @param include_tips [Boolean]  Whether to also include more detailed storage tips, or just show 
#   storage durations.
# @return [Ox::Element]
def storage_instructions(product_id, db, storage_type: nil, include_tips: true)
    # Field / column prefixes by storage type. 
    field_prefixes = {
        pantry:      [ 'Pantry',      'DOP_Pantry',      'Pantry_After_Opening'                                   ],
        refrigerate: [ 'Refrigerate', 'DOP_Refrigerate', 'Refrigerate_After_Opening', 'Refrigerate_After_Thawing' ],
        freeze:      [ 'Freeze',      'DOP_Freeze'                                                                ]
    }
    field_prefixes[nil] = field_prefixes.values.flatten # All if storage type not given.

    selected_prefixes = field_prefixes[storage_type]

    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])
    is_empty = lambda { |k,v| v.empty? }
    instructions = Ox::Element.new('itemizedlist')

    selected_prefixes.each do |prefix|
        next if product["#{prefix}_Min"].empty?

        instruction = shelf_life(product_id, db, prefix) + 
            (storage_tips(product_id, db, prefix) if include_tips)
        instructions << (Ox::Element.new('listitem') << (Ox::Element.new('para') << instruction))
    end

    return instructions
end

# Create a topic from given FoodKeeper product data for the "Storage Overview" section.
# in the "Storage Overview" section.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [FoodRescueTopic]  The created topic.
def storage_overview_topic(product_id, db)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    topic = basic_topic(product_id, db)
    topic.title= 'Storage Durations'
    topic.section= 'storage_overview'

    intro = Ox::Element.new('para') << 'The typical storage life of this item is:'
    list = storage_instructions(product_id, db)
    outro = Ox::Element.new('para') # No text, as this part is unused so far.
    topic.main= [intro, list, outro]

    return topic
end


# Create a topic from given FoodKeeper product about pantry storage.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [FoodRescueTopic]  The created topic.
def pantry_storage_topic(product_id, db)
    topic = basic_topic(product_id, db)

    topic.title= 'Pantry storage'
    topic.section= 'storage_instructions'

    intro = Ox::Element.new('para') << 'The typical storage life of this item in the pantry is:'
    list = storage_instructions(product_id, db, storage_type: :pantry, include_tips: true)
    outro = Ox::Element.new('para') << 'Storage life affects quality. The item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, outro]

    return topic
end


# Create a topic from given FoodKeeper product about refrigerated storage.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [FoodRescueTopic]  The created topic.
def fridge_storage_topic(product_id, db)
    topic = basic_topic(product_id, db)

    topic.title= 'Fridge storage'
    topic.section= 'storage_instructions'

    intro = Ox::Element.new('para') << 'The typical storage life of this item in the fridge is:'
    list = storage_instructions(product_id, db, storage_type: :refrigerate, include_tips: true)
    outro = Ox::Element.new('para') << 'Storage life affects quality. The item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, outro]

    return topic
end


# Create a topic from given FoodKeeper product about freezer storage.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @return [FoodRescueTopic]  The created topic.
def freezer_storage_topic(product_id, db)
    topic = basic_topic(product_id, db)

    topic.title= 'Freezer storage'
    topic.section= 'storage_instructions'

    intro = Ox::Element.new('para') << 'The typical storage life of this item in the freezer is:'
    list = storage_instructions(product_id, db, storage_type: :freeze, include_tips: true)
    outro = Ox::Element.new('para') << 'Storage life affects quality. The item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, outro]

    return topic
end


# Import a single FoodKeeper product by converting its data into corresponding DocBook XML files.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param file_prefix [String]  The prefix to use for the DocBook XML output files. The system will choose 
#   the next available filename by combining the prefix, the next available sequence number and the 
#   `.xml` filename extension. The prefix may start with a path. Everything after the last "/" (or the 
#   whole if there is none) is considered the filename prefix.
def import_product(product_id, db, file_prefix)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    topics = []
    topics << storage_overview_topic(product_id, db)
    topics << pantry_storage_topic(product_id, db) \
        unless product['Pantry_tips'].empty? and product['DOP_Pantry_tips'].empty?
    topics << fridge_storage_topic(product_id, db) \
        unless product['Refrigerate_tips'].empty? and product['DOP_Refrigerate_tips'].empty?
    topics << freezer_storage_topic(product_id, db) \
        unless product['Freeze_Tips'].empty? and product['DOP_Freeze_Tips'].empty?

    # TODO (later): Create and write a topic for the "Preparation Instructions" section.
    # (Using the content from the COOKING_METHODS and COOKING_TIPS tables.)

    # Write all topics to disk as DocBook XML files.
    topics.each { |t| t.to_docbook(file_prefix: file_prefix, file_padding: 3) }
end


#############################################################################
# MAIN PROGRAM

# Argument parsing.
begin
    args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
    $stderr.puts e.message
    exit -1
end

# Refuse to run if any files with PREFIX already exist.
# (It indicates output / leftovers from a previous run, and we don't want to make a mess.)
unless Dir.glob("#{args['PREFIX']}*").empty?
    $stderr.puts "Output files with the given prefix #{args['PREFIX']} already exist. Exiting."
    exit -1
end

# Convert FoodKeeper products to DocBook XML.
begin
    db = SQLite3::Database.new args['DBFILE'], { results_as_hash: true }
    create_categories_mapping(db)
  
    # Load each FoodKeeper product (in English) and convert it to DocBook XML files.
    db.execute('SELECT ID FROM PRODUCTS') do |product|
        import_product(product['ID'], db, args['PREFIX'])
    end

    # TODO (later): Also load the FoodKeeper products in Spanish and Portuguese and convert them to 
    # translated DocBook XML files.
rescue ArgumentError => e
    $stderr.puts e.message
    $stderr.puts e.backtrace
    exit -1
ensure
    db.close if db
end
