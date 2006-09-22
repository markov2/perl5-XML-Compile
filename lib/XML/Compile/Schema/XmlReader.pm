package XML::Compile::Schema::XmlReader;

use strict;
use warnings;
no warnings 'once';

=chapter NAME

XML::Compile::Schema::XmlReader - bricks to translate XML to HASH

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 my $code   = $schema->compile(READER => ...);

=chapter DESCRIPTION
The translator understands schema's, but does not encode that into
actions.  This module implements those actions to translate from XML
into a (nested) Perl HASH structure.

=cut

# Each action implementation returns a code reference, which will be
# used to do the run-time work.  The principle of closures is used to
# keep the important information.  Be sure that you understand closures
# before you attempt to change anything.
#
# The returned reader subroutines will always be called
#       $reader->($xml_node) 

sub tag_qualified
{   my $name = $_[3];
     $name =~ s/.*?\://;   # strip prefix, that's all
     $name;
      };
*tag_unqualified = \&tag_qualified;

sub wrapper
{   my $processor = shift;
    sub { my $xml = ref $_[0] && $_[0]->isa('XML::LibXML::Node')
                  ? $_[0]
                  : XML::Compile->parse(\$_[0]);
          $xml ? $processor->($xml) : ();
        };
}

sub wrapper_ns        # no namespaces in the HASH
{   my ($path, $args, $processor, $index) = @_;
    $processor;
}

#
## Element
#

sub element_repeated
{   my ($path, $args, $ns, $childname, $do, $min, $max) = @_;
    my $err  = $args->{err};
    sub { my @nodes = $_[0]->getChildrenByTagName($childname);
          $err->($path,scalar @nodes,"too few values (need $min)")
             if @nodes < $min;
          $err->($path,scalar @nodes,"too many values (max $max)")
             if $max ne 'unbounded' && @nodes > $max;
          my @r = map { $do->($_) } @nodes;
          @r ? ($childname => \@r) : (); 
        };
}

sub element_array
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { my @r = map { $do->($_) } $_[0]->getChildrenByTagName($childname);
          @r ? ($childname => \@r) : ();
        };
}

sub element_obligatory
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub {
# This should work with namespaces (but doesn't yet)
# my @nodes = $_[0]->getElementsByTagNameNS($ns,$childname);
          my @nodes = $_[0]->getChildrenByTagName($childname);
          my $node
           = (@nodes==0 || !defined $nodes[0])
           ? $err->($path, undef, "one value required")
           : shift @nodes;
          $node = $err->($path, 'found '.@nodes, "only one value expected")
             if @nodes;
          defined $node ? ($childname => $do->($node)) : ();
        };
}

sub element_default
{   my ($path, $args, $ns, $childname, $do, $min, $max, $default) = @_;
    my $err  = $args->{err};
    my $def  = $do->($default);

    sub { my @nodes = $_[0]->getChildrenByTagName($childname);
          my $node = shift @nodes;
          $node = $err->($path, 'found '.@nodes, "only one value expected")
             if @nodes;
          ( $childname => (defined $node ? $do->($node) : $def) );
        };
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
    my $err = $args->{err};
    my $def  = $do->($fixed);

    sub { my @nodes = $_[0]->getChildrenByTagName($childname);
          my $node = shift @nodes;
          $node = $err->($path, 'found '.@nodes, "only one value expected")
              if @nodes;
          my $value = defined $node ? $do->($node) : undef;
          $err->($path, $value,"value fixed to '".$fixed->value."'")
              if !defined $value || $value ne $def;
          ($childname => $def);
        };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { my @nodes = $_[0]->getChildrenByTagName($childname);
          my $node
           = (@nodes==0 || !defined $nodes[0])
           ? $err->($path, undef, "one value required")
           : shift @nodes;
          $err->($path, 'found '.@nodes, "only one value expected")
             if @nodes;
          my $nil = $node->getAttribute('nil') || 'false';
          $childname => ($nil eq 'true' ? undef : $do->($node));
        };
}

sub element_optional
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { my @nodes = $_[0]->getElementsByLocalName($childname)
             or return ();
          $err->($path, scalar @nodes, "only one value expected")
             if @nodes > 1;
          my $val = $do->($nodes[0]);
          defined $val ? ($childname => $val) : ();
        };
}

#
# complexType/ComplexContent
#

sub create_complex_element
{   my ($path, $args, $tag, @childs) = @_;
    my @do;
    while(@childs) {shift @childs; push @do, shift @childs}

    sub { my @pairs = map {$_->(@_)} @do;
          @pairs ? {@pairs} : ();
        };
}

