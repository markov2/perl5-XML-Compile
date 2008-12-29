use warnings;
use strict;

package XML::Compile::Iterator;

use XML::Compile::Util  qw/pack_type type_of_node/;
use Log::Report 'xml-compile', syntax => 'SHORT';

=chapter NAME

XML::Compile::Iterator - reduce view on a node tree

=chapter SYNOPSIS

=chapter DESCRIPTION

It would have been nice to be able to use M<XML::LibXML::Iterator>, but
on the moment of this writing, that module is not maintained.  Besides,
this implementation of the iterator is more specific for our purpose.
The main user for this object currently is M<XML::Compile::Schema::Translate>.

=chapter METHODS

=section Constructors

=c_method new NODE, PATH, FILTER,
The NODE is a M<XML::LibXML::Node> object, of which the direct childs
are inspected.

The FILTER a CODE reference which is called for each child node.
The only paramter is the parent NODE, and then it must return
either true or false.  In case of true, the node is selected.
The FILTERS is applied to all childs of the NODE once, when the
first child is requested by the program.
=cut

sub new($@)
{   my ($class, $node, $path, $filter) = splice @_, 0, 4;
    (bless {}, $class)
      ->init( { node => $node, filter => $filter, path => $path, @_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{node}   = delete $args->{node}
        or panic "no node specified";

    $self->{filter} = delete $args->{filter}
        or panic "no filter specified";

    $self->{path}   = delete $args->{path}
        or panic "no path specified";

    $self->{current} = 0;
    $self;
}

=method descend [NODE, [PATH, [FILTER]]]
The NODE is a child of the node handled by the iterator where this
method is called upon.  Without explicit NODE, the current node is used.
Returned is a new M<XML::Compile::Iterator> object.  The new iterator
will use the same FILTER as the parent iterator by default.  The internal
administered path with be extended with the PATH.

=cut

sub descend(;$$$)
{   my ($self, $node, $p, $filter) = @_;
    $node  ||= $self->currentChild;
    defined $node or return undef;

    my $path = $self->path;
    $path   .= '/'.$p if defined $p;

    (ref $self)->new
      ($node, $path, ($filter || $self->{filter}));
}

=section Attributes

=method node
Returns the M<XML::LibXML::Node> node of which the childs are walked
through.
=cut

sub node()   {shift->{node}}

=method filter
Returns the CODE reference which is used to select the nodes.
=cut

sub filter() {shift->{filter}}

=method path
The path represents the location where the node is, like a symbolic
link, how you got there.
=cut

sub path() {shift->{path}}

=section Scanning

=method childs
Returns the child nodes which fulfil the filter requirements.  In LIST
context as list, in SCALAR context as reference to an ARRAY.
=cut

sub childs()
{   my $self = shift;
    my $ln   = $self->{childs};
    unless(defined $ln)
    {   my $filter = $self->filter;
        $ln = $self->{childs}
            = [ grep {$filter->($_)} $self->node->childNodes ];
    }
    wantarray ? @$ln : $ln;
}

=method currentChild
Returns the current child node.
=cut

sub currentChild() { $_[0]->childs->[$_[0]->{current}] }

=method firstChild
Returns the first child node.  Does not change the current position.
=cut

sub firstChild() {shift->childs->[0]}

=method lastChild
Returns the last child node which fulfills the requirements.
Does not change the current position.
=cut

sub lastChild()
{   my $list = shift->childs;
    @$list ? $list->[-1] : undef;   # avoid error on empty list
}

=method nextChild
Returns the next child when available, otherwise C<undef>.
=cut

sub nextChild()
{   my $self = shift;
    my $list = $self->childs;
    $self->{current} < @$list ? $list->[ ++$self->{current} ] : undef;
}

=method previousChild
Returns the previous child when available, otherwise C<undef>.
=cut

sub previousChild()
{   my $self = shift;
    my $list = $self->childs;
    $self->{current} > 0 ? $list->[ --$self->{current} ] : undef;
}

=method nrChildren
Returns the number of childnodes which fulfill the restriction.
=cut

sub nrChildren()
{   my $list = shift->childs;
    scalar @$list;
}

=section simplify XML node access

=method nodeType
Returns the type of the M<node()>, or the empty string.
=cut

sub nodeType() { type_of_node(shift->node) || '' }

=method nodeLocal
Returns the local name of the M<node()>, or the empty string.
=cut

sub nodeLocal()
{   my $node = shift->node or return '';
    $node->localName;
}

=method textContent
Returns the textContent of the M<node()>, or undef.
=cut

sub textContent()
{   my $node = shift->node or return undef;
    $node->textContent;
}

=method currentType
Returns the type of the M<currentChild()>, or the empty string.
=cut

sub currentType() { type_of_node(shift->currentChild) || '' }

=method currentLocal
Returns the local name of the M<currentChild()>, or the empty string.
=cut

sub currentLocal()
{   my $current = shift->currentChild or return '';
    $current->localName;
}

=method currentContent
Returns the textContent of the M<currentChild()> node, or undef.
=cut

sub currentContent()
{   my $current = shift->currentChild or return undef;
    $current->textContent;
}

1;
