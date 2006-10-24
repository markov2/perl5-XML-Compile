
package XML::Compile::Schema::Template;

use XML::Compile::Schema::XmlWriter;

use strict;
use warnings;
no warnings 'once';

=chapter NAME

XML::Compile::Schema::Template - bricks to create an XML or HASH example

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 print $schema->template(XML  => $type, ...);
 print $schema->template(HASH => $type, ...);

=chapter DESCRIPTION
The translator understands schema's, but does not encode that into
actions.

=cut

BEGIN {
   no strict 'refs';
   *$_ = *{"XML::Compile::Schema::XmlWriter::$_"}
      for qw/tag_qualified tag_unqualified wrapper_ns/;
}

sub wrapper() { my $proc = shift; sub { $proc->() } }

#
## Element
#

sub element_repeated
{   my ($path, $args, $ns, $childname, $do, $min, $max) = @_;
    my $err  = $args->{err};
    sub { ( occur => "$childname $min <= # <= $max times"
          ,  $do->()
          );
        };
}

sub element_array
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { ( occur => "$childname any number"
          ,  $do->()
          );
        };
}

sub element_obligatory
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { ( occur => "$childname is required"
          ,  $do->()
          )
        };
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
    my $err  = $args->{err};
    $fixed   = $fixed->example ;

    sub { ( occur => "$childname fixed to example $fixed"
          ,  $do->()
          );
        };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { ( occur => "$childname is nillable"
          ,  $do->()
          );
        };
}

sub element_default
{   my ($path, $args, $ns, $childname, $do, $min, $max, $default) = @_;
    sub { ( occur => "$childname defaults to example $default"
          ,  $do->()
          );
        }
}

sub element_optional
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { ( occur => "$childname is optional"
          ,  $do->()
          );
        };
}

#
# complexType/ComplexContent
#

sub create_complex_element
{   my ($path, $args, $tag, @do) = @_;
    sub { my @parts = @do;
          my (@attrs, @elems);

          while(@parts)
          {   my $childname = shift @parts;
              my $child     = (shift @parts)->();
              if($child->{attr})
              {   push @attrs, $child;
              }
              else
              {   push @elems, $child;
              }
          }

          +{ kind    => 'complex'
           , struct  => "$tag is complex"
           , tag     => $tag
           , attrs   => \@attrs
           , elems   => \@elems
           };
        };
}

#
# complexType/simpleContent
#

sub create_tagged_element
{   my ($path, $args, $tag, $st, $attrs) = @_;
    my @do  = @$attrs;
    sub { my @attrs;
          my @parts   = @do;
          while(@parts)
          {   my $childname = shift @parts;
              push @attrs, (shift @parts)->();
          }

          +{ kind    => 'tagged'
           , struct  => "$tag is simple value with attributes"
           , tag     => $tag
           , attrs   => \@attrs
           , example => $st->()
           };
       };
}

#
# simpleType
#

sub create_simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { +{ kind    => 'simple'
           , struct  => "$tag is a single value"
           , tag     => $tag
           , $st->()
           };
        };
}

sub builtin_checked
{   my ($path, $args, $type, $def) = @_;
    my $example = $def->{example};
    sub { ( type    => $type
          , example => $example
          );
        };
}

sub builtin_unchecked(@) { &builtin_checked };

# simpleType

sub list
{   my ($path, $args, $st) = @_;
    sub { ( struct => "a (blank separated) list of elements"
          , $st->()
          );
        };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { ( facets => "with some limits on the list"
          , $st->()
          );
        };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { ( facets => "with some limits"
          , $st->()
          );
        };
}

sub union
{   my ($path, $args, $err, @types) = @_;
    sub { +{ kind   => 'union'
           , struct => "one of the following (union)"
           , choice => [ map { $_->() } @types ]
           };
        };
}

# Attributes

sub attribute_required
{   my ($path, $args, $ns, $tag, $do) = @_;

    sub { +{ kind   => 'attr'
           , tag    => $tag
           , occurs => "attribute $tag is required"
           , $do->()
           };
        };
}

sub attribute_prohibited
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { () };
}

sub attribute_default
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { +{ kind   => 'attr'
           , tag    => $tag
           , occurs => "attribute $tag has default"
           , $do->()
           };
        };
}

sub attribute_optional
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { +{ kind   => 'attr'
           , tag    => $tag
           , occurs => "attribute $tag is optional"
           , $do->()
           };
        };
}

sub attribute_fixed
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    $fixed   = $fixed->example ;

    sub { +{ kind    => 'attr'
           , tag     => $tag
           , occurs  => "attribute $tag is fixed"
           , example => $fixed
           };
        };
}

###
### toPerl
###

sub toPerl($%)
{   my ($class, $ast, %args) = @_;
    join "\n", perl_any($ast, \%args), '';
}

sub perl_any($$);
sub perl_any($$)
{   my ($ast, $args) = @_;

    my @lines;
    push @lines, "# $ast->{struct}" if $ast->{struct} && $args->{show_struct};
    push @lines, "# is a $ast->{type}" if $ast->{type} && $args->{show_type};
    push @lines, "# $ast->{occur}"  if $ast->{occur}  && $args->{show_occur};
    push @lines, "# $ast->{facets}" if $ast->{facets} && $args->{show_facets};

    my @childs;
    push @childs, @{$ast->{attrs}} if $ast->{attrs};
    push @childs, @{$ast->{elems}} if $ast->{elems};

    my @subs;
    foreach my $child (@childs)
    {   my @sub = perl_any($child, $args);
        @sub or next;

        # seperator blank between childs when comments
        unshift @sub, '' if @subs && $sub[0] =~ m/^\# /;

        # last line is code and gets comma
        $sub[-1] .= ',';

        # all lines get indented
        push @subs, map {length($_) ? "$args->{indent}$_" : ''} @sub;
    }

    if(@subs)
    {   $subs[0] =~ s/^ /{/;
        push @lines, "$ast->{tag} =>", @subs, '}';
    }
    else
    {   my $example = $ast->{example};
        $example = qq{"$example"} if $example !~ m/^\d+(?:\.\d+)?$/;
        push @lines, "$ast->{tag} => $example";
    }

    @lines;
}

1;
