
package XML::Compile::Schema::XmlWriter;

use strict;
use warnings;
no warnings 'once';

use List::Util    qw/first/;

=chapter NAME

XML::Compile::Schema::XmlWriter - bricks to translate HASH to XML

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 my $code   = $schema->compile(WRITER => ...);

=chapter DESCRIPTION
The translator understands schema's, but does not encode that into
actions.  This module implements those actions to translate from
a (nested) Perl HASH structure onto XML.

=cut


# Each action implementation returns a code reference, which will be
# used to do the run-time work.  The principle of closures is used to
# keep the important information.  Be sure that you understand closures
# before you attempt to change anything.
#
# The returned writer subroutines will always be called
#       $writer->($doc, $value) 

sub tag_qualified
{   my ($path, $args, $node, $name) = @_;
    my ($pref, $label)
       = index($name, ':') >=0 ? split(/\:/, $name) : ('',$name);

    my $ns  = length($pref)? $node->lookupNamespaceURI($pref) :$args->{tns};

    my $out_ns = $args->{output_namespaces};
    my $out = $out_ns->{$ns};

    unless($out)   # start new name-space
    {   if(first {$pref eq $_->{prefix}} values %$out_ns)
        {   # avoid name clashes
            length($pref) or $pref = 'x';
            my $trail = '0';
            $trail++ while first {"$pref$trail" eq $_->{prefix}}
                             values %$out_ns;
            $pref .= $trail;
        }
        $out_ns->{$ns} = $out = {uri => $ns, prefix => $pref};
    }

    $out->{used}++;
    my $prefix = $out->{prefix};
    length($prefix) ? "$prefix:$name" : $name;
}

sub tag_unqualified
{   my ($path, $args, $node, $name) = @_;
    $name =~ s/.*\://;
    $name;
}

sub wrapper
{   my $processor = shift;
    sub { my ($doc, $data) = @_;
          my $top = $processor->(@_);
          $doc->indexElements;
          $top;
        };
}

sub wrapper_ns
{   my ($path, $args, $processor, $index) = @_;
    my @entries = map { $_->{used} ? [ $_->{uri}, $_->{prefix} ] : () }
        values %$index;

    sub { my $node = $processor->(@_);
          $node->setNamespace(@$_, 0) foreach @entries;
          $node;
        };
}

#
## Element
#

sub element_repeated
{   my ($path, $args, $ns, $childname, $do, $min, $max) = @_;
    my $err  = $args->{err};
    sub { my ($doc, $values) = @_;
          my @values = ref $values eq 'ARRAY' ? @$values
                     : defined $values ? $values : ();
          $err->($path,scalar @values,"too few values (need $min)")
             if @values < $min;
          $err->($path,scalar @values,"too many values (max $max)")
             if $max ne 'unbounded' && @values > $max;
          map { $do->($doc, $_) } @values;
        };
}

sub element_array
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { my ($doc, $values) = @_;
          map { $do->($doc, $_) }
              ref $values eq 'ARRAY' ? @$values
            : defined $values ? $values : ();
        };
}

sub element_obligatory
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { my ($doc, $value) = @_;
          return $do->($doc, $value) if defined $value;
          $value = $err->($path, $value, "one value required");
          defined $value ? $do->($doc, $value) : undef;
        };
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
    my $err  = $args->{err};
    $fixed   = $fixed->value;

    sub { my ($doc, $value) = @_;
          my $ret = defined $value ? $do->($doc, $value) : undef;
          return $ret if defined $ret && $ret->textContent eq $fixed;

          $err->($path, $value, "value fixed to '$fixed'");
          $do->($doc, $fixed);
        };
}

sub element_fixed_optional
{   my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
    my $err  = $args->{err};
    $fixed   = $fixed->value;

    sub { my ($doc, $value) = @_;
          my $ret = defined $value ? $do->($doc, $value) : undef;
          return $ret if !defined $ret || $ret->textContent eq $fixed;

          $err->($path, $value, "value fixed to '$fixed'");
          $do->($doc, $fixed);
        };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $err  = $args->{err};
    sub { my ($doc, $value) = @_;
          return $do->($doc, $value) if defined $value;
          my $node = $doc->createElement($childname);
          $node->setAttribute(nil => 'true');
          $node;
        };
}

sub element_default
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { defined $_[1] ? $do->(@_) : (); };
}
*element_optional = \&element_default;

#
# complexType/ComplexContent
#

