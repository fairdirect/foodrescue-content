# Utility functions for this project.

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