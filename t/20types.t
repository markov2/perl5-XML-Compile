#!/usr/bin/perl

use warnings;
use strict;

use File::Spec;

use lib 'lib', 't';
use XML::Compile::Schema;
use TestTools;

use Test::More tests => 17;

our $xmlfile = File::Spec->rel2abs('xsd/2001-XMLSchema.xsd');

ok(-r $xmlfile,  'find demo file');

my $parser = XML::LibXML->new;
my $doc    = $parser->parse_file($xmlfile);
ok(defined $doc, 'parsing schema');
isa_ok($doc, 'XML::LibXML::Document');

my $schema  = XML::Compile::Schema->new($doc);
ok(defined $schema);

my $namespaces  = $schema->namespaces;
isa_ok($namespaces, 'XML::Compile::Schema::NameSpaces');

my @ns      = $namespaces->list;
cmp_ok(scalar(@ns), '==', 1, 'one target namespace');
my $ns = shift @ns;
is($ns, $SchemaNS);

my @schemas = $namespaces->namespace($ns);
ok(scalar(@schemas), 'found ns');

@schemas
   or die "no schemas, so no use to continue";

my $list = '';
open OUT, '>', \$list or die $!;
$_->printIndex(\*OUT) for @schemas;
close OUT;

my @types   = sort split /\n/, $list;
cmp_ok(scalar(@types), '==', 147);

my $random = (sort @types)[42];
is($random, '      element redefine');

my %t;
foreach (@types)
{   my ($type, $name) = split;
    $t{$type}++;
}

cmp_ok(scalar(keys %t), '==', 6);

cmp_ok($t{simpleType},     '==', 55);
cmp_ok($t{complexType},    '==', 35);
cmp_ok($t{group},          '==', 12);
cmp_ok($t{attributeGroup}, '==',  2);
cmp_ok($t{element},        '==', 41);
cmp_ok($t{notation},       '==',  2);
