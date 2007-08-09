#!/usr/bin/perl
# simpleType union

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 72;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<simpleType name="t1">
  <union>
    <simpleType>
      <restriction base="int" />
    </simpleType>
    <simpleType>
      <restriction base="string">
        <enumeration value="unbounded" />
      </restriction>
    </simpleType>
  </union>
</simpleType>

<element name="test1" type="me:t1" />

<simpleType name="t2">
  <restriction base="string">
     <enumeration value="any" />
  </restriction>
</simpleType>

<simpleType name="t3">
  <union memberTypes="me:t2 int">
    <simpleType>
      <restriction base="string">
         <enumeration value="none" />
      </restriction>
    </simpleType>
  </union>
</simpleType>

<element name="test3" type="me:t3" />

</schema>
__SCHEMA__

ok(defined $schema);
my $error;

test_rw($schema, "test1" => <<__XML__, 1 );
<test1>1</test1>
__XML__

test_rw($schema, "test1" => <<__XML__, 'unbounded');
<test1>unbounded</test1>
__XML__

$error = reader_error($schema, test1 => <<__XML__);
<test1>other</test1>
__XML__
is($error, "no match for `other' in union at {http://test-types}test1#union");

$error = writer_error($schema, test1 => 'other');
is($error, "no match for `other' in union at {http://test-types}test1#union");

test_rw($schema, "test3" => <<__XML__, 1 );
<test3>1</test3>
__XML__

test_rw($schema, "test3" => <<__XML__, 'any');
<test3>any</test3>
__XML__

test_rw($schema, "test3" => <<__XML__, 'none');
<test3>none</test3>
__XML__

$error = reader_error($schema, test3 => <<__XML__);
<test3>other</test3>
__XML__
is($error, "no match for `other' in union at {http://test-types}test3#union");

$error = writer_error($schema, test3 => 'other');
is($error, "no match for `other' in union at {http://test-types}test3#union");
