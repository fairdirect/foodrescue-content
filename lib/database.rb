# Suppress depreciation warnings from the awesome_print gem.
# @todo Fix the gem, then remove this.
$VERBOSE = nil

# Gem includes. See Gemfile.
require 'sqlite3'
require 'awesome_print'

# Local, non-gem includes.
require_relative '../lib/food_rescue'
require_relative '../lib/utils'


# Interface to the SQLite data storage for food rescue content.
# 
# 
# ## Database design
# 
# Table structure follows standard SQLite3 practice by default (integer primary keys as alias for ROWID), with exceptions only 
# for data that (1) will be included in distributed versions of the database and (2) where significant amounts of storage space 
# can be saved (roughly meaning >200 kiB unpacked per intervention). So far that means:
# 
# **Table `categories`.** Nothing to optimize. Column id is an alias for ROWID, using 64 bit per value. But at <5000 records in 
# this table for distributed SQLite files, the wasted storage is only 5000 × (8 B - 2 B) = 30 kB.
# 
# **Tables `category_structure`, `product_categories`, `product_countries`, `topic_categories`.** No additional ROWID column
# is needed as the table includes two columns that are useful together as a primary key. So the table uses `WITHOUT ROWID`. A 
# ROWID column would take additional space, as only one-column `INTEGER PRIMARY KEY` columns become an alias of ROWID 
# ([see](https://www.sqlite.org/lang_createtable.html#rowid)). The two columns of the primary key refer to ROWID columns in 
# another table, but because they are not ROWID columns themselves, storage on disk only needs as much space as the integer 
# values, not 8 B constantly ([see](https://www.sqlite.org/datatype3.html#storage_classes_and_datatypes)).
#
# **Table `products`.** The GTIN code is saved into an integer column. Compared to a 14 B string column, that saves 7 B, given 
# that most numbers are 14 decimal digits long, utilizing 6 or 8 B in storage in the INTEGER SQLite storage class 
# ([see](https://www.sqlite.org/datatype3.html#storage_classes_and_datatypes)). We do not use the code column directly as 
# primary key because the GTIN numbers stored in it are relatively large (7 B average). No space can be saved for this column, 
# but for columns referencing it in foreign keys: here, option `WITHOUT ROWID` and a primary key using the row number needs at 
# most 3 B per value. At 400,000 records like for the French products, that saves 400,000 × (7 B - 3 B) = 1.6 MB. With only one 
# foreign key referencing the products table in the distributable version (namely from products_categories), the saving is 
# smaller as the additional foreign key column also utilizes 3 B: 400,000 × (7 B - 3 B - 3 B) = 0.4 MB. That's still useful, 
# and less than the other alternative for this case of not having a products table at all (since it has no other attributes 
# right now). Having a products table is also more flexible for future expansion.
# 
# **Table `countries`.** Nothing to optimize. This table contains few values and is not included into distributed databases.
# 
# **Table `topics`.** Nothing to optimize, as this table contains few records.
# 
# **Table `topics_literature`.** This table records to which works of literature a topic's text refers to. This is redundant to 
# the literature references in the topics' actual content, but in contrast to there it is here in a normalized form, making the 
# data easily accessible for client applications.
# 
# 
# ## Hints on SQLite quirks
# 
# * There is no need to write "INTEGER PRIMARY KEY NOT NULL", as that is equivalent to "INTEGER PRIMARY KEY" because when 
#   attempting to insert NULL, the system will choose a non-NULL value automatically 
#   ([see](https://www.sqlite.org/lang_createtable.html#rowid)).
# * There is no need to write "INT PRIMARY KEY" instead of "INTEGER PRIMARY KEY" to avoid creating an alias for ROWID columns, 
#   as that quirk does not apply for our WITHOUT ROWID tables 
#   ([see](https://www.sqlite.org/withoutrowid.html#differences_from_ordinary_rowid_tables)).
# 
# 
# @todo Document the remaining database tables and the optimizations used in them.
class FoodRescue::Database < SQLite3::Database

  # Create a connection to a SQLite3 database file with food rescue content.
  # 
  # @param dbfile [String]  Absolute or relative path to the SQLite3 database file.
  # @param options [Hash]  Options for the database connection as in {SQLite3::Database#initialize}. By default, option 
  #   `results_as_hash: true` is used unless overwritten.
  # @see SQLite3::Database#initialize
  def initialize(dbfile, options = {})
    options[:results_as_hash] = true unless options.key?( :results_as_hash )

    super(dbfile, options)

    # Enforce foreign key relations, including cascading deletes.
    execute "PRAGMA foreign_keys = ON"

    # Let the OS sync write operations to the database file when it wants rather than after each command. Because "commits 
    # can be orders of magnitude faster with synchronous OFF" as per https://sqlite.org/pragma.html#pragma_synchronous and 
    # we don't care that the database might become corrupted on power outage. Because it can be simply generated anew by 
    # running the import scripts again.
    execute "PRAGMA synchronous = OFF"

    # @todo (later) Run all prepare_*_tables methods here. This guarantees that any FoodRescue::Database object can take 
    #   any kind of record without further checks and preparations.
  end

  
  # Helper method to determine the main name of a category
  # 
  # @param [Hash] block  A description of the category with the same structure as used in method add_category.
  # @return [Array<String>]  Name and language code of the category's main name.
  # @see #add_category
  def self.cat_main_name( block )
    # Find the "main" name of the category: English one if existing, otherwise first one.
    full_name = block[:names].select{ |name| name[:lang] == 'en' }.first
    full_name = block[:names][0] if full_name.nil?
    
    return [ full_name[:cat_names][0][:value], full_name[:lang] ]
  end


  # Create the SQLite tables for categories their hierarchy.
  #
  # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the 
  #   same structure already exist.
  # @see FoodRescue::Database  FoodRescue::Database documentation (explains the database design)
  def prepare_category_tables(allow_reuse = true)
    if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

    # Multiple execute statements are preferable over execute_batch as backtraces then indicate the erroneous statement.

    execute "
      CREATE TABLE #{if_not_exists} categories (
        id              INTEGER PRIMARY KEY, -- alias of ROWID as per https://stackoverflow.com/a/8246737
        product_count   INTEGER              -- number of products in this category
      )"

    execute "
      CREATE TABLE #{if_not_exists} category_names (
        category_id     INTEGER,
        name            TEXT,
        lang            TEXT,                -- language tag such as 'en', 'en-GB'
        ----
        PRIMARY KEY     (name, lang),        -- Not including category_id to prevent inserting any duplicate names.
                                             -- Otherwise names would not necessarily identify categories.
        FOREIGN KEY     (category_id) REFERENCES categories(id) ON DELETE CASCADE
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} category_structure (
        category_id     INTEGER,
        parent_id       INTEGER,
        ----
        PRIMARY KEY     (category_id, parent_id),
        FOREIGN KEY     (category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY     (parent_id) REFERENCES categories(id)
      ) WITHOUT ROWID"

    # @todo (later) Raise an exception if allow_reuse==false and a table exists.
    # @todo (later) Raise an exception if allow_reuse==true but the existing tables have a different structure.
  end


  # Create the SQLite tables for topics (units of knowledge about food rescue).
  #
  # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the same structure already exist.
  def prepare_topic_tables(allow_reuse: false)
    if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

    # Multiple execute statements are preferable over execute_batch as backtraces then indicate the erroneous statement.

    execute "
      CREATE TABLE #{if_not_exists} authors (
        id              INTEGER PRIMARY KEY,    -- alias of ROWID as per https://stackoverflow.com/a/8246737
        givenname       TEXT,
        honorific       TEXT,
        middlenames     TEXT,
        surname         TEXT,
        orgname         TEXT,                   -- if filled in addition to a person name, it's the affiliation
        orgdiv          TEXT,
        uri             TEXT,
        email           TEXT
      )"

    execute "
      CREATE TABLE #{if_not_exists} literature (
        id              TEXT PRIMARY KEY,     -- Literature work ID. Same as its BibTeX key and AsciiDoc anchor / label.
        abbrev          TEXT,                 -- Display text for the list item identifier in the bibliography. 
                                              -- Same as its AsciiDoc xreftext and DocBook bibliograpy abbrev element.
                                              -- See: https://asciidoctor.org/docs/user-manual/#user-biblio
        entry           TEXT                  -- Bibliography entry of one literature work, pre-rendered to DocBook XML.
      ) WITHOUT ROWID"
    
    execute "
      CREATE TABLE #{if_not_exists} topics (
        id              INTEGER PRIMARY KEY,  -- alias of ROWID as per https://stackoverflow.com/a/8246737
        external_id     TEXT UNIQUE,          -- longer ID to trace the origin of the topic; for example 'native-123'
        section         TEXT,                 -- string ID of the section to show the topic in
        version         TEXT                  -- version date in yyyy-mm-dd format
      )"

    execute "
      CREATE TABLE #{if_not_exists} topic_authors (
        topic_id        INTEGER,
        author_id       TEXT,
        role            TEXT,                 -- author's role in producing the topic
        ----
        PRIMARY KEY     (topic_id, author_id),
        FOREIGN KEY     (topic_id) REFERENCES topics(id) ON DELETE CASCADE,
        FOREIGN KEY     (author_id) REFERENCES authors(id)
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} topic_contents (
        topic_id        INTEGER,
        lang            TEXT,                 -- language tag such as 'en'
        title           TEXT,
        abstract        TEXT,
        content         TEXT,                 -- topic main content
        ----
        PRIMARY KEY     (topic_id, lang)
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} topic_categories (
        topic_id        INTEGER,
        category_id     INTEGER,
        ----
        PRIMARY KEY     (topic_id, category_id),
        FOREIGN KEY     (topic_id) REFERENCES topics(id) ON DELETE CASCADE,
        FOREIGN KEY     (category_id) REFERENCES categories(id)
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} topic_literature (
        topic_id        INTEGER,
        literature_id   TEXT,
        ----
        PRIMARY KEY     (topic_id, literature_id),
        FOREIGN KEY     (topic_id) REFERENCES topics(id) ON DELETE CASCADE,
        FOREIGN KEY     (literature_id) REFERENCES literature(id)
      ) WITHOUT ROWID"

    # @todo (later) Import bibliography.bib completely. This requires columns for all BibTeX fields in table literature. 
    #   Currently, asciidoctor-bibtext creates the pre-rendered literature entries at the time of importing content to this 
    #   database. That works, but loses semantics, so that on export to DocBook etc., only the same style of references can 
    #   be used. When importing the complete BibTeX file to this table, asciidoctor-bibtex will still determine the inline 
    #   citation labels, but the bibliography entry styles can be determined on export using bibtex-ruby 
    #   (https://github.com/inukshuk/bibtex-ruby) or similar. Also, export of raw bibliograpy to DocBook is possible then. 
    #   But then again, this is important, just about keeping all semantic information in this database in a principled way.
    #   It might be better not to try to be a literature database and rather be content with BibTeX pre-rendering.
    # @todo (later) Raise an exception if allow_reuse==false and a table exists.
    # @todo (later) Raise an exception if allow_reuse==true but the existing tables have a different structure.
  end


  # Create or re-create the SQLite tables for products. Requires category tables to exist.
  # 
  # @param allow_reuse [Boolean]  If true, no error will occur in case tables of the same structure already exist.
  # @see FoodRescue::Database  Gives the reasoning for the table structure.
  def prepare_product_tables(allow_reuse=false)
    if_not_exists = if allow_reuse then "IF NOT EXISTS" else "" end

    # @todo Add a unique constraint to products.code, and raise an exception if it is violated upon insert.

    # Multiple execute statements are preferable over execute_batch as backtraces then indicate the erroneous statement.

    execute "
      CREATE TABLE #{if_not_exists} products (
        id              INTEGER PRIMARY KEY,
        code            INTEGER
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} product_categories (
        product_id      INTEGER,
        category_id     INTEGER,
        ----
        PRIMARY KEY     (product_id, category_id),
        FOREIGN KEY     (product_id) REFERENCES products(id),
        FOREIGN KEY     (category_id) REFERENCES categories(id)
      ) WITHOUT ROWID"

    execute "
      CREATE TABLE #{if_not_exists} countries (
        id              INTEGER PRIMARY KEY,  --alias of ROWID as per https://stackoverflow.com/a/8246737
        name            TEXT                  --English-language country name
      )"

    execute "
      CREATE TABLE #{if_not_exists} product_countries (
        product_id      INTEGER,
        country_id      INTEGER,
        ----
        PRIMARY KEY     (product_id, country_id),
        FOREIGN KEY     (product_id) REFERENCES products(id),
        FOREIGN KEY     (country_id) REFERENCES countries(id)
      ) WITHOUT ROWID"

    # @todo (later) Raise an exception if allow_reuse==false and a table exists.
    # @todo (later) Raise an exception if allow_reuse==true but the existing tables have a different structure.
  end


  # Record the names of a category definition to the database.
  # 
  # @param [Hash<Array<…>>] category_properties  A nested Hash of the following structure. In this structure, there is always an array around
  #   the nested hashes, even when that array contains zero or one elements. This allows to iterate over these arrays easily.
  # 
  #   ```
  #   {
  #     :names => [
  #       { :lang => "en",  :cat_names => [ {:value => "…" }, {:value => "…" }, ... ] },
  #       { :lang => "fr",  :cat_names => [ {:value => "…" }, {:value => "…" }, ... ] },
  #       ...
  #     ],
  #     :parents => [
  #       { :lang => "en",  :cat_name => "…" },
  #       { :lang => "fr",  :cat_name => "…" },
  #       ...
  #     ],
  #     :properties => [ ... not evaluated here ... ]
  #   }
  #   ```
  #
  # @todo Simplify the value of the `:cat_names` key to an array of strings before handing this stuff as a parameter to this method.
  def add_category(category_properties)

    # Get the id of a new category record, needed to associate the names with lateron.
    execute "INSERT INTO categories (product_count) VALUES (NULL)"
    category_id = get_first_value "SELECT last_insert_rowid()"

    category_properties[:names].each do |name|
      lang = name[:lang]

      name[:cat_names].each do |cat_name|
        synonym = cat_name[:value]

        # Fix that the categories.txt definition file is inconsistent about case.
        #
        # Mostly categories.txt contains categories in "Capital case" but sometimes in "all lowercase". All categories are shown
        # in capital case on the Open Food Facts website, so that is the intention and it shoul be that way in the database
        # to avoid errors when importing food rescue topics and their category associations. Note that the "COLLATE NOCASE"
        # option would allow case-insensitive comparion in SQLite3, but this has incomplete Unicode support so we better do it here.
        #
        # Also note, `"Hello World".capitalize => "Hello world". Yes, it lowercases the second and following words. Because city
        # and person names should not be accidentally lowercased this way, `#capitalize` is only applied here if the category names
        # start with a lowercase letter. (That still might lead to accidental lowercasing in a few cases, of course.)
        #
        # @todo Remove this hack once categories.txt has been fixed upstream.
        synonym.capitalize! if synonym.match?(/^[[:lower:]]/)

        begin
          execute "INSERT INTO category_names (category_id, name, lang) VALUES (?, ?, ?)", [category_id, synonym, lang]
        rescue SQLite3::ConstraintException => e
          puts "WARNING:".in_orange + " Category '#{lang}:#{name}' already exists in the database. Ignoring."
        end

      end

    end


