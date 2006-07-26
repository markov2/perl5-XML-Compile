#!/usr/bin/perl
# test complex type extensions

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
  <complexContent>
    <sequence>
      <element name="t1_a" type="int" />
      <element name="t1_b" type="int" />
    </sequence>
  </complexContent>
  <attribute name="a1_a" type="int" />
  <attribute name="a1_b" type="int" use="required" />
</complexType>

<complexType name="t2">
  <complexContent>
    <extension base="me:t1">
       <element name="t2_a" type="int" />
    </extension>
  </complexContent>
  <attribute name="a2_a" type="int" />
</complexType>

<element name="test1" type="me:t2" />

</schema>
__SCHEMA__

ok(defined $schema);

my %t1 = (t1_a => 11, t1_b => 12, a1_a => 13, a1_b => 14, t2_a => 15, a2_a=>16);
run_test($schema, "test1" => <<__XML__, \%t1);
<test1 a1_a="13" a1_b="14" a2_a="16">
   <t1_a>11</t1_a>
   <t1_b>12</t1_b>
   <t2_a>15</t2_a>
</test1>
__XML__

