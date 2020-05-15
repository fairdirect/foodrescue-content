# Food Rescue Content


**Table of Contents**

**[1. Overview](#1-overview)**  
**[2. Repository Structure](#2-repository-structure)**  
**[3. Installation](#3-installation)**  
**[4. Usage](#4-usage)**  
**[5. Development Guide](#5-development-guide)**  
**[6. License and Credits](#6-license-and-credits)**

------


## 1. Overview

This repository contains open knowledge about rescueing expired or otherwise tarnished food, and scripts to convert and package this knowledge. The dataset is made for the open source [Food Rescue App](https://fairdirect.org/food-rescue-app).

In addition, the following re-usable pieces of this repository will be interesting to Open Food Facts developers:

* **Scripts to import Open Food Facts CSV to SQLite.** See `scripts/frc-import-*.rb`. Only a few fields are imported right now (GTIN / barcode, category, countries, category taxonomy) but this can be extended easily. The result is a fully normalized and storage space optimized SQLite database. Previous solutions are [PostgreSQL import instructions](https://blog-postgresql.verite.pro/2018/12/21/import-openfoodfacts.html) and [a minimal SQLite import script](https://github.com/benhamner/open-food-facts). Both result in one single table, structured like the CSV file. By contrast, the scripts provided here result in a fully normalized table structure. For potential new tools, check the Open Food Facts wiki page "[Reusing Open Food Facts Data](https://wiki.openfoodfacts.org/Reusing_Open_Food_Facts_Data)".

* **Script to filter the Open Food Facts CSV file.** See `scripts/frc-filter-products-csv.rb`. In most cases you'll be better off and faster done using [`csvkit`](https://csvkit.readthedocs.io/), though.


## 2. Repository Structure

**A self-contained repository.** Source code is everything to reliably build the outputs. External libraries can be omitted as long as they can be reliably obtained on demand in the required version. The latter is difficult for datasets. For example, the Open Food Facts dataset utilized here does not come in versioned releases. So to make build outputs reproducible and allow error isolation, relevant subsets of the Open Food Facts dataset are included in this repository. That data is not compressed, allowing for space-efficiently handling of revisions by Git.

**Files and folders.**

[TODO]


## 3. Installation

This is a set of Ruby scripts requiring Ruby 2.7 or higher (but only because `Enumerable#filter_map` is used in a few places). Assuming a Debian-esque Linux, Ruby 2.7 and `bundler` are available system-wide, you could just install everything with:

```
sudo apt install sqlite3 libsqlite3-dev
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

    * This will install `bundler` to `~/.gem/ruby/2.3.7/`. This is probably needed, as installing gems into a gem bundle is only possible with bundler. However, it might be better to install bundler system-wide.
    * This only works when `chruby` shows that a Ruby is active. Otherwise you get "ERROR: Could not find a valid gem 'bundler' (>= 0) in any repository".

    ```
    gem install bundler
    ```

6. **Install the gemset.** In the repos's directory, execute:

    ```
    sudo apt install sqlite3 libsqlite3-dev
    bundle install
    ```


## 4. Usage

To generating the food rescue content in the format expected by the Food Rescue App, just run:

```
make
```

[TODO: The Makefile based build process still has to be implemented.]


## 5. Development Guide

Each script in `scripts/` contains its own usage instructions, which you'll see when executing it with `--help`, such as `frc-import-products-csv.rb --help`.

The different import scripts need to run in a certain order because each will rely on SQLite tables created by a previous one:

1. `frc-import-categories-txt.rb`
2. `frc-import-categories-json.rb` (optional)
3. `frc-import-products-csv.rb`

The easiest is to adapt your own build process based on the existing `Makefile`.

**Guiding principles used in the code:**

* **Object-relational mapping scheme.** The data of database records and application logic related to it is placed into classes created like in Rails ActiveRecord: one class per table, one object per database record, one attribute per column, and lazy loading of connected records from other tables via instance methods. Small tables can be exceptions from the "one class per table" rule. For example, topic author data is also handled by class FoodRescueTopic. Objects delegate behavior related to storing to and loading from the database to a single class FoodRescueDatabase, so that the storage backend can be exchanged easily. All SQLite3 queries are contained within class FoodRescueDatabase.

* **Classes for database tables should use SQLite3 compatible data types for attributes.** All values in SQLite3 are of the storage classes NULL, INTEGER, REAL, TEXT, BLOB ([see](https://www.sqlite.org/datatype3.html)). To avoid useless conversions, attributes in classes representing database tables should use values of the equivalent Ruby data types Nil, Integer, Real and String. The task of these classes is being a database interface, so there is no use for higher-level datatypes in them – for example, no need for FoodRescueTopic#edition to be of type Date when it is saved as storage class TEXT in the database anyway. The exception are attributes where additional semantics are needed for transformations during the object lifetime; for example, Ox::Element to represent DocBook XML in the main text content of FoodRescueTopic.

* **Hashes as lightweight objects.** The SQLite3 interface returns database records as hashes, keyed by fieldname. This data structure is used as a lightweight representation where structured data is needed as for Ruby objects, but without attached behavior, so not requiring a custom class. These objects can be aggregated in arrays or in hashes keyed by database ID. In the latter case, the hashes representing the database records should still have their ID hash key inside in addition, to keep up a uniform interface.

* **Database IDs as even more lightweight objects.** The database ID of an object, as a string, can be used as an even lighter way to represent objects, namely where only a reference is needed and not the data about the object. These can be aggregated in arrays.

* **Data type for DocBook XML content.** `Ox::Document` is meant to store collections of XML elements (inside its `#nodes` array), without being an element itself or rendering to visible XML output. See: `Ox.dump(Ox::Document.new) => "\n"`. So this is used to hand over collections of XML elements, even if this does not represent a fully features XML element. It's cleaner than using the data structure of the `#nodes` arrays directly, which would be `Array<Ox::Element|String>`).


## 6. License and Credits

**Licenses.** This repository exclusively contains material under free software licencses, open content licenses and open database licenses. Different licenses apply to different parts, as follows:

* **License for the database.** All files in folders `contents-*/`, taken together, are "the database". The database is made available under the [Open Database License v1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/1.0/). A copy of the license text is provided in [LICENSE.ODbL.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.ODbL.md). Files that are generated automatically during the build process and include content from the database are governed by the same license.

* **License for database contents.** While the database license governs the rights to the database as a whole, all individual contents of the database (as defined above) are additionally covered by the [Database Contents License v1.0 (DbCL)](https://opendatacommons.org/licenses/dbcl/1.0/). A copy of the license text is provided in [LICENSE.DbCL.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.DbCL.md). Database content in files generated automatically during the build process is governed by the same license.

* **License for all other material.** Everything in this repository that is not "database" or "database contents" as described above is considered "other material" and licensed under the MIT license. A copy of the license text is provided in [LICENSE.MIT.md](https://github.com/fairdirect/foodrescue-content/blob/master/LICENSE.MIT.md).


**Credits.** Within the rights granted by the applicable licenses, this repository contains works of the following open source projects, authors or groups, which are hereby credited for their contributions and for holding the copyright to their contributions:

* **[Open Food Facts](https://openfoodfacts.org/).** The database in this repository contains information from [Open Food Facts](https://openfoodfacts.org/), which is made available here under the [Open Database License v1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/1.0/). Individual contents of the database are available under the [Database Contents License](https://opendatacommons.org/licenses/dbcl/1.0/). Our re-use of the Open Food Facts data is also additionally governed by the Open Food Facts [Terms of use, contribution and re-use](https://world.openfoodfacts.org/terms-of-use), specifically the sections "General terms and conditions" and "Terms and conditions for re-use".

* **[FoodKeeper App](https://www.foodsafety.gov/keep-food-safe/foodkeeper-app).** An initiative by the USDA Food Safety and Inspection Service and the United States Department of Health & Human Services, providing food safety and storage information in web and mobile app form. The distributables built from this repository can be built to include this content. As a work of the Federal Government of the United States, this content is in the public domain ([details](https://en.wikipedia.org/wiki/Copyright_status_of_works_by_the_federal_government_of_the_United_States)).

* **[IQAndreas/markdown-licenses](https://github.com/IQAndreas/markdown-licenses).** Provides orginal open source licenses in Markdown format. Some of them have been used in the `LICENSE.*.md` files in this repository. Specifically, ODbL 1.0 has been obtained from [pull request #8](https://github.com/IQAndreas/markdown-licenses/pull/8) by [scubbx](https://github.com/scubbx).
