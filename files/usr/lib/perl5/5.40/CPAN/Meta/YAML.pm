use 5.008001; # sane UTF-8 support
use strict;
use warnings;
package CPAN::Meta::YAML; # git description: v1.68-2-gcc5324e
$CPAN::Meta::YAML::VERSION = '0.018';
; # original $VERSION removed by Doppelgaenger


use Exporter;
our @ISA       = qw{ Exporter  };
our @EXPORT    = qw{ Load Dump };
our @EXPORT_OK = qw{ LoadFile DumpFile freeze thaw };


sub Dump {
    return CPAN::Meta::YAML->new(@_)->_dump_string;
}

sub Load {
    my $self = CPAN::Meta::YAML->_load_string(@_);
    if ( wantarray ) {
        return @$self;
    } else {
        # To match YAML.pm, return the last document
        return $self->[-1];
    }
}

BEGIN {
    *freeze = \&Dump;
    *thaw   = \&Load;
}

sub DumpFile {
    my $file = shift;
    return CPAN::Meta::YAML->new(@_)->_dump_file($file);
}

sub LoadFile {
    my $file = shift;
    my $self = CPAN::Meta::YAML->_load_file($file);
    if ( wantarray ) {
        return @$self;
    } else {
        # Return only the last document to match YAML.pm,
        return $self->[-1];
    }
}



sub new {
    my $class = shift;
    bless [ @_ ], $class;
}


sub read_string {
    my $self = shift;
    $self->_load_string(@_);
}

sub write_string {
    my $self = shift;
    $self->_dump_string(@_);
}

sub read {
    my $self = shift;
    $self->_load_file(@_);
}

sub write {
    my $self = shift;
    $self->_dump_file(@_);
}





my @UNPRINTABLE = qw(
    0    x01  x02  x03  x04  x05  x06  a
    b    t    n    v    f    r    x0E  x0F
    x10  x11  x12  x13  x14  x15  x16  x17
    x18  x19  x1A  e    x1C  x1D  x1E  x1F
);

my %UNESCAPES = (
    0 => "\x00", z => "\x00", N    => "\x85",
    a => "\x07", b => "\x08", t    => "\x09",
    n => "\x0a", v => "\x0b", f    => "\x0c",
    r => "\x0d", e => "\x1b", '\\' => '\\',
);


my %QUOTE = map { $_ => 1 } qw{
    null true false
};

