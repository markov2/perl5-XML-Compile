
package XML::Compile::Schema::Template;

use XML::Compile::Schema::XmlWriter;

use strict;
use warnings;
no warnings 'once';

use XML::Compile::Util qw/odd_elements block_label unpack_type/;
use Log::Report 'xml-compile', syntax => 'SHORT';

=chapter NAME

XML::Compile::Schema::Template - bricks to create an XML or PERL example

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 print $schema->template(XML  => $type, ...);
 print $schema->template(PERL => $type, ...);

 # script as wrapper for this module
 schema2example -f XML ...

=chapter DESCRIPTION

The translator understands schemas, but does not encode that into
actions.  This module interprets the parse results of the translator,
and creates a kind of abstract syntax tree from it, which can be used
for documentational purposes.  Then, it implements to ways to represent
that knowledge: as an XML or a Perl example of the data-structure which
the schema describes.

=cut

BEGIN {
   no strict 'refs';
   *$_ = *{"XML::Compile::Schema::XmlWriter::$_"}
      for qw/tag_qualified tag_unqualified wrapper_ns/;
}

sub element_wrapper
{   my ($path, $args, $processor) = @_;
    sub { $processor->() };
}
*attribute_wrapper = \&element_wrapper;

sub _block($@)
{   my ($block, $path, $args, @pairs) = @_;
    bless
    sub { my @elems  = map { $_->() } odd_elements @pairs;
          my @tags   = map { $_->{tag} } @elems;

          my $struct = "$block of ". join(', ',@tags);
          my @lines;
          while(length $struct > 65)
          {   $struct =~ s/(.{1,60})(\s)//;
              push @lines, $1;
          }
          push @lines, $struct;
          $lines[$_] =~ s/^/  / for 1..$#lines;

          local $" = ', ';
           { tag    => $block
           , elems  => \@elems
           , struct => \@lines
           };
        }, 'BLOCK';
}

sub sequence { _block(sequence => @_) }
sub choice   { _block(choice   => @_) }
sub all      { _block(all      => @_) }

sub block_handler
{   my ($path, $args, $label, $min, $max, $proc, $kind) = @_;

    my $code =
    sub { my $data = $proc->();
          my $occur
           = $max eq 'unbounded' && $min==0 ? 'occurs any number of times'
           : $max ne 'unbounded' && $max==1 && $min==0 ? 'is optional' 
           : $max ne 'unbounded' && $max==1 && $min==1 ? ''  # the usual case
           :       "occurs $min <= # <= $max times";

          $data->{occur}   = $occur if $occur;
          if($max ne 'unbounded' && $max==1)
          {   bless $data, 'BLOCK';
          }
          else
          {   $data->{tag}      = block_label $kind, $label;
              $data->{is_array} = 1;
              bless $data, 'REP-BLOCK';
          }
          $data;
        };
    ($label => $code);
}

sub element_handler
{   my ($path, $args, $label, $min, $max, $req, $opt) = @_;
    sub { my $data = $opt->();
          my $occur
           = $max eq 'unbounded' && $min==0 ? 'occurs any number of times'
           : $max ne 'unbounded' && $max==1 && $min==0 ? 'is optional' 
           : $max ne 'unbounded' && $max==1 && $min==1 ? ''  # the usual case
           :                                  "occurs $min <= # <= $max times";
          $data->{occur}    = $occur if $occur;
          $data->{is_array} = $max eq 'unbounded' || $max > 1;
          $data;
        };
}

sub required
{   my ($path, $args, $label, $do) = @_;
    $do;
}

sub element_href
{   my ($path, $args, $ns, $childname, $do) = @_;
    $do;
}

sub element
{   my ($path, $args, $ns, $childname, $do) = @_;
    $do;
}

sub element_default
{   my ($path, $args, $ns, $childname, $do, $default) = @_;
    sub { (occur => "$childname defaults to example $default",  $do->()) };
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $fixed) = @_;
    $fixed   = $fixed->example;
    sub { (occur => "$childname fixed to example $fixed", $do->()) };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { (occur => "$childname is nillable", $do->()) };
}

