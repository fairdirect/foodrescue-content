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
to files named PREFIXnnn.xml, where nnnn is a 3-digit, zero-padded number. If files 
with PREFIX exist, this script will refuse to run. DBFILE will not be modified.

Full process to convert FoodKeeper data:

1. Obtain the .apk file of FoodKeeper on your desktop computer. The FoodKeeper app 
   is linked from the FoodKeeper website (https://www.foodsafety.gov/keep-food-safe/foodkeeper-app).
   A good, cross-platform option is using Raccoon (https://raccoon.onyxbits.de/).
2. Unzip the APK package: 
   unzip decode gov.usda.fsis.foodkeeper2-46.apk
4. Get the database out of the decoded files:
   cp gov.usda.fsis.foodkeeper2-46/assets/databases/foodkeeper.db FoodKeeper.sqlite3
5. Run this script to convert the database to DocBook XML topics.

Examples: For the foodrescue-content repo, the command to run is:

    scripts/frc-import-foodkeeper.rb \
        content-topics/FoodKeeper.sqlite3 \
        content-topics/topics-foodkeeper-en/topic-foodkeeper-

convention for PREFIX is to include the author, here: "topic-foodkeeper-".

Usage:
    #{__FILE__} DBFILE PREFIX
    #{__FILE__} -h | --help
    #{__FILE__} -v | --version

Options:
    -h, --help                     Show this screen.
    -v, --version                  Show version.

DOCOPT

# ## Table structure of the FoodKeeper App database
#
# * **FOOD_CATEGORY, FOOD_CATEGORY_ES, FOOD_CATEGORY_PT.** The 25 main and sub categories 
#   of food found on the app's start screen. Not all categories have sub-categories, but if 
#   one has them, then products can not be in the main category.
# * **PRODUCTS, PRODUCTS_ES, PRODUCTS_PT.** The main table with all storage durations 
#   and instructions for 396 products. Products are rather types of products. There is one 
#   table per language, where all tips and other texts are translated and all numbers appear 
#   redundantly. Translation is complete.
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
#
# ## Column structure of the PRODUCTS table in the FoodKeeper App database
# 
# * **Name.** Defines the general type of product.
# * **Name_subtitle.** An optional, more detailed definition of the type of product, used esp. 
#   where "Name" is identical for several products.
# * **\*_Min, \*_Max, \*_Metric.** The storage duration range for a specific storage type. 
#   The `_Metric` column contains the unit ("Days", "Weeks" etc.).
# * **Pantry_(Min|Max|Metric).** The "general" pantry storage, independent of whether the package is already 
#   opened or not. Only 6 products have this. A value here is mutually exclusive with a value 
#   in any of the other two pantry storage types.
# * **DOP_Pantry_(Min|Max|Metric).** Storage in the pantry from the date of purchase. Without opening 
#   the package, as otherwise also having the "pantry after opening" storage type would make no sense. 
#   Products can have values heere and in the "pantry after opening" columns at the same time.
# * **Pantry_After_Opening_(Min|Max|Metric).** Values can appear here in addition to `DOP_Pantry_(Min|Max|Metric)`.
# 
# For the refrigeration and freezing related columns, the same relationship between columns applies as 
# for the pantry storage related columns.
# 
# * **Pantry_tips, Refrigerate_tips, Freeze_Tips.** These are the only relevant columns with tips. 
#   The columns `DOP_*_tips` are all empty, and other tips columns do not even exist. Logically, some 
#   tips here refer storage types stored in other columns than `Pantry_*`, `Refrigerate_*` or 
#   `Freeze_*`, for example the tip "After opening time applies to prepared product.". So these tips 
#   should be rendered once for the whole list of pantry, refrigerator or freezer storage instructions, 
#   as they seem to apply to the whole list.
# * **DOP_Pantry_tips, DOP_Refrigerate_tips, DOP_Freeze_Tips.** These columns are completely empty, see:
#   `SELECT ID, DOP_Pantry_tips FROM PRODUCTS WHERE DOP_Pantry_tips != '';`
# 
# All columns are of data type "TEXT".
# 
#
# ## Other observations about the FoodKeeper App
# 
# * The app is 94 MiB in size and basically all of that is consumed by high-dpi stock images 
#   in PNG format (!), used in the app in the background.
# * The database is only 280 kiB, and even that contains redundancy due to the way how 
#   translations, cooking methods and cooking tips are saved. And because each column has a 
#   SQLite3 ROWID column. 120 kiB would be achievable easily.
# 
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

    topic.literature_used= [ {id: 'USDA-1', ref_details: "PRODUCTS.ID=#{product_id}"} ]

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
# @return [String]  The shelf life string. It may contain XML, so must be added as raw content to 
#   an XML file. It may be the empty string if no information is present.
def shelf_life(product_id, db, field_prefix)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    fields = product.select { |k,v| k.match(/^#{field_prefix}_(Min|Max|Metric)$/) }

    min_duration = product["#{field_prefix}_Min"]
    max_duration = product["#{field_prefix}_Max"]
    duration_metric = product["#{field_prefix}_Metric"]

    text_after = case field_prefix
        when 'Pantry';                      'in the pantry, whether sealed or not'
        when 'DOP_Pantry';                  'in the pantry, if still sealed'
        when 'Pantry_After_Opening';        'in the pantry, after opening the package'
        when 'Refrigerate';                 'in the fridge, whether sealed or not'
        when 'DOP_Refrigerate';             'in the fridge, if stored there immediately after purchase, whether sealed or not'
        when 'Refrigerate_After_Opening';   'in the fridge, if stored there after opening the package'
        when 'Refrigerate_After_Thawing';   'in the fridge, if stored there after thawing a frozen item, whether sealed or not'
        when 'Freeze';                      'in the freezer, whether sealed or not'
        when 'DOP_Freeze';                  'in the freezer, if stored there immediately after purchase, whether sealed or not'
    end

    if min_duration.empty?
        ""
    elsif min_duration == max_duration
        "<emphasis>#{min_duration} #{duration_metric}</emphasis> #{text_after}"
    else
        # An en dash, like here, is the correct typography for a range. See:
        # https://en.wikipedia.org/wiki/Dash#Ranges_of_values
        "<emphasis>#{min_duration}–#{max_duration} #{duration_metric}</emphasis> #{text_after}"
    end
end


# Render the specified product's storage tips into a string.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param storage_type [Symbol]  The storage type to generate instructions for. Any of `:pantry`, 
#   `:refrigerate`, `:freeze`. If omitted, instructions for all storage types are included.
# @return [String]  The storage tips string, which can be the empty string.
def storage_tips(product_id, db, storage_type: nil)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    # Note that tips fields are either named `*_Tips` or `*_tips`. It should be `*_Tips` everywhere, 
    # as SQLite3 column names are case-independent, this sloppyness is tolerated in the database. 
    # But not for the hash keys here.
    case storage_type
    when :pantry
        product['Pantry_tips']
    when :refrigerate
        product['Refrigerate_tips']
    when :freeze
        product['Freeze_Tips']
    when nil
        "#{product['Pantry_tips']} #{product['Refrigerate_tips']} #{product['Freeze_Tips']}"
    end
end


# Generate a list of storage instructions in XML for the specified product.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
# @param storage_type [Symbol]  The storage type to generate instructions for. Any of `:pantry`, `:refrigerate`, `:freeze`.
#   If omitted, instructions for all storage types are included.
# @param include_tips [Boolean]  Whether to also include more detailed storage tips, or just show 
#   storage durations.
# @return [Ox::Element]
def storage_durations(product_id, db, storage_type: nil, include_tips: true)
    # Field / column prefixes by storage type. 
    field_prefixes = {
        pantry:      [ 'Pantry',      'DOP_Pantry',      'Pantry_After_Opening'                                   ],
        refrigerate: [ 'Refrigerate', 'DOP_Refrigerate', 'Refrigerate_After_Opening', 'Refrigerate_After_Thawing' ],
        freeze:      [ 'Freeze',      'DOP_Freeze'                                                                ]
    }
    field_prefixes[nil] = field_prefixes.values.flatten # All if storage type not given.

    instructions = Ox::Element.new('itemizedlist')
    selected_prefixes = field_prefixes[storage_type]

    selected_prefixes.each do |prefix|
        instruction = shelf_life(product_id, db, prefix) 
        instructions << (
            Ox::Element.new('listitem') << (Ox::Element.new('para') << Ox::Raw.new(instruction))
        ) unless instruction.empty?
    end

    return instructions
end


# Generate an introductory sentence for the list of estimated storage durations.
# 
# @param product_id [Integer]  The FoodKeeper database's PRODUCTS.ID value of the product about which 
#   the topic will be about.
# @param db [SQLite3::Database]  The database connection to the FoodKeeper database.
def storage_intro_text(product_id, db)
    product = db.get_first_row('SELECT * FROM PRODUCTS WHERE ID = ?', [ product_id ])

    name = if product['Name_subtitle'].empty? 
        then product['Name'] 
        else "#{product['Name']}, #{product['Name_subtitle']}" 
    end

    return "The typical storage life of '#{name}' is:"
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

    intro = Ox::Element.new('para') << storage_intro_text(product_id, db)
    list = storage_durations(product_id, db, include_tips: false)

    topic.main= [intro, list]

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

    intro = Ox::Element.new('para') << storage_intro_text(product_id, db)
    list = storage_durations(product_id, db, storage_type: :pantry)
    tips = Ox::Element.new('para') << storage_tips(product_id, db, storage_type: :pantry)
    outro = Ox::Element.new('para') << 'Storage life affects quality. This item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, tips, outro]

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

    intro = Ox::Element.new('para') << storage_intro_text(product_id, db)
    list = storage_durations(product_id, db, storage_type: :refrigerate)
    tips = Ox::Element.new('para') << storage_tips(product_id, db, storage_type: :refrigerate)
    outro = Ox::Element.new('para') << 'Storage life affects quality. This item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, tips, outro]

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

    intro = Ox::Element.new('para') << storage_intro_text(product_id, db)
    list = storage_durations(product_id, db, storage_type: :freeze)
    tips = Ox::Element.new('para') << storage_tips(product_id, db, storage_type: :freeze)
    outro = Ox::Element.new('para') << 'Storage life affects quality. This item may or may not be safe to eat afterwards. Details may be provided below.'
    topic.main= [intro, list, tips, outro]

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
    # Create an in-memory database to avoid changing the on-disk database. This connection must be 
    # kept open, because when the last connection to an in-memory database closes, its data is gone. 
    # It uses shared cache mode to allow other database connections to see the same data.
    # See: https://www.sqlite.org/inmemorydb.html
    mem_db = SQLite3::Database.new 'file::memory:?cache=shared', { results_as_hash: true }

    # Fill the in-memory database from the on-disk database. See:
    # https://www.sqlite.org/lang_vacuum.html#vacuuminto
    # https://stackoverflow.com/a/58932207
    file_db = SQLite3::Database.new args['DBFILE'], { results_as_hash: true }
    file_db.execute("VACUUM INTO 'file::memory:?cache=shared'")
    file_db.close

    create_categories_mapping(mem_db)
  
    # Load each FoodKeeper product (in English) and convert it to DocBook XML files.
    mem_db.execute('SELECT ID FROM PRODUCTS') do |product|
        import_product(product['ID'], mem_db, args['PREFIX'])
    end

    # TODO (later): Also load the FoodKeeper products in Spanish and Portuguese and convert them to 
    # translated DocBook XML files.
rescue ArgumentError => e
    $stderr.puts e.message
    $stderr.puts e.backtrace
    exit -1
ensure
    file_db.close if file_db
    mem_db.close if mem_db
end
