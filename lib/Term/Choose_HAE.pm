package Term::Choose_HAE;

use warnings;
use strict;
use 5.008003;

our $VERSION = '0.001';
use Exporter 'import';
our @EXPORT_OK = qw( choose );

use Carp                 qw( croak carp );
use Text::LineFold       qw();
use Unicode::GCString    qw();
use Text::ANSI::WideUtil qw( ta_mbtrunc );

use parent 'Term::Choose';
use Term::Choose::Constants qw( :choose );

no warnings 'utf8';
#use Log::Log4perl qw( get_logger );
# #Log::Log4perl::init() called in main::
#my $log = get_logger( __PACKAGE__ );

my $Plugin_Package;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Term::Choose::Win32;
        $Plugin_Package = 'Term::Choose::Win32';
    }
    else {
        require Term::Choose::Linux;
        $Plugin_Package = 'Term::Choose::Linux';
    }
}


sub new {
    my $class = shift;
    my ( $opt ) = @_;
    croak "new: called with " . @_ . " arguments - 0 or 1 arguments expected" if @_ > 1;
    my $self = bless {}, $class;
    if ( defined $opt ) {
        croak "new: the (optional) argument must be a HASH reference" if ref $opt ne 'HASH';
        $self->Term::Choose::__validate_and_add_options( $opt );
    }
    $self->{plugin} = $Plugin_Package->new();
    return $self;
}


sub DESTROY {
    my ( $self ) = @_;
    $self->Term::Choose::__reset_term();
}


sub config {
    my $self = shift;
    my ( $opt ) = @_;
    croak "config: called with " . @_ . " arguments - 0 or 1 arguments expected" if @_ > 1;
    if ( defined $opt ) {
        croak "config: the argument must be a HASH reference" if ref $opt ne 'HASH';
        $self->Term::Choose::__validate_and_add_options( $opt );
    }
}