sub create_complex_element
{   my ($path, $args, $tag, $childs, $any_elem, $any_attr) = @_;
    my @do = @$childs;
    my $err = $args->{err};
    sub { my ($doc, $data) = @_;
          unless(UNIVERSAL::isa($data, 'HASH'))
          {   $data = defined $data ? "$data" : 'undef';
              $err->($path, $data, 'expected hash of input data');
              return ();
          }
          my @elems = @do;
          my @childs;
          while(@elems)
          {   my $childname = shift @elems;
              push @childs, (shift @elems)
                  ->($doc, delete $data->{$childname});
          }

       ANY:
          foreach my $tag (sort keys %$data)
          {   next unless $tag =~ m/^\{([^}]*)\}(.*)$/;
              my ($ns, $type) = ($1, $2);
              my $value = delete $data->{$tag};
              defined $value or next;

              my $any
               = !ref $value                         ? undef
               : $value->isa('XML::LibXML::Attr')    ? $any_attr
               : $value->isa('XML::LibXML::Element') ? $any_elem
               : undef;

              unless($any)
              {   $err->($path, ref $value
                , "requires XML::LibXML::Attr or ::Element as value for $tag");
                  next ANY;
              }

              foreach my $try (@$any)
              {   my $v = $try->($doc, $tag, $ns, $type, $value);
                  defined $v or next;
                  push @childs, $v;
                  next ANY;
              }

              $err->($path, ref $value, "value for $tag not used");
          }

          $err->($path, join(' ', sort keys %$data), 'unused data')
              if keys %$data;

          @childs or return ();
          my $node  = $doc->createElement($tag);
          $node->addChild
            ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
            : $doc->createTextNode(defined $_ ? $_ : ''))
               for @childs;

          $node;
        };
}

#
# complexType/simpleContent
#

sub create_tagged_element
{   my ($path, $args, $tag, $st, $attrs) = @_;
    my @do  = @$attrs;
    my $err = $args->{err};
    sub { my ($doc, $data) = @_;
          unless(UNIVERSAL::isa($data, 'HASH'))
          {   $data = defined $data ? "$data" : 'undef';
              $err->($path, $data, 'expected hash of input data');
              return ();
          }
          my $content = $st->($doc, delete $data->{_});
          my @childs;
          push @childs, $doc->createTextNode($content)
             if defined $content;

          my @attrs   = @do;
          while(@attrs)
          {   my $childname = shift @attrs;
              push @childs,
                (shift @attrs)->($doc, delete $data->{$childname});
          }
          $err->($path, join(' ', sort keys %$data), 'unused data')
              if keys %$data;

          @childs or return ();
          my $node  = $doc->createElement($tag);
          $node->addChild
            ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
            : $doc->createTextNode(defined $_ ? $_ : ''))
               for @childs;
          $node;
       };
}

#
# simpleType
#

sub create_simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { my ($doc, $data) = @_;
          my $value = $st->($doc, $data);
          my $node  = $doc->createElement($tag);
          $node->addChild
            ( ref $value && $value->isa('XML::LibXML::Node') ? $value
            : $doc->createTextNode(defined $value ? $value : ''));
          $node;
        };
}

sub builtin_checked
{   my ($path, $args, $node, $type, $def) = @_;
    my $check  = $def->{check};
    defined $check
       or return builtin_unchecked(@_); 

    my $format = $def->{format};
    my $err    = $args->{err};

      defined $format
    ? sub { defined $_[1] or return undef;
            my $value = $format->($_[1], $node);
            return $value if defined $value && $check->($value);
            $value = $err->($path, $_[1], "illegal value for $type");
            defined $value ? $format->($value, $node) : undef;
          }
    : sub { return $_[1] if !defined $_[1] || $check->($_[1]);
            my $value = $err->($path, $_[1], "illegal value for $type");
            defined $value ? $format->($value, $node) : undef;
          };
}

sub builtin_unchecked
{   my $format = $_[4]->{format};
    my $node   = $_[2];
      defined $format
    ? sub { defined $_[1] ? $format->($_[1], $node) : undef }
    : sub { $_[1] }
}

# simpleType

sub list
{   my ($path, $args, $st) = @_;
    sub { defined $_[1] or return undef;
          my @el = ref $_[1] eq 'ARRAY' ? (grep {defined} @{$_[1]}) : $_[1];
          my @r = grep {defined} map {$st->($_[0], $_)} @el;
          @r or return undef;
          join ' ', grep {defined} @r;
        };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { defined $_[1] or return undef;
          my @el = ref $_[1] eq 'ARRAY' ? (grep {defined} @{$_[1]}) : $_[1];

          my @r = grep {defined} map {$st->($_[0], $_)} @el;

      EL: for(@r)
          {   for my $l (@$late)
              { defined $_ or next EL; $_ = $l->($_) }
          }

          @r or return undef;
          my $r = join ' ', grep {defined} @r;

          my $v = $r;  # do not test with original
          for(@$early) { defined $v or return (); $v = $_->($v) }
          $r;
        };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { defined $_[1] or return undef;
          my $v = $st->(@_);
          for(reverse @do)
          { defined $v or return (); $v = $_->($v) }
          $v;
        };
}

