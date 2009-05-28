#!/usr/bin/perl
# test the handling of xsi:type

use warnings;
use strict;

use lib 'lib', 't';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More
   skip_all => "xsi:type not yet supported";

use Test::More tests => 3;
use Log::Report mode => 3;

set_compile_defaults
    elements_qualified => 'NONE';

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );

<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<complexType name="f_t1">
  <attribute name="f_a1" type="int"/>
</complexType>

<complexType name="f_t2">
  <complexContent>
    <extension base="me:f_t1">
      <sequence>
        <element name="f_a2" type="int"/>
      </sequence>
    </extension>
  </complexContent>
</complexType>

<element name="f_test">
  <complexType>
    <sequence>
      <element name="f_a3" type="me:f_t1" minOccurs="0" maxOccurs="unbounded"/>
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

test_rw($schema, "f_test" => <<__XML, {f_a2 => 4, f_a1 => 18});
<f_test>
    <f_a3 type="f_t2" f_a1="18">
        <f_a2>4</f_a2>
    </f_a3>
</f_test>
__XML
