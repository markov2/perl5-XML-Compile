#!/usr/bin/perl
# test facets

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 348;

set_compile_defaults
    elements_qualified => 'NONE';

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

<element name="test13">
  <simpleType>
    <restriction base="base64Binary">
      <length value="5"/>
    </restriction>
  </simpleType>
</element>

<!-- rt.cpan.org#62237, enumeration of qname -->
<element name="test14">
  <simpleType>
    <restriction base="QName">
      <enumeration value="me:DataEncodingUnknown"/>
      <enumeration value="me:MustUnderstand"/>
      <enumeration value="me:Receiver"/>
      <enumeration value="me:Sender"/>
      <enumeration value="me:VersionMismatch"/>
    </restriction>
  </simpleType>
</element>

<!-- from KML 2.2 -->
<element name="test15" type="me:colorType" />
<simpleType name="colorType">
  <annotation>
    <documentation><![CDATA[
        
        aabbggrr
        
        ffffffff: opaque white
        ff000000: opaque black
        
        ]]></documentation>
  </annotation>
  <restriction base="hexBinary">
    <length value="4"/>
  </restriction>
</simpleType>

</schema>
__SCHEMA__

ok(defined $schema);

##
### Integers
##

test_rw($schema, test1 => <<__XML, 12);
<test1>12</test1>
__XML

test_rw($schema, test2 => <<__XML, 13);
<test2>13</test2>
__XML

test_rw($schema, test2 => <<__XML, 42);
<test2>42</test2>
__XML

my $error = error_r($schema, test2 => <<__XML);
<test2>43</test2>
__XML
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = error_w($schema, test2 => 43);
is($error, "too large inclusive 43, max 42 at {http://test-types}test2#facet");

$error = error_r($schema, test2 => <<__XML);
<test2>11</test2>
__XML
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

$error = error_w($schema, test2 => 11);
is($error, "too small inclusive 11, min 12 at {http://test-types}test2#facet");

test_rw($schema, "test3" => <<__XML, 44);
<test3>44</test3>
__XML

$error = error_r($schema, test3 => <<__XML);
<test3>45</test3>
__XML
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = error_w($schema, test3 => 45);
is($error, "too large exclusive 45, smaller 45 at {http://test-types}test3#facet");

$error = error_r($schema, test3 => <<__XML);
<test3>13</test3>
__XML
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

$error = error_w($schema, test3 => 13);
is($error, "too small exclusive 13, larger 13 at {http://test-types}test3#facet");

##
### strings
##

test_rw($schema, "test4" => <<__XML, "aap");
<test4>aap</test4>
__XML

$error = error_r($schema, test4 => <<__XML);
<test4>noot</test4>
__XML

is($error, "string `noot' does not have required length 3 but 4 at {http://test-types}test4\#facet");

$error = error_w($schema, test4 => 'noot');
is($error, "string `noot' does not have required length 3 but 4 at {http://test-types}test4\#facet");

$error = error_r($schema, test4 => <<__XML);
<test4>ik</test4>
__XML
is($error, "string `ik' does not have required length 3 but 2 at {http://test-types}test4#facet");

$error = error_w($schema, test4 => "ik");
is($error,  "string `ik' does not have required length 3 but 2 at {http://test-types}test4#facet");

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

$error = error_r($schema, test8 => <<__XML);
<test8>three</test8>
__XML
is($error, "invalid enumerate `three' at {http://test-types}test8#facet");

$error = error_r($schema, test8 => <<__XML);
<test8/>
__XML
is($error, "invalid enumerate `' at {http://test-types}test8#facet");

### test9 (bug reported by Gert Doering)

set_compile_defaults
   sloppy_integers    => 1
 , sloppy_floats      => 1
 , elements_qualified => 'NONE';

test_rw($schema, test9 => '<test9>0</test9>', 0);

test_rw($schema, test9 => '<test9>12</test9>', 12);

test_rw($schema, test9 => '<test9>123</test9>', 123);

test_rw($schema, test9 => '<test9>1234</test9>', 1234);

$error = error_w($schema, test9 => 12345);
is($error, 'decimal too long, got 5 digits max 4 at {http://test-types}test9#facet');

$error = error_r($schema, test9 => '<test9>12345</test9>');
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

$error = error_w($schema, test11 => {t11 => 3});
is($error, 'too small inclusive 3, min 12 at {http://test-types}test11/t11#facet');

### test12 rt.cpan.org#39224

test_rw($schema, test12 => '<test12>1.12</test12>', '1.12');
test_rw($schema, test12 => '<test12>1.10</test12>', '1.10');
test_rw($schema, test12 => '<test12>1.00</test12>', '1.00');
test_rw($schema, test12 => '<test12>1.2</test12>',  '1.2');
test_rw($schema, test12 => '<test12>1.</test12>',   '1.');

$error = error_r($schema, test12 => '<test12>1</test12>');
like($error, qr/^string \`1' does not match pattern /);

# dot problem with regex '.'
$error = error_r($schema, test12 => '<test12>42</test12>');
like($error, qr/^string \`42' does not match pattern /);

### test13 length on base64

test_rw($schema, test13 => '<test13>YWJjZGU=</test13>', 'abcde');

$error = error_r($schema, test13 => '<test13>YWJjYWJjZGU=</test13>');
is($error, "string `abcabcde' does not have required length 5 but 8 at {http://test-types}test13#facet");

$error = error_w($schema, test13 => 'abcdef');
is($error, "base64 data does not have required length 5, but 6 at {http://test-types}test13#facet");

### test15 length of hexBinary

test_rw($schema, test15 => '<test15>deadbeef</test15>', pack('N', 0xdeadbeef));

$error = error_r($schema, test15 => '<test15>345678</test15>');
is($error, "string `4Vx' does not have required length 4 but 3 at {http://test-types}test15#facet");

$error = error_w($schema, test15 => 'abc');
is($error, "hex data does not have required length 4, but 3 at {http://test-types}test15#facet");

$error = error_w($schema, test15 => 'anything');
is($error, "hex data does not have required length 4, but 8 at {http://test-types}test15#facet");

### test14 enumeration of qnames [Aleksey Mashanov]

set_compile_defaults
    include_namespaces    => 1
  , use_default_namespace => 0
  , prefixes => [ a => $TestNS ];

test_rw($schema, test14 => qq{<a:test14 xmlns:a="$TestNS">a:Sender</a:test14>}
  , "{$TestNS}Sender");