#    begin
#      execute "INSERT INTO categories (name, lang) VALUES (?, ?)", [name, lang]
#    rescue SQLite3::ConstraintException => e
#      puts "WARNING:".in_orange + " Category '#{lang}:#{name}' already exists in the database. Ignoring."
#    end
  end


  # Record in the database which categories are parent categories of the given category.
  # 
  # Will result in a warning when a referenced parent category does not exist in the database. Such a parent category
  # reference is then ignored.
  # 
  # @param [Hash] block  A description of the category with the same structure as used in method `add_category()`.
  def add_category_parents(block)
    cat_name, cat_lang = self.class.cat_main_name(block)
    cat_id = get_first_value "SELECT category_id FROM category_names WHERE name = ? AND lang = ?", [ cat_name, cat_lang ]
    # puts "DEBUG: Going to assign category '#{cat_lang}:#{cat_name}' to #{block[:parents].count} parent categories"
    if cat_id.nil? then raise ArgumentError, "Category '#{cat_lang}:#{cat_name}' not found in database. Ignoring." end

    block[:parents].each do |parent|
      parent_name, parent_lang = [ parent[:cat_name], parent[:lang] ]
      parent_id = get_first_value "SELECT category_id FROM category_names WHERE name = ? AND lang = ?", [ parent_name, parent_lang ]

      if parent_id.nil? 
        then puts "WARNING: ".in_orange + "Parent category not found in database. Ignoring. Relevant source snippet:\n" +
        "    <#{parent_lang}:#{parent_name}\n" +
        "    #{cat_lang}:#{cat_name}"
      end
      
      begin
        execute "INSERT INTO category_structure VALUES (?, ?)", [cat_id, parent_id]
      rescue SQLite3::ConstraintException => e
        puts "WARNING: ".in_orange + "Parent category assignment already exists in database. Ignoring.\n" +
           "    <#{parent_lang}:#{parent_name}\n" +
           "    #{cat_lang}:#{cat_name}"
      end
    end
  end


  # Save the number of products for which a category is used to the database.
  # 
  # @param cat_name [String]  Identifying name of the category to save the product count for. Use the English name, and if 
  #   not available the first name given. Use the full name, not the tokenized form. Do not include a language prefix.
  # @param product_count [Integer]  Number of products in this category.
  #
  # @todo Also consider the language when identifying a category in the database.
  def add_product_count(cat_name, product_count)
    execute "UPDATE categories SET product_count = ? WHERE name = ? LIMIT 1", [product_count, cat_name]

    puts "WARNING:".in_orange + " Could not add product count to category '#{cat_name}'. Ignoring." if changes == 0
  end


  # Save one product to the database.
  # 
  # @param product_code [Integer]  Unique product identification number, usually its GTIN code.
  # @param categories [Array<Hash>]  The categories to which the product is assigned. If any of these categories does not 
  #   yet exist in the database, an entry will be created with its name (excluding name translations or hierarchy information,
  #   obviously). Each array element is a Hash describing one category, with keys as follows:
  # 
  #   * **`:lang`** (String) — A language code of the form `ab` or `abc` or a language tag of the forms `ab_CD` or `abc_DE`.
  #   * **`:name`** (String) — The full name of the category in the specified language.
  # 
  # @param countries [Array]  English-language names of countries in which the product is on sale. If a country is not yet 
  #   known in the database, a record will be created for it in table `countries`.
  # 
  # @see https://en.wikipedia.org/wiki/Language_localisation#Language_tags_and_codes Wikipedia: Language tags and codes
  # @todo Find out if language tags are indeed in the form `ab_CD` resp. `abc_DE`, and not `ab-CD` resp. `abc-DE`. Not very
  #   relevant right now, as the current database only contains two-letter language codes right now.
  def add_product(product_code, categories, countries)

    # Since products is a WITHOUT ROWID table, we have to supply our own primary key value.
    # See: https://stackoverflow.com/a/61448442
    product_id = get_first_value "SELECT IFNULL(MAX(id),0) + 1 FROM products"
    execute "INSERT INTO products (id, code) VALUES (?, ?)", [product_id, product_code]

    # Add database IDs to the records in "categories". If necessary, create category records on the fly.
    categories.each do |cat|
      category_id = get_first_value "SELECT category_id FROM category_names WHERE name = ? and lang = ? LIMIT 1",
        [cat[:name], cat[:lang]]

      if category_id.nil? then
        # TODO: Categories that do not yet exist in the database are those not in the OpenFoodFacts categories.txt taxonomy.
        # They are probably in the normalized form (all-lowercase, dashes for spaces), which should not be recorded into the
        # database. Either de-normalize it, or get the original form from another source.

        execute "INSERT INTO categories (product_count) VALUES (NULL)"
        category_id = get_first_value "SELECT last_insert_rowid()"
        execute "INSERT INTO category_names (category_id, name, lang) VALUES (?, ?, ?)", [category_id, cat[:name], cat[:lang]]
      end
      cat[:id] = category_id
    end

    # Collect ancestor information for all product categories.
    # The query determines all ancestors of the specified product categories. This is done efficiently in a single database
    # query using a SQLite Common Table Expression; see https://www.sqlite.org/lang_with.html .
    category_ids = categories.collect { |cat| cat[:id] }
    ancestor_ids = execute "
      WITH RECURSIVE ancestor_categories (child_id, ancestor_id) AS (
        SELECT category_id, parent_id
          FROM category_structure
          WHERE category_id IN (#{category_ids.join(',')})
        UNION ALL
        SELECT ancestor_categories.child_id, category_structure.parent_id
          FROM ancestor_categories
            INNER JOIN category_structure ON ancestor_categories.ancestor_id = category_structure.category_id
      )
      SELECT DISTINCT ancestor_id FROM ancestor_categories"
    ancestor_ids.collect! { |id| id['ancestor_id'] } # Remove the column names added by SQLite.

#    if ancestor_ids.count != 0
#      puts "DEBUG: processing product #{product_code}"
#      puts "DEBUG:   directly assigned categories: #{category_ids.count} total"
#      ap category_ids
#      puts "DEBUG:   ancestor categories: #{ancestor_ids.count} total"
#      ap ancestor_ids
#    end

    # Associate the product with each of its categories, either directly or via the hierarchy.
    categories.each do |cat|
      # puts "DEBUG: processing product category '#{cat[:name]}'" if ancestor_ids.count != 0
      # ap cat if ancestor_ids.count != 0

      # Ignore product categories that are ancestors of other product categories. In the Open Food Facts CSV products export,
      # products are assigned explicitly also to categories that are ancestors of other assigned categories. This is
      # not normalized, so we fix this before storing to the database. That step reduces the total database size by about
      # 40-50% as of 2020-07.
      if ancestor_ids.include?(cat[:id])
        # puts "DEBUG: ignoring implicitly assigned ancestor category ##{cat[:id]}"
        next
      end

      begin
        execute "INSERT INTO product_categories VALUES (?, ?)", [product_id, cat[:id]]
      rescue SQLite3::ConstraintException => e
        puts "WARNING:".in_orange + " Category '#{cat[:name]}' assigned twice to product #{product_code}. Ignoring."
      end
    end

    # Associate the product with each of its countries. If necessary, create a country record first.
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


  # Fill an author's record in the database with the given field values, but only where there is no value yet.
  # 
  # @param id [Integer]  ID database table `authors` of the author record to update.
  # @param fields [Hash<String>]  Hash of author record fieldnames and values to set, keyed by symbol or string.
  def complete_author(id, fields)

    fields.each do |key, value|
      next if value.nil? or value.empty?

      column = key.to_s
      db_field_is_filled = get_first_value("SELECT ? NOT NULL AND ? != '' FROM authors WHERE id = ?", column, column, id)
      next if db_field_is_filled

      execute "UPDATE authors SET ? = ? WHERE id = ? LIMIT 1", column, value, id
    end
  end


  # Add one author to a topic, creating or completing the author record as needed.
  # 
  # @param topic_id [Integer]
  # @param author [Hash]  Author data. For the hash keys, see {FoodRescue::Topic#authors}.
  def add_author(topic_id, author)
    # Check if there is a record exactly corresponding to the "identifying" parts of an author. (More than one result would 
    # be an error. Not happening, as we check before adding records.)
    # 
    # @todo Write this query in a more compact and readable way.
    author_record = get_first_row "
      SELECT * FROM authors 
      WHERE 
        #{if author[:givenname].nil?   then 'givenname   IS NULL' else "givenname   = '#{author[:givenname]}'"   end} AND
        #{if author[:middlenames].nil? then 'middlenames IS NULL' else "middlenames = '#{author[:middlenames]}'" end} AND
        #{if author[:surname].nil?     then 'surname     IS NULL' else "surname     = '#{author[:surname]}'"     end} AND
        #{if author[:orgname].nil?     then 'orgname     IS NULL' else "orgname     = '#{author[:orgname]}'"     end} 
      LIMIT 1"

    if author_record.nil?
      # Create a not-yet-existing author record.
      execute "
        INSERT INTO authors (givenname, honorific, middlenames, surname, orgname, orgdiv, uri, email) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
        author[:givenname], author[:honorific], author[:middlenames], author[:surname], 
        author[:orgname], author[:orgdiv], author[:uri], author[:email]

      author_id = get_first_value "SELECT last_insert_rowid()"
    else
      # Add more information (if we have) to the existing author record.
      author_id = author_record['id']
      complete_author author_id, author.slice(:honorific, :orgdiv, :uri, :email)
    end

    # Record the connection between this topic and the author record.
    execute "
      INSERT INTO topic_authors (topic_id, author_id, role)
      VALUES (?, ?, ?)", 
      topic_id, author_id, author[:role]
  end


  # Save the content of one food rescue topic to the database.
  # 
  # @param topic_id [Integer]  ID of the topic as recorded in the database.
  # @param lang [String]  Language code of the topic's content, for example `en`.
  # @param title [String]  The topic's title, as a plain text string.
  # @param content [Ox::Document]  The topic's content in DocBook 5.1 XML.
  def add_topic_content(topic_id, lang, title, content)
    execute "
      INSERT INTO topic_contents (topic_id, lang, title, content) VALUES (?, ?, ?, ?)",
      topic_id, lang, title, Ox.dump(content)
  end


  # Insert a topic of food rescue content into the database that does not yet exist there.
  #
  # The topic, as identified by `topic.external_id`, must not yet exist in the database.
  #
  # The given topic can mention bibliographic references. If it does, these must already exist in the database. The topic can
  # also mention an author name. If it exists in the database, it will be referenced, otherwise a new record will be created.
  #
  # @param topic [FoodRescue::Topic]  The topic to add.
  # @return [Integer]  The database ID of the topic just inserted.
  # @raise [RuntimeError]  If a referenced author or literature record does not exist in the database.
  def add_basic_topic(topic)
    # Write the topic's table entry.
    execute "INSERT INTO topics (external_id, section, version) VALUES (?, ?, ?)", topic.external_id, topic.section, topic.edition
    topic_id = get_first_value "SELECT last_insert_rowid()"

    # Ensure that referenced authors exist in the authors table, if necessary creating them.
    # Also create the required topic_authors table entries.
    topic.authors.each do |author| add_author topic_id, author end

    # Write the topic_categories table entry.
    topic.categories.each do |cat|
      cat_id = get_first_value "SELECT category_id FROM category_names WHERE name = ? AND lang LIKE 'en%'", cat
      raise RuntimeError, "Referenced category #{cat} not found." if cat_id.nil?
      # @todo (later) Instead of raising an error, create the category while logging a notice.
      # @todo (later) So far, a topic refers to its categories always in English, regardless of the topic language.
      #   That is limiting, as not all category names have been translated. So, allow topics to reference non-English
      #   categories as well. Their names would start with a language tag.

      # puts "DEBUG: Going to insert into topic_categories: category_id = '#{cat_id}, topic id = #{topic_id}'"

      execute "INSERT INTO topic_categories (category_id, topic_id) VALUES (?, ?)", cat_id, topic_id

      # @todo If the same category was assigned twice, ignore that and print a notice. Currently this leads to a crash.
    end

    # Ensure that referenced literature works exist in the literature table. Raise an error if not.
    # Also write the topic_literature table entries.
    topic.bibliography.each do |bibtex_key|
      literature_record = execute "SELECT * FROM literature WHERE id = ? LIMIT 1", bibtex_key

      if literature_record.empty?
        raise RuntimeError, "Referenced literature work #{bibtex_key} not found in database."
      else
        execute "
          INSERT INTO topic_literature (topic_id, literature_id) VALUES (?, ?)",
          topic_id, bibtex_key
      end
    end

    return topic_id
  end

  # Save one topic of food rescue content to the database.
  # 
  # The given topic can mention bibliographic references. If it does, these must already exist in the database. The topic can 
  # also mention an author name. If it exists in the database, it will be referenced, otherwise a new record will be created.
  # 
  # @param topic [FoodRescue::Topic]  The topic to add.
  def add_topic(topic)

    # Check if a topic by that ID already exists, create it only if not.
    topic_id = get_first_value("SELECT id FROM topics WHERE external_id = ?", topic.external_id)

    if topic_id.nil?
      topic_id = add_basic_topic(topic)
    end

    # Write the topic_contents table entry.
    # @todo Finalize literature references in the topic main text by processing with asciidoctor-bibtex.
    add_topic_content(topic_id, topic.language, topic.title, topic.content)
  end
end
