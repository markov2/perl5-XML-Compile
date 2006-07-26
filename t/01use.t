#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use Test::More tests => 7;

require_ok('XML::Compile');
require_ok('XML::Compile::Schema');
require_ok('XML::Compile::Schema::Specs');
require_ok('XML::Compile::Schema::BuiltInTypes');
require_ok('XML::Compile::Schema::BuiltInStructs');
require_ok('XML::Compile::Schema::BuiltInFacets');
require_ok('XML::Compile::Schema::Translate');
