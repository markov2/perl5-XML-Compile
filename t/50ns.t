#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 49;

my $NS2 = "http://test2/ns";

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<wsdl>

<xs:schema targetNamespace="$TestNS"
        xmlns:xs="$SchemaNS"
        xmlns:me="$TestNS">

<!-- sequence with one element -->

<xs:element name="test1" type="xs:int" />

<xs:complexType name="ct1">
  <xs:sequence>
    <xs:element name="c1_a" type="xs:int" />
  </xs:sequence>
  <xs:attribute name="a1_a" type="xs:int" />
</xs:complexType>

<xs:element name="test2" type="me:ct1" />

</xs:schema>

<schema
 targetNamespace="$NS2"
 xmlns="$SchemaNS"
 xmlns:that="$TestNS">

<element name="test3" type="that:ct1" />

<element name="test4">
  <complexType>
    <complexContent>
      <extension base="that:ct1">
        <sequence>
          <element name="c4_a" type="int" />
        </sequence>
        <attribute name="a4_a" type="int" />
      </extension>
    </complexContent>
  </complexType>
</element>

</schema>

</wsdl>
__SCHEMA__

ok(defined $schema);

is(join("\n", join "\n", $schema->types)."\n", <<__TYPES__);
{http://test-types}ct1
__TYPES__

is(join("\n", join "\n", $schema->elements)."\n", <<__ELEMS__);
{http://test-types}test1
{http://test-types}test2
{http://test2/ns}test3
{http://test2/ns}test4
__ELEMS__

@run_opts =
 ( elements_qualified   => 1
 , attributes_qualified => 1
 );

#
# simple name-space on schema
#

ok(1, "** Testing simple namespace");

test_rw($schema, test1 => <<__XML__, 10);
<test1 xmlns="$TestNS">10</test1>
__XML__

test_rw($schema, "test2" => <<__XML__, {c1_a => 11});
<test2 xmlns="$TestNS"><c1_a>11</c1_a></test2>
__XML__

test_rw($schema, "{$NS2}test3" => <<__XML__, {c1_a => 12, a1_a => 13});
<test3 xmlns="$NS2" xmlns:x0="$TestNS" x0:a1_a="13">
   <x0:c1_a>12</x0:c1_a>
</test3>
__XML__

my %t4 = (c1_a => 14, a1_a => 15, c4_a => 16, a4_a => 17);
test_rw($schema, "{$NS2}test4" => <<__XML__, \%t4);
<test4 xmlns="$NS2"
       a1_a="15"
       a4_a="17">
   <c1_a>14</c1_a>
   <c4_a>16</c4_a>
</test4>
__XML__

# now with name-spaces off

@run_opts =
 ( ignore_namespaces => 1
 );

test_rw($schema, "{$NS2}test3" => <<__XML__, {c1_a => 18});
<test3>
   <c1_a>18</c1_a>
</test3>
__XML__

splice @run_opts, -2;
