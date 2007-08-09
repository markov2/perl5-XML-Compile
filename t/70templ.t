#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 5;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
       <element name="t1_a" type="int" />
       <element name="t1_b" type="int" use="optional" />
       <element name="t1_c" type="me:test2" />
       <element name="t1_d">
         <complexType>
           <sequence>
             <element name="t1_e" type="string" />
             <element name="t1_f" type="float"  />
           </sequence>
         </complexType>
       </element>
    </sequence>
  </complexType>
</element>

<complexType name="test2">
  <complexContent>
    <extension base="me:test3">
      <sequence>
        <element name="t2_a" type="int" />
      </sequence>
    </extension>
  </complexContent>
</complexType>

<complexType name="test3">
  <sequence>
    <element name="t3_a" />
    <element name="t3_b" type="me:test4" />
  </sequence>
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

templ_perl($schema, 'test1', <<__TEST1__, show => 'ALL');
test1 =>
{ # sequence of t1_a, t1_b, t1_c, t1_d
  # is a {http://www.w3.org/2001/XMLSchema}int
  t1_a => 42,

  # is a {http://www.w3.org/2001/XMLSchema}int
  t1_b => 42,
  t1_c =>
  { # sequence of t3_a, t3_b
    # is a {http://www.w3.org/2001/XMLSchema}anyType
    t3_a => "anything",

    # is a {http://www.w3.org/2001/XMLSchema}int
    # with some limits
    t3_b => 42,

    # sequence of t2_a
    # is a {http://www.w3.org/2001/XMLSchema}int
    t2_a => 42,
  },
  t1_d =>
  { # sequence of t1_e, t1_f
    # is a {http://www.w3.org/2001/XMLSchema}string
    t1_e => "example",

    # is a {http://www.w3.org/2001/XMLSchema}float
    t1_f => 3.1415,
  },
}
__TEST1__

templ_perl($schema, 'test1', <<__TEST1b__, show => 'NONE', indent => '    ');
test1 =>
{   t1_a => 42,
    t1_b => 42,
    t1_c =>
    {   t3_a => "anything",
        t3_b => 42,
        t2_a => 42,
    },
    t1_d =>
    {   t1_e => "example",
        t1_f => 3.1415,
    },
}
__TEST1b__

templ_xml($schema, 'test1', <<__TEST1c__, show => 'ALL');
<test1>
  <!--
    sequence of t1_a, t1_b, t1_c, t1_d
  -->
  <t1_a type="int">42</t1_a>
  <t1_b type="int">42</t1_b>
  <t1_c>
    <!--
      sequence of t3_a, t3_b
    -->
    <t3_a type="anyType">anything</t3_a>
    <t3_b type="int">
      <!--
        with some limits
      -->
      42
    </t3_b>
    <!--
      sequence of t2_a
    -->
    <t2_a type="int">42</t2_a>
  </t1_c>
  <t1_d>
    <!--
      sequence of t1_e, t1_f
    -->
    <t1_e type="string">example</t1_e>
    <t1_f type="float">3.1415</t1_f>
  </t1_d>
</test1>
__TEST1c__

templ_xml($schema, 'test1', <<__TEST1d__, show => 'NONE');
<test1>
  <t1_a>42</t1_a>
  <t1_b>42</t1_b>
  <t1_c>
    <t3_a>anything</t3_a>
    <t3_b>42</t3_b>
    <t2_a>42</t2_a>
  </t1_c>
  <t1_d>
    <t1_e>example</t1_e>
    <t1_f>3.1415</t1_f>
  </t1_d>
</test1>
__TEST1d__
