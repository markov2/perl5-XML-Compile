#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 21 + ($skip_dumper ? 0 : 18);

my $TestNS2 = "http://second-ns";

my $schema  = XML::Compile::Schema->new( <<__SCHEMA__ );
<schemas>

<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1" type="me:c1" />
<complexType name="c1">
  <sequence>
     <element name="e1_a" type="int" />
     <element name="e1_b" type="int" />
  </sequence>
  <attribute name="a1_a" type="int" />
</complexType>

<group name="g2">
  <sequence>
     <element name="g2_a" type="int" />
     <element name="g2_b" type="int" />
  </sequence>
</group>

<element name="test2">
  <complexType>
    <sequence>
      <element name="e2_a" type="int" />
      <group ref="me:g2" />
      <element name="e2_b" type="int" />
    </sequence>
  </complexType>
</element>
</schema>

<schema targetNamespace="$TestNS2"
        xmlns="$SchemaNS"
        xmlns:first="$TestNS">

<element name="test3">
  <complexType>
    <sequence>
      <element ref="first:test1" />
    </sequence>
  </complexType>
</element>

</schema>

</schemas>
__SCHEMA__

ok(defined $schema);

#
# element as reference to an element
#

ok(1, "** Testing element ref ");

my %r1_a = (a1_a => 10, e1_a => 11, e1_b => 12);
test_rw($schema, "{$TestNS2}test3" => <<__XML__, {test1 => \%r1_a});
<test3><test1 a1_a="10"><e1_a>11</e1_a><e1_b>12</e1_b></test1></test3>
__XML__

#
# element groups
#

ok(1, "** Testing element group ");

my %r2_a = (e2_a => 20, g2_a => 22, g2_b => 23, e2_b => 21);
test_rw($schema, test2 => <<__XML__, \%r2_a);
<test2>
  <e2_a>20</e2_a>
  <g2_a>22</g2_a>
  <g2_b>23</g2_b>
  <e2_b>21</e2_b>
</test2>
__XML__
