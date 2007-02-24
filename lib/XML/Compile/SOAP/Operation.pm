use warnings;
use strict;

package XML::Compile::SOAP::Operation;

use Carp;
use List::Util  'first';

my $soap1 = 'http://schemas.xmlsoap.org/wsdl/soap/';
my $http1 = 'http://schemas.xmlsoap.org/soap/http';

=chapter NAME

XML::Compile::SOAP::Operation - defines a possible SOAP interaction

=chapter SYNOPSIS

=chapter DESCRIPTION

=chapter METHODS

=section Constructors

=method new OPTIONS

The OPTIONS are all collected from the WSDL description by
M<XML::Compile::WSDL::operation()>.  End-users should not attempt to
initiate this object directly.

=requires service  HASH
=requires port     HASH
=requires binding  HASH
=requires portType HASH
=requires schemas  M<XML::Compile::Schema> object

=requires portOperation HASH

=option   bindOperation HASH
=default  bindOperation C<undef>

=option   protocol URI|'HTTP'
=default  protocol 'HTTP'
C<HTTP> is short for C<http://schemas.xmlsoap.org/soap/http>, which
is a constant to indicate that transport should use the HyperText
Transfer Protocol.

=option   soapStyle 'document'|'rpc'
=default  soapStyle 'document'
=cut

sub new(@)
{   my $class = shift;
    (bless {@_}, $class)->init;
}

sub init()
{   my $self = shift;

    # autodetect namespaces used
    my $soapns = $self->{soap_ns}
      = exists $self->port->{ "{$soap1}address" } ? $soap1
      : croak "ERROR: soap namespace not supported";

    $self->schemas->importData($soapns);

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.
    my @order    = @{$self->portOperation->{_ELEMENT_ORDER}};
    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq 'input';
        $first_out = $i if !defined $first_out && $order[$i] eq 'output';
    }

    $self->{kind}
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    $self->{protocol}  ||= 'HTTP';
    $self->{soapStyle} ||= 'document';
    $self;
}

=section Accessors
=method service
=method port
=method bindings
=method portType
=method schemas
=method portOperation
=method bindOperation
=cut

sub service()  {shift->{service}}
sub port()     {shift->{port}}
sub binding()  {shift->{binding}}
sub portType() {shift->{portType}}
sub schemas()  {shift->{schemas}}

sub portOperation() {shift->{portOperation}}
sub bindOperation() {shift->{bindOperation}}

=section Use

=method soapNamespace
=cut

sub soapNamespace() {shift->{soap_ns}}

=method endPointAddresses
Returns the list of alternative URLs for the end-point, which should
be defined within the service's port declaration.
=cut

sub endPointAddresses()
{   my $self = shift;
    return @{$self->{addrs}} if $self->{addrs};

    my $soapns   = $self->soapNamespace;
    my $addrtype = "{$soapns}address";

    my $addrxml  = $self->port->{$addrtype}
        or croak "ERROR: soap end-point address not found in service port.\n";

    my $addr_r   = $self->schemas->compile(READER => $addrtype);

    my @addrs    = map {$addr_r->($_)->{location}} @$addrxml;
    $self->{addrs} = \@addrs;
    @addrs;
}

=method canTransport PROTOCOL, STYLE
Returns a true value when the pair with URI of the PROTOCOL and
processing style (either C<document> (default) or C<rpc>) is
provided as soap binding.
=cut

sub canTransport($$)
{   my ($self, $proto, $style) = @_;
    my $trans = $self->{trans};

    unless($trans)
    {   # collect the transport information
        my $soapns   = $self->soapNamespace;
        my $bindtype = "{$soapns}binding";

        my $bindxml  = $self->binding->{$bindtype}
            or croak "ERROR: soap transport binding not found in binding.\n";

        my $bind_r   = $self->schemas->compile(READER => $bindtype);
  
        my @bindings = map {$bind_r->($_)} @$bindxml;
        $_->{style} ||= 'document' for @bindings;
        $self->{trans} = $trans = \@bindings;
    }

    my @proto = grep {$_->{transport} eq $proto} @$trans;
    @proto or return ();

    my ($action, $op_style) = $self->action;
    return $op_style eq $style if defined $op_style; # explicit style

    first {$_->{style} eq $style} @proto;            # the default style
}

