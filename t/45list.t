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
  <list itemType="int" />
</simpleType>

<element name="test1" type="me:t1" />

<simpleType name="t2">
  <list>
    <simpleType>
      <restriction base="int" />
    </simpleType>
  </list>
</simpleType>

<element name="test2" type="me:t2" />

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts, invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"};

test_rw($schema, "test1" => <<__XML__, [1]);
<test1>1</test1>
__XML__
ok(!@errors);

test_rw($schema, "test1" => <<__XML__, [2, 3]);
<test1>2 3</test1>
__XML__
ok(!@errors);

test_rw($schema, "test1" => <<__XML__, [4, 5, 6]);
<test1> 4
  5\t  6 </test1>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, [1]);
<test2>1</test2>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, [2, 3]);
<test2>2 3</test2>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, [4, 5, 6]);
<test2> 4
  5\t  6 </test2>
__XML__
ok(!@errors);
