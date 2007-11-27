#!/usr/bin/perl
# check access to old schema types

use warnings;
use strict;

use File::Spec;

use lib 'lib', 't';
use XML::Compile::Schema;
use TestTools;

use Test::More tests => 10;

my $oldns  = 'http://www.w3.org/2000/10/XMLSchema';

my $schema = XML::Compile::Schema->new( <<__SCHEMA );
<schema xmlns="$oldns" targetNamespace="$TestNS"
   xmlns:x="$TestNS">

<element name="test1" type="int" />

</schema>
__SCHEMA
ok(defined $schema);

test_rw($schema, test1 => '<test1>42</test1>', 42);