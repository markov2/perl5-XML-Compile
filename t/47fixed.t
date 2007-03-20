#!/usr/bin/perl
# test use element fixed

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 57 + ($skip_dumper ? 0 : 45);

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

my @errors;
push @run_opts
 , invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef}
 ;

##
### Fixed Integers
##  Big-ints are checked in 49big.t

test_rw($schema, test1 => <<__XML__, {t1a => 'not-changeable', t1c => 42});
<test1 t1c="42"><t1a>not-changeable</t1a></test1>
__XML__
ok(!@errors);

my %t1b = (t1a => 'not-changeable', t1b => 12, t1c => 42);
test_rw($schema, test1 => <<__XML__, \%t1b, <<__EXPECT__, {t1b => 13});
<test1><t1b>12</t1b></test1>
__XML__
<test1 t1c="42"><t1a>not-changeable</t1a><t1b>13</t1b></test1>
__EXPECT__

is(shift @errors, "value fixed to 'not-changeable' ()");
is(shift @errors, "attr value fixed to '42' ()");
is(shift @errors, "value fixed to 'not-changeable' ()");
is(shift @errors, "attr value fixed to '42' ()");
ok(!@errors);

#
# Optional fixed integers
#

my %t2a = (t2a => 14, t2b => 13);
test_rw($schema, test2 => <<__XML__, \%t2a);
<test2 t2a="14" t2b="13"/>
__XML__
ok(!@errors);

my %t2b     = (t2a => 15, t2b => 13);
my %t2b_err = (t2a => 16, t2b => 12);
test_rw($schema, test2 => <<__XML__, \%t2b, <<__EXPECT__, \%t2b_err);
<test2 t2a="15" t2b="12"/>
__XML__
<test2 t2a="16" t2b="13"/>
__EXPECT__
is(shift @errors, "attr value fixed to '13' (12)");
is(shift @errors, "attr value fixed to '13' (12)");
ok(!@errors);

my %t2c     = (t2a => 17);
test_rw($schema, test2 => <<__XML__, \%t2c);
<test2 t2a="17"/>
__XML__
ok(!@errors);
