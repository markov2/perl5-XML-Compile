#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use XML::Compile::Schema;

use Test::More tests => 8;

my $TestNS   = 'http://test-types';
my $SchemaNS = 'http://www.w3.org/2001/XMLSchema';

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">
<element name="test1" type="int" />
<simpleType  name="test2">
  <restriction base="int" />
</simpleType>
<complexType name="test3">
  <sequence>
    <element name="test3_1" type="int" />
    <element name="test3_2" type="int" />
  </sequence>
</complexType>
</schema>
__SCHEMA__

ok(defined $schema);

#
# simple element type
#

my $read_t1   = $schema->compile
 ( READER => "$TestNS#test1"
 , check_values => 1
 );

ok(defined $read_t1, "reader element test1");
cmp_ok(ref($read_t1), 'eq', 'CODE');

my $t1 = $read_t1->( <<__XML__ );
<test1>42</test1>
__XML__

cmp_ok($t1, '==', 42);

#
# the simpleType, less simple type
#

my $read_t2   = $schema->compile
 ( READER => "$TestNS#test2"
 , check_values => 1
 );

ok(defined $read_t2, "reader simpleType test2");
cmp_ok(ref($read_t2), 'eq', 'CODE');

my $hash = $read_t2->( <<__XML__ );
<test2>42</test2>
__XML__

#
# The not so complex complexType
#

my $read_t3   = $schema->compile
 ( READER => "$TestNS#test3"
 , check_values => 1
 );

ok(defined $read_t3, "reader complexType test3");
cmp_ok(ref($read_t3), 'eq', 'CODE');

my $hash2 = $read_t3->( <<__XML__ );
<test3>
  <test3_1>13</test3_1>
  <test3_2>42</test3_2>
</test3>
__XML__
