#!/usr/bin/perl
# test facets

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 167;

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

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts,
    invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef};

##
### Integers
##

test_rw($schema, "test1" => <<__XML__, 12);
<test1>12</test1>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, 13);
<test2>13</test2>
__XML__
ok(!@errors);

test_rw($schema, "test2" => <<__XML__, 42);
<test2>42</test2>
__XML__
ok(!@errors);

# correct to ceiling
test_rw($schema, "test2" => <<__XML__, 42, <<__XML__);
<test2>43</test2>
__XML__
<test2>42</test2>
__XML__
is(shift @errors, "too large inclusive, max 42 (43)");
ok(!@errors);

# correct to floor
test_rw($schema, "test2" => <<__XML__, 12, <<__XML__);
<test2>11</test2>
__XML__
<test2>12</test2>
__XML__
is(shift @errors, "too small inclusive, min 12 (11)");
ok(!@errors);

test_rw($schema, "test3" => <<__XML__, 44);
<test3>44</test3>
__XML__
ok(!@errors);

# correct to ceiling
test_rw($schema, "test3" => <<__XML__, 45, undef);
<test3>45</test3>
__XML__
is(shift @errors, "too large exclusive, smaller 45 (45)");
ok(!@errors);

# correct to floor
test_rw($schema, "test3" => <<__XML__, 13, undef);
<test3>13</test3>
__XML__
is(shift @errors, "too small exclusive, larger 13 (13)");
ok(!@errors);

##
### strings
##

test_rw($schema, "test4" => <<__XML__, "aap");
<test4>aap</test4>
__XML__
ok(!@errors);

test_rw($schema, "test4" => <<__XML__, "noo", <<__XML__, 'noot');
<test4>noot</test4>
__XML__
<test4>noo</test4>
__XML__
is(shift @errors, "required length 3 (noot)");
is(shift @errors, "required length 3 (noot)");
ok(!@errors);

test_rw($schema, "test4" => <<__XML__, "ikX", <<__XML__, 'ik');
<test4>ik</test4>
__XML__
<test4>ikX</test4>
__XML__
is(shift @errors, "required length 3 (ik)");
is(shift @errors, "required length 3 (ik)");
ok(!@errors);

test_rw($schema, "test5" => <<__XML__, "\ \ \t\n\tmies \t");
<test5>\ \ \t
\tmies \t</test5>
__XML__
ok(!@errors);

test_rw($schema, "test6" => <<__XML__, "     mies  ", <<__XML__, "\ \ \t \tmies \t");
<test6>\ \ \t
\tmies \t</test6>
__XML__
<test6>     mies  </test6>
__XML__
ok(!@errors);

test_rw($schema, "test7" => <<__XML__, 'mies', <<__XML__, "\ \ \t \tmies \t");
<test7>\ \ \t
\tmies \t</test7>
__XML__
<test7>mies</test7>
__XML__
ok(!@errors);

test_rw($schema, "test8" => <<__XML__, 'one');
<test8>one</test8>
__XML__
ok(!@errors);

test_rw($schema, "test8" => <<__XML__, 'two');
<test8>two</test8>
__XML__
ok(!@errors);

test_rw($schema, "test8" => <<__XML__, "three", '', 'three');
<test8>three</test8>
__XML__
is(shift @errors, "invalid enum (three)");
ok(!@errors);

test_rw($schema, "test8" => <<__XML__, "", '', '');
<test8/>
__XML__
is(shift @errors, "invalid enum ()");
ok(!@errors);