my %recurse;
sub complex_element
{   my ($path, $args, $tag, $elems, $attrs, $any_attr) = @_;
    my @parts = (odd_elements(@$elems, @$attrs), @$any_attr);

    sub { my (@attrs, @elems);

          if($recurse{$tag})
          {   return
              +{ kind   => 'complex'
               , struct => 'probably a recursive complex'
               , tag    => $tag
               };
          }

          $recurse{$tag}++;
          foreach my $part (@parts)
          {   my $child = $part->();
              if($child->{attr}) { push @attrs, $child }
              else               { push @elems, $child }
          }
          $recurse{$tag}--;

          +{ kind    => 'complex'
#          , struct  => "$tag is complex"  # too obvious to mention
           , tag     => $tag
           , attrs   => \@attrs
           , elems   => \@elems
           };
        };
}

sub tagged_element
{   my ($path, $args, $tag, $st, $attrs, $attrs_any) = @_;
    my @parts = (odd_elements(@$attrs), @$attrs_any);

    my %content =
     ( tag     => '_'
     , struct  => 'string content of the container'
     , example => 'Hello, World!' 
     );

    sub { my @attrs  = map {$_->()} @parts;
          my $simple = $st->() || '';

          +{ kind    => 'tagged'
           , struct  => "$tag is simple value with attributes"
           , tag     => $tag
           , attrs   => \@attrs
           , elems   => [ \%content ]
           };
        };
}

sub mixed_element
{   my ($path, $args, $tag, $attrs, $attrs_any) = @_;
    my @parts = (odd_elements(@$attrs), @$attrs_any);

    my %mixed =
     ( tag     => '_'
     , struct  => "mixed content cannot be processed automatically"
     , example => "XML::LibXML::Element->new($tag)"
     );

    unless(@parts)   # show simpler alternative
    {   $mixed{tag} = $tag;
        return sub { \%mixed };
    }

    sub { my @attrs = map {$_->()} @parts;
          +{ kind    => 'mixed'
           , struct  => "$tag has a mixed content"
           , tag     => $tag
           , elems   => [ \%mixed ]
           , attrs   => \@attrs
           };
        };
}

sub simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { +{ kind    => 'simple'
#          , struct  => "elem $tag is a single value"  # too obvious
           , tag     => $tag
           , $st->()
           };
        };
}

sub builtin
{   my ($path, $args, $node, $type, $def, $check_values) = @_;
    my $example = $def->{example};
    sub { (type => $type, example => $example) };
}

sub list
{   my ($path, $args, $st) = @_;
    sub { (struct => "a (blank separated) list of elements", $st->()) };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { (facets => "with some restrictions on list elements", $st->()) };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { (facets => "with some value restrictions", $st->()) };
}

sub union
{   my ($path, $args, @types) = @_;
    sub { my @choices = map { +{$_->()} } @types;
          +( kind    => 'union'
           , struct  => "one of the following (union)"
           , choice  => \@choices
           , example => $choices[0]->{example}
           );
        };
}

sub attribute_required
{   my ($path, $args, $ns, $tag, $do) = @_;

    sub { +{ kind    => 'attr'
           , tag     => $tag
           , occurs  => "attribute $tag is required"
           , $do->()
           };
        };
}

sub attribute_prohibited
{   my ($path, $args, $ns, $tag, $do) = @_;
    ();
}

sub attribute
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { +{ kind    => 'attr'
           , tag     => $tag
           , $do->()
           };
        };
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

sub attribute_fixed
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $value = $fixed->value;

    sub { +{ kind    => 'attr'
           , tag     => $tag
           , occurs  => "attribute $tag is fixed"
           , example => $value
           };
        };
}

