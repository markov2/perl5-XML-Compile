#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 5;

set_compile_defaults
    elements_qualified => 'NONE';

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
       <element name="t1_a" type="int" />
       <element name="t1_b" type="int" />
       <element name="t1_c" type="me:test2" maxOccurs="2" />
       <element name="t1_d">
         <complexType>
           <sequence>
             <element name="t1_e" type="string" />
             <element name="t1_f" type="float" maxOccurs="2" />
           </sequence>
         </complexType>
       </element>
       <choice maxOccurs="3">
         <element name="t1_g" type="me:test3" />
         <element name="t1_h" type="int" minOccurs="0" />
         <element name="t1_i" type="negativeInteger" maxOccurs="unbounded" />
       </choice>
    </sequence>
  </complexType>
</element>

<complexType name="test2">
  <complexContent>
    <extension base="me:test3">
      <sequence>
        <element name="t2_a" type="int" />
      </sequence>
      <attribute name="a2_a" type="int" />
      <attribute name="a2_b" type="string" use="required" />
    </extension>
  </complexContent>
</complexType>

<complexType name="test3">
  <sequence>
    <element name="t3_a" />
    <element name="t3_b" type="me:test4" />
  </sequence>
  <attribute name="a3_a" type="int" />
</complexType>

<simpleType name="test4">
  <restriction base="int">
    <minInclusive value="12" />
    <maxExclusive value="77" />
  </restriction>
</simpleType>

</schema>
__SCHEMA__

ok(defined $schema);

my $out = templ_perl($schema, "{$TestNS}test1", show => 'ALL');
is($out, <<__TEST1__);
{ # sequence of t1_a, t1_b, t1_c, t1_d, cho_t1_g

  # is a {http://www.w3.org/2001/XMLSchema}int
  t1_a => 42,

  # is a {http://www.w3.org/2001/XMLSchema}int
  t1_b => 42,

  # occurs 1 <= # <= 2 times
  t1_c =>
  [ { # sequence of t3_a, t3_b

      # is a {http://www.w3.org/2001/XMLSchema}anyType
      t3_a => "anything",

      # is a {http://www.w3.org/2001/XMLSchema}int
      # with some value restrictions
      t3_b => 42,

      # sequence of t2_a

      # is a {http://www.w3.org/2001/XMLSchema}int
      t2_a => 42,

      # is a {http://www.w3.org/2001/XMLSchema}int
      a3_a => 42,

      # is a {http://www.w3.org/2001/XMLSchema}int
      a2_a => 42,

      # is a {http://www.w3.org/2001/XMLSchema}string
      a2_b => "example", }, ],
  t1_d =>
  { # sequence of t1_e, t1_f

    # is a {http://www.w3.org/2001/XMLSchema}string
    t1_e => "example",

    # is a {http://www.w3.org/2001/XMLSchema}float
    # occurs 1 <= # <= 2 times
    t1_f =>  [ 3.1415, ], },

  # choice of t1_g, t1_h, t1_i
  # occurs 1 <= # <= 3 times
  cho_t1_g => 
  [ { t1_g =>
      { # sequence of t3_a, t3_b

        # is a {http://www.w3.org/2001/XMLSchema}anyType
        t3_a => "anything",

        # is a {http://www.w3.org/2001/XMLSchema}int
        # with some value restrictions
        t3_b => 42,

        # is a {http://www.w3.org/2001/XMLSchema}int
        a3_a => 42, },

      # is a {http://www.w3.org/2001/XMLSchema}int
      # is optional
      t1_h => 42,

      # is a {http://www.w3.org/2001/XMLSchema}negativeInteger
      # occurs 1 <= # <= unbounded times
      t1_i =>  [ -1, ], },
  ], }
__TEST1__

$out = templ_perl($schema, "{$TestNS}test1", show => 'NONE', indent => '    ');
is($out, <<__TEST1b__);
{   t1_a => 42,
    t1_b => 42,
    t1_c =>
    [ {   t3_a => "anything",
          t3_b => 42,
          t2_a => 42,
          a3_a => 42,
          a2_a => 42,
          a2_b => "example", }, ],
    t1_d =>
    {   t1_e => "example",
        t1_f =>  [ 3.1415, ], },
    cho_t1_g => 
    [ {   t1_g =>
          {   t3_a => "anything",
              t3_b => 42,
              a3_a => 42, },
          t1_h => 42,
          t1_i =>  [ -1, ], },
    ], }
__TEST1b__

$out = templ_xml($schema, "{$TestNS}test1", show => 'ALL');
is($out, <<__TEST1c__);
<test1>
  <!-- sequence of t1_a, t1_b, t1_c, t1_d, cho_t1_g -->
  <t1_a type="int">42</t1_a>
  <t1_b type="int">42</t1_b>
  <t1_c>
    <!-- occurs 1 <= # <= 2 times -->
    <!-- sequence of t3_a, t3_b -->
    <t3_a type="anyType">anything</t3_a>
    <t3_b type="int">
      <!-- with some value restrictions -->
      42
    </t3_b>
    <!-- sequence of t2_a -->
    <t2_a type="int">42</t2_a>
    <a3_a type="int">42</a3_a>
    <a2_a type="int">42</a2_a>
    <a2_b type="string">example</a2_b>
  </t1_c>
  <t1_d>
    <!-- sequence of t1_e, t1_f -->
    <t1_e type="string">example</t1_e>
    <t1_f type="float">
      <!-- occurs 1 <= # <= 2 times -->
      3.1415
    </t1_f>
  </t1_d>
  <!-- choice of t1_g, t1_h, t1_i
       occurs 1 <= # <= 3 times -->
  <t1_g>
    <!-- sequence of t3_a, t3_b -->
    <t3_a type="anyType">anything</t3_a>
    <t3_b type="int">
      <!-- with some value restrictions -->
      42
    </t3_b>
    <a3_a type="int">42</a3_a>
  </t1_g>
  <t1_h type="int">
    <!-- is optional -->
    42
  </t1_h>
  <t1_i type="negativeInteger">
    <!-- occurs 1 <= # <= unbounded times -->
    -1
  </t1_i>
</test1>
__TEST1c__

$out = templ_xml($schema, "{$TestNS}test1", show => 'NONE');
is($out, <<__TEST1d__);
<test1>
  <t1_a>42</t1_a>
  <t1_b>42</t1_b>
  <t1_c>
    <t3_a>anything</t3_a>
    <t3_b>42</t3_b>
    <t2_a>42</t2_a>
    <a3_a>42</a3_a>
    <a2_a>42</a2_a>
    <a2_b>example</a2_b>
  </t1_c>
  <t1_d>
    <t1_e>example</t1_e>
    <t1_f>3.1415</t1_f>
  </t1_d>
  <t1_g>
    <t3_a>anything</t3_a>
    <t3_b>42</t3_b>
    <a3_a>42</a3_a>
  </t1_g>
  <t1_h>42</t1_h>
  <t1_i>-1</t1_i>
</test1>
__TEST1d__
