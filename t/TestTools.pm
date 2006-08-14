use warnings;
use strict;

package TestTools;
use base 'Exporter';

use XML::LibXML;
use Test::More;
use Test::Deep   qw/cmp_deeply/;

our @EXPORT = qw/
 $TestNS
 $SchemaNS
 @run_opts
 run_test
 /;

our $TestNS   = 'http://test-types';
our $SchemaNS = 'http://www.w3.org/2001/XMLSchema';
our @run_opts = ();

sub run_test($$$$;$$)
{   my ($schema, $test, $xml, $hash, $expect, $h2) = @_;

    # Read testing
    my $abs = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $read_t = $schema->compile
     ( READER             => $abs
     , check_values       => 1
     , include_namespaces => 0
     , @run_opts
     );

    ok(defined $read_t, "reader element $test");
    cmp_ok(ref($read_t), 'eq', 'CODE');

    my $h = $read_t->($xml);

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

    my $write_t = $schema->compile
     ( WRITER             => $abs
     , check_values       => 1
     , include_namespaces => 0
     , @run_opts
     );

    ok(defined $write_t, "writer element $test");
    defined $write_t or next;

    cmp_ok(ref($write_t), 'eq', 'CODE');

    my $doc = XML::LibXML->createDocument('test doc', 'utf-8');
    isa_ok($doc, 'XML::LibXML::Document');

    $h = $h2 if defined $h2;

    my $tree = $write_t->($doc, $h);
    ok(defined $tree);
    defined $tree or return;

    isa_ok($tree, 'XML::LibXML::Node');
    $expect ||= $xml;
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

1;
