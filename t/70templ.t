#!/usr/bin/env perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More    tests => 7;
use Test::Deep    qw/cmp_deeply/;

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

<element name="test3" type="me:test3" />
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

my $out = templ_perl($schema, "{$TestNS}test1", show => 'ALL', skip_header => 1);
is($out, <<__TEST1__);
# Describing complex x0:test1
#     {http://test-types}test1

# is an unnamed complex
{ # sequence of t1_a, t1_b, t1_c, t1_d, cho_t1_g

  # is a xs:int
  t1_a => 42,

  # is a xs:int
  t1_b => 42,

  # is a x0:test2
  # occurs 1 <= # <= 2 times
  t1_c =>
  [ { # sequence of t3_a, t3_b

      # is a xs:anyType
      t3_a => "anything",

      # is a xs:int
      # value < 77
      # value >= 12
      t3_b => 42,

      # sequence of t2_a

      # is a xs:int
      t2_a => 42,

      # is a xs:int
      a3_a => 42,

      # is a xs:int
      a2_a => 42,

      # is a xs:string
      # attribute a2_b is required
      a2_b => "example", }, ],

  # is an unnamed complex
  t1_d =>
  { # sequence of t1_e, t1_f

    # is a xs:string
    t1_e => "example",

    # is a xs:float
    # occurs 1 <= # <= 2 times
    t1_f => [ 3.1415, ], },

  # choice of t1_g, t1_h, t1_i
  # occurs 1 <= # <= 3 times
  cho_t1_g => 
  [ {
      # is a x0:test3
      t1_g =>
      { # sequence of t3_a, t3_b

        # is a xs:anyType
        t3_a => "anything",

        # is a xs:int
        # value < 77
        # value >= 12
        t3_b => 42,

        # is a xs:int
        a3_a => 42, },

      # is a xs:int
      # is optional
      t1_h => 42,

      # is a xs:negativeInteger
      # occurs 1 <= # <= unbounded times
      t1_i => [ -1, ], },
  ], }
__TEST1__

$out = templ_perl($schema, "{$TestNS}test1", show => 'NONE', indent => '    ', skip_header => 1);
is($out, <<__TEST1b__);
# Describing complex x0:test1
#     {http://test-types}test1

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
        t1_f => [ 3.1415, ], },

    cho_t1_g => 
    [ {   t1_g =>
          {   t3_a => "anything",
              t3_b => 42,
              a3_a => 42, },

          t1_h => 42,
          t1_i => [ -1, ], },
    ], }
__TEST1b__

$out = templ_xml($schema, "{$TestNS}test1", show => 'ALL', skip_header => 1
 , use_default_namespace => 1, include_namespaces => 1);

is($out, <<__TEST1c__);
<test1 xmlns="http://test-types" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="x0:unnamed complex">
  <!-- sequence of t1_a, t1_b, t1_c, t1_d, cho_t1_g -->
  <t1_a xsi:type="xs:int">42</t1_a>
  <t1_b xsi:type="xs:int">42</t1_b>
  <t1_c xsi:type="test2">
    <!-- occurs 1 <= # <= 2 times -->
    <!-- sequence of t3_a, t3_b -->
    <t3_a xsi:type="xs:anyType">anything</t3_a>
    <t3_b xsi:type="xs:int">
      <!-- value < 77
           value >= 12 -->
      42
    </t3_b>
    <!-- sequence of t2_a -->
    <t2_a xsi:type="xs:int">42</t2_a>
    <a3_a xsi:type="xs:int">42</a3_a>
    <a2_a xsi:type="xs:int">42</a2_a>
    <a2_b xsi:type="xs:string">
      <!-- attribute x0:a2_b is required -->
      example
    </a2_b>
  </t1_c>
  <t1_d xsi:type="x0:unnamed complex">
    <!-- sequence of t1_e, t1_f -->
    <t1_e xsi:type="xs:string">example</t1_e>
    <t1_f xsi:type="xs:float">
      <!-- occurs 1 <= # <= 2 times -->
      3.1415
    </t1_f>
  </t1_d>
  <!-- choice of t1_g, t1_h, t1_i
       occurs 1 <= # <= 3 times -->
  <t1_g xsi:type="test3">
    <!-- sequence of t3_a, t3_b -->
    <t3_a xsi:type="xs:anyType">anything</t3_a>
    <t3_b xsi:type="xs:int">
      <!-- value < 77
           value >= 12 -->
      42
    </t3_b>
    <a3_a xsi:type="xs:int">42</a3_a>
  </t1_g>
  <t1_h xsi:type="xs:int">
    <!-- is optional -->
    42
  </t1_h>
  <t1_i xsi:type="xs:negativeInteger">
    <!-- occurs 1 <= # <= unbounded times -->
    -1
  </t1_i>
</test1>
__TEST1c__

$out = templ_xml($schema, "{$TestNS}test1", show => 'NONE', skip_header => 1
 , use_default_namespace => 1, include_namespaces => 1);
is($out, <<__TEST1d__);
<test1 xmlns="http://test-types">
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

$out = templ_perl($schema, "{$TestNS}test3", show => 'ALL', skip_header => 1
 , key_rewrite => 'PREFIXED', include_namespaces => 1
 , prefixes => [ 'me' => $TestNS ], elements_qualified => 'ALL');
is($out, <<__TEST3__);
# Describing complex me:test3
#     {http://test-types}test3
# xmlns:me        http://test-types

# is a me:test3
{ # sequence of me_t3_a, me_t3_b

  # is a xs:anyType
  me_t3_a => "anything",

  # is a xs:int
  # value < 77
  # value >= 12
  me_t3_b => 42,

  # is a xs:int
  a3_a => 42, }
__TEST3__

my $tree = templ_tree($schema, "{$TestNS}test3");
#use Data::Dumper;
#$Data::Dumper::Indent    = 1;
#$Data::Dumper::Quotekeys = 0;
#warn Dumper $tree;
isa_ok($tree, 'HASH');
