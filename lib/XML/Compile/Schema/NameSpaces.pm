
use warnings;
use strict;

package XML::Compile::Schema::NameSpaces;

use Carp;

=chapter NAME

XML::Compile::Schema::NameSpaces - Connect name-spaces from schemas

=chapter SYNOPSIS

 # Used internally by XML::Compile::Schema
 my $nss = XML::Compile::Schema::NameSpaces->new;
 $nss->add($schema);

=chapter DESCRIPTION

This module keeps overview on a set of schema's.

=chapter METHODS

=section Constructors

=method new OPTIONS
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{tns} = {};
    $self;
}

=section Accessors

=method list
Returns the list of name-space names defined until now.
=cut

sub list() { keys %{shift->{tns}} }

=method namespace URI
Returns a list of M<XML::Compile::Schema::Instance> objects which have
the URI as target namespace.
=cut

sub namespace($)
{   my $self = shift;
    my $nss  = $self->{tns}{(shift)};
    $nss ? @$nss : ();
}

=method add SCHEMA
Adds the M<XML::Compile::Schema::Instance> object to the internal
knowledge of this object.
=cut

sub add($)
{   my ($self, $schema) = @_;
    my $tns = $schema->targetNamespace;
    unshift @{$self->{tns}{$tns}}, $schema;
    $schema;
}

=method schemas URI
We need the name-space; when it is lacking then import must help, but that
must be called explictly.
=cut

sub schemas($)
{   my ($self, $ns) = @_;
    $self->namespace($ns);
}

=method allSchemas
Returns a list of all known schema instances.
=cut

sub allSchemas()
{   my $self = shift;
    map {$self->schemas($_)} $self->list;
}

=method find KIND, ADDRESS|(URI,NAME)
Lookup the definition for the specified KIND of definition: the name
of a gloabl element, gloabl attribute, attributeGroup or model group.
The ADDRESS is constructed as C< {uri}name > or as seperate URI and NAME.
=cut

sub find($$;$)
{   my ($self, $kind, $ns, $name) = @_;
    my $label  = $ns;
    if(defined $name) { $label = "{$ns}$name" }
    elsif($label =~ m/^\s*\{(.*)\}(.*)/) { ($ns, $name) = ($1, $2) }
    else { return undef  } 

    foreach my $schema ($self->schemas($ns))
    {   my $def = $schema->find($kind, $label);
        return $def if defined $def;
    }

    undef;
}

=method findSgMembers ADDRESS|(URI,NAME)
Lookup the substitutionGroup alternatives for a specific element,
which is an ADDRESS of form C< {uri}name > or as seperate URI and NAME.
Returned is a list of parse nodes (HASHes)
=cut

sub findSgMembers($;$)
{   my ($self, $ns, $name) = @_;
    my $label  = $ns;
    if(defined $name) { $label = "{$ns}$name" }
    elsif($label =~ m/^\s*\{(.*)\}(.*)/) { ($ns, $name) = ($1, $2) }
    else { return undef  } 

    map {$_->substitutionGroupMembers($label)}
        $self->allSchemas;
}

=method findID ADDRESS|(URI,ID)
Lookup the definition for the specified id, which is constructed as
C< uri#id > or as seperate URI and ID.
=cut

sub findID($;$)
{   my ($self, $ns, $name) = @_;
    my $label  = $ns;
    if(defined $name) { $label = "$ns#$name" }
    elsif($label =~ m/\#/) { ($ns, $name) = split /\#/,$label,2 }
    else { return undef  } 

    foreach my $schema ($self->schemas($ns))
    {   my $def = $schema->id($label);
        return $def if defined $def;
    }

    undef;
}

1;
