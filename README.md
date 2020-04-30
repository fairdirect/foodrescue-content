# Food Rescue Content


## Contents

**[1. Overview](#1-overview)**  
**[2. Repository Structure](2-repository-structure)**  
**[3. Installation](3-installation)**  
**[4. Usage](4-usage)**  
**[5. Development Guide](5-development-guide)**  
**[6. License](6-license)**


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


## 6. License

License differs between files of different origins, as follows:

[TODO]
