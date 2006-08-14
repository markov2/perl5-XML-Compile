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
   else
   {   plan tests => 95;
   }
}

my $some_big1 = "124321562398761237";
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
    <element name="t4" type="integer" fixed="79" />
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts
 , sloppy_integers => 0
 , invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef}
 ;

##
### Integers
##

run_test($schema, "test1" => <<__XML__, Math::BigInt->new(12));
<test1>12</test1>
__XML__
ok(!@errors);

run_test($schema, "test1" => <<__XML__, Math::BigInt->new($some_big1));
<test1>$some_big1</test1>
__XML__
ok(!@errors);

run_test($schema, "test2" => <<__XML__, Math::BigInt->new(42));
<test2>42</test2>
__XML__
ok(!@errors);

run_test($schema, "test2" => <<__XML__, Math::BigInt->new($some_big1));
<test2>$some_big1</test2>
__XML__
ok(!@errors);

# limit to huge maxInclusive
run_test($schema, "test2" => <<__XML__, Math::BigInt->new($some_big1), <<__XML__,Math::BigInt->new($some_big2));
<test2>$some_big2</test2>
__XML__
<test2>$some_big1</test2>
__XML__
is(shift @errors, "too large inclusive, max $some_big1 ($some_big2)");
is(shift @errors, "too large inclusive, max $some_big1 ($some_big2)");
ok(!@errors);

#
## Big defaults
#

my %t31 = (t3a => Math::BigInt->new(12), t3b => 13);
run_test($schema, "test3" => <<__XML__, \%t31);
<test3><t3a>12</t3a><t3b>13</t3b></test3>
__XML__
ok(!@errors);

my %t32 = (t3a => 14, t3b => Math::BigInt->new(15));
my %t33 = (t3a => Math::BigInt->new(14), t3b => 15);
run_test($schema, test3 => <<__XML__, \%t33, <<__XML__, \%t32);
<test3><t3a>14</t3a><t3b>15</t3b></test3>
__XML__
<test3><t3a>14</t3a><t3b>15</t3b></test3>
__XML__
ok(!@errors);

my %t34 = (t3a => Math::BigInt->new(10), t3b => 11);
run_test($schema, test3 => <<__XML__, \%t34, <<__XML__, {t3b => 16});
<test3 />
__XML__
<test3><t3b>16</t3b></test3>
__XML__
ok(!@errors);

#
## Big fixed
#

my $bi4 = Math::BigInt->new(78);
my $bi4b = Math::BigInt->new(79);
run_test($schema, test4 => <<__XML__, {t4 => $bi4b}, <<__XML__, {t4 => $bi4});
<test4><t4>78</t4></test4>
__XML__
<test4><t4>79</t4></test4>
__XML__

is(shift @errors, "value fixed to '79' (78)");
is(shift @errors, "value fixed to '79' (78)");
ok(!@errors);
