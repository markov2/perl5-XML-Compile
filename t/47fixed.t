#!/usr/bin/perl
# test use element fixed

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 25;

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

</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts
 , invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"; undef}
 ;

##
### Integers
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
