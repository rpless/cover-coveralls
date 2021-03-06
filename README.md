# Cover Coveralls
[![Build Status](https://travis-ci.org/rpless/cover-coveralls.svg)](https://travis-ci.org/rpless/cover-coveralls)
[![Coverage Status](https://coveralls.io/repos/rpless/cover-coveralls/badge.svg?branch=master&service=github)](https://coveralls.io/github/rpless/cover-coveralls?branch=master)

Adds [Coveralls](https://coveralls.io/) support to [Cover](https://github.com/florence/cover).
This plugin generates a Coveralls coverage json file and then sends it to Coveralls.

*Note*: This library currently has a dependency on bash and cURL.

## Use with TravisCI

If your code is hosted on a public github repo then you can use this plugin in conjunction with [TravisCI](https://travis-ci.org/).
Just enable your repository on both services, add `cover-coveralls` to the `build-deps` of your `info.rkt` and then add a `.travis.yml` file to your repo with the following contents:
```yml
langauge: c
sudo: false
env:
  global:
    - RACKET_DIR=~/racket
  matrix:
    - RACKET_VERSION=6.2 # Set this to the version of racket you use

before_install: # Install Racket
  - git clone https://github.com/greghendershott/travis-racket.git ../travis-racket
  - cat ../travis-racket/install-racket.sh | bash
  - export PATH="${RACKET_DIR}/bin:${PATH}"

install: raco pkg install --deps search-auto $TRAVIS_BUILD_DIR # install dependencies

script:
  - raco test $TRAVIS_BUILD_DIR # run tests. you wrote tests, right?

after_success:
  - raco cover -f coveralls -d $TRAVIS_BUILD_DIR/coverage . # generate coverage information for coveralls
```
The above Travis configuration will install any project dependencies, test your project, and report coverage information to coveralls.

If you want a failure to upload to Coveralls, move the `raco cover -f coveralls -d $TRAVIS_BUILD_DIR/coverage .` into the `script` section.

For additional Travis configuration information look at [Travis Racket](https://github.com/greghendershott/travis-racket).

Note: This currently only works for public Github repos. This project does not support `coveralls.yml` configurations for private repos.
