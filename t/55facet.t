#!/usr/bin/perl
# test facets

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 274;

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

<element name="test11">
  <complexType>
    <sequence>
      <element name="t11" type="me:t2" />
    </sequence>
  </complexType>
</element>

<!-- rt.cpan.org#39224, order of pattern match and value decoding -->
<simpleType name="DecimalType">
  <restriction base="decimal">
    <pattern value="[0-9]{1,13}\\.[0-9]{0,2}"/>
  </restriction>
</simpleType>
<element name="test12" type="me:DecimalType" />

</schema>
__SCHEMA__

ok(defined $schema);

##
### Integers
##

test_rw($schema, "test1" => <<__XML, 12);
<test1>12</test1>
__XML

test_rw($schema, "test2" => <<__XML, 13);
<test2>13</test2>
__XML

test_rw($schema, "test2" => <<__XML, 42);
<test2>42</test2>
__XML

my $error = reader_error($schema, test2 => <<__XML);
<test2>43</test2>
__XML
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = writer_error($schema, test2 => 43);
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = reader_error($schema, test2 => <<__XML);
<test2>11</test2>
__XML
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

$error = writer_error($schema, test2 => 11);
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

test_rw($schema, "test3" => <<__XML, 44);
<test3>44</test3>
__XML

$error = reader_error($schema, test3 => <<__XML);
<test3>45</test3>
__XML
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = writer_error($schema, test3 => 45);
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = reader_error($schema, test3 => <<__XML);
<test3>13</test3>
__XML
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

$error = writer_error($schema, test3 => 13);
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

##
### strings
##

test_rw($schema, "test4" => <<__XML, "aap");
<test4>aap</test4>
__XML

$error = reader_error($schema, test4 => <<__XML);
<test4>noot</test4>
__XML

is($error, "string `noot' does not have required length 3 at {http://test-types}test4\#facet");

$error = writer_error($schema, test4 => 'noot');
is($error, "string `noot' does not have required length 3 at {http://test-types}test4\#facet");

$error = reader_error($schema, test4 => <<__XML);
<test4>ik</test4>
__XML
is($error, "string `ik' does not have required length 3 at {http://test-types}test4#facet");

$error = writer_error($schema, test4 => "ik");
is($error,  "string `ik' does not have required length 3 at {http://test-types}test4#facet");

test_rw($schema, "test5" => <<__XML, "\ \ \t\n\tmies \t");
<test5>\ \ \t
\tmies \t</test5>
__XML

test_rw($schema, "test6" => <<__XML, "     mies  ", <<__XML, "\ \ \t \tmies \t");
<test6>\ \ \t
\tmies \t</test6>
__XML
<test6>     mies  </test6>
__XML

test_rw($schema, "test7" => <<__XML, 'mies', <<__XML, "\ \ \t \tmies \t");
<test7>\ \ \t
\tmies \t</test7>
__XML
<test7>mies</test7>
__XML

test_rw($schema, "test8" => <<__XML, 'one');
<test8>one</test8>
__XML

test_rw($schema, "test8" => <<__XML, 'two');
<test8>two</test8>
__XML

$error = reader_error($schema, test8 => <<__XML);
<test8>three</test8>
__XML
is($error, "invalid enumerate `three' at {http://test-types}test8#facet");

$error = reader_error($schema, test8 => <<__XML);
<test8/>
__XML
is($error, "invalid enumerate `' at {http://test-types}test8#facet");

### test9 (bug reported by Gert Doering)

set_compile_defaults
   sloppy_integers => 1
 , sloppy_floats   => 1;

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

### test11 (from bug reported by Allan Wind)

$error = writer_error($schema, test11 => {t11 => 3});
is($error, 'too small inclusive 3, min 12 at {http://test-types}test11/t11#facet');

### test12 rt.cpan.org#39224

test_rw($schema, test12 => '<test12>1.12</test12>', '1.12');
test_rw($schema, test12 => '<test12>1.10</test12>', '1.10');
test_rw($schema, test12 => '<test12>1.00</test12>', '1.00');
test_rw($schema, test12 => '<test12>1.2</test12>',  '1.2');
test_rw($schema, test12 => '<test12>1.</test12>',   '1.');

$error = reader_error($schema, test12 => '<test12>1</test12>');
like($error, qr/^string \`1' does not match pattern /);

# dot problem with regex '.'
$error = reader_error($schema, test12 => '<test12>42</test12>');
like($error, qr/^string \`42' does not match pattern /);
