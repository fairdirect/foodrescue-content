# Suppress depreciation warnings from the awesome_print gem.
# TODO: Fix the gem, then remove this.
$VERBOSE = nil

# Stdlib includes.
require 'date'

# Gem includes. See Gemfile.
require 'sqlite3'
require 'awesome_print'
require 'ox'
require 'asciidoctor'

require_relative '../lib/utils'


# A topic of food rescue content.
# 
# One FoodRescueTopic represents one record in database table `topics`. Connected records in other database 
# tables are referenced by their IDs, without storing their data directly here. (The exception are the 
# author records.)
# 
# "Topic" means a unit of knowledge about food rescue. The name is in analogy to 
# [DocBook 5.1 Topics](https://www.xmlmind.com/tutorials/DocBookAssemblies/).
class FoodRescueTopic

    # The topic's title.
    # @return [String]
    # @todo Support multiple titles, one per language.
    attr_accessor :title 


    # The topic's author(s).
    # 
    # @return [Array<Hash>]  The topic's authors, one per array element. Hash keys:
    #   * `:role`: Contribution of the given author. Values can be "author", "editor", any of the 
    #     `<othercredit class="">` values ([see](https://tdg.docbook.org/tdg/5.1/othercredit.html)) or 
    #     any other value. The latter case, is equivalent to `<othercredit class="other" otherclass="…">`
    #     in DocBook. The default is "author".
    #   * `:givenname`: givenname of the author
    #   * `:honorific`: honorifi title of the author
    #   * `:middlenames`: pre-rendered list of all names between givenname and surname, separated with space characters
    #   * `:surname`: surname of the author
    #   * `:orgname`: the organization name of the author, if the author is an organization; or the author's 
    #      organizational affiliation if the author is a person (means, any of the name keys is present)
    #   * `:orgdiv`: the organization's division, if the author is an organization
    #   * `:uri`: the author's URI, applicable to both persons and organizations
    #   * `:email`: the author's e-mail address, applicable to both persons and organizations
    attr_accessor :authors


    # The topic's version date. If not set at output time, the default is `Date.today`.
    # @return [Date]
    attr_accessor :edition


    # The topic's section, wich is the part where this topic will appear when being displayed as part of 
    # a food item's associated food rescue content.
    # 
    # @return [String]  The section name. The values follow closely the section headings 
    #   in rendered food rescue content: `risks`, `edibility_assessment`, `symptoms`, 
    #   `edible_parts`, `storage_overview`, `storage_instructions`, `preservation`, `preparation`, 
    #   `reuse_and_recycling`.
    attr_accessor :section


    # The topic's Open Food Fact categories.
    # 
    # Their effect is that a food rescue topic is displayed for all products in the given categories.
    # 
    # @return [Array<String>]  The categories, given with their full English names without 
    #   language prefixes.
    # 
    # TODO: Rename to "categories" to comply with the object-relational mapping scheme.
    # TODO: Also support language prefixes.
    # TODO: Also support tag versions of category identifiers. They would be immediately converted 
    #   to full names if possible.
    attr_accessor :off_categories


    # The topic's summary text.
    # @return [String]  The summary, as plain text. The empty string if there is no abstract.
    attr_accessor :abstract


    # @overload main
    #   Gets the topic's main content in DocBook 5.1 XML.
    #   @return [Array<Ox::Element>]
    # 
    # @overload main=(main_content, format)
    #   Set the topic's main content.
    #   @param main_content [Array<Ox::Element>|String]  The object(s) that form the main content, in the 
    #       format specified by `format`.
    #   @param format [Symbol]  The format to interpret main_content. One of:
    #       * `:docbook_dom` if `main_content` is Array<Ox::Element>. This is the default.
    #       * `:asciidoc` if `main_content` is a String with [Asciidoctor markup](https://asciidoctor.org/docs/asciidoc-syntax-quick-reference)
    #       * `:plaintext` if `main_content` is a plain text String. Internally this is just a synonym for 
    #         `:asciidoc` since plaintext strings are valid AsciiDoc.
    # 
    #   @todo Allow providing texts in multiple languages (see database table topic_texts).
    #   @todo Rename to "text" to keep in line with the object-relational mapping scheme.
    #   @todo (later) Also support DocBook XML given as a text string, using format `:docbook`.
    attr_reader :main


    # YARD documentation included at attr_reader :main, ignored here.
    # See: https://github.com/lsegal/yard/blob/master/docs/GettingStarted.md#documentation-for-a-separate-attribute-writer
    def main=(main_content, format: :docbook_dom)
        case format
        when :docbook_dom
            @main = main_content

        when :asciidoc, :plaintext
            @main = []
            docbook_string = Asciidoctor.convert main_content, backend: 'docbook', safe: :safe

            # To parse XML with Ox, we need a single root element. So we wrap and unwrap the content.
            docbook_dom = Ox.parse "<container>#{docbook_string}</container>"
            @main = docbook_dom.nodes
        end
    end


    # Bibliographic references to works used to write this topic in addition to those references 
    # contained in the topic text.
    # 
    # This is used to render a list of additional literature references below the topic text. 
    # In contrast to referencing literature explicitly from inside the topic text, it is not 
    # explicated which information in the topic text comes from each of these extra literature references.
    # 
    # These extra references refer to works in a topic's bibliography, so works referenced here must 
    # also be included into `#bibliography`.
    # 
    # @return [Array<Hash>]  The literature works used, with references to which parts were used.
    #   Each hash describes one work used, with keys as follows: 
    #   * `id`: Identifies the work via its BibTeX key, as recorded in `literature.id` in the database.
    #   * `ref`: A reference to a page, chapter or similar part identifier of the work used.
    #   * `ref_details`: Detailed information about the reference that is only shown when debugging 
    #     automatically imported content. For example, it can contain the database ID of a source record.
    attr_accessor :extra_bibrefs


    # The works of literature referenced in the topic text and in `#extra_bibrefs`.
    # 
    # Only include works of literature that are indeed referenced, as otherwise the literature list 
    # below a topic becomes unnecessary long.
    # 
    # @return [Array<String>]  The literature works in the topic's bibliography, each represented by 
    #   its BibTeX key, as recorded in `literature.id` in the database.
    # 
    # TODO: Create bibliography(data_source) to obtain teh actual bibliographic data from either a 
    #   SQLite3 database or a BibTeX file. Given the object-relational mapping scheme used and the 
    #   independence of FoodRescueTopics from a database, this is the right way to implement this.
    attr_accessor :bibliography


    # Create a new food rescue topic, empty or with values read from a XML file.
    # 
    # @param path [String]  Path to an AsciiDoc file to initialize the object from.
    public
    def initialize(path=nil)

        # Initialize optional elements so no errors will happen when saving to DocBook / SQLite.
        @authors = []
        @off_categories = []
        @abstract = ''
        @extra_bibrefs = []
        @bibliography = []

        # TODO: Create the topic from the data in a DocBook XML file, if specified.
        # Could be possible with the object marshalling (deserialization) functions of Ox.
        # See: http://www.ohler.com/ox/Ox.html#load_file-class_method
    end


    # TODO: Documentation.
    protected
    def docbook_instruct
        instruct = Ox::Instruct.new(:xml)
        instruct[:version] = '1.0'
        instruct[:encoding] = 'UTF-8'

        return instruct
    end


    # TODO: Documentation.
    protected
    def docbook_topic
        topic = Ox::Element.new('topic')

        # TODO Re-enable the "nicer" assignment below once it stops messing up the 
        # syntax highlighting in VS Code.
        # topic.attributes= {
        #     'type': @section,
        #     'version': '5.1',
        #     'xmlns': 'http://docbook.org/ns/docbook',
        #     'xmlns:xlink': 'http://www.w3.org/1999/xlink',
        #     'xmlns:xila': 'http://www.w3.org/2001/XInclude/local-attributes',
        #     'xmlns:xi': 'http://www.w3.org/2001/XInclude',
        #     'xmlns:trans': 'http://docbook.org/ns/transclusion'
        # }
        topic[:'type'] = @section
        topic[:'version'] = '5.1'
        topic[:'xmlns'] = 'http://docbook.org/ns/docbook'
        topic[:'xmlns:xlink'] = 'http://www.w3.org/1999/xlink'
        topic[:'xmlns:xila'] = 'http://www.w3.org/2001/XInclude/local-attributes'
        topic[:'xmlns:xi'] = 'http://www.w3.org/2001/XInclude'
        topic[:'xmlns:trans'] = 'http://docbook.org/ns/transclusion'

        return topic
    end


    # Render the author metadata of this topic to a DocBook XML `author`or `authorgroup` element.
    protected
    def docbook_authors
        # TODO: Is this the right way? Or do we have to return nil?
        return '' if @authors.length == 0

        @authors.each |author| do
            author[:role] = 'author' unless author.key? :role

            # Create the correct outer element for the author / editor / collaborator.
            case author[:role]
            when 'author'
                author_element = Ox::Element.new('author')
            when 'editor'
                author_element = Ox::Element.new('editor')
            when 'copyeditor', 'graphicdesigner', 'productioneditor', 'technicaleditor',\
                    'translator', 'indexer', 'proofreader', 'coverdesigner', 'interiordesigner',\
                    'illustrator', 'reviewer', 'typesetter', 'conversion'
                author_element = Ox::Element.new('othercredit')
                author_element[:class] = author[:role]
            else 
                author_element = Ox::Element.new('othercredit')
                author_element[:class] = 'other'
                author_element[:otherclass] = author[:role]
            end

            # Create the correct inner elements for person / organization names.
            if author.key? :surname # Author is a person.
                personname_element = Ox::Element.new('personname')
                personname_element << (Ox::Element.new('givenname') << author[:givenname]) if author.key? :givenname
                personname_element << (Ox::Element.new('honorific') << author[:honorific]) if author.key? :honorific
                if author.key? :middlenames
                    author[:middlenames].split.each do |name| 
                        middlename = Ox::Element.new('othername') << name
                        middlename[:role] = 'middlename'
                        personname_element << middlename
                    end
                end
                personname_element << (Ox::Element.new('surname') << author[:surname]) if author.key? :surname

                author_element << personname_element

                if author.key? :orgname # Author is a person but affiliation is given.
                    affiliation_element = Ox::Element.new('affiliation')
                    affiliation_element << (Ox::Element.new('orgname') << author[:orgname]) if author.key? :orgname
                    affiliation_element << (Ox::Element.new('orgdiv') << author[:orgdiv]) if author.key? :orgdiv
                    
                    author_element << affiliation_element
                end

            elsif author.key? :orgname # Author is an organization.
                author_element = (Ox::Element.new('orgname') << author[:orgname]) if author.key? :orgname
                author_element = (Ox::Element.new('orgdiv') << author[:orgname]) if author.key? :orgdiv
            end

            author_element = (Ox::Element.new('email') << author[:email]) if author.key? :email
            author_element = (Ox::Element.new('uri') << author[:uri]) if author.key? :uri

            result << author_element
        end

        # Wrap the result in <authorgroup>…</authorgroup> if necessary.
        if result.length > 1
            authorgroup_element = Ox::Element.new('authorgroup')
            result.each {|e| authorgroup_element << e}
            result = authorgroup_element
        end

        return result
    end


    # Render the metadata of this topic to a DocBook XML `info` element.
    protected 
    def docbook_info
        info = Ox::Element.new('info')

        title = Ox::Element.new('title') << @title
        info << title

        info << docbook_authors
        
        date = if @edition.nil? then Date.today.iso8601 else @edition.iso8601 end
        info << (Ox::Element.new('edition') << (Ox::Element.new('date') << date))

        unless @abstract.empty?
            Ox::Element.new('abstract') << (Ox::Element.new('para') << @abstract)
            info << abstract
        end

        unless @off_categories == [] 
            subjectset = Ox::Element.new('subjectset')
            subjectset[:scheme] = 'off-categories-subset-frc'

            @off_categories.each do |cat|
                subjectset << (Ox::Element.new('subject') << (Ox::Element.new('subjectterm') << cat))
            end

            info << subjectset
        end

        return info
    end


    # Render the additional bibliographic references to DocBook XML.
    # 
    # @return Ox::Element
    # 
    # TODO: Render the literature references as proper DoxBook XML elements, not as plain text.
    #   This has to include an element for conditional presentation of the `ref_details` value, 
    #   which is only relevant when debugging where errors in the topics come from.
    protected
    def docbook_extra_bibrefs
        list = Ox::Element.new('itemizedlist')

        @extra_bibrefs.each do |item|
            reference_text = [ item[:ref], item[:ref_details] ].compact.join(', ')
            reference_text = if reference_text.empty? then item[:id] else "#{item[:id]} (#{reference_text})" end

            list << (
                Ox::Element.new('listitem') << (
                    Ox::Element.new('para') << reference_text
                )
            )
        end

        return Ox::Element.new('para') << "Sources used: " << list
    end


    # Render the topic's bibliography to DocBook XML.
    protected 
    def docbook_bibliography
        # TODO (later): Implementation, rendering the actual, full bibliography list. Not required right 
        # now as rendering to DocBook is for later when it comes to ebook publishing. Since usually 
        # multiple topic will be mixed together, their bibliography lists also have to be mixed together. 
        # Due to this, this method should probably return individually rendered items.
    end


    # Write this topic in DocBook 5.1 XML format to the specified file.
    # 
    # @param file_name [String]  The path of the file to write to.
    # @param file_prefix [String]  As an alternative to passing `file_name`, you can let the system 
    #   create the filename by combining the given prefix, the next available sequence number and the 
    #   `.xml` filename extension. The prefix can contain a path (absolute or relative) and a 
    #   filename prefix. Everything after the last "/" (or the whole if there is none) is the filename prefix.
    # @param file_padding [Integer]  The number of digits to use for the numerical filename part that 
    #   follows the given prefix. Ignored when using `file_name`.
    # @raise [Errno::*]  In case the file cannot be opened for writing. As raised by File#open.
    # @raise [ArgumentError]  In case the padding does not provide enough digits to encode the next filename.
    public
    def to_docbook(file_name: nil, file_prefix: nil, file_padding: 3)
        raise ArgumentError "Neither filename nor its prefix have been passed." \
            if file_prefix.nil? and file_name.nil?
        raise ArgumentError "Both filename and prefix have been passed." \
            if !file_prefix.nil? and !file_name.nil?

        doc = Ox::Document.new

        doc << docbook_instruct

        topic = docbook_topic
        topic << docbook_info
        @main.each { |element| topic << element }
        topic << docbook_extra_bibrefs
        topic << docbook_bibliography
        doc << topic

        # Generate the filename from prefix, number and padding (if needed).
        if file_name.nil? 
            search_pattern = file_prefix + ('[0-9]' * file_padding) + '.xml'
            file_nextnum = 1
            Dir.glob(search_pattern).sort.each do |f|
                # The last number in the filename is the file's number.
                file_num = f.scan(/[0-9]{#{file_padding},#{file_padding}}/).last
                file_nextnum = Integer(file_num, 10) + 1 unless file_nextnum.nil?
            end

            if file_nextnum.to_s.length > file_padding
                raise ArgumentError "Not enough digits for the number in the next filename."
            end

            # Zero padding of the file number is done with .rjust; see https://stackoverflow.com/a/1543199
            file_name = file_prefix + file_nextnum.to_s.rjust(file_padding, "0") + '.xml'
        end

        # Documentation for Ox#to_file: https://github.com/ohler55/ox/blob/develop/ext/ox/ox.c#L1336
        # (It's missing from the YARD docs: http://www.ohler.com/ox/Ox.html#to_file-class_method )
        Ox.to_file(file_name, doc, indent: 4)
    end


    # Write this topic to the given SQLite3 database.
    # 
    # @param db [FoodRescueDatabase]  The database interface to use for writing the topic.
    public
    def to_sqlite(db)
        # Delegate to FoodRescueDatabase because handling SQL queries is in its domain. (This is 
        # different from #to_docbook, which is implemented in this class because there is not yet a 
        # class to handle DocBook files.)
        db.add_topic self
    end
end
