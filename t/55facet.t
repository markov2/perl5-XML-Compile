#!/usr/bin/perl
# test facets

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 300;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<simpleType name="t1">
  <restriction base="int" />
</simpleType>

<simpleType name="t2">
  <restriction base="int">
    <maxInclusive value="42" />
    <minInclusive value="12" />
  </restriction>
</simpleType>

<element name="test1" type="me:t1" />

<element name="test2" type="me:t2" />

<element name="test3">
  <simpleType>
    <restriction base="int">
      <maxExclusive value="45" />
      <minExclusive value="13" />
    </restriction>
  </simpleType>
</element>

<element name="test4">
  <simpleType>
    <restriction base="string">
      <length value="3" />
    </restriction>
  </simpleType>
</element>

<element name="test5">
  <simpleType>
    <restriction base="string">
      <whiteSpace value="preserve" />
    </restriction>
  </simpleType>
</element>

<element name="test6">
  <simpleType>
    <restriction base="string">
      <whiteSpace value="replace" />
    </restriction>
  </simpleType>
</element>

<element name="test7">
  <simpleType>
    <restriction base="string">
      <whiteSpace value="collapse" />
    </restriction>
  </simpleType>
</element>

<element name="test8">
  <simpleType>
    <restriction base="string">
      <enumeration value="one" />
      <enumeration value="two" />
    </restriction>
  </simpleType>
</element>

<element name="test9">
  <simpleType>
    <restriction base="long">
      <totalDigits value="4" />
    </restriction>
  </simpleType>
</element>

<element name="test10">
  <simpleType>
    <restriction base="float">
      <totalDigits value="4" />
    </restriction>
  </simpleType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

##
### Integers
##

test_rw($schema, "test1" => <<__XML__, 12);
<test1>12</test1>
__XML__

test_rw($schema, "test2" => <<__XML__, 13);
<test2>13</test2>
__XML__

test_rw($schema, "test2" => <<__XML__, 42);
<test2>42</test2>
__XML__

my $error = reader_error($schema, test2 => <<__XML__);
<test2>43</test2>
__XML__
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = writer_error($schema, test2 => 43);
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = reader_error($schema, test2 => <<__XML__);
<test2>11</test2>
__XML__
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

$error = writer_error($schema, test2 => 11);
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

test_rw($schema, "test3" => <<__XML__, 44);
<test3>44</test3>
__XML__

$error = reader_error($schema, test3 => <<__XML__);
<test3>45</test3>
__XML__
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = writer_error($schema, test3 => 45);
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = reader_error($schema, "test3" => <<__XML__);
<test3>13</test3>
__XML__
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

$error = writer_error($schema, test3 => 13);
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

##
### strings
##

test_rw($schema, "test4" => <<__XML__, "aap");
<test4>aap</test4>
__XML__

$error = reader_error($schema, "test4" => <<__XML__);
<test4>noot</test4>
__XML__

is($error, "string `noot' does not have required length 3 at {http://test-types}test4\#facet");

$error = writer_error($schema, test4 => 'noot');
is($error, "string `noot' does not have required length 3 at {http://test-types}test4\#facet");

$error = reader_error($schema, test4 => <<__XML__);
<test4>ik</test4>
__XML__
is($error, "string `ik' does not have required length 3 at {http://test-types}test4#facet");

$error = writer_error($schema, test4 => "ik");
is($error,  "string `ik' does not have required length 3 at {http://test-types}test4#facet");

test_rw($schema, "test5" => <<__XML__, "\ \ \t\n\tmies \t");
<test5>\ \ \t
\tmies \t</test5>
__XML__

test_rw($schema, "test6" => <<__XML__, "     mies  ", <<__XML__, "\ \ \t \tmies \t");
<test6>\ \ \t
\tmies \t</test6>
__XML__
<test6>     mies  </test6>
__XML__

test_rw($schema, "test7" => <<__XML__, 'mies', <<__XML__, "\ \ \t \tmies \t");
<test7>\ \ \t
\tmies \t</test7>
__XML__
<test7>mies</test7>
__XML__

test_rw($schema, "test8" => <<__XML__, 'one');
<test8>one</test8>
__XML__

test_rw($schema, "test8" => <<__XML__, 'two');
<test8>two</test8>
__XML__

$error = reader_error($schema, test8 => <<__XML__);
<test8>three</test8>
__XML__
is($error, "invalid enumerate `three' at {http://test-types}test8#facet");

$error = reader_error($schema, test8 => <<__XML__);
<test8/>
__XML__
is($error, "invalid enumerate `' at {http://test-types}test8#facet");

### test9 (bug reported by Gert Doering)

push @run_opts, sloppy_integers => 1;

test_rw($schema, test9 => '<test9>0</test9>', 0);

test_rw($schema, test9 => '<test9>12</test9>', 12);

test_rw($schema, test9 => '<test9>123</test9>', 123);

test_rw($schema, test9 => '<test9>1234</test9>', 1234);

$error = writer_error($schema, test9 => 12345);
is($error, 'decimal too long, got 5 digits max 4 at {http://test-types}test9#facet');

$error = reader_error($schema, test9 => '<test9>12345</test9>');
is($error, 'decimal too long, got 5 digits max 4 at {http://test-types}test9#facet');

### test10 (same bug reported by Gert Doering)

test_rw($schema, test10 => '<test10>0</test10>', 0);

test_rw($schema, test10 => '<test10>1.2</test10>', 1.2);

test_rw($schema, test10 => '<test10>1.23</test10>', 1.23);

test_rw($schema, test10 => '<test10>12.3</test10>', 12.3);

test_rw($schema, test10 => '<test10>1.234</test10>', 1.234);

test_rw($schema, test10 => '<test10>12.34</test10>', 12.34);

test_rw($schema, test10 => '<test10>123.4</test10>', 123.4);

test_rw($schema, test10 => '<test10>1234</test10>', 1234);
