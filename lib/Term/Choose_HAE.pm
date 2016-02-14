package Term::Choose_HAE;

use warnings;
use strict;
use 5.010001;

our $VERSION = '0.021_01';
use Exporter 'import';
our @EXPORT_OK = qw( choose );

use Parse::ANSIColor::Tiny qw();
use Term::ANSIColor        qw( colored );
use Text::ANSI::WideUtil   qw( ta_mbtrunc );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use Term::Choose::Constants qw( :choose :linux );
use Term::Choose::LineFold qw( print_columns );

use parent 'Term::Choose';

no warnings 'utf8';



sub __valid_options {
    my $valid = Term::Choose::__valid_options();
    $valid->{fill_up} = '[ 0 1 2 ]';
    return $valid;
};


sub __defaults {
    my ( $self ) = @_;
    my $defaults = Term::Choose::__defaults();
    $defaults->{fill_up} = 1;
    return $defaults;
}


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

sub _strip_ansi_color {
    ( my $str = $_[0] ) =~ s/\e\[[\d;]*m//msg;
    return $str;
}

sub __print_columns {
    #my $self = $_[0];
    print_columns( _strip_ansi_color( $_[1] ) );
}


sub __wr_cell {
    my( $self, $row, $col ) = @_;
    my $is_current_pos = $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
    my $idx = $self->{rc2idx}[$row][$col];
    my( $wrap, $str ) = ( '', '' );
    open my $trapstdout, '>', \$wrap or die "can't open TRAPSTDOUT: $!";
    if ( $#{$self->{rc2idx}} == 0 ) {
        my $lngth = 0;
        if ( $col > 0 ) {
            for my $cl ( 0 .. $col - 1 ) {
                my $i = $self->{rc2idx}[$row][$cl];
                $lngth += $self->__print_columns( $self->{list}[$i] );
                $lngth += $self->{pad_one_row};
            }
        }
        $self->__goto( $row - $self->{row_on_top}, $lngth );
        select $trapstdout;
        print BOLD_UNDERLINE if $self->{marked}[$row][$col];    # use escape sequences for Win32 too and translate them with Win32::Console::ANSI
        print REVERSE        if $is_current_pos;                # so Parse::ANSIColor::Tiny can take into account these highlightings
        select STDOUT;
        $str = $self->{list}[$idx];
        $self->{i_col} += $self->__print_columns( $self->{list}[$idx] );
    }
    else {
        $self->__goto( $row - $self->{row_on_top}, $col * $self->{col_width} );
        select $trapstdout;
        print BOLD_UNDERLINE if $self->{marked}[$row][$col];
        print REVERSE        if $is_current_pos;
        select STDOUT;
        $str = $self->__unicode_sprintf( $idx );
        $self->{i_col} += $self->{length_longest};
    }
    select STDOUT;
    close $trapstdout;

    my $ansi   = Parse::ANSIColor::Tiny->new();
    my @codes  = ( $wrap =~ /\e\[([\d;]*)m/g );
    my @attr   = $ansi->identify( @codes ? @codes : '' );
    my $marked = $ansi->parse( $str );
    if ( $self->{length}[$idx] > $self->{avail_width} && $self->{fill_up} != 2 ) {
        if ( @$marked > 1 && ! @{$marked->[-1][0]} && $marked->[-1][1] =~ /^\.\.\.\z/ ) {
            $marked->[-1][0] = $marked->[-2][0];
        }
    }
    if ( $attr[0] ne 'clear' ) {
        if ( $self->{fill_up} == 1 && @$marked > 1 ) {
            if ( ! @{$marked->[0][0]} && $marked->[0][1] =~ /^\s+\z/ ) {
                $marked->[0][0] = $marked->[1][0];
            }
            if ( ! @{$marked->[-1][0]}&& $marked->[-1][1] =~ /^\s+\z/ ) {
                $marked->[-1][0] = $marked->[-2][0];
            }
        }
        if ( ! $self->{fill_up} ) {
            if ( ! @{$marked->[0][0]} && $marked->[0][1] =~ /^(\s+)\S/ ) {
                my $tmp = $1;
                $marked->[0][1] =~ s/^\s+//;
                unshift @$marked, [ [], $tmp ];
            }
            elsif ( ! @{$marked->[-1][0]} && $marked->[-1][1] =~ /\S(\s+)\z/ ) {
                my $tmp = $1;
                $marked->[-1][1] =~ s/\s+\z//;
                push @$marked, [ [], $tmp ];
            }
        }
        for my $i ( 0 .. $#$marked ) {
            if ( ! $self->{fill_up} ) {
                if ( $i == 0 || $i == $#$marked ) {
                    if ( ! @{$marked->[$i][0]} && $marked->[$i][1] =~ /^\s+\z/ ) {
                        next;
                    }
                }
            }
            $marked->[$i][0] = [ $ansi->normalize( @{ $marked->[$i][0] }, @attr ) ];
        }
    }
    print join '', map { @{$_->[0]} ? colored( @$_ ) : $_->[1] } @$marked;
    if ( $self->{marked}[$row][$col] || $is_current_pos ) {
        print RESET;
    }
}


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose_HAE - Choose items from a list interactively.

=head1 VERSION

Version 0.021_01

=cut

=head1 SYNOPSIS

Functional interface:

    use Term::Choose_HAE qw( choose );
    use Term::ANSIColor;

    my $array_ref = [
        colored( 'red_string', 'red'),
        colored( 'green_string', 'green'),
        colored( 'blue_string', 'cyan'),
    ];

    my $choice = choose( $array_ref );                            # single choice
    print "$choice\n";

    my @choices = choose( [ 1 .. 100 ], { justify => 1 } );       # multiple choice
    print "@choices\n";

    choose( [ 'Press ENTER to continue' ], { prompt => '' } );    # no choice

Object-oriented interface:

    use Term::Choose_HAE;
    use Term::ANSIColor;

    my $array_ref = [
        colored( 'red_string', 'red'),
        colored( 'green_string', 'green'),
        colored( 'blue_string', 'cyan'),
    ];

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

C<Term::Choose_HAE> works like C<Term::Choose> except that C<choose> from C<Term::Choose_HAE> does not disable ANSI
escape sequences; so with C<Term::Choose_HAE> it is possible to output colored text. On a MSWin32 OS
L<Win32::Console::ANSI> is used to translate the ANSI escape sequences. C<Term::Choose_HAE> provides one additional
option: I<fill_up>.

Else see L<Term::Choose> for usage and options.

=head2 Occupied escape sequences

C<choose> uses the "inverse" escape sequence to mark the cursor position and the "underline" and "bold" escape sequences
to mark the selected items in list context.

=head1 OPTIONS

C<Term::Choose_HAE> inherits the options from L<Term::Choose|Term::Choose/OPTIONS> and adds the option I<fill_up>:

=head2 fill_up

0 - off

1 - fill up selected items with the adjacent color. (default)

2 - fill up selected items with the default color.

If I<fill_up> is enabled, the highlighting of the cursor position and in list context the highlighting of the selected
items has always the width of the column.

=over

=item

I<fill_up> set to C<1>: the color of the highlighting of leading and trailings spaces is set to the color of
the highlighting of the adjacent non-space character of the item if these spaces are not embedded in escape sequences.

=item

I<fill_up> set to C<2>: leading and trailings spaces are highlighted with the default color for highlighting if
these spaces are not embedded in escape sequences.

=back

If I<fill_up> is disabled, leading and trailing spaces are not highlighted if they are not embedded in escape sequences.

=head1 REQUIREMENTS

The requirements are the same as with C<Term::Choose> except that the minimum Perl version for C<Term::Choose_HAE> is
5.10.1 instead of 5.8.3.

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

Copyright (C) 2015-2016 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
