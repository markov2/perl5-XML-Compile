#!/usr/bin/perl
# simpleType list

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 43;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<simpleType name="t1">
  <list itemType="int" />
</simpleType>

<element name="test1" type="me:t1" />

<simpleType name="t2">
  <list>
    <simpleType>
      <restriction base="int" />
    </simpleType>
  </list>
</simpleType>

<element name="test2" type="me:t2" />

</schema>
__SCHEMA

ok(defined $schema);

test_rw($schema, "test1" => <<__XML, [1]);
<test1>1</test1>
__XML

test_rw($schema, "test1" => <<__XML, [2, 3]);
<test1>2 3</test1>
__XML

test_rw($schema, "test1" => <<__XML, [4, 5, 6]);
<test1> 4
  5\t  6 </test1>
__XML

test_rw($schema, "test2" => <<__XML, [1]);
<test2>1</test2>
__XML

test_rw($schema, "test2" => <<__XML, [2, 3]);
<test2>2 3</test2>
__XML

test_rw($schema, "test2" => <<__XML, [4, 5, 6]);
<test2> 4
  5\t  6 </test2>
__XML
