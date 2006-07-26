#!/usr/bin/perl
# patterns are still poorly supported.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 26;

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

my @errors;
push @run_opts, invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"};

run_test($schema, "test1" => <<__XML__, "abc");
<test1>abc</test1>
__XML__
ok(!@errors);

run_test($schema, "test1" => <<__XML__, undef, <<__XML__, 'abbc');
<test1>abbc</test1>
__XML__
__XML__
is(shift @errors, 'does not match pattern (?-xism:a.c) (abbc)');
ok(!@errors);

run_test($schema, "test1" => <<__XML__, 'abaaBcdef');
<test1>abaaBcdef</test1>
__XML__
ok(!@errors);
