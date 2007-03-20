#!/usr/bin/perl
# test any and anyAttribute
# any with list of url's is not yet tested.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use Test::More tests => 101 + ($skip_dumper ? 0 : 9);

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
  , anyElement   => 'TAKE_ALL'   # warning!  order important for filter
  , anyAttribute => 'TAKE_ALL';

my $r2b = reader($schema, test2 => "{$TestNS}test2");
my $h2b = $r2b->( <<__XML__);
<test2 xmlns="$TestNS" xmlns:b="http://x" tns_a="11" b:tns_b="12">
  <tns_e>10</tns_e>
</test2>
__XML__

is(delete $h2b->{tns_e}, 10);
is(delete $h2b->{tns_a}, 11);
my $x2ba = delete $h2b->{"{$TestNS}tns_a"};
my $x2be = delete $h2b->{"{$TestNS}tns_e"};
ok(!keys %$h2b);
ok(defined $x2ba);
ok(defined $x2be);
isa_ok($x2ba, 'XML::LibXML::Attr');
isa_ok($x2be, 'ARRAY');
cmp_ok(scalar(@$x2be), '==', 1);
isa_ok($x2be->[0], 'XML::LibXML::Element');
is($x2ba->toString, ' tns_a="11"');
is($x2be->[0]->toString, '<tns_e>10</tns_e>');

# writer

my $nat_at_type = "{$TestNS}nat_at";
my $nat_at = $doc->createAttributeNS($TestNS, 'nat_at', 24);
ok(defined $nat_at, "create native attribute nat_at");

my $for_at_type = '{http://x}for_at';
my $for_at = $doc->createAttributeNS('http://x', 'for_at', 23);
ok(defined $for_at, "create foreign attribute for_at");
isa_ok($for_at, 'XML::LibXML::Attr');

my $nat_el_type = "{$TestNS}nat_el";
my $nat_el = $doc->createElementNS($TestNS, 'nat_el');
ok(defined $nat_el, "create native element nat_el");
$nat_el->appendText(25);
is($nat_el->toString, '<nat_el xmlns="http://test-types">25</nat_el>');

my $for_el_type = '{http://x}for_el';
my $for_el = $doc->createElementNS('http://x', 'for_el');
ok(defined $for_el, "create foreign element for_el");
isa_ok($for_el, 'XML::LibXML::Element');
$for_el->appendText(26);
is($for_el->toString, '<for_el xmlns="http://x">26</for_el>');

my %h2c = (tns_a => 21, tns_e => 22
  , $nat_at_type => $nat_at, $for_at_type => $for_at
  , $nat_el_type => $nat_el, $for_el_type => $for_el
  );

my $w2c = writer($schema, test2 => "{$TestNS}test2");
my $h2c = writer_test($w2c, \%h2c, $doc);
compare_xml($h2c, <<__XML);
<test2 xmlns="http://test-types" tns_a="21" nat_at="24">
  <tns_e>22</tns_e>
  <nat_el xmlns="http://test-types">25</nat_el>
</test2>
__XML
is(shift @errors, "value for $for_at_type not used (XML::LibXML::Attr)");
is(shift @errors, "value for $for_el_type not used (XML::LibXML::Element)");
ok(!@errors);

#
# Take only other namespace
#

my $r3b = reader($schema, test3 => "{$TestNS}test3");
my $h3b = $r3b->( <<__XML__);
<test3 xmlns="$TestNS" xmlns:b="http://x" other_a="11" b:other_b="12">
  <other_e>10</other_e>
  <for_el xmlns="http://x">26</for_el>
</test3>
__XML__

is(delete $h3b->{other_e}, 10);
is(delete $h3b->{other_a}, 11);

my $x3b = delete $h3b->{"{http://x}other_b"};
ok(defined $x3b);
isa_ok($x3b, 'XML::LibXML::Attr');
is($x3b->toString, ' b:other_b="12"');

my $x3b2 = delete $h3b->{"{http://x}for_el"};
ok(defined $x3b2);
isa_ok($x3b2, 'ARRAY');
cmp_ok(scalar(@$x3b2), '==', 1);
isa_ok($x3b2->[0], 'XML::LibXML::Element');
is($x3b2->[0]->toString, '<for_el xmlns="http://x">26</for_el>');

ok(!keys %$h3b);

# writer

my %h3c =
 (other_a => 10, other_e => 11
 , $nat_at_type => $nat_at, $for_at_type => $for_at
 , $nat_el_type => $nat_el, $for_el_type => $for_el
 );

my $w3c = writer($schema, test3 => "{$TestNS}test3");
my $h3c = writer_test($w3c, \%h3c, $doc);
compare_xml($h3c, <<__XML);
<test3 xmlns="http://test-types" other_a="10" b:for_at="23">
  <other_e>11</other_e>
  <for_el xmlns="http://x">26</for_el>
</test3>
__XML
is(shift @errors, "value for $nat_at_type not used (XML::LibXML::Attr)");
is(shift @errors, "value for $nat_el_type not used (XML::LibXML::Element)");
ok(!@errors);

#
# Take any namespace
#

my $r4b = reader($schema, test4 => "{$TestNS}test4");
my $h4b = $r4b->( <<__XML__);
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

my $x4b3 = delete $h4b->{"{$TestNS}any_e"};
ok(defined $x4b3);
isa_ok($x4b3, 'ARRAY');
cmp_ok(scalar(@$x4b3), '==', 1);
isa_ok($x4b3->[0], 'XML::LibXML::Element');
is($x4b3->[0]->toString, '<any_e>10</any_e>');

ok(!keys %$h4b);

# writer

my %h4c = (any_a => 10, any_e => 11
  , $nat_at_type => $nat_at, $for_at_type => $for_at);

my $w4c = writer($schema, test4 => "{$TestNS}test4");
my $h4c = writer_test($w4c, \%h4c);
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

my $r5b = reader($schema, test4 => "{$TestNS}test4");
my $h5b = $r5b->( <<__XML__);
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

my $x5b3 = delete $h5b->{"{$TestNS}any_e"};
isa_ok($x5b3, 'ARRAY');
cmp_ok(scalar(@$x5b3), '==', 1);
isa_ok($x5b3->[0], 'XML::LibXML::Element');
is($x5b3->[0]->toString, '<any_e>10</any_e>');

ok(!keys %$h5b);

