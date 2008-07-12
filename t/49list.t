#!/usr/bin/perl
# simpleType list

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 57;

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

<element name="test3">
  <simpleType>
    <restriction base="me:t2">
      <enumeration value="1" />
      <enumeration value="2" />
    </restriction>
  </simpleType>
</element>

<element name="test4">
  <simpleType>
    <restriction base="NMTOKENS">
      <enumeration value="3" />
      <enumeration value="4" />
    </restriction>
  </simpleType>
</element>

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

test_rw($schema, test2 => <<__XML, [1]);
<test2>1</test2>
__XML

test_rw($schema, test2 => <<__XML, [2, 3]);
<test2>2 3</test2>
__XML

test_rw($schema, test2 => <<__XML, [4, 5, 6]);
<test2> 4
  5\t  6 </test2>
__XML

#### restriction on simple-list base

test_rw($schema, test3 => <<__XML, [1, 2, 1, 1]);
<test3>1 2 1 1</test3>
__XML


# predefined

test_rw($schema, test4 => <<__XML, [3, 4, 4, 3]);
<test4>3 4 4 3</test4>
__XML

