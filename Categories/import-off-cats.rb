#!/usr/bin/ruby

require 'docopt'
version = '0.1'
doc = <<DOCOPT
Convert Open Food Facts category definitions into a XML or SQL format.

The script reads all files given by INFILE arguments, and writes the converted data to OUTFILE 
or to stdout if none is given. Two types of INFILE files are understood:

* Open Food Facts category data JSON files, for example: 
  https://world.openfoodfacts.org/category/categories
* Open Food Facts category taxonomy files, for example: 
  https://github.com/openfoodfacts/openfoodfacts-server/blob/master/taxonomies/categories.txt

Usage:
  #{__FILE__} INFILE... [options] [OUTFILE]
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  --filter-lang LANGS         Only include categories in the given languages, specified as a 
                              comma-separated list of ISO 639-1 two-letter language codes.
  --filter-known              Only include categories that are included in the Open Food Facts 
                              category taxonomy.
  --filter-min-use COUNT      Only include categories with at least COUNT uses.
  -f FORMAT, --format FORMAT  Write the output in format XML or SQLite3. [default: SQLite3]
  -h, --help                  Show this screen.
  -v, --version               Show version.

DOCOPT

begin
  args = Docopt::docopt(doc, {version: version, help: true})
rescue Docopt::Exit => e
  puts e.message
end

## SECTION: INPUT

# Validate the input filenames.
for filename in args['INFILE'] do
  # Make sure the file exists and can be read; exit if not.
  # TODO
end

# Validate the argument to --filter-lang.
unless args['--filter-lang'] = false then
  args['--filter-lang'] = args['--filter-lang'].split(',')

  # TODO: Go through the array and check if all languages are valid codes. Exit if not.
end

# Validate the argument to --filter-min-use.
unless args['--filter-min-use'] = false then
  begin
    args['--filter-min-use'] = Integer(args['--filter-min-use'])
  rescue ArgumentError
    puts "Argument to --filter-min-use must be an integer.\n\n"
    Docopt::Exit.set_usage(nil)
    raise Exit
  end
end

# Validate the argument to --format.
unless ['XML', 'SQLite3'].include?(args['--filter-min-use'])
  puts "--format must be XML or SQLite3.\n\n"
  Docopt::Exit.set_usage(nil)
  raise Exit
end


## SECTION: CONVERSION

# Read all JSON input files into a common data structure.
for filename in arguments['INFILE'].select { |f| File.extname(f) = '.json' } do
    # TODO: Parse the JSON file.
    # TODO: Validate the JSON file against a schema.
    # TODO: Put the JSON file into a hash indexed by JSON field "ID".
end

# Read all other input files into the same JSON-derived datastructure.
# (Parsing must happen after having all infos from JSON files.)
for filename in arguments['INFILE'].select { |f| File.extname(f) != '.json' } do
    # TODO: Parse the file. (Using the Perl server software parser as a template.)
    # TODO: Record hierarchy information and translation information into our data structure.
  end
end

# Mark all elements to export: categories matching --filter-* and their parents.
# TODO


## SECTION: OUTPUT

# Export all marked elements to SQLite format (without buffering).
# TODO

# Export all marked elements to XML format (without buffering).
# TODO