sub choose {
    if ( ref $_[0] ne 'Term::Choose_HAE' ) {
        return Term::Choose_HAE->new()->choose( @_ );
    }
    my $self = shift;
    my ( $orig_list_ref, $opt ) = @_;
    croak "choose: called with " . @_ . " arguments - 1 or 2 arguments expected" if @_ < 1 || @_ > 2;
    croak "choose: the first argument must be an ARRAY reference" if ref $orig_list_ref ne 'ARRAY';
    if ( defined $opt ) {
        croak "choose: the (optional) second argument must be a HASH reference" if ref $opt ne 'HASH';
        $self->{backup_opt} = { map{ $_ => $self->{$_} } keys %$opt };
        $self->Term::Choose::__validate_and_add_options( $opt );
    }
    if ( ! @$orig_list_ref ) {
        return;
    }
    local $\ = undef;
    local $, = undef;
    local $| = 1;
    $self->{wantarray} = wantarray;
    $self->Term::Choose::__undef_to_defaults();
    $self->{orig_list} = $orig_list_ref;
    $self->__copy_orig_list();
    $self->__length_longest();
    $self->{col_width} = $self->{length_longest} + $self->{pad};
    local $SIG{'INT'} = sub {
        # my $signame = shift;
        exit 1;
    };
    $self->Term::Choose::__init_term();
    $self->Term::Choose::__write_first_screen();

    while ( 1 ) {
        my $key = $self->Term::Choose::__get_key();
        if ( ! defined $key ) {
            $self->Term::Choose::__reset_term( 1 );
            carp "EOT: $!";
            return;
        }
        my ( $new_width, $new_height ) = $self->{plugin}->__get_term_size();
        if ( $new_width != $self->{term_width} || $new_height != $self->{term_height} ) {
            $self->{list} = $self->__copy_orig_list();
            $self->{default} = $self->{rc2idx}[$self->{pos}[ROW]][$self->{pos}[COL]];
            if ( $self->{wantarray} && @{$self->{marked}} ) {
                $self->{mark} = $self->Term::Choose::__marked_to_idx();
            }
            print CR;
            my $up = $self->{i_row} + $self->{nr_prompt_lines};
            $self->{plugin}->__up( $up ) if $up;
            $self->{plugin}->__clear_to_end_of_screen();
            $self->__write_first_screen();
            next;
        }
        next if $key == NEXT_get_key;
        next if $key == KEY_Tilde;

        # $self->{rc2idx} holds the new list (AoA) formated in "__size_and_layout" appropirate to the chosen layout.
        # $self->{rc2idx} does not hold the values dircetly but the respective list indexes from the original list.
        # If the original list would be ( 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' ) and the new formated list should be
        #     a d g
        #     b e h
        #     c f
        # then the $self->{rc2idx} would look like this
        #     0 3 6
        #     1 4 7
        #     2 5
        # So e.g. the second value in the second row of the new list would be $self->{list}[ $self->{rc2idx}[1][1] ].
        # On the other hand the index of the last row of the new list would be $#{$self->{rc2idx}}
        # or the index of the last column in the first row would be $#{$self->{rc2idx}[0]}.

        if ( $key == KEY_j || $key == VK_DOWN ) {
            if ( $#{$self->{rc2idx}} == 0 || ! (    $self->{rc2idx}[$self->{pos}[ROW]+1]
                                                 && $self->{rc2idx}[$self->{pos}[ROW]+1][$self->{pos}[COL]] )
            ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{pos}[ROW]++;
                if ( $self->{pos}[ROW] <= $self->{p_end} ) {
                    $self->__wr_cell( $self->{pos}[ROW] - 1, $self->{pos}[COL] );
                    $self->__wr_cell( $self->{pos}[ROW],     $self->{pos}[COL] );
                }
                else {
                    $self->{row_on_top} = $self->{pos}[ROW];
                    $self->{p_begin} = $self->{p_end} + 1;
                    $self->{p_end}   = $self->{p_end} + $self->{avail_height};
                    $self->{p_end}   = $#{$self->{rc2idx}} if $self->{p_end} > $#{$self->{rc2idx}};
                    $self->Term::Choose::__wr_screen();
                }
            }
        }
        elsif ( $key == KEY_k || $key == VK_UP ) {
            if ( $self->{pos}[ROW] == 0 ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{pos}[ROW]--;
                if ( $self->{pos}[ROW] >= $self->{p_begin} ) {
                    $self->__wr_cell( $self->{pos}[ROW] + 1, $self->{pos}[COL] );
                    $self->__wr_cell( $self->{pos}[ROW],     $self->{pos}[COL] );
                }
                else {
                    $self->{row_on_top} = $self->{pos}[ROW] - ( $self->{avail_height} - 1 );
                    $self->{p_end}   = $self->{p_begin} - 1;
                    $self->{p_begin} = $self->{p_begin} - $self->{avail_height};
                    $self->{p_begin} = 0 if $self->{p_begin} < 0;
                    $self->Term::Choose::__wr_screen();
                }
            }
        }
        elsif ( $key == KEY_TAB || $key == CONTROL_I ) {
            if (    $self->{pos}[ROW] == $#{$self->{rc2idx}}
                 && $self->{pos}[COL] == $#{$self->{rc2idx}[$self->{pos}[ROW]]}
            ) {
                $self->Term::Choose::__beep();
            }
            else {
                if ( $self->{pos}[COL] < $#{$self->{rc2idx}[$self->{pos}[ROW]]} ) {
                    $self->{pos}[COL]++;
                    $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] - 1 );
                    $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
                }
                else {
                    $self->{pos}[ROW]++;
                    if ( $self->{pos}[ROW] <= $self->{p_end} ) {
                        $self->{pos}[COL] = 0;
                        $self->__wr_cell( $self->{pos}[ROW] - 1, $#{$self->{rc2idx}[$self->{pos}[ROW] - 1]} );
                        $self->__wr_cell( $self->{pos}[ROW],     $self->{pos}[COL] );
                    }
                    else {
                        $self->{row_on_top} = $self->{pos}[ROW];
                        $self->{p_begin} = $self->{p_end} + 1;
                        $self->{p_end}   = $self->{p_end} + $self->{avail_height};
                        $self->{p_end}   = $#{$self->{rc2idx}} if $self->{p_end} > $#{$self->{rc2idx}};
                        $self->{pos}[COL] = 0;
                        $self->Term::Choose::__wr_screen();
                    }
                }
            }
        }
        elsif ( $key == KEY_BSPACE || $key == CONTROL_H || $key == KEY_BTAB ) {
            if ( $self->{pos}[COL] == 0 && $self->{pos}[ROW] == 0 ) {
                $self->Term::Choose::__beep();
            }
            else {
                if ( $self->{pos}[COL] > 0 ) {
                    $self->{pos}[COL]--;
                    $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] + 1 );
                    $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
                }
                else {
                    $self->{pos}[ROW]--;
                    if ( $self->{pos}[ROW] >= $self->{p_begin} ) {
                        $self->{pos}[COL] = $#{$self->{rc2idx}[$self->{pos}[ROW]]};
                        $self->__wr_cell( $self->{pos}[ROW] + 1, 0 );
                        $self->__wr_cell( $self->{pos}[ROW],     $self->{pos}[COL] );
                    }
                    else {
                        $self->{row_on_top} = $self->{pos}[ROW] - ( $self->{avail_height} - 1 );
                        $self->{p_end}   = $self->{p_begin} - 1;
                        $self->{p_begin} = $self->{p_begin} - $self->{avail_height};
                        $self->{p_begin} = 0 if $self->{p_begin} < 0;
                        $self->{pos}[COL] = $#{$self->{rc2idx}[$self->{pos}[ROW]]};
                        $self->Term::Choose::__wr_screen();
                    }
                }
            }
        }
        elsif ( $key == KEY_l || $key == VK_RIGHT ) {
            if ( $self->{pos}[COL] == $#{$self->{rc2idx}[$self->{pos}[ROW]]} ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{pos}[COL]++;
                $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] - 1 );
                $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
            }
        }
        elsif ( $key == KEY_h || $key == VK_LEFT ) {
            if ( $self->{pos}[COL] == 0 ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{pos}[COL]--;
                $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] + 1 );
                $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
            }
        }
        elsif ( $key == CONTROL_B || $key == VK_PAGE_UP ) {
            if ( $self->{p_begin} <= 0 ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{row_on_top} = $self->{avail_height} * ( int( $self->{pos}[ROW] / $self->{avail_height} ) - 1 );
                $self->{pos}[ROW] -= $self->{avail_height};
                $self->{p_begin} = $self->{row_on_top};
                $self->{p_end}   = $self->{p_begin} + $self->{avail_height} - 1;
                $self->Term::Choose::__wr_screen();
            }
        }
        elsif ( $key == CONTROL_F || $key == VK_PAGE_DOWN ) {
            if ( $self->{p_end} >= $#{$self->{rc2idx}} ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{row_on_top} = $self->{avail_height} * ( int( $self->{pos}[ROW] / $self->{avail_height} ) + 1 );
                $self->{pos}[ROW] += $self->{avail_height};
                if ( $self->{pos}[ROW] >= $#{$self->{rc2idx}} ) {
                    if ( $#{$self->{rc2idx}} == $self->{row_on_top} || ! $self->{rest} || $self->{pos}[COL] <= $self->{rest} - 1 ) {
                        if ( $self->{pos}[ROW] != $#{$self->{rc2idx}} ) {
                            $self->{pos}[ROW] = $#{$self->{rc2idx}};
                        }
                        if ( $self->{rest} && $self->{pos}[COL] > $self->{rest} - 1 ) {
                            $self->{pos}[COL] = $#{$self->{rc2idx}[$self->{pos}[ROW]]};
                        }
                    }
                    else {
                        $self->{pos}[ROW] = $#{$self->{rc2idx}} - 1;
                    }
                }
                $self->{p_begin} = $self->{row_on_top};
                $self->{p_end}   = $self->{p_begin} + $self->{avail_height} - 1;
                $self->{p_end}   = $#{$self->{rc2idx}} if $self->{p_end} > $#{$self->{rc2idx}};
                $self->Term::Choose::__wr_screen();
            }
        }
        elsif ( $key == CONTROL_A || $key == VK_HOME ) {
            if ( $self->{pos}[COL] == 0 && $self->{pos}[ROW] == 0 ) {
                $self->Term::Choose::__beep();
            }
            else {
                $self->{row_on_top} = 0;
                $self->{pos}[ROW] = $self->{row_on_top};
                $self->{pos}[COL] = 0;
                $self->{p_begin} = $self->{row_on_top};
                $self->{p_end}   = $self->{p_begin} + $self->{avail_height} - 1;
                $self->{p_end}   = $#{$self->{rc2idx}} if $self->{p_end} > $#{$self->{rc2idx}};
                $self->Term::Choose::__wr_screen();
            }
        }
        elsif ( $key == CONTROL_E || $key == VK_END ) {
            if ( $self->{order} == 1 && $self->{rest} ) {
                if (    $self->{pos}[ROW] == $#{$self->{rc2idx}} - 1
                     && $self->{pos}[COL] == $#{$self->{rc2idx}[$self->{pos}[ROW]]}
                ) {
                    $self->Term::Choose::__beep();
                }
                else {
                    $self->{row_on_top} = @{$self->{rc2idx}} - ( @{$self->{rc2idx}} % $self->{avail_height} || $self->{avail_height} );
                    $self->{pos}[ROW] = $#{$self->{rc2idx}} - 1;
                    $self->{pos}[COL] = $#{$self->{rc2idx}[$self->{pos}[ROW]]};
                    if ( $self->{row_on_top} == $#{$self->{rc2idx}} ) {
                        $self->{row_on_top} = $self->{row_on_top} - $self->{avail_height};
                        $self->{p_begin} = $self->{row_on_top};
                        $self->{p_end}   = $self->{p_begin} + $self->{avail_height} - 1;
                    }
                    else {
                        $self->{p_begin} = $self->{row_on_top};
                        $self->{p_end}   = $#{$self->{rc2idx}};
                    }
                    $self->Term::Choose::__wr_screen();
                }
            }
            else {
                if (    $self->{pos}[ROW] == $#{$self->{rc2idx}}
                     && $self->{pos}[COL] == $#{$self->{rc2idx}[$self->{pos}[ROW]]}
                ) {
                    $self->Term::Choose::__beep();
                }
                else {
                    $self->{row_on_top} = @{$self->{rc2idx}} - ( @{$self->{rc2idx}} % $self->{avail_height} || $self->{avail_height} );
                    $self->{pos}[ROW] = $#{$self->{rc2idx}};
                    $self->{pos}[COL] = $#{$self->{rc2idx}[$self->{pos}[ROW]]};
                    $self->{p_begin} = $self->{row_on_top};
                    $self->{p_end}   = $#{$self->{rc2idx}};
                    $self->Term::Choose::__wr_screen();
                }
            }
        }
        elsif ( $key == KEY_q || $key == CONTROL_D ) {
            $self->Term::Choose::__reset_term( 1 );
            return;
        }
        elsif ( $key == CONTROL_C ) {
            $self->Term::Choose::__reset_term( 1 );
            print STDERR "^C\n";
            exit 1;
        }
        elsif ( $key == KEY_ENTER ) {
            #my @chosen; # ###
            if ( ! defined $self->{wantarray} ) {
                $self->Term::Choose::__reset_term( 1 );
                return;
            }
            elsif ( $self->{wantarray} ) {
                $self->{marked}[$self->{pos}[ROW]][$self->{pos}[COL]] = 1;
                my $chosen = $self->Term::Choose::__marked_to_idx();
                my $index = $self->{index};
                $self->Term::Choose::__reset_term( 1 );
                return $index ? @$chosen : map { $self->{orig_list}[$_] } @$chosen;
            }
            else {
                my $i = $self->{rc2idx}[$self->{pos}[ROW]][$self->{pos}[COL]];
                my $chosen = $self->{index} ? $i : $self->{orig_list}[$i];
                $self->Term::Choose::__reset_term( 1 );
                return $chosen;
            }
        }
        elsif ( $key == KEY_SPACE ) {
            if ( $self->{wantarray} ) {
                my $locked = 0;
                if ( $self->{no_spacebar} ) {
                    for my $no_spacebar ( @{$self->{no_spacebar}} ) {
                        if ( $self->{rc2idx}[$self->{pos}[ROW]][$self->{pos}[COL]] == $no_spacebar ) {
                            ++$locked;
                            last;
                        }
                    }
                }
                if ( $locked ) {
                    $self->Term::Choose::__beep();
                }
                else {
                    if ( ! $self->{marked}[$self->{pos}[ROW]][$self->{pos}[COL]] ) {
                        $self->{marked}[$self->{pos}[ROW]][$self->{pos}[COL]] = 1;
                    }
                    else {
                        $self->{marked}[$self->{pos}[ROW]][$self->{pos}[COL]] = 0;
                    }
                    $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
                }
            }
        }
        elsif ( $key == CONTROL_SPACE ) {
            if ( $self->{wantarray} ) {
                if ( $self->{pos}[ROW] == 0 ) {
                    for my $i ( 0 .. $#{$self->{rc2idx}} ) {
                        for my $j ( 0 .. $#{$self->{rc2idx}[$i]} ) {
                            $self->{marked}[$i][$j] = $self->{marked}[$i][$j] ? 0 : 1;
                        }
                    }
                }
                else {
                    for my $i ( $self->{p_begin} .. $self->{p_end} ) {
                        for my $j ( 0 .. $#{$self->{rc2idx}[$i]} ) {
                            $self->{marked}[$i][$j] = $self->{marked}[$i][$j] ? 0 : 1;
                        }
                    }
                }
                if ( defined $self->{no_spacebar} ) {
                    $self->Term::Choose::__idx_to_marked( $self->{no_spacebar}, 0 );
                }
                $self->Term::Choose::__wr_screen();
            }
            else {
                $self->Term::Choose::__beep();
            }
        }
        else {
            $self->Term::Choose::__beep();
        }
    }
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
            $copy =~ s/\p{Space}/ /g;  # replace, but don't squash sequences of spaces

            #$copy =~ s/\p{C}//g;
            $copy =~ s/\p{C}/$&=~m|\e| && $&/eg;  # remove \p{C} but keep \e

            $copy;
        } @{$self->{orig_list}} ];
    }
}


