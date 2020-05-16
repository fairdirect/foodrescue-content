# Various re-usable utility functions and classes.

# Gem includes. See Gemfile.
require 'ox'


# A mixin that extends String with ways to colorize text for terminal output.
# 
# Usage:
# 
# * `puts "I'm a red herring".in_red`
# * `puts "#{'WARNING:'.in_red.on_cyan} Hello World"`
# 
# @see https://stackoverflow.com/a/11482430 base code (written by Erik Skoglund, licenced CC-BY-SA 4.0)
class String

    # Apply color formatting when writing to terminal output.
    # 
    # @param color_code [Integer]  Numerical part of the escape sequence to colorize the string.
    # @see https://stackoverflow.com/a/18280137 available color codes
    def colorize(color_code)
        stylize(color_code, 0)
    end

    # Apply any formatting when writing to terminal output.
    # 
    # @param style_code [Integer]  Numerical part of the escape sequence to stylize the string.
    # @param end_code [Integer]  Numerical part of the matching escape sequence to end the one started with `style_code`.
    # @see https://stackoverflow.com/a/18280137 available style codes
    def stylize(style_code, end_code)
        "\e[#{style_code}m#{self}\e[#{end_code}m"
    end

    # Write the string in black.
    def in_black;      colorize(30) end
    # Write the string in red.
    def in_red;        colorize(31) end
    # Write the string in green.
    def in_green;      colorize(32) end
    # Write the string in orange.
    def in_orange;     colorize(33) end
    # Write the string in blue.
    def in_blue;       colorize(34) end
    # Write the string in magenta.
    def in_magenta;    colorize(35) end
    # Write the string in cyan.
    def in_cyan;       colorize(36) end
    # Write the string in gray.
    def in_gray;       colorize(37) end

    # Write the string on black background.
    def on_black;      colorize(40) end
    # Write the string on red background.
    def on_red;        colorize(41) end
    # Write the string on green background.
    def on_green;      colorize(42) end
    # Write the string on orange background.
    def on_orange;     colorize(43) end
    # Write the string on blue background.
    def on_blue;       colorize(44) end
    # Write the string on magenta background.
    def on_magenta;    colorize(45) end
    # Write the string on cyan background.
    def on_cyan;       colorize(46) end
    # Write the string on gray background.
    def on_gray;       colorize(47) end

    # Write the string in bold font.
    def in_bold;       stylize(1, 22) end
    # Write the string in italic font.
    def in_italic;     stylize(3, 23) end
    # Write the string in underlined font.
    def underlined;    stylize(4, 24) end
    # Write the string in blinking font.
    def blinking;      stylize(5, 25) end
    # Write the string in reversed font.
    def reversed;      stylize(7, 27) end
end


# A mixin for `Ox::HasAttrs`, adding small fixes or convenience features.
module Ox::HasAttrs

    # Add a method for mass assigning attributes, in analogy to the mass read method #attributes.
    # 
    # @param attributes [Hash]  The attributes to assign.
    # @see #attributes
    # @see http://www.ohler.com/ox/Ox/HasAttrs.html#attributes-instance_method
    # @todo Suggest this as a feature upstream in Ox::HasAttrs.
    def attributes= (attributes)
        attributes.each { |key, value| self[key] = value }
    end
end


# A mixin for `Ox::Element`, adding small fixes or convenience features.
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
