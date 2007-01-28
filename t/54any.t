#!/usr/bin/perl
# test any and anyAttribute
# any with list of url's is not yet tested.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use Test::More tests => 72;

my $NS2 = "http://test2/ns";
my $doc = XML::LibXML::Document->new('test doc', 'utf-8');
isa_ok($doc, 'XML::LibXML::Document');
my $root = $doc->createElement('root');
$doc->setDocumentElement($root);
$root->setNamespace('http://x', 'b', 1);

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<wsdl>

<xs:schema
  targetNamespace="$TestNS"
  xmlns:xs="$SchemaNS"
  xmlns:me="$TestNS"
  elementFormDefault="qualified"
>

<xs:element name="test1" type="xs:int" />

<xs:element name="test2" type="me:tns" />
<xs:complexType name="tns">
  <xs:sequence>
    <xs:element name="tns_e" type="xs:int" />
    <xs:any namespace="##targetNamespace" processContents="lax" />
  </xs:sequence>
  <xs:attribute name="tns_a" type="xs:int" />
  <xs:anyAttribute namespace="##targetNamespace" processContents="lax" />
</xs:complexType>

<xs:element name="test3" type="me:other" />
<xs:complexType name="other">
  <xs:sequence>
    <xs:element name="other_e" type="xs:int" />
    <xs:any namespace="##other" processContents="lax" />
  </xs:sequence>
  <xs:attribute name="other_a" type="xs:int" />
  <xs:anyAttribute namespace="##other" processContents="lax" />
</xs:complexType>

<xs:element name="test4" type="me:any" />
<xs:complexType name="any">
  <xs:sequence>
    <xs:element name="any_e" type="xs:int" />
    <xs:any namespace="##any" processContents="lax" />
  </xs:sequence>
  <xs:attribute name="any_a" type="xs:int" />
  <xs:anyAttribute namespace="##any" processContents="lax" />
</xs:complexType>

</xs:schema>

<schema
 targetNamespace="$NS2"
 xmlns="$SchemaNS"
 xmlns:that="$TestNS">

<attribute name="in_other" type="xs:int" />

</schema>

</wsdl>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts
  , invalid            => sub {no warnings; push @errors, "$_[2] ($_[1])"}
  , include_namespaces => 1;

my %t2a = (tns_e => 10, tns_a => 11);
test_rw($schema, test2 => <<__XML__, \%t2a);
<test2 xmlns="$TestNS" tns_a="11"><tns_e>10</tns_e></test2>
__XML__

#
# Take it, in target namespace
#

push @run_opts
  , anyAttribute       => 'TAKE_ALL';

my $h2b = reader($schema, test2 => "{$TestNS}test2" => <<__XML__);
<test2 xmlns="$TestNS" xmlns:b="http://x" tns_a="11" b:tns_b="12">
  <tns_e>10</tns_e>
</test2>
__XML__

is(delete $h2b->{tns_e}, 10);
is(delete $h2b->{tns_a}, 11);
my $x2b = delete $h2b->{"{$TestNS}tns_a"};
ok(!keys %$h2b);
ok(defined $x2b);
isa_ok($x2b, 'XML::LibXML::Attr');
is($x2b->toString, ' tns_a="11"');

# writer

my $nat_at_type = "{$TestNS}nat_at";
my $nat_at = $doc->createAttributeNS($TestNS, 'nat_at', 24);
ok(defined $nat_at, "create native attribute nat_at");

my $for_at_type = '{http://x}for_at';
my $for_at = $doc->createAttributeNS('http://x', 'for_at', 23);
ok(defined $for_at, "create foreign attribute for_at");
isa_ok($for_at, 'XML::LibXML::Attr');

my %h2c = (tns_a => 21, tns_e => 22
  , $nat_at_type => $nat_at, $for_at_type => $for_at);

my $h2c = writer($schema, $doc, test2 => "{$TestNS}test2" => \%h2c);
compare_xml($h2c, <<__XML);
<test2 xmlns="http://test-types" tns_a="21" nat_at="24">
  <tns_e>22</tns_e>
</test2>
__XML
is(shift @errors, "value for $for_at_type not used (XML::LibXML::Attr)");
ok(!@errors);

#
# Take only other namespace
#

my $h3b = reader($schema, test3 => "{$TestNS}test3" => <<__XML__);
<test3 xmlns="$TestNS" xmlns:b="http://x" other_a="11" b:other_b="12">
  <other_e>10</other_e>
</test3>
__XML__

is(delete $h3b->{other_e}, 10);
is(delete $h3b->{other_a}, 11);
my $x3b = delete $h3b->{"{http://x}other_b"};
ok(!keys %$h3b);
ok(defined $x3b);
isa_ok($x3b, 'XML::LibXML::Attr');
is($x3b->toString, ' b:other_b="12"');

# writer

my %h3c = (other_a => 10, other_e => 11
  , $nat_at_type => $nat_at, $for_at_type => $for_at);

my $h3c = writer($schema, $doc, test3 => "{$TestNS}test3" => \%h3c);
compare_xml($h3c, <<__XML);
<test3 xmlns="http://test-types" other_a="10" b:for_at="23">
  <other_e>11</other_e>
</test3>
__XML
is(shift @errors, "value for $nat_at_type not used (XML::LibXML::Attr)");
ok(!@errors);

#
# Take any namespace
#

my $h4b = reader($schema, test4 => "{$TestNS}test4" => <<__XML__);
<test4 xmlns="$TestNS" xmlns:b="http://x" any_a="11" b:any_b="12">
  <any_e>10</any_e>
</test4>
__XML__

is(delete $h4b->{any_e}, 10);
is(delete $h4b->{any_a}, 11);

my $x4b = delete $h4b->{"{$TestNS}any_a"};
ok(defined $x4b);
isa_ok($x4b, 'XML::LibXML::Attr');
is($x4b->toString, ' any_a="11"');

my $x4b2 = delete $h4b->{"{http://x}any_b"};
ok(defined $x4b2);
isa_ok($x4b2, 'XML::LibXML::Attr');
is($x4b2->toString, ' b:any_b="12"');
ok(!keys %$h4b);

# writer

my %h4c = (any_a => 10, any_e => 11
  , $nat_at_type => $nat_at, $for_at_type => $for_at);

my $h4c = writer($schema, $doc, test4 => "{$TestNS}test4" => \%h4c);
compare_xml($h4c, <<__XML);
<test4 xmlns="http://test-types" any_a="10" nat_at="24" b:for_at="23">
  <any_e>11</any_e>
</test4>
__XML
ok(!@errors);

#
# Test filter
#

my @filtered;
$run_opts[-1] =
 sub { my ($type, $value) = @_;
       push @filtered, $type;
       ok(defined $type, "filter $type");
       isa_ok($value, 'XML::LibXML::Attr');
       my $flat = $value->toString;
       $type =~ m/_a/ ? ($type, $flat) : ();
     };

my $h5b = reader($schema, test4 => "{$TestNS}test4" => <<__XML__);
<test4 xmlns="$TestNS" xmlns:b="http://x" any_a="11" b:any_b="12">
  <any_e>10</any_e>
</test4>
__XML__

is(delete $h5b->{any_e}, 10);
is(delete $h5b->{any_a}, 11);

my $x5b = delete $h5b->{"{$TestNS}any_a"};
is($x5b, ' any_a="11"');

my $x5b2 = delete $h5b->{"{http://x}any_b"};
ok(!defined $x5b2);
ok(!keys %$h5b);

