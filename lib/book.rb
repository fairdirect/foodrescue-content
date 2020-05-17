# Suppress depreciation warnings from the awesome_print gem.
# @todo Fix the gem, then remove this.
$VERBOSE = nil

# Gem includes. See Gemfile.
require 'awesome_print'

# Local, non-gem includes.
require_relative '../lib/food_rescue'
require_relative '../lib/utils'


# A way to create a book with the food rescue content in DocBook 5.1 XML format.
#
# This is meant to work with `FoodRescue::Database` as the data source, as that is the authoritative data source for all export 
# tasks. Further conversion tasks to EPUB, PDF etc. may be done with XSLT transforms on the generated DocBook files.
#
# @todo Complete the implementation. So far, the code was just moved here from class {FoodRescue::Topic}. It should not take 
#   its data from a collection of topics, but get a connection to the database to fetch its own data as needed.
class FoodRescue::Book

    attr_accessor :topics

    def initialize(topics)
        @topics = topics
    end


    protected
    # @todo Documentation.
    def instruct_element
        instruct = Ox::Instruct.new(:xml)
        instruct[:version] = '1.0'
        instruct[:encoding] = 'UTF-8'

        return instruct
    end


    protected
    # @todo Documentation.
    def topic_element
        doc = Ox::Element.new('topic')

        topic[:'type']        = @section
        topic[:'version']     = '5.1'
        topic[:'xmlns']       = 'http://docbook.org/ns/docbook'
        topic[:'xmlns:xlink'] = 'http://www.w3.org/1999/xlink'
        topic[:'xmlns:xila']  = 'http://www.w3.org/2001/XInclude/local-attributes'
        topic[:'xmlns:xi']    = 'http://www.w3.org/2001/XInclude'
        topic[:'xmlns:trans'] = 'http://docbook.org/ns/transclusion'

        return topic
    end


    protected
    # Render the author metadata of this topic to a DocBook XML `author`or `authorgroup` element.
    def author_element(authors)

        # @todo Is this the right way? Or do we have to return nil?
        return '' if authors.length == 0

        authors.each do |author|
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


    protected
    # Render the metadata of this topic to a DocBook XML `info` element.
    def info_element(title, edition, abstract)
        info = Ox::Element.new('info')

        info << Ox::Element.new('title') << title
        info << docbook_authors
        info << (Ox::Element.new('edition') << (Ox::Element.new('date') << edition))

        unless @abstract.empty?
            Ox::Element.new('abstract') << (Ox::Element.new('para') << abstract)
            info << abstract
        end

        unless @categories == [] 
            subjectset = Ox::Element.new('subjectset')
            subjectset[:scheme] = 'off-categories-subset-frc'

            @categories.each do |cat|
                subjectset << (Ox::Element.new('subject') << (Ox::Element.new('subjectterm') << cat))
            end

            info << subjectset
        end

        return info
    end


    protected
    # Render the topic's bibliography to DocBook XML.
    def bibliography_element(bibliography)
        # @todo (later) Implementation, rendering the actual, full bibliography list. Not required right now as rendering to 
        #   DocBook is for later when it comes to ebook publishing. Since usually multiple topic will be mixed together, their 
        #   bibliography lists also have to be mixed together. Due to this, this method should probably return individually 
        #   rendered items.
    end


    public
    # Write one food rescue topic as a DocBook 5.1 XML topic to disk.
    # 
    # @see #write
    # @todo Modify this to write sections and sub-sections rather than topics. Because when exporting to e-book formats, the 
    #   content from multiple food rescue topics has to be mixed together for the reader, similarly to what the Food Rescue App 
    #   does dynamically.
    def write_topic(topic, file_prefix: nil, file_padding: 3)
        doc = Ox::Document.new

        doc \
            << instruct_element \
            << (topic_element \
                << info_element(topic.title, topic.edition, topic.abstract) \
                << topic.content \
                << bibliography_element(topic.bibliography)
            )

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


    public
    # Write the book in DocBook 5.1 XML format to the specified file(s).
    # 
    # @param file_prefix [String]  As an alternative to passing `file_name`, you can let the system 
    #   create the filename by combining the given prefix, the next available sequence number and the 
    #   `.xml` filename extension. The prefix can contain a path (absolute or relative) and a 
    #   filename prefix. Everything after the last "/" (or the whole if there is none) is the filename prefix.
    # @param file_padding [Integer]  The number of digits to use for the numerical filename part that 
    #   follows the given prefix. Ignored when using `file_name`.
    # @raise [Errno::*]  In case the file cannot be opened for writing. As raised by File#open.
    # @raise [ArgumentError]  In case the padding does not provide enough digits to encode the next filename.
    def write(file_prefix: nil, file_padding: 3)
        @topics.each { |t| t.write_topic(t, file_prefix: file_prefix, file_padding: 3) }
    end

end
