#!/usr/bin/perl
# test the handling of xsi:type

use warnings;
use strict;

use lib 'lib', 't';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;
use XML::Compile::Util 'SCHEMA2001i';
my $schema2001i = SCHEMA2001i;

use Test::More tests => 10;
#use Log::Report mode => 3;

my %xsi_types = ("{$TestNS}f_t1" => [ "{$TestNS}f_t2" ] );

set_compile_defaults
    include_namespaces => 1
  , xsi_type => \%xsi_types;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );

<schema
    targetNamespace="$TestNS"
    xmlns="$SchemaNS"
    xmlns:me="$TestNS"
    elementFormDefault="qualified"
>

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

my %f1 = (f_a3 =>
  [ { XSI_TYPE => "{$TestNS}f_t2"
    , f_a1 => 18,
    , f_a2 => 4
    }
  , { XSI_TYPE => "{$TestNS}f_t1"
    , f_a1 => 19
    }
  ] );

test_rw($schema, "f_test" => <<__XML, \%f1);
<f_test xmlns="$TestNS" xmlns:xsi="$schema2001i">
    <f_a3  f_a1="18" xsi:type="f_t2">
        <f_a2>4</f_a2>
    </f_a3>
    <f_a3 f_a1="19" xsi:type="f_t1"/>
</f_test>
__XML

my $out = templ_perl $schema, "{$TestNS}f_test"
  , xsi_type => \%xsi_types, skip_header => 1;
is($out, <<'__TEMPL');
# Describing complex {http://test-types}f_test

{ # sequence of f_a3

  # xsi:type alternatives:
  # {http://test-types}f_t1
  # {http://test-types}f_t2
  # occurs any number of times
  f_a3 => [ { XSI_TYPE => '{http://test-types}f_t1', %data }, ], }
__TEMPL
