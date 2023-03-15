#!/usr/bin/env perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 33;

set_compile_defaults
    elements_qualified => 'NONE';

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<!-- all with one element -->

<element name="test0">
  <complexType>
    <sequence>
      <group ref="me:g1" />
    </sequence>
  </complexType>
</element>

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1a" type="string" />
      <group ref="me:g1" />
      <element name="t1b" type="string" />
    </sequence>
  </complexType>
</element>

<group name="g1">
  <sequence>
    <element name="g1_a" type="int" />
    <element name="g1_b" type="int" />
  </sequence>
</group>

<element name="test2">
  <complexType>
    <sequence>
      <group ref="me:g1" minOccurs="0" maxOccurs="unbounded" />
    </sequence>
  </complexType>
</element>

<group name="g3">
  <sequence />
</group>

<element name="test3">
  <complexType>
    <sequence>
      <group ref="me:g3" />
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);
my $error;

test_rw($schema, test0 => <<__XML, {g1_a => 10, g1_b => 11});
<test0><g1_a>10</g1_a><g1_b>11</g1_b></test0>
__XML


test_rw($schema, test1 => <<__XML, {g1_a => 10, g1_b => 11, t1a => 'a', t1b => 'b'});
<test1><t1a>a</t1a><g1_a>10</g1_a><g1_b>11</g1_b><t1b>b</t1b></test1>
__XML

my %g2a =
 (gr_g1 =>
    [ { g1_a => 12, g1_b => 13}
    , { g1_a => 14, g1_b => 15}
    ]
 );

test_rw($schema, test2 => <<__XML, \%g2a);
<test2>
  <g1_a>12</g1_a><g1_b>13</g1_b>
  <g1_a>14</g1_a><g1_b>15</g1_b>
</test2>
__XML

test_rw($schema, test3 => <<__XML, {});
<test3/>
__XML
