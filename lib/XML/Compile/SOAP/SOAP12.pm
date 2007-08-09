use warnings;
use strict;

package XML::Compile::SOAP::SOAP12;
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile', syntax => 'SHORT';

my $base  = 'http://www.w3.org/2003/05';

my $role  = "$base/soap-envelope/role";
my %roles =
 ( NEXT     => "$role/next"
 , NONE     => "$role/none"
 , ULTIMATE => "$role/ultimateReceiver"
 );

=chapter NAME
XML::Compile::SOAP::SOAP12 - implementation of SOAP1.2

=chapter SYNOPSIS

=chapter DESCRIPTION
**WARNING** Implementation not finished: not usable!!

This module handles the SOAP protocol version 1.2.
See F<http://www.w3.org/TR/soap12/>).

=chapter METHODS

=section Constructors

=method new OPTIONS

=option  header_fault <anything>
=default header_fault error
SOAP1.1 defines a header fault type, which not present in SOAP 1.2,
where it is replaced by a C<notUnderstood> structure.

=default envelope_ns C<http://www.w3.org/2003/05/soap-envelope>
=default encoding_ns C<http://www.w3.org/2003/05/soap-encoding>

=option  rpc_ns      URI
=default rpc_ns      C<http://www.w3.org/2003/05/soap-rpc>
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $env = $args->{envelope_ns} ||= "$base/soap-envelope";
    my $enc = $args->{encoding_ns} ||= "$base/soap-encoding";
    $self->SUPER::init($args);

    my $rpc = $self->{rpc} = $args->{rpc} || "$base/soap-rpc";

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $schemas->importDefinitions($rpc);
    $self;
}

=section Accessors

=method rpcNS
=cut

sub rpcNS() {shift->{rpc}}

sub _writer($)
{   my ($self, $args) = @_;

    error __x"headerfault does only exist in SOAP1.1"
        if $args->{header_fault};

}

=method roleAbbreviation STRING
Translates actor abbreviations into URIs.  For SOAP1.2, defined are C<NEXT>,
C<NONE>, and C<ULTIMATE>.  Returns the unmodified STRING in all other cases.
=cut

sub roleAbbreviation($) { $roles{$_[1]} || $_[1] }

1;