=method action
Returns the C<soapAction> and C<style> attributes, when available.
=cut

sub action()
{   my $self   = shift;
    my $action = $self->{action};

    unless($action)
    {   # collect the action information
        my $soapns = $self->soapNamespace;
        my $optype = "{$soapns}operation";

        my @action;
        my $opxml = $self->bindOperation->{$optype};
        if($opxml)
        {   my $op_r   = $self->schemas->compile(READER => $optype);

            my $binding
             = @$opxml > 1
             ? first {$_->{style} eq $self->soapStyle} @$opxml
             : $opxml->[0];

            my $opdata = $op_r->($binding);
            @action    = @$opdata{ qw/soapAction style/ };
        }
        $action = $self->{action} = \@action;
    }

    @$action;
}

=method kind
This returns the type of operation this is.  There are four kinds, which
are returned as strings C<one-way>, C<request-response>, C<sollicit-response>,
and C<notification>.  The latter two are initiated by a server, the former
two by a client.
=cut

sub kind() {shift->{kind}}

=method prepare OPTIONS
Returns one CODE reference which handles the processing for this
operation.

You pass that CODE reference an input message of the correct
type, as pure Perl HASH structure.  An 'request-response' operation
will return then answer, or C<undef> in case of failure.  An 'one-way'
operation with return C<undef> in case of failure, and a true value
when successfull.

=option  role 'CLIENT'|'SERVER'
=default role 'CLIENT'
Of course, when you interact between two systems, then you need to
define whether you are the sender or receiver of the data.

=option  soapStyle 'document'||'rpc'
=default soapStyle M<new(soapStyle)>

=option  protocol  URI|'HTTP'
=default protocol  M<new(protocol)>
=cut

sub prepare(@)
{   my ($self, %args) = @_;
    my $role     = $args{role} || 'CLIENT';
    my $port     = $self->portOperation;
    my $bind     = $self->bindOperation;

# parsing of input and output wrong: both lists.  Schema parser gets
# confused by <choice><group><group>.  Needs a hook
    my @po_in    = @{$port->{input}  || []};
    my @po_out   = @{$port->{output} || []};
    my @po_fault = @{$port->{fault}  || []};
    my $bi_in    = $bind->{input};
    my $bi_out   = $bind->{output};
    my $bi_fault = $bind->{fault};

    my (@readers, @writers);
    if($role eq 'CLIENT')
    {   @readers = map {$self->_message_reader(\%args, $_, $bi_out)}
           @po_out;

        @writers = map {$self->_message_writer(\%args, $_, $bi_in)}
           @po_in;

        push @readers, map {$self->_message_reader(\%args, $_, $bi_fault)}
           @po_fault;
    }
    elsif($role eq 'SERVER')
    {   @readers = map {$self->_message_reader(\%args, $_, $bi_in)}
           @po_in;

        @writers = map {$self->_message_writer(\%args, $_, $bi_out)}
           @po_out;

        push @writers, map {$self->_message_reader(\%args, $_, $bi_fault)}
           @po_fault;
    }
    else
    {   croak "ERROR: WSDL role must be CLIENT or SERVER, not '$role'"; 
    }

    my $soapns  = $self->soapNamespace;
    my $addrs   = $self->endPointAddresses;

    my $proto   = $args{protocol}  || $self->{protocol}  || 'HTTP';
    $proto = $http1 if $proto eq 'HTTP';

    my $style   = $args{soapStyle} || $self->{soapStyle} || 'document';

    $self->canTransport($proto, $style)
        or croak "ERROR: transport $proto as $style not defined in WSDL";

    $proto eq $http1
        or die "SORRY: only transport of HTTP ($proto) implemented\n";

    $style eq 'document'
        or die "SORRY: only transport style 'document' implemented\n";

    # http requires soapAction
    my ($action, undef) = $self->soapAction;

    croak "ERROR: work in progress: implementation not finished";
}

sub _message_reader($$$)
{   my ($self, $args, $message, $bind) = @_;
    ();
}

sub _message_writer($$$)
{   my ($self, $args, $message, $bind) = @_;
    ();
}

1;

