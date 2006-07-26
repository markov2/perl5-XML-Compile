#!/usr/bin/perl
# simpleType list

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

<simpleType name="t1">
  <union>
    <simpleType>
      <restriction base="int" />
    </simpleType>
    <simpleType>
      <restriction base="string">
        <enumeration value="unbounded" />
      </restriction>
    </simpleType>
  </union>
</simpleType>

<element name="test1" type="me:t1" />

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts,
     invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef};

run_test($schema, "test1" => <<__XML__, 1 );
<test1>1</test1>
__XML__
ok(!@errors);

run_test($schema, "test1" => <<__XML__, 'unbounded');
<test1>unbounded</test1>
__XML__
ok(!@errors);

run_test($schema, "test1" => <<__XML__, undef, '', 'other');
<test1>other</test1>
__XML__

is(shift @errors, 'no match in union (other)');
ok(!@errors);
