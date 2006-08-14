#!/usr/bin/perl
# test element default

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 30;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1a" type="integer" default="10"/>
      <element name="t1b" type="integer" default="10"/>
    </sequence>
  </complexType>
</element>

<element name="test2">
  <complexType>
    <sequence>
      <element name="t2a" type="string" default="foo" />
      <element name="t2b" type="string" />
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts
 , sloppy_integers => 1
 , invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef}
 ;

##
### Integers
##  Big-ints are checked in 49big.t

run_test($schema, "test1" => <<__XML__, {t1a => 11, t1b => 12});
<test1><t1a>11</t1a><t1b>12</t1b></test1>
__XML__
ok(!@errors);

# insert default in hash, but not when producing XML
run_test($schema, "test1" => <<__XML__, {t1a => 10, t1b => 13}, <<__XML__, {t1b => 13});
<test1><t1b>13</t1b></test1>
__XML__
<test1><t1b>13</t1b></test1>
__XML__
ok(!@errors);

##
### Strings
##

my %t21 = (t2a => 'foo', t2b => 'bar');
my %t22 = (t2b => 'bar');  # do not complete default in XML output
run_test($schema, "test2" => <<__XML__, \%t21, <<__XML__, \%t22);
<test2><t2b>bar</t2b></test2>
__XML__
<test2><t2b>bar</t2b></test2>
__XML__
