#!/usr/bin/perl
# simpleType list

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 61;

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

<simpleType name="t2">
  <restriction base="string">
     <enumeration value="any" />
  </restriction>
</simpleType>

<simpleType name="t3">
  <union memberTypes="me:t2 int">
    <simpleType>
      <restriction base="string">
         <enumeration value="none" />
      </restriction>
    </simpleType>
  </union>
</simpleType>

<element name="test3" type="me:t3" />

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts,
     invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef};

test_rw($schema, "test1" => <<__XML__, 1 );
<test1>1</test1>
__XML__
ok(!@errors);

test_rw($schema, "test1" => <<__XML__, 'unbounded');
<test1>unbounded</test1>
__XML__
ok(!@errors);

test_rw($schema, "test1" => <<__XML__, undef, '', 'other');
<test1>other</test1>
__XML__

is(shift @errors, 'no match in union (other)');
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 1 );
<test3>1</test3>
__XML__
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 'any');
<test3>any</test3>
__XML__
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 'none');
<test3>none</test3>
__XML__
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, undef, '', 'other');
<test3>other</test3>
__XML__

is(shift @errors, 'no match in union (other)');
ok(!@errors);