sub attribute_fixed_optional
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $value = $fixed->value;

    sub { +{ kind    => 'attr'
           , tag     => $tag
           , occurs  => "attribute $tag is fixed optional"
           , example => $value
           };
        };
}

sub substgroup
{   my ($path, $args, $type, %do) = @_;
    sub { +{ kind    => 'substitution group'
           , struct  => "one of the following, which extend $type"
           , map { $_->() } values %do
           }
        };
}

sub anyAttribute
{   my ($path, $args, $handler, $yes, $no, $process) = @_;
    my $occurs = @$yes ? "in @$yes" : @$no ? "not in @$no" : 'any type';
    bless sub { +{kind => 'attr' , struct  => "anyAttribute $occurs"} }, 'ANY';
}

sub anyElement
{   my ($path, $args, $handler, $yes, $no, $process, $min, $max) = @_;
    $yes ||= []; $no ||= [];
    my $occurs = @$yes ? "in @$yes" : @$no ? "not in @$no" : 'any type';
    bless sub { +{kind => 'element', struct  => 'anyElement'} }, 'ANY';
}

sub hook($$$$$)
{   my ($path, $args, $r, $before, $produce, $after) = @_;
    return $r if $r;
    warning __x"hooks are not shown in templates";
    ();
}


###
### toPerl
###

sub toPerl($%)
{   my ($class, $ast, %args) = @_;
    my $lines = join "\n", perl_any($ast, \%args);
    $lines =~ s/\,?\s*$/\n/;
    $lines;
}

