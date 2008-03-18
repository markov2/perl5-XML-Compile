#!/usr/bin/perl
# test use of big math

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More;

BEGIN {
   eval 'require Math::BigInt';
   if($@)
   {   plan skip_all => "Math::BigInt not installed";
   }

   eval "require Math::BigInt::GMP";
   unless($@)
   {   # cmp_deeply does not understand ::GMP objects
       plan skip_all => "using Math::BigInt::GMP";
   }

   plan tests => 86;
}

# Will fail when perl's longs get larger than 64bit
my $some_big1 = "12432156239876121237";
my $some_big2 = "243587092790745290879";

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<simpleType name="t1">
  <restriction base="integer" />
</simpleType>

<element name="test1" type="me:t1" />

<simpleType name="t2">
  <restriction base="integer">
    <minInclusive value="40" />
    <maxInclusive value="$some_big1" />
  </restriction>
</simpleType>

<element name="test2" type="me:t2" />

<element name="test3">
  <complexType>
    <sequence>
      <element name="t3a" type="integer" default="10" />
      <element name="t3b" type="int"     default="11" />
    </sequence>
  </complexType>
</element>

<element name="test4">
  <complexType>
    <sequence>
      <element name="t4" type="integer" fixed="79" />
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

push @run_opts, sloppy_integers => 0;

##
### Integers
##

test_rw($schema, "test1" => <<__XML__, Math::BigInt->new(12));
<test1>12</test1>
__XML__

test_rw($schema, "test1" => <<__XML__, Math::BigInt->new($some_big1));
<test1>$some_big1</test1>
__XML__

test_rw($schema, "test2" => <<__XML__, Math::BigInt->new(42));
<test2>42</test2>
__XML__

test_rw($schema, "test2" => <<__XML__, Math::BigInt->new($some_big1));
<test2>$some_big1</test2>
__XML__

# limit to huge maxInclusive

my $error = reader_error($schema, test2 => <<__XML__);
<test2>$some_big2</test2>
__XML__

is($error, 'too large inclusive 243587092790745290879, max 12432156239876121237 at {http://test-types}test2#facet');

$error = writer_error($schema, test2 => Math::BigInt->new($some_big2));
is($error, 'too large inclusive 243587092790745290879, max 12432156239876121237 at {http://test-types}test2#facet');

#
## Big defaults
#

my %t31 = (t3a => Math::BigInt->new(12), t3b => 13);
test_rw($schema, "test3" => <<__XML__, \%t31);
<test3><t3a>12</t3a><t3b>13</t3b></test3>
__XML__

my %t32 = (t3a => 14, t3b => Math::BigInt->new(15));
my %t33 = (t3a => Math::BigInt->new(14), t3b => 15);
test_rw($schema, test3 => <<__XML__, \%t33, <<__XML__, \%t32);
<test3><t3a>14</t3a><t3b>15</t3b></test3>
__XML__
<test3><t3a>14</t3a><t3b>15</t3b></test3>
__XML__

my %t34 = (t3a => Math::BigInt->new(10), t3b => 11);
test_rw($schema, test3 => <<__XML__, \%t34, <<__XML__, {t3b => 16});
<test3 />
__XML__
<test3><t3b>16</t3b></test3>
__XML__

#
## Big fixed
#

my $bi4 = Math::BigInt->new(79);
test_rw($schema, test4 => <<__XML__, {t4 => $bi4}, <<__XML__, {t4 => $bi4});
<test4><t4>79</t4></test4>
__XML__
<test4><t4>79</t4></test4>
__XML__
