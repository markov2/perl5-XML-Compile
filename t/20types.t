#!/usr/bin/perl

use warnings;
use strict;

use File::Spec;

use lib 'lib';
use XML::Compile::Schema;

use Test::More tests => 22;

our $xmlfile = File::Spec->rel2abs('xsd/2001-XMLSchema.xsd');

ok(-r $xmlfile,  'find demo file');

my $parser = XML::LibXML->new;
my $doc    = $parser->parse_file($xmlfile);
ok(defined $doc, 'parsing schema');
isa_ok($doc, 'XML::LibXML::Document');

my $schema  = XML::Compile::Schema->new($doc);
ok(defined $schema);

my @types  = $schema->types(namespace => 'EXPANDED');
cmp_ok(scalar(@types), '==', 138);
my $random = (sort @types)[42];
is($random, 'http://www.w3.org/2001/XMLSchema#duration');

my @types2 = $schema->types(namespace => 'PREFIXED');
cmp_ok(scalar(@types2), '==', 138);
my $random2 = (sort @types2)[42];
is($random2, 'duration');

my @types3 = $schema->types(namespace => 'LOCAL');
cmp_ok(scalar(@types3), '==', 138);
my $random3 = (sort @types3)[42];
is($random3, 'duration');

my $types4 = $schema->typesPerNamespace;
ok(defined $types4, 'typesPerNamespace');
cmp_ok(scalar(keys %$types4), '==', 1);
my $key = (keys %$types4)[0];
is($key, 'http://www.w3.org/2001/XMLSchema');
ok(exists $types4->{$key}{duration});

#

my $t = $schema->types;
ok(defined $t,   'counting detected types');
cmp_ok(scalar(keys %$t), '==', 138);
my %t;

$t{$_->{type}}++ for values %$t;
cmp_ok(scalar(keys %t), '==', 5);

cmp_ok($t{simpleType},     '==', 55);
cmp_ok($t{complexType},    '==', 28);
cmp_ok($t{group},          '==', 12);
cmp_ok($t{attributeGroup}, '==', 2);
cmp_ok($t{element},        '==', 41);
