#!/usr/bin/perl
# Mixed elements

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Data::Dumper;

use XML::Compile::Schema;

use Test::More tests => 36;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType mixed="true">
    <sequence>
      <element name="ignored" type="int"/>
    </sequence>
    <attribute name="id" type="string" />
  </complexType>
</element>

<element name="test2" type="me:test2"/>
<complexType name="test2" mixed="true">
  <sequence>
    <element name="ignored" type="int"/>
  </sequence>
</complexType>

</schema>
__SCHEMA__

ok(defined $schema);

### test 1, nameless complexType with attributes

my $t1read = reader($schema, test1 => "{$TestNS}test1");
isa_ok($t1read, 'CODE', 'compiled reader');

my $t1mixed = <<'__XML';
<test1 id="5">
  aaa
  <count>1</count>
  bbb
</test1>
__XML
my $r1a = $t1read->($t1mixed);

isa_ok($r1a, 'HASH', 'got result');
is($r1a->{id}, '5', 'check attribute');
ok(exists $r1a->{_}, 'has node');
isa_ok($r1a->{_}, 'XML::LibXML::Element');
compare_xml($r1a->{_}->toString, $t1mixed);

my $t1write = writer($schema, test1 => "{$TestNS}test1");
my $t1w1node = XML::LibXML::Element->new('test1');
my $t1w1a = writer_test($t1write, $t1w1node);
compare_xml($t1w1a,  '<test1/>');

my $t1w1b = writer_test($t1write, { _ => $t1w1node, id => 6});
compare_xml($t1w1b,  '<test1 id="6"/>');

is($schema->template(PERL => "{$TestNS}test1"), <<'__TEMPL');
# test1 has a mixed content
test1 =>
{ # is a {http://www.w3.org/2001/XMLSchema}string
  id => "example",

  # mixed content cannot be processed automatically
  _ => "XML::LibXML::Element->new(test1)", }
__TEMPL

### test 2, named complexType without attibutes

my $t2read = reader($schema, test2 => "{$TestNS}test2");
isa_ok($t2read, 'CODE', 'compiled reader');

my $t2mixed = <<'__XML';
<test2>bbb</test2>
__XML
my $r2a = $t2read->($t2mixed);

isa_ok($r2a, 'XML::LibXML::Element');
compare_xml($r2a->toString, $t2mixed);

my $t2write = writer($schema, test2 => "{$TestNS}test2");
my $t2w1node = XML::LibXML::Element->new('test2');
my $t2w1a = writer_test($t2write, $t2w1node);
compare_xml($t2w1a,  '<test2/>');

my $t2w1b = writer_test($t2write, { _ => $t2w1node});
compare_xml($t2w1b,  '<test2/>');

is($schema->template(PERL => "{$TestNS}test2"), <<'__TEMPL');
# mixed content cannot be processed automatically
test2 => "XML::LibXML::Element->new(test2)"
__TEMPL
