# Suppress depreciation warnings from the awesome_print gem.
# TODO: Fix the gem, then remove this.
$VERBOSE = nil

# Gem includes. See Gemfile.
require 'sqlite3'
require 'awesome_print'

# Local, non-gem includes.
require_relative 'utils'


# Interface to the SQLite data storage for food rescue content.
# 
# ## Table design
# 
# Table structure follows standard SQLite practice by default (integer primary keys as alias for ROWID), with 
# exceptions only for data that (1) will be included in distributed versions of the database and (2) wher significant 
# amounts of storage space can be saved (roughly meaning >200 kiB unpacked per intervention). So far that means:
# 
# **Table categories.** Nothing to optimize. Column id is an alias for ROWID, using 64 bit per value. But at <5000 
# records in this table for distributed SQLite files, the wasted storage is only 5000 * (8-2 Byte) = 30 kB.
# 
# **Tables categories_structure, product_categories, product_countries.** Using WITHOUT ROWID, as the table includes 
# two columns that are useful together as a primary key, so no additional ROWID column is needed. It would be 
# additional, since only one-column INTEGER PRIMARY KEY columns become an alias of ROWID 
# (https://www.sqlite.org/lang_createtable.html#rowid). The two columns of the primary key refer to ROWID columns in 
# another table, but because they are not ROWID columns themselves, storage on disk only needs as much space as the 
# integer values, not 8 byte constantly (see https://www.sqlite.org/datatype3.html#storage_classes_and_datatypes).
#
# **Table products.** The GTIN code is saved into an integer column. Compared to a 14 Byte string column, that 
# saves 7 Bytes, given that most numbers are 14 decimal digits long, utilizing 6 or 8 Bytes in storage in the 
# INTEGER SQLite storage class, see https://www.sqlite.org/datatype3.html#storage_classes_and_datatypes. We do 
# not use the code column directly as primary key because the GTIN numbers stored in it are relatively large 
# (7 Byte average). No space can be saved for this column, but for columns referencing it in foreign keys: here, 
# option WITHOUT ROWID and a primary key using the row number needs at most 3 Bytes per value. At 400,000 records like for  
# the French products, that saves 400,000 * (7 B - 3 B) = 1.6 MB. With only one foreign key referencing the products 
# table in the distributable version (namely from products_categories), the saving is smaller as the additional 
# foreign key column also utilizes 3 Bytes: 400,000 * (7 B - 3 B - 3 Byte) = 0.4 MB. That's still useful, and less 
# than the other alternative for this case of not having a products table at all (since it has no other attributes 
# right now). Having a products table is also more flexible for future expansion.
# 
# **Table countries.** Nothing to optimize, as this table contains few values an is not included into distributable 
# versions anyway.
# 
# ## Hints on SQLite quirks
# 
# * There is no need to write "INTEGER PRIMARY KEY NOT NULL", as that is equivalent to "INTEGER PRIMARY KEY" because 
#   when attempting to insert NULL, the system will choose a non-NULL value automatically (see 
#   https://www.sqlite.org/lang_createtable.html#rowid).
# * There is no need to write "INT PRIMARY KEY" instead of "INTEGER PRIMARY KEY" to avoid creating an alias for ROWID 
#   columns, as that quirk does not apply for our WITHOUT ROWID tables (see 
#   https://www.sqlite.org/withoutrowid.html#differences_from_ordinary_rowid_tables).
class FoodRescueDatabase < SQLite3::Database

    def initialize(dbfile)
        super(dbfile)

        execute "PRAGMA foreign_keys = ON;"

        # Let the OS sync write operations to the database file when it wants rather than after each command.
        # Because "commits can be orders of magnitude faster with synchronous OFF" as per 
        # https://sqlite.org/pragma.html#pragma_synchronous and we don't care that the database might become 
        # corrupted on power outage. Because it can be simply generated anew by running the import scripts again.
        execute "PRAGMA synchronous = OFF;"

        # TODO (later): Run all prepare_*_tables methods here. This guarantees that any FoodRescueDatabase 
        # object can take any kind of record without further checks and preparations.
    end

    # Helper method to determine the main name of a category
    # 
    # @param [Hash] block  A description of the category with the same structure as used in method write_cat_names.
    # @return [String, String]  Name and language code of the category's main name.
    # @see #write_cat_names
    def self.cat_main_name(block)
        # ap 'DEBUG: #cat_main_name: block = '
        # ap block

        # Find the "main" name of the category: English one if existing, otherwise first one.
        full_name = block[:names].select { |name| name[:lang] == 'en'}.first
        full_name = block[:names][0] if full_name.nil?
        
        return [ full_name[:cat_names][0][:value], full_name[:lang] ]
    end


    # Create the SQLite tables for categories their hierarchy.
    #
    # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the 
    #   same structure already exist.
    # @see FoodRescueDatabase  Gives the reasoning for the table structure.
    def prepare_category_tables(allow_reuse=false)
        if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

        execute_batch "
            CREATE TABLE #{if_not_exists} categories (
                id            INTEGER PRIMARY KEY, --alias of ROWID as per https://stackoverflow.com/a/8246737
                name          TEXT,                --the English name, otherwise the first available name
                lang          TEXT,                --language tag such as 'en', 'en-GB'
                local_names   JSON,                --array of name objects, each with 'name' and 'lang' properties
                product_count INTEGER              --number of products in this category
            );

            CREATE TABLE #{if_not_exists} categories_structure (
                category_id   INTEGER,
                parent_id     INTEGER,
                PRIMARY KEY (category_id, parent_id),
                FOREIGN KEY (category_id) REFERENCES categories(id),
                FOREIGN KEY (parent_id) REFERENCES categories(id)
            ) WITHOUT ROWID;
        "

        # TODO (later): Raise an exception if allow_reuse==false and a table exists.
        # TODO (later): Raise an exception if allow_reuse==true but the existing tables have a different structure.
    end


    # Create the SQLite tables for topics (units of knowledge about food rescue).
    #
    # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the 
    #   same structure already exist.
    def prepare_topic_tables(allow_reuse: false)
        if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

        execute_batch "
            CREATE TABLE #{if_not_exists} topics (
                id            INTEGER PRIMARY KEY, --alias of ROWID as per https://stackoverflow.com/a/8246737
                title         TEXT,                
                lang          TEXT,                --language tag such as 'en', 'en-GB'
                section       TEXT,                --string ID of the section to show the topic in
                author_id     INTEGER,             
                version       TEXT,                --version date in yyyy-mm-dd format
                text          TEXT,                --topic main content
                FOREIGN KEY (author_id) REFERENCES authors(id)
            );

            CREATE TABLE #{if_not_exists} topic_categories (
                topic_id      INTEGER,
                category_id   INTEGER,
                PRIMARY KEY (topic_id, category_id),
                FOREIGN KEY (topic_id) REFERENCES topics(id),
                FOREIGN KEY (category_id) REFERENCES categories(id)
            ) WITHOUT ROWID;
        "

        # TODO (later): Raise an exception if allow_reuse==false and a table exists.
        # TODO (later): Raise an exception if allow_reuse==true but the existing tables have a different structure.
    end


    # Create or re-create the SQLite tables for products. Requires category tables to exist.
    # 
    # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the 
    # same structure already exist.
    # @see FoodRescueDatabase  Gives the reasoning for the table structure.
    def prepare_product_tables(allow_reuse=false)
        if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

        # TODO: Add a unique constraint to products.code, and raise an exception if it is violated upon insert.

        execute_batch "
            CREATE TABLE #{if_not_exists} products (
                id             INTEGER PRIMARY KEY,
                code           INTEGER
            ) WITHOUT ROWID;

            CREATE TABLE #{if_not_exists} product_categories (
                product_id     INTEGER,
                category_id    INTEGER,
                PRIMARY KEY (product_id, category_id),
                FOREIGN KEY (product_id) REFERENCES products(id),
                FOREIGN KEY (category_id) REFERENCES categories(id)
            ) WITHOUT ROWID;

            CREATE TABLE #{if_not_exists} countries (
                id             INTEGER PRIMARY KEY,  --alias of ROWID as per https://stackoverflow.com/a/8246737
                name           TEXT                  --English-language country name
            );

            CREATE TABLE #{if_not_exists} product_countries (
                product_id     INTEGER,
                country_id     INTEGER,
                PRIMARY KEY (product_id, country_id),
                FOREIGN KEY (product_id) REFERENCES products(id),
                FOREIGN KEY (country_id) REFERENCES countries(id)
            ) WITHOUT ROWID;
        "

        # TODO (later): Raise an exception if allow_reuse==false and a table exists.
        # TODO (later): Raise an exception if allow_reuse==true but the existing tables have a different structure.
    end


    # Record the names of a category definition to the database.
    # 
    # @param [Hash] block  A nested Hash of the following structure. In this structure, there is always an array around the nested 
    # hashes, even when the array contains one or even zero elements. This is needed to be able to iterate over these arrays.
    # 
    #   {
    #     :parents => [
    #       {:lang=>"en", :cat_name => "…" },
    #       {:lang=>"fr", :cat_name => "…" },
    #       ...
    #     ]
    #     :names => [
    #       {
    #         :lang => "en", 
    #         :cat_names => [ {:value => "…" }, {:value => "…" }, ... ]
    #       },
    #       ...
    #     ],
    #     :properties => [
    #        ... not evaluate here ... 
    #     ]
    #   }
    def add_category(block)
        name, lang = self.class.cat_main_name(block)

        # TODO: Create a JSON structure for the remaining names and put it into column local_names.
        # TODO: Switch to the INSERT statement with column references.
        begin
            execute "INSERT INTO categories (name, lang) VALUES (?, ?)", [name, lang]
        rescue SQLite3::ConstraintException => e
            puts "WARNING:".in_orange + " Category '#{lang}:#{name}' already exists in the database. Ignoring."
        end
    end


    # Record the parent categories of a category into the database.
    # 
    # Will result in a warning when the referenced parent categories do not exist in the database.
    # 
    # @param [Hash] block  A description of the category with the same structure as used in method write_cat_names.
    # @see #write_cat_names
    def add_category_parents(block)
        cat_name, cat_lang = self.class.cat_main_name(block)
        cat_id = get_first_value "SELECT id FROM categories WHERE name = ? AND lang = ?", [ cat_name, cat_lang ]
        if cat_id.nil? then raise ArgumentError, "Category '#{cat_lang}:#{cat_name}' not found in database. Ignoring." end

        block[:parents].each do |parent| 
            parent_name, parent_lang = [ parent[:cat_name], parent[:lang] ]
            parent_id = get_first_value "SELECT id FROM categories WHERE name = ? AND lang = ?", [ parent_name, parent_lang ]
            if parent_id.nil? then raise ArgumentError, "Parent category '#{parent_lang}:#{parent_name}' not found in database. Ignoring." end
            
            begin
                execute "INSERT INTO categories_structure VALUES (?, ?)", [cat_id, parent_id]
            rescue SQLite3::ConstraintException => e
                puts "WARNING:".in_orange + " Parent category definition already exists in database. Ignoring.\n" +
                     "    <#{parent_lang}:#{parent_name}\n" +
                     "    #{cat_lang}:#{cat_name}"
            end
        end
    end


    # Save the number of products for which a category is used to the database.
    # 
    # @param [String] cat_name  Identifying name of the category to save the product count for. 
    # Use the English name, and if not available the first name given. Use the full name, not the 
    # tokenized form. Do not include a language prefix.
    #
    # @param [Integer]  Number of products in this category.
    def add_product_count(cat_name, product_count)
        # ap execute "SELECT * FROM categories WHERE name = ?", [name]
        
        execute "UPDATE categories SET product_count = ? WHERE name = ? LIMIT 1", [product_count, cat_name]

        puts "WARNING:".in_orange + " Could not add product count to category '#{cat_name}'. Ignoring." if changes == 0
    end


    # Save one product to the database.
    # 
    # @param product_code [Integer]  Unique product identification number, usually its GTIN code.
    # @param categories [Array<Hash>]  Full names of the categories assigned to the product. Each array 
    # element has the structure {lang: '…', name: '…'}, where "lang" is a language code of the form 
    # "ab" or "abc" or a language tag of the forms "ab_CD" or "abc_DE". If a category is not yet known, 
    # an entry will be created for it. This does not include any translations of hierarchy information 
    # about that category, obviously.
    # @param [Array]  English-language names of countries in which the product is on sale. If a country 
    # is not yet known, a record will be created for it.
    # 
    # @see https://en.wikipedia.org/wiki/Language_localisation#Language_tags_and_codes
    def add_product(product_code, categories, countries)

        # Since products is a WITHOUT ROWID table, we have to supply our own primary key value.
        # See: https://stackoverflow.com/a/61448442
        product_id = get_first_value "SELECT IFNULL(MAX(id),0) + 1 FROM products"

        execute "INSERT INTO products (id, code) VALUES (?, ?)", [product_id, product_code]

        # Associate the product with each category. If necessary, create a category record first.
        categories.each do |cat|
            category_id = get_first_value "SELECT id FROM categories WHERE name = ? and lang = ? LIMIT 1", [cat[:name], cat[:lang]]
            if category_id.nil? then
                execute "INSERT INTO categories (name, lang) VALUES (?, ?)", [cat[:name], cat[:lang]]
                category_id = get_first_value "SELECT last_insert_rowid()"
            end

            begin
                execute "INSERT INTO product_categories VALUES (?, ?)", [product_id, category_id]
            rescue SQLite3::ConstraintException => e
                puts "WARNING:".in_orange + " Category '#{cat[:name]}' assigned twice to product #{product_code}. Ignoring."
            end
        end

        # Associate the product with each country. If necessary, create a country record first.
        countries.each do |country|
            country_id = get_first_value "SELECT id FROM countries WHERE name = ?", [country]
            if country_id.nil? then
                execute "INSERT INTO countries (name) VALUES (?)", [country]
                country_id = get_first_value "SELECT last_insert_rowid()"
            end

            begin
                execute "INSERT INTO product_countries VALUES (?, ?)",  [product_id, country_id]
            rescue SQLite3::ConstraintException => e
                puts "WARNING:".in_orange + " Country '#{country}' assigned twice to product #{product_code}. Ignoring."
            end
        end

    end

    # Save one topic of food rescue content to the database.
    # 
    # The given topic can mention bibliographic references. If it does, these must already exist in 
    # the database. The topic can also mention an author name. If it exists in the database, it will 
    # be referenced, otherwise a new record will be created.
    # 
    # @param topic [FoodRescueTopic]  The topic to add.
    # @raise [ArgumentError]  If a referenced author or literature record does not exist in the database.
    def add_topic(topic)
        # TODO: Implementation.
    end

end
