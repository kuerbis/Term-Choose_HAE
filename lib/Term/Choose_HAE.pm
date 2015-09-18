package Term::Choose_HAE;

use warnings;
use strict;
use 5.010001;

our $VERSION = '0.011';
use Exporter 'import';
our @EXPORT_OK = qw( choose );

use Parse::ANSIColor::Tiny qw();
use Term::ANSIColor        qw( colored );
use Text::ANSI::WideUtil   qw( ta_mbtrunc );
use Unicode::GCString      qw();

use Term::Choose::Constants qw(:choose);

use parent 'Term::Choose';

no warnings 'utf8';


sub __valid_options {
    my $valid = Term::Choose::__valid_options();
    $valid->{fill_up} = '[ 0 1 ]';
    return $valid;
};


sub choose {
    if ( ref $_[0] ne 'Term::Choose_HAE' ) {
        return Term::Choose_HAE->new()->Term::Choose::__choose( @_ );
    }
    my $self = shift;
    return $self->Term::Choose::__choose( @_ );
}


sub __copy_orig_list {
    my ( $self ) = @_;
    if ( $self->{ll} ) {
        $self->{list} = [ map {
            my $copy = $_;
            if ( ! $copy ) {
                $copy = $self->{undef} if ! defined $copy;
                $copy = $self->{empty} if $copy eq '';
            }
            $copy;
        } @{$self->{orig_list}} ];
    }
    else {
        $self->{list} = [ map {
            my $copy = $_;
            if ( ! $copy ) {
                $copy = $self->{undef} if ! defined $copy;
                $copy = $self->{empty} if $copy eq '';
            }
            if ( ref $copy ) {
                $copy = sprintf "%s(0x%x)", ref $copy, $copy;
            }
            $copy =~ s/\p{Space}/ /g;               # replace, but don't squash sequences of spaces
            $copy =~ s/\p{C}/$&=~m|\e| && $&/eg;    # remove \p{C} but keep \e
            $copy;
        } @{$self->{orig_list}} ];
    }
}


sub __unicode_trim {
    my ( $self, $str, $len ) = @_;
    return ta_mbtrunc( $str, $len );
}


sub __print_columns {
    #my $self = $_[0];
    Unicode::GCString->new( __strip_ansi_color( $_[1] ) )->columns();
}

