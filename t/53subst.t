#!/usr/bin/perl
# SubstitutionGroups

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 21 + ($skip_dumper ? 0 : 18);
my $TestNS2 = "http://second-ns";

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">

<element name="head" type="string" abstract="true" />

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1" type="int"  />
      <element ref="one:head"        />
      <element name="t3" type="int"  />
    </sequence>
  </complexType>
</element>

<!-- more schemas below -->
</schema>
__SCHEMA__

ok(defined $schema);

my @errors;
push @run_opts, invalid => sub {no warnings; push @errors, "$_[2] ($_[1])"};

eval {
test_rw($schema, "test1" => <<__XML__, [1]);
<test1><t1>42</t1><t2>43</t2><t3>44</t3></test1>
__XML__
};

like($@, qr/no substitution.*found/);
ok(!@errors);

$schema->importDefinitions( <<__EXTRA__ );
<!-- alternatives in same namespace -->
<schemas>

<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">

<!-- this is not an extension of head's "string" but easier to recognize -->
<element name="alt1" substitutionGroup="one:head">
  <complexType>
    <sequence>
      <element name="a1" type="int" />
    </sequence>
  </complexType>
</element>

</schema>

<!-- alternatives in other namespace -->
<schema targetNamespace="$TestNS2"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">
        xmlns:two="$TestNS2">

<element name="alt2" substitutionGroup="one:head">
  <complexType>
    <sequence>
      <element name="a2" type="int" />
    </sequence>
  </complexType>
</element>

</schema>

</schemas>
__EXTRA__

my %t1 = (t1 => 42, alt1 => {a1 => 43}, t3 => 44);
test_rw($schema, "test1" => <<__XML__, \%t1);
<test1><t1>42</t1><alt1><a1>43</a1></alt1><t3>44</t3></test1>
__XML__

my %t2 = (t1 => 45, alt2 => {a2 => 46}, t3 => 47);
test_rw($schema, "test1" => <<__XML__, \%t2);
<test1><t1>45</t1><alt2><a2>46</a2></alt2><t3>47</t3></test1>
__XML__
