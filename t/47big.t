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
   {   plan tests => 53;
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

<simpleType name="t2">
  <restriction base="integer">
    <minInclusive value="40" />
    <maxInclusive value="$some_big1" />
  </restriction>
</simpleType>

<element name="test1" type="me:t1" />

<element name="test2" type="me:t2" />

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
