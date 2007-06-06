use warnings;
use strict;

package XML::Compile::SOAP::SOAP11;
use base 'XML::Compile::SOAP';

my $base       = 'http://schemas.xmlsoap.org/soap';
my $actor_next = "$base/actor/next";

=chapter NAME
XML::Compile::SOAP::SOAP11 - implementation of SOAP1.1

=chapter SYNOPSIS

=chapter DESCRIPTION
**WARNING** Implementation not finished: not usable!!

This module handles the SOAP protocol version 1.1.
See F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>).
The implementation tries to behave like described in
F<http://www.ws-i.org/Profiles/BasicProfile-1.0.html>

=chapter METHODS

=section Constructors

=method new OPTIONS
To simplify the URIs of the actors, as specified with the C<destination>
option, you may use the STRING C<NEXT>.  It will be replaced by the
right URI.

=default envelope_ns C<http://schemas.xmlsoap.org/soap/envelope/>
=default encoding_ns C<http://schemas.xmlsoap.org/soap/encoding/>
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $env = $args->{envelope_ns} ||= "$base/envelope/";
    my $enc = $args->{encoding_ns} ||= "$base/encoding/";
    $self->SUPER::init($args);

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $self;
}

=method compile ('CLIENT'|'SERVER'),('INPUT'|'OUTPUT'), OPTIONS
=option  headerfault ENTRIES
=default headerfault []
ARRAY of simple name with element references, for all expected
faults.  There can be unexpected faults, which will not get
decoded automatically.
=cut

#sub compile

sub _writer_header_env($$$$)
{   my ($self, $code, $allns, $understand, $actors) = @_;
    $understand || $actors or return $code;

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

    # Cannot precompile everything, because $doc is unknown
    my $ucode;
    if($understand)
    {   my $u_w = $self->{soap11_u_w} ||=
          $schema->compile
            ( WRITER => "{$envns}mustUnderstand"
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        $ucode =
        sub { my $el = $code->(@_) or return ();
              my $un = $u_w->($_[0], 1);
              $el->addChild($un) if $un;
              $el;
            };
    }
    else {$ucode = $code}

    if($actors)
    {   $actors =~ s/\b(\S+)\b/$self->roleAbbreviation($1)/ge;

        my $a_w = $self->{soap11_a_w} ||=
          $schema->compile
            ( WRITER => "{$envns}actor"
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        return
        sub { my $el  = $ucode->(@_) or return ();
              my $act = $a_w->($_[0], $actors);
              $el->addChild($act) if $act;
              $el;
            };
    }

    $ucode;
}

sub _writer($)
{   my ($self, $args) = @_;
    $args->{prefix_table}
     = [ ''         => 'do not use'
       , 'SOAP-ENV' => $self->envelopeNS
       , 'SOAP-ENC' => $self->encodingNS
       , xsd        => 'http://www.w3.org/2001/XMLSchema'
       , xsi        => 'http://www.w3.org/2001/XMLSchema-instance'
       ];

    $self->SUPER::_writer($args);
}

=method roleAbbreviation STRING
Translates actor abbreviations into URIs.  The only one defined for
SOAP1.1 is C<NEXT>.  Returns the unmodified STRING in all other cases.
=cut

sub roleAbbreviation($) { $_[1] eq 'NEXT' ? $actor_next : $_[1] }

1;
