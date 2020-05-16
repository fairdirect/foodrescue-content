# Suppress depreciation warnings from the awesome_print gem.
# @todo Fix the gem, then remove this.
$VERBOSE = nil

# Stdlib includes.
require 'date'

# Gem includes. See Gemfile.
require 'sqlite3'
require 'awesome_print'
require 'ox'
require 'asciidoctor'

# Local, non-gem includes.
require_relative '../lib/food_rescue'
require_relative '../lib/utils'


# A topic of food rescue content.
# 
# One FoodRescue::Topic represents one record in database table `topics`. Connected records in other database 
# tables are referenced by their IDs, without storing their data directly here. (The exception are the 
# author records.)
# 
# "Topic" means a unit of knowledge about food rescue. The name is in analogy to 
# [DocBook 5.1 Topics](https://www.xmlmind.com/tutorials/DocBookAssemblies/).
class FoodRescue::Topic

    public
    # Create a new food rescue topic, empty or with values read from a XML file.
    # 
    # @param path [String]  Path to an AsciiDoc file to initialize the object from.
    def initialize(path=nil)

        # Initialize optional elements so no errors will happen when saving to DocBook / SQLite.
        @authors = []
        @categories = []
        @abstract = ''
        @edition = Date.today.iso8601.to_s
        @content_xbibrefs = []
        @bibliography = []

        # @todo Create the topic from the data in a DocBook XML file, if specified.
        # Could be possible with the object marshalling (deserialization) functions of Ox.
        # See: http://www.ohler.com/ox/Ox.html#load_file-class_method
    end


    # The topic's title.
    # 
    # @return [String]
    # @todo Support multiple titles, one per language.
    attr_accessor :title 


    # The topic's author(s).
    # 
    # @return [Array<Hash>]  The topic's authors, one per array element. Hash keys:
    #   
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


    # The topic's version date.
    # 
    # @return [String]  The version date as a String in ISO8601 "yyyy-mm-dd" format. Defaults to today.
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
    # @todo Also support language prefixes.
    # @todo Also support tag versions of category identifiers. They would be immediately converted 
    #   to full names if possible.
    attr_accessor :categories


    # The topic's summary text.
    # 
    # @return [String]  The summary, as plain text. The empty string if there is no abstract.
    attr_accessor :abstract


    # The topic's content in DocBook 5.1 XML, excluding parts that are automatically appended 
    # such as a list of the literature used (see {#content_xbibrefs}).
    # 
    # @return [Ox::Document]
    # @todo Allow providing texts in multiple languages (see database table topic_texts).
    # @todo Rename to "text" to keep in line with the object-relational mapping scheme.
    attr_accessor :content_proper


    public
    # Set the topic's main content in DocBook 5.1 XML by converting from a different format.
    # 
    # @param content [Ox::Document | String]  The object(s) that form the topic's content.
    # @param format [Symbol]  The format to interpret `content`. One of:
    # 
    #   * `:docbook_dom` if `content` is `Array<Ox::Element|String>`, as used in {Ox::Element#nodes}. This is the default.
    #   * `:asciidoc` if `content` is a String with [Asciidoctor markup](https://asciidoctor.org/docs/asciidoc-syntax-quick-reference).
    #   * `:plaintext` if `content` is a plain text String. Internally this is a synonym for 
    #     `:asciidoc` since plaintext strings are valid AsciiDoc.
    # 
    # @todo (later) Also support DocBook XML given as a text string, using format `:docbook`.
    def import_content_proper(content, format: :docbook_dom)
        case format
        when :docbook_dom
            @content_proper = content

        when :asciidoc, :plaintext
            content_docbook_string = Asciidoctor.convert content, backend: 'docbook', safe: :safe

            # docbook_dom may have multiple XML elements at the root level, so we want Ox.parse() 
            # to return a Ox::Document rather than a single Ox::Element (the only other option).
            # To recognize a XML document, Ox needs a prepended <?xml?> processing instruction.
            content_docbook_dom = Ox.parse "<?xml?>#{content_docbook_string}"

            @content_proper = content_docbook_dom
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
    # 
    #   * `id`: Identifies the work via its BibTeX key, as recorded in `literature.id` in the database.
    #   * `ref`: A reference to a page, chapter or similar part identifier of the work used.
    #   * `ref_details`: Detailed information about the reference that is only shown when debugging 
    #     automatically imported content. For example, it can contain the database ID of a source record.
    attr_accessor :content_xbibrefs


    public
    # Get the complete content field of this food rescue topic, as it would be stored in a database for 
    # showing to a user.
    # 
    # This includes #content_proper and any automatically generated content before and afterwards, 
    # such as a list of bibliographic references.
    # 
    # @return [Ox::Document | NilClass]  DocBook XML content with the bibliographic references, 
    #   or `nil` if there are none.
    # @todo Render the literature references as proper DoxBook XML elements, not as plain text.
    #   This has to include an element for conditional presentation of the `ref_details` value, 
    #   which is only relevant when debugging where errors in the topics come from.
    def content 

        if @content_xbibrefs.nil? or @content_xbibrefs.empty? 
            return content_proper

        else
            # Render the literature references into a list.
            list = Ox::Element.new('itemizedlist')
            # 
            @content_xbibrefs.each do |item|
                reference_text = [ item[:ref], item[:ref_details] ].compact.join(', ')
                reference_text = if reference_text.empty? then item[:id] else "#{item[:id]} (#{reference_text})" end

                list << (
                    Ox::Element.new('listitem') << (
                        Ox::Element.new('para') << reference_text
                    )
                )
            end

            # << modifies the caller object, so duplicate it to avoid the damage.
            return content_proper.dup << (Ox::Element.new('simpara') << "Sources used: ") << list
        end
    end


    # The works of literature referenced in the topic text and in `#xbibrefs`.
    # 
    # Only include works of literature that are indeed referenced, as otherwise the literature list 
    # below a topic becomes unnecessary long.
    # 
    # @return [Array<String>]  The literature works in the topic's bibliography, each represented by 
    #   its BibTeX key, as recorded in `literature.id` in the database.
    # @todo Create bibliography(data_source) to obtain teh actual bibliographic data from either a 
    #   SQLite3 database or a BibTeX file. Given the object-relational mapping scheme used and the 
    #   independence of FoodRescue::Topics from a database, this is the right way to implement this.
    attr_accessor :bibliography

end
