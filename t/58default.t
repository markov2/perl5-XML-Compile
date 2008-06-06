#!/usr/bin/perl
# test element default

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 38;

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
    <attribute name="t2c" type="int"    default="42" />
  </complexType>
</element>

<element name="test3">
  <complexType>
    <sequence>
      <element name="e3" type="me:t3" default="foo bar" />
    </sequence>
  </complexType>
</element>

<simpleType name="t3">
  <list itemType="token" />
</simpleType>

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
set_compile_defaults
   sloppy_integers => 1
 , invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef}
 ;

##
### Integers
##  Big-ints are checked in 49big.t

test_rw($schema, "test1" => <<__XML, {t1a => 11, t1b => 12});
<test1><t1a>11</t1a><t1b>12</t1b></test1>
__XML
ok(!@errors);

# insert default in hash, but not when producing XML
test_rw($schema, "test1" => <<__XML, {t1a => 10, t1b => 13}, <<__XML, {t1b => 13});
<test1><t1b>13</t1b></test1>
__XML
<test1><t1b>13</t1b></test1>
__XML
ok(!@errors);

##
### Strings
##

my %t21 = (t2a => 'foo', t2b => 'bar', t2c => '42');
my %t22 = (t2b => 'bar');  # do not complete default in XML output
test_rw($schema, "test2" => <<__XML, \%t21, <<__XML, \%t22);
<test2><t2b>bar</t2b></test2>
__XML
<test2><t2b>bar</t2b></test2>
__XML

##
### List
##

# bug-report rt.cpan.org#36093

my %t31 = (e3 => ['foo', 'bar']);
test_rw($schema, "test3" => <<__XML, \%t31, <<__XML, {});
<test3/>
__XML
<test3/>
__XML

test_rw($schema, "test3" => <<__XML, \%t31, <<__XML, {e3 => []});
<test3><e3></e3></test3>
__XML
<test3><e3></e3></test3>
__XML
