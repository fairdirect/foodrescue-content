# foodrescue-content

Knowledge about rescuing edible food, in both human readable and machine readable form.


## Contents

[TODO]


## 1. Overview

The repository contains all data that is needed to build its outputs. Because that is properly its "source code", even though much of this data is just a download from the Open Food Facts database. The exception is the Open Food Facts products CSV file, which is contained here with only the `code` (EAN / GTIN code) and `categories` columns present. It is not compressed, as that allows space-efficiently adding to the file from daily CSV update files published by Open Food Facts.


## 2. Installation

This is a set of simple Ruby scripts without special requirements about the Ruby version. So assuming you have Ruby and `bundler` available system-wide, you could just install everything with:

```
sudo apt install sqlite3 libsqlite3-dev
bundle install
```

However, for server environments and also to separate your various Ruby projects, it is often preferable to install multiple rubies in parallel and switch between them. Here is a setup like that for Ubuntu 19.10:

1. Install `ruby-install`.

    ```
    sudo apt update
    sudo apt install build-essential
    cd ~/some-temp-dir/
    wget -O ruby-install-0.7.0.tar.gz https://github.com/postmodern/ruby-install/archive/v0.7.0.tar.gz
    tar -xzvf ruby-install-0.7.0.tar.gz
    cd ruby-install-0.7.0/
    sudo checkinstall make install
    ```

2. Install Ruby:

    ```
    ruby-install ruby 2.7.1
    ```

3. Install and configure `chruby`.

    ```
    https://github.com/postmodern/chruby
    cd ~/Software/UbuntuLinux/
    wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz
    cd chruby-0.3.9/
    sudo checkinstall make install

    # Add the lines to load chruby to your `~/.bashrc`:
    cat >> ~/.$(basename $SHELL)rc <<EOF 
    # Load chruby, a tool to switch between Ruby versions. 
    source /usr/local/share/chruby/chruby.sh 
    source /usr/local/share/chruby/auto.sh 
    EOF
    
    # Reload the shell (or open a new tab).
    exec $SHELL
    ```

4. Test `chruby`:

    1. Execute `chruby`. It should show available rubies.
    2. Execute `chruby` in the repo's directory. It should show that Ruby 2.7.1 is selected now, due to the auto-switching mechanism using the `.ruby-version` file in this repository. Whenever you change `.ruby-version`, you need to re-login or `exec $SHELL` again for the changes to be picked up.

5. Install `bundler`. Notes:

    * This will install `bundler` to ~/.gem/ruby/2.3.7/ . This is probably needed, as installing gems into a gem bundle is only possible with bundler. However, it might be better to install bundler system-wide.
    * This only works when chruby shows that a Ruby is active. Otherwise: "ERROR:  Could not find a valid gem 'bundler' (>= 0) in any repository".

    ```
    gem install bundler
    ```

6. Install the gemset. In the repos's directory, execute:

    ```
    sudo apt install sqlite3 libsqlite3-dev
    bundle install
    ```


## 3. Usage

[TODO]


## 4. License

[TODO]
