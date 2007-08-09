#!/usr/bin/perl
# patterns are still poorly supported.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 32;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <simpleType>
    <restriction base="string">
      <pattern value="a.c" />
    </restriction>
  </simpleType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);
my $error;

test_rw($schema, "test1" => <<__XML, "abc");
<test1>abc</test1>
__XML

$error = reader_error($schema, test1 => <<__XML);
<test1>abbc</test1>
__XML
is($error, "string `abbc' does not match pattern (?-xism:a.c) at {http://test-types}test1#facet");

$error = writer_error($schema, test1 => 'abbc');
is($error, "string `abbc' does not match pattern (?-xism:a.c) at {http://test-types}test1#facet");

test_rw($schema, "test1" => <<__XML, 'abaaBcdef');
<test1>abaaBcdef</test1>
__XML