my $re_capture_double_quoted = qr/\"([^\\"]*(?:\\.[^\\"]*)*)\"/;
my $re_capture_single_quoted = qr/\'([^\']*(?:\'\'[^\']*)*)\'/;
my $re_capture_unquoted_key  = qr/([^:]+(?::+\S(?:[^:]*|.*?(?=:)))*)(?=\s*\:(?:\s+|$))/;
my $re_trailing_comment      = qr/(?:\s+\#.*)?/;
my $re_key_value_separator   = qr/\s*:(?:\s+(?:\#.*)?|$)/;








sub _load_file {
    my $class = ref $_[0] ? ref shift : shift;

    # Check the file
    my $file = shift or $class->_error( 'You did not specify a file name' );
    $class->_error( "File '$file' does not exist" )
        unless -e $file;
    $class->_error( "'$file' is a directory, not a file" )
        unless -f _;
    $class->_error( "Insufficient permissions to read '$file'" )
        unless -r _;

    # Open unbuffered with strict UTF-8 decoding and no translation layers
    open( my $fh, "<:unix:encoding(UTF-8)", $file );
    unless ( $fh ) {
        $class->_error("Failed to open file '$file': $!");
    }

    # flock if available (or warn if not possible for OS-specific reasons)
    if ( _can_flock() ) {
        flock( $fh, Fcntl::LOCK_SH() )
            or warn "Couldn't lock '$file' for reading: $!";
    }

    # slurp the contents
    my $contents = eval {
        use warnings FATAL => 'utf8';
        local $/;
        <$fh>
    };
    if ( my $err = $@ ) {
        $class->_error("Error reading from file '$file': $err");
    }

    # close the file (release the lock)
    unless ( close $fh ) {
        $class->_error("Failed to close file '$file': $!");
    }

    $class->_load_string( $contents );
}

sub _load_string {
    my $class  = ref $_[0] ? ref shift : shift;
    my $self   = bless [], $class;
    my $string = $_[0];
    eval {
        unless ( defined $string ) {
            die \"Did not provide a string to load";
        }

        # Check if Perl has it marked as characters, but it's internally
        # inconsistent.  E.g. maybe latin1 got read on a :utf8 layer
        if ( utf8::is_utf8($string) && ! utf8::valid($string) ) {
            die \<<'...';
Read an invalid UTF-8 string (maybe mixed UTF-8 and 8-bit character set).
Did you decode with lax ":utf8" instead of strict ":encoding(UTF-8)"?
...
        }

        # Ensure Unicode character semantics, even for 0x80-0xff
        utf8::upgrade($string);

        # Check for and strip any leading UTF-8 BOM
        $string =~ s/^\x{FEFF}//;

        # Check for some special cases
        return $self unless length $string;

        # Split the file into lines
        my @lines = grep { ! /^\s*(?:\#.*)?\z/ }
                split /(?:\015{1,2}\012|\015|\012)/, $string;

        # Strip the initial YAML header
        @lines and $lines[0] =~ /^\%YAML[: ][\d\.]+.*\z/ and shift @lines;

        # A nibbling parser
        my $in_document = 0;
        while ( @lines ) {
            # Do we have a document header?
            if ( $lines[0] =~ /^---\s*(?:(.+)\s*)?\z/ ) {
                # Handle scalar documents
                shift @lines;
                if ( defined $1 and $1 !~ /^(?:\#.+|\%YAML[: ][\d\.]+)\z/ ) {
                    push @$self,
                        $self->_load_scalar( "$1", [ undef ], \@lines );
                    next;
                }
                $in_document = 1;
            }

            if ( ! @lines or $lines[0] =~ /^(?:---|\.\.\.)/ ) {
                # A naked document
                push @$self, undef;
                while ( @lines and $lines[0] !~ /^---/ ) {
                    shift @lines;
                }
                $in_document = 0;

            # XXX The final '-+$' is to look for -- which ends up being an
            # error later.
            } elsif ( ! $in_document && @$self ) {
                # only the first document can be explicit
                die \"CPAN::Meta::YAML failed to classify the line '$lines[0]'";
            } elsif ( $lines[0] =~ /^\s*\-(?:\s|$|-+$)/ ) {
                # An array at the root
                my $document = [ ];
                push @$self, $document;
                $self->_load_array( $document, [ 0 ], \@lines );

            } elsif ( $lines[0] =~ /^(\s*)\S/ ) {
                # A hash at the root
                my $document = { };
                push @$self, $document;
                $self->_load_hash( $document, [ length($1) ], \@lines );

            } else {
                # Shouldn't get here.  @lines have whitespace-only lines
                # stripped, and previous match is a line with any
                # non-whitespace.  So this clause should only be reachable via
                # a perlbug where \s is not symmetric with \S

                # uncoverable statement
                die \"CPAN::Meta::YAML failed to classify the line '$lines[0]'";
            }
        }
    };
    my $err = $@;
    if ( ref $err eq 'SCALAR' ) {
        $self->_error(${$err});
    } elsif ( $err ) {
        $self->_error($err);
    }

    return $self;
}

sub _unquote_single {
    my ($self, $string) = @_;
    return '' unless length $string;
    $string =~ s/\'\'/\'/g;
    return $string;
}

sub _unquote_double {
    my ($self, $string) = @_;
    return '' unless length $string;
    $string =~ s/\\"/"/g;
    $string =~
        s{\\([Nnever\\fartz0b]|x([0-9a-fA-F]{2}))}
         {(length($1)>1)?pack("H2",$2):$UNESCAPES{$1}}gex;
    return $string;
}

sub _load_scalar {
    my ($self, $string, $indent, $lines) = @_;

    # Trim trailing whitespace
    $string =~ s/\s*\z//;

    # Explitic null/undef
    return undef if $string eq '~';

    # Single quote
    if ( $string =~ /^$re_capture_single_quoted$re_trailing_comment\z/ ) {
        return $self->_unquote_single($1);
    }

    # Double quote.
    if ( $string =~ /^$re_capture_double_quoted$re_trailing_comment\z/ ) {
        return $self->_unquote_double($1);
    }

    # Special cases
    if ( $string =~ /^[\'\"!&]/ ) {
        die \"CPAN::Meta::YAML does not support a feature in line '$string'";
    }
    return {} if $string =~ /^{}(?:\s+\#.*)?\z/;
    return [] if $string =~ /^\[\](?:\s+\#.*)?\z/;

    # Regular unquoted string
    if ( $string !~ /^[>|]/ ) {
        die \"CPAN::Meta::YAML found illegal characters in plain scalar: '$string'"
            if $string =~ /^(?:-(?:\s|$)|[\@\%\`])/ or
                $string =~ /:(?:\s|$)/;
        $string =~ s/\s+#.*\z//;
        return $string;
    }

    # Error
    die \"CPAN::Meta::YAML failed to find multi-line scalar content" unless @$lines;

    # Check the indent depth
    $lines->[0]   =~ /^(\s*)/;
    $indent->[-1] = length("$1");
    if ( defined $indent->[-2] and $indent->[-1] <= $indent->[-2] ) {
        die \"CPAN::Meta::YAML found bad indenting in line '$lines->[0]'";
    }

    # Pull the lines
    my @multiline = ();
    while ( @$lines ) {
        $lines->[0] =~ /^(\s*)/;
        last unless length($1) >= $indent->[-1];
        push @multiline, substr(shift(@$lines), length($1));
    }

    my $j = (substr($string, 0, 1) eq '>') ? ' ' : "\n";
    my $t = (substr($string, 1, 1) eq '-') ? ''  : "\n";
    return join( $j, @multiline ) . $t;
}

sub _load_array {
    my ($self, $array, $indent, $lines) = @_;

    while ( @$lines ) {
        # Check for a new document
        if ( $lines->[0] =~ /^(?:---|\.\.\.)/ ) {
            while ( @$lines and $lines->[0] !~ /^---/ ) {
                shift @$lines;
            }
            return 1;
        }

        # Check the indent level
        $lines->[0] =~ /^(\s*)/;
        if ( length($1) < $indent->[-1] ) {
            return 1;
        } elsif ( length($1) > $indent->[-1] ) {
            die \"CPAN::Meta::YAML found bad indenting in line '$lines->[0]'";
        }

        if ( $lines->[0] =~ /^(\s*\-\s+)[^\'\"]\S*\s*:(?:\s+|$)/ ) {
            # Inline nested hash
            my $indent2 = length("$1");
            $lines->[0] =~ s/-/ /;
            push @$array, { };
            $self->_load_hash( $array->[-1], [ @$indent, $indent2 ], $lines );

        } elsif ( $lines->[0] =~ /^\s*\-\s*\z/ ) {
            shift @$lines;
            unless ( @$lines ) {
                push @$array, undef;
                return 1;
            }
            if ( $lines->[0] =~ /^(\s*)\-/ ) {
                my $indent2 = length("$1");
                if ( $indent->[-1] == $indent2 ) {
                    # Null array entry
                    push @$array, undef;
                } else {
                    # Naked indenter
                    push @$array, [ ];
                    $self->_load_array(
                        $array->[-1], [ @$indent, $indent2 ], $lines
                    );
                }

            } elsif ( $lines->[0] =~ /^(\s*)\S/ ) {
                push @$array, { };
                $self->_load_hash(
                    $array->[-1], [ @$indent, length("$1") ], $lines
                );

            } else {
                die \"CPAN::Meta::YAML failed to classify line '$lines->[0]'";
            }

        } elsif ( $lines->[0] =~ /^\s*\-(\s*)(.+?)\s*\z/ ) {
            # Array entry with a value
            shift @$lines;
            push @$array, $self->_load_scalar(
                "$2", [ @$indent, undef ], $lines
            );

        } elsif ( defined $indent->[-2] and $indent->[-1] == $indent->[-2] ) {
            # This is probably a structure like the following...
            # ---
            # foo:
            # - list
            # bar: value
            #
            # ... so lets return and let the hash parser handle it
            return 1;

        } else {
            die \"CPAN::Meta::YAML failed to classify line '$lines->[0]'";
        }
    }

    return 1;
}

sub _load_hash {
    my ($self, $hash, $indent, $lines) = @_;

    while ( @$lines ) {
        # Check for a new document
        if ( $lines->[0] =~ /^(?:---|\.\.\.)/ ) {
            while ( @$lines and $lines->[0] !~ /^---/ ) {
                shift @$lines;
            }
            return 1;
        }

        # Check the indent level
        $lines->[0] =~ /^(\s*)/;
        if ( length($1) < $indent->[-1] ) {
            return 1;
        } elsif ( length($1) > $indent->[-1] ) {
            die \"CPAN::Meta::YAML found bad indenting in line '$lines->[0]'";
        }

        # Find the key
        my $key;

        # Quoted keys
        if ( $lines->[0] =~
            s/^\s*$re_capture_single_quoted$re_key_value_separator//
        ) {
            $key = $self->_unquote_single($1);
        }
        elsif ( $lines->[0] =~
            s/^\s*$re_capture_double_quoted$re_key_value_separator//
        ) {
            $key = $self->_unquote_double($1);
        }
        elsif ( $lines->[0] =~
            s/^\s*$re_capture_unquoted_key$re_key_value_separator//
        ) {
            $key = $1;
            $key =~ s/\s+$//;
        }
        elsif ( $lines->[0] =~ /^\s*\?/ ) {
            die \"CPAN::Meta::YAML does not support a feature in line '$lines->[0]'";
        }
        else {
            die \"CPAN::Meta::YAML failed to classify line '$lines->[0]'";
        }

        if ( exists $hash->{$key} ) {
            warn "CPAN::Meta::YAML found a duplicate key '$key' in line '$lines->[0]'";
        }

        # Do we have a value?
        if ( length $lines->[0] ) {
            # Yes
            $hash->{$key} = $self->_load_scalar(
                shift(@$lines), [ @$indent, undef ], $lines
            );
        } else {
            # An indent
            shift @$lines;
            unless ( @$lines ) {
                $hash->{$key} = undef;
                return 1;
            }
            if ( $lines->[0] =~ /^(\s*)-/ ) {
                $hash->{$key} = [];
                $self->_load_array(
                    $hash->{$key}, [ @$indent, length($1) ], $lines
                );
            } elsif ( $lines->[0] =~ /^(\s*)./ ) {
                my $indent2 = length("$1");
                if ( $indent->[-1] >= $indent2 ) {
                    # Null hash entry
                    $hash->{$key} = undef;
                } else {
                    $hash->{$key} = {};
                    $self->_load_hash(
                        $hash->{$key}, [ @$indent, length($1) ], $lines
                    );
                }
            }
        }
    }

    return 1;
}



sub _dump_file {
    my $self = shift;

    require Fcntl;

    # Check the file
    my $file = shift or $self->_error( 'You did not specify a file name' );

    my $fh;
    # flock if available (or warn if not possible for OS-specific reasons)
    if ( _can_flock() ) {
        # Open without truncation (truncate comes after lock)
        my $flags = Fcntl::O_WRONLY()|Fcntl::O_CREAT();
        sysopen( $fh, $file, $flags );
        unless ( $fh ) {
            $self->_error("Failed to open file '$file' for writing: $!");
        }

        # Use no translation and strict UTF-8
        binmode( $fh, ":raw:encoding(UTF-8)");

        flock( $fh, Fcntl::LOCK_EX() )
            or warn "Couldn't lock '$file' for reading: $!";

        # truncate and spew contents
        truncate $fh, 0;
        seek $fh, 0, 0;
    }
    else {
        open $fh, ">:unix:encoding(UTF-8)", $file;
    }

    # serialize and spew to the handle
    print {$fh} $self->_dump_string;

    # close the file (release the lock)
    unless ( close $fh ) {
        $self->_error("Failed to close file '$file': $!");
    }

    return 1;
}

sub _dump_string {
    my $self = shift;
    return '' unless ref $self && @$self;

    # Iterate over the documents
    my $indent = 0;
    my @lines  = ();

    eval {
        foreach my $cursor ( @$self ) {
            push @lines, '---';

            # An empty document
            if ( ! defined $cursor ) {
                # Do nothing

            # A scalar document
            } elsif ( ! ref $cursor ) {
                $lines[-1] .= ' ' . $self->_dump_scalar( $cursor );

            # A list at the root
            } elsif ( ref $cursor eq 'ARRAY' ) {
                unless ( @$cursor ) {
                    $lines[-1] .= ' []';
                    next;
                }
                push @lines, $self->_dump_array( $cursor, $indent, {} );

            # A hash at the root
            } elsif ( ref $cursor eq 'HASH' ) {
                unless ( %$cursor ) {
                    $lines[-1] .= ' {}';
                    next;
                }
                push @lines, $self->_dump_hash( $cursor, $indent, {} );

            } else {
                die \("Cannot serialize " . ref($cursor));
            }
        }
    };
    if ( ref $@ eq 'SCALAR' ) {
        $self->_error(${$@});
    } elsif ( $@ ) {
        $self->_error($@);
    }

    join '', map { "$_\n" } @lines;
}

sub _has_internal_string_value {
    my $value = shift;
    my $b_obj = B::svref_2object(\$value);  # for round trip problem
    return $b_obj->FLAGS & B::SVf_POK();
}

sub _dump_scalar {
    my $string = $_[1];
    my $is_key = $_[2];
    # Check this before checking length or it winds up looking like a string!
    my $has_string_flag = _has_internal_string_value($string);
    return '~'  unless defined $string;
    return "''" unless length  $string;
    if (Scalar::Util::looks_like_number($string)) {
        # keys and values that have been used as strings get quoted
        if ( $is_key || $has_string_flag ) {
            return qq['$string'];
        }
        else {
            return $string;
        }
    }
    if ( $string =~ /[\x00-\x09\x0b-\x0d\x0e-\x1f\x7f-\x9f\'\n]/ ) {
        $string =~ s/\\/\\\\/g;
        $string =~ s/"/\\"/g;
        $string =~ s/\n/\\n/g;
        $string =~ s/[\x85]/\\N/g;
        $string =~ s/([\x00-\x1f])/\\$UNPRINTABLE[ord($1)]/g;
        $string =~ s/([\x7f-\x9f])/'\x' . sprintf("%X",ord($1))/ge;
        return qq|"$string"|;
    }
    if ( $string =~ /(?:^[~!@#%&*|>?:,'"`{}\[\]]|^-+$|\s|:\z)/ or
        $QUOTE{$string}
    ) {
        return "'$string'";
    }
    return $string;
}

sub _dump_array {
    my ($self, $array, $indent, $seen) = @_;
    if ( $seen->{refaddr($array)}++ ) {
        die \"CPAN::Meta::YAML does not support circular references";
    }
    my @lines  = ();
    foreach my $el ( @$array ) {
        my $line = ('  ' x $indent) . '-';
        my $type = ref $el;
        if ( ! $type ) {
            $line .= ' ' . $self->_dump_scalar( $el );
            push @lines, $line;

        } elsif ( $type eq 'ARRAY' ) {
            if ( @$el ) {
                push @lines, $line;
                push @lines, $self->_dump_array( $el, $indent + 1, $seen );
            } else {
                $line .= ' []';
                push @lines, $line;
            }

        } elsif ( $type eq 'HASH' ) {
            if ( keys %$el ) {
                push @lines, $line;
                push @lines, $self->_dump_hash( $el, $indent + 1, $seen );
            } else {
                $line .= ' {}';
                push @lines, $line;
            }

        } else {
            die \"CPAN::Meta::YAML does not support $type references";
        }
    }

    @lines;
}

sub _dump_hash {
    my ($self, $hash, $indent, $seen) = @_;
    if ( $seen->{refaddr($hash)}++ ) {
        die \"CPAN::Meta::YAML does not support circular references";
    }
    my @lines  = ();
    foreach my $name ( sort keys %$hash ) {
        my $el   = $hash->{$name};
        my $line = ('  ' x $indent) . $self->_dump_scalar($name, 1) . ":";
        my $type = ref $el;
        if ( ! $type ) {
            $line .= ' ' . $self->_dump_scalar( $el );
            push @lines, $line;

        } elsif ( $type eq 'ARRAY' ) {
            if ( @$el ) {
                push @lines, $line;
                push @lines, $self->_dump_array( $el, $indent + 1, $seen );
            } else {
                $line .= ' []';
                push @lines, $line;
            }

        } elsif ( $type eq 'HASH' ) {
            if ( keys %$el ) {
                push @lines, $line;
                push @lines, $self->_dump_hash( $el, $indent + 1, $seen );
            } else {
                $line .= ' {}';
                push @lines, $line;
            }

        } else {
            die \"CPAN::Meta::YAML does not support $type references";
        }
    }

    @lines;
}




our $errstr    = '';

sub _error {
    require Carp;
    $errstr = $_[1];
    $errstr =~ s/ at \S+ line \d+.*//;
    Carp::croak( $errstr );
}

my $errstr_warned;
sub errstr {
    require Carp;
    Carp::carp( "CPAN::Meta::YAML->errstr and \$CPAN::Meta::YAML::errstr is deprecated" )
        unless $errstr_warned++;
    $errstr;
}






use B;

my $HAS_FLOCK;
sub _can_flock {
    if ( defined $HAS_FLOCK ) {
        return $HAS_FLOCK;
    }
    else {
        require Config;
        my $c = \%Config::Config;
        $HAS_FLOCK = grep { $c->{$_} } qw/d_flock d_fcntl_can_lock d_lockf/;
        require Fcntl if $HAS_FLOCK;
        return $HAS_FLOCK;
    }
}



use Scalar::Util ();
BEGIN {
    local $@;
    if ( eval { Scalar::Util->VERSION(1.18); } ) {
        *refaddr = *Scalar::Util::refaddr;
    }
    else {
        eval <<'END_PERL';
sub refaddr {
    my $pkg = ref($_[0]) or return undef;
    if ( !! UNIVERSAL::can($_[0], 'can') ) {
        bless $_[0], 'Scalar::Util::Fake';
    } else {
        $pkg = undef;
    }
    "$_[0]" =~ /0x(\w+)/;
    my $i = do { no warnings 'portable'; hex $1 };
    bless $_[0], $pkg if defined $pkg;
    $i;
}
END_PERL
    }
}

delete $CPAN::Meta::YAML::{refaddr};

1;



__END__




