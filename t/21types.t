#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 55;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1" type="int" />
<element name="test2" type="boolean" />

</schema>
__SCHEMA__

ok(defined $schema);

###
### int
###

test_rw($schema, test1 => '<test1>0</test1>', 0); 
test_rw($schema, test1 => '<test1>3</test1>', 3); 

###
### Boolean
###

test_rw($schema, test2 => '<test2>0</test2>', 0); 
test_rw($schema, test2 => '<test2>false</test2>', 0
  , '<test2>false</test2>', 'false'); 

test_rw($schema, test2 => '<test2>1</test2>', 1); 
test_rw($schema, test2 => '<test2>true</test2>', 1
  , '<test2>true</test2>', 'true'); 
