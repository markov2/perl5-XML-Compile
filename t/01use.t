#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use Test::More tests => 13;

# The versions of the following packages are reported to help understanding
# the environment in which the tests are run.  This is certainly not a
# full list of all installed modules.
my @show_versions =
 qw/Test::More
    Test::Deep
    XML::LibXML
    Math::BigInt
   /;

foreach my $package (@show_versions)
{   eval "require $package";

    my $report
      = !$@                    ? "version ". ($package->VERSION || 'unknown')
      : $@ =~ m/^Can't locate/ ? "not installed"
      : "reports error";

    warn "$package $report\n";
}

require_ok('XML::Compile');
require_ok('XML::Compile::Schema');
require_ok('XML::Compile::Schema::BuiltInFacets');
require_ok('XML::Compile::Schema::BuiltInTypes');
require_ok('XML::Compile::Schema::Instance');
require_ok('XML::Compile::Schema::NameSpaces');
require_ok('XML::Compile::Schema::Specs');
require_ok('XML::Compile::Schema::Translate');
require_ok('XML::Compile::Schema::XmlReader');
require_ok('XML::Compile::Schema::XmlWriter');
require_ok('XML::Compile::Schema::Template');
require_ok('XML::Compile::WSDL');
require_ok('XML::Compile::SOAP::Operation');
