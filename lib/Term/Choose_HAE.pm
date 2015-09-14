package Term::Choose_HAE;

use warnings;
use strict;
use 5.010001;

our $VERSION = '0.006';
use Exporter 'import';
our @EXPORT_OK = qw( choose );

use Unicode::GCString    qw();
use Text::ANSI::WideUtil qw( ta_mbtrunc );
use Parse::ANSIColor::Tiny;
use Term::ANSIColor qw(colored);
use Term::Choose::Constants qw(:choose);

use parent 'Term::Choose';

no warnings 'utf8';



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
    return '' if $len <= 0; #
    return ta_mbtrunc( $str, $len - 1 ); # -1 ?
}


sub __print_columns {
    #my $self = $_[0];
    ( my $str = $_[1] ) =~ s/\e\[[\d;]*m//msg;
    Unicode::GCString->new( $str )->columns();
}


sub __wr_cell {
    my( $self, $row, $col ) = @_;
    my( $wrap, $str) = ("", "");
    open TRAPSTDOUT, '>', \$wrap || die "can't open TRAPSTDOUT: $!";
    if ( $#{$self->{rc2idx}} == 0 ) {
        my $lngth = 0;
        if ( $col > 0 ) {
            for my $cl ( 0 .. $col - 1 ) {
                my $gcs_element = Unicode::GCString->new(
                    __strip_ansi_color(
                        $self->{list}[ $self->{rc2idx}[$row][$cl] ]
                    )
                );
                $lngth += $gcs_element->columns();
                $lngth += $self->{pad_one_row};
            }
        }
        $self->__goto( $row - $self->{row_on_top}, $lngth );
        select TRAPSTDOUT;
        $self->{plugin}->__bold_underline() if $self->{marked}[$row][$col];
        $self->{plugin}->__reverse()        if $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
        select STDOUT;
        $str = $self->{list}[$self->{rc2idx}[$row][$col]];
        my $gcs_element = Unicode::GCString->new(
            __strip_ansi_color($self->{list}[ $self->{rc2idx}[$row][$col] ]));
        $self->{i_col} += $gcs_element->columns();
    }
    else {
        $self->__goto( $row - $self->{row_on_top}, $col * $self->{col_width} );
        select TRAPSTDOUT;
        $self->{plugin}->__bold_underline() if $self->{marked}[$row][$col];
        $self->{plugin}->__reverse()        if $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
        select STDOUT;
        $str = $self->__unicode_sprintf( $self->{rc2idx}[$row][$col] );
        $self->{i_col} += $self->{length_longest};
    }
    select STDOUT;
    close TRAPSTDOUT;

    my $ansi   = Parse::ANSIColor::Tiny->new();
    my @codes  = ($wrap =~ m{ \e\[ ([\d;]*) m }xg);
    my @attr   = $ansi->identify(@codes ? @codes : "");
    my $marked = $ansi->parse($str);
    if ($attr[0] ne "clear") {
        foreach my $ele (@$marked) {
            $ele->[0] = [ $ansi->normalize(@{ $ele->[0] }, @attr) ];
        }
    }
    print join("",
        map { @{ $_->[0] } ? Term::ANSIColor::colored(@$_) : $_->[1] }
          @$marked);

    $self->{plugin}->__reset() if $self->{marked}[$row][$col] || $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
}


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose_HAE - Choose items from a list interactively.

=head1 VERSION

Version 0.006

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

C<Term::Choose_HAE> works like C<Term::Choose> except that the method/subroutine C<choose> from C<Term::Choose_HAE> does
not disable ANSI escape sequences; so with C<Term::Choose_HAE> it is possible to output coloured text.

See L<Term::Choose> for usage and options.

=head2 Occupied escape sequences

Don't use the "inverse" escape sequence (C<\e[7m>) (or corresponding coloures) because C<choose> uses "inverse" to mark
the cursor position and don't use the escape sequence "underline" (C<\e[7m>) because C<choose> in list context markes
the selected items with the "underline" escape sequence. Also reset escapes (C<\e[0m>) should only be at the end of the
strings.

=head1 REQUIREMENTS

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
