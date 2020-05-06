# Suppress depreciation warnings from the awesome_print gem.
# TODO: Fix the gem, then remove this.
$VERBOSE = nil

# Stdlib includes.
require 'date'

# Gem includes. See Gemfile.
require 'sqlite3'
require 'awesome_print'
require 'ox'


module Ox::HasAttrs

    # Add a method for mass assigning attributes, in analogy to the mass read method #attributes.
    # 
    # @param attributes [Hash]  The attributes to assign.
    # @see #attributes
    # @see http://www.ohler.com/ox/Ox/HasAttrs.html#attributes-instance_method
    # TODO: Suggest this as a feature upstream in Ox::HasAttrs.
    def attributes= (attributes)
        attributes.each { |key, value| self[key] = value }
    end
end


# Represents a food rescue content topic, and its representation in a DocBook XML file.
# 
# A unit of knowledge about food rescue is called a "topic". The name is in analogy to 
# [DocBook 5.1 Topics](https://www.xmlmind.com/tutorials/DocBookAssemblies/), the file 
# format used to store these units of knowledge.
class FoodRescueTopic

    # TODO (later): Documentation.
    def initialize(docbook_path: nil)

        # Initialize optional elements so no errors will happen when saving to DocBook / SQLite.
        @author = {}
        @off_categories = []
        @abstract = ''
        @literature_used = []
        @bibliography = {}

        # TODO (later): Create the topic from the data in a DocBook XML file, if specified.
        # Could be possible with the object marshalling (deserialization) functions of Ox.
        # See: http://www.ohler.com/ox/Ox.html#load_file-class_method
    end


    # Set the topic's title.
    # @param title [String]
    def title=(title);                  @title = title end


    # Set the topic's author.
    # @param author [Hash]  Defines the author name or where to obtain it. Keys:
    #   * include_from: relative or absolute path to a XML file with the <author> element
    #   * firstname: firstname of the author if given directly
    #   * lastname: lastname of the author if given directly
    def author=(author);                @author = author end


    # Set the topic's version date. If not set at output time, the default is `Date.today`.
    # @param date [Date]
    def edition=(date);                 @edition = date end


    # Set the topic's section (the part where this topic will appear when being displayed as part of a food 
    # item's associated food rescue content).
    # 
    # @param section [String]  The section name. The values follow closely the section headings 
    #   in rendered food rescue content: `risks`, `edibility_assessment`, `symptoms`, 
    #   `edible_parts`, `storage_overview`, `storage_instructions`, `preservation`, `preparation`, 
    #   `reuse_and_recycling`.
    def section=(section);              @section = section end


    # Set the topic's Open Food Fact categories.
    # 
    # This food rescue topic will be displayed for all products in the given OFF categories.
    # @param categories [Array<String>]  The categories, given with their full names without 
    #   language prefixes.
    def off_categories=(categories);    @off_categories = categories end


    # Set the topic's summary text.
    # @param text [String]  The summary, as plain text.
    def abstract=(text);                @abstract = text end


    # Set the topic's main content.
    # 
    # @param elements [Array<Ox::Element>]  The elements that form the main content.
    # 
    # TODO (later): Also support a plaintext parameter. Good for automatic content generation for testing.
    # TODO (later, maybe): Also support XML given as a text string.
    def main=(elements);                     @main = elements end


    # Set the works of literature used to write this topic.
    # 
    # This will be rendered as an unspecific literature reference at the bottom of the topic.
    # 
    # @param works [Array<String>]  The identifiers of the literature works in the bibliography, 
    #   using the value of the works' DocBook XML `biblioentry`.`abbrev` elements.
    def literature_used=(works)         @literature_used = works end


    # Set the content of the bibliography section available for literature references in this topic.
    # 
    # The bibliography may contain more works than referenced in this topic, allowing to share it 
    # between topics. In the rendered output, only those works will be listed that are in use.
    # 
    # @param biblio [Hash]  Defines the bibliography section or where to obtain it. Keys:
    #   * include_from: relative or absolute path to a XML file with the <author> element
    # @todo Also implement a way to specify the bibliography section directly.
    def bibliography=(bibliography)     @bibliography = bibliography end


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
    def docbook_topic_element
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


    # TODO: Documentation.
    protected 
    def docbook_info
        info = Ox::Element.new('info')

        title = Ox::Element.new('title') << @title
        info << title

        author = Ox::Element.new('xi:include')
        author[:href] = 'author-foodkeeper.xml'
        info << author
        
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


    # TODO: Documentation.
    protected 
    def docbook_bibliography
        bibliography = Ox::Element.new('xi:include')
        bibliography[:href] = 'bibliography.xml'

        return bibliography
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

        topic = docbook_topic_element
        topic << docbook_info
        @main.each { |element| topic << element }
        topic << docbook_bibliography

        doc << docbook_instruct
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
    # @param db [SQLite3::Database]  The database connection to use for writing the topic. The following 
    #   table structure must exist in it: (TODO).
    public
    def to_sqlite(db)
        # TODO
    end
end
