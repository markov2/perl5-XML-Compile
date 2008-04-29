#!/usr/bin/perl
# test use element fixed

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 45;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1a" type="string" fixed="not-changeable" />
      <element name="t1b" type="int" minOccurs="0" />
    </sequence>
    <attribute name="t1c" type="int" fixed="42" />
  </complexType>
</element>

<element name="test2">
  <complexType>
    <attribute name="t2a" type="int" />
    <attribute name="t2b" type="int" fixed="13" use="optional" />
  </complexType>
</element>
</schema>
__SCHEMA__

ok(defined $schema);

##
### Fixed Integers
##  Big-ints are checked in 49big.t

test_rw($schema, test1 => <<__XML__, {t1a => 'not-changeable', t1c => 42});
<test1 t1c="42"><t1a>not-changeable</t1a></test1>
__XML__

my $error = reader_error($schema, test1 => <<__XML__);
<test1><t1b>12</t1b></test1>
__XML__
is($error, "element `t1a' with fixed value `not-changeable' missing at {http://test-types}test1/el(t1a)");

my %t1b = (t1b => 12, t1c => 42);
$error = writer_error($schema, test1 => \%t1b);
is($error, "required value for `t1a' missing at {http://test-types}test1");

my %t1c = (t1a => 'wrong', t1b => 12, t1c => 42);
$error = writer_error($schema, test1 => \%t1c);
is($error, "element `t1a' has value fixed to `not-changeable', got `wrong' at {http://test-types}test1/el(t1a)");

#
# Optional fixed integers
#

my %t2a = (t2a => 14, t2b => 13);
test_rw($schema, test2 => <<__XML__, \%t2a);
<test2 t2a="14" t2b="13"/>
__XML__

$error = reader_error($schema, test2 => <<__XML__);
<test2 t2a="15" t2b="12"/>
__XML__
is($error, "value of attribute `t2b' is fixed to `13', not `12' at {http://test-types}test2/\@t2b");

my %t2b     = (t2a => 15, t2b => 12);
$error = writer_error($schema, test2 => \%t2b);
is($error, "value of attribute `t2b' is fixed to `13', not `12' at {http://test-types}test2/\@t2b");

my %t2c     = (t2a => 17, t2b => 13);
test_rw($schema, test2 => <<__XML__, \%t2c);
<test2 t2a="17" t2b="13"/>
__XML__
