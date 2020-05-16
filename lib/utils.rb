# Various re-usable utility functions and classes.

# Gem includes. See Gemfile.
require 'ox'


# Extend String with ways to colorize text for terminal output.
# 
# Usage: `puts "I'm a red herring".red`
# 
# @see https://stackoverflow.com/a/11482430 (source; written by Erik Skoglund, licenced CC-BY-SA 4.0)
class String
    def colorize(color_code)
        stylize(color_code, 0)
    end

    def stylize(style_code, end_code)
        "\e[#{style_code}m#{self}\e[#{end_code}m"
    end
  
    def in_black;      colorize(30) end
    def in_red;        colorize(31) end
    def in_green;      colorize(32) end
    def in_orange;     colorize(33) end
    def in_blue;       colorize(34) end
    def in_magenta;    colorize(35) end
    def in_cyan;       colorize(36) end
    def in_gray;       colorize(37) end

    def on_black;      colorize(40) end
    def on_red;        colorize(41) end
    def on_green;      colorize(42) end
    def on_orange;     colorize(43) end
    def on_blue;       colorize(44) end
    def on_magenta;    colorize(45) end
    def on_cyan;       colorize(46) end
    def on_gray;       colorize(47) end

    def in_bold;       stylize(1, 22) end
    def in_italic;     stylize(3, 23) end
    def underlined;    stylize(4, 24) end
    def blinking;      stylize(5, 25) end
    def reversed;      stylize(7, 27) end
end


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


class Ox::Element

    # Appends a Node (or the nodes of a `Ox::Document` or array) to the Element's nodes array.
    # 
    # This overwrites the original `Ox::Element#<<` operator to support merging of documents and arrays. 
    # The operator could be applies to `Ox::Document` before because it's a subclass of `Ox::Node`. 
    # But doing so later results in "Unexpected class, Ox::Document, while dumping generic XML". 
    # Instead, we'll treat `Ox::Document` as a collection of nodes, and just append these nodes.
    # 
    # @param appendee [Ox::Node | String | Array] The node or collection of nodes to append. Appending 
    #   a String means adding a plaintext section to an XML element, without further XML inside.
    # @return The element itself, after appending the node(s) from the given argument. This allows 
    #   to chain multiple appends together.
    def <<(appendee)
        raise "argument to << must be one of: Ox::Node, String, Array." \
            unless appendee.is_a?(String) or appendee.is_a?(Ox::Node)

        @nodes = [] if !instance_variable_defined?(:@nodes) or @nodes.nil?

        case appendee
        when Ox::Document
            appendee.nodes.each { |n| @nodes << n }
        when Array
            appendee.each { |n| @nodes << n }
        when Ox::Node, String
            @nodes << appendee
        end

        self
    end
end