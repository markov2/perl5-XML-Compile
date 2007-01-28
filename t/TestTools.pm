use warnings;
use strict;

package TestTools;
use base 'Exporter';

use XML::LibXML;
use Test::More;
use Test::Deep   qw/cmp_deeply/;

$ENV{SCHEMA_DIRECTORIES} = 'xsd';

our @EXPORT = qw/
 $TestNS
 $SchemaNS
 @run_opts
 reader
 writer
 compare_xml
 test_rw
 templ_xml
 templ_perl
 /;

our $TestNS   = 'http://test-types';
our $SchemaNS = 'http://www.w3.org/2001/XMLSchema';
our @run_opts = ();

sub reader($$$$)
{   my ($schema, $test, $type, $xml) = @_;

    my $read_t = $schema->compile
     ( READER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , @run_opts
     );

    ok(defined $read_t, "reader element $test");
    cmp_ok(ref($read_t), 'eq', 'CODE');

    $read_t->($xml);
}

sub writer($$$$$)
{   my ($schema, $doc, $test, $type, $data) = @_;

    my $write_t = $schema->compile
     ( WRITER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , @run_opts
     );

    ok(defined $write_t, "writer element $test");
    defined $write_t or next;

    cmp_ok(ref($write_t), 'eq', 'CODE');

    my $tree = $write_t->($doc, $data);
    ok(defined $tree);
    defined $tree or return;

    isa_ok($tree, 'XML::LibXML::Node');
    $tree;
}

sub test_rw($$$$;$$)
{   my ($schema, $test, $xml, $hash, $expect, $h2) = @_;

    my $type = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $h = reader($schema, $test, $type, $xml);

#use Data::Dumper;
#warn Dumper $h;
    unless(defined $h)   # avoid crash of is_deeply
    {   if(defined $expect && length($expect))
        {   ok(0, "failure: nothing read from XML");
        }
        else
        {   ok(1, "empty result");
        }
        return;
    }

#use Data::Dumper;
#warn Dumper $h, $hash;
    cmp_deeply($h, $hash, "from xml");

    # Write testing

    my $doc = XML::LibXML->createDocument('test doc', 'utf-8');
    isa_ok($doc, 'XML::LibXML::Document');

    my $tree = writer($schema, $doc, $test, $type, defined $h2 ? $h2 : $h);
    compare_xml($tree, $expect || $xml);
}

sub compare_xml($$)
{   my ($tree, $expect) = @_;
    my $dump = $tree->toString;

    if($dump =~ m/\n|\s\s/)
    {   # output expects superfluous blanks
        $expect =~ s/\n\z//;
    }
    else
    {   for($expect)
        {   s/\>\s+/>/gs;
            s/\s+\</</gs;
            s/\>\s+\</></gs;
            s/\s*\n\s*/ /gs;
            s/\s{2,}/ /gs;
            s/\s+\z//gs;
        }
    }
    is($dump, $expect);
}

sub templ_xml($$$@)
{   my ($schema, $test, $xml, @opts) = @_;

    # Read testing
    my $abs = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $output = $schema->template
     ( XML                => $abs
     , include_namespaces => 0
     , @opts
     );

   is($output."\n", $xml, "xml for $test");
}

sub templ_perl($$$@)
{   my ($schema, $test, $perl, @opts) = @_;

    # Read testing
    my $abs    = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $output = $schema->template
     ( PERL               => $abs
     , include_namespaces => 0
     , @opts
     );

    is($output, $perl, "perl for $test");
}

1;
