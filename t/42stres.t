#!/usr/bin/perl
# test simple type restriction

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 97;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<simpleType name="t1">
  <restriction base="int" />
</simpleType>

<simpleType name="t2">
  <restriction base="me:t1">
    <minInclusive value="10" />
  </restriction>
</simpleType>

<simpleType name="t3">
  <restriction base="me:t2">
    <maxInclusive value="20" />
  </restriction>
</simpleType>

<element name="test1" type="me:t1" />

<element name="test2" type="me:t2" />

<element name="test3" type="me:t3" />

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts, invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"};

#
# In range
#

test_rw($schema, "test1" => <<__XML__, 12);
<test1>12</test1>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, 13);
<test2>13</test2>
__XML__
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 14);
<test3>14</test3>
__XML__
ok(!@errors);

#
# too small
#

test_rw($schema, "test1" => <<__XML__, 5);
<test1>5</test1>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, 10, <<__XML__, 6);
<test2>6</test2>
__XML__
<test2>10</test2>
__XML__
is(shift @errors, "too small inclusive, min 10 (6)");
is(shift @errors, "too small inclusive, min 10 (6)");
ok(!@errors);

# inherited restriction
test_rw($schema, "test3" => <<__XML__, 10, <<__XML__, 6);
<test3>6</test3>
__XML__
<test3>10</test3>
__XML__
is(shift @errors, "too small inclusive, min 10 (6)");
is(shift @errors, "too small inclusive, min 10 (6)");
ok(!@errors);

#
# too large
#

test_rw($schema, "test1" => <<__XML__, 55);
<test1>55</test1>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, 56);
<test2>56</test2>
__XML__
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 20 , <<__XML__, 57);
<test3>57</test3>
__XML__
<test3>20</test3>
__XML__
is(shift @errors, "too large inclusive, max 20 (57)");
is(shift @errors, "too large inclusive, max 20 (57)");
ok(!@errors);

#
