package Term::Choose_HAE;

use warnings;
use strict;
use 5.008003;

our $VERSION = '0.005';
use Exporter 'import';
our @EXPORT_OK = qw( choose );

use Unicode::GCString    qw();
use Text::ANSI::WideUtil qw( ta_mbtrunc );

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



1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose_HAE - Choose items from a list interactively.

=head1 VERSION

Version 0.005

=cut

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::Choose

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012-2015 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