sub __strip_ansi_color {
    ( my $str = $_[0] ) =~ s/\e\[[\d;]*m//msg;
    return $str;
}


sub __wr_cell {
    my( $self, $row, $col ) = @_;
    my $cell_is_cursor_pos = ( $row == $self->{pos}[ROW] && $col == $self->{pos}[COL] ) ? 1 : 0;
    my $cell_is_selected   = $self->{marked}[$row][$col] ? 1 : 0;
    my $idx = $self->{rc2idx}[$row][$col];
    my( $wrap, $str ) = ( '', '' );
    open my $TRAPSTDOUT, '>', \$wrap or die "can't open TRAPSTDOUT: $!";
    if ( $#{$self->{rc2idx}} == 0 ) {
        my $lngth = 0;
        if ( $col > 0 ) {
            for my $cl ( 0 .. $col - 1 ) {
                $lngth += $self->__print_columns( $self->{list}[ $self->{rc2idx}[$row][$cl] ] );
                $lngth += $self->{pad_one_row};
            }
        }
        $self->__goto( $row - $self->{row_on_top}, $lngth );
        select $TRAPSTDOUT;
        $self->{plugin}->__bold_underline() if $cell_is_selected;
        $self->{plugin}->__reverse()        if $cell_is_cursor_pos;
        select STDOUT;
        $str = $self->{list}[$idx];
        $self->{i_col} += $self->__print_columns( $self->{list}[$idx] );
    }
    else {
        $self->__goto( $row - $self->{row_on_top}, $col * $self->{col_width} );
        select $TRAPSTDOUT;
        $self->{plugin}->__bold_underline() if $cell_is_selected;
        $self->{plugin}->__reverse()        if $cell_is_cursor_pos;
        select STDOUT;
        $str = $self->__unicode_sprintf( $idx );
        $self->{i_col} += $self->{length_longest};
    }
    select STDOUT;
    close $TRAPSTDOUT;

    my $ansi   = Parse::ANSIColor::Tiny->new();
    my @codes  = ( $wrap =~ m{ \e\[ ([\d;]*) m }xg );
    my @attr   = $ansi->identify( @codes ? @codes : '' );
    my $marked = $ansi->parse( $str );
    if ( ( $self->{length}[$idx] // $self->{length_longest} ) > $self->{avail_width} ) {
        if ( @$marked > 1 && ! @{$marked->[-1][0]} && $marked->[-1][1] =~ /^\.\.\.\z/ ) {
            $marked->[-1][0] = $marked->[-2][0];
        }
    }
    if ( $attr[0] ne 'clear' ) {
        for my $i ( 0 .. $#$marked ) {
            if ( @$marked > 1 && ! @{$marked->[$i][0]} ) {
                if ( $i == 0         && ( $self->{justify} == 1 || $self->{justify} == 2 ) && $marked->[$i][1] =~ /^\s*\z/ ) {
                    if ( ! $self->{fill_up} ) {
                        next;
                    }
                    $marked->[$i][0] = $marked->[$i+1][0];
                }
                if ( $i == $#$marked && ( $self->{justify} == 0 || $self->{justify} == 2 ) && $marked->[$i][1] =~ /^\s*\z/ ) {
                    if ( ! $self->{fill_up} ) {
                        next;
                    }
                    $marked->[$i][0] = $marked->[$i-1][0];
                }
            }
            $marked->[$i][0] = [ $ansi->normalize( @{ $marked->[$i][0] }, @attr ) ];
        }
    }
    print join '', map { @{$_->[0]} ? colored( @$_ ) : $_->[1] } @$marked;
    if ( $cell_is_selected || $cell_is_cursor_pos ) {
        $self->{plugin}->__reset();
    }
}


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose_HAE - Choose items from a list interactively.

=head1 VERSION

Version 0.011

=cut

=head1 SYNOPSIS

Functional interface:

    use Term::Choose_HAE qw( choose );

    my $array_ref = [ qw( one two three four five ) ];

    my $choice = choose( $array_ref );                            # single choice
    print "$choice\n";

    my @choices = choose( [ 1 .. 100 ], { justify => 1 } );       # multiple choice
    print "@choices\n";

    choose( [ 'Press ENTER to continue' ], { prompt => '' } );    # no choice

Object-oriented interface:

    use Term::Choose_HAE;

    my $array_ref = [ "\e[31mred\e[0m", "\e[32mgreen\e[0m", "\e[34mblue\e[0m" ];

    my $new = Term::Choose_HAE->new();

    my $choice = $new->choose( $array_ref );                       # single choice
    print "$choice\n";

    $new->config( { justify => 1 } );
    my @choices = $new->choose( [ 1 .. 100 ] );                    # multiple choice
    print "@choices\n";

    my $stopp = Term::Choose_HAE->new( { prompt => '' } );
    $stopp->choose( [ 'Press ENTER to continue' ] );               # no choice

=head1 DESCRIPTION

Choose interactively from a list of items.

C<Term::Choose_HAE> works like C<Term::Choose> except that C<choose> from C<Term::Choose_HAE> does
not disable ANSI escape sequences; so with C<Term::Choose_HAE> it is possible to output colored text.

C<Term::Choose_HAE> provides one additional option: I<fill_up>.

Else see L<Term::Choose> for usage and options.

=head2 Occupied escape sequences

C<choose> uses the "inverse" escape sequence (C<\e[7m>) to mark the cursor position and the "underline" escape sequence
(C<\e[7m>) to mark
the selected items in list context.

=head1 OPTIONS

C<Term::Choose_HAE> provides one additional option to the options which are available with
L<Term::Choose|Term::Choose/OPTIONS>:

=head2 fill_up

0 - off (default)

1 - on

If I<fill_up> is enabled, the highlighting of the cursor position and in list context the highlighting of the selected
items has always the width of the column. If I<fill_up> is disabled, the highlighting has the width of the highlighted
item.

=head1 REQUIREMENTS

The requirements are the same as with C<Term::Choose> except that the minimum Perl version for C<Term::Choose_HAE>
is 5.10.1
instead of 5.8.3.

=head2 Perl version

Requires Perl version 5.10.1 or greater.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::Choose_HAE

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Based on a patch for C<Term::Choose> from Stephan Sachse.

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
