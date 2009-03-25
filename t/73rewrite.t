#!/usr/bin/perl
# Test key rewrite

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;
#use Log::Report mode => 3;

use Test::More tests => 39;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema
   targetNamespace="$TestNS"
   xmlns="$SchemaNS"
   xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1-E1" type="int"/>
      <element name="t1E2"  type="int"/>
      <element name="t1-e3" type="int"/>
    </sequence>
  </complexType>
</element>

<!-- to be used in substitutionGroup tests-->
<element name="t2a" type="int" />
<element name="t2b" substitutionGroup="me:t2a" />
<element name="test2">
  <complexType>
    <sequence>
      <element ref="me:t2a" />
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

### stacked rewrites

my %rewrite_table = ( 't1-e3' => 'Tn3' );
sub rewrite_dash { $_[1] =~ s/\-/_/g; $_[1] };
sub rewrite_lowercase { lc $_[1] }

set_compile_defaults
    elements_qualified => 'NONE'
  , key_rewrite => [ \%rewrite_table, \&rewrite_dash, \&rewrite_lowercase ];

test_rw($schema, test1 => <<__XML, {t1_e1 => 42, t1e2 => 43, tn3 => 44});
<test1>
  <t1-E1>42</t1-E1>
  <t1E2>43</t1E2>
  <t1-e3>44</t1-e3>
</test1>
__XML

### pre-defined simplify

set_compile_defaults
    elements_qualified => 'NONE'
  , key_rewrite        => 'SIMPLIFIED';

test_rw($schema, test1 => <<__XML, {t1_e1 => 45, t1e2 => 46, t1_e3 => 47});
<test1>
  <t1-E1>45</t1-E1>
  <t1E2>46</t1E2>
  <t1-e3>47</t1-e3>
</test1>
__XML

### pre-defined prefixed

set_compile_defaults
    elements_qualified => 'NONE'
  , key_rewrite        => 'PREFIXED'
  , prefixes           => [ me => $TestNS ]
  , elements_qualified => 1
  , include_namespaces => 1;

my %t3 = ('me_t1-E1' => 50, 'me_t1E2' => 51, 'me_t1-e3' => 52);
test_rw($schema, test1 => <<__XML, \%t3);
<me:test1 xmlns:me="$TestNS">
  <me:t1-E1>50</me:t1-E1>
  <me:t1E2>51</me:t1E2>
  <me:t1-e3>52</me:t1-e3>
</me:test1>
__XML

### example from the manual-page

set_compile_defaults
    key_rewrite => [ qw/PREFIXED SIMPLIFIED/ ]
  , prefixes => [ mine => $TestNS ]
  , elements_qualified => 'ALL';

my $r4 = reader_create $schema, 'changed prefix', "{$TestNS}test1";
my $x4 = $r4->( <<__XML );
<test1 xmlns="$TestNS">
  <t1-E1>60</t1-E1>
  <t1E2>61</t1E2>
  <t1-e3>62</t1-e3>
</test1>
__XML

is_deeply($x4, {mine_t1_e1 => 60, mine_t1e2 => 61, mine_t1_e3 => 62});

### substitutionGroup

set_compile_defaults
    key_rewrite => sub { uc $_[1] }
  , include_namespaces => 1
  , elements_qualified => 'ALL';

test_rw($schema, test2 => <<__XML, {T2A => 70});
<test2 xmlns="$TestNS">
  <t2a>70</t2a>
</test2>
__XML

test_rw($schema, test2 => <<__XML, {T2B => 71});
<test2 xmlns="$TestNS">
  <t2b>71</t2b>
</test2>
__XML

is($schema->template( PERL => "{$TestNS}test2"
                    , key_rewrite => sub {uc $_[1]}, skip_header => 1)
                    , <<__TEMPL);
# xmlns:          http://test-types

{ # sequence of T2A

  # substitutionGroup
  # {http://test-types}t2a:
  #   T2A  T2B
  T2A => "{ T2A => {...} }", }
__TEMPL
