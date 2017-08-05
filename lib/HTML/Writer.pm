package HTML::Writer;
use strict;

use XML::Writer;
use XML::DTDParser;
use LWP::Simple;
use File::Slurp;
use Carp qw(croak);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT;
our $VERSION = 0.001;

our $DTD; # DTD structure, to trap errors e.g. illegal attributes
# default DTD file
my $dtdfile = "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd";
my $dtdtype;

our $__frag = ''; # XXX how _not_ make that a package global?

sub import {
    my $package = shift;
    $dtdfile = shift if $_[0];
    $dtdfile =~ /(\w+)\.dtd/ && ($dtdtype = ucfirst($1));
    my $dtd;
    if($dtdfile =~ /^http:\/\//) {
        $dtd = get($dtdfile);
    } else {
        foreach my $p(@INC) {
            if (-f "$p/$dtdfile") {
                $dtd = read_file("$p/$dtdfile") or die "$!\n";
                last;
            }
        }
    }
    $dtd =~ s/.*=== Imported Names =+-->//s; # trap 'die' in XML::DTDParser
    $DTD = ParseDTD $dtd or die "$!";
    my $elems = [ map { uc($_) } keys %$DTD ];
    my %s;
    my $attrs = [
    grep { s/-/_/g; ! $s{$_}++ }
        map { keys %{$DTD->{$_}->{'attributes'}} } keys %$DTD
    ];
    define_vocabulary($elems,$attrs);
    HTML::Writer->export_to_level(1,$package);
} 

sub define_vocabulary {
    no strict "refs";
    my($elems, $attrs) = @_;
    for (@$elems) {
        my $name = $_;
        *{$_} = sub(&) { _elem($name, @_) };
    }
    for (@$attrs) {
        my $name = $_;
        *{$_."_"} = sub($) { _attr($name, @_) };
    }
    push(@EXPORT,
        qw(render t ),
        @$elems, map {$_.'_'} @$attrs
    );
}

# root fragment
sub doc(&) {
    my ($content_fn) = @_;
    local $__frag = [undef,undef,undef];
    $content_fn->();
    $__frag->[2][0];
}

sub _elem {
    my ($elem_name, $content_fn) = @_;
    # an element is represented by the triple [name, attrs, children]
    my $elem = [$elem_name, undef, undef];
    my $ret =  do { local $__frag = $elem; $content_fn->(); };
    $elem->[2] = [$ret] if defined $ret and not $elem->[2];
    $__frag->[2] = [] unless $__frag->[2];
    push @{$__frag->[2]}, $elem;
    undef;
}

sub _attr {
    my ($attr_name, $val) = @_;
    $attr_name =~ s/_/-/g;
    my $parent = $__frag->[0];
    croak "Illegal attribute '$attr_name' in '$parent'"
        unless $DTD->{lc $parent}->{attributes}->{$attr_name};
    push @{$__frag->[1]}, [$attr_name, $val];
    undef;
}

sub t ($) { push @{$__frag->[2]}, @_ }

sub render_via_xml_writer {
    my $doc = shift;
    my $writer = XML::Writer->new(@_);  # extra args go to ->new()
    $writer->doctype( "html",
        "-//W3C//DTD XHTML 1.0 $dtdtype//EN",
        $dtdfile
    ) if 0;
    _render($writer,$doc);
    $writer->end();
    undef $__frag;
}

sub _render {
    my ($writer,$frag) = @_;
    my ($elem, $attrs, $children) = @$frag;
    
    $elem = lc($elem);
    $writer->startTag( $elem, map {@$_} @$attrs );
    for (@$children) {
        ref() ? _render($writer,$_) : $writer->characters($_);
    }
    $writer->endTag($elem);
}

sub render(&;$) {
    local $__frag = '';
    my $docfn  = shift;
    my $indent = shift;
    my $output = '';
    (defined $indent and $indent =~ /^\d+/) or ($indent = 2);
    render_via_xml_writer(
        doc( \&$docfn ),
        DATA_MODE => 1,
        UNSAFE => 1,
        DATA_INDENT => $indent,
        OUTPUT => \$output,
    );
    undef $__frag;
    undef $docfn;
    my $wantarray = wantarray;
    if(defined $wantarray) {
        return $wantarray == 0 ? $output : split /\n/, $output;
    }
    print $output;
}
1;
__END__

=head1 NAME

HTML::Writer - write HTML documents in perl

=head1 SYNOPSIS

    package Test;
    my $foo  = "my \$foo";
    our $bar = "our \$bar";
    my $pack = __PACKAGE__;
    sub baz { "Test::baz" }

    package Page {
        use HTML::Writer qw(xhtml1-transitional.dtd);
        push local @ISA, $pack;
        render {
            HTML {
                HEAD {
                    TITLE { "foo bar"};
                };
                BODY {
                    class_ "ugly";
                    onload_ "javascript: mumble()";
                    DIV {
                        class_ "foo";
                        id_    "bar";
                        t      "If in doubt, mumble.";
                        IMG { src_ "foo.jpg" }; 
                    };
                    TABLE {
                        my $c;
                        for ($foo, $bar, Page->baz()) {
                            TR {
                                TD { $_ }; TD { $c++};
                            } 
                        } 
                    };
                    DIV { class_ "bar"; t "End of that." };
                } 
            };
        };
    };

=head1 DESCRIPTION

blah blah...

=head1 AUTHOR

    shmem@cpan.org

=head1 CREDITS

This module is based on an idea by Tom Moertel (tmoertel on PerlMonks).

=head1 COPYRIGHT

       Copyright 2017, shmem

       This library is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=cut
