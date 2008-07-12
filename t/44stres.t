#!/usr/bin/perl
# test simple type restriction

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 70;

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

#
# In range
#

test_rw($schema, "test1" => <<__XML__, 12);
<test1>12</test1>
__XML__

test_rw($schema, "test2" => <<__XML__, 13);
<test2>13</test2>
__XML__

test_rw($schema, "test3" => <<__XML__, 14);
<test3>14</test3>
__XML__

#
# too small
#

test_rw($schema, "test1" => <<__XML__, 5);
<test1>5</test1>
__XML__

my $error = reader_error($schema, test2 => <<__XML__);
<test2>6</test2>
__XML__
is($error, 'too small inclusive 6, min 10 at {http://test-types}test2#facet');

$error = writer_error($schema, test2 => 6);
is($error, "too small inclusive 6, min 10 at {http://test-types}test2#facet");

# inherited restriction
$error = reader_error($schema, test3 => <<__XML__);
<test3>6</test3>
__XML__
is($error, 'too small inclusive 6, min 10 at {http://test-types}test3#facet');

$error = writer_error($schema, test3 => 6);
is($error, "too small inclusive 6, min 10 at {http://test-types}test3#facet");

#
# too large
#

test_rw($schema, "test1" => <<__XML__, 55);
<test1>55</test1>
__XML__

test_rw($schema, "test2" => <<__XML__, 56);
<test2>56</test2>
__XML__

$error = reader_error($schema, test3 => <<__XML__);
<test3>57</test3>
__XML__
is($error, 'too large inclusive 57, max 20 at {http://test-types}test3#facet');

$error = writer_error($schema, test3 => 57);
is($error, "too large inclusive 57, max 20 at {http://test-types}test3#facet");