sub union
{   my ($path, $args, $err, @types) = @_;
    sub { defined $_[1] or return undef;
          for(@types) {my $v = $_->(@_); defined $v and return $v }
          $err->($path, $_[1], "no match in union");
        };
}

# Attributes

sub attribute_required
{   my ($path, $args, $ns, $tag, $do) = @_;
    my $err = $args->{err};

    sub { my $value = $do->(@_);
          $value = $err->($path, 'undef'
                     , "missing value for required attribute $tag")
             unless defined $value;
          defined $value or return ();
          $_[0]->createAttributeNS($ns, $tag, $value);
        };
}

sub attribute_prohibited
{   my ($path, $args, $ns, $tag, $do) = @_;
    my $err = $args->{err};

    sub { my $value = $do->(@_);
          $err->($path, $value, "attribute $tag prohibited")
             if defined $value;
          ();
        };
}

sub attribute_default
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { my $value = $do->(@_);
          defined $value ? $_[0]->createAttributeNS($ns, $tag, $value) : ();
        };
}
*attribute_optional = \&attribute_default;

sub attribute_fixed
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $err  = $args->{err};
    $fixed   = $fixed->value;

    sub { my ($doc, $value) = @_;
          my $ret = defined $value ? $do->($doc, $value) : undef;
          return $doc->createAttributeNS($ns, $tag, $ret)
              if defined $ret && $ret eq $fixed;

          $err->($path, $value, "attr value fixed to '$fixed'");
          $ret = $do->($doc, $fixed);
          defined $ret ? $doc->createAttributeNS($ns, $tag, $ret) : ();
        };
}

sub attribute_fixed_optional
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $err  = $args->{err};
    $fixed   = $fixed->value;

    sub { my ($doc, $value) = @_;
          defined $value or return ();

          my $ret = $do->($doc, $value);
          return $doc->createAttributeNS($ns, $tag, $ret)
              if defined $ret && $ret eq $fixed;

          $err->($path, $value, "attr value fixed to '$fixed'");
          $ret = $do->($doc, $fixed);
          defined $ret ? $doc->createAttributeNS($ns, $tag, $ret) : ();
        };
}

# any

sub anyAttribute
{   my ($path, $args, $handler, $yes, $no, $process) = @_;
    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};
    my $err = $args->{err};

    sub { my ($doc, $key, $ns, $type, $value) = @_;
          my $vns = $value->namespaceURI;
          $vns eq $ns or $err->($path, $vns, "value name-space must be $ns");
          # type can best be made explicit, but cannot be checked.
          return $yes{$ns} ? $value : undef  if keys %yes;
          return $no{$ns}  ? undef  : $value if keys %no;
          $value;
        };
}

sub anyElement
{   my ($path, $args, $handler, $yes,$no, $process, $min,$max) = @_;
    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};
    my $err = $args->{err};

    defined $handler or return sub { () };

    sub { my ($doc, $key, $ns, $type, $values) = @_;
          my @values = ref $values eq 'ARRAY' ? @$values : $values;
          foreach my $value (@values)
          {  my $vns = $value->namespaceURI;
             $vns eq $ns or $err->($path, $vns, "value name-space must be $ns");
             return $yes{$ns} ? $value : undef  if keys %yes;
             return $no{$ns}  ? undef  : $value if keys %no;
          }
          @values;
        };
}

=chapter DETAILS

=section Processing Wildcards

Complex elements can define C<any> (element) and C<anyAttribute> components,
with unpredictable content.  In this case, you are quite on your own in
processing those constructs.  The use of both schema components should
be avoided: please specify your data-structures explicit by clean type
extensions.

The procedure for the XmlWriter is simple: add key-value pairs to your
hash, in which the valie is a fully prepared M<XML::LibXML::Attr>
or M<XML::LibXML::Element>.  The keys have the form C<{namespace}type>.
The I<namespace> component is important, because only spec confirmant
namespaces will be used.  The type is ignored.  The elements and
attributes are added in random order.

=example specify anyAttribute
 my $attr = $doc->createAttributeNS($somens, $sometype, 42);
 my $h = { a => 12     # normal element or attribute
         , "{$somens}$sometype" => $attr # anyAttribute
         };

=cut

1;