sub __length_longest {
    my ( $self ) = @_;
    if ( $self->{ll} ) {
        $self->{length_longest} = $self->{ll};
        $self->{length} = [];
    }
    else {
        my $list = $self->{list};
        my $len = [];
        my $longest = 0;
        for my $i ( 0 .. $#$list ) {

            #my $gcs = Unicode::GCString->new( $list->[$i] );
            #my $gcs = Unicode::GCString->new( $list->[$i] =~ s{ \e\[ [\d;]* m }{}xmsgr );
            #my $gcs = Unicode::GCString->new( ( my $s = $list->[$i] ) =~ s{ \e\[ [\d;]* m }{}xmsg );
            my $gcs = Unicode::GCString->new( _strip_ansi_color( $list->[$i] ) );

            $len->[$i] = $gcs->columns();
            $longest = $len->[$i] if $len->[$i] > $longest;
        }
        $self->{length_longest} = $longest;
        $self->{length} = $len;
    }
}


sub __prepare_promptline {
    my ( $self ) = @_;
    if ( $self->{prompt} eq '' ) {
        $self->{nr_prompt_lines} = 0;
        return;
    }
    $self->{prompt} =~ s/[^\n\P{Space}]/ /g;
    $self->{prompt} =~ s/[^\n\P{C}]//g;

    #my $gcs_prompt = Unicode::GCString->new( $self->{prompt} );
    my $gcs_prompt = Unicode::GCString->new( _strip_ansi_color( $self->{prompt} ) );

    if ( $self->{prompt} !~ /\n/ && $gcs_prompt->columns() <= $self->{avail_width} ) {
        $self->{nr_prompt_lines} = 1;
        $self->{prompt_copy} = $self->{prompt} . "\n\r";
    }
    else {
        my $line_fold = Text::LineFold->new(
            Charset=> 'utf-8',
            ColMax => $self->{avail_width},
            OutputCharset => '_UNICODE_',
            Urgent => 'FORCE'
        );
        if ( defined $self->{lf} ) {
            $self->{prompt_copy} = $line_fold->fold( ' ' x $self->{lf}[0], ' ' x $self->{lf}[1], $self->{prompt} );
        }
        else {
            $self->{prompt_copy} = $line_fold->fold( $self->{prompt}, 'PLAIN' );
        }
        $self->{nr_prompt_lines} = $self->{prompt_copy} =~ s/\n/\n\r/g;
    }
}


