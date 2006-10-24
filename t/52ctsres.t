#!/usr/bin/perl
# test complex type simpleContent restrictions

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 10;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<complexType name="t1">
  <simpleContent>
    <restriction base="int">
      <attribute name="a1_a" type="int" />
    </restriction>
  </simpleContent>
</complexType>

<element name="test1" type="me:t1" />

</schema>
__SCHEMA__

ok(defined $schema);

my %t1 = (_ => 11, a1_a => 13);
test_rw($schema, "test1" => <<__XML__, \%t1);
<test1 a1_a="13">11</test1>
__XML__