#
# complexType/simpleContent
#

sub create_tagged_element
{   my ($path, $args, $tag, $st, $attrs) = @_;
    my @attrs = @$attrs;
    my @do;
    while(@attrs) {shift @attrs; push @do, shift @attrs}

    sub { my @a = @do;
          my $simple = $st->(@_);
          my @pairs = map {$_->(@_)} @do;
          defined $simple or @pairs or return ();
          defined $simple or $simple = 'undef';
          {_ => $simple, @pairs};
        };
}

#
# simpleType
#

sub create_simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { my $value = $st->(@_);
          defined $value ? $value : undef;
        };
}

sub builtin_checked
{   my ($path, $args, $type, $def) = @_;
    my $check = $def->{check};
    defined $check
       or return builtin_unchecked(@_); 
    my $parse = $def->{parse};
    my $err   = $args->{err};

      defined $parse
    ? sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
            defined $value or return undef;
              $check->($value)
            ? $parse->($value)
            : $err->($path, $value, "illegal value for $type");
          }
    : sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
            defined $value or return undef;
              $check->($value)
            ? $value
            : $err->($path, $value, "illegal value for $type");
          };
}

sub builtin_unchecked
{   my $parse = $_[3]->{parse};

      defined $parse
    ? sub { my $v = $_[0]->textContent; defined $v ? $parse->($v) : undef }
    : sub { $_[0]->textContent }
}

# simpleType

sub list
{   my ($path, $args, $st) = @_;
    sub { defined $_[0] or return undef;
          my $v = $_[0]->textContent;
          my @v = grep {defined} map {$st->($_) } split(" ",$v);
          \@v;
        };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { defined $_[0] or return undef;
          my $v = $st->(@_);
          for(@$early) { defined $v or return (); $v = $_->($v) }
          my @v = defined $v ? split(" ",$v) : ();
          my @r;
      EL: for my $e (@v)
          {   for(@$late) { defined $e or next EL; $e = $_->($e) }
              push @r, $e;
          }
          @r ? \@r : ();
        };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { defined $_[0] or return undef;
          my $v = $st->(@_);
          for(@do) { defined $v or return (); $v = $_->($v) }
          $v;
        };
}

sub union
{   my ($path, $args, $err, @types) = @_;
    sub { defined $_[0] or return undef;
          for(@types) {my $v = $_->($_[0]); defined $v and return $v }
          my $text = $_[0]->textContent;
          substr $text, 10, -1, '...' if length($text) > 13;
          $err->($path, $text, "no match in union");
        };
}

# Attributes

sub attribute_required
{   my ($path, $args, $tag, $do) = @_;
    my $err  = $args->{err};
    sub { my $node = $_[0]->getAttributeNode($tag)
                  || $err->($path, undef, "attribute $tag required");
          defined $node or return ();
          my $value = $do->($node);
          defined $value ? ($tag => $value) : ();
        };
}

sub attribute_prohibited
{   my ($path, $args, $tag, $do) = @_;
    my $err  = $args->{err};
    sub { my $node = $_[0]->getAttributeNode($tag);
          defined $node or return ();
          $err->($path, $node->textContent, "attribute $tag prohibited");
          ();
        };
}

sub attribute_optional
{   my ($path, $args, $tag, $do) = @_;
    my $err  = $args->{err};
    sub { my $node = $_[0]->getAttributeNode($tag)
             or return ();
          my $val = $do->($node);
          defined $val ? ($tag => $val) : ();
        };
}

sub attribute_default
{   my ($path, $args, $tag, $do, $default) = @_;
    my $err  = $args->{err};
    my $def  = $do->($default);

    sub { my $node = $_[0]->getAttributeNode($tag);
          ($tag => defined $node ? $do->($node) : $def);
        };
}

sub attribute_fixed
{   my ($path, $args, $tag, $do, $fixed) = @_;
    my $err = $args->{err};
    my $def  = $do->($fixed);

    sub { my $node  = $_[0]->getAttributeNode($tag);
          my $value = defined $node ? $do->($node) : undef;
          $err->($path, $value, "attr value fixed to '".$fixed->value."'")
              if !defined $value || $value ne $def;
          ($tag => $def);
        };
}


# SubstitutionGroups

sub element_substgroup
{   my ($path, $args, $name, $defs) = @_;
    my $err  = $args->{err};
    sub { foreach my $def (@$defs)
          {   my $node = $_[0]->getChildrenByTagName($def->[1])
                 or next;
              return $def->[2]->(@_);
          }
          $err->($path, $name, "none of the substitution alternatives found.");
        };
}

1;