sub __size_and_layout {
    my ( $self ) = @_;
    $self->{rc2idx} = [];
    if ( $self->{length_longest} > $self->{avail_width} ) {
        $self->{avail_col_width} = $self->{avail_width};
        $self->{layout} = 3;
    }
    else {
        $self->{avail_col_width} = $self->{length_longest};
    }
    my $all_in_first_row;
    if ( $self->{layout} == 0 || $self->{layout} == 1 ) {
        for my $idx ( 0 .. $#{$self->{list}} ) {
            $all_in_first_row .= $self->{list}[$idx];
            $all_in_first_row .= ' ' x $self->{pad_one_row} if $idx < $#{$self->{list}};

            #my $gcs_first_row = Unicode::GCString->new( $all_in_first_row );
            my $gcs_first_row = Unicode::GCString->new( _strip_ansi_color( $all_in_first_row ) );

            if ( $gcs_first_row->columns() > $self->{avail_width} ) {
                $all_in_first_row = '';
                last;
            }
        }
    }
    if ( $all_in_first_row ) {
        $self->{rc2idx}[0] = [ 0 .. $#{$self->{list}} ];
    }
    elsif ( $self->{layout} == 3 ) {
        if ( $self->{length_longest} <= $self->{avail_width} ) {
            for my $idx ( 0 .. $#{$self->{list}} ) {
                $self->{rc2idx}[$idx][0] = $idx;
            }
        }
        else {
            for my $idx ( 0 .. $#{$self->{list}} ) {
                my $gcs_element = Unicode::GCString->new( $self->{list}[$idx] );

                my $gcs_count = Unicode::GCString->new( _strip_ansi_color( $self->{list}[$idx] ) );
                #if ( $gcs_element->columns > $self->{avail_width} ) {
                if ( $gcs_count->columns > $self->{avail_width} ) {

                    $self->{list}[$idx] = $self->__unicode_trim( $gcs_element, $self->{avail_width} - 3 ) . '...';
                }
                $self->{rc2idx}[$idx][0] = $idx;
            }
        }
    }
    else {
        my $tmp_avail_width = $self->{avail_width} + $self->{pad} - WIDTH_CURSOR;
        # auto_format
        if ( $self->{layout} == 1 || $self->{layout} == 2 ) {
            my $tmc = int( @{$self->{list}} / $self->{avail_height} );
            $tmc++ if @{$self->{list}} % $self->{avail_height};
            $tmc *= $self->{col_width};
            if ( $tmc < $tmp_avail_width ) {
                $tmc = int( $tmc + ( ( $tmp_avail_width - $tmc ) / 1.5 ) ) if $self->{layout} == 1;
                $tmc = int( $tmc + ( ( $tmp_avail_width - $tmc ) / 4 ) )   if $self->{layout} == 2;
                $tmp_avail_width = $tmc;
            }
        }
        # order
        my $cols_per_row = int( $tmp_avail_width / $self->{col_width} );
        $cols_per_row = 1 if $cols_per_row < 1;
        $self->{rest} = @{$self->{list}} % $cols_per_row;
        if ( $self->{order} == 1 ) {
            my $rows = int( ( @{$self->{list}} - 1 + $cols_per_row ) / $cols_per_row );
            my @rearranged_idx;
            my $begin = 0;
            my $end = $rows - 1;
            for my $c ( 0 .. $cols_per_row - 1 ) {
                --$end if $self->{rest} && $c >= $self->{rest};
                $rearranged_idx[$c] = [ $begin .. $end ];
                $begin = $end + 1;
                $end = $begin + $rows - 1;
            }
            for my $r ( 0 .. $rows - 1 ) {
                my @temp_idx;
                for my $c ( 0 .. $cols_per_row - 1 ) {
                    next if $r == $rows - 1 && $self->{rest} && $c >= $self->{rest};
                    push @temp_idx, $rearranged_idx[$c][$r];
                }
                push @{$self->{rc2idx}}, \@temp_idx;
            }
        }
        else {
            my $begin = 0;
            my $end = $cols_per_row - 1;
            $end = $#{$self->{list}} if $end > $#{$self->{list}};
            push @{$self->{rc2idx}}, [ $begin .. $end ];
            while ( $end < $#{$self->{list}} ) {
                $begin += $cols_per_row;
                $end   += $cols_per_row;
                $end    = $#{$self->{list}} if $end > $#{$self->{list}};
                push @{$self->{rc2idx}}, [ $begin .. $end ];
            }
        }
    }
}


sub __unicode_trim {
    my ( $self, $gcs, $len ) = @_;
    return '' if $len <= 0; #
    return ta_mbtrunc( $gcs, $len - 1 );
}


sub __wr_cell {
    my( $self, $row, $col ) = @_;
    if ( $#{$self->{rc2idx}} == 0 ) {
        my $lngth = 0;
        if ( $col > 0 ) {
            for my $cl ( 0 .. $col - 1 ) {

                #my $gcs_element = Unicode::GCString->new( $self->{list}[$self->{rc2idx}[$row][$cl]] );
                my $gcs_element = Unicode::GCString->new( _strip_ansi_color( $self->{list}[$self->{rc2idx}[$row][$cl]] ) );

                $lngth += $gcs_element->columns();
                $lngth += $self->{pad_one_row};
            }
        }
        $self->Term::Choose::__goto( $row - $self->{row_on_top}, $lngth );
        $self->{plugin}->__bold_underline() if $self->{marked}[$row][$col];
        $self->{plugin}->__reverse()        if $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
        print $self->{list}[$self->{rc2idx}[$row][$col]];

        #my $gcs_element = Unicode::GCString->new( $self->{list}[$self->{rc2idx}[$row][$col]] );
        my $gcs_element = Unicode::GCString->new( _strip_ansi_color( $self->{list}[$self->{rc2idx}[$row][$col]] ) );

        $self->{i_col} += $gcs_element->columns();
    }
    else {
        $self->Term::Choose::__goto( $row - $self->{row_on_top}, $col * $self->{col_width} );
        $self->{plugin}->__bold_underline() if $self->{marked}[$row][$col];
        $self->{plugin}->__reverse()        if $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
        print $self->__unicode_sprintf( $self->{rc2idx}[$row][$col] );
        $self->{i_col} += $self->{length_longest};
    }
    $self->{plugin}->__reset() if $self->{marked}[$row][$col] || $row == $self->{pos}[ROW] && $col == $self->{pos}[COL];
}



sub __unicode_sprintf {
    my ( $self, $idx ) = @_;
    my $unicode;
    my $str_length = defined $self->{length}[$idx] ? $self->{length}[$idx] : $self->{length_longest};
    if ( $str_length > $self->{avail_col_width} ) {
        my $gcs = Unicode::GCString->new( $self->{list}[$idx] );
        $unicode = $self->__unicode_trim( $gcs, $self->{avail_col_width} );
    }
    elsif ( $str_length < $self->{avail_col_width} ) {
        if ( $self->{justify} == 0 ) {
            $unicode = $self->{list}[$idx] . " " x ( $self->{avail_col_width} - $str_length );
        }
        elsif ( $self->{justify} == 1 ) {
            $unicode = " " x ( $self->{avail_col_width} - $str_length ) . $self->{list}[$idx];
        }
        elsif ( $self->{justify} == 2 ) {
            my $all = $self->{avail_col_width} - $str_length;
            my $half = int( $all / 2 );
            $unicode = " " x $half . $self->{list}[$idx] . " " x ( $all - $half );
        }
    }
    else {
        $unicode = $self->{list}[$idx];
    }
    return $unicode;
}


sub __mouse_info_to_key {
    my ( $self, $abs_cursor_y, $button, $abs_mouse_x, $abs_mouse_y ) = @_;
    if ( $button == 4 ) {
        return VK_PAGE_UP;
    }
    elsif ( $button == 5 ) {
        return VK_PAGE_DOWN;
    }
    my $abs_y_top_row = $abs_cursor_y - $self->{cursor_row};
    return NEXT_get_key if $abs_mouse_y < $abs_y_top_row;
    my $mouse_row = $abs_mouse_y - $abs_y_top_row;
    my $mouse_col = $abs_mouse_x;
    my( $found_row, $found_col );
    my $found = 0;
    if ( $#{$self->{rc2idx}} == 0 ) {
        my $row = 0;
        if ( $row == $mouse_row ) {
            my $end_last_col = 0;
            COL: for my $col ( 0 .. $#{$self->{rc2idx}[$row]} ) {

                #my $gcs_element = Unicode::GCString->new( $self->{list}[$self->{rc2idx}[$row][$col]] );
                my $gcs_element = Unicode::GCString->new( _strip_ansi_color( $self->{list}[$self->{rc2idx}[$row][$col]] ) );

                my $end_this_col = $end_last_col + $gcs_element->columns() + $self->{pad_one_row};
                if ( $col == 0 ) {
                    $end_this_col -= int( $self->{pad_one_row} / 2 );
                }
                if ( $col == $#{$self->{rc2idx}[$row]} ) {
                    $end_this_col = $self->{avail_width} if $end_this_col > $self->{avail_width};
                }
                if ( $end_last_col < $mouse_col && $end_this_col >= $mouse_col ) {
                    $found = 1;
                    $found_row = $row + $self->{row_on_top};
                    $found_col = $col;
                    last;
                }
                $end_last_col = $end_this_col;
            }
        }
    }
    else {
        ROW: for my $row ( 0 .. $#{$self->{rc2idx}} ) {
            if ( $row == $mouse_row ) {
                my $end_last_col = 0;
                COL: for my $col ( 0 .. $#{$self->{rc2idx}[$row]} ) {
                    my $end_this_col = $end_last_col + $self->{col_width};
                    if ( $col == 0 ) {
                        $end_this_col -= int( $self->{pad} / 2 );
                    }
                    if ( $col == $#{$self->{rc2idx}[$row]} ) {
                        $end_this_col = $self->{avail_width} if $end_this_col > $self->{avail_width};
                    }
                    if ( $end_last_col < $mouse_col && $end_this_col >= $mouse_col ) {
                        $found = 1;
                        $found_row = $row + $self->{row_on_top};
                        $found_col = $col;
                        last ROW;
                    }
                    $end_last_col = $end_this_col;
                }
            }
        }
    }
    return NEXT_get_key if ! $found;
    my $return_char = '';
    if ( $button == 1 ) {
        $return_char = KEY_ENTER;
    }
    elsif ( $button == 3 ) {
        $return_char = KEY_SPACE;
    }
    else {
        return NEXT_get_key;
    }
    if ( $found_row != $self->{pos}[ROW] || $found_col != $self->{pos}[COL] ) {
        my $tmp = $self->{pos};
        $self->{pos} = [ $found_row, $found_col ];
        $self->__wr_cell( $tmp->[0], $tmp->[1] );
        $self->__wr_cell( $self->{pos}[ROW], $self->{pos}[COL] );
    }
    return $return_char;
}


sub _strip_ansi_color {
    my ( $str ) = @_;
    #return $str =~ s{ \e\[ [\d;]* m }{}xmsgr; # r requires 5.012
    ( my $s = $str ) =~ s/\e\[[\d;]*m//msg;
    return $s;
}


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose_HAE - Choose items from a list interactively.

=head1 VERSION

Version 0.001

=cut

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::Choose

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012-2015 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
