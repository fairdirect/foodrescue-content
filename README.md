# Food Rescue Content


**Table of Contents**

**[1. Overview](#1-overview)**

**[2. Installation](#2-installation)**

**[3. Repository Layout](#3-repository-layout)**

**[4. Development Setup](#4-development-setup)**

**[5. Build Process](#5-build-process)**

**[6. Style Guide](#6-style-guide)**

  * [6.1. Content Authoring](#61-content-authoring)
  * [6.2. Software Design](#62-software-design)
  * [6.3. Code Style Guide](#63-code-style-guide)
  * [6.4. Documentation Style Guide](#64-documentation-style-guide)

**[7. License and Credits](#7-license-and-credits)**

------


## 1. Overview

This repository contains open knowledge about rescueing expired or otherwise tarnished food, and scripts to convert and package this knowledge. This dataset is made for the open source [Food Rescue App](https://fairdirect.org/food-rescue-app), and the main build output here is the SQLite database used by that app.

In addition, the following re-usable pieces of this repository will be interesting to Open Food Facts developers:

* **Scripts to import Open Food Facts CSV to SQLite.** See `scripts/frc-import-*.rb`. Only a few fields are imported right now (GTIN / barcode, category, countries, category taxonomy) but this can be extended easily. The result is a fully normalized and storage space optimized SQLite database. Previous solutions are [PostgreSQL import instructions](https://blog-postgresql.verite.pro/2018/12/21/import-openfoodfacts.html) and [a minimal SQLite import script](https://github.com/benhamner/open-food-facts). Both result in one single table, structured like the CSV file. By contrast, the scripts provided here result in a fully normalized table structure. For potential new tools, check the Open Food Facts wiki page "[Reusing Open Food Facts Data](https://wiki.openfoodfacts.org/Reusing_Open_Food_Facts_Data)".

* **Script to filter the Open Food Facts CSV file.** See `scripts/frc-filter-products-csv.rb`. In most cases you'll be better off and faster done using [`csvkit`](https://csvkit.readthedocs.io/), though.


## 2. Installation

The simplest way to install the build outputs from this repository is:

1. **Download a release version.** Go to [foodrescue-content releases](https://github.com/fairdirect/foodrescue-content/releases) and download the release version corresponding to the version of [Food Rescue App](https://github.com/fairdirect/foodrescue-app) that you have built or want to build. Version numbers always corresponds; for example, foodrescue-content v0.3 is meant to be used with foodrescue-app v0.3. In almost all cases, simply download the latest version.

2. **Unzip.** The database is provided as a ZIP compressed file, so you have to unzip it first:

    ```
    unzip foodrescue-content.sqlite3.zip
    ```

3. **Place the database into the correct location.** Put it (or symlink it) into the location where Food Rescue App will find it when starting. The location is different for different operating systems, and mentioned in the [Food Rescue App README, section 5. Development Guide](https://github.com/fairdirect/foodrescue-app#5-development-guide) in steps "Install the database.".


## 3. Repository Layout

**A self-contained repository.** The source code here is everything to reliably build the outputs. External libraries are omitted as long as they can be reliably obtained on demand in the required version. The latter is difficult for datasets. For example, the Open Food Facts dataset utilized here does not come in versioned releases. So to make build outputs reproducible and allow error isolation, relevant subsets of the Open Food Facts dataset are included in this repository. That data is not compressed, allowing for space-efficient handling of revisions by Git.

**Files and folders.**

@todo


## 4. Development Setup

This is a set of Ruby scripts requiring Ruby 2.7 or higher (but only because `Enumerable#filter_map` is used in a few places). Assuming a Debian-esque Linux, Ruby 2.7 and `bundler` are available system-wide, you could just install everything with:

```
sudo apt install sqlite3 libsqlite3-dev
git clone https://github.com/fairdirect/foodrescue-content.git
cd foodrescue-content
bundle install
```

However, for server environments and also to separate your various Ruby projects, it is often preferable to install multiple rubies in parallel and switch between them. Here is a setup like that for Ubuntu 19.10:

1. **Install [`ruby-install`](https://github.com/postmodern/ruby-install/).**

    ```
    sudo apt update
    sudo apt install build-essential

    cd ~/some-temp-dir/
    wget -O ruby-install-0.7.0.tar.gz https://github.com/postmodern/ruby-install/archive/v0.7.0.tar.gz
    tar -xzvf ruby-install-0.7.0.tar.gz
    cd ruby-install-0.7.0/
    sudo checkinstall make install
    ```

2. **Install Ruby.**

    ```
    ruby-install ruby 2.7.1
    ```

3. **Install [`chruby`](https://github.com/postmodern/chruby).**

    ```
    wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz
    cd chruby-0.3.9/
    sudo checkinstall make install

    # Run this to make your ~/.bashrc include chruby on login.
    printf '%s\n' \
        "# Load chruby, a tool to switch between Ruby versions." \
        "source /usr/local/share/chruby/chruby.sh" \
        "source /usr/local/share/chruby/auto.sh"   \
        >> ~/.$(basename $SHELL)rc
    
    # Reload the shell (or open a new tab).
    exec $SHELL
    ```

4. **Test `chruby`.**

    1. Execute `chruby`. It should show available rubies.
    2. Execute `chruby` in the repo's directory. It should show that Ruby 2.7.1 is selected now, due to the auto-switching mechanism using the `.ruby-version` file in this repository. Whenever you change `.ruby-version`, you need to re-login or `exec $SHELL` again for the changes to be picked up.

5. **Install `bundler`.** Notes:

    * This will install `bundler` to `~/.gem/ruby/2.3.7/`. This is probably needed, as installing gems into a gem bundle is only possible with bundler. However, it might be better to install bundler system-wide.
    * This only works when `chruby` shows that a Ruby is active. Otherwise you get "ERROR: Could not find a valid gem 'bundler' (>= 0) in any repository".

    ```
    gem install bundler
    ```

6. **Install the SQLit3.**

    ```
    sudo apt install sqlite3 libsqlite3-dev
    ```

7. **Clone the repository.**

    ```
    git clone https://github.com/fairdirect/foodrescue-content.git
    cd foodrescue-content
    ```

8. **Install the gemset.**

    ```
    bundle install
    ```


## 5. Build Process

The build output is a SQLite3 database `foodrescue-content.sqlite3`. For now, the instructions below simply link to recipes in the [developer notes for this project](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA), because eventually the whole build process will be automated and available as a single `rake` call. For the time being, it's this more manual build process:

1. **[Import the Open Food Facts categories](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#z=SkWGMKu7dTKGDLzdMeqKXwSR).** Both topics and products depend on categories, so this step has to come first. The output is the SQLite3 database file, for now filled only with the OFF category hierarchy, using category names in all available languages:

    ```
    build/foodrescue-content.sqlite3
    ```

2. **[Convert the FoodKeeper data to food rescue topics](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#z=-z4bUBa-OgxdNdk41YixMrzG).** The output are the following CSV files, using AsciiDoctor syntax for some column values, wich is the native topic format for this project:

    ```
    content-topics-foodkeeper/topics-foodkeeper-de.csv
    content-topics-foodkeeper/topics-foodkeeper-en.csv
    ```

3. **[Import all food rescue topics](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#z=T-Qjurv_B2Wkh_2SmLafB9sQ).** This imports both the native food rescue topics from `content-topics-native/` and also the topics converted from FoodKeeper content above. It does not create a new build output but adds to the SQLite3 database file:

    ```
    build/foodrescue-content.sqlite3
    ```

4. **[Import the Open Food Facts products](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#z=XRDaq0klfoPLh6ak2stvrI19).** This step will take the most time by far (around 60 minutes), so it's good to do it last. It does not create a new build output but completes the SQLite3 database file:

    ```
    build/foodrescue-content.sqlite3
    ```

TODO: Improve this build process so that eventually one only has to run `./scripts/frc make` to build everything.

The build scripts have other capabilities that are helpful for example when you want to rebuild only parts of the database content. To learn about these:

* Look at the [list of recipes](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#q=%23foodrescue-content%20) in the developer notes for this project.

* Use the command line option `--help` with any of the custom build scripts in folder `scrips/` to learn about its usage.


## 6. Style Guide

### 6.1. Content Authoring

To contribute new food rescue content to this repository, you can choose between two formats:

* Put many short articles together into one LibreOffice `.fods` spreadsheet in directory `content-topics-csv`.
* Put longer articles into individual files into directory `content-topics-asciidoc`.

In both cases, you write the actual content using AsciiDoctor syntax ([reference](https://asciidoctor.org/docs/asciidoc-syntax-quick-reference), [cheatsheet](https://powerman.name/doc/asciidoc)). Note that some [Markdown can be used](https://asciidoctor.org/docs/asciidoc-syntax-quick-reference/#markdown-compatibility) via an extension of AsciiDoctor syntax, and we prefer that over the "normal" AsciiDoctor syntax wherever it can be utilized.

To create and edit the content in spreadsheets, collaborators are free to use whatever tool they like, as long as the content is finally in a CSV or LibreOffice `.fods` format with the columns mentioned below and included into this "authoritative" repository [fairdirect/foodrescue-content](https://github.com/fairdirect/foodrescue-content).

**The columns to use in a spreadsheet file:** You can use file `content-topics-csv/template.ods` to start a new spreadsheet file with food rescue content. It already contains the necessary columns as documented below.

* **ID.** A continuous number, unique inside your spreadsheet file. Used for tracing back content errors from the database to their source documents.

* **Text.** The actual content of your food rescue topics, using AsciiDoctor syntax. Note that only this column allows to use the AsciiDoctor markup language, all other columns have to be plain text.

* **Text type.** Possible values are mentioned in the documentation of [content sections](https://dynalist.io/d/To5BNup9nYdPq7QQ3KlYa-mA#z=ZYsoIiZKiCqqvdw_JZC4f7fV). As of 2020-06-29, the possible values are:
    * `risks`
    * `assessment`
    * `symptoms`
    * `post_spoilage`
    * `donation_options`
    * `edible_parts`
    * `residual_food`
    * `unliked_food`
    * `pantry_storage`
    * `refrigerator_storage`
    * `freezer_storage`
    * `other_storage`
    * `commercial_storage`
    * `preservation`
    * `preparation`
    * `reuse_and_recycling`
    * `production_waste`
    * `packaging_waste`

* **Categories.** The Open Food Facts categories to show this topic for, as a multiline field with one category name per line. Use the full category names, not the Open Food Facts tag version of the category names.

* **Author.** Firstname and lastname of who wrote this topic.

* **Date added.** An ISO 8601 date.

* **Version date.** An ISO 8601 date.

**AsciiDoctor format restrictions:** Due to the conversion step from DocBook to HTML done just before rendering with own XQuery transformations, at this time not the full syntax of AsciiDoctor is supported. Any unsupported syntax simply results in DocBook tags that will be ignored (not ignoring their content, though). At the current time, the DocBook conversion can handle the following elememts, so all AsciiDoctor syntax equivalent to these is evaluated, and all other AsciiDoctor syntax is effectively ignored:

* `title`
* `simpara`
* `itemizedlist`
* `listitem`
* TODO: Complete this list. It should eventually contain all DocBook elements generated from AsciiDoc by the typical conversion process.


**Content authoring tips:**

* Alle Angaben sollten auf Literatur-Referenzen beruhen, damit die Informationen nachprüfbar sind und vertrauenswürdig wirken (und wir nicht irgendwelche Probleme mit Haftungsdingen haben wenn sich jemand mal eine Lebensmittelvergiftung holt …).

* To enter a forced linebreak in a LibreOffice spreadsheet, press Ctrl + Return.

* Obviously, do not copy from copyrighted material, and when copying from open content material provide proper attribution (via literature references).

* Place references to web resources as ordinary hyperlinks. Except if the web resource is a source reference for your content, in which case use a proper literature reference.

* To create a literature reference in your text, use a shortname for the literature item and a page reference like this: `cite:[Shortname(123)]`. This is [asciidoctor-bibtex syntax](https://github.com/asciidoctor/asciidoctor-bibtex#usage), see there for details.

* Define the shortnames used in your literature references in a proper bibliography in [BibTeX format](https://ctan.org/pkg/biblatex-cheatsheet).


### 6.2. Software Design

* **Database as authoritative data source.** The SQLite3 database is used as intended for a "data base", as the one-and-only authoritative source for food rescue content. So naturally, the tasks of scripts provided in this repository are to (1) first import all data from various source formats to the database, (2) then do anything else using the data in the database, such as export to a minified database, to a book in DocBook format and so on.

* **Database to provide consistency during a script run.** Many challenges in programming are related to consistency and predictability of data modification. Solutions to this in object-oriented programming are quite verbose, such as side-effect free code by not modifying any global variables (and instead needing all variables via parameters) and capsuling all data into objects. A simpler way is to let the database ensure data consistency (as that is its job!) and only pass the database connection around as a parameter. There is nothing to be said against every part of the program being able to read and write every part of the database. There is no need for the complexity of a complete OOP layer to access that data as objects (see below for hashes and IDs to represent database objects). For example, instead of passing supplementary data of a CSV file around, import it to the database first, then only pass the database connection around.

* **Object-relational mapping scheme.** The data of database records and application logic related to it is placed into classes created like in Rails ActiveRecord: one class per table, one object per database record, one attribute per column, and lazy loading of connected records from other tables via instance methods. Small tables can be exceptions from the "one class per table" rule. For example, topic author data is also handled by class `FoodRescue::Topic`. Objects delegate behavior related to storing to and loading from the database to a single class `FoodRescue::Database`, so that the storage backend can be exchanged easily. All SQLite3 queries are contained within class `FoodRescue::Database`.

* **Classes for database tables should use SQLite3 compatible data types for attributes.** All values in SQLite3 are of the storage classes NULL, INTEGER, REAL, TEXT, BLOB ([see](https://www.sqlite.org/datatype3.html)). To avoid useless conversions, attributes in classes representing database tables should use values of the equivalent Ruby data types Nil, Integer, Real and String. The task of these classes is being a database interface, so there is no use for higher-level datatypes in them – for example, no need for `FoodRescue::Topic#edition` to be of type Date when it is saved as storage class TEXT in the database anyway. The exception are attributes where additional semantics are needed for transformations during the object lifetime; for example, Ox::Element to represent DocBook XML in the main text content of `FoodRescue::Topic`.

* **Hashes as lightweight objects.** The SQLite3 interface returns database records as hashes, keyed by fieldname. This data structure is used as a lightweight representation where structured data is needed as for Ruby objects, but without attached behavior, so not requiring a custom class. These objects can be aggregated in arrays or in hashes keyed by database ID. In the latter case, the hashes representing the database records should still have their ID hash key inside in addition, to keep up a uniform interface.

* **Database IDs as even more lightweight objects.** The database ID of an object, as a string, can be used as an even lighter way to represent objects, namely where only a reference is needed and not the data about the object. These can be aggregated in arrays.

* **Data type for DocBook XML content.** `Ox::Document` is meant to store collections of XML elements (inside its `#nodes` array), without being an element itself or rendering to visible XML output. See: `Ox.dump(Ox::Document.new) => "\n"`. So this is used to hand over collections of XML elements, even if this does not represent a fully features XML element. It's cleaner than using the data structure of the `#nodes` arrays directly, which would be `Array<Ox::Element|String>`).


### 6.3. Code Style Guide

The guiding idea is to write code that reads almost like natural language. That affects variable and method naming, source code layout and also choice of the logical flow and distributing algorithmic complexity so that one can understand everything while reading through once.

This project relies on [The Ruby Style Guide](https://rubystyle.guide/), but with the following justified exceptions that make code read more like natural language:

* **Maximum Line Length.** The Ruby Style Guide [recommends](https://rubystyle.guide/#80-character-limits) 80 characters. This project uses (1) a soft limit of 100 characters for code and code comments typically read together with the code (with exceptions that can be reasoned for), (2) a hard limit of 128 characters for code, YARD code comments and longer block-style code comments that are not typically read when navigating through code (3) no limit for files where editing with line wrapping enabled is preferable, such as pure Markdown. Reasons: 128 and 100 are nice numbers; Github has a 128 character line length; 128 fixed-width characters fit well on any screen >1200 px when no sidebar is shown, while 100 characters fit well on any screen >1200 px when a sidebar is visible; 100 characters for code lines is within the limits of [recommendations for major programming languages](https://en.wikipedia.org/wiki/Characters_per_line#In_programming) (Python, Android, Google Java, PHP). It is recommended to adapt the font size so that 100 and 128 characters are shown with and without a sidebar, respectively; because screen reading is mostly tedious [because of too small text](http://mikeyanderson.com/optimal_characters_per_line).

* **Two or more empty lines.** The Ruby Style Guide [recommends](https://rubystyle.guide/#two-or-more-empty-lines) "Don’t use several empty lines in a row." However, they are a nice way to add structure for fast visual navigation when scrolling, similar to how in text documents there are also different vertical gaps between chapters and between paragraphs. So this project uses two vertical lines in the following cases: (1) between two methods, classes or modules and (2) before a Markdown header, except there is a preceding header with nothing else in between.

* **Ternary Operator vs `if`.** The Ruby Style Guide [recommends](https://rubystyle.guide/#ternary-operator) to use the ternary operator `? :` rather than a single-line `if … then … else` expression. However, while the latter reads like natural language while it is not clear how to even pronounce the ternary operator. So we don't use the ternary operator at all.

* **`not`, `and`, `or`.** The Ruby Style Guide [says](https://rubystyle.guide/#bang-not-not) "Use `!` instead of `not`." But `not` is much more readable like natural language, given that it is an English word, long enough to not miss it, and separated with a space from the rest of the expression. `!` is more like a formula sign. Granted, `not` needs parentheses in some cases – so `!` is easier to write but `not` is easier to read, and that's more important because "write once, read often". The same applies to `and` and `or` in Boolean expressions, even though The Ruby Style Guide says "The and and or keywords are banned.", again just because of operator precedence. Still use a suffixed `if` or `unless` modifier expression for control flow rather than `or`.

* **Short Methods.** The Ruby Style Guide [recommends](https://rubystyle.guide/#short-methods) to "avoid methods longer than 10 LOC". That is a good rule of thumb, but it depends on what type of software one is developing. The idea is that, for good code readability, the reader should always be able to "keep the control flow of a method in the mind". So the more algorithmically complex, the shorter the methods should be, down to 5 LOC. In low-complexity software with a linear control flow, such as for data format conversion, methods up to one screenful (40 LOC incl. comments) are fine, and for the top-level linear control flow of scripts even 2-3 screenfuls.

* **Method invocation parentheses.** The Ruby Style Guide [says](https://rubystyle.guide/#method-invocation-parens) "Use parentheses around the arguments of method invocations" but also [recommends](https://rubystyle.guide/#no-dsl-decorating) to omit them for methods are part of an internal Domain Specific Language (Rails, Rake, RSpec etc.), that is, that serve declarative purposes. However, when parentheses do not inhibit reading, code reads more like natural language. So we omit them when there is only a single method call in an expression (means, no chaining or nesting).

* **The right shebang.** Executable Ruby scripts start with the shebang line `#!/usr/bin/env ruby`. That selects the first Ruby found in `$PATH` and is standard practice to make a shebang line work with multiple installed Ruby versions and Ruby version switchers like `chruby` ([see](https://stackoverflow.com/a/2792076)).


### 6.4. Documentation Style Guide

For in-code documentation, we follow The Ruby Style Guide's section "[Comments](https://rubystyle.guide/#comments)". However, while The Ruby Style Guide [is against comments](https://rubystyle.guide/#no-comments) and for self-documenting code, we are for self-documenting code *and* for comments where comments improve the code. That means, where the code becomes more readable, navigable and understandable. The idea is to write for a developer *starting* to dive into your code, and perhaps even into the language. See below for details.

* **Use Markdown where possible.** To limit the confusion around the plaintext markup languages, this project uses Markdown widely because it is the least common denominator of multiple tools it relies on:

    * Code documentor [YARD](https://yardoc.org/), when run with `--markup markdown`.
    * Code repository Github, by using [Github flavored Markdown](https://github.github.com/gfm/) for the repo's `README.md` etc..
    * Content source format AsciiDoc, by using the [Markdown Compatibility syntax](https://asciidoctor.org/docs/asciidoc-syntax-quick-reference/#markdown-compatibility) in the Asciidoctor implementation.
    * Project documentation and task list system [Dynalist](https://dynalist.io/).

    So where possible, use Markdown. For example, use YARD-style links only to link to code elements, but not to normal URLs. So instead of `{http://example.com/ Example}`, write `[Example](http://example.com/)`. There is no real alternative to Markdown – Github understands AsciiDoc markup, but YARD does not understand AsciiDoc without custom coding, and Dynalist only understands Markdown.

* **Use code comments to make code read like text.** As with the code style guide, the guiding idea is here to write code that reads almost like natural language. The redundancy introduced by comments is a minor drawback compared to that benefit. Comments are employed to assist that. Specifically: 

    * Use comments to spare the reader from jumping back and forth between many parts of the code in order to understand one section. When code can be read sequentially like an article or book, it's a good thing.

    * Use comments to document the interface of each and every method, using YARD syntax from which documentation can be generated. This is esp. necessary in dynamically typed languages like Ruby, where the code does not tell about the accepted data types. Otherwise the reader has to search for and jump to calling code to see how a method is used, or try to infer data types (which the reader should know when starting to read a method) from the method's implementation. Both goes against sequential readability of code.

    * Use comments as sub-section headers. Like books, software has sections (modules), chapters (classes) and sub-chapters (methods). But a heading level for one or more paragraphs of text is missing. Use a blank like followed by a single-line comment for that, which summarizes the 3-10 lines of code up to the next such comment. But it helps navigate code faster because reading one sentence is faster than understanding 3-10 lines of code. And aiding fast navigation is the whole point of headings. This comment is redundant to the code, but so is a heading redundant to the text.

* **Annotations keyword format.** Instead of the "`TODO: …`" format [proposed](https://rubystyle.guide/#annotate-keywords) in The Ruby Style Guide, a "`@todo …`" format is used. This is the tag format of YARD, with the intention to eventually extend YARD for collecting, listing and managing these code annotations.

* **Hash key documentation with YARD.** YARD will render the `@option` tags in a section titled "Options Hash (varname):". This is not applicable if multiple method parameters are structured hashes or if the hash is nested or if the return value is a structured hash. We use (nested) itemized lists in a way that emulates the rendered output of YARD, as follows. This is actually preferable over `@options` in all cases for consistency, and because the output is indented below the right parameter and not a separate "options hash" section. This corresponds to the fact that an options hash has always been just a normal method parameter and is falling mostly out of use due to keywork arguments now anyway. The format we use is:

    ```
    * **:keyname** (Datatype of value) *(defaults to: value)* — Option description as a full sentence.
    ```


## 7. License and Credits

**Licenses.** This repository exclusively contains material under free software licencses, open content licenses and open database licenses. Different licenses apply to different parts, as follows:

* **License for the database.** All files in folders `contents-*/`, taken together, are "the database". The database is made available under the [Open Database License v1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/1.0/). A copy of the license text is provided in [LICENSE.ODbL.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.ODbL.md). Files that are generated automatically during the build process and include content from the database are governed by the same license.

* **License for database contents.** While the database license governs the rights to the database as a whole, all individual contents of the database (as defined above) are additionally covered by the [Database Contents License v1.0 (DbCL)](https://opendatacommons.org/licenses/dbcl/1.0/). A copy of the license text is provided in [LICENSE.DbCL.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.DbCL.md). Database content in files generated automatically during the build process is governed by the same license.

* **License for all other material.** Everything in this repository that is not "database" or "database contents" as described above is considered "other material" and licensed under the MIT license. A copy of the license text is provided in [LICENSE.MIT.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.MIT.md).


**Credits.** Within the rights granted by the applicable licenses, this repository contains works of the following open source projects, authors or groups, which are hereby credited for their contributions and for holding the copyright to their contributions:

* **[Open Food Facts](https://openfoodfacts.org/).** The database in this repository contains information from [Open Food Facts](https://openfoodfacts.org/), which is made available here under the [Open Database License v1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/1.0/). Individual contents of the database are available under the [Database Contents License](https://opendatacommons.org/licenses/dbcl/1.0/). Our re-use of the Open Food Facts data is also additionally governed by the Open Food Facts [Terms of use, contribution and re-use](https://world.openfoodfacts.org/terms-of-use), specifically the sections "General terms and conditions" and "Terms and conditions for re-use".

* **[FoodKeeper App](https://www.foodsafety.gov/keep-food-safe/foodkeeper-app).** An initiative by the USDA Food Safety and Inspection Service and the United States Department of Health & Human Services, providing food safety and storage information in web and mobile app form. The distributables built from this repository can be built to include this content. As a work of the Federal Government of the United States, this content is in the public domain ([details](https://en.wikipedia.org/wiki/Copyright_status_of_works_by_the_federal_government_of_the_United_States)).

* **[IQAndreas/markdown-licenses](https://github.com/IQAndreas/markdown-licenses).** Provides orginal open source licenses in Markdown format. Some of them have been used in the `LICENSE.*.md` files in this repository. Specifically, ODbL 1.0 has been obtained from [pull request #8](https://github.com/IQAndreas/markdown-licenses/pull/8) by [scubbx](https://github.com/scubbx).