sub perl_any($$);
sub perl_any($$)
{   my ($ast, $args) = @_;

    my @lines;
    if($ast->{struct} && $args->{show_struct})
    {   my $struct = $ast->{struct};
        my @struct = ref $struct ? @$struct : $struct;
        s/^/# /gm for @struct;
        push @lines, @struct;
    }
    push @lines, "# is a $ast->{type}" if $ast->{type} && $args->{show_type};
    push @lines, "# $ast->{occur}"  if $ast->{occur}   && $args->{show_occur};
    push @lines, "# $ast->{facets}" if $ast->{facets}  && $args->{show_facets};

    my @childs;
    push @childs, @{$ast->{attrs}}  if $ast->{attrs};
    push @childs, @{$ast->{elems}}  if $ast->{elems};
    push @childs,   $ast->{body}    if $ast->{body};

    my @subs;
    foreach my $child (@childs)
    {   my @sub = perl_any($child, $args);
        @sub or next;

        # last line is code and gets comma
        $sub[-1] =~ s/\,?\s*$/,/;

        if(ref $ast ne 'BLOCK')
        {   s/^(.)/$args->{indent}$1/ for @sub;
        }

        # seperator blank, sometimes
        unshift @sub, '' if $sub[0] =~ m/^\s*[#{]/;  # } 

        push @subs, @sub;
    }

    if(ref $ast eq 'REP-BLOCK')
    {  # repeated block
       @subs or @subs = '';
       $subs[0]  =~ s/^  /{ /;
       $subs[-1] =~ s/$/ },/;
    }

    # XML does not permit difficult tags, but we still check.
    my $tag = $ast->{tag} || '';
    if(defined $tag && $tag !~ m/^[\w_][\w\d_]*$/)
    {   $tag =~ s/\\/\\\\/g;
        $tag =~ s/'/\\'/g;
        $tag = qq{'$tag'};
    }

    my $kind = $ast->{kind} || '';
    if(ref $ast eq 'REP-BLOCK')
    {   s/^(.)/  $1/ for @subs;
        $subs[0] =~ s/^ ?/[/;
        push @lines, "$tag => ", @subs , ']';
    }
    elsif(ref $ast eq 'BLOCK')
    {   push @lines, @subs;
    }
    elsif(@subs)
    {   length $subs[0] or shift @subs;
        if($ast->{is_array})
        {   s/^(.)/  $1/ for @subs;
            $subs[0]  =~ s/^[ ]{0,3}/[ {/;
            $subs[-1] =~ s/$/ }, ], /;
            push @lines, "$tag =>", @subs;
        }
        else
        {   $subs[0]  =~ s/^  /{ /;
            $subs[-1] =~ s/$/ },/;
            push @lines, "$tag =>", @subs;
        }
    }
    elsif($kind eq 'complex' || $kind eq 'mixed')  # empty complex-type
    {   push @lines, "$tag => {}";
    }
    elsif($kind eq 'union')    # union type
    {   foreach my $union ( @{$ast->{choice}} )
        {  # remove examples
           my @l = grep { m/^#/ } perl_any($union,$args);
           s/^\#/#  -/ for $l[0];
           s/^\#/#   / for @l[1..$#l];
           push @lines, @l;
        }
    }
    elsif(!$ast->{example})
    {   push @lines, "$tag => 'TEMPLATE-ERROR $ast->{kind}'";
    }

    if(my $example = $ast->{example})
    {   $example = qq{"$example"} if $example !~ m/^[+-]?\d+(?:\.\d+)?$/;
        push @lines, "$tag => "
          . ($ast->{is_array} ? " [ $example, ]" : $example);
    }
    @lines;
}

###
### toXML
###

sub toXML($$%)
{   my ($class, $doc, $ast, %args) = @_;
    xml_any($doc, $ast, "\n$args{indent}", \%args);
}

sub xml_any($$$$);
sub xml_any($$$$)
{   my ($doc, $ast, $indent, $args) = @_;
    my @res;

    my @comment;
    if($ast->{struct} && $args->{show_struct})
    {   my $struct = $ast->{struct};
        push @comment, ref $struct ? @$struct : $struct;
    }

    push @comment, $ast->{occur}  if $ast->{occur}  && $args->{show_occur};
    push @comment, $ast->{facets} if $ast->{facets} && $args->{show_facets};

    if(defined $ast->{kind} && $ast->{kind} eq 'union')
    {   push @comment, map { "  $_->{type}"} @{$ast->{choice}};
    }

    my @attrs = @{$ast->{attrs} || []};
    foreach my $attr (@attrs)
    {   push @res, $doc->createAttribute($attr->{tag}, $attr->{example});
        push @comment, "$attr->{tag}: $attr->{type}"
            if $args->{show_type};
    }

    my $nest_indent = $indent.$args->{indent};
    if(@comment)
    {   my $comment = ' '.join("$nest_indent   ", @comment) .' ';
        push @res
          , $doc->createTextNode($indent)
          , $doc->createComment($comment);
    }

    my @elems = @{$ast->{elems} || []};
    foreach my $elem (@elems)
    {   if(ref $elem eq 'BLOCK' || ref $elem eq 'REP-BLOCK')
        {   push @res, xml_any($doc, $elem, $indent, $args);
        }
        elsif($elem->{tag} eq '_')
        {   push @res, $doc->createTextNode($indent.$elem->{example});
        }
        else
        {   push @res, $doc->createTextNode($indent)
              , scalar xml_any($doc, $elem, $nest_indent, $args);
        }
    }

    (my $outdent = $indent) =~ s/$args->{indent}$//;  # sorry

    if(my $example = $ast->{example})
    {  push @res, $doc->createTextNode
          (@comment ? "$indent$example$outdent" : $example)
    }

    if($ast->{type} && $args->{show_type})
    {   my $full = $ast->{type};
        my ($ns, $type) = unpack_type $full;
        # Don't known how to encode the namespace (yet)
        push @res, $doc->createAttribute(type => $type);
    }

    return @res
        if wantarray;

    my $node = $doc->createElement($ast->{tag});
    $node->addChild($_) for @res;
    $node->appendText($outdent) if @elems;
    $node;
}

=chapter DETAILS

=section Processing Wildcards
Wildcards are not (yet) supported.

=section Schema hooks
The C<before> and C<after> hooks are ignored.  The C<replace> hook will
produce an error.
=cut

1;
